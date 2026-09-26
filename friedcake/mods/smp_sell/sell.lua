-- FriedcakeSMP — smp_sell/sell.lua
--
-- The sale engine: intake -> price -> route -> validate -> pay.
--
-- This module deliberately knows nothing about inventories, formspecs or
-- detached containers. Callers (menu.lua for the observed `Sell` container,
-- init.lua for `/sell hand` and `/sell all`) supply the stacks and do the
-- physical item movement around `E.pay`, following the transaction model in
-- spec/shared/02-architecture.md §2.3:
--
--   1. validate everything first          ->  E.plan / E.validate
--   2. remove the source value            ->  caller (consume)
--   3. add the destination value          ->  E.pay (orders, then server)
--   4. append the ledger entry            ->  inside smp_store.api.add_money
--   5. mark records dirty                 ->  inside smp_store
--
-- No step yields: there is no core.after, no coroutine and no I/O between
-- validation and mutation, so a sale can never interleave with another
-- callback (shared §2.3, hard rule 8).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local deps = ...   -- { items, prices, history, receipt, orders, cfg, S }

local items   = deps.items
local prices  = deps.prices
local history = deps.history
local receipt = deps.receipt
local orders  = deps.orders
local cfg     = deps.cfg
local S       = deps.S

local E = {}

----------------------------------------------------------------------
-- Intake context
----------------------------------------------------------------------

local function collect_ctx()
	return {
		base_price  = function(key) return prices.base_price(key) end,
		meta_exempt = cfg.meta_exempt_keys,
		item_exempt = cfg.meta_exempt_items,
		sell_enchanted = cfg.sell_enchanted,
	}
end
E.collect_ctx = collect_ctx

----------------------------------------------------------------------
-- 1. Plan (pure — nothing is mutated here)
----------------------------------------------------------------------

-- Returns a plan:
--   { ok, reason, receipt, groups = { {key, key_m1, unit, count,
--                                       server_qty, server_cents,
--                                       routes = { {order, qty, cents} }} },
--     returns = { ItemStack }, rejected = n, server_total, order_total }
function E.plan(player_name, stacks, source)
	local ctx = collect_ctx()
	local collected = items.collect(stacks, ctx)

	local plan = {
		ok = true,
		reason = nil,
		source = source or "container",
		player = player_name,
		receipt = receipt.new(source or "container"),
		groups = {},
		returns = collected.returns,
		return_slots = collected.return_slots,
		rejected = #collected.rejected,
		server_total = 0,
		order_total = 0,
		stacks_in = stacks,
	}

	for _, r in ipairs(collected.rejected) do
		plan.receipt:add_returned(r.stack, r.reason)
	end

	local multiplier = tonumber(cfg.multiplier) or 1
	for _, g in ipairs(collected.groups) do
		local base = prices.base_price(g.key)
		-- Enchanted stacks earn a flat bonus per enchantment level on top of
		-- the base price (PROPOSED — f02 §10 V-99).
		local bonus = prices.enchant_bonus(g.ench, cfg.enchant_bonus)
		local unit = prices.unit_value(g.key, multiplier, bonus)
		if base and unit and unit > 0 then
			local entry = {
				key = g.key, line = g.id or g.key, key_m1 = g.key_m1,
				unit = unit, count = g.count, lots = g.lots,
				server_qty = 0, server_cents = 0, routes = {},
			}
			local left = g.count

			-- 2. Route to better-paying orders first, descending unit price
			--    [S4]. Only the units an order can still take are routed. A
			--    group with no M1 key (an enchanted stack smp_items cannot
			--    key) is never routed.
			local candidates = g.key_m1
				and orders.open_orders_above(g.key_m1, unit, player_name) or {}
			for _, o in ipairs(candidates) do
				if left <= 0 then break end
				local n = math.min(left, o.remaining)
				if n > 0 then
					entry.routes[#entry.routes + 1] = {
						order = o, qty = n, cents = n * o.unit_price,
						unit_price = o.unit_price,
					}
					plan.receipt:add_order(entry.line, n, o.unit_price, o.id)
					plan.order_total = plan.order_total + n * o.unit_price
					left = left - n
				end
			end

			-- 3. The remainder goes to the server at the unit value.
			if left > 0 then
				entry.server_qty = left
				entry.server_cents = left * unit
				plan.receipt:add_server(entry.line, left, unit)
				plan.server_total = plan.server_total + left * unit
			end

			plan.groups[#plan.groups + 1] = entry
		else
			-- Priced at 0 (or the multiplier is 0): hand the items back.
			for _, lot in ipairs(g.lots) do
				plan.returns[#plan.returns + 1] = lot.stack
				plan.receipt:add_returned(lot.stack, "no_price")
			end
		end
	end

	return plan
end

----------------------------------------------------------------------
-- 2. Validate (still pure; refuses before anything is consumed)
----------------------------------------------------------------------

function E.validate(player_name, plan)
	if not plan then return false, S("No items to sell") end
	if #plan.groups == 0 and #plan.returns == 0 then
		return false, S("No items to sell")
	end

	-- shared §0.7 / f01: the balance cap is absolute. Payouts are checked
	-- against the headroom BEFORE any item is consumed, so a player at the
	-- cap loses nothing. Order proceeds are included because they land in
	-- the same balance; if routing later fails, the total can only shrink,
	-- so this check stays conservative.
	local total = plan.server_total + plan.order_total
	if total > 0 then
		local rec = smp_store.api.get_player(player_name)
		local have = (rec and tonumber(rec.money)) or 0
		local cap = tonumber(cfg.max_balance) or 1e15
		if have + total > cap then
			return false, S("You reached the balance limit")
		end
	end
	return true, nil
end

----------------------------------------------------------------------
-- 3. Pay (the mutating step)
----------------------------------------------------------------------

-- Pays order proceeds, then server proceeds, then writes statistics and
-- history. Returns:
--   { ok, err, paid = { [group_index] = true }, server_cents, order_cents,
--     history_id }
-- A group is marked paid only after its money has been credited, so a
-- failure mid-way lets the caller hand back exactly the unpaid items
-- (E.unpaid_stacks) instead of duplicating or destroying value.
function E.pay(player_name, plan)
	local result = { ok = true, err = nil, paid = {}, server_cents = 0,
	                 order_cents = 0, history_id = nil }

	for i, g in ipairs(plan.groups) do
		local order_qty, order_cents, order_ids = 0, 0, {}
		local server_qty = g.server_qty

		-- Order proceeds first: they come out of the buyer's escrow
		-- (shared §2.6 R2) and f04 writes its own `order_payout` ledger rows.
		for _, route in ipairs(g.routes) do
			local accepted, paid, reason = orders.absorb(route.order, player_name,
				g.key_m1, route.qty)
			accepted = math.floor(tonumber(accepted) or 0)
			paid = math.floor(tonumber(paid) or 0)
			if accepted > 0 and paid > 0 then
				order_qty = order_qty + accepted
				order_cents = order_cents + paid
				order_ids[#order_ids + 1] = route.order.id
				result.order_cents = result.order_cents + paid
			end
			local leftover = route.qty - accepted
			if leftover > 0 then
				-- Routing is an optimisation, not an obligation: units an
				-- order would not take (or a partial acceptance) fall through
				-- to the server price.
				core.log("action", string.format(
					"[smp_sell] routing %dx%s fell back to the server (%s)",
					leftover, g.key, tostring(reason or "partial")))
				server_qty = server_qty + leftover
			end
		end

		-- Server proceeds: one ledger row per item type, reason `sell`
		-- (shared §2.6 R3). add_money credits and appends in one call and
		-- applies the balance cap itself.
		local server_cents = 0
		if server_qty > 0 then
			server_cents = server_qty * g.unit
			local ok, applied = pcall(smp_store.api.add_money, player_name, server_cents,
				"sell", "sell:" .. g.key .. ":" .. server_qty)
			if not ok then
				result.ok = false
				result.err = tostring(applied)
				core.log("error", "[smp_sell] add_money failed for " .. player_name
					.. " / " .. g.key .. ": " .. tostring(applied))
				break
			end
			applied = math.floor(tonumber(applied) or 0)
			server_cents = applied
			result.server_cents = result.server_cents + applied
			if applied < server_qty * g.unit then
				core.log("warning", string.format(
					"[smp_sell] payout capped for %s: %d of %d cents (%s)",
					player_name, applied, server_qty * g.unit, g.key))
			end
		end

		-- The receipt was planned before payment; rewrite the line with what
		-- actually happened so history and chat never disagree.
		plan.receipt:set_line(g.line or g.key, server_qty, server_cents,
			order_qty, order_cents, order_ids)

		result.paid[i] = true
	end

	if not result.ok then return result end

	-- Statistics: server and order proceeds both count towards
	-- `money_made_from_sell` (f02 §4.8, f14 §5).
	local total_paid = result.server_cents + result.order_cents
	if total_paid > 0 then
		local ok, err = pcall(function()
			local rec = smp_store.api.ensure_player(player_name)
			rec.stats = type(rec.stats) == "table" and rec.stats or {}
			rec.stats.money_made_from_sell =
				math.floor(tonumber(rec.stats.money_made_from_sell) or 0) + total_paid
			smp_store.api.upsert_player(rec)
		end)
		if not ok then
			core.log("error", "[smp_sell] stats update failed for " .. player_name
				.. ": " .. tostring(err))
		end
	end

	-- History (f02 §4.7). A failure here loses a record, never an item or a
	-- payment, so it is logged and swallowed.
	if #plan.receipt.lines > 0 then
		local entry = plan.receipt:to_entry()
		local ok, stored = pcall(history.append, player_name, entry)
		if ok and stored then
			result.history_id = stored.id
		elseif not ok then
			core.log("error", "[smp_sell] history append failed for " .. player_name
				.. ": " .. tostring(stored))
		end
	end

	return result
end

-- Stacks belonging to groups that were NOT paid. Used by callers to hand
-- items back after a partial failure without duplicating the paid ones.
function E.unpaid_stacks(plan, result)
	local out = {}
	for i, g in ipairs(plan.groups) do
		if not (result and result.paid and result.paid[i]) then
			for _, lot in ipairs(g.lots) do
				out[#out + 1] = lot.stack
			end
		end
	end
	return out
end

----------------------------------------------------------------------
-- 4. Transact — the whole operation, in §2.3 order
----------------------------------------------------------------------

-- `stacks` MUST be a snapshot of copies (ItemStack(s)), never live inventory
-- references: the plan keeps those objects and hands them back unchanged if
-- the sale is refused or fails.
--
--   hooks.consume(plan)      remove the offered items from their source
--   hooks.give_back(stacks)  return items to the player (never drops value)
--
-- Returns (ok, messages, plan, result).
function E.transact(player_name, stacks, source, hooks)
	hooks = hooks or {}
	local plan = E.plan(player_name, stacks, source)

	-- 1. Validate. Nothing has been consumed, so a refusal is free.
	local valid, why = E.validate(player_name, plan)
	if not valid then
		return false, { why }, plan, nil
	end

	local messages
	local result
	local ok, err = pcall(function()
		-- 2. Remove the source value.
		if hooks.consume then hooks.consume(plan) end

		-- 3./4./5. Add the destination value, ledger, dirty flags.
		result = E.pay(player_name, plan)

		local give = {}
		for _, s in ipairs(plan.returns) do give[#give + 1] = s end
		if not result.ok then
			-- Partial failure: hand back exactly the items that were not
			-- paid for. The paid ones are already money in the balance.
			for _, s in ipairs(E.unpaid_stacks(plan, result)) do give[#give + 1] = s end
		end
		if hooks.give_back then hooks.give_back(give, plan) end

		messages = plan.receipt:messages(cfg.receipt_max_lines)
		if not result.ok then
			messages[#messages + 1] = S("Some items could not be sold and were returned")
			core.log("error", "[smp_sell] partial failure for " .. player_name
				.. ": " .. tostring(result.err))
		end
	end)

	if not ok then
		-- Unexpected error after the items left their source: give back the
		-- whole snapshot. Loud, because it means the item path has a bug.
		core.log("error", "[smp_sell] sale failed for " .. tostring(player_name)
			.. ": " .. tostring(err) .. " — returning the offered items")
		if hooks.give_back then
			pcall(hooks.give_back, stacks)
		end
		return false, { S("Some items could not be sold and were returned") }, plan, nil
	end

	return true, messages or {}, plan, result
end

return E
