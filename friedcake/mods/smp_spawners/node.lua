-- FriedcakeSMP — smp_spawners / node.lua
-- smp_spawners:spawner — a plain node with metadata and a node timer.
--
-- Cardinal rule (f07 §8, goal G1): this is NEVER an entity and never an
-- ABM. It is a separate node from mcl_mobspawners:spawner, so no
-- mob-spawning code runs. on_punch does nothing and on_blast only acts
-- when the operator has turned spawners.blast_immune off (f07 §4.6.7,
-- T4).
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

	-- The engine calls on_dig(pos, node, digger) — three arguments only
	-- (luanti src/script/cpp_api/s_node.cpp:118-130, also
	-- serverpackethandler.cpp) — so the wielded tool has to be read off
	-- the player when it is not passed in. Without this, silk could
	-- never be seen in production (f07 §10, engine-truth fix).
	tool = tool or (player and player.get_wielded_item and
		player:get_wielded_item())

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

	-- f07 §4.6.6: core.is_protected(pos, player_name) — the second
	-- argument is a PLAYER NAME (luanti builtin/game/misc.lua), not an
	-- action tag (f07 §10, engine-truth fix).
	if core.is_protected(pos, name) then
		if name then
			core.chat_send_player(name, S("This area is protected"))
		end
		return
	end

	-- f07 §4.5: every interaction converts elapsed time before the
	-- state object that gets written is read (F07-7).
	smp_spawners.accrue(pos)

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
	-- f07 §4.6.7: unmovable_by_piston = 1 aborts the push in Mineclonia
	-- (mods/ITEMS/REDSTONE/mcl_pistons/api.lua:56). container = 7 is
	-- Mineclonia's "no generic movement" class (mcl_util
	-- move_item_container bails on 7 before touching either inventory,
	-- and hopper_push only accepts 2..6): it keeps the virtual storage
	-- out of every container path while still routing hopper pulls to
	-- our own _on_hopper_out hook below (mcl_hoppers init.lua:62-70).
	groups = { cracky = 3, oddly_breakable_by_hand = 1,
		unmovable_by_piston = 1, container = 7 },
	-- Nothing drops from the node itself: the dig path hands the
	-- digger their spawner items, and storage loss is deliberate
	-- (f07 §4.6.5). Without this, get_node_drops returns the bare
	-- node item and the "last spawner" dig leaks one.
	drop = "",
	on_dig = on_dig,
	on_rightclick = on_rightclick,
	-- f07 §4.6.7, T4: blasts are ignored while spawners.blast_immune
	-- (the default). With the toggle off the node behaves like a normal
	-- block — mcl_explosions leaves the removal to us when on_blast is
	-- defined (mods/CORE/mcl_explosions/init.lua:338-341) and drops
	-- nothing because drop = "".
	on_blast = function(pos, intensity, do_drop)
		if cfg.blast_immune then return end
		smp_spawners.performance.stop_timer(pos)
		core.remove_node(pos)
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
	-- f07 §4.6.8: optional hopper extraction (off by default). Mineclonia
	-- calls this before any generic pull (mcl_hoppers init.lua:64-70);
	-- the generic path is blocked by container = 7 anyway.
	_on_hopper_out = function(pos, hpos)
		return smp_spawners.performance.hopper_extract(pos, hpos)
	end,
})

----------------------------------------------------------------------
-- Natural spawners (f07 §4.6.9, spawners.convert_natural)
--
-- Dungeon spawners stay vanilla by default. When the operator turns the
-- key on, a dig that also satisfies the Silk Touch rule converts the
-- vanilla node into a virtual spawner of the matching type instead of
-- breaking it. Type comes from the vanilla `Mob` metadata key, mapped
-- back through types.def[*].mob; an unmapped mob (or a type disabled by
-- spawners.enable_creeper) leaves the vanilla node alone.
----------------------------------------------------------------------

local VANILLA = "mcl_mobspawners:spawner"

if core.registered_nodes and core.registered_nodes[VANILLA] then
	local prev_on_dig = core.registered_nodes[VANILLA].on_dig

	-- reverse map: mob entity name -> spawner type id
	local mob_to_type = {}
	for id, tdef in pairs(smp_spawners.types.def) do
		if tdef.mob then mob_to_type[tdef.mob] = id end
	end

	core.override_item(VANILLA, {
		on_dig = function(pos, node, digger, tool)
			local name = digger and digger.get_player_name and
				digger:get_player_name()
			tool = tool or (digger and digger.get_wielded_item and
				digger:get_wielded_item())
			local has_st = tool and mcl_enchanting and
				mcl_enchanting.has_enchantment and
				mcl_enchanting.has_enchantment(tool, "silk_touch")

			local convert = cfg.convert_natural and name ~= nil
				and (has_st or not cfg.require_silk_touch)
				and not core.is_protected(pos, name)

			if convert then
				local mob = core.get_meta(pos):get_string("Mob")
				local type_id = mob_to_type[mob]
				-- types.get applies the creeper gate (f07 §4.2, V-04).
				if type_id and smp_spawners.types.get(type_id) then
					-- Validate done. set_node runs the vanilla
					-- on_destruct (doll + XP cleanup) and clears the
					-- metadata, so the Mob key is read first.
					core.set_node(pos, { name = "smp_spawners:spawner" })
					smp_spawners.init_meta(pos, type_id)
					smp_spawners.performance.start_timer(pos)
					return
				end
			end

			if prev_on_dig then return prev_on_dig(pos, node, digger, tool) end
			return core.node_dig(pos, node, digger)
		end,
	})
end
