-- FriedcakeSMP — smp_amethyst/axe.lua
--
-- Shard Axe. Fells a tree with its connected logs and leaves [S9]:
-- from the dug log, a breadth-first search through nodes in the
-- `tree` and `leaves` groups (used by mcl_trees) removes the connected
-- tree, limited to `amethyst.felling_limit` nodes and protection-
-- checked per node.
--
-- Pointing at a non-log performs a normal single-node dig, so the axe
-- is still usable as an axe.
--
-- Spec: f06 §4.3. Acceptance T6 (stops at felling_limit).

local S = core.get_translator(core.get_current_modname())
local am = smp_amethyst

core.register_tool("smp_amethyst:axe", {
	description = S("Shard Axe"),
	inventory_image = "mcl_amethyst_shard.png",
	wield_image = "mcl_amethyst_shard.png",
	stack_max = 1,
	groups = {
		axey = 5,
		dig_speed_class = 5,
		enchantability = 10,
		rarity = 2,
	},
	tool_capabilities = {
		full_punch_interval = 0.625,
		max_drop_level = 5,
		damage_groups = { fleshy = 2 },
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
		local start = pointed_thing.under
		local node = core.get_node_or_nil(start)
		if not node or node.name == "air" then return itemstack end
		local def = core.registered_nodes[node.name]
		local groups = def and def.groups or {}

		-- Not a log: behave as a normal axe (one node).
		if not groups.tree then
			core.node_dig(start, node, player)
			am.refresh_description(itemstack)
			player:set_wielded_item(itemstack)
			return itemstack
		end

		-- Fell: BFS through connected logs and leaves.
		local positions = am.logic.bfs_connected(start, function(pos)
			local n = core.get_node_or_nil(pos)
			if not n or n.name == "air" then return nil end
			local d = core.registered_nodes[n.name]
			return d and d.groups or nil
		end, { "tree", "leaves" }, am.cfg.felling_limit)

		am.begin_dig(name)
		local ok, err = pcall(function()
			for _, pos in ipairs(positions) do
				if am.logic.same_pos(pos, start) then
					core.node_dig(pos, core.get_node(pos), player)
				else
					am.dig_node_once(pos, player, itemstack:get_name())
				end
			end
		end)
		am.end_dig(name)
		if not ok then
			core.log("error", "[smp_amethyst] axe felling failed: " .. tostring(err))
		end

		core.chat_send_player(name, S("Felled @1 blocks.", #positions))
		am.refresh_description(itemstack)
		player:set_wielded_item(itemstack)
		return itemstack
	end,
})
