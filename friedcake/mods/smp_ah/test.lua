-- FriedcakeSMP — smp_ah acceptance tests (in-game)
--
-- Loaded by `/smp test smp_ah` (smp_ah.run_tests). Returns
-- `{ passed, failed, lines }` like smp_core/test.lua.
--
-- This is a smoke test of the f03 §9 surface that is safe to run against a
-- live server: it asserts the observed strings verbatim, the M1/M2 keying
-- (shared §2.5) and the listing record shape, and that a purchase re-validates
-- its version. The full headless T1–T10 matrix lives in
-- dev-tests/test_ah.lua; everything here uses a reserved seller name and
-- cleans up after itself.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname() or "smp_ah")

local results = { passed = 0, failed = 0, lines = {} }

local function fail(msg)
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] = "FAIL " .. tostring(msg)
end

local function eq(a, b, msg)
	if a == b then
		results.passed = results.passed + 1
		return true
	end
	fail(string.format("%s: expected %s got %s", tostring(msg), tostring(b), tostring(a)))
	return false
end

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		fail(msg)
	end
	return cond and true or false
end

local function has(text, sub, msg)
	return ok(type(text) == "string" and text:find(sub, 1, true) ~= nil,
		msg .. " [missing: " .. tostring(sub) .. "]")
end

local keys = smp_ah.keys
local listings = smp_ah.listings
local TEST = "__smp_ah_test"

----------------------------------------------------------------------
-- T1/T2: the board renders the observed strings verbatim
----------------------------------------------------------------------

do
	local fs = smp_ah.fs.board({ page = 1, pages = 1, items = {},
		sort = "lowest_price", total = 0 })
	has(fs, "Auction (Page 1)", "T1 board title")
	has(fs, "Search", "T2 Search tooltip line 1")
	has(fs, "Click to search", "T2 Search tooltip line 2")
	has(fs, "Filter", "T2 Filter tooltip line 1")
	has(fs, "Click to change", "T2 Filter tooltip line 2")
	has(fs, "Lowest Price", "T2 the sort option list")
	has(fs, "Highest Price", "T2 the sort option list (2)")
	has(fs, "Recently Listed", "T2 the sort option list (3)")
	has(fs, "Your Items", "T2 Your Items tooltip line 1")
	has(fs, "Click to view", "T2 Your Items tooltip line 2")
	ok(fs:find("component%(s%)") == nil, "T2 the Java component line is dropped")
	has(smp_ah.fs.your_items({ page = 1, pages = 1, items = {} }),
		"Auction > Your Items", "the `Your Items` title uses `>` (shared §4.2)")
	has(smp_ah.fs.search(""), "Search Auction", "the search prompt title")
	has(smp_ah.fs.search(""), "Cancel", "the search prompt has a Cancel button")
	has(smp_ah.fs.price(""), "Edit Sign Message", "the price prompt keeps the sign-editor title")
	has(smp_ah.fs.price(""), "Type price", "the price prompt keeps the placeholder")
	has(smp_ah.fs.price(""), "Done", "the price prompt keeps the Done button")
end

----------------------------------------------------------------------
-- Keys (shared §2.5, the slice f03 owns)
----------------------------------------------------------------------

do
	local plain = ItemStack("mcl_core:diamond 64")
	local worn  = ItemStack("mcl_tools:shovel_diamond 1")
	worn:set_wear(1)
	ok(keys.key(plain, "M1") ~= nil, "keys: a plain stack has an M1 key")
	eq(keys.key(worn, "M1"), nil, "keys: a worn stack has no M1 key")
	eq(keys.key(ItemStack(""), "M2"), nil, "keys: an empty stack has no key")
	ok(keys.matches(plain, keys.key(plain, "M1"), "M1"), "keys: matches() agrees with key()")
	ok(keys.key(plain, "M2") ~= keys.key(worn, "M2"), "keys: M2 distinguishes wear")
end

----------------------------------------------------------------------
-- Config: ah.sorts parsing and Filter tooltip (A3)
----------------------------------------------------------------------

do
	-- Default sorts order
	eq(smp_ah.cfg.sorts[1], "lowest_price", "cfg.sorts default first")
	eq(smp_ah.cfg.sorts[2], "highest_price", "cfg.sorts default second")
	eq(smp_ah.cfg.sorts[3], "recently_listed", "cfg.sorts default third")
	-- listings.SORTS reflects config
	eq(listings.SORTS[1], "lowest_price", "listings.SORTS default first")
	eq(listings.SORTS[2], "highest_price", "listings.SORTS default second")
	eq(listings.SORTS[3], "recently_listed", "listings.SORTS default third")
	-- Filter tooltip includes all three in order
	local board_fs = smp_ah.fs.board({ page = 1, pages = 1, items = {},
		sort = "lowest_price", total = 0 })
	has(board_fs, "Lowest Price", "Filter tooltip has Lowest Price")
	has(board_fs, "Highest Price", "Filter tooltip has Highest Price")
	has(board_fs, "Recently Listed", "Filter tooltip has Recently Listed")
end

----------------------------------------------------------------------
-- Config: ah.history and legacy aliases (A4)
----------------------------------------------------------------------

do
	local hp = listings.config().history_page
	local hps = listings.config().history_pages
	eq(hp, 100, "default history_page = 100")
	eq(hps, 10, "default history_pages = 10")
	local cap = hp * hps
	eq(cap, 1000, "history cap = per_page * pages")
end

----------------------------------------------------------------------
-- T5 record shape (create_listing needs no online player)
----------------------------------------------------------------------

local rec, err = smp_ah.create_listing(TEST, ItemStack("mcl_core:diamond 16"), 900000)
ok(rec ~= nil, "T5 a listing can be created via the public API (" .. tostring(err) .. ")")
if rec then
	eq(rec.price, 900000, "T5 the price is integer cents (total for the stack)")
	eq(rec.count, 16, "T5 the stack count is recorded")
	eq(rec.unit_price, math.floor(900000 / 16), "T5 the unit price is derived and floored")
	eq(rec.state, "active", "T5 the listing is active")
	eq(rec.version, 1, "T5 version starts at 1")
	eq(rec.key, keys.key(ItemStack(rec.stack), "M2"), "T5 the record carries its M2 key")
end

----------------------------------------------------------------------
-- T6/T9: purchase re-validates the version before anything else
----------------------------------------------------------------------

if rec then
	-- A forged/stale version is refused (the check precedes any player or
	-- money lookup, so this is safe even for a caller who is not a buyer).
	local lost, reason = smp_ah.buy(TEST .. "_nobody", rec.id, 999)
	eq(lost, nil, "T9 a forged version is refused")
	eq(reason, "already_bought", "T9 with the race reason")
	eq(listings.get(rec.id).state, "active", "T9 and the listing is untouched")
end

----------------------------------------------------------------------
-- Verbatim chat strings (shared §8.6)
----------------------------------------------------------------------

eq(S("You bought @1 @2 for $ @3", 1, "Ender Chest", "5.1K"),
	"You bought 1 Ender Chest for $ 5.1K", "the purchase line renders verbatim [F0055]")
eq(S("This item was already bought"),
	"This item was already bought", "the race-loss string is verbatim [F0037]")
eq(S("You're going to sell this item for $@1", "1"),
	"You're going to sell this item for $1", "the confirm tooltip renders verbatim [F0142]")

----------------------------------------------------------------------
-- A2: Confirm Listing renders Match lowest; activates and rewrites draft price
----------------------------------------------------------------------

do
	-- Create a listing to match against
	local match_rec = smp_ah.create_listing("match_seller", ItemStack("mcl_core:stone 10"), 5000)
	ok(match_rec ~= nil, "A2 match listing created")
	-- Open a flow with a stack of the same item
	local bob = "__smp_ah_test_bob"
	smp_ah._flows[bob] = { stage = "confirm", stack = ItemStack("mcl_core:stone 5"), price = 10000 }
	-- Check confirm_listing formspec has Match lowest button
	local confirm_fs = smp_ah.fs.confirm_listing({ name = "mcl_core:stone", count = 5,
		display = { name = "Stone" } }, 10000)
	has(confirm_fs, "Match lowest", "A2 Confirm Listing has Match lowest button")
	has(confirm_fs, "Click to match lowest price", "A2 Match lowest has tooltip")
	-- Simulate the match_lowest field handler
	local v = smp_core.get_session(bob, "smp_ah:view")
	if not v then v = smp_core.open_session(bob, "smp_ah:view", { view = "confirm_listing", formname = "smp_ah:confirm_listing" }) end
	v.view = "confirm_listing"
	v.formname = "smp_ah:confirm_listing"
	smp_ah.handle_fields(bob, "smp_ah:confirm_listing", { ah_match_lowest = "" })
	-- Price should be rewritten to match_rec.unit_price * 5 = 500 * 5 = 2500
	local f = smp_ah._flows[bob]
	ok(f and f.price == 2500, "A2 Match lowest rewrites draft price to 2500 (got " .. tostring(f and f.price) .. ")")
	-- Clean up
	if match_rec then listings.purge(match_rec.id) end
	smp_ah._flows[bob] = nil
end

----------------------------------------------------------------------
-- A1-adjacent: harness registers globalstep under core.register_globalstep
----------------------------------------------------------------------

do
	ok(type(core.register_globalstep) == "function", "A1 core.register_globalstep exists")
	ok(type(core.register_on_globalstep) ~= "function", "A1 no register_on_globalstep")
end

----------------------------------------------------------------------
-- S3/AH-2: the public entry points refuse a non-string player name
----------------------------------------------------------------------

do
	local rec = smp_ah.create_listing(TEST, ItemStack("mcl_core:cobble 1"), 100)
	ok(rec ~= nil, "AH-2 setup listing created")

	-- What `register_on_player_receive_fields` passes as `name`: an
	-- ObjectRef, not a string. The engine's own APIs raise on it, so the
	-- mod has to refuse before it ever reaches one (MS-3).
	local objref = {}
	ok(not pcall(core.get_player_by_name, objref),
		"AH-2 get_player_by_name(ObjectRef) raises like luaL_checkstring")
	ok(not pcall(core.chat_send_player, objref, "hi"),
		"AH-2 chat_send_player(ObjectRef) raises like luaL_checkstring")

	local r, e = smp_ah.buy(objref, rec.id, nil)
	eq(r, nil, "AH-2 buy(ObjectRef) is refused")
	eq(e, "offline", "AH-2 buy(ObjectRef) with the offline reason")

	local r2, e2 = smp_ah.withdraw(objref, rec.id)
	eq(r2, nil, "AH-2 withdraw(ObjectRef) is refused")
	eq(e2, "offline", "AH-2 withdraw(ObjectRef) with the offline reason")

	local r3, e3 = smp_ah.create_listing(objref, ItemStack("mcl_core:cobble 1"), 100)
	eq(r3, nil, "AH-2 create_listing(ObjectRef) is refused")
	eq(e3, "offline", "AH-2 create_listing(ObjectRef) with the offline reason")

	eq(select(2, smp_ah.buy(nil, rec.id, nil)), "offline", "AH-2 buy(nil) refuses")
	eq(select(2, smp_ah.buy("", rec.id, nil)), "offline", "AH-2 buy(\"\") refuses")

	-- Nothing was mutated by the refusals.
	eq(listings.get(rec.id).state, "active", "AH-2 the listing is untouched")
	listings.purge(rec.id)
end

----------------------------------------------------------------------
-- Cleanup: leave the store as we found it.
----------------------------------------------------------------------

for _, l in ipairs(listings.for_seller(TEST)) do
	listings.purge(l.id)
end
smp_store.api.set_money(TEST, 0, "test", "smp_ah test cleanup")

results.lines[#results.lines + 1] = string.format("smp_ah: %d passed, %d failed",
	results.passed, results.failed)
return results
