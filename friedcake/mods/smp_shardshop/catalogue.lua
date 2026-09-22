-- FriedcakeSMP — smp_shardshop/catalogue.lua
--
-- The shard shop catalogue as documented in September 2026 [S8]
-- (spec/features/f06-shards.md §4.2), mapped to Mineclonia.
--
-- * The Netherite Spear is OMITTED: Mineclonia has no spear [M1].
-- * Netherite armour itemstrings are NOT hard-coded: they are derived
--   from mcl_armor.elements (the input mcl_armor.register_set uses) and
--   confirmed against core.registered_items at runtime.
-- * Enchantment lists are explicit in this table (PROPOSED — Donut
--   sources say only "maximally enchanted"; f06 §10 V-20).
--
-- Prices are SHARD COUNTS (integers), not money.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local M = {}

----------------------------------------------------------------------
-- Netherite armour itemstrings, resolved at runtime.
--
-- mcl_armor.register_set names each piece "<element.name>_<setname>"
-- (verified in ~/dev/mineclonia-git mods/ITEMS/mcl_armor: element names
-- are helmet, chestplate, leggings, boots). We derive the candidate the
-- same way and only return it if it is actually registered, so a
-- Mineclonia change can never make us sell a ghost item.
----------------------------------------------------------------------

local function armor_itemstring(element_name)
	if not (mcl_armor and type(mcl_armor.elements) == "table") then
		return nil
	end
	local el = mcl_armor.elements[element_name]
	if not el or type(el.name) ~= "string" then return nil end
	local candidate = "mcl_armor:" .. el.name .. "_netherite"
	if core.registered_items[candidate] then
		return candidate
	end
	return nil
end

M.armor_itemstring = armor_itemstring

----------------------------------------------------------------------
-- The offers
----------------------------------------------------------------------

M.offers = {
	-- Shard items (amethyst) — never enchanted; the self-destruct timer
	-- is stamped on delivery (smp_amethyst.set_expiry).
	{
		id = "shard_pickaxe",
		name = "Shard Pickaxe",
		shards = 3000,
		item = "smp_amethyst:pickaxe",
	},
	{
		id = "shard_axe",
		name = "Shard Axe",
		shards = 3000,
		item = "smp_amethyst:axe",
	},
	{
		id = "shard_shovel",
		name = "Shard Shovel",
		shards = 3000,
		item = "smp_amethyst:shovel",
	},
	{
		id = "haste_potion",
		name = "Shard Potion of Haste",
		shards = 6000,
		item = "smp_amethyst:haste_potion",
	},

	-- Mace with both of its enchantments [M1]. Levels PROPOSED (V-20).
	{
		id = "mace",
		name = "Mace",
		shards = 2000,
		item = "mcl_tools:mace",
		ench = { density = 5, wind_burst = 3 },
	},

	-- Netherite Spear: OMITTED — no Mineclonia equivalent [M1].

	{
		id = "sword_netherite",
		name = "Netherite Sword",
		shards = 1500,
		item = "mcl_tools:sword_netherite",
		-- "Maximum enchantments" (PROPOSED, V-20).
		ench = { sharpness = 5, looting = 3, unbreaking = 3, mending = 1 },
	},
	{
		id = "pick_netherite_silk",
		name = "Netherite Pickaxe (Silk Touch)",
		shards = 1000,
		item = "mcl_tools:pick_netherite",
		ench = { efficiency = 5, silk_touch = 1, unbreaking = 3, mending = 1 },
	},
	{
		id = "pick_netherite_fortune",
		name = "Netherite Pickaxe (Fortune)",
		shards = 1000,
		item = "mcl_tools:pick_netherite",
		ench = { efficiency = 5, fortune = 3, unbreaking = 3, mending = 1 },
	},
	{
		id = "shovel_netherite",
		name = "Netherite Shovel",
		shards = 800,
		item = "mcl_tools:shovel_netherite",
		ench = { efficiency = 5, unbreaking = 3, mending = 1 },
	},
	{
		id = "axe_netherite",
		name = "Netherite Axe",
		shards = 600,
		item = "mcl_tools:axe_netherite",
		ench = { efficiency = 5, unbreaking = 3, mending = 1 },
	},
	{
		id = "hoe_netherite",
		name = "Netherite Hoe",
		shards = 500,
		item = "mcl_farming:hoe_netherite",
		ench = { efficiency = 5, unbreaking = 3, mending = 1 },
	},
	{
		id = "bow",
		name = "Bow",
		shards = 500,
		item = "mcl_bows:bow",
		ench = { power = 5, unbreaking = 3, mending = 1 },
	},
	{
		id = "crossbow",
		name = "Crossbow",
		shards = 500,
		item = "mcl_bows:crossbow",
		ench = { quick_charge = 3, multishot = 1, piercing = 4,
			unbreaking = 3, mending = 1 },
	},

	-- Netherite armour, per piece. Leggings and boots lack Blast
	-- Protection [S8]. Itemstrings resolved at runtime (see above).
	{
		id = "armor_helmet",
		name = "Netherite Helmet",
		shards = 1500,
		armor_element = "head",
		ench = { blast_protection = 4, respiration = 3,
			unbreaking = 3, mending = 1 },
	},
	{
		id = "armor_chestplate",
		name = "Netherite Chestplate",
		shards = 1500,
		armor_element = "torso",
		ench = { blast_protection = 4, thorns = 3,
			unbreaking = 3, mending = 1 },
	},
	{
		id = "armor_leggings",
		name = "Netherite Leggings",
		shards = 1500,
		armor_element = "legs",
		ench = { protection = 4, unbreaking = 3, mending = 1 },
	},
	{
		id = "armor_boots",
		name = "Netherite Boots",
		shards = 1500,
		armor_element = "feet",
		ench = { protection = 4, feather_falling = 4, depth_strider = 3,
			unbreaking = 3, mending = 1 },
	},
}

----------------------------------------------------------------------
-- Offer lookup and item resolution
----------------------------------------------------------------------

function M.find_offer(id)
	for _, o in ipairs(M.offers) do
		if o.id == id then return o end
	end
	return nil
end

-- Resolve the itemstring for an offer. nil when the item does not exist
-- in this engine (e.g. an armour piece if mcl_armor is absent) — the
-- offer is then unbuyable and rendered as unavailable.
function M.resolve_item(offer)
	if offer.item then
		return offer.item
	end
	if offer.armor_element then
		return armor_itemstring(offer.armor_element)
	end
	return nil
end

-- Build the stack for an offer: item + enchantments (PROPOSED lists).
-- Amethyst items get their self-destruct timer stamped here.
function M.make_stack(offer)
	local item = M.resolve_item(offer)
	if not item then return nil end
	local stack = ItemStack(item)
	if offer.ench and mcl_enchanting
			and type(mcl_enchanting.set_enchantments) == "function" then
		mcl_enchanting.set_enchantments(stack, offer.ench)
	end
	-- Shard items carry the one-day self-destruct timer from purchase
	-- (f06 §4.3). Other catalogue items are not timed.
	if item:sub(1, 13) == "smp_amethyst:"
			and smp_amethyst and type(smp_amethyst.set_expiry) == "function" then
		smp_amethyst.set_expiry(stack)
	end
	return stack
end

return M
