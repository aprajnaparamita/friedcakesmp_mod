-- FriedcakeSMP — smp_sell/orders.lua
--
-- Sell routing adapter (f02 §4.4, §6; f04 §4.8).
--
-- `/sell` routes units into the best compatible OPEN ORDER (M1 key) whenever
-- that order pays more per unit than the server does, highest unit price
-- first, until the order's remaining quantity or the seller's quantity runs
-- out [S4]. The seller receives the order's unit price for routed units; the
-- remainder is sold to the server.
--
-- `smp_orders` is phase P3 and does not exist yet. This adapter therefore
-- degrades to "no orders" — every unit goes to the server — and exposes an
-- injection point (`O.source`) so the routing logic is testable today and
-- wires up unchanged when f04 lands. f02 T4 is exercised through that seam.
--
-- The contract proposed to f04 (also in f02 §11):
--   smp_orders.open_orders_above(key_m1, unit_cents, player_name)
--       -> array of order records, descending unit_price, only state="open",
--          unit_price > unit_cents, remaining qty > 0, buyer ~= player_name
--   smp_orders.absorb_from_sell(order, player_name, key_m1, qty)
--       -> paid_cents (integer) or nil, reason
--          Pays from the order's escrow (shared §2.6 R2) and writes its own
--          `order_payout` ledger entries. Never yields.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local O = {}

-- Injectable source. A table with `open_orders_above` and `absorb`. When nil,
-- the live `smp_orders` global is used if it provides those functions.
O.source = nil

local function backend()
	if type(O.source) == "table" then return O.source end
	local live = rawget(_G, "smp_orders")
	if type(live) == "table" then return live end
	return nil
end

function O.available()
	local b = backend()
	if not b then return false end
	return type(b.open_orders_above) == "function"
end

-- Descending list of orders that beat `unit` cents for `key_m1`.
-- Always returns a table; never raises (a broken f04 must not break /sell).
function O.open_orders_above(key_m1, unit, player_name)
	local b = backend()
	if not b or type(b.open_orders_above) ~= "function" then return {} end

	local ok, list = pcall(b.open_orders_above, key_m1, unit, player_name)
	if not ok or type(list) ~= "table" then
		if not ok then
			core.log("error", "[smp_sell] open_orders_above failed: " .. tostring(list))
		end
		return {}
	end

	-- Re-validate every candidate: the client of this function must be able
	-- to trust the shape, and a future f04 must not be able to route items
	-- into a filled, cancelled or self-owned order.
	local out = {}
	for _, o in ipairs(list) do
		if type(o) == "table" then
			local price = math.floor(tonumber(o.unit_price) or 0)
			local qty = math.floor(tonumber(o.qty) or 0)
			local delivered = math.floor(tonumber(o.delivered) or 0)
			local remaining = qty - delivered
			local state = o.state or "open"
			if price > unit and remaining > 0 and state == "open"
			   and o.buyer ~= player_name then
				out[#out + 1] = {
					ref = o,               -- the record f04 handed us
					id = o.id,
					version = o.version,
					unit_price = price,
					remaining = remaining,
				}
			end
		end
	end
	table.sort(out, function(a, b2)
		if a.unit_price == b2.unit_price then
			return tostring(a.id) < tostring(b2.id)
		end
		return a.unit_price > b2.unit_price
	end)
	return out
end

-- Hand `qty` units to an order. Returns the number of units the order
-- actually accepted and the cents it paid, or (nil, reason).
--
-- Contract (owner: f04, `smp_orders.absorb_from_sell`):
--   absorb_from_sell(o, player, key, n) -> accepted_count, cents_paid
-- A partial acceptance is normal (the order may have less than `qty`
-- remaining), so the caller MUST route the unaccepted remainder to the
-- server. Tolerant shims: a single-number return is read as `paid cents`
-- (an earlier PROPOSED shape) and (nil, reason) is a refusal.
function O.absorb(order, player_name, key_m1, qty)
	if not order or qty <= 0 then return nil, "nothing to route" end
	local b = backend()
	if not b then return nil, "no order backend" end

	local fn = b.absorb_from_sell or b.absorb
	if type(fn) ~= "function" then return nil, "no absorb function" end

	local ok, r1, r2 = pcall(fn, order.ref or order, player_name, key_m1, qty)
	if not ok then
		core.log("error", "[smp_sell] absorb_from_sell failed: " .. tostring(r1))
		return nil, "order backend error"
	end

	if type(r1) == "number" and type(r2) == "number" then
		-- f04 shape: accepted_count, cents_paid.
		local accepted = math.floor(tonumber(r1) or 0)
		local paid = math.floor(tonumber(r2) or 0)
		if accepted <= 0 or paid <= 0 then return nil, "order refused" end
		return accepted, paid
	elseif type(r1) == "number" and (r2 == nil or r2 == true) then
		-- Earlier PROPOSED shape: paid cents as the single return.
		local paid = math.floor(tonumber(r1) or 0)
		if paid <= 0 then return nil, "order paid nothing" end
		return qty, paid
	end
	return nil, r2 or r1 or "order refused"
end

return O
