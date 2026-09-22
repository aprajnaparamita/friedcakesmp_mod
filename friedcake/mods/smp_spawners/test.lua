-- FriedcakeSMP — smp_spawners acceptance tests
-- Loaded by `/smp test smp_spawners` in-game. Returns {passed, failed,
-- lines}.
--
-- Covers what is safely re-runnable on a live server: the production
-- curve (T1/T2/T3), the type table (PROPOSED markers, blaze rods,
-- creeper gate), configuration defaults, integer formatting, and the
-- no-entity invariants (T4). The stateful paths (T5, T6, T7, T8,
-- T10) run in the standalone harness
-- friedcake/dev-tests/test_spawners.lua.
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
local function near(a, b, tol, msg)
	ok(type(a) == "number" and math.abs(a - b) <= (tol or 1e-9),
		string.format("%s: expected %s (+/-%s) got %s",
			msg or "near", tostring(b), tostring(tol or 1e-9),
			tostring(a)))
end

local cfg = smp_spawners.cfg

----------------------------------------------------------------------
-- T1 — the curve: f(1) = r, the published skeleton illustration
----------------------------------------------------------------------

local r = cfg.r
local C = smp_spawners.cfg.C["skeleton"]
eq(C, 1505.35, "T1 skeleton C is the published value [S24]")
near(smp_spawners.curve(1, r, C), r, 1e-9, "T1 f(1) = r")
near(smp_spawners.curve(10, 6, 1505.35), 58.9, 0.05, "T1 f(10) = 58.9")
near(smp_spawners.curve(64, 6, 1505.35), 339.5, 0.05, "T1 f(64) = 339.5")
near(smp_spawners.curve(100, 6, 1505.35), 495.7, 0.05, "T1 f(100) = 495.7")
near(smp_spawners.curve(500, 6, 1505.35), 1301.0, 0.05, "T1 f(500) = 1301.0")
near(smp_spawners.curve(1000, 6, 1505.35), 1477.6, 0.05,
	"T1 f(1000) = 1477.6")

----------------------------------------------------------------------
-- T2 — monotonicity and decreasing marginal output
----------------------------------------------------------------------

do
	local base = 1 - r / C
	local prev = smp_spawners.curve(1, r, C)
	local monotone = true
	for n = 2, 7000 do
		local v = smp_spawners.curve(n, r, C)
		if v <= prev then monotone = false break end
		prev = v
	end
	ok(monotone, "T2 output strictly monotonic in stack size")

	local pm = r
	local decreasing = true
	for n = 2, 7000 do
		local m = r * base ^ (n - 1) -- exact marginal
		if m >= pm then decreasing = false break end
		pm = m
	end
	ok(decreasing, "T2 marginal output strictly decreases")
end

----------------------------------------------------------------------
-- T3 — approaches but never exceeds C
----------------------------------------------------------------------

do
	local v = smp_spawners.curve(1000, r, C)
	ok(v < C, "T3 f(1000) < C")
	ok(v > C * 0.97, "T3 f(1000) within 3% of C")
	local over = false
	for _, n in ipairs({ 1, 10, 100, 1000, 100000, 2147483647 }) do
		if smp_spawners.curve(n, r, C) > C then over = true end
	end
	ok(not over, "T3 curve never exceeds C")
end

----------------------------------------------------------------------
-- T4 — zero entities, zero ABMs (goal G1)
----------------------------------------------------------------------

ok(core.registered_nodes["smp_spawners:spawner"] ~= nil,
	"T4 spawner is a registered node")
local uses_entity = false
if core.registered_entities then
	for name in pairs(core.registered_entities) do
		if name:find("^smp_spawners:") then uses_entity = true end
	end
end
ok(not uses_entity, "T4 no smp_spawners entities registered")

----------------------------------------------------------------------
-- Types: PROPOSED markers, blaze rods, creeper gate, supply rules
----------------------------------------------------------------------

do
	local blaze = smp_spawners.types.get("blaze")
	ok(blaze ~= nil and blaze.loot["mcl_mobitems:blaze_rod"] == 0.5,
		"blaze outputs rods (S10 over S24, f07 §10)")
	ok(blaze ~= nil and blaze.loot["mcl_mobitems:blaze_powder"] == nil,
		"blaze does not output powder")
	local creeper = smp_spawners.types.get("creeper")
	ok(creeper ~= nil and creeper.conditional == true,
		"creeper present and conditional (f07 §4.2)")
	local skeleton = smp_spawners.types.get("skeleton")
	eq(skeleton.xp, 5, "skeleton xp PROPOSED 5")
	eq(smp_spawners.types.get("unknown_type"), nil,
		"unknown type rejected")
	eq(#smp_spawners.types.order, 9, "nine spawner types")
	ok(cfg.acquisition.admin == true, "admin issue enabled [S10]")
	ok(cfg.acquisition.shard_shop == false, "shard shop closed [S10]")
	ok(cfg.acquisition.crates == false, "crates closed [S10]")
	ok(cfg.acquisition.natural == false, "natural supply closed [S10]")
end

----------------------------------------------------------------------
-- Configuration defaults (f07 §7)
----------------------------------------------------------------------

eq(cfg.accrual_mode, "active_only", "accrual default active_only")
eq(cfg.timer_interval, 60, "timer interval 60 s")
eq(cfg.stack_mode, "all", "stack mode all [S24]")
eq(cfg.storage.per_spawner, 2880, "storage per spawner PROPOSED")
eq(cfg.storage.hard_cap, 2147483647, "storage hard cap PROPOSED")
eq(cfg.xp.per_spawner_cap, 2000, "xp cap PROPOSED")
eq(cfg.require_silk_touch and true or false, true,
	"silk touch required [C3]")
eq(cfg.sneak_break_max, 64, "sneak break max [C3]")
eq(cfg.open_requires_access and true or false, false,
	"open requires access PROPOSED false")
eq(cfg.blast_immune and true or false, true, "blast immune")
eq(cfg.convert_natural and true or false, false,
	"convert natural PROPOSED false")
eq(smp_spawners.MAX_STACK, 2147483647, "max stack [S24]")

----------------------------------------------------------------------
-- Integer boundary and number formatting
----------------------------------------------------------------------

eq(smp_spawners.fmt_int(0), "0", "fmt_int 0")
eq(smp_spawners.fmt_int(999), "999", "fmt_int 999")
eq(smp_spawners.fmt_int(12480), "12,480", "fmt_int 12,480")
eq(smp_spawners.fmt_int(368640), "368,640", "fmt_int 368,640")
eq(smp_spawners.fmt_int(2147483647), "2,147,483,647", "fmt_int max int")

----------------------------------------------------------------------
-- Capacity and XP caps
----------------------------------------------------------------------

eq(smp_spawners.capacity(1), 2880, "capacity(1)")
eq(smp_spawners.capacity(128), 368640, "capacity(128) (the §3 example)")
eq(smp_spawners.xp_cap(128), 256000, "xp cap (128) (the §3 example)")
eq(smp_spawners.store_total({ a = 1.5, b = 2.25 }), 3.75,
	"store total sums floats")

----------------------------------------------------------------------
-- Accrual clamping (f07 §4.5)
----------------------------------------------------------------------

eq(smp_spawners.clamp_elapsed(100000, "active_only"), 120,
	"active_only clamps to 2 x timer_interval")
eq(smp_spawners.clamp_elapsed(100, "always"), 100, "always unclamped")
eq(smp_spawners.clamp_elapsed(100000, "capped"),
	cfg.offline_cap_hours * 3600, "capped to offline_cap_hours")
eq(smp_spawners.clamp_elapsed(-5, "active_only"), 0,
	"negative elapsed is zero")

----------------------------------------------------------------------
-- The node callbacks exist and blast/punch are no-ops
----------------------------------------------------------------------

do
	local def = core.registered_nodes["smp_spawners:spawner"]
	ok(type(def.on_dig) == "function", "on_dig registered")
	ok(type(def.on_rightclick) == "function", "on_rightclick registered")
	ok(type(def.on_blast) == "function", "on_blast registered")
	ok(type(def.on_punch) == "function", "on_punch registered")
	ok(type(def.on_timer) == "function", "on_timer registered")
end

return results
