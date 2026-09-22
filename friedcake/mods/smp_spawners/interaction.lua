-- FriedcakeSMP — smp_spawners / interaction.lua
-- Place, stacking, menu open and the re-validation shared by every
-- menu action. f07 §4.6, §4.8; shared §2.3, §2.6 R7.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_spawners.S
local cfg = smp_spawners.cfg

smp_spawners.interaction = {}

-- Maximum signed 32-bit spawner stack [S24].
local MAX_STACK = 2147483647
smp_spawners.MAX_STACK = MAX_STACK

-- Menu actions require the player within 8 nodes (f07 §4.8, R7).
local MAX_MENU_DIST2 = 8 * 8

function smp_spawners.within_menu_range(pos, player)
	if not player or not player.get_pos then return false end
	local ppos = player:get_pos()
	if not ppos then return false end
	local dx = ppos.x - pos.x
	local dy = ppos.y - pos.y
	local dz = ppos.z - pos.z
	return (dx * dx + dy * dy + dz * dz) <= MAX_MENU_DIST2
end

----------------------------------------------------------------------
-- Placement (f07 §4.6.1)
----------------------------------------------------------------------

function smp_spawners.interaction.place(placer, pointed_thing, itemstack)
	if not placer or not pointed_thing then return itemstack end
	local ptype = smp_spawners.item_type(itemstack)
	if not ptype then return itemstack end

	local placepos = pointed_thing.above or pointed_thing.node
	if not placepos then return itemstack end
	if core.is_protected(placepos, "place", placer) then
		core.chat_send_player(placer:get_player_name(),
			S("This area is protected"))
		return itemstack
	end
	local existing = core.get_node_or_nil(placepos)
	if existing and existing.name ~= "air" and existing.name ~= "ignore" then
		return itemstack
	end

	-- Validate done; no yields from here on (shared §2.3).
	local ok = core.place_node(placepos,
		ItemStack("smp_spawners:spawner"), placer)
	if not ok then return itemstack end
	smp_spawners.init_meta(placepos, ptype)
	smp_spawners.performance.start_timer(placepos)

	itemstack = itemstack:remove_item(1)
	return itemstack
end

----------------------------------------------------------------------
-- Stacking (f07 §4.6.2, LIVE [S24] stack_mode = "all")
-- Sneak + right-click with a same-type spawner item adds the whole
-- held stack. Other types are rejected. Requires protection access.
----------------------------------------------------------------------

function smp_spawners.interaction.add_stack(pos, player, itemstack)
	local name = player:get_player_name()
	if itemstack:get_name() ~= "smp_spawners:spawner_item" then
		return itemstack
	end
	local ptype = smp_spawners.item_type(itemstack)
	if not ptype then
		core.chat_send_player(name, S("Unknown spawner type"))
		return itemstack
	end
	if core.is_protected(pos, "place", player) then
		core.chat_send_player(name, S("This area is protected"))
		return itemstack
	end

	-- Validate first (shared §2.3).
	local state = smp_spawners.read_state(pos)
	if not state then
		core.chat_send_player(name, S("This spawner has changed"))
		return itemstack
	end
	if state.type_id ~= ptype then
		core.chat_send_player(name,
			S("Different spawner types cannot be stacked"))
		return itemstack
	end
	local held = itemstack:get_count()
	if state.stack + held > MAX_STACK then
		core.chat_send_player(name,
			S("The stack would exceed the maximum size"))
		return itemstack
	end

	-- Mutate. No yields.
	state.stack = state.stack + held
	smp_spawners.write_state(state)
	return itemstack:remove_item(held)
end

----------------------------------------------------------------------
-- Menu open (f07 §4.6.3, §4.6.6)
----------------------------------------------------------------------

function smp_spawners.interaction.open_menu(pos, player)
	local name = player:get_player_name()
	if cfg.open_requires_access and
	   core.is_protected(pos, "interact", player) then
		core.chat_send_player(name, S("This area is protected"))
		return
	end
	local state = smp_spawners.read_state(pos)
	if not state then
		core.chat_send_player(name, S("This spawner has changed"))
		return
	end
	smp_spawners.formspecs.open(pos, player, state)
end

----------------------------------------------------------------------
-- Shared re-validation for every menu action (f07 §4.8, R7).
--
-- The node must still exist, still be a spawner of the same type the
-- menu was opened on, have a positive stack, and the player must be
-- within 8 nodes. Returns the fresh state or nil. The fresh state is
-- what every action acts on — a second collector always sees the
-- first one's updated counts (T6).
----------------------------------------------------------------------

function smp_spawners.revalidate(pos, opened_type, player)
	local node = core.get_node_or_nil(pos)
	if not node or node.name ~= "smp_spawners:spawner" then return nil end
	local state = smp_spawners.read_state(pos)
	if not state then return nil end
	if opened_type and state.type_id ~= opened_type then return nil end
	if not smp_spawners.within_menu_range(pos, player) then return nil end
	return state
end

----------------------------------------------------------------------
-- Taking stored output
--
-- Integer boundary: virtual counts are floats; a take is
-- math.floor(count) items, never more, and can only take what is
-- whole. Fractional remainders stay stored (f07 §4.2, §4.4).
--
-- Returns (taken, state) or (0, nil) when the re-validation failed
-- (T10: an action on a dug node fails safely).
----------------------------------------------------------------------

function smp_spawners.take(pos, player, opened_type, item_name, n)
	local state = smp_spawners.revalidate(pos, opened_type, player)
	if not state then return 0, nil end
	local count = state.store[item_name] or 0
	local take = math.min(math.floor(count + 0.5 - 1e-9), n or math.huge)
	if take < 1 then
		-- Nothing whole to take; the node is unchanged.
		return 0, state
	end
	state.store[item_name] = count - take
	smp_spawners.write_state(state)

	if player then
		local stack = ItemStack(item_name)
		stack:set_count(take)
		if not player:get_inventory():add_item("main", stack) then
			core.item_drop({ x = state.pos.x, y = state.pos.y + 0.5,
				z = state.pos.z }, stack)
		end
	end
	return take, state
end

----------------------------------------------------------------------
-- Collect XP (f07 §4.4)
----------------------------------------------------------------------

function smp_spawners.collect_xp(pos, player, opened_type)
	local state = smp_spawners.revalidate(pos, opened_type, player)
	if not state then return 0, nil end
	local xp = state.xp
	if xp < 1 then
		return 0, state
	end
	state.xp = 0
	smp_spawners.write_state(state)
	if player and mcl_experience and mcl_experience.add_xp then
		mcl_experience.add_xp(player, xp)
	end
	return xp, state
end
