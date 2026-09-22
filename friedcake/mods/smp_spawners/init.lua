-- FriedcakeSMP — smp_spawners
-- Virtual spawners: a node with metadata and a node timer. Zero
-- entities, zero ABMs (goal G1). Implements spec/features/f07-spawners.md.
--
-- Commands:
--   /spawner give <player> <type> [count]   issue spawner items (admin)
--
-- Submodules (loaded below in dependency order):
--   types.lua       spawner type table (data only; PROPOSED markers)
--   accrue.lua      production curve and lazy accrual
--   item.lua        smp_spawners:spawner_item (item meta carries type)
--   node.lua        smp_spawners:spawner node + metadata schema
--   interaction.lua place, stacking, Silk Touch break, menu open
--   formspecs.lua   container menu over the virtual storage
--   routing.lua     sell-all bridge into f02
--   performance.lua node timer lifecycle and no-op callbacks
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local MODNAME = core.get_current_modname() or "smp_spawners"
smp_spawners = { S = core.get_translator(MODNAME) }
local S = smp_spawners.S

----------------------------------------------------------------------
-- Configuration (f07 §7)
----------------------------------------------------------------------

local function num(key, default)
	local v = tonumber(core.settings:get(key))
	if v == nil then return default end
	return v
end
local function str(key, default)
	local v = core.settings:get(key)
	if v == nil or v == "" then return default end
	return v
end
local function bool(key, default)
	return core.settings:get_bool(key) or default
end

smp_spawners.cfg = {
	-- PROPOSED: single-spawner rate, roughly a vanilla spawner.
	r = num("spawners.r", 6),
	-- timer interval; the clamp for active_only is 2 x this (f07 §4.5)
	timer_interval = num("spawners.timer_interval", 60),
	-- active_only | always | capped (default active_only)
	accrual_mode = str("spawners.accrual_mode", "active_only"),
	-- PROPOSED, used only by accrual_mode = "capped"
	offline_cap_hours = num("spawners.offline_cap_hours", 24),
	-- LIVE [S24]: the whole held stack merges
	stack_mode = str("spawners.stack_mode", "all"),
	-- f07 §4.4
	storage = {
		per_spawner = num("spawners.storage.per_spawner", 2880),  -- PROPOSED
		hard_cap = num("spawners.storage.hard_cap", 2147483647),  -- PROPOSED
	},
	xp = {
		per_spawner_cap = num("spawners.xp.per_spawner_cap", 2000), -- PROPOSED
	},
	-- CLONE [C3]
	require_silk_touch = bool("spawners.require_silk_touch", true),
	sneak_break_max = num("spawners.sneak_break_max", 64),
	-- PROPOSED
	open_requires_access = bool("spawners.open_requires_access", false),
	blast_immune = bool("spawners.blast_immune", true),
	convert_natural = bool("spawners.convert_natural", false),
	-- f07 §4.6.8: optional hopper extraction, off by default
	hopper_extraction = bool("spawners.hopper_extraction", false),
	-- f07 §4.2 "conditional" creeper (f07 §10)
	enable_creeper = bool("spawners.enable_creeper", true),
	-- f07 §4.7: no new supply; admin issue only [S10]
	acquisition = {
		shard_shop = bool("spawners.acquisition.shard_shop", false),
		crates = bool("spawners.acquisition.crates", false),
		natural = bool("spawners.acquisition.natural", false),
		admin = bool("spawners.acquisition.admin", true),
	},
	-- C per type: skeleton is LIVE [S24]; the rest PROPOSED.
	-- (types.lua carries the defaults; a setting overrides one type.)
	C = setmetatable({}, {
		__index = function(_, type_id)
			local def = smp_spawners.types.def[type_id]
			return def and def.C or nil
		end,
	}),
}
do
	local raw = core.settings:get("spawners.C")
	if raw and raw ~= "" then
		for pair in raw:gmatch("([^,%s]+)=([^,%s]+)") do
			local id, v = pair:match("^([^=]+)=[^=]*(%d+%.?%d*)$")
			local val = tonumber(v)
			if id and val and val > 0 then
				smp_spawners.cfg.C[id] = val
			end
		end
	end
end

----------------------------------------------------------------------
-- Submodules
----------------------------------------------------------------------

local modpath = core.get_modpath(MODNAME)
for _, file in ipairs({
	"types.lua",
	"accrue.lua",
	"item.lua",
	"node.lua",
	"performance.lua",
	"interaction.lua",
	"formspecs.lua",
	"routing.lua",
}) do
	local chunk, err = loadfile(modpath .. "/" .. file)
	if not chunk then
		error("[smp_spawners] cannot load " .. file .. ": " .. tostring(err))
	end
	local ok, lerr = pcall(chunk)
	if not ok then
		error("[smp_spawners] error in " .. file .. ": " .. tostring(lerr))
	end
end

smp_spawners.formspecs.register_handler()
smp_spawners.formspecs.register_leave()

----------------------------------------------------------------------
-- Commands (f07 §2)
----------------------------------------------------------------------

local function usage(sender)
	core.chat_send_player(sender, S("/spawner give <player> <type> [count]"))
end

-- The smp_admin privilege is registered by smp_admin (load order in
-- modpack.conf puts it before us).
core.register_chatcommand("spawner", {
	privilege = "smp_admin",
	func = function(sender, params)
		local parts = {}
		for w in params:gmatch("%S+") do parts[#parts + 1] = w end

		if #parts == 0 then usage(sender) return end
		if parts[1] ~= "give" then usage(sender) return end

		local target, type_id = parts[2], parts[3]
		if not target or not type_id then usage(sender) return end
		if not smp_spawners.cfg.acquisition.admin then
			core.chat_send_player(sender,
				S("Administrative spawner issue is disabled"))
			return
		end
		if not smp_spawners.types.get(type_id) then
			core.chat_send_player(sender, S("Unknown spawner type"))
			return
		end
		local count = 1
		if parts[4] then
			local n = math.floor(tonumber(parts[4]) or 0)
			if n < 1 or n > 64 then
				core.chat_send_player(sender,
					S("Count must be between 1 and 64"))
				return
			end
			count = n
		end
		local player = core.get_player_by_name(target)
		if not player then
			core.chat_send_player(sender, S("Player not found: @1", target))
			return
		end
		local stack = smp_spawners.make_item(type_id, count)
		local inv = player:get_inventory()
		if not inv:add_item("main", stack) then
			core.item_drop(player:get_pos(), stack)
		end
		core.chat_send_player(sender,
			S("Gave @1 @2 @3 Spawner", target, count,
				smp_spawners.types.get(type_id).display))
		return true
	end,
})

core.log("action",
	"[smp_spawners] loaded: virtual spawners, node timer " ..
	smp_spawners.cfg.timer_interval .. "s, accrual " ..
	smp_spawners.cfg.accrual_mode)
