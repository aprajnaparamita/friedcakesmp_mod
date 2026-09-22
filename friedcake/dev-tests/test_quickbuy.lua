-- dev-tests/test_quickbuy.lua
--
-- Standalone smoke tests for smp_quickbuy: entry CRUD, live price lookup,
-- the 3x price guard, and the buy path — with the f03/f10/f14 bridges stubbed
-- to deterministic values. Covers f05 §9 T1–T7 logic without an engine.
--
-- Run: luajit friedcake/dev-tests/test_quickbuy.lua
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local function S_factory(_mod)
	return function(s, ...)
		local a = { ... }
		return (s:gsub("@(%d+)", function(n) return tostring(a[tonumber(n)] or "") end))
	end
end

core = {
	get_translator = S_factory,
	get_current_modname = function() return "smp_quickbuy" end,
	log = function() end,
	chat_send_player = function() end,
}

-- In-memory player records (enough of smp_store for the modules under test).
local records = {}
smp_store = { api = {} }
function smp_store.api.ensure_player(name)
	if not records[name] then records[name] = { name = name, money = 0, quickbuy = {} } end
	return records[name]
end
function smp_store.api.get_player(name) return records[name] end
function smp_store.api.upsert_player(rec) records[rec.name] = rec end

smp_quickbuy = { cfg = { price_guard = 3.0, max_entries = 45, page_size = 45 } }

local modpath = "/Volumes/Dara/dev/coconut/friedcake/mods/smp_quickbuy"
dofile(modpath .. "/bridges.lua")
dofile(modpath .. "/entries.lua")
dofile(modpath .. "/price.lua")
dofile(modpath .. "/buy.lua")

----------------------------------------------------------------------
-- Deterministic auction-house fake (the f03 bridge, stubbed)
----------------------------------------------------------------------

local function ench_key(ench)
	local parts = {}
	for id, lvl in pairs(ench or {}) do parts[#parts + 1] = id .. "=" .. tostring(lvl) end
	table.sort(parts)
	return table.concat(parts, ",")
end

local auction = { listings = {}, force_fail = nil }

function auction.reset(listings)
	auction.listings = {}
	for _, l in ipairs(listings or {}) do
		auction.listings[#auction.listings + 1] = {
			key = l.key, ench = l.ench or {}, id = l.id, version = l.version or 1,
			count = l.count or 1, price = l.price, state = "active",
		}
	end
	auction.force_fail = nil
end

function auction.cheapest_for(key, ench, qty)
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

function auction.buy(player, id, version)
	local name = player:get_player_name()
	if auction.force_fail == id then return nil end
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

-- Wire the bridges to the fake.
smp_quickbuy.au.cheapest_for = function(key, ench, qty) return auction.cheapest_for(key, ench, qty) end
smp_quickbuy.au.buy = function(player, id, version) return auction.buy(player, id, version) end
smp_quickbuy.combat.is_tagged = function(player) return player.tagged and true or false end
smp_quickbuy.stats.add = function(player, key, value)
	local rec = smp_store.api.ensure_player(player:get_player_name())
	rec.stats = rec.stats or {}
	rec.stats[key] = (rec.stats[key] or 0) + value
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function make_player(name)
	local p = { name = name, tagged = false }
	p.get_player_name = function() return name end
	return p
end

local function seed_money(name, cents)
	smp_store.api.ensure_player(name).money = cents
end

local function entry_of(pname, idx)
	return smp_quickbuy.entries.get(pname, idx)
end

local function stats_of(name, key)
	local r = smp_store.api.get_player(name)
	return r and r.stats and r.stats[key] or 0
end

local function eq(a, b, msg)
	if a ~= b then
		error(string.format("FAIL %s: expected %s got %s", msg, tostring(b), tostring(a)), 2)
	end
end

local function yes(cond, msg)
	if not cond then error("FAIL " .. msg, 2) end
end

local function no(cond, msg)
	if cond then error("FAIL " .. msg .. " (expected falsy)", 2) end
end

----------------------------------------------------------------------
-- Entries CRUD
----------------------------------------------------------------------

local alice = make_player("alice")
local alice_name = "alice"
smp_store.api.ensure_player(alice_name).quickbuy = {}

yes(smp_quickbuy.entries.add(alice_name, { key = "mcl_core:diamond", ench = {}, qty = 64 }),
	"add entry succeeds")
eq(smp_quickbuy.entries.count(alice_name), 1, "one entry after add")
eq(entry_of(alice_name, 1).key, "mcl_core:diamond", "entry key stored")
eq(entry_of(alice_name, 1).qty, 64, "entry qty stored")

yes(smp_quickbuy.entries.set(alice_name, 1, { key = "mcl_core:diamond", ench = {}, qty = 32 }),
	"set entry succeeds")
eq(entry_of(alice_name, 1).qty, 32, "entry qty updated")

local removed = smp_quickbuy.entries.remove(alice_name, 1)
eq(removed.key, "mcl_core:diamond", "remove returns entry")
eq(smp_quickbuy.entries.count(alice_name), 0, "entry list empty after remove")

-- capacity: max_entries = 45 (PROPOSED)
for i = 1, 45 do
	smp_quickbuy.entries.add(alice_name, { key = "mcl_core:dirt", ench = {}, qty = 1 })
end
eq(smp_quickbuy.entries.count(alice_name), 45, "45 entries allowed")
local ok46 = smp_quickbuy.entries.add(alice_name, { key = "mcl_core:stone", ench = {}, qty = 1 })
no(ok46, "46th entry refused (max_entries)")

-- reset
smp_store.api.ensure_player(alice_name).quickbuy = {}
smp_store.api.ensure_player(alice_name).stats = {}

----------------------------------------------------------------------
-- T1: live price lookup and update on redraw
----------------------------------------------------------------------

auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 100 },
	{ key = "mcl_core:diamond", ench = {}, id = 2, count = 1, price = 300 },
})
local price = smp_quickbuy.price.lookup("mcl_core:diamond", {}, 2)
eq(price, 400, "T1 lowest two listings cost 400 (100 + 300)")

-- Redraw simulation: a cheaper listing appears; the lookup must change.
auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 100 },
	{ key = "mcl_core:diamond", ench = {}, id = 2, count = 1, price = 300 },
	{ key = "mcl_core:diamond", ench = {}, id = 3, count = 1, price = 10 },
})
price = smp_quickbuy.price.lookup("mcl_core:diamond", {}, 2)
eq(price, 110, "T1 price updates on redraw (10 + 100)")

no(smp_quickbuy.price.lookup("mcl_core:diamond", {}, 999), "T1 insufficient listings -> nil")

----------------------------------------------------------------------
-- T2/T3: the 3x guard (boundary: 3, not 2 or 4)
----------------------------------------------------------------------

eq(smp_quickbuy.price.within_guard(100, 300), true,  "T3 boundary: 300 == 3x shown, allowed")
eq(smp_quickbuy.price.within_guard(100, 301), false, "T3 boundary: 301 > 3x shown, warn")
eq(smp_quickbuy.price.within_guard(100, 299), true,  "T3 boundary: 299 < 3x shown, allowed")
eq(smp_quickbuy.price.within_guard(100, 200), true,  "T3 2x is allowed (guard is 3, not 2)")
eq(smp_quickbuy.price.within_guard(100, 400), false, "T3 4x warns (guard is 3, not 4)")

-- T2: within the guard, a purchase completes without confirmation.
auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 100 },
})
smp_quickbuy.entries.add(alice_name, { key = "mcl_core:diamond", ench = {}, qty = 1 })
seed_money(alice_name, 1000)
alice.tagged = false

local r, spent, bought = smp_quickbuy.buy.entry(alice, 1, 100, false)
eq(r, true, "T2 within-guard purchase succeeds")
eq(spent, 100, "T2 spent 100")
eq(smp_store.api.get_player(alice_name).money, 900, "T2 buyer debited 100")

-- T3: above 3x shown, the purchase warns, then completes after re-confirm.
auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 400 },
})
seed_money(alice_name, 1000)
local wr, wi, ws, wc = smp_quickbuy.buy.entry(alice, 1, 100, false)
eq(wr, "warn", "T3 above-guard purchase returns warn")
eq(wi, 1, "T3 warn carries the entry index")
eq(wc, 400, "T3 warn carries the live cost")
eq(smp_store.api.get_player(alice_name).money, 1000, "T3 nothing charged before re-confirm")

local rr, rspent = smp_quickbuy.buy.entry(alice, 1, 100, true)
eq(rr, true, "T3 re-confirmed purchase succeeds")
eq(rspent, 400, "T3 re-confirmed spent 400")
eq(smp_store.api.get_player(alice_name).money, 600, "T3 buyer debited 400 after confirm")

----------------------------------------------------------------------
-- T4: enchantment-exact matching
----------------------------------------------------------------------

auction.reset({
	{ key = "mcl_tools:sword_netherite", ench = { sharpness = 4 }, id = 10, count = 1, price = 100 },
})
smp_quickbuy.entries.add(alice_name, { key = "mcl_tools:sword_netherite", ench = { sharpness = 5 }, qty = 1 })
no(smp_quickbuy.price.lookup("mcl_tools:sword_netherite", { sharpness = 5 }, 1),
	"T4 Sharpness IV listing does not fill a Sharpness V entry")

seed_money(alice_name, 1000)
local t4r, t4m = smp_quickbuy.buy.entry(alice, 2, 100, false)
no(t4r, "T4 Sharpness IV listing does not satisfy Sharpness V entry")

-- a matching Sharpness V listing does satisfy it
auction.reset({
	{ key = "mcl_tools:sword_netherite", ench = { sharpness = 5 }, id = 11, count = 1, price = 100 },
})
local t4p = smp_quickbuy.price.lookup("mcl_tools:sword_netherite", { sharpness = 5 }, 1)
eq(t4p, 100, "T4 Sharpness V listing fills the Sharpness V entry")

----------------------------------------------------------------------
-- T5: combat refusal
----------------------------------------------------------------------

auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 100 },
})
seed_money(alice_name, 1000)
alice.tagged = true
local t5r = smp_quickbuy.buy.entry(alice, 1, 100, false)
no(t5r, "T5 combat-tagged purchase refused")
eq(smp_store.api.get_player(alice_name).money, 1000, "T5 nothing charged while tagged")
alice.tagged = false

----------------------------------------------------------------------
-- T6: money_spent_on_shop increments by exactly the amount paid
----------------------------------------------------------------------

auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 1, count = 1, price = 250 },
})
seed_money(alice_name, 10000)
smp_store.api.ensure_player(alice_name).stats = {}
local t6r, t6spent = smp_quickbuy.buy.entry(alice, 1, 250, false)
eq(t6r, true, "T6 purchase succeeds")
eq(t6spent, 250, "T6 spent 250")
eq(stats_of(alice_name, "money_spent_on_shop"), 250, "T6 stat incremented by exactly 250")

----------------------------------------------------------------------
-- T7: a listing bought out from under the purchase is not charged
----------------------------------------------------------------------

-- Two listings fill qty 2; the cheaper one is raced mid-purchase.
auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 100, count = 1, price = 100 },
	{ key = "mcl_core:diamond", ench = {}, id = 200, count = 1, price = 200 },
})
smp_quickbuy.entries.set(alice_name, 1, { key = "mcl_core:diamond", ench = {}, qty = 2 })
seed_money(alice_name, 10000)
smp_store.api.ensure_player(alice_name).stats = {}

auction.force_fail = 100   -- the 100-cent listing was bought out from under us
local t7r, t7spent, t7bought = smp_quickbuy.buy.entry(alice, 1, 300, false)
eq(t7r, true, "T7 partial purchase still succeeds")
eq(t7bought, 1, "T7 only one of two listings bought")
eq(t7spent, 200, "T7 charged only the listing that succeeded (200, not 300)")
eq(smp_store.api.get_player(alice_name).money, 9800, "T7 buyer debited 200, not 300")
eq(stats_of(alice_name, "money_spent_on_shop"), 200, "T7 stat reflects only the amount paid")

-- And if EVERY listing is raced, nothing is charged and the buy is refused.
auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 100, count = 1, price = 100 },
})
seed_money(alice_name, 10000)
smp_store.api.ensure_player(alice_name).stats = {}
auction.force_fail = 100
local t7all = smp_quickbuy.buy.entry(alice, 1, 100, false)
no(t7all, "T7 all-raced purchase refused")
eq(smp_store.api.get_player(alice_name).money, 10000, "T7 nothing charged when every listing raced")

print("ALL OK")
