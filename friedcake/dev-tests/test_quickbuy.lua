-- dev-tests/test_quickbuy.lua
--
-- Standalone smoke tests for smp_quickbuy: entry CRUD, live price lookup,
-- the 3x price guard, and the buy path — with the f03/f10/f14 mods faked
-- BEHIND the real bridge layer (smp_ah / smp_combat / smp_stats), so
-- bridges.lua itself is under test. Covers f05 §9 T1–T7 plus the S05/QB-1
-- regression without an engine.
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

-- Repo root from the script path, so this harness runs from a git
-- worktree checkout too (pattern: dev-tests/test_economy.lua). The old
-- hardcoded /Volumes/Dara/dev/coconut path silently tested a DIFFERENT
-- checkout than the one the agent edited.
local function find_root()
	local script = (arg and arg[0]) or ""
	local prefix = script:match("^(.-)friedcake/dev%-tests/[^/]*$")
	if prefix and prefix ~= "" then
		return (prefix:gsub("/+$", ""))
	end
	return "."
end

local ROOT = find_root()

-- In-memory player records (enough of smp_store for the modules under
-- test). Declared before the core stub: the strict get_player_by_name
-- below reads it.
local records = {}

local logs = {}     -- { level, msg } captured from core.log
local chats = {}    -- { name, msg } captured from core.chat_send_player

-- STRICT engine stubs (S05/QB-1). The real engine runs luaL_checkstring
-- on both of these calls (l_env.cpp:648 for get_player_by_name,
-- l_server.cpp:92 for chat_send_player) and RAISES when the first
-- argument is not a string. Quick Buy used to forward an ObjectRef, so
-- the raise escaped on_player_receive_fields and the server stopped.
-- These stubs must raise the same way, otherwise the regression test
-- below proves nothing.
core = {
	get_translator = S_factory,
	get_current_modname = function() return "smp_quickbuy" end,
	log = function(level, msg)
		logs[#logs + 1] = { level = level, msg = msg }
	end,
	chat_send_player = function(name, msg)
		if type(name) ~= "string" then
			error(string.format(
				"engine parity: core.chat_send_player expects a string name, got %s",
				type(name)), 2)
		end
		chats[#chats + 1] = { name = name, msg = msg }
	end,
	get_player_by_name = function(name)
		if type(name) ~= "string" then
			error(string.format(
				"engine parity: core.get_player_by_name expects a string name, got %s",
				type(name)), 2)
		end
		if not records[name] then return nil end
		return { get_player_name = function() return name end }
	end,
}

-- In-memory player records live above (strict get_player_by_name reads
-- them); smp_store is the tiny slice of the store the modules under test
-- need.
smp_store = { api = {} }
function smp_store.api.ensure_player(name)
	if not records[name] then records[name] = { name = name, money = 0, quickbuy = {} } end
	return records[name]
end
function smp_store.api.get_player(name) return records[name] end
function smp_store.api.upsert_player(rec) records[rec.name] = rec end

smp_quickbuy = { cfg = { price_guard = 3.0, max_entries = 45, page_size = 45 } }

local modpath = ROOT .. "/friedcake/mods/smp_quickbuy"
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

local auction = { listings = {}, force_fail = nil, raise_on = nil }

function auction.reset(listings)
	auction.listings = {}
	for _, l in ipairs(listings or {}) do
		auction.listings[#auction.listings + 1] = {
			key = l.key, ench = l.ench or {}, id = l.id, version = l.version or 1,
			count = l.count or 1, price = l.price, state = "active",
		}
	end
	auction.force_fail = nil
	auction.raise_on = nil
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

-- The AH fake takes a NAME, exactly like smp_ah.buy does.
function auction.buy(pname, id, version)
	if auction.raise_on == id then
		-- A pathological listing that blows up inside smp_ah.buy.
		error("smp_ah.buy exploded for listing " .. tostring(id))
	end
	if auction.force_fail == id then return nil end
	local l
	for _, x in ipairs(auction.listings) do if x.id == id then l = x end end
	if not l or l.state ~= "active" or l.version ~= version then return nil end
	local rec = smp_store.api.get_player(pname)
	if not rec or rec.money < l.price then return nil end
	rec.money = rec.money - l.price
	l.state = "sold"
	l.version = l.version + 1
	return { stack = {} }
end

----------------------------------------------------------------------
-- The REAL cross-mod globals the bridges delegate to.
--
-- S05/QB-1: this test used to overwrite smp_quickbuy.au.* directly,
-- which bypassed bridges.lua entirely — that is why the dev-tests passed
-- while the game shut the server down. The fakes now live behind
-- smp_ah / smp_combat / smp_stats, so the code under test includes
-- smp_quickbuy's own ObjectRef -> name normalisation, and smp_ah.buy is
-- written the way the shipped one is: strict about the player name and
-- calling the two engine APIs that raise on a non-string.
----------------------------------------------------------------------

local ah_names = {}   -- every pname smp_ah.buy was called with

smp_ah = {}
function smp_ah.cheapest_for(key, ench, qty)
	return auction.cheapest_for(key, ench, qty)
end
function smp_ah.buy(pname, id, version)
	-- Engine parity: the shipped smp_ah.buy(pname, …) takes a NAME.
	if type(pname) ~= "string" then
		error(string.format(
			"QB-1: smp_ah.buy expects a player name string, got %s",
			type(pname)), 2)
	end
	-- Both engine calls run luaL_checkstring (l_env.cpp:648,
	-- l_server.cpp:92) and raise on a non-string; the stub is strict too.
	core.get_player_by_name(pname)
	ah_names[#ah_names + 1] = { pname = pname, t = type(pname) }
	return auction.buy(pname, id, version)
end

smp_combat = {}
function smp_combat.is_tagged(player) return player.tagged and true or false end

local stats_names = {}   -- every name the QB-1b stats bridge forwarded
smp_stats = {}
function smp_stats.add(name, key, value)
	-- f14's smp_stats.name_of only accepts a string (or a plain table
	-- player); an ObjectRef here would silently drop the stat (QB-1b).
	if type(name) ~= "string" then
		error(string.format(
			"QB-1b: smp_stats.add expects a name string, got %s",
			type(name)), 2)
	end
	stats_names[#stats_names + 1] = name
	local rec = smp_store.api.ensure_player(name)
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

----------------------------------------------------------------------
-- S05/QB-1: the strict engine stub, and the ObjectRef -> name fix.
--
-- The shipped smp_ah.buy runs luaL_checkstring on its first argument
-- (core.get_player_by_name at smp_ah/init.lua:211, chat_send_player at
-- :203), so an ObjectRef RAISES. The stubs above are strict in the same
-- way; these cases prove the raise is what the old code hit, and that
-- the bridge no longer feeds it one.
----------------------------------------------------------------------

-- 1. Engine parity: both stubs raise on a non-string, like the engine.
no(pcall(core.get_player_by_name, alice),
	"QB-1 stub: core.get_player_by_name raises on an ObjectRef")
no(pcall(core.chat_send_player, alice, "hi"),
	"QB-1 stub: core.chat_send_player raises on an ObjectRef")

-- 2. A purchase driven with the ObjectRef (what on_player_receive_fields
--    hands the mod) succeeds end to end: the bridge forwards a string,
--    the AH takes the listing, cost_cents is charged, the item is bought.
auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 77, count = 1, price = 150 },
})
smp_quickbuy.entries.set(alice_name, 1,
	{ key = "mcl_core:diamond", ench = {}, qty = 1 })
seed_money(alice_name, 1000)
smp_store.api.ensure_player(alice_name).stats = {}
local n_before = #ah_names
local q1r, q1spent = smp_quickbuy.buy.entry(alice, 1, 150, false)
eq(q1r, true, "QB-1 purchase with an ObjectRef succeeds")
eq(q1spent, 150, "QB-1 charged cost_cents (150)")
eq(smp_store.api.get_player(alice_name).money, 850, "QB-1 buyer debited 150")
eq(#ah_names, n_before + 1, "QB-1 exactly one smp_ah.buy call")
eq(ah_names[#ah_names].t, "string", "QB-1 smp_ah.buy received a string name")
eq(ah_names[#ah_names].pname, alice_name, "QB-1 the buyer's name was forwarded")
eq(auction.listings[1].state, "sold", "QB-1 the listing was bought")
eq(stats_names[#stats_names], alice_name, "QB-1b stats.add received a name string")

-- 3. Refusals still talk to the player through the strict chat stub
--    (they pass a resolved name, never the ObjectRef).
smp_quickbuy.entries.remove(alice_name, 1)
no(smp_quickbuy.buy.entry(alice, 1, 100, false),
	"QB-1 a missing entry is refused without raising")

-- 4. The bridge accepts a plain name string too (the other form).
auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 900, count = 1, price = 50 },
})
seed_money(alice_name, 100)
yes(smp_quickbuy.au.buy(alice_name, 900, 1), "bridge accepts a name string")
eq(smp_quickbuy.au.buy({ no_getter = true }, 900, 1), nil,
	"bridge returns nil for a player it cannot resolve (no raise)")

-- 5. pcall isolation (buy.lua): one listing that RAISES inside the AH
--    is logged and skipped; the rest of the purchase still completes,
--    and only the successful listings are charged.
auction.reset({
	{ key = "mcl_core:diamond", ench = {}, id = 501, count = 1, price = 100 },
	{ key = "mcl_core:diamond", ench = {}, id = 502, count = 1, price = 200 },
})
smp_quickbuy.entries.set(alice_name, 1, { key = "mcl_core:diamond", ench = {}, qty = 2 })
seed_money(alice_name, 10000)
smp_store.api.ensure_player(alice_name).stats = {}
auction.raise_on = 501   -- the cheapest listing blows up first
local logs_before = #logs
local p1r, p1spent, p1bought = smp_quickbuy.buy.entry(alice, 1, 300, true)
eq(p1r, true, "QB-1 a raising listing does not abort the loop")
eq(p1bought, 1, "QB-1 the other listing was still bought")
eq(p1spent, 200, "QB-1 only the successful listing was charged (200)")
eq(smp_store.api.get_player(alice_name).money, 9800,
	"QB-1 nothing charged for the raising listing")
eq(stats_of(alice_name, "money_spent_on_shop"), 200,
	"QB-1 stat counts only what was paid")
local saw_error = false
for i = logs_before + 1, #logs do
	if logs[i].level == "error" and logs[i].msg:find("501", 1, true) then
		saw_error = true
	end
end
yes(saw_error, "QB-1 the raise is logged as an error, not fatal")

print("S05/QB-1 ok: strict stub, ObjectRef normalisation, pcall isolation")

print("ALL OK")
