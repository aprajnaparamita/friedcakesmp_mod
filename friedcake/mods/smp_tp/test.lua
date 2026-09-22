-- FriedcakeSMP — smp_tp acceptance tests
-- Loaded by `/smp test smp_tp` in-game.
--
-- In-game-safe slice of spec/features/f08-teleport.md §9 and
-- spec/plan/acceptance-tests.md T1–T13. The state-machine and async
-- behaviours are covered by friedcake/dev-tests/test_tp.lua (which
-- runs against a fake engine); this file checks what can be checked
-- live without teleporting the running player:
--   * every f08 command is registered
--   * T1: rtp.menu_enabled is false (bare /rtp, no menu)
--   * /back is disabled by default (f08 §4.5.4)
--   * the warm-up framework surface (the deliverable f09 rides on)
--   * T2's reject list against an INJECTED node accessor (no world
--     reads, no movement)
--   * the tier-reduced cooldown values (T6, via the smp_ranks bridge)
--   * T7: a /tpa to an unknown player gets the generic refusal
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "ok")
	end
end

local function eq(a, b, msg)
	ok(a == b, string.format("%s: expected %s got %s",
		msg or "eq", tostring(b), tostring(a)))
end

----------------------------------------------------------------------
-- Command registration
----------------------------------------------------------------------

local cmds = {
	"rtp", "tpa", "tp", "tpahere", "tpaccept", "tpadeny", "tpdeny",
	"tpacancel", "tpauto", "tpatoggle", "tpaheretoggle", "spawn",
	"warp", "world", "back", "return",
}
for _, c in ipairs(cmds) do
	ok(core.registered_chatcommands[c] ~= nil, "command /" .. c .. " registered")
end

----------------------------------------------------------------------
-- T1: no menu on /rtp
----------------------------------------------------------------------

ok(smp_tp.cfg ~= nil, "smp_tp.cfg present")
eq(smp_tp.cfg.rtp.menu_enabled, false, "T1 rtp.menu_enabled is false")
eq(smp_tp.cfg.tp.back_enabled, false, "/back disabled by default")

----------------------------------------------------------------------
-- Warm-up framework surface (f08 §4.1 — f09's /home rides on this)
----------------------------------------------------------------------

ok(type(smp_tp.teleport_with_warmup) == "function",
	"warm-up framework: teleport_with_warmup present")
ok(type(smp_tp.is_warming_up) == "function",
	"warm-up framework: is_warming_up present")
ok(type(smp_tp.cancel_warmup) == "function",
	"warm-up framework: cancel_warmup present")
ok(smp_tp.warmup ~= nil, "warm-up table present")
ok(smp_tp.cfg.tp.warmup >= 1, "warm-up duration configured")
ok(smp_tp.cfg.tp.cancel_move_distance >= 1,
	"cancel-on-move distance configured")

----------------------------------------------------------------------
-- State schema
----------------------------------------------------------------------

local st = smp_tp.get_state("__t_tp_probe")
ok(st ~= nil, "get_state returns a table")
ok(st.last_teleport_from == nil, "fresh state has no last_teleport_from")
ok(st.requests_in ~= nil and st.requests_out ~= nil, "request tables present")
ok(st.cooldowns ~= nil, "cooldown table present")
ok(st.warmup == nil, "fresh state has no warm-up")

----------------------------------------------------------------------
-- T2: the safe-y reject list, against an injected node accessor.
-- No world is read and nothing moves; the accessor is restored
-- after.
----------------------------------------------------------------------

local saved_node_at = smp_tp._node_at
local function col(world, x, z, y)
	local c = world[x .. "," .. z]
	return c and c[y] or "air"
end
local band = { min = 50, max = 64 }
local function expect(world, x, z, dim, y_expect, msg)
	smp_tp._node_at = function(px, py, pz)
		return col(world, px, pz, py)
	end
	local pos = smp_tp.find_safe_y(x, z, dim, band)
	if y_expect == nil then
		ok(pos == nil, msg .. " rejected")
	else
		ok(pos ~= nil and math.floor(pos.y) == y_expect, msg)
	end
end
local dirt = { ["1,1"] = { [60] = "mcl_core:dirt", [59] = "mcl_core:stone" } }
expect(dirt, 1, 1, "overworld", 61, "T2 plain dirt lands at y+1")
for _, name in ipairs({
	"mcl_core:water_source", "mcl_core:lava_source", "mcl_fire:fire",
	"mcl_core:cactus", "mcl_nether:magma", "mcl_campfires:campfire",
	"mcl_farming:sweet_berry_bush_2", "mcl_powder_snow:powder_snow",
	"mcl_trees:leaves_oak",
}) do
	expect({ ["1,1"] = { [60] = name } }, 1, 1, "overworld", nil,
		"T2 " .. name)
end
expect({ ["1,1"] = { [60] = "mcl_core:dirt", [62] = "mcl_core:water_source" } },
	1, 1, "overworld", nil, "T2 blocked node above")
expect({ ["1,1"] = { [60] = "mcl_core:dirt" } }, 1, 1, "end", nil,
	"T2 end: dirt is not end stone")
expect({ ["1,1"] = { [60] = "mcl_end:end_stone" } }, 1, 1, "end", 61,
	"T2 end: end stone lands")
smp_tp._node_at = saved_node_at

----------------------------------------------------------------------
-- T6: cooldown values through the tier bridge
----------------------------------------------------------------------

ok(type(smp_tp.cooldown_secs) == "function", "cooldown_secs present")
eq(smp_tp.cooldown_secs("__t_tp_probe", "rtp") > 0, true,
	"T6 default rtp cooldown positive")
local def = smp_tp.cooldown_secs("__t_tp_probe", "rtp")
local t1 = (function()
	-- If smp_ranks is loaded the bridge uses it; the probe name has no
	-- rank so it should resolve to the default tier.
	return smp_tp.bridge.tier("__t_tp_probe")
end)()
ok(type(t1) == "string" and t1 ~= "", "T6 tier bridge returns a tier")
ok(smp_tp.cfg.rtp.cooldown.tier1 <= def, "T6 tier1 cooldown <= default")
smp_tp.start_cooldown("__t_tp_probe", "rtp")
local rem = smp_tp.cooldown_remaining("__t_tp_probe", "rtp")
ok(rem > 0, "T6 cooldown active after start_cooldown")
ok(rem <= def, "T6 cooldown within configured duration")
-- Clear it so the probe state is not left dirty.
smp_tp.get_state("__t_tp_probe").cooldowns.rtp = nil

----------------------------------------------------------------------
-- T7: /tpa to an unknown player is the generic refusal
----------------------------------------------------------------------

local cmd_tpa = core.registered_chatcommands["tpa"]
local r = cmd_tpa.func("__t_tp_probe", "__no_such_player_9999")
ok(r == false, "T7 /tpa to unknown player refused")

----------------------------------------------------------------------

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_tp tests passed."
else
	results.lines[#results.lines + 1] = string.format(
		"%d failures.", results.failed)
end
return results
