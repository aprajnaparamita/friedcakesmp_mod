-- FriedcakeSMP — smp_combat / attribution.lua
-- Who hit whom: melee, projectiles and explosions.
-- spec/features/f10-combat.md §4.2.1 and §8.
--
-- Three cases for resolve_attacker (§8):
--   1. a player ObjectRef            — melee punch
--   2. an entity with `_shooter`     — arrows [M1]
--   3. nil                           — environment (no tag)
--
-- Explosion attribution (end crystals, respawn anchors, TNT) is a
-- 10-second ring buffer of (pos, placer), honoured within
-- `combat.explosion_radius` nodes of the damaged position (PROPOSED;
-- V-70). Verified against ~/dev/mineclonia-git:
--   * crystals explode with source = the puncher (mcl_end/end_crystal),
--     so a punched crystal attributes directly — no ring needed;
--   * TNT explodes with direct = the primed TNT entity and source = nil,
--     so the ring keys off the entity position;
--   * respawn anchors explode with neither direct nor source, so the
--     ring keys off the victim position.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_combat.attribution = {}

local A = smp_combat.attribution

----------------------------------------------------------------------
-- resolve_attacker: melee / _shooter / environment
----------------------------------------------------------------------

local function ref_is_player(o)
	return o.is_player and o:is_player() or false
end

local function ref_name(o)
	return o:get_player_name()
end

function A.resolve(obj)
	if obj == nil then return nil end
	local t = type(obj)
	if t ~= "userdata" and t ~= "table" then return nil end
	local ok, is_p = pcall(ref_is_player, obj)
	if not ok then return nil end
	if is_p then
		local ok2, nm = pcall(ref_name, obj)
		if ok2 and type(nm) == "string" and nm ~= "" then return nm end
		return nil
	end
	-- Entity case: an arrow carries the shooter in `_shooter` [M1].
	local ok3, le = pcall(function() return obj.get_luaentity and obj:get_luaentity() end)
	if ok3 and type(le) == "table" then
		local shooter = le._shooter
		if shooter ~= nil
			and (type(shooter) == "table" or type(shooter) == "userdata") then
			local ok4, s_p = pcall(ref_is_player, shooter)
			if ok4 and s_p then
				local ok5, nm = pcall(ref_name, shooter)
				if ok5 and type(nm) == "string" and nm ~= "" then return nm end
			end
		end
	end
	return nil
end

-- Top-level alias: the §6 algorithm calls smp_combat.resolve_attacker.
smp_combat.resolve_attacker = A.resolve

----------------------------------------------------------------------
-- Explosion ring: 10 s of (pos, placer) pairs
----------------------------------------------------------------------

local ring = {} -- ordered oldest -> newest
local RING_MAX = 64
A.ring = ring

function A.prune(now)
	now = now or os.time()
	local w = smp_combat.cfg.combat.explosion_window or 10
	for i = #ring, 1, -1 do
		if now - ring[i].t > w then table.remove(ring, i) end
	end
end

function A.record(pos, placer_name)
	if not pos or not placer_name then return end
	local now = os.time()
	A.prune(now)
	ring[#ring + 1] = {
		t = now,
		pos = { x = pos.x, y = pos.y, z = pos.z },
		placer = placer_name,
	}
	while #ring > RING_MAX do table.remove(ring, 1) end
end

-- Nearest recorded placer around `pos`, excluding `exclude` (the victim
-- must not be attributed to themselves).
function A.nearest_placer(pos, exclude)
	if not pos then return nil end
	local now = os.time()
	A.prune(now)
	local r = smp_combat.cfg.combat.explosion_radius or 12
	local best, best_d
	for i = #ring, 1, -1 do
		local e = ring[i]
		if e.placer ~= exclude then
			local dx = e.pos.x - pos.x
			local dy = e.pos.y - pos.y
			local dz = e.pos.z - pos.z
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d <= r and (not best_d or d < best_d) then
				best, best_d = e.placer, d
			end
		end
	end
	return best
end

----------------------------------------------------------------------
-- Node triggers: what may explode without a player source.
-- Verified against ~/dev/mineclonia-git:
--   mcl_tnt:tnt                        (ignited by tools/fire/redstone)
--   mcl_beds:respawn_anchor[_charged_*] (charged anchors explode in the
--                                        Overworld when used)
-- End crystals are entities and are attributed through their puncher
-- source instead (see header).
----------------------------------------------------------------------

local function trigger_node(name)
	if name == "mcl_tnt:tnt" or name == "mcl_beds:respawn_anchor" then
		return true
	end
	return name:match("^mcl_beds:respawn_anchor_charged_") ~= nil
end

local function placer_of(obj)
	if obj == nil then return nil end
	local ok, is_p = pcall(ref_is_player, obj)
	if ok and is_p then
		local ok2, nm = pcall(ref_name, obj)
		if ok2 and type(nm) == "string" and nm ~= "" then return nm end
	end
	return nil
end

function A.on_placenode(pos, newnode, placer)
	if not pos or not newnode then return end
	local name = placer_of(placer)
	if not name then return end
	if trigger_node(newnode.name) then A.record(pos, name) end
end

function A.on_punchnode(pos, node, puncher)
	if not pos or not node then return end
	local name = placer_of(puncher)
	if not name then return end
	if trigger_node(node.name) then A.record(pos, name) end
end

----------------------------------------------------------------------
-- killer_from: extract a player attacker from a death reason.
-- Handles the Mineclonia path (reason._mcl_reason set by
-- mcl_damage.damage_player via set_hp) and the engine-native punch
-- reason ({type = "punch", object = hitter}). String or unrelated
-- reasons yield nil (environment death).
----------------------------------------------------------------------

function A.killer_from(reason)
	if type(reason) ~= "table" then return nil end
	local mcl = reason._mcl_reason
	if type(mcl) == "table" then
		local src = mcl.source
		if src ~= nil then
			local nm = A.resolve(src)
			if nm then return nm end
		end
	end
	local src = reason.source
	if src ~= nil then
		local nm = A.resolve(src)
		if nm then return nm end
	end
	if reason.type == "punch" and reason.object ~= nil then
		return A.resolve(reason.object)
	end
	return nil
end

smp_combat.killer_from = A.killer_from

----------------------------------------------------------------------
-- Safe zone / PvP policy (f15 §4.2.1: PvP disabled inside the spawn
-- protection radius; X10: no tag, no bounty payout there).
-- Prefers the predicate f15 will export as smp_core.is_spawn_protected;
-- falls back to the same radius rule so f10 works standalone (PROPOSED).
----------------------------------------------------------------------

function smp_combat.in_safe_zone(pos)
	if not pos then return false end
	if smp_core and smp_core.is_spawn_protected then
		return smp_core.is_spawn_protected(pos) and true or false
	end
	local r = 128 -- f15 §7 default: world.spawn_protect_radius = 128
	if core.settings and core.settings.get then
		r = tonumber(core.settings:get("world.spawn_protect_radius")) or r
	end
	if r <= 0 then return false end
	if mcl_worlds and mcl_worlds.pos_to_dimension then
		local ok, dim = pcall(mcl_worlds.pos_to_dimension, pos)
		if ok and dim ~= "overworld" then return false end
	end
	return math.abs(pos.x) <= r and math.abs(pos.z) <= r
end

function smp_combat.pvp_allowed(victim, attacker)
	local pos
	if type(victim) == "string" then
		local p = core.get_player_by_name(victim)
		pos = p and p.get_pos and p:get_pos()
	elseif victim ~= nil
		and (type(victim) == "table" or type(victim) == "userdata") then
		local ok, p = pcall(function()
			return victim.get_pos and victim:get_pos()
		end)
		if ok then pos = p end
	end
	if not pos then return true end
	return not smp_combat.in_safe_zone(pos)
end
