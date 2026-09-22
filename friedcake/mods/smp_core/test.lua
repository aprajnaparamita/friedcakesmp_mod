-- FriedcakeSMP — smp_core acceptance tests
-- Loaded by `/smp test smp_core` in-game. Can also be run as plain Lua with
-- a tiny core stub (see the smoke test in the repo).
--
-- Tests cover spec/features/f01-economy-core.md §9 T1, T2, T3.
-- Future feature mods add their own test files and register them under
-- their mod path; /smp test discovers them.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator and core.get_translator("smp_core")
	or function(s, ...) return s end

local results = { passed = 0, failed = 0, lines = {} }

local function eq(a, b, msg)
	if a == b then
		results.passed = results.passed + 1
		return true
	end
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] =
		string.format("FAIL %s: expected %q got %q",
			msg or "eq", tostring(b), tostring(a))
	return false
end

local function yes(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "true")
	end
end

-- T1: fmt_money spacing rules.
eq(smp_core.fmt_money(70000, "body"),     "$ 700",   "T1 body $700")
eq(smp_core.fmt_money(70000, "inline"),   "$700",    "T1 inline $700")
eq(smp_core.fmt_money(510000, "body"),    "$ 5.1K",  "T1 body $ 5.1K")
eq(smp_core.fmt_money(3000000, "body"),   "$ 30K",   "T1 body $ 30K")
eq(smp_core.fmt_money(900000, "body"),    "$ 9K",    "T1 body $ 9K")
eq(smp_core.fmt_money(2500000, "body"),   "$ 25K",   "T1 body $ 25K")
eq(smp_core.fmt_money(18200000, "body"),  "$ 182K",  "T1 body $ 182K")
eq(smp_core.fmt_money(400000000, "body"), "$ 4M",    "T1 body $ 4M")
eq(smp_core.fmt_money(100, "inline"),     "$1",      "T1 inline $1")
eq(smp_core.fmt_money(3000000, "inline"), "$30K",    "T1 inline $30K")

-- T2: fmt_qty lower-case suffixes.
eq(smp_core.fmt_qty(753000),  "753k", "T2 753k")
eq(smp_core.fmt_qty(1300000), "1.3m", "T2 1.3m")
eq(smp_core.fmt_qty(167000),  "167k", "T2 167k")
eq(smp_core.fmt_qty(200000),  "200k", "T2 200k")

-- T3: parse_amount.
local c
c = smp_core.parse_amount("250k");  eq(c, 25000000,  "T3 250k")
c = smp_core.parse_amount("1.5M");  eq(c, 150000000, "T3 1.5M")
c = smp_core.parse_amount("10");    eq(c, 1000,      "T3 10")
c = smp_core.parse_amount("10.50"); eq(c, 1050,      "T3 10.50")
yes(smp_core.parse_amount("-1")    == nil, "T3 reject -1")
yes(smp_core.parse_amount("nan")   == nil, "T3 reject nan")
yes(smp_core.parse_amount("inf")   == nil, "T3 reject inf")
yes(smp_core.parse_amount("1e400") == nil, "T3 reject 1e400")
yes(smp_core.parse_amount("")      == nil, "T3 reject empty")
yes(smp_core.parse_amount("abc")   == nil, "T3 reject abc")

-- Session API smoke (open / get / close).
local fake_player = "__test_player"
local s = smp_core.open_session(fake_player, "test:fs", { x = 1 })
eq(s.x, 1, "session initial state")
local s2 = smp_core.get_session(fake_player, "test:fs")
eq(s, s2, "session identity preserved")
smp_core.close_session(fake_player, "test:fs")
local s3 = smp_core.get_session(fake_player, "test:fs")
eq(s3, nil, "session closed")

return results
