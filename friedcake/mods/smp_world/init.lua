-- FriedcakeSMP — smp_world
-- f15 World Rules and Server Configuration: the four hooks of the config
-- package — spawn protection, soft world border, account-per-IP flag and
-- staff-name filter. The rules themselves are documented in
-- friedcake/WORLD_RULES.md; the specification is
-- spec/features/f15-world-rules.md.
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_world = {}

----------------------------------------------------------------------
-- Configuration
--
-- All keys are read LIVE from minetest.conf (defaults from spec §7, all
-- PROPOSED). The pins for engine settings live in
-- friedcake/minetest.conf.example.
----------------------------------------------------------------------

local DEFAULT_SPAWN_RADIUS = 128 -- spec §7 world.spawn_protect_radius
local DEFAULT_BORDER_MARGIN = 16 -- spec §7 world.border_margin
local DEFAULT_MAX_ACCOUNTS = 5   -- rule LIVE [S18]; enforcement PROPOSED
local DEFAULT_NAME_FILTER =
	"^admin$,^admin[%d_%-],^administrator$," ..
	"^staff$,^staff[%d_%-],^mod$,^mod[%d_%-]," ..
	"^moderator$,^moderator[%d_%-],^operator$," ..
	"^owner$,^server$,^server[%d_%-]" -- PROPOSED (f15 §7)

local function cfg_number(key, default)
	local v = tonumber(core.settings:get(key))
	return v or default
end

local function cfg_bool(key, default)
	local v = core.settings:get(key)
	if v == nil then
		return default
	end
	v = string.lower(v)
	return not (v == "false" or v == "0" or v == "no" or v == "off")
end

local function cfg_string(key, default)
	local v = core.settings:get(key)
	if v == nil then
		return default
	end
	return v
end

----------------------------------------------------------------------
-- 1. Spawn protection (spec §4.2.1, §6, acceptance T1, X10)
----------------------------------------------------------------------

-- The configured square half-width, for f08's /rtp ring clipping.
function smp_world.spawn_radius()
	return cfg_number("world.spawn_protect_radius", DEFAULT_SPAWN_RADIUS)
end

-- O(1) spawn protection test: a square of half-width
-- world.spawn_protect_radius around the origin, Overworld only. No node
-- scanning — pure arithmetic plus one dimension lookup (spec §6).
function smp_world.is_spawn_protected(pos)
	local r = smp_world.spawn_radius()
	if r <= 0 then
		return false -- radius 0 disables spawn protection
	end
	if math.abs(pos.x) > r or math.abs(pos.z) > r then
		return false
	end
	return mcl_worlds.pos_to_dimension(pos) == "overworld"
end

-- Compose into the existing core.is_protected chain (spec §6, §8): the
-- engine default returns false, Mineclonia's mcl_levelgen wraps that for
-- ungenerated chunks, and we wrap whatever is current. WRAPPING — never
-- replacing — keeps every earlier layer reachable regardless of mod load
-- order, so every mod that consults core.is_protected (f07 spawner
-- digging, f06 amethyst tools, f10 PvP policy, f08 /rtp landing) honours
-- spawn protection automatically (T1, X10).
local old_is_protected = core.is_protected

function core.is_protected(pos, name)
	if pos and smp_world.is_spawn_protected(pos) then
		-- The engine's protection_bypass privilege is documented as
		-- "Can bypass node protection in the world"; honouring it here
		-- keeps staff able to build and clear at spawn.
		local bypass = name and
			core.check_player_privs(name, "protection_bypass")
		if not bypass then
			return true
		end
	end
	return old_is_protected(pos, name)
end

-- The verbatim f15 refusal string (spec §6 / §3, PROPOSED house style).
-- Registered unconditionally per spec §6: Mineclonia's only other
-- protection source today is mcl_levelgen's ungenerated-chunk guard,
-- where "This area is protected." is equally accurate.
function smp_world.on_protection_violation(pos, name)
	core.chat_send_player(name, S("This area is protected."))
end

core.register_on_protection_violation(smp_world.on_protection_violation)
