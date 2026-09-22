-- FriedcakeSMP — smp_tp /rtp (f08 §4.2, §6.2)
--
-- No menu (rtp.menu_enabled = false; removed 15 June 2026 [S14]).
-- Bare /rtp starts the warm-up immediately (OBSERVED [F0037]).
--
-- Generation is asynchronous: core.emerge_area first, the safe search
-- in the callback, never a synchronous scan (performance budget,
-- shared §2.7). The emerge callback MUST check remaining == 0 —
-- ignoring it is the classic async-Lua bug (f08 brief).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_tp.S

----------------------------------------------------------------------
-- Node classification (f08 §4.2.6 reject list)
--
-- Reject as landings: water, lava, fire, cactus, magma blocks,
-- campfires, sweet berry bushes, powder snow and leaves. The two
-- nodes above a landing must be free and non-liquid.
----------------------------------------------------------------------

smp_tp.rtp = {}

local HAZARD_NODES = {
	["mcl_core:water_source"] = true,
	["mcl_core:water_flowing"] = true,
	["mcl_core:lava_source"] = true,
	["mcl_core:lava_flowing"] = true,
	["mcl_fire:fire"] = true,
	["mcl_core:cactus"] = true,
	["mcl_nether:magma"] = true,
	["mcl_campfires:campfire"] = true,
	["mcl_powder_snow:powder_snow"] = true,
}
local HAZARD_PREFIXES = {
	"mcl_farming:sweet_berry_bush",
	"mcl_trees:leaves",
}
-- End: land only on end stone (f08 §4.2.6).
local END_STONE = "mcl_end:end_stone"

-- Injectable node accessor; dev tests override this.
smp_tp._node_at = function(x, y, z)
	return core.get_node(vector.new(x, y, z)).name
end

local function liquid(name)
	if name == "mcl_core:water_source" or name == "mcl_core:water_flowing"
		or name == "mcl_core:lava_source" or name == "mcl_core:lava_flowing" then
		return true
	end
	if core.get_item_group then
		local ok, g = pcall(core.get_item_group, name, "liquid")
		return ok and g == 1
	end
	return false
end

local function hazard(name)
	if HAZARD_NODES[name] then return true end
	for _, p in ipairs(HAZARD_PREFIXES) do
		if name:sub(1, #p) == p then return true end
	end
	if core.get_item_group then
		local ok, g = pcall(core.get_item_group, name, "fire")
		if ok and g == 1 then return true end
	end
	return false
end

-- A landing: solid (not air), not liquid, not on the reject list.
local function is_landing(name, dim)
	if name == "air" or liquid(name) or hazard(name) then return false end
	if dim == "end" and name ~= END_STONE then return false end
	return true
end

-- A "free" node above a landing: not liquid, not hazardous (you must
-- be able to stand and look up). T2: "two breathable nodes above".
local function is_breathable(name)
	return not liquid(name) and not hazard(name)
end

----------------------------------------------------------------------
-- Safe-y finder (f08 §4.2.6)
--
-- Overworld: top-down scan of the configured band.
-- Nether: downward from below mg_bedrock_nether_top_max, avoiding lava
--   (the "above" check catches lava pools and ceilings alike).
-- End: same top-down scan but the landing must be end stone.
--
-- Returns a position (feet) or nil.
----------------------------------------------------------------------

function smp_tp.find_safe_y(x, z, dim, band)
	local node_at = smp_tp._node_at
	local y0, y1
	if dim == "overworld" then
		y0, y1 = band.max, band.min      -- top-down
	elseif dim == "nether" then
		y0, y1 = band.max, band.min      -- downward from below the ceiling
	else -- end
		y0, y1 = band.max, band.min
	end
	local step = (y1 <= y0) and -1 or 1
	for y = y0, y1, step do
		local ground = node_at(x, y, z)
		if is_landing(ground, dim) then
			if is_breathable(node_at(x, y + 1, z))
				and is_breathable(node_at(x, y + 2, z)) then
				return vector.new(x, y + 1, z)  -- feet on top of ground
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Target sampling (f08 §4.2.3)
--
-- A random (x, z) inside the ring from rtp.min_radius to rtp.max_radius
-- around the region centre, clipped to the world border, inside the
-- region rectangle (if given) and outside the protected spawn radius.
----------------------------------------------------------------------

local function spawn_position()
	if mcl_spawn and mcl_spawn.get_world_spawn_pos then
		local ok, pos = pcall(mcl_spawn.get_world_spawn_pos)
		if ok and pos then return vector.new(pos) end
	end
	return vector.new(0, 72, 0)
end

smp_tp._spawn_position = spawn_position

function smp_tp.random_rtp_target(region)
	local cfg = smp_tp.cfg
	local cx, cz
	if region then
		cx, cz = region.cx or 0, region.cz or 0
	elseif cfg.rtp.regions and next(cfg.rtp.regions) then
		-- No region named: centre of the whole world.
		cx, cz = 0, 0
	else
		cx, cz = 0, 0
	end
	local span = cfg.rtp.max_radius - cfg.rtp.min_radius
	local border = (smp_tp._border or 30000) - 1
	local spawn = smp_tp._spawn_position()
	local prot = cfg.rtp.spawn_protect_radius

	for _ = 1, 64 do
		::continue::
		local r = cfg.rtp.min_radius + (span > 0 and math.random() * span or 0)
		local ang = math.random() * 2 * math.pi
		local x = math.floor(cx + r * math.cos(ang))
		local z = math.floor(cz + r * math.sin(ang))
		x = math.min(border, math.max(-border, x))
		z = math.min(border, math.max(-border, z))
		if region and (x < region.minx or x > region.maxx
			or z < region.minz or z > region.maxz) then
			goto continue
		end
		if prot > 0 then
			local dx, dz = x - spawn.x, z - spawn.z
			if dx * dx + dz * dz < prot * prot then goto continue end
		end
		return x, z
	end
	return nil
end

----------------------------------------------------------------------
-- Cooldowns (per-kind, tier-reduced; f08 §4.1)
----------------------------------------------------------------------

function smp_tp.cooldown_secs(name, kind)
	local tier = smp_tp.bridge.tier(name)
	if kind == "rtp" then
		return smp_tp.cfg.rtp.cooldown[tier] or smp_tp.cfg.rtp.cooldown.default
	end
	local map = smp_tp.cfg.tp.cooldown[kind]
	if map then
		return map[tier] or map.default or 0
	end
	return 0
end

-- Returns remaining seconds (0 = ready).
function smp_tp.cooldown_remaining(name, kind)
	local st = smp_tp.get_state(name)
	local exp = st.cooldowns[kind]
	if not exp then return 0 end
	local rem = exp - os.time()
	if rem <= 0 then st.cooldowns[kind] = nil; return 0 end
	return rem
end

function smp_tp.start_cooldown(name, kind)
	local secs = smp_tp.cooldown_secs(name, kind)
	if secs > 0 then
		smp_tp.get_state(name).cooldowns[kind] = os.time() + secs
	end
end

----------------------------------------------------------------------
-- The search itself (f08 §6.2)
--
-- smp_tp.rtp(name, dim, region_name, attempt). Async; re-enters with
-- attempt + 1 on a dry candidate. On total failure the player is told
-- and NO cooldown starts (f08 §4.2.7, T5).
----------------------------------------------------------------------

function smp_tp.rtp(name, dim, region_name, attempt)
	attempt = attempt or 1
	local cfg = smp_tp.cfg
	if attempt > cfg.rtp.max_attempts then
		core.chat_send_player(name, S("No safe location found. Try again."))
		return "failed"
	end
	local band = cfg.rtp.scan[dim]
	if not band then
		core.chat_send_player(name, S("Unknown dimension: @1", dim))
		return "failed"
	end
	local region = region_name and cfg.rtp.regions[region_name] or nil
	local x, z = smp_tp.random_rtp_target(region)
	if not x then
		core.chat_send_player(name, S("No safe location found. Try again."))
		return "failed"
	end

	core.emerge_area(vector.new(x, band.min, z), vector.new(x, band.max, z),
		function(_, _, remaining)
			-- Classic async-Lua bug: without this guard the search
			-- reads ungenerated columns.
			if remaining and remaining > 0 then return end
			local p = core.get_player_by_name(name)
			if not p then return end  -- left while generating
			local pos = smp_tp.find_safe_y(x, z, dim, band)
			if pos then
				local ok = smp_tp.teleport_with_warmup(p, pos, "rtp")
				if ok then
					smp_tp.start_cooldown(name, "rtp")
				end
			else
				smp_tp.rtp(name, dim, region_name, attempt + 1)
			end
		end)
	return "searching"
end

----------------------------------------------------------------------
-- /rtp command handler (registered in commands.lua)
--
-- T1: opens no menu and begins the warm-up immediately.
----------------------------------------------------------------------

function smp_tp.cmd_rtp(name, param)
	local cfg = smp_tp.cfg
	if smp_tp.bridge.is_tagged(name) then
		core.chat_send_player(name, S("You cannot teleport while in combat"))
		return false
	end
	if smp_tp.is_warming_up(name) then
		core.chat_send_player(name, S("Already teleporting"))
		return false
	end
	local dim, region_name = "overworld", nil
	if param and param ~= "" then
		param = param:lower()
		if param == "overworld" or param == "nether" or param == "end" then
			dim = param
		elseif cfg.rtp.regions and cfg.rtp.regions[param] then
			region_name = param
			dim = "overworld"  -- regions are Overworld rectangles (PROPOSED)
		else
			core.chat_send_player(name,
				S("Usage: /rtp [overworld|nether|end|region]"))
			return false
		end
	end
	local rem = smp_tp.cooldown_remaining(name, "rtp")
	if rem > 0 then
		core.chat_send_player(name,
			S("You can random teleport again in @1s", rem))
		return false
	end
	local p = core.get_player_by_name(name)
	if not p then return false end
	-- No menu (T1): straight into the async search.
	smp_tp.rtp(name, dim, region_name, 1)
	return true
end

----------------------------------------------------------------------
-- RTP zone (f08 §4.2.9, T12)
--
-- A configured box at spawn: a player who STAYS inside for
-- rtp.zone_delay is sent to the Overworld; presence is checked once
-- per second. Pass-through (less than zone_delay) does not trigger.
----------------------------------------------------------------------

local zone_timer = 0
function smp_tp.rtp_zone_step(dtime)
	zone_timer = zone_timer + dtime
	if zone_timer < 1 then return end
	zone_timer = 0  -- once per second (shared §2.7)

	local z = smp_tp.cfg.rtp.zone
	if not z then return end
	local spawn = smp_tp._spawn_position()
	local minx, maxx = spawn.x + z.minx, spawn.x + z.maxx
	local minz, maxz = spawn.z + z.minz, spawn.z + z.maxz
	local miny, maxy = spawn.y + (z.miny or -2), spawn.y + (z.maxy or 3)
	local now = os.time()

	for _, p in ipairs(core.get_connected_players()) do
		local name = p:get_player_name()
		local pos = p:get_pos()
		local inside = pos.x >= minx and pos.x <= maxx
			and pos.y >= miny and pos.y <= maxy
			and pos.z >= minz and pos.z <= maxz
		local st = smp_tp.get_state(name)
		if inside then
			if st.zone_entered_at == nil then
				st.zone_entered_at = now
			elseif now - st.zone_entered_at >= smp_tp.cfg.rtp.zone_delay then
				st.zone_entered_at = nil
				p:set_pos(spawn)
			end
		else
			st.zone_entered_at = nil
		end
	end
end

return smp_tp
