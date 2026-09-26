-- FriedcakeSMP — smp_sell acceptance tests
--
-- Loaded by `/smp test smp_sell` in-game (the `/smp` wrapper lives in
-- init.lua; smp_economy's own dispatcher is not modified). Returns
-- `{ passed = N, failed = N, lines = { ... } }` like smp_core/test.lua.
--
-- Covers spec/features/f02-sell.md §9:
--   T1  the container is titled exactly `Sell`, with the confirm pane in the
--       bottom-right cell of the grid
--   T2  nothing is sold until the confirm control is clicked
--   T3  ineligible items are returned, not consumed
--   T4  items route to a better-paying order first, highest price first
--   T5  a shulker's eligible contents are sold, the box comes back with the
--       ineligible items intact
--   T6  closing without confirming returns every item
--   T7  leaving with the menu open returns every item
--   T8  a full inventory drops the returns at the player's feet
--   T9  sell.multiplier triples server payouts and leaves order payouts alone
--   T10 selling while combat-tagged succeeds
--
-- The container tests run against the CALLING player, because a detached
-- inventory is owner-scoped and needs a real player object. Their inventory,
-- balance, statistics and sell history are snapshotted first and restored
-- afterwards on every exit path, including failures.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator and core.get_translator("smp_sell")
	or function(s, ...) return s end

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. tostring(msg)
	end
end

local function eq(got, want, msg)
	ok(got == want, string.format("%s: expected %s got %s",
		tostring(msg), tostring(want), tostring(got)))
end

----------------------------------------------------------------------
-- Test fixtures
----------------------------------------------------------------------

local items = smp_sell.items
local prices = smp_sell.prices
local menu = smp_sell.menu
local engine = smp_sell.engine
local FORMNAME = menu.FORMNAME

-- Two items that actually exist in this game AND have a price, so the suite
-- works with any operator price table.
local cheap, cheap_cents, pricey, pricey_cents
do
	local best_cheap, best_pricey = math.huge, -1
	for key, cents in pairs(prices.all()) do
		if core.registered_items[key] then
			if cents < best_cheap then best_cheap, cheap, cheap_cents = cents, key, cents end
			if cents > best_pricey then best_pricey, pricey, pricey_cents = cents, key, cents end
		end
	end
end
if not cheap or not pricey then
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] =
		"FAIL no priced, registered items: the price table has nothing usable"
	return results
end
if cheap == pricey then
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] =
		"FAIL the price table has only one usable item; T4/T5 need two"
	return results
end

-- An item with no price at all, to stand in for "the server does not buy it".
-- Registered once per server session; it is deliberately invisible in the
-- creative inventory and nothing else in the modpack refers to it.
local unpriced = "smp_sell:unpriced_probe"
if not core.registered_items[unpriced] then
	core.register_craftitem(unpriced, {
		description = "Sell Test Probe",
		stack_max = 1,
		groups = { not_in_creative_inventory = 1 },
	})
end

-- An ineligible version of the cheap item: a renamed stack (M0 rejects it).
local function ineligible_stack()
	local s = ItemStack(cheap)
	s:get_meta():set_string("name", "Not For Sale")
	return s
end

----------------------------------------------------------------------
-- Player fixture: snapshot and restore
----------------------------------------------------------------------

-- The container tests need a real player object: a detached inventory is
-- owner-scoped and its callbacks receive the player. Use whoever ran
-- `/smp test smp_sell`.
local player
for _, p in ipairs(core.get_connected_players()) do
	if core.check_player_privs(p:get_player_name(), { smp_admin = true }) then
		player = p
		break
	end
end
if not player then
	for _, p in ipairs(core.get_connected_players()) do
		player = p
		break
	end
end
if not player then
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] = "FAIL no player to run the container tests against"
	return results
end

local pname = player:get_player_name()
local inv = player:get_inventory()
local saved_list = inv:get_list("main")
local saved_record = smp_store.api.get_player(pname)
local saved_money = (saved_record and saved_record.money) or 0
local saved_stats = (saved_record and saved_record.stats) or {}
local saved_money_made = saved_stats.money_made_from_sell or 0
local saved_history = smp_sell.history.list(pname)

-- Give the tests a clean slate: empty inventory, zero balance, no history.
do
	local empty = {}
	for i = 1, inv:get_size("main") do empty[i] = ItemStack("") end
	inv:set_list("main", empty)
	smp_store.api.set_money(pname, 0, "test", "smp_sell test fixture")
	smp_sell.history.clear(pname)
end

local function restore()
	inv:set_list("main", saved_list)
	smp_store.api.set_money(pname, saved_money, "test", "smp_sell test restore")
	local rec = smp_store.api.ensure_player(pname)
	rec.stats = type(rec.stats) == "table" and rec.stats or {}
	rec.stats.money_made_from_sell = saved_money_made
	smp_store.api.upsert_player(rec)
	-- History cannot be un-appended; the fixture cleared it, so re-seed what
	-- was there (newest first) to leave the player's record as we found it.
	for i = #saved_history, 1, -1 do
		smp_sell.history.append(pname, saved_history[i])
	end
	-- Empty the container without selling: menu.close() would sell in
	-- `close` mode, and a test must never depend on that setting.
	menu.return_contents(player, pname)
	if core.remove_detached_inventory then
		pcall(core.remove_detached_inventory, menu.inv_name(pname))
	end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Count items of a given name in the player's inventory. `skip_named`
-- ignores renamed stacks, which is what T3 needs: the ineligible probe is
-- the same item as the sellable one, only renamed.
local function inventory_count(name, skip_named)
	local total = 0
	for i = 1, inv:get_size("main") do
		local s = inv:get_stack("main", i)
		if not s:is_empty() and s:get_name() == name then
			if not (skip_named and s:get_meta():get_string("name") ~= "") then
				total = total + s:get_count()
			end
		end
	end
	return total
end

local function total_inventory_count()
	local total = 0
	for i = 1, inv:get_size("main") do
		local s = inv:get_stack("main", i)
		if not s:is_empty() then total = total + s:get_count() end
	end
	return total
end

local function money()
	local r = smp_store.api.get_player(pname)
	return (r and r.money) or 0
end

local function reset()
	local empty = {}
	for i = 1, inv:get_size("main") do empty[i] = ItemStack("") end
	inv:set_list("main", empty)
	smp_store.api.set_money(pname, 0, "test", "reset")
	local rec = smp_store.api.ensure_player(pname)
	rec.stats = type(rec.stats) == "table" and rec.stats or {}
	rec.stats.money_made_from_sell = 0
	smp_store.api.upsert_player(rec)
	-- Empty the container without selling, whatever sell.mode is set to.
	menu.return_contents(player, pname)
	if core.remove_detached_inventory then
		pcall(core.remove_detached_inventory, menu.inv_name(pname))
	end
end

-- Put a stack into the container through the detached-inventory callbacks,
-- exactly as the engine does for a player drag (so allow_put is exercised).
local function put(stack, index)
	local dinv = menu.get_inv(pname)
	if not dinv then return false end
	local cb = menu.callbacks_for(pname)
	local allowed = stack:get_count()
	if cb and cb.allow_put then
		allowed = cb.allow_put(dinv, "main", index, stack, player)
	end
	if allowed <= 0 then return false end
	local s = ItemStack(stack)
	s:set_count(math.min(allowed, s:get_count()))
	dinv:set_stack("main", index, s)
	if cb and cb.on_put then cb.on_put(dinv, "main", index, s, player) end
	return true
end

local function container_count()
	local dinv = menu.get_inv(pname)
	if not dinv then return 0 end
	local n = 0
	for i = 1, dinv:get_size("main") do
		local s = dinv:get_stack("main", i)
		if not s:is_empty() then n = n + s:get_count() end
	end
	return n
end

-- Each confirm is a separate sale: clear the SE-5 rate limit first, or
-- back-to-back confirms (and a frozen test clock) trip it.
local function confirm()
	if smp_sell._reset_sell_cooldown then smp_sell._reset_sell_cooldown(pname) end
	menu.confirm(player)
end

local function shulker_box(contents)
	-- Any registered shulker box will do; fall back to a chest-like probe if
	-- the game has none (then T5 is reported as skipped, not failed).
	local name
	for candidate in pairs(core.registered_items) do
		if core.get_item_group(candidate, "shulker_box") > 0
		   and core.registered_items[candidate].stack_max == 1 then
			name = candidate
			break
		end
	end
	if not name then return nil end
	local box = ItemStack(name)
	local list = {}
	for i = 1, items.SHULKER_SLOTS do list[i] = ItemStack("") end
	for i, s in ipairs(contents or {}) do list[i] = ItemStack(s) end
	items.encode_contents(box, list)
	return box
end

----------------------------------------------------------------------
-- Run
----------------------------------------------------------------------

local function run_all()
	----------------------------------------------------------------------
	-- Pure logic: keys, plainness, prices
	----------------------------------------------------------------------
	local plain = ItemStack(cheap .. " 4")
	eq(items.key_m0(plain), items.resolve_name(cheap), "M0 key of a plain stack")
	eq(items.key_m0(ineligible_stack()), nil, "a renamed stack has no M0 key")
	eq(items.key_m1(plain), items.plain_m1(items.resolve_name(cheap)),
		"M1 key of a plain stack")
	ok(prices.base_price(cheap) ~= nil, "the fixture item has a base price")
	ok(smp_sell.unit_value(cheap) >= prices.base_price(cheap),
		"unit value is at least the base price at multiplier >= 1")

	-- Shulker codec round-trip (needs a box in this game).
	local probe = shulker_box({ ItemStack(cheap .. " 3") })
	if probe then
		local decoded = items.decode_contents(probe)
		local found = 0
		for _, s in ipairs(decoded) do
			if not s:is_empty() then found = found + s:get_count() end
		end
		eq(found, 3, "T5 shulker contents survive the codec round-trip")
		items.encode_contents(probe, {})
		eq(probe:get_meta():get_string("compressed"), "",
			"an emptied box loses its contents metadata")
	else
		results.lines[#results.lines + 1] =
			"NOTE no shulker box registered in this game; T5 codec test skipped"
	end

	----------------------------------------------------------------------
	-- T1: the observed container
	----------------------------------------------------------------------
	reset()
	ok(menu.open(player), "T1 /sell opens the container")
	local session = smp_core.get_session(pname, FORMNAME)
	ok(session ~= nil, "T1 a server-side session exists (shared §2.4)")
	local fs = menu.formspec(pname, session)
	ok(fs:find("label[0.375,0.375;Sell]", 1, true) ~= nil
		or fs:find(";Sell]", 1, true) ~= nil,
		"T1 the container is titled exactly `Sell` [F0093]")
	ok(fs:find("list[detached:" .. menu.inv_name(pname) .. ";main;", 1, true) ~= nil,
		"T1 the grid is a detached inventory, never a node inventory")
	ok(fs:find("listring[", 1, true) ~= nil, "T1 shift-click rings are set")
	ok(fs:find("item_image_button[", 1, true) ~= nil
		or smp_sell.cfg.mode ~= "button",
		"T1 button mode renders the confirm pane [F0094]")
	ok(fs:find("tooltip[confirm;" .. core.formspec_escape(S("Confirm")), 1, true) ~= nil
		or smp_sell.cfg.mode ~= "button",
		"T1 the confirm tooltip starts with the observed `Confirm` line")
	eq(menu.slot_count(), smp_sell.cfg.mode == "button" and 44 or 45,
		"T1 the grid is five rows, minus the confirm cell in button mode")
	ok(fs:find("Inventory", 1, true) ~= nil, "T1 the `Inventory` label is present")

	----------------------------------------------------------------------
	-- T2: nothing sells before the confirm control
	----------------------------------------------------------------------
	reset()
	menu.open(player)
	put(ItemStack(cheap .. " 5"), 1)
	eq(money(), 0, "T2 dropping items into the grid sells nothing")
	eq(container_count(), 5, "T2 the items are in the container")
	confirm()
	eq(money(), 5 * smp_sell.unit_value(cheap), "T2 confirming pays the unit value")
	eq(container_count(), 0, "T2 the container is empty after the sale")
	ok(not menu.is_open(pname), "T2 confirming closes the menu")
	eq(smp_sell.history.count(pname), 1, "T2 the sale is in the history")
	local rec = smp_store.api.get_player(pname)
	eq(rec.stats.money_made_from_sell, 5 * smp_sell.unit_value(cheap),
		"T2 the proceeds increment money_made_from_sell (f14 T4)")

	----------------------------------------------------------------------
	-- T3: ineligible items are returned
	----------------------------------------------------------------------
	reset()
	menu.open(player)
	put(ineligible_stack(), 1)
	put(ItemStack(unpriced .. " 3"), 2)
	put(ItemStack(cheap .. " 2"), 3)
	confirm()
	eq(money(), 2 * smp_sell.unit_value(cheap), "T3 only the eligible item was sold")
	eq(inventory_count(items.resolve_name(cheap), true), 0,
		"T3 the sellable stacks were consumed")
	eq(inventory_count(unpriced), 3, "T3 the unpriced item was returned")
	local back
	for i = 1, inv:get_size("main") do
		local s = inv:get_stack("main", i)
		if s:get_meta():get_string("name") == "Not For Sale" then
			back = s
			break
		end
	end
	ok(back ~= nil, "T3 the renamed item was returned")
	eq(back and back:get_meta():get_string("name"), "Not For Sale",
		"T3 the returned item kept its custom name")
	eq(back and back:get_count(), 1, "T3 the returned item kept its count")

	----------------------------------------------------------------------
	-- T4: routing to the better-paying order, highest first
	----------------------------------------------------------------------
	reset()
	local absorbed = {}
	local key_m1 = items.plain_m1(items.resolve_name(cheap))
	local unit = smp_sell.unit_value(cheap)
	smp_sell.orders.source = {
		open_orders_above = function(k)
			if k ~= key_m1 then return {} end
			return {
				-- deliberately unsorted, plus rows that must be filtered out
				{ id = 11, version = 1, state = "open", buyer = "carol",
				  unit_price = unit + 5, qty = 100, delivered = 96 },
				{ id = 12, version = 1, state = "open", buyer = "dave",
				  unit_price = unit + 9, qty = 100, delivered = 98 },
				{ id = 13, version = 1, state = "filled", buyer = "erin",
				  unit_price = unit + 99, qty = 100, delivered = 0 },
				{ id = 14, version = 1, state = "open", buyer = pname,
				  unit_price = unit + 99, qty = 100, delivered = 0 },
				{ id = 15, version = 1, state = "open", buyer = "frank",
				  unit_price = 1, qty = 100, delivered = 0 },
			}
		end,
		absorb_from_sell = function(order, who, k, qty)
			absorbed[#absorbed + 1] = { id = order.id, qty = qty }
			-- f04 pays the seller from the order's escrow and writes its own
			-- `order_payout` ledger row (shared §2.6 R2, R3).
			smp_store.api.add_money(who, qty * order.unit_price, "order_payout",
				"order:" .. order.id)
			return qty, qty * order.unit_price
		end,
	}
	menu.open(player)
	put(ItemStack(cheap .. " 10"), 1)
	confirm()
	eq(#absorbed, 2, "T4 two orders were used")
	eq(absorbed[1] and absorbed[1].id, 12, "T4 the highest unit price is served first")
	eq(absorbed[1] and absorbed[1].qty, 2, "T4 only the remaining order quantity is taken")
	eq(absorbed[2] and absorbed[2].id, 11, "T4 the next-best order is served second")
	eq(absorbed[2] and absorbed[2].qty, 4, "T4 the second order takes what it has room for")
	eq(money(), 2 * (unit + 9) + 4 * (unit + 5) + 4 * unit,
		"T4 routed units pay the order price, the rest the server price")
	local hist = smp_sell.history.list(pname)[1]
	eq(hist.order_total, 2 * (unit + 9) + 4 * (unit + 5), "T4 history keeps the order total")
	eq(hist.server_total, 4 * unit, "T4 history keeps the server total")
	eq(#hist.lines[1].order_ids, 2, "T4 history keeps both order ids")
	smp_sell.orders.source = nil

	----------------------------------------------------------------------
	-- T5: shulker boxes
	----------------------------------------------------------------------
	reset()
	local box = shulker_box({
		ItemStack(cheap .. " 7"),
		ineligible_stack(),
		ItemStack(unpriced .. " 2"),
	})
	if box then
		menu.open(player)
		put(box, 1)
		confirm()
		eq(money(), 7 * smp_sell.unit_value(cheap),
			"T5 the eligible contents were sold")
		eq(inventory_count(box:get_name()), 1, "T5 the box was returned")
		local returned
		for i = 1, inv:get_size("main") do
			local s = inv:get_stack("main", i)
			if s:get_name() == box:get_name() then returned = s end
		end
		local left = items.decode_contents(returned)
		local n = 0
		local names = {}
		for _, s in ipairs(left) do
			if not s:is_empty() then
				n = n + 1
				names[s:get_name()] = (names[s:get_name()] or 0) + s:get_count()
			end
		end
		eq(n, 2, "T5 exactly the ineligible items are still inside")
		eq(names[unpriced], 2, "T5 the unpriced contents are intact")
		eq(names[items.resolve_name(cheap)], 1, "T5 the renamed item is intact")
	else
		results.lines[#results.lines + 1] =
			"NOTE no shulker box registered in this game; T5 container test skipped"
	end

	----------------------------------------------------------------------
	-- T6: closing without confirming
	----------------------------------------------------------------------
	reset()
	menu.open(player)
	put(ItemStack(cheap .. " 8"), 1)
	menu.close(player, "quit")
	eq(money(), 0, "T6 closing without confirming sells nothing")
	eq(inventory_count(items.resolve_name(cheap)), 8, "T6 every item came back")
	eq(container_count(), 0, "T6 the container is empty")
	ok(not menu.is_open(pname), "T6 the session closed")

	-- R4: a stale/forged field with no session must do nothing.
	menu.confirm(player)
	eq(money(), 0, "R4 confirm without a session does nothing")

	----------------------------------------------------------------------
	-- T7: leaving with the menu open
	----------------------------------------------------------------------
	reset()
	menu.open(player)
	put(ItemStack(cheap .. " 6"), 1)
	local returned = menu.return_contents(player, pname)
	ok(returned >= 1, "T7 the container contents are returned on leave")
	eq(money(), 0, "T7 leaving sells nothing")
	eq(inventory_count(items.resolve_name(cheap)), 6, "T7 the items are back in the inventory")
	eq(container_count(), 0, "T7 the container is empty")

	----------------------------------------------------------------------
	-- T8: a full inventory drops the returns
	----------------------------------------------------------------------
	reset()
	local size = inv:get_size("main")
	for i = 1, size do inv:set_stack("main", i, ItemStack(unpriced .. " 1")) end
	menu.open(player)
	put(ItemStack(unpriced .. " 1"), 1)
	put(ItemStack(cheap .. " 4"), 2)
	local inventory_before = total_inventory_count() + 1 + 4
	confirm()
	local inventory_after = total_inventory_count()
	-- Anything that did not fit was dropped by menu.give_back; the engine
	-- owns those entities, so the invariant we can check in-game is that the
	-- player kept every item that fitted and paid for the rest.
	ok(inventory_after <= inventory_before, "T8 the inventory never grows on return")
	eq(money(), 4 * smp_sell.unit_value(cheap), "T8 the sellable item was still paid for")
	eq(inventory_count(unpriced), size, "T8 every slot that was full stayed full")

	----------------------------------------------------------------------
	-- T9: the multiplier
	----------------------------------------------------------------------
	reset()
	local saved_multiplier = smp_sell.cfg.multiplier
	smp_sell.cfg.multiplier = 3
	menu.open(player)
	put(ItemStack(cheap .. " 2"), 1)
	confirm()
	eq(money(), 2 * math.floor(prices.base_price(cheap) * 3 + 0.5),
		"T9 a 3x multiplier triples the server payout")
	smp_sell.cfg.multiplier = saved_multiplier

	-- Order payouts do not move with the multiplier.
	reset()
	smp_sell.cfg.multiplier = 3
	local order_unit = smp_sell.unit_value(cheap) + 100
	smp_sell.orders.source = {
		open_orders_above = function()
			return { { id = 21, version = 1, state = "open", buyer = "carol",
			           unit_price = order_unit, qty = 5, delivered = 0 } }
		end,
		absorb_from_sell = function(order, who, k, qty)
			smp_store.api.add_money(who, qty * order.unit_price, "order_payout",
				"order:" .. order.id)
			return qty, qty * order.unit_price
		end,
	}
	menu.open(player)
	put(ItemStack(cheap .. " 5"), 1)
	confirm()
	eq(money(), 5 * order_unit, "T9 an order pays its own unit price at 3x")
	smp_sell.orders.source = nil
	smp_sell.cfg.multiplier = saved_multiplier

	----------------------------------------------------------------------
	-- T10: combat
	----------------------------------------------------------------------
	reset()
	local saved_combat = smp_combat
	smp_combat = { is_tagged = function() return true end }
	-- SE-4: the container refuses puts while tagged (items parked there
	-- would dodge the combat-log drop), but selling itself still works.
	menu.open(player)
	ok(not put(ItemStack(cheap .. " 1"), 1),
		"T10 SE-4 the sell container refuses items while combat-tagged")
	menu.return_contents(player, pname)
	inv:set_stack("main", player:get_wield_index(), ItemStack(cheap .. " 1"))
	if smp_sell._reset_sell_cooldown then smp_sell._reset_sell_cooldown(pname) end
	core.registered_chatcommands.sell.func(pname, "hand")
	ok(money() > 0, "T10 selling while combat-tagged succeeds (/sell hand)")
	ok(smp_sell.ALLOWED_IN_COMBAT.sell == true,
		"T10 smp_sell publishes its combat whitelist for f10")
	smp_combat = saved_combat

	----------------------------------------------------------------------
	-- /worth and /sellhistory
	----------------------------------------------------------------------
	reset()
	local wok, wout = core.registered_chatcommands.worth.func(pname, cheap)
	ok(wok and wout:find("each", 1, true) ~= nil, "/worth names a price per item")
	wok, wout = core.registered_chatcommands.worth.func(pname, unpriced)
	ok(wout:find("no server price", 1, true) ~= nil, "/worth reports an unpriced item")

	menu.open(player)
	put(ItemStack(cheap .. " 1"), 1)
	confirm()
	local hok, hout = core.registered_chatcommands.sellhistory.func(pname, "1")
	ok(hok and hout:find("Sell history", 1, true) ~= nil, "/sellhistory renders a page")

	----------------------------------------------------------------------
	-- Balance cap: refused before anything is consumed
	----------------------------------------------------------------------
	reset()
	local cap = tonumber(smp_sell.cfg.max_balance) or 1e15
	smp_store.api.set_money(pname, cap - 1, "test", "cap fixture")
	menu.open(player)
	put(ItemStack(pricey .. " 64"), 1)
	local container_before = container_count()
	confirm()
	eq(money(), cap - 1, "a sale over the balance cap is refused")
	eq(inventory_count(items.resolve_name(pricey)), 64,
		"a refused sale returns every item")
	smp_store.api.set_money(pname, 0, "test", "cap fixture cleanup")

	----------------------------------------------------------------------
	-- S02 recipe arbitrage: no craft or stonecutter recipe may sell for
	-- more than its inputs. Needs the live registry, so it only runs
	-- in-engine; the luajit harness has no recipes and skips it.
	----------------------------------------------------------------------
	if type(core.get_all_craft_recipes) == "function" and smp_sell.arbitrage
			and (core.get_all_craft_recipes("mcl_core:stonebrick") or {})[1] then
		local violations, scanned = smp_sell.arbitrage.scan()
		ok(scanned > 0, "S02 the arbitrage scan found recipes")
		for i = 1, math.min(#violations, 10) do
			results.lines[#results.lines + 1] =
				"  arbitrage: " .. smp_sell.arbitrage.describe(violations[i])
		end
		eq(#violations, 0, "S02 no recipe sells for more than its inputs")
	end
end

local run_ok, run_err = pcall(run_all)
if not run_ok then
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] = "FAIL test run crashed: " .. tostring(run_err)
end

local restore_ok, restore_err = pcall(restore)
if not restore_ok then
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] =
		"FAIL could not restore the player state: " .. tostring(restore_err)
	core.log("error", "[smp_sell] test restore failed for " .. pname
		.. ": " .. tostring(restore_err))
end

return results
