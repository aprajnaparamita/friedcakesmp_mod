-- FriedcakeSMP — smp_amethyst/shovel.lua
--
-- Shard Shovel. Pickaxe-style multi-block digging for dirt types [S9]:
-- the same 3x3 plane dig as the Shard Pickaxe, restricted to the
-- dirt-family node list `amethyst.shovel_nodes` (group `shovely` —
-- PROPOSED, f06 §10 V-21).
--
-- Spec: f06 §4.3.

local S = core.get_translator(core.get_current_modname())
local am = smp_amethyst

-- Dirt-family check: group shovely (PROPOSED). Kept in one place so the
-- operator can tighten or widen it in config later.
local function is_shovel_node(groups)
	return (groups and (groups.shovely or 0) > 0) or false
end
smp_amethyst.is_shovel_node = is_shovel_node

core.register_tool("smp_amethyst:shovel", {
	description = S("Shard Shovel"),
	inventory_image = "mcl_amethyst_shard.png",
	wield_image = "mcl_amethyst_shard.png",
	stack_max = 1,
	groups = {
		shovely = 5,
		dig_speed_class = 5,
		enchantability = 10,
		rarity = 2,
	},
	tool_capabilities = {
		full_punch_interval = 0.55,
		max_drop_level = 5,
		damage_groups = { fleshy = 1 },
	},
	sound = { breaks = "default_tool_breaks" },
	on_use_primary = function(itemstack, player, pointed_thing)
		local name = player:get_player_name()

		if am.in_dig(name) then return itemstack end
		if am.is_tagged(name) then
			core.chat_send_player(name,
				S("You cannot use this while in combat"))
			return itemstack
		end
		if am.remove_expired(itemstack, player) then
			return ItemStack("")
		end
		if not pointed_thing or pointed_thing.type ~= "node" then
			return itemstack
		end
		local under, above = pointed_thing.under, pointed_thing.above

		local positions = am.logic.plane_positions(under, above)
		local function eligible(pos)
			local node = core.get_node_or_nil(pos)
			if not node or node.name == "air" then return false end
			local def = core.registered_nodes[node.name]
			if not def or not def.diggable then return false end
			if not is_shovel_node(def.groups) then return false end
			if core.is_protected(pos, name) then return false end
			if am.dig_blacklisted(pos) then return false end
			return true
		end

		if not eligible(under) then
			core.chat_send_player(name, S("Nothing to mine here"))
			return itemstack
		end

		local to_dig = {}
		for _, pos in ipairs(positions) do
			if eligible(pos) then to_dig[#to_dig + 1] = pos end
		end

		am.begin_dig(name)
		local ok, err = pcall(function()
			local did_center = false
			for _, pos in ipairs(to_dig) do
				if am.logic.same_pos(pos, under) then
					core.node_dig(pos, core.get_node(pos), player)
					did_center = true
				else
					am.dig_node_once(pos, player, itemstack:get_name())
				end
			end
			assert(did_center, "center block disappeared")
		end)
		am.end_dig(name)
		if not ok then
			core.log("error", "[smp_amethyst] shovel dig failed: " .. tostring(err))
		end

		am.refresh_description(itemstack)
		player:set_wielded_item(itemstack)
		return itemstack
	end,
})
