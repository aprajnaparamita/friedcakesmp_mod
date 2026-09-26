-- FriedcakeSMP — smp_orders / routing.lua
-- Order creation with the automatic auction sweep (f04 §6.1), the
-- routing-in API other features call (f02 /sell, f03 auction, f07 Sell
-- all), cancellation and collection.
--
-- Cross-mod contracts implemented here (documented in the callers'
-- specs — f02 §6, f03 §6.1):
--   smp_orders.best_open_order(key)                  -> order | nil   [f03]
--   smp_orders.fill_from_stack(order, player, stack) -> result | nil  [f03]
--       SUCCESS is a TABLE: { accepted, payout, remaining = 0 }.
--       REFUSAL is `nil, reason_string`.
--       Test `type(r) == 'table'` — NEVER `r ~= false` (nil passes) and
--       never pcall's success flag (it only says the call did not raise).
--       Both mistakes deleted items on refusal: f03 AH-1, f06 AX-1
--       (S04/OR-2).
--   smp_orders.can_take_stack(order, name, stack)    -> bool, reason  [f03]
--       The predicate form of the exact same check: `true` when
--       fill_from_stack would take the stack, `false, reason_string`
--       when it would refuse. Call it BEFORE fill_from_stack to skip
--       orders that cannot take the stack (the reason string is the one
--       fill_from_stack would have returned).
--   smp_orders.open_orders_above(key, unit, [seller])-> {orders}      [f02]
--   smp_orders.absorb_from_sell(o, player, key, n)   -> n, cents      [f02]
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_orders.S
local cfg = smp_orders.cfg
local display = smp_orders.display

----------------------------------------------------------------------
-- Small shared helpers
----------------------------------------------------------------------

-- Accept an M0 or M1 key and normalise to the M1 key orders are stored
-- under. f02's /sell routing groups by M0; a plain stack's M1 key is
-- "m1|<name>||0" (empty enchantment string, empty meta hash).
local function to_m1(key)
	local parsed = smp_items.parse_key(key)
	if not parsed then return nil end
	if parsed.level == "M1" then return key end
	if parsed.level == "M0" then return "m1|" .. parsed.name .. "||0" end
	return nil
end
smp_orders.to_m1 = to_m1

function smp_orders.apply_delivery(o, supplier_name, accepted)
	o.delivered = o.delivered + accepted
	o.version = o.version + 1
	o.suppliers[supplier_name] = (o.suppliers[supplier_name] or 0) + accepted
	if o.delivered >= o.qty then o.state = "filled" end
	smp_orders.save_one(o)   -- S04/OR-1: written through with the payout
end

----------------------------------------------------------------------
-- Notifications (f04 §4.13: respect eco.order_alerts — f12)
----------------------------------------------------------------------

function smp_orders.alerts_on(name)
	if smp_settings and type(smp_settings.get) == "function" then
		local ok, v = pcall(smp_settings.get, name, "eco.order_alerts")
		if ok and v ~= nil then return v and true or false end
	end
	return true -- f12 leaves eco.order_alerts unregistered until its category opens;
	             -- nil -> default on is correct and must be kept.
end

function smp_orders.notify_buyer(o, msg)
	local p = core.get_player_by_name and core.get_player_by_name(o.buyer)
	if p and smp_orders.alerts_on(o.buyer) then
		core.chat_send_player(o.buyer, msg)
	end
end

----------------------------------------------------------------------
-- Creation (f04 §6.1)
----------------------------------------------------------------------

smp_orders._last_create = {}

-- create(player_or_name, m1_key, qty, unit_price) -> id | nil, message
function smp_orders.create(player, key, qty, unit_price)
	local name = smp_orders.player_name(player)
	if not name then return nil, S("This order has changed") end

	-- 1. Validate everything up front (shared §2.3)
	qty = math.floor(tonumber(qty) or 0)
	unit_price = math.floor(tonumber(unit_price) or 0)
	if qty < 1 then
		return nil, S("Invalid amount: @1", "qty < 1")
	end
	if unit_price < cfg.min_price then
		return nil, S("Price below minimum (@1)", display.money(cfg.min_price))
	end
	local total = unit_price * qty
	if total > 1e15 then
		return nil, S("Total too large")
	end
	local now = (core.get_gametime and core.get_gametime()) or os.time()
	local last = smp_orders._last_create[name]
	if last and (now - last) < cfg.create_interval then
		return nil, S("Too fast, slow down") -- R9 rate limit (PROPOSED string)
	end
	if not smp_orders.can_create(name) then
		return nil, S("You reached order limits") -- house sibling of "You reached home limits" [F0055]
	end
	if smp_orders.blacklisted(key) then
		return nil, S("This item cannot be ordered")
	end
	local parsed = smp_items.parse_key(key)
	if not parsed or parsed.level ~= "M1" then
		return nil, S("This item cannot be ordered")
	end
	local rec = smp_store.api.ensure_player(name)
	if (rec.money or 0) < total then
		return nil, S("Insufficient funds")
	end

	-- 2. Mutate — no yields from here (shared §2.3)
	smp_orders._last_create[name] = now
	-- S04/OR-1: reserve the id, take the escrow, THEN write the record.
	-- The order matters: money writes through immediately, so the record
	-- must not become durable before the escrow has actually been taken —
	-- that would leave a funded-less open order that anyone can fill and
	-- be paid from (minted money). A crash inside the gap instead costs
	-- the buyer the escrow (bounded loss), which is the safe direction.
	local id = smp_orders.reserve_id()
	local taken = smp_orders.escrow.deposit(name, total, id)
	if not taken then
		-- Cannot happen without yields (the balance was checked above)
		-- and nothing has been written yet — nothing to roll back (R2).
		return nil, S("Insufficient funds")
	end
	smp_orders.insert_order({
		id = id,
		buyer = name,
		key = key,
		template = parsed.name,
		ench = parsed.ench,
		qty = qty,
		delivered = 0,
		collected = 0,
		unit_price = unit_price,
		escrow = total,                 -- unit_price × qty committed [F0204]
		state = "open",
		version = 1,
		created = os.time(),
		expires = os.time() + cfg.duration,
		suppliers = {},
	})

	-- 3. Sweep the auction house: buy matching listings at or below the
	--    unit price, cheapest first, until filled [S2][S6].
	smp_orders.sweep_auction(id)
	return id
end

----------------------------------------------------------------------
-- Auction sweep (f04 §4.5, §6.1) — degrades when smp_ah is absent
----------------------------------------------------------------------

-- Absorb a whole auction listing `l` into order `o`. f03's
-- consume_listing closes the ENTIRE listing, so only listings whose
-- count fits within the order's remaining quantity can be absorbed
-- (a listing larger than the remainder is skipped — PROPOSED; the
-- reference behaviour for a too-large listing is unobserved).
-- The seller receives THEIR OWN listing price (§4.5); unused escrow
-- stays with the order.
-- S04/OR-3: the price paid is `l.price`, not floor(l.price/count)×count —
-- the old form silently dropped up to count−1 cents (a listing of 3 for
-- 1000 paid 999). The at-or-below check stays on the UNIT price: the
-- listing's own implied unit price must not exceed what the order pays,
-- and the total must fit the escrow (R2).
function smp_orders.absorb_listing(o, l)
	if not o or o.state ~= "open" then return false end
	local count = math.floor(tonumber(l.count) or 0)
	if count <= 0 then
		local stack = ItemStack(l.stack)
		count = stack:get_count()
	end
	if count <= 0 or count > smp_orders.remaining(o) then return false end
	local price = math.floor(tonumber(l.price) or 0)
	local listed_unit = math.floor(tonumber(l.unit_price) or 0)
	if price <= 0 then
		-- Degenerate record with no total: fall back to unit × count so
		-- the old behaviour survives for callers that only send a unit.
		if listed_unit <= 0 then return false end
		price = listed_unit * count
	end
	-- Unit-price check, on the price the listing actually asks for.
	local unit = math.floor(price / count)
	if unit > o.unit_price then return false end
	if price > o.escrow then
		-- Cannot happen for listings at-or-below the order price; never
		-- pay beyond escrow (R2).
		return false
	end
	-- Remove the source first: f03 must acknowledge the listing change
	-- before money moves. When smp_ah is absent the bridge degrades and
	-- returns false, so nothing happens.
	if not smp_orders.au.consume_listing(l.id, o.buyer, price) then return false end

	local paid = smp_orders.escrow.payout(o, l.seller, price)
	smp_orders.apply_delivery(o, l.seller, count)
	smp_orders.notify_buyer(o, S("@1 delivered @2 @3 to your order",
		l.seller, display.qty(count), display.order_name(o)))
	core.log("action", string.format(
		"[smp_orders] order %d absorbed listing %s (%d at %d, paid %d to %s)",
		o.id, tostring(l.id), count, unit, paid, tostring(l.seller)))
	return true
end

function smp_orders.sweep_auction(order_id)
	local o = smp_orders.get_order(order_id)
	if not o or o.state ~= "open" then return 0 end
	local listings = smp_orders.au.listings_at_or_below(o.key, o.unit_price)
	local absorbed = 0
	for _, l in ipairs(listings or {}) do
		o = smp_orders.get_order(order_id)
		if not o or o.state ~= "open" or smp_orders.remaining(o) <= 0 then
			break
		end
		local before = o.delivered
		if smp_orders.absorb_listing(o, l) then
			absorbed = absorbed + (o.delivered - before)
		end
	end
	return absorbed
end

----------------------------------------------------------------------
-- Routing-in API for f03 (auction listing path)
----------------------------------------------------------------------

-- Best (highest-paying) open order for `key` with remaining capacity.
-- Called by smp_ah.create_listing (f03 §6.1).
function smp_orders.best_open_order(key)
	local m1 = to_m1(key) or key
	local best
	for _, o in ipairs(smp_orders.open_orders_for_key(m1)) do
		if smp_orders.remaining(o) > 0 and
		   (not best or o.unit_price > best.unit_price) then
			best = o
		end
	end
	return best
end

-- Fill an order directly from a stack a player was about to list (f03
-- §6.1: "seller paid order price"). f03's create_listing treats a
-- non-error return as "routed" and discards the stack, so this function
-- consumes the WHOLE stack or refuses — never a partial consumption
-- (the leftover would be lost, X1). The seller is paid the order unit
-- price from escrow.
--
-- RETURN CONTRACT (S04/OR-2 — see the header): a TABLE on success,
-- `nil, reason_string` on refusal. Test `type(r) == 'table'`.
--
-- The validation below is the same check as can_take_stack; keep the
-- two in step by calling it (they can never drift apart).
function smp_orders.fill_from_stack(order, player, stack)
	local o = (type(order) == "table") and order or smp_orders.get_order(order)
	local name = smp_orders.player_name(player)
	local can, why = smp_orders.can_take_stack(o, name, stack)
	if not can then return nil, why end

	-- No yields from here (shared §2.3)
	local take = stack:get_count()
	local payout = take * o.unit_price
	local applied = smp_orders.escrow.payout(o, name, payout)
	stack:take_item(take)
	smp_orders.apply_delivery(o, name, take)
	smp_orders.notify_buyer(o, S("@1 delivered @2 @3 to your order",
		name, display.qty(take), display.order_name(o)))
	return { accepted = take, payout = applied, remaining = 0 }
end

-- Predicate form of fill_from_stack's validation (S04/OR-2).
--   -> true                     the stack would be taken
--   -> false, reason_string     it would be refused (the SAME reason
--                               fill_from_stack returns)
-- Pure read: never consumes the stack, never mutates the order, never
-- yields, so callers may use it before deciding whether to route.
-- `order` may be a record or an id; `name` a name or a PlayerRef.
function smp_orders.can_take_stack(order, name, stack)
	local o = (type(order) == "table") and order or smp_orders.get_order(order)
	local pname = smp_orders.player_name(name)
	if not o or o.state ~= "open" or not pname then
		return false, S("This order has changed")
	end
	if o.buyer == pname and not cfg.allow_self_delivery then
		return false, S("You cannot deliver to your own order")
	end
	-- An ItemStack is a userdata in the engine and a table in the
	-- dev-test harness; anything else cannot match.
	if (type(stack) ~= "table" and type(stack) ~= "userdata")
	   or not smp_items.matches(stack, o.key, "M1") then
		return false, S("Nothing matched this order")
	end
	local take = stack:get_count()
	if take <= 0 then
		return false, S("This order has changed")
	end
	if take > smp_orders.remaining(o) then
		-- Whole-stack or nothing (see fill_from_stack). f03 lists the
		-- stack normally instead. Raw token, not translated: callers
		-- (f03, f06) match on it.
		return false, "full"
	end
	return true
end

----------------------------------------------------------------------
-- Routing-in API for f02 (/sell, spawner "Sell all")
----------------------------------------------------------------------

-- Open orders paying MORE than `unit_price` for `key`, best payer first
-- (f02 §6: descending unit price). `seller_name` is optional; when given
-- (and self-delivery is off) the seller's own orders are skipped.
function smp_orders.open_orders_above(key, unit_price, seller_name)
	local m1 = to_m1(key)
	if not m1 then return {} end
	local out = {}
	for _, o in ipairs(smp_orders.open_orders_for_key(m1)) do
		if o.unit_price > unit_price and smp_orders.remaining(o) > 0 then
			if not (seller_name and o.buyer == seller_name
			        and not cfg.allow_self_delivery) then
				out[#out + 1] = o
			end
		end
	end
	table.sort(out, function(a, b)
		if a.unit_price ~= b.unit_price then return a.unit_price > b.unit_price end
		return a.id < b.id
	end)
	return out
end

-- Absorb n virtual items from a /sell routing (f02 §6). The sell flow has
-- already committed the player's items; this pays the player the ORDER's
-- unit price from escrow. Returns accepted_count, cents_paid.
function smp_orders.absorb_from_sell(o, player, key, n)
	local order = (type(o) == "table") and o or smp_orders.get_order(o)
	local name = smp_orders.player_name(player)
	if not order or order.state ~= "open" or not name then return 0, 0 end
	if order.key ~= to_m1(key) then return 0, 0 end
	if order.buyer == name and not cfg.allow_self_delivery then return 0, 0 end
	local take = math.min(math.floor(tonumber(n) or 0), smp_orders.remaining(order))
	if take <= 0 then return 0, 0 end

	-- No yields from here (shared §2.3)
	local applied = smp_orders.escrow.payout(order, name, take * order.unit_price)
	smp_orders.apply_delivery(order, name, take)
	smp_orders.notify_buyer(order, S("@1 delivered @2 @3 to your order",
		name, display.qty(take), display.order_name(order)))
	return take, applied
end

----------------------------------------------------------------------
-- Collection (f04 §4.9 — virtual counts become stacks ONLY here, T12)
----------------------------------------------------------------------

function smp_orders.collect(order, player)
	local o = (type(order) == "table") and order or smp_orders.get_order(order)
	local name = smp_orders.player_name(player)
	if not o or not name then return nil, S("This order has changed") end
	if o.buyer ~= name then
		return nil, S("Only the buyer can collect this order")
	end
	local avail = o.delivered - o.collected
	if avail <= 0 then return nil, S("No items to collect") end

	local template = smp_items.stack_from_key(o.key)
	if not template then return nil, S("This item cannot be ordered") end
	local inv = player.get_inventory and player:get_inventory()
	if not inv then return nil, S("No items to collect") end

	local stack_max = math.max(1, template.get_stack_max and template:get_stack_max() or 64)
	local taken = 0
	-- Bounded by inventory room: at most a few dozen add_item calls.
	while taken < avail do
		local batch = math.min(stack_max, avail - taken)
		local s = ItemStack(template)
		s:set_count(batch)
		if inv:room_for_item("main", s) then
			inv:add_item("main", s)
			taken = taken + batch
		else
			break
		end
	end
	if taken == 0 then return nil, S("No inventory space") end

	-- No yields between the adds and the record update
	o.collected = o.collected + taken
	o.version = o.version + 1
	smp_orders.save_one(o)   -- S04/OR-1: materialised items must be durable
	                         -- before the next restart, or collect() repeats
	return taken
end

----------------------------------------------------------------------
-- Cancellation (f04 §4.10, T14: refund unspent escrow exactly;
-- delivered items stay collectible)
----------------------------------------------------------------------

function smp_orders.cancel(order, player_or_name, by_admin)
	local o = (type(order) == "table") and order or smp_orders.get_order(order)
	local name = smp_orders.player_name(player_or_name)
	if not o then return nil, S("This order has changed") end
	if not by_admin and o.buyer ~= name then
		return nil, S("Only the buyer can cancel this order")
	end
	if o.state ~= "open" then
		return nil, S("This order has changed")
	end
	local refunded = smp_orders.escrow.refund(o, o.escrow)
	o.state = "cancelled"
	o.version = o.version + 1
	smp_orders.save_one(o)   -- S04/OR-1: state durable with the refund
	core.log("action", string.format(
		"[smp_orders] order %d cancelled by %s, refunded %d cents",
		o.id, by_admin and (tostring(name) .. " (admin)") or tostring(name),
		refunded))
	return refunded
end

----------------------------------------------------------------------
-- Choose Item hover worth [F0192] — base price from f02
----------------------------------------------------------------------

function smp_orders.worth_of(itemstring)
	-- V-46 (open): whether this is the /sell base price or the lowest
	-- auction price. f02's base_price is the documented reading [S2].
	if smp_sell and type(smp_sell.base_price) == "function" then
		local ok, cents = pcall(smp_sell.base_price, "m0|" .. itemstring)
		if ok and type(cents) == "number" and cents > 0 then
			return math.floor(cents)
		end
	end
	return nil -- TODO(f02): omit the Worth line until smp_sell ships
end
