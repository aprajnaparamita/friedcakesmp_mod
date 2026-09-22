-- FriedcakeSMP — smp_social /findplayer (f11 §4.5)
--
-- Returns location, rank and username like the official lookup
-- endpoint [S23][S24]. On a raiding server exact coordinates would
-- expose bases, so the location is COARSE (PROPOSED, T9):
--
--   `Offline`                       player not connected
--   `Spawn`                         within findplayer.spawn_radius of world spawn
--   `<Dimension> – <Region>`        dimension via mcl_worlds.pos_to_dimension,
--                                   region is a compass sector (§10 V-88)
--
-- Never exact coordinates. The output shape `<Field>: <Value>` follows
-- the Review Order grammar (shared §4.7); the field block is one chat
-- message with embedded newlines, the way builtin /help renders.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

local DIMENSION_NAMES = {
	overworld = "Overworld",
	nether    = "Nether",
	["end"]   = "The End",
	void      = "Void",
}

local function player_exists(name)
	if core.player_exists then return core.player_exists(name) end
	return true
end

-- Compass sector around spawn, quantised to findplayer.region_band
-- (default 2048 nodes). Nine buckets, none of them a coordinate.
local function region_of(x, z)
	local band = smp_social.cfg.findplayer.region_band
	local function axis(v)
		if v > band then return 1 elseif v < -band then return -1 end
		return 0
	end
	local ns = axis(z)
	local ew = axis(x)
	local ns_name = ns == 1 and "South" or (ns == -1 and "North" or "")
	local ew_name = ew == 1 and "East" or (ew == -1 and "West" or "")
	if ns_name == "" and ew_name == "" then return "Center" end
	if ns_name ~= "" and ew_name ~= "" then return ns_name .. "-" .. ew_name end
	return ns_name ~= "" and ns_name or ew_name
end
smp_social.region_of = region_of -- exported for tests (T9)

local function world_spawn(target)
	if type(mcl_spawn) == "table" and mcl_spawn.get_world_spawn_pos then
		local ok, pos = pcall(mcl_spawn.get_world_spawn_pos, target)
		if ok and type(pos) == "table" then return pos end
	end
	return { x = 0, y = 0, z = 0 }
end

local function dimension_of(pos)
	if type(mcl_worlds) == "table" and mcl_worlds.pos_to_dimension then
		local ok, dim = pcall(mcl_worlds.pos_to_dimension, pos)
		if ok and type(dim) == "string" then
			return DIMENSION_NAMES[dim] or "Overworld"
		end
	end
	return "Overworld" -- no mcl_worlds: permissive fallback
end

local function location_of(target)
	local pos = target:get_pos()
	local spawn = world_spawn(target)
	local dx, dz = pos.x - spawn.x, pos.z - spawn.z
	local radius = smp_social.cfg.findplayer.spawn_radius
	if dx * dx + dz * dz <= radius * radius then
		return "Spawn"
	end
	return dimension_of(pos) .. " – " .. region_of(dx, dz)
end

smp_social.register_cmd("findplayer", {
	params = S("<player>"),
	description = S("Show the coarse location, rank and username of a player"),
	func = function(name, param)
		param = (param or ""):match("^%s*(.-)%s*$") or ""
		if param == "" then return false end
		if not player_exists(param) then
			return smp_social.say(name, S("Player @1 does not exist", param))
		end
		local target = core.get_player_by_name(param)
		local location = target and location_of(target) or S("Offline")
		local rank = smp_social.rank_display(param)
		local username = target and target:get_player_name() or param
		return smp_social.say(name,
			S("Name: @1", username) .. "\n" ..
			S("Rank: @1", rank) .. "\n" ..
			S("Location: @1", location))
	end,
}, { "fp" })

return true
