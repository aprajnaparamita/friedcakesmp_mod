-- FriedcakeSMP — smp_spawners / node.lua
-- smp_spawners:spawner — a plain node with metadata and a node timer.
--
-- Cardinal rule (f07 §8, goal G1): this is NEVER an entity and never an
-- ABM. It is a separate node from mcl_mobspawners:spawner, so no
-- mob-spawning code runs. on_blast and on_punch do nothing (T4,
-- f07 §4.6.7).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_spawners.S
local cfg = smp_spawners.cfg

----------------------------------------------------------------------
-- Metadata initialisation (f07 §5)
----------------------------------------------------------------------

function smp_spawners.init_meta(pos, type_id)
	local meta = core.get_meta(pos)
	meta:set_string("smp:type", type_id)
	meta:set_int("smp:stack", 1)
	meta:set_float("smp:last_update", os.time())
	meta:set_string("smp:store", core.serialize({}))
	meta:set_float("smp:xp", 0)
	meta:set_int("smp:version", 0)
	local def = smp_spawners.types.get(type_id)
	meta:set_string("infotext", S("@1 Spawner x@2",
		def and def.display or "Unknown", 1))
end

-- Defensive: cover placements that did not go through the item's
-- on_place (e.g. a creative inventory). Missing keys are filled in;
-- existing state is left alone.
core.register_on_placenode(function(pos, node)
	if node.name ~= "smp_spawners:spawner" then return end
	local meta = core.get_meta(pos)
	if meta:get_string("smp:type") == "" then
		-- Unknown type: this should not happen; make it a skeleton so
		-- the node stays consistent and the menu stays openable.
		core.log("warning",
			"[smp_spawners] spawner placed without a type; " ..
			"defaulting to skeleton at " .. pos.x .. "," .. pos.y .. "," .. pos.z)
		smp_spawners.init_meta(pos, "skeleton")
	end
end)

----------------------------------------------------------------------
-- Digging (f07 §4.6.5, T7, T8)
--
-- Silk Touch is required (spawners.require_silk_touch, CLONE [C3]).
-- A normal dig removes one spawner from the stack; a sneaking dig
-- removes up to spawners.sneak_break_max (64). Partial removals keep
-- the stored output; at zero the node is removed and the remaining
-- storage is lost, as in the clone [C3].
----------------------------------------------------------------------

local function on_dig(pos, node, player, tool)
	local name = player and player:get_player_name()

	-- Refused without Silk Touch (PROPOSED, T7). The node survives.
	if cfg.require_silk_touch then
		local has_st = tool and mcl_enchanting and
			mcl_enchanting.has_enchantment and
			mcl_enchanting.has_enchantment(tool, "silk_touch")
		if not has_st then
			if name then
				core.chat_send_player(name,
					S("Silk Touch is required to dig a spawner"))
			end
			return
		end
	end

	if core.is_protected(pos, "dig", player) then
		if name then
			core.chat_send_player(name, S("This area is protected"))
		end
		return
	end

	-- Validate before mutating (shared §2.3); no yields in between.
	local state = smp_spawners.read_state(pos)
	if not state then return end

	local count = 1
	if player and player.get_player_control and
	   (player:get_player_control() or {}).sneak then
		count = math.min(cfg.sneak_break_max, state.stack)
	end

	-- Stop the timer first so the removed node keeps no timer.
	smp_spawners.performance.stop_timer(pos)

	state.stack = state.stack - count
	if state.stack <= 0 then
		-- Node removed; remaining storage lost, as in the clone [C3].
		core.node_dig(pos, node)
	else
		smp_spawners.write_state(state)
	end

	if not player then return end
	local stack = smp_spawners.make_item(state.type_id, count)
	local inv = player:get_inventory()
	if not inv:add_item("main", stack) then
		core.item_drop({ x = pos.x, y = pos.y + 0.5, z = pos.z }, stack)
	end
end

----------------------------------------------------------------------
-- Right-click (f07 §4.6.2, §4.6.3)
--
-- Sneak + same-type spawner item: stack the whole held stack.
-- Anything else: open the menu.
----------------------------------------------------------------------

local function on_rightclick(pos, node, player, itemstack)
	if not player then return end

	local held_type = smp_spawners.item_type(itemstack)
	local controls = player.get_player_control and
		player:get_player_control() or {}
	if held_type and controls.sneak then
		return smp_spawners.interaction.add_stack(pos, player, itemstack)
	end
	return smp_spawners.interaction.open_menu(pos, player)
end

----------------------------------------------------------------------
-- Node definition
----------------------------------------------------------------------

core.register_node("smp_spawners:spawner", {
	description = S("Spawner"),
	tiles = { "mcl_mobspawners:mob_spawner.png" },
	paramtype = "light",
	is_ground = true,
	groups = { cracky = 3, oddly_breakable_by_hand = 1 },
	on_dig = on_dig,
	on_rightclick = on_rightclick,
	-- Cardinal rule: explosions do nothing. f07 §4.6.7, T4.
	on_blast = function(pos, intensity)
		-- deliberately empty
	end,
	-- Cardinal rule: punching does nothing.
	on_punch = function()
		-- deliberately empty
	end,
	on_timer = function(pos)
		smp_spawners.accrue(pos)
		-- Reschedule while the block is active (accrual_mode
		-- active_only: the timer only runs then).
		smp_spawners.performance.start_timer(pos)
	end,
})
