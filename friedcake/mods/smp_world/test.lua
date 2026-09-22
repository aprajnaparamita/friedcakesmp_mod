-- In-game acceptance tests for f15 — World Rules and Server Configuration.
-- Covers T1 (spawn protection through core.is_protected), T3 (soft border),
-- T5 (account-per-IP flag, not blocked) and T7 (zero ABMs) against the LIVE
-- engine; the standalone twin is friedcake/dev-tests/test_world.lua.
--
-- Loaded with `pcall(chunk)` and expected to return { passed, failed, lines }
-- (same contract as smp_core/test.lua). Dispatching to it needs one line in
-- the /smp test dispatcher — proposed for the integrator in f15 §10
-- (## Proposed shared changes); until then this file is dormant.
--
-- Nothing here mutates the world: the border clamp runs against a stub
-- player object, and the T5 join runs against six fake joiners with a
-- patched core.get_player_ip (always restored, even on error).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local results = { passed = 0, failed = 0, lines = {} }

local function yes(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL: " .. msg
	end
end

local function eq(got, want, msg)
	yes(got == want, msg .. " (got " .. tostring(got) ..
		", want " .. tostring(want) .. ")")
end

if smp_world == nil then
	yes(false, "smp_world is not loaded (load_mod = smp_world?)")
	return results
end

----------------------------------------------------------------------
-- T1: spawn protection runs through core.is_protected
----------------------------------------------------------------------

-- A dummy name with no privileges (never joins, so protection_bypass is
-- impossible and the result does not depend on who runs the test).
local DUMMY = "smp_world_t1_dummy"

eq(smp_world.is_spawn_protected({ x = 0, y = 8, z = 0 }), true,
	"T1 spawn centre is protected")
eq(smp_world.is_spawn_protected({ x = 128, y = 8, z = -128 }), true,
	"T1 radius boundary (<= 128) is inside")
eq(smp_world.is_spawn_protected({ x = 129, y = 8, z = 0 }), false,
	"T1 just outside the radius is not protected by us")
eq(smp_world.is_spawn_protected({ x = 32767, y = 8, z = 32767 }), false,
	"T1 far away is not protected by us")

-- Nether: same X/Z inside the square, wrong dimension (mcl_vars is the
-- Mineclonia dimension band table, spec 4.2.1).
if mcl_vars and mcl_vars.mg_nether_min then
	eq(smp_world.is_spawn_protected({ x = 0,
		y = mcl_vars.mg_nether_min + 10, z = 0 }), false,
		"T1 nether band inside the square is not spawn-protected")
end

-- The chain itself: the engine default is false, so a true here proves
-- our wrap is installed. (The converse — outside — is NOT asserted: the
-- live mcl_levelgen area guard may legitimately answer for ungenerated
-- chunks; chain composition is covered by the dev-test.)
eq(core.is_protected({ x = 0, y = 8, z = 0 }, DUMMY), true,
	"T1 core.is_protected answers true at spawn")

local cbs = core.registered_on_protection_violation
yes(type(cbs) == "table" and next(cbs) ~= nil,
	"T1 protection-violation callback is registered")

----------------------------------------------------------------------
-- T3: crossing the soft border moves the player back inside
----------------------------------------------------------------------

local function stub_player(x, y, z, name)
	local p = { pos = { x = x, y = y, z = z }, name = name, sets = 0 }
	function p:get_pos()
		return { x = self.pos.x, y = self.pos.y, z = self.pos.z }
	end
	function p:set_pos(np)
		self.sets = self.sets + 1
		self.pos = np
	end
	function p:get_player_name()
		return self.name
	end
	return p
end

local lim = smp_world.border_limit()
local raw_limit = tonumber(core.get_mapgen_setting("mapgen_limit"))
if lim == false or type(lim) ~= "number" then
	results.lines[#results.lines + 1] =
		"INFO: soft border inactive on this world (mapgen_limit=" ..
		tostring(raw_limit) .. "), clamp checks skipped"
else
	yes(raw_limit ~= nil and lim == raw_limit - 16,
		"T3 border_limit = mapgen_limit - world.border_margin (got " ..
		tostring(lim) .. ")")

	local out = stub_player(40000, 64, -40000, "smp_world_t3_stub")
	smp_world.enforce_border(out)
	eq(out.sets, 1, "T3 player past the border is moved back")
	eq(out.pos.x, lim, "T3 X clamped to +limit")
	eq(out.pos.z, -lim, "T3 Z clamped to -limit")
	eq(out.pos.y, 64, "T3 Y untouched")

	local inside = stub_player(0, 64, 0, "smp_world_t3_stub")
	smp_world.enforce_border(inside)
	eq(inside.sets, 0, "T3 player inside is not moved")
end

----------------------------------------------------------------------
-- T5: the sixth distinct account from one IP flags staff, never blocks
----------------------------------------------------------------------

-- Fresh IP per run so the bucket starts empty (otherwise a previously
-- polluted bucket flags from the first join and the boundary assertions
-- would not hold). The value is only a map key inside smp_world's own
-- storage; core.get_player_ip is patched to hand it out below.
local test_ip = "198.51.100." .. tostring(os.time()) .. "." ..
	tostring(math.random(1000, 9999))

local flags_before = smp_world.staff_flag_count
local old_get_ip = core.get_player_ip
core.get_player_ip = function()
	return test_ip
end

local t5_ok, t5_err = pcall(function()
	for i = 1, 5 do
		local pl = { get_player_name = function()
			return "__smpw_t5_" .. i
		end }
		local ret = smp_world.on_joinplayer(pl)
		eq(ret, nil, "T5 account " .. i .. " (<= max) is not blocked")
		eq(smp_world.staff_flag_count, flags_before,
			"T5 account " .. i .. " raises no flag yet")
	end

	local pl6 = { get_player_name = function() return "__smpw_t5_6" end }
	eq(smp_world.on_joinplayer(pl6), nil,
		"T5 sixth account is NOT blocked (flag only)")
	eq(smp_world.staff_flag_count, flags_before + 1,
		"T5 sixth distinct account raises the staff flag")
	eq(smp_world.accounts_on_ip(test_ip), 6,
		"T5 index counts six distinct accounts on the IP")
end)

core.get_player_ip = old_get_ip -- always restore, even on failure

if not t5_ok then
	yes(false, "T5 crashed: " .. tostring(t5_err))
end

----------------------------------------------------------------------
-- T7: zero ABMs across the smp_ mod set (runtime view; the static
--     source scan lives in dev-tests/test_world.lua)
----------------------------------------------------------------------

local offenders = {}
for _, abm in ipairs(core.registered_abms or {}) do
	local origin = tostring(abm.mod_origin or "")
	if origin:find("^smp_") then
		offenders[#offenders + 1] = origin
	end
end
yes(#offenders == 0, "T7 zero ABMs registered by smp_* (offenders: " ..
	(#offenders > 0 and table.concat(offenders, ", ") or "none") .. ")")

return results
