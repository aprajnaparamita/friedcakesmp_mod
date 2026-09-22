-- FriedcakeSMP — smp_orders / delivery.lua
-- The delivery flow (f04 §3.4, §6.2): Orders -> Deliver Items over a
-- detached inventory, Orders -> Confirm Delivery with the lime pane,
-- the "Delivering..." action bar [F0226] and the singular-name chat
-- result [F0227].
--
-- R5/R6: the detached inventory is owner-only; its contents are returned
-- to the player on menu close without confirm and on disconnect (T13).
-- Items are virtual counts on the order record; nothing is ever
-- materialised into a container (T12).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_orders.S
local cfg = smp_orders.cfg
local display = smp_orders.display

smp_orders.delivery = {}
local delivery = smp_orders.delivery

local function detached_name(pname)
	return "smp_orders_deliver_" .. pname
end

----------------------------------------------------------------------
-- Return paths (never destroy, never duplicate — R6, X1)
----------------------------------------------------------------------

-- Give one stack back to a player; drop at their feet when the inventory
-- is full. Returns the undroppable leftover (normally empty).
function delivery.return_to(player, stack)
	if not stack or stack:is_empty() then return stack end
	local inv = player.get_inventory and player:get_inventory()
	local leftover = stack
	if inv then
		leftover = inv:add_item("main", stack)
	end
	if leftover and not leftover:is_empty() then
		local pos = player.get_pos and player:get_pos()
		if core.item_drop and pos then
			leftover = core.item_drop(leftover, pos) or ItemStack("")
		end
	end
	if leftover and not leftover:is_empty() then
		core.log("error", "[smp_orders] could not return " ..
			tostring(leftover.get_name and leftover:get_name()) .. " x" ..
			tostring(leftover.get_count and leftover:get_count()) ..
			" to " .. tostring(smp_orders.player_name(player)))
	end
	return leftover
end

-- Empty the delivery grid back into the player's inventory (T13).
function delivery.return_all(pname, player)
	local inv = core.get_detached_inventory and
		core.get_detached_inventory(detached_name(pname))
	if not inv then return 0 end
	if type(player) ~= "table" then player = nil end
	player = player or (core.get_player_by_name and core.get_player_by_name(pname))
	local returned = 0
	local size = inv:get_size("main")
	for i = 1, size do
		local s = inv:get_stack("main", i)
		if not s:is_empty() then
			returned = returned + s:get_count()
			if player then
				delivery.return_to(player, s)
			else
				core.log("error", "[smp_orders] return_all without player for "
					.. pname .. " — items dropped by inventory clear")
			end
			inv:set_stack("main", i, ItemStack(""))
		end
	end
	return returned
end

-- Close the delivery session: return items (unless already consumed),
-- destroy the detached inventory, drop the session.
function delivery.close(pname, do_return, player)
	if do_return then
		delivery.return_all(pname, player)
	end
	if core.remove_detached_inventory then
		core.remove_detached_inventory(detached_name(pname))
	end
	smp_core.close_session(pname, smp_orders.fs.FORMNAME.deliver)
end

----------------------------------------------------------------------
-- Action bar [F0226]
----------------------------------------------------------------------

function delivery.action_bar(player, text)
	if mcl_title and type(mcl_title.set) == "function" and player then
		pcall(mcl_title.set, player, "actionbar", { text = text })
	end
end

----------------------------------------------------------------------
-- Detached inventory (owner-only, R5)
----------------------------------------------------------------------

function delivery.create_detached(pname)
	local owner = pname
	local callbacks = {
		allow_put = function(inv, listname, index, stack, player)
			if not player or player:get_player_name() ~= owner then return 0 end
			-- Any item may be placed; matching is resolved at Confirm and
			-- everything else is returned (f04 §4.6, [F0218]).
			return stack:get_count()
		end,
		allow_take = function(inv, listname, index, stack, player)
			if not player or player:get_player_name() ~= owner then return 0 end
			return stack:get_count()
		end,
		allow_move = function(inv, from_list, from_index, to_list, to_index,
		               count, player)
			if not player or player:get_player_name() ~= owner then return 0 end
			return count
		end,
		on_put = function() delivery.refresh(owner) end,
		on_take = function() delivery.refresh(owner) end,
		on_move = function() delivery.refresh(owner) end,
	}
	local inv = core.create_detached_inventory(detached_name(pname), callbacks, pname)
	if inv and inv.set_size then inv:set_size("main", 27) end
	return inv
end

-- Live preview of what Confirm would pay, and how many items match.
function delivery.preview(pname, o)
	local inv = core.get_detached_inventory and
		core.get_detached_inventory(detached_name(pname))
	if not inv or not o then return 0, 0 end
	local matched, payout = 0, 0
	local left = smp_orders.remaining(o)
	local size = inv:get_size("main")
	for i = 1, size do
		local s = inv:get_stack("main", i)
		if not s:is_empty() and smp_items.matches(s, o.key, "M1") then
			local n = math.min(s:get_count(), left)
			matched = matched + n
			payout = payout + n * o.unit_price
			left = left - n
		end
	end
	return payout, matched
end

----------------------------------------------------------------------
-- The delivery transaction (f04 §6.2)
----------------------------------------------------------------------

-- deliver(player, order_id, stacks, seen_version)
-- `stacks` are ItemStack VALUES (copies are fine — the caller owns the
-- container). Returns accepted, payout, err, processed:
--   processed = the stacks list was consumed/returned by this call, so
--   the caller MUST clear its container (prevents duplication, X1).
-- Validation happens fully before any mutation; no yields in between
-- (shared §2.3). The version re-check is the race guard (X2).
function smp_orders.deliver(player, order_id, stacks, seen_version)
	local pname = smp_orders.player_name(player)
	local o = smp_orders.get_order(order_id)

	-- 1. Validate
	if not o or o.state ~= "open" or o.version ~= seen_version then
		return nil, nil, S("This order has changed"), false
	end
	if not pname then
		return nil, nil, S("This order has changed"), false
	end
	if o.buyer == pname and not cfg.allow_self_delivery then
		-- PROPOSED refusal (V-45 open)
		return nil, nil, S("You cannot deliver to your own order"), false
	end
	if smp_orders.remaining(o) <= 0 then
		return nil, nil, S("This order has changed"), false
	end

	-- Plan (still validation — nothing is mutated)
	local plan, accepted, left = {}, 0, smp_orders.remaining(o)
	for _, s in ipairs(stacks or {}) do
		if s and not s:is_empty() then
			if smp_items.matches(s, o.key, "M1") then
				local n = math.min(s:get_count(), left)
				if n > 0 then
					plan[#plan + 1] = { stack = s, take = n }
					accepted = accepted + n
					left = left - n
				end
			end
		end
	end

	if accepted == 0 then
		-- Refuse — but everything placed is returned (§6.2, T8)
		for _, s in ipairs(stacks or {}) do
			delivery.return_to(player, s)
		end
		return nil, nil, S("Nothing matched this order"), true
	end

	-- 2. Action bar first (observed sequence: "Delivering..." [F0226],
	--    then the result chat line [F0227])
	delivery.action_bar(player, S("Delivering..."))

	-- 3. Mutate — no yields from here (shared §2.3)
	local payout = accepted * o.unit_price
	local applied = smp_orders.escrow.payout(o, pname, payout) -- R2: clamps to escrow
	smp_orders.apply_delivery(o, pname, accepted)

	-- Consume the accepted portion; return everything else (surplus of
	-- partially-matching stacks and all non-matching stacks).
	for _, p in ipairs(plan) do
		local s = p.stack
		local surplus = s:get_count() - p.take
		if surplus > 0 then
			local back = ItemStack(s)
			back:set_count(surplus)
			delivery.return_to(player, back)   -- surplus (T9)
		end
		-- The accepted part vanishes into the order's virtual count.
		s:set_count(0)
	end
	for _, s in ipairs(stacks or {}) do
		if s and not s:is_empty() then
			delivery.return_to(player, s)      -- non-matching (T8)
		end
	end

	-- 4. Feedback: chat uses the SINGULAR display name [F0227] (T3)
	core.chat_send_player(pname,
		display.delivered_message(accepted, o, applied))
	smp_orders.notify_buyer(o, S("@1 delivered @2 @3 to your order",
		pname, display.qty(accepted), display.order_name(o)))

	return accepted, applied, nil, true
end

----------------------------------------------------------------------
-- Form flow
----------------------------------------------------------------------

function delivery.open(player, order_id)
	local pname = smp_orders.player_name(player)
	if not pname then return false end
	-- Normalise to the PlayerRef when online.
	player = (core.get_player_by_name and core.get_player_by_name(pname)) or player
	local o = smp_orders.get_order(order_id)
	if not o or o.state ~= "open" or smp_orders.remaining(o) <= 0 then
		core.chat_send_player(pname, S("This order has changed"))
		return false
	end
	if o.buyer == pname and not cfg.allow_self_delivery then
		core.chat_send_player(pname, S("You cannot deliver to your own order"))
		return false
	end

	-- Fresh grid: close (and return!) any stale delivery session first.
	delivery.close(pname, true, player)
	delivery.create_detached(pname)
	local session = smp_core.open_session(pname, smp_orders.fs.FORMNAME.deliver, {
		order_id = o.id,
		version = o.version,
		mode = "deliver",
	})
	delivery.show(pname, session, player)
	return true
end

function delivery.show(pname, session, player)
	local o = smp_orders.get_order(session.order_id)
	if not o then
		delivery.close(pname, true, player)
		core.chat_send_player(pname, S("This order has changed"))
		return
	end
	-- Re-sync the seen version on every render; the confirm click
	-- re-validates it, which is the race guard (X2).
	if o.state ~= "open" then
		delivery.close(pname, true, player)
		core.chat_send_player(pname, S("This order has changed"))
		return
	end
	session.version = o.version

	local payout, matched = delivery.preview(pname, o)
	local fs = smp_orders.fs
	local spec
	if session.mode == "confirm" then
		spec = fs.confirm_delivery(pname, o, matched, payout)
	else
		spec = fs.deliver_items(pname, payout)
	end
	smp_core.show_formspec(pname, fs.FORMNAME.deliver, spec)
end

-- Re-render after an inventory change so the Confirm affordance line
-- carries the live payout ("Click to deliver items ($30K)" [F0222]).
function delivery.refresh(pname)
	local session = smp_core.get_session(pname, smp_orders.fs.FORMNAME.deliver)
	if not session then return end
	local player = core.get_player_by_name and core.get_player_by_name(pname)
	if not player then return end
	delivery.show(pname, session, player)
end

-- Confirm pane clicked: execute the delivery (f04 §6.2).
function delivery.confirm(player, session)
	local pname = player:get_player_name()
	local o = smp_orders.get_order(session.order_id)
	local inv = core.get_detached_inventory and
		core.get_detached_inventory(detached_name(pname))
	if not o or not inv then
		delivery.close(pname, true, player)
		core.chat_send_player(pname, S("This order has changed"))
		return
	end

	local stacks = {}
	local size = inv:get_size("main")
	for i = 1, size do
		local s = inv:get_stack("main", i)
		if not s:is_empty() then stacks[#stacks + 1] = s end
	end

	local accepted, payout, err, processed =
		smp_orders.deliver(player, o.id, stacks, session.version)

	if processed then
		-- deliver() consumed the accepted part and returned the rest to
		-- the player; the grid copies must now be cleared (X1).
		for i = 1, size do
			inv:set_stack("main", i, ItemStack(""))
		end
	end

	if accepted then
		delivery.close(pname, false, player)
	else
		core.chat_send_player(pname, err or S("Nothing matched this order"))
		if processed then
			delivery.close(pname, false, player)
		else
			-- Validation refusal: items stay in the grid, re-render.
			delivery.show(pname, session, player)
		end
	end
	return accepted, payout, err
end
