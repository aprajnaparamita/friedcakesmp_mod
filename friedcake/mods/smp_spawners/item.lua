-- FriedcakeSMP — smp_spawners / item.lua
-- smp_spawners:spawner_item — the stackable spawner item. The spawner
-- TYPE lives in item meta key "type" (f07 §4.6.1); the itemstring is
-- shared by all types.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_spawners.S

-- Build a spawner item of the given type with count n.
function smp_spawners.make_item(type_id, n)
	local stack = ItemStack("smp_spawners:spawner_item")
	stack:set_count(n or 1)
	local meta = stack:get_meta()
	meta:set_string("type", type_id)
	meta:set_string("infotext", S("@1 Spawner",
		smp_spawners.types.get(type_id).display))
	return stack
end

-- Type id carried by a spawner item, or nil.
function smp_spawners.item_type(stack)
	if type(stack) ~= "table" or not stack.get_meta then return nil end
	if stack:get_name() ~= "smp_spawners:spawner_item" then return nil end
	local t = stack:get_meta():get_string("type")
	if t and smp_spawners.types.get(t) then return t end
	return nil
end

core.register_craftitem("smp_spawners:spawner_item", {
	description = S("Spawner"),
	tiles = { "mcl_mobspawners:mob_spawner.png" },
	groups = {
		not_in_creative = 1,   -- no normal supply; admin /spawner give (f07 §4.7)
		not_in_creative_inventory = 1,
	},
	place_influid = false,
	on_place = function(itemstack, user, pointed_thing)
		-- Delegates to interaction.place, which validates and creates
		-- the node. Returns the (possibly decremented) itemstack.
		return smp_spawners.interaction.place(user, pointed_thing, itemstack)
	end,
	-- Infotext is set per-type by smp_spawners.make_item (item meta
	-- "type"); there is no on_construct hook for items in this engine.
})
