-- FriedcakeSMP — smp_amethyst/pickaxe.lua
--
-- Shard Pickaxe ("drill"). Mines nine blocks at once [S9]: the pointed
-- block plus its 8 neighbours in the plane perpendicular to the dug
-- face. Deliberately unusable in combat [S19] — refused while tagged.
--
-- Each mined block must be diggable by a pickaxe (group `pickaxey`),
-- unprotected and not in the dig blacklist (bedrock, barriers, spawner
-- nodes, containers — PROPOSED). The primary block is dug with
-- core.node_dig so wear is applied exactly once per use; the neighbours
-- are removed with smp_amethyst.dig_node_once (no wear, no re-entry).
--
-- Spec: f06 §4.3. Acceptance T4, T5.

local S = core.get_translator(core.get_current_modname())
local am = smp_amethyst

core.register_tool("smp_amethyst:pickaxe", {
	description = S("Shard Pickaxe"),
	inventory_image = "mcl_amethyst_shard.png",
	wield_image = "mcl_amethyst_shard.png",
	stack_max = 1,
	groups = {
		pickaxey = 5,
		dig_speed_class = 5,
		enchantability = 10,
		rarity = 2,
	},
	tool_capabilities = {
		full_punch_interval = 0.5,
		max_drop_level = 5,
		damage_groups = { fleshy = 1 },
	},
	sound = { breaks = "default_tool_breaks" },
	on_use_primary = function(itemstack, player, pointed_thing)
		local name = player:get_player_name()

		-- Re-entrancy guard: a dig callback that re-enters this tool
		-- would loop forever (f06 §8).
		if am.in_dig(name) then
			return itemstack
		end

		-- Refused while combat-tagged [S19].
		if am.is_tagged(name) then
			core.chat_send_player(name,
				S("You cannot use this while in combat"))
			return itemstack
		end

		-- Expired items are removed on use (T3).
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
			local groups = def.groups or {}
			if (groups.pickaxey or 0) <= 0 then return false end
			if core.is_protected(pos, name) then return false end
			if am.dig_blacklisted(pos) then return false end
			return true
		end

		-- The pointed block must itself be a valid drill target.
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
					-- Primary block: full engine dig — protection,
					-- drops, after_dig_node, and ONE application of wear.
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
			core.log("error", "[smp_amethyst] pickaxe dig failed: " .. tostring(err))
		end

		-- Description refreshes with the remaining time on use.
		am.refresh_description(itemstack)
		player:set_wielded_item(itemstack)
		return itemstack
	end,
})
