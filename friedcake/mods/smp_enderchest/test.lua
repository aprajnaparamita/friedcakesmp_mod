-- FriedcakeSMP — smp_enderchest acceptance tests
-- Loaded by `/smp test smp_enderchest` in-game (once the generic test
-- registry lands). Returns {passed, failed, lines}.
--
-- Covers what is safely re-runnable on a live server: the capacity
-- contract (54 slots, 9x6), the double-chest formspec geometry, the
-- formname substitution and the help-text upgrade. The join/migration
-- and reach-rule paths run in the standalone harness
-- friedcake/dev-tests/test_enderchest.lua.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "assertion")
	end
end
local function eq(a, b, msg)
	ok(a == b, string.format("%s: expected %q got %q",
		msg or "eq", tostring(b), tostring(a)))
end

local E = smp_enderchest
local LIST = E.LIST

----------------------------------------------------------------------
-- T1 — capacity: 9 columns x 6 rows = 54 slots (twice a normal chest)
----------------------------------------------------------------------

eq(E.COLS, 9, "T1 nine columns")
eq(E.ROWS, 6, "T1 six rows")
eq(E.SLOTS, 54, "T1 capacity is 54 slots")
eq(E.COLS * E.ROWS, E.SLOTS, "T1 SLOTS = COLS * ROWS")
eq(LIST, "smp_enderchest", "T1 storage list name")

----------------------------------------------------------------------
-- T2 — formspec: double-chest geometry, our 9x6 list, engine list gone
----------------------------------------------------------------------

local fs = E.formspec()
ok(fs:find("formspec_version[4]", 1, true), "T2 formspec version 4")
ok(fs:find("size[11.75,14.15]", 1, true),
	"T2 size matches mcl_chests' double chest")
ok(fs:find("list[current_player;" .. LIST .. ";0.375,0.75;9,6;]", 1, true),
	"T2 9x6 ender list at 0.375,0.75")
ok(fs:find("list[current_player;main;0.375,8.825;9,3;9]", 1, true),
	"T2 main rows under the container")
ok(fs:find("list[current_player;main;0.375,12.775;9,1;]", 1, true),
	"T2 hotbar row last")
ok(not fs:find("current_player;enderchest;", 1, true),
	"T2 engine 27-slot list is not referenced")
local ri = fs:find("listring[current_player;" .. LIST .. "]", 1, true)
local rm = fs:find("listring[current_player;main]", 1, true)
ok(ri and rm and ri < rm, "T2 listring cycles ender list into main")
ok(fs:find("Ender Chest", 1, true), "T2 title is Ender Chest")
ok(fs:find("Inventory", 1, true), "T2 Inventory label present")

----------------------------------------------------------------------
-- T3 — formname substitution: only the ender-chest formname swaps
----------------------------------------------------------------------

eq(E.intercept("mcl_chests:ender_chest_Alice", "stock 9x3"), fs,
	"T3 ender formname replaced with the 9x6 formspec")
eq(E.intercept("mcl_chests:ender_chest_", "stock"), fs,
	"T3 bare ender prefix replaced")
eq(E.intercept("mcl_chests:chest_1_2_3", "keep"), "keep",
	"T3 double chest untouched")
eq(E.intercept("mcl_chests:trapped_chest_1_2_3", "keep"), "keep",
	"T3 trapped chest untouched")
eq(E.intercept("smp_quickbuy:main", "keep"), "keep",
	"T3 other mods' formspecs untouched")
eq(E.intercept(123, 123), 123, "T3 non-string formname passes through")

----------------------------------------------------------------------
-- T4 — help text: both ender-chest defs say 54, never 27
----------------------------------------------------------------------

for _, name in ipairs({ "mcl_chests:ender_chest", "mcl_chests:ender_chest_small" }) do
	local def = core.registered_nodes and core.registered_nodes[name]
	ok(def ~= nil, "T4 " .. name .. " is registered")
	if def then
		local tt = def._tt_help or ""
		ok(tt:find("54 interdimensional inventory slots", 1, true),
			"T4 " .. name .. " tooltip says 54 slots")
		ok(not tt:find("27", 1, true),
			"T4 " .. name .. " tooltip no longer says 27")
		ok((def._doc_items_longdesc or ""):find("54 slots", 1, true),
			"T4 " .. name .. " doc longdesc says 54 slots")
	end
end

----------------------------------------------------------------------
-- T5 — capacity invariant: a 9x6 grid holds exactly twice a 9x3 one
----------------------------------------------------------------------

eq(E.SLOTS, 9 * 3 * 2, "T5 capacity is exactly twice a normal chest")

return results
