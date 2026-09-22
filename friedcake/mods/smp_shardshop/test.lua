-- FriedcakeSMP — smp_shardshop acceptance tests
-- Loaded in-game via `/smp test smp_shardshop`.
--
-- Covers the engine-testable parts of spec/features/f06-shards.md §9:
--   T7: catalogue prices match f06 §4.2; the spear is omitted [M1];
--       amethyst items are in the orders blacklist
--   T9: the entry point smp_shardshop.open(player) is exposed with the
--       observed control tooltip, and /shardshop opens the shop
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator and core.get_translator("smp_shardshop")
	or function(s, ...) return s end

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "ok")
	end
end

local cat = smp_shardshop.catalogue
local by_id = {}
for _, o in ipairs(cat.offers) do by_id[o.id] = o end

-- T7: the documented prices (f06 §4.2, LIVE [S8]).
local prices = {
	shard_pickaxe = 3000,
	shard_axe = 3000,
	shard_shovel = 3000,
	haste_potion = 6000,
	mace = 2000,
	sword_netherite = 1500,
	pick_netherite_silk = 1000,
	pick_netherite_fortune = 1000,
	shovel_netherite = 800,
	axe_netherite = 600,
	hoe_netherite = 500,
	bow = 500,
	crossbow = 500,
	armor_helmet = 1500,
	armor_chestplate = 1500,
	armor_leggings = 1500,
	armor_boots = 1500,
}
for id, shards in pairs(prices) do
	ok(by_id[id] ~= nil, id .. " offered")
	if by_id[id] then
		ok(by_id[id].shards == shards,
			id .. " costs " .. shards .. " shards")
	end
end

-- The Netherite Spear is omitted: no Mineclonia spear [M1].
local has_spear = false
for _, o in ipairs(cat.offers) do
	if o.id == "spear" or o.name:find("Spear") ~= nil then
		has_spear = true
	end
end
ok(has_spear == false, "netherite spear omitted")

-- Netherite armour itemstrings resolved at runtime (not hard-coded),
-- and all four pieces exist in this engine.
for _, el in ipairs({ "head", "torso", "legs", "feet" }) do
	local offer = by_id["armor_" .. el]
	if offer then
		local item = cat.resolve_item(offer)
		ok(item ~= nil and core.registered_items[item] ~= nil,
			"armour piece resolved: " .. el)
	end
end

-- Leggings and boots lack Blast Protection [S8].
ok(by_id.armor_leggings and
	by_id.armor_leggings.ench.blast_protection == nil,
	"leggings: no blast protection")
ok(by_id.armor_boots and
	by_id.armor_boots.ench.blast_protection == nil,
	"boots: no blast protection")

-- T7 (blacklist): every amethyst offer is order-blacklisted.
local blacklisted = {}
for _, name in ipairs(smp_amethyst and smp_amethyst.blacklist or {}) do
	blacklisted[name] = true
end
for _, o in ipairs(cat.offers) do
	if o.item and o.item:sub(1, 13) == "smp_amethyst:" then
		ok(blacklisted[o.item] == true, o.item .. " is order-blacklisted")
	end
end

-- T9: the entry point f04 uses, with the observed control tooltip
-- [F0179, F0182].
ok(type(smp_shardshop.open) == "function", "open(player) exposed")
ok(smp_shardshop.SHARD_CONTROL and
	smp_shardshop.SHARD_CONTROL.tooltip[1] == "Shard Shop",
	"control tooltip line 1: Shard Shop")
ok(smp_shardshop.SHARD_CONTROL and
	smp_shardshop.SHARD_CONTROL.tooltip[2] == "Click to view",
	"control tooltip line 2: Click to view")
ok(core.registered_chatcommands["shardshop"] ~= nil,
	"/shardshop registered")

-- The shop formspec renders with the title and the grid.
local fs = smp_shardshop.fs.shop_form(12345)
ok(type(fs) == "string" and fs:find("Shard Shop") ~= nil,
	"shop formspec renders the title")
ok(fs:find("offer_shard_pickaxe") ~= nil, "shop grid has the offers")
ok(fs:find("Inventory") ~= nil, "shop shows the player inventory")

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_shardshop tests passed."
else
	results.lines[#results.lines + 1] =
		string.format("%d failures.", results.failed)
end
return results
