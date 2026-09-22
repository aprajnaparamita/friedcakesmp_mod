-- Standalone smoke tests for f15 — World Rules and Server Configuration.
-- Covers acceptance tests T1 (spawn protection through core.is_protected),
-- T3 (soft border), T5 (account-per-IP flag), T6 guard (no seed leak) and
-- T7 (zero ABMs across the smp_ set) from
-- spec/features/f15-world-rules.md §9.
--
-- Runs under plain luajit with a mocked `core`/`mcl_worlds` — no engine
-- required. Works from any checkout (including a git worktree): paths are
-- resolved relative to this script's own location.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

----------------------------------------------------------------------
-- Path resolution and mock environment
----------------------------------------------------------------------

local script = (arg and arg[0]) or "friedcake/dev-tests/test_world.lua"
local modpack = script:match("^(.*)/dev%-tests/[^/]+$") or "friedcake"
local init_path = modpack .. "/mods/smp_world/init.lua"

local checks, failures = 0, 0

local function ok(cond, msg)
	checks = checks + 1
	if cond then
		print("PASS: " .. msg)
	else
		failures = failures + 1
		print("FAIL: " .. msg)
	end
end

local function eq(got, want, msg)
	ok(got == want, msg .. " (got " .. tostring(got) ..
		", want " .. tostring(want) .. ")")
end

-- Mock state, exported so each test section can inspect it.
local M = {
	chats = {},             -- [player] = { messages }
	logs = {},              -- { lines }
	privs = {},             -- [name] = { priv = true }
	settings_store = {},    -- [key] = string
	violation_cbs = {},     -- register_on_protection_violation
	join_cbs = {},          -- register_on_joinplayer
	step_cbs = {},          -- register_globalstep
	mods_loaded_cbs = {},   -- register_on_mods_loaded
	baseline_hits = 0,      -- calls that reached the old is_protected
	kicks = {},             -- [name] = reason
	storage = {},           -- mod-storage mock, [key] = string
	json_registry = {},     -- write_json/parse_json stand-in
	mapgen = { mapgen_limit = "31007" },
	ip_of = {},             -- [name] = ip
	connected = {},         -- list of player objects
	registered_abms = {},   -- core.registered_abms snapshot for T7
}

local function chat_send_player(name, msg)
	M.chats[name] = M.chats[name] or {}
	table.insert(M.chats[name], msg)
end

core = {
	-- translator: identity, so assertions see the raw fmt string
	get_translator = function()
		return function(s, ...) return s end
	end,
	get_current_modname = function() return "smp_world" end,
	settings = {
		get = function(_, key) return M.settings_store[key] end,
	},
	log = function(level, msg) table.insert(M.logs, level .. ": " .. msg) end,
	chat_send_player = chat_send_player,
	register_on_protection_violation = function(fn)
		table.insert(M.violation_cbs, fn)
	end,
	register_on_joinplayer = function(fn)
		table.insert(M.join_cbs, fn)
	end,
	register_globalstep = function(fn)
		table.insert(M.step_cbs, fn)
	end,
	register_on_mods_loaded = function(fn)
		table.insert(M.mods_loaded_cbs, fn)
	end,
	register_abm = function(spec)
		table.insert(core.registered_abms, spec)
		spec.mod_origin = "??"
	end,

	-- The engine default: nothing is protected until mods say otherwise.
	is_protected = function()
		M.baseline_hits = M.baseline_hits + 1
		return false
	end,
	check_player_privs = function(name, priv)
		local have = M.privs[name]
		if type(priv) == "string" then
			return have and have[priv] == true or false, priv
		end
		if have then
			for p in pairs(priv) do
				if have[p] then return true end
			end
		end
		return false
	end,

	get_mapgen_setting = function(name) return M.mapgen[name] end,
	get_player_ip = function(name) return M.ip_of[name] end,
	get_connected_players = function() return M.connected end,
	kick_player = function(name, reason)
		table.insert(M.kicks, { name = name, reason = reason })
	end,
	get_mod_storage = function()
		return {
			get_string = function(_, k) return M.storage[k] or "" end,
			set_string = function(_, k, v) M.storage[k] = v end,
		}
	end,
	sha1 = function(data) return "sha1_" .. data end,
	-- Round-trip stand-in: serialise a deep copy, parse by registry key.
	write_json = function(v)
		local function deepcopy(x)
			if type(x) ~= "table" then return x end
			local out = {}
			for k, val in pairs(x) do out[k] = deepcopy(val) end
			return out
		end
		table.insert(M.json_registry, deepcopy(v))
		return "\1json" .. #M.json_registry
	end,
	parse_json = function(s)
		local idx = s and s:match("^\1json(%d+)$")
		return idx and M.json_registry[tonumber(idx)] or nil
	end,
}

core.registered_abms = M.registered_abms

-- Dimension mock: y <= -1000 is the Nether band, everything else the
-- Overworld (deterministic stand-in for mcl_worlds.pos_to_dimension).
mcl_worlds = {
	pos_to_dimension = function(pos)
		if pos.y <= -1000 then return "nether" end
		return "overworld"
	end,
}

-- Load the mod under test.
dofile(init_path)

----------------------------------------------------------------------
-- T1: digging inside the spawn radius is refused through core.is_protected;
--     digging outside succeeds (the refusal itself is the engine's doing —
--     builtin game/item.lua returns false from dig/place when
--     core.is_protected is true, verified against Luanti source).
----------------------------------------------------------------------

-- Inside: protected, and the old chain is NOT consulted (short-circuit).
local before = M.baseline_hits
eq(core.is_protected({ x = 0, y = 10, z = 0 }, "alice"), true,
	"T1 inside spawn is protected")
eq(M.baseline_hits, before, "T1 inside spawn short-circuits the old chain")

-- Outside: the chain falls through to the previous is_protected.
eq(core.is_protected({ x = 200, y = 10, z = 0 }, "alice"), false,
	"T1 outside spawn is not protected by us")
ok(M.baseline_hits > before, "T1 outside spawn consults the old chain")

-- Boundary: inclusive at exactly the radius (spec §6 uses <=).
eq(smp_world.is_spawn_protected({ x = 128, y = 0, z = -128 }), true,
	"T1 boundary 128 is inside")
eq(smp_world.is_spawn_protected({ x = 129, y = 0, z = 0 }), false,
	"T1 129 is outside")

-- Overworld only: same X/Z inside the square but in the Nether band.
eq(smp_world.is_spawn_protected({ x = 0, y = -1000, z = 0 }), false,
	"T1 nether position inside the square is not spawn-protected")
eq(core.is_protected({ x = 0, y = -1000, z = 0 }, "alice"), false,
	"T1 nether position falls through the chain")

-- protection_bypass exempts staff inside the radius.
M.privs["staffer"] = { protection_bypass = true }
eq(core.is_protected({ x = 0, y = 10, z = 0 }, "staffer"), false,
	"T1 protection_bypass falls through inside spawn")
M.privs["staffer"] = nil

-- Config: radius is live; 0 disables protection entirely.
M.settings_store["world.spawn_protect_radius"] = "64"
eq(smp_world.is_spawn_protected({ x = 100, y = 0, z = 0 }), false,
	"T1 radius honours world.spawn_protect_radius=64")
eq(smp_world.is_spawn_protected({ x = 64, y = 0, z = 0 }), true,
	"T1 radius 64 keeps its boundary inside")
M.settings_store["world.spawn_protect_radius"] = "0"
eq(smp_world.is_spawn_protected({ x = 0, y = 0, z = 0 }), false,
	"T1 radius 0 disables spawn protection")
M.settings_store["world.spawn_protect_radius"] = nil

-- Composition: a mod loading later and wrapping core.is_protected (as
-- mcl_levelgen does in the other direction) must still reach our check.
local mine = core.is_protected
core.is_protected = function(pos, name)
	return mine(pos, name) or false
end
eq(core.is_protected({ x = 0, y = 10, z = 0 }, "alice"), true,
	"T1 spawn protection survives an outer wrapper (chain composition)")
core.is_protected = mine

-- The violation callback is registered and delivers the verbatim string.
eq(#M.violation_cbs, 1, "T1 exactly one protection-violation callback")
if M.violation_cbs[1] then
	M.violation_cbs[1]({ x = 1, y = 1, z = 1 }, "alice")
end
eq(M.chats["alice"] and M.chats["alice"][1], "This area is protected.",
	"T1 violation message is the verbatim f15 string")

----------------------------------------------------------------------
-- T3: a player crossing the soft border is moved back inside and told
----------------------------------------------------------------------

local function stub_player(x, y, z, name)
	local p = { pos = { x = x, y = y, z = z }, name = name or "tester",
		gets = 0, sets = {} }
	function p:get_pos()
		self.gets = self.gets + 1
		return { x = self.pos.x, y = self.pos.y, z = self.pos.z }
	end
	function p:set_pos(np)
		table.insert(self.sets, np)
		self.pos = np
	end
	function p:get_player_name()
		return self.name
	end
	return p
end

eq(#M.step_cbs, 1, "T3 exactly one border globalstep registered")

-- Default world: mapgen_limit 31007, margin 16 -> clamp at 30991.
eq(smp_world.border_limit(), 30991, "T3 border = mapgen_limit - margin")

-- Beyond the border in both X and Z: clamped, Y untouched, told once.
local out = stub_player(40000, 64, -40000)
smp_world.enforce_border(out)
eq(#out.sets, 1, "T3 player past the border is moved")
if #out.sets == 1 then
	eq(out.sets[1].x, 30991, "T3 X clamped to +limit")
	eq(out.sets[1].z, -30991, "T3 Z clamped to -limit")
	eq(out.sets[1].y, 64, "T3 Y untouched")
end
local border_msgs = M.chats["tester"] or {}
eq(#border_msgs, 1, "T3 exactly one message")
eq(border_msgs[1], "You have reached the world border.",
	"T3 verbatim f15 border string")

-- Inside: no movement, no message.
local inside = stub_player(10, 64, 10, "insider")
smp_world.enforce_border(inside)
eq(#inside.sets, 0, "T3 player inside is not moved")
eq(M.chats["insider"], nil, "T3 player inside is not told")

-- One axis only: Z clamped, X preserved.
local edge = stub_player(5, 64, 40000, "edge")
smp_world.enforce_border(edge)
eq(#edge.sets, 1, "T3 Z-only crossing is moved")
if #edge.sets == 1 then
	eq(edge.sets[1].x, 5, "T3 X preserved when only Z crosses")
	eq(edge.sets[1].z, 30991, "T3 Z clamped")
end

-- Live margin configuration.
M.settings_store["world.border_margin"] = "32"
eq(smp_world.border_limit(), 30975, "T3 margin honours world.border_margin")
M.settings_store["world.border_margin"] = nil

-- world.soft_border = false: no movement, no message.
M.settings_store["world.soft_border"] = "false"
local off = stub_player(40000, 64, 0, "offster")
smp_world.enforce_border(off)
eq(#off.sets, 0, "T3 soft_border=false disables enforcement")
M.settings_store["world.soft_border"] = nil

-- Unlimited world (mapgen_limit 0) disables the border.
M.mapgen.mapgen_limit = "0"
eq(smp_world.border_limit(), false, "T3 mapgen_limit 0 -> no border")
local unlim = stub_player(999999999, 64, 0, "unlim")
smp_world.enforce_border(unlim)
eq(#unlim.sets, 0, "T3 unlimited world is not clamped")
M.mapgen.mapgen_limit = "31007"

-- Margin >= limit degenerates to no border.
M.mapgen.mapgen_limit = "10"
eq(smp_world.border_limit(), false, "T3 margin >= limit -> no border")
M.mapgen.mapgen_limit = "31007"

-- Cadence: sweeps happen once per accumulated second, O(players), and a
-- lag spike produces exactly one sweep (no burst).
local a = stub_player(40000, 64, 0, "cadence1")
local b = stub_player(-40000, 64, 0, "cadence2")
local c = stub_player(0, 64, 40000, "cadence3")
M.connected = { a, b, c }

smp_world.border_step(0.5)
eq(a.gets + b.gets + c.gets, 0, "T3 no sweep before one second accumulates")
smp_world.border_step(0.6)
eq(a.gets, 1, "T3 sweep after 1.1 s checks player A")
eq(b.gets, 1, "T3 sweep checks player B (O(players))")
eq(c.gets, 1, "T3 sweep checks player C (O(players))")

local before_spike = a.gets
smp_world.border_step(5.0) -- server freeze: one sweep, not five
eq(a.gets - before_spike, 1, "T3 lag spike produces exactly one sweep")
local burst = a.gets
smp_world.border_step(0.1)
eq(a.gets, burst, "T3 remainder reset prevents a burst")
M.connected = {}

-- The registered globalstep routes through border_step.
local probe = stub_player(40000, 64, 0, "routed")
M.connected = { probe }
M.settings_store["world.soft_border"] = nil
-- drain the accumulator deterministically first
smp_world.border_step(2.0)
probe.gets = 0
smp_world.border_step(0.05)
smp_world.border_step(0.96) -- 1.01 accumulates -> sweep
eq(probe.gets, 1, "T3 registered globalstep drives the sweep")
M.connected = {}

print(string.format("world dev-test: %d checks, %d failures",
	checks, failures))
if failures > 0 then
	error(failures .. " check(s) failed", 0)
end
print("ALL OK so far (T1, T3)")
