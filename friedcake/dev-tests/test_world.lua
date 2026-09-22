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

print(string.format("world dev-test: %d checks, %d failures",
	checks, failures))
if failures > 0 then
	error(failures .. " check(s) failed", 0)
end
print("ALL OK so far (T1)")
