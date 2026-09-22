-- FriedcakeSMP — smp_sell/prices_default.lua
--
-- Shipped base-price table for `/sell` and `/worth` (f02 §4.9, §7).
--
-- VALUES ARE INTEGER CENTS (AGENTS.md hard rule 6: money is integer cents,
-- floats are forbidden). 1000 = $10.00.
--
-- Anchors that come from evidence:
--   mcl_mobitems:bone  1000   $10.00 per bone — the figure used throughout
--                              the v0.1 spec ("a base price of $10.00 per
--                              bone"), and the value f02 §5's schema example
--                              computes with (400 bones -> $4,000).
--   mcl_core:cobble     600   "cobblestone ... set to 6 on 27 June 2026" [S2]
--   mcl_walls:cobble    700   "cobblestone walls ... 7 on 27 June 2026" [S2]
--                              The unit of those two numbers is not stated in
--                              the source; dollars is the reading adopted
--                              here. See f02 §10 V-88.
--
-- EVERY OTHER VALUE IS `PROPOSED`. They are placeholders that keep the
-- feature playable and the acceptance tests meaningful; operators are
-- expected to replace them. All itemstrings below were verified against
-- ~/dev/mineclonia-git (the engine source-of-truth named in AGENTS.md), not
-- against the stale commit pinned in spec/README.md.
--
-- Operators override this file WITHOUT editing the modpack: put a Lua file
-- returning `{ ["mcl_core:diamond"] = 1250000, ... }` at
--   <worlddir>/smp_sell_prices.lua
-- (or point `sell.base_prices` at any path) and run `/smp reload`. Override
-- values replace defaults per item; a value of 0 or false removes an item
-- from the sellable set.

return {
	-- Stone and earth ------------------------------------------------
	["mcl_core:stone"]              = 700,
	["mcl_core:cobble"]              = 600,   -- anchor [S2]
	["mcl_core:mossycobble"]         = 900,
	["mcl_core:stone_smooth"]        = 800,
	["mcl_core:stonebrick"]          = 800,
	["mcl_core:dirt"]                = 100,
	["mcl_core:dirt_with_grass"]     = 150,
	["mcl_core:coarse_dirt"]         = 120,
	["mcl_core:sand"]                = 200,
	["mcl_core:redsand"]             = 250,
	["mcl_core:sandstone"]           = 300,
	["mcl_core:gravel"]              = 200,
	["mcl_core:flint"]               = 500,
	["mcl_core:obsidian"]            = 50000,
	["mcl_walls:cobble"]             = 700,   -- anchor [S2]
	["mcl_walls:mossycobble"]        = 1000,
	["mcl_amethyst:calcite"]         = 900,
	["mcl_amethyst:tinted_glass"]    = 4000,
	["mcl_amethyst:amethyst_block"]  = 48000,
	["mcl_amethyst:amethyst_shard"]  = 12000,
	["mcl_nether:quartz"]            = 3000,
	["mcl_end:end_stone"]            = 1200,

	-- Ores and ingots ------------------------------------------------
	["mcl_core:coal_lump"]           = 2000,
	["mcl_core:charcoal_lump"]       = 1500,
	["mcl_core:lapis"]               = 6000,
	["mcl_core:iron_ingot"]          = 25000,
	["mcl_core:iron_nugget"]         = 2700,
	["mcl_core:gold_ingot"]          = 60000,
	["mcl_core:gold_nugget"]         = 6600,
	["mcl_core:diamond"]             = 900000,
	["mcl_core:emerald"]             = 1200000,
	["mcl_core:coalblock"]           = 18000,
	["mcl_core:ironblock"]           = 225000,
	["mcl_core:goldblock"]           = 540000,
	["mcl_core:diamondblock"]        = 8100000,
	["mcl_core:emeraldblock"]        = 10800000,
	["mcl_core:lapisblock"]          = 54000,
	["mcl_redstone:redstone"]        = 4000,

	-- Wood -----------------------------------------------------------
	["mcl_trees:wood_oak"]           = 300,
	["mcl_trees:wood_spruce"]        = 300,
	["mcl_trees:wood_birch"]         = 300,
	["mcl_trees:wood_jungle"]        = 350,
	["mcl_trees:wood_acacia"]        = 350,
	["mcl_trees:wood_dark_oak"]      = 350,

	-- Mob drops ------------------------------------------------------
	["mcl_mobitems:bone"]            = 1000,  -- anchor ($10.00)
	["mcl_core:bone_block"]          = 9000,
	["mcl_mobitems:rotten_flesh"]    = 300,
	["mcl_mobitems:string"]          = 800,
	["mcl_mobitems:spider_eye"]      = 900,
	["mcl_mobitems:gunpowder"]       = 1500,
	["mcl_mobitems:slimeball"]       = 2500,
	["mcl_mobitems:leather"]         = 3000,
	["mcl_mobitems:feather"]         = 600,
	["mcl_mobitems:blaze_rod"]       = 25000,
	["mcl_throwing:ender_pearl"]     = 70000, -- $700, matching the observed
	                                           -- Ender Pearl listing [F0108]
	["mcl_throwing:egg"]             = 250,
	["mcl_mobitems:shulker_shell"]   = 400000,
	["mcl_totems:totem"]             = 3000000, -- $30K, matching the observed
	                                             -- totem delivery [F0227]
	["mcl_mobitems:beef"]            = 900,
	["mcl_mobitems:porkchop"]        = 900,
	["mcl_mobitems:chicken"]         = 800,
	["mcl_mobitems:mutton"]          = 850,
	["mcl_mobitems:rabbit"]          = 800,
	["mcl_mobitems:cooked_beef"]     = 1400,
	["mcl_mobitems:cooked_porkchop"] = 1400,
	["mcl_mobitems:cooked_chicken"]  = 1300,
	["mcl_mobitems:cooked_mutton"]   = 1350,
	["mcl_mobitems:cooked_rabbit"]   = 1300,

	-- Farming --------------------------------------------------------
	["mcl_farming:wheat_item"]       = 500,
	["mcl_farming:wheat_seeds"]      = 100,
	["mcl_farming:carrot_item"]      = 400,
	["mcl_farming:potato_item"]      = 400,
	["mcl_farming:potato_item_baked"] = 700,
	["mcl_farming:beetroot_item"]    = 450,
	["mcl_farming:beetroot_seeds"]   = 100,
	["mcl_farming:bread"]            = 1500,
	["mcl_farming:beetroot_soup"]    = 2000,
	["mcl_core:apple"]               = 700,
	["mcl_core:apple_gold"]          = 90000,

	-- Miscellaneous --------------------------------------------------
	["mcl_books:book"]               = 1200,
	["mcl_books:bookshelf"]          = 5000,
	["mcl_chests:chest"]             = 2500,
	["mcl_chests:violet_shulker_box"] = 1500000,
	["mcl_chests:violet_shulker_box_small"] = 1500000,
	["mcl_end:dragon_egg"]           = 0,     -- not sellable (trophy)

	-- Tools ----------------------------------------------------------
	-- Only a PRISTINE tool is sellable: M0 rejects wear, enchantments and
	-- custom names (shared §2.5), which is most of the tools in circulation.
	["mcl_tools:pick_wood"]          = 900,
	["mcl_tools:shovel_wood"]        = 500,
	["mcl_tools:axe_wood"]           = 1100,
	["mcl_tools:sword_wood"]         = 900,
	["mcl_tools:pick_stone"]         = 1500,
	["mcl_tools:shovel_stone"]       = 800,
	["mcl_tools:axe_stone"]          = 1800,
	["mcl_tools:sword_stone"]        = 1500,
	["mcl_tools:pick_copper"]        = 12000,
	["mcl_tools:sword_copper"]       = 12000,
	["mcl_tools:pick_iron"]          = 60000,
	["mcl_tools:shovel_iron"]        = 30000,
	["mcl_tools:axe_iron"]           = 70000,
	["mcl_tools:sword_iron"]         = 55000,
	["mcl_tools:pick_gold"]          = 140000,
	["mcl_tools:sword_gold"]         = 130000,
	["mcl_tools:pick_diamond"]       = 2100000,
	["mcl_tools:shovel_diamond"]     = 1000000,
	["mcl_tools:axe_diamond"]        = 2400000,
	["mcl_tools:sword_diamond"]      = 1900000,
	["mcl_tools:pick_netherite"]     = 9000000,
	["mcl_tools:shovel_netherite"]   = 4500000,
	["mcl_tools:axe_netherite"]      = 10000000,
	["mcl_tools:sword_netherite"]    = 8000000,
	["mcl_tools:shears"]             = 25000,
	["mcl_tools:mace"]               = 12000000,
}
