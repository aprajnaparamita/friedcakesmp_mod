-- FriedcakeSMP — smp_spawners / types.lua
-- Spawner type table (data only). f07 §4.2.
--
-- Evidence: 0 frames. Every loot and XP number is PROPOSED except where
-- marked otherwise. Only the skeleton asymptote is published
-- (C = 1505.35 kills/min [S24, LIVE]); the single-spawner rate r = 6 and
-- every non-skeleton C are PROPOSED uncalibrated defaults that MUST be
-- calibrated per f07 §4.3 before the rates are trusted.
--
-- Blaze conflict: rods per S10 (more recent than S24's powder).
-- Documented in f07 §10.
--
-- Creeper: f07 §4.2 marks the type "conditional". We implement it and
-- gate it on spawners.enable_creeper (default true), because the single
-- source that documents it [S24] is recent. Decision in f07 §10.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_spawners.types = {}

-- Published skeleton asymptote [S24, LIVE]: 1,505.35 kills/min.
local C_SKELETON_LIVE = 1505.35
-- PROPOSED uncalibrated default asymptote for every other type.
local C_PROPOSED = 250.0

smp_spawners.types.def = {
	skeleton = {
		id = "skeleton",
		display = "Skeleton",
		mob = "mobs_mc:skeleton",
		C = C_SKELETON_LIVE,   -- LIVE [S24]
		r = 6,                 -- PROPOSED (roughly a vanilla spawner)
		-- Bones [S10][S24]
		loot = { ["mcl_mobitems:bone"] = 1.0 },
		xp = 5,                -- PROPOSED
	},
	iron_golem = {
		id = "iron_golem",
		display = "Iron Golem",
		mob = "mobs_mc:iron_golem",
		C = C_PROPOSED,        -- PROPOSED
		r = 6,                 -- PROPOSED
		-- Iron ingots [S10][S24]
		loot = { ["mcl_core:iron_ingot"] = 4.0 },  -- PROPOSED
		xp = 0,                -- PROPOSED
	},
	spider = {
		id = "spider",
		display = "Spider",
		mob = "mobs_mc:spider",
		C = C_PROPOSED,        -- PROPOSED
		r = 6,                 -- PROPOSED
		-- String, spider eyes [S10][S25]
		loot = {
			["mcl_mobitems:string"] = 1.0,       -- PROPOSED
			["mcl_mobitems:spider_eye"] = 0.33,  -- PROPOSED
		},
		xp = 5,                -- PROPOSED
	},
	zombified_piglin = {
		id = "zombified_piglin",
		display = "Zombified Piglin",
		mob = "mobs_mc:zombified_piglin",
		C = C_PROPOSED,        -- PROPOSED
		r = 6,                 -- PROPOSED
		-- Gold nuggets [S10][S24]
		loot = {
			["mcl_core:gold_nugget"] = 0.5,       -- PROPOSED
			["mcl_mobitems:rotten_flesh"] = 0.5,  -- PROPOSED
		},
		xp = 5,                -- PROPOSED
	},
	blaze = {
		id = "blaze",
		display = "Blaze",
		mob = "mobs_mc:blaze",
		C = C_PROPOSED,        -- PROPOSED
		r = 6,                 -- PROPOSED
		-- Blaze rods [S10]. S24 says powder; rods chosen (more recent
		-- source). f07 §10.
		loot = { ["mcl_mobitems:blaze_rod"] = 0.5 },  -- PROPOSED (verify)
		xp = 10,               -- PROPOSED
	},
	zombie = {
		id = "zombie",
		display = "Zombie",
		mob = "mobs_mc:zombie",
		C = C_PROPOSED,        -- PROPOSED
		r = 6,                 -- PROPOSED
		-- Rotten flesh [S10][S24]
		loot = { ["mcl_mobitems:rotten_flesh"] = 1.0 },  -- PROPOSED
		xp = 5,                -- PROPOSED
	},
	pig = {
		id = "pig",
		display = "Pig",
		mob = "mobs_mc:pig",
		C = C_PROPOSED,        -- PROPOSED
		r = 6,                 -- PROPOSED
		-- Raw porkchop [S10][S25]
		loot = { ["mcl_mobitems:porkchop"] = 2.0 },      -- PROPOSED
		xp = 2,                -- PROPOSED
	},
	cow = {
		id = "cow",
		display = "Cow",
		mob = "mobs_mc:cow",
		C = C_PROPOSED,        -- PROPOSED
		r = 6,                 -- PROPOSED
		-- Raw beef, no leather [S10][S24]
		loot = { ["mcl_mobitems:beef"] = 2.0 },          -- PROPOSED
		xp = 2,                -- PROPOSED
	},
	creeper = {
		id = "creeper",
		display = "Creeper",
		mob = "mobs_mc:creeper",
		C = C_PROPOSED,        -- PROPOSED
		r = 6,                 -- PROPOSED
		-- Gunpowder; one source only [S24]. f07 §4.2 "conditional":
		-- gated on spawners.enable_creeper. f07 §10.
		loot = { ["mcl_mobitems:gunpowder"] = 1.0 },     -- PROPOSED
		xp = 5,                -- PROPOSED
		conditional = true,
	},
}

-- Display and /spawner give order.
smp_spawners.types.order = {
	"skeleton", "iron_golem", "spider", "zombified_piglin", "blaze",
	"zombie", "pig", "cow", "creeper",
}

-- Resolve a type id, honouring the creeper gate. nil for unknown or
-- disabled types.
function smp_spawners.types.get(id)
	if type(id) ~= "string" then return nil end
	local def = smp_spawners.types.def[id]
	if not def then return nil end
	if def.conditional and not smp_spawners.cfg.enable_creeper then
		return nil
	end
	return def
end
