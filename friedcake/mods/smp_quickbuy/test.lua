-- FriedcakeSMP — smp_quickbuy acceptance tests
-- Loaded by `/smp test smp_quickbuy` in-game.
--
-- Covers spec/features/f05-quickbuy.md §9 T1–T7 on the buy path, with the
-- f03/f10/f14 bridges stubbed to deterministic fakes. The auction fake is
-- restored afterwards so the live mod is untouched.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator and core.get_translator("smp_quickbuy")
	or function(s, ...) return s end

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "ok")
	end
end

local function eq(a, b, msg)
	ok(a == b, string.format("%s: expected %s got %s", msg or "eq", tostring(b), tostring(a)))
end

----------------------------------------------------------------------
-- Save the real bridges so they can be restored.
----------------------------------------------------------------------

local real_au_cheapest, real_au_buy =
	smp_quickbuy.au.cheapest_for, smp_quickbuy.au.buy
local real_is_tagged = smp_quickbuy.combat.is_tagged
local real_stats_add = smp_quickbuy.stats.add

----------------------------------------------------------------------
-- Deterministic auction fake.
----------------------------------------------------------------------

local function ench_key(ench)
	local parts = {}
	for id, lvl in pairs(ench or {}) do parts[#parts + 1] = id .. "=" .. tostring(lvl) end
	table.sort(parts)
	return table.concat(parts, ",")
end

local auction = { listings = {}, force_fail = nil }

local function reset(listings)
	auction.listings = {}
	for _, l in ipairs(listings or {}) do
		auction.listings[#auction.listings + 1] = {
			key = l.key, ench = l.ench or {}, id = l.id, version = l.version or 1,
			count = l.count or 1, price = l.price, state = "active",
		}
	end
	auction.force_fail = nil
end

local function fake_cheapest_for(key, ench, qty)
	local wanted = ench_key(ench)
	local matches = {}
	for _, l in ipairs(auction.listings) do
		if l.key == key and l.state == "active" and ench_key(l.ench) == wanted then
			matches[#matches + 1] = l
		end
	end
	table.sort(matches, function(a, b) return a.price / a.count < b.price / b.count end)
	local picked, got, cost = {}, 0, 0
	for _, l in ipairs(matches) do
		if got >= qty then break end
		picked[#picked + 1] = {
			id = l.id, version = l.version, count = l.count,
			price = l.price, unit_price = l.price / l.count,
		}
		got = got + l.count
		cost = cost + l.price
	end
	if got < qty then return nil end
	return { listings = picked, cost_cents = cost }
end

local function fake_buy(player, id, version)
	if auction.force_fail == id then return nil end
	local name = player:get_player_name()
	local l
	for _, x in ipairs(auction.listings) do if x.id == id then l = x end end
	if not l or l.state ~= "active" or l.version ~= version then return nil end
	local rec = smp_store.api.get_player(name)
	if not rec or rec.money < l.price then return nil end
	rec.money = rec.money - l.price
	l.state = "sold"
	l.version = l.version + 1
	return { stack = {} }
end

-- Wire the fakes in.
smp_quickbuy.au.cheapest_for = fake_cheapest_for
smp_quickbuy.au.buy = fake_buy
smp_quickbuy.combat.is_tagged = function(p) return p.tagged and true or false end
smp_quickbuy.stats.add = function(p, key, value)
	local rec = smp_store.api.ensure_player(p:get_player_name())
	rec.stats = rec.stats or {}
	rec.stats[key] = (rec.stats[key] or 0) + value
end

----------------------------------------------------------------------
-- Set-up.
----------------------------------------------------------------------

local PNAME = "__test_quickbuy"
local function seed_money(cents) smp_store.api.set_money(PNAME, cents, "test", "qb setup") end
local function money() return smp_store.api.get_player(PNAME).money end
local function stat(key)
	local r = smp_store.api.get_player(PNAME)
	return r and r.stats and r.stats[key] or 0
end

local player = {
	name = PNAME,
	tagged = false,
	get_player_name = function() return PNAME end,
}

local rec = smp_store.api.ensure_player(PNAME)
rec.quickbuy = {}
rec.stats = {}
smp_store.api.upsert_player(rec)

----------------------------------------------------------------------
-- T1: live price lookup updates when listings change.
----------------------------------------------------------------------

reset({ { key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 100 },
        { key = "mcl_core:diamond", ench = {}, id = 2, count = 1, price = 300 } })
eq(smp_quickbuy.price.lookup("mcl_core:diamond", {}, 2), 400, "T1 initial price")
reset({ { key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 100 },
        { key = "mcl_core:diamond", ench = {}, id = 2, count = 1, price = 300 },
        { key = "mcl_core:diamond", ench = {}, id = 3, count = 1, price = 10 } })
eq(smp_quickbuy.price.lookup("mcl_core:diamond", {}, 2), 110, "T1 price updates on redraw")

----------------------------------------------------------------------
-- T2/T3: the 3x guard.
----------------------------------------------------------------------

eq(smp_quickbuy.price.within_guard(100, 300), true,  "T3 3x exactly: allowed")
eq(smp_quickbuy.price.within_guard(100, 301), false, "T3 over 3x: warn")

reset({ { key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 100 } })
smp_quickbuy.entries.add(PNAME, { key = "mcl_core:diamond", ench = {}, qty = 1 })
seed_money(1000)
local r, spent = smp_quickbuy.buy.entry(player, 1, 100, false)
eq(r, true, "T2 within-guard purchase completes")
eq(spent, 100, "T2 spent")
eq(money(), 900, "T2 debited")

reset({ { key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 400 } })
seed_money(1000)
local wr, _, _, wc = smp_quickbuy.buy.entry(player, 1, 100, false)
eq(wr, "warn", "T3 above-guard returns warn")
eq(wc, 400, "T3 warn carries live cost")
eq(money(), 1000, "T3 nothing charged before re-confirm")
local rr, rspent = smp_quickbuy.buy.entry(player, 1, 100, true)
eq(rr, true, "T3 completes after re-confirm")
eq(rspent, 400, "T3 spent after re-confirm")
eq(money(), 600, "T3 debited after re-confirm")

----------------------------------------------------------------------
-- T4: enchantment-exact matching.
----------------------------------------------------------------------

reset({ { key = "mcl_tools:sword_netherite", ench = { sharpness = 4 }, id = 10, count = 1, price = 100 } })
smp_quickbuy.entries.add(PNAME, { key = "mcl_tools:sword_netherite", ench = { sharpness = 5 }, qty = 1 })
ok(smp_quickbuy.price.lookup("mcl_tools:sword_netherite", { sharpness = 5 }, 1) == nil,
	"T4 Sharpness IV does not fill Sharpness V")
local t4r = smp_quickbuy.buy.entry(player, 2, 100, false)
ok(t4r == nil, "T4 Sharpness IV listing refused for Sharpness V entry")

----------------------------------------------------------------------
-- T5: combat refusal.
----------------------------------------------------------------------

reset({ { key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 100 } })
seed_money(1000)
player.tagged = true
ok(smp_quickbuy.buy.entry(player, 1, 100, false) == nil, "T5 combat-tagged refused")
eq(money(), 1000, "T5 nothing charged while tagged")
player.tagged = false

----------------------------------------------------------------------
-- T6: money_spent_on_shop increments by exactly the amount paid.
----------------------------------------------------------------------

reset({ { key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 250 } })
seed_money(10000)
rec = smp_store.api.ensure_player(PNAME); rec.stats = {}; smp_store.api.upsert_player(rec)
local _, t6spent = smp_quickbuy.buy.entry(player, 1, 250, false)
eq(t6spent, 250, "T6 spent 250")
eq(stat("money_spent_on_shop"), 250, "T6 stat increments by exactly 250")

----------------------------------------------------------------------
-- T7: a raced listing is not charged; the rest of the purchase completes.
----------------------------------------------------------------------

reset({ { key = "mcl_core:diamond", ench = {}, id = 100, count = 1, price = 100 },
        { key = "mcl_core:diamond", ench = {}, id = 200, count = 1, price = 200 } })
smp_quickbuy.entries.set(PNAME, 1, { key = "mcl_core:diamond", ench = {}, qty = 2 })
seed_money(10000)
rec = smp_store.api.ensure_player(PNAME); rec.stats = {}; smp_store.api.upsert_player(rec)
auction.force_fail = 100
local t7r, t7spent, t7bought = smp_quickbuy.buy.entry(player, 1, 300, false)
eq(t7r, true, "T7 partial purchase succeeds")
eq(t7bought, 1, "T7 one listing bought")
eq(t7spent, 200, "T7 charged only the successful listing")
eq(money(), 9800, "T7 buyer debited 200, not 300")
eq(stat("money_spent_on_shop"), 200, "T7 stat reflects only the amount paid")

----------------------------------------------------------------------
-- Restore the real bridges and clean up.
----------------------------------------------------------------------

smp_quickbuy.au.cheapest_for = real_au_cheapest
smp_quickbuy.au.buy = real_au_buy
smp_quickbuy.combat.is_tagged = real_is_tagged
smp_quickbuy.stats.add = real_stats_add

smp_store.api.set_money(PNAME, 0, "test", "qb cleanup")
rec = smp_store.api.ensure_player(PNAME)
rec.quickbuy = {}
rec.stats = {}
smp_store.api.upsert_player(rec)

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_quickbuy tests passed."
else
	results.lines[#results.lines + 1] = string.format("%d failures.", results.failed)
end
return results
