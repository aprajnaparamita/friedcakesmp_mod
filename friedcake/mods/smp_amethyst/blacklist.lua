-- FriedcakeSMP — smp_amethyst/blacklist.lua
--
-- The orders blacklist for amethyst (shard) items.
--
-- f06 §4.3: amethyst items are sellable and auctionable but NOT
-- orderable [S9]. f04 (smp_orders) imports this list and refuses to
-- create orders for any of these itemstrings (f04 §4.12,
-- `orders.blacklist`).
--
-- Contract:
--   local blacklist = dofile(modpath .. "/blacklist.lua")
--   -- or, at runtime once smp_amethyst has loaded:
--   --   smp_amethyst.blacklist
--
-- A flat list of exact itemstrings. f04 compares against the resolved
-- item name of the M1 key (shared §2.5), not the full key: amethyst
-- offers are never enchanted or named, so the bare name is the identity
-- that matters.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

return {
	"smp_amethyst:pickaxe",
	"smp_amethyst:axe",
	"smp_amethyst:shovel",
	"smp_amethyst:haste_potion",
	"smp_amethyst:bucket",
	"smp_amethyst:sell_axe",
}
