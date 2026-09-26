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
	-- f07 §4.6.6: core.is_protected(pos, player_name) — the second
	-- argument is a PLAYER NAME (luanti builtin/game/misc.lua), not an
	-- action tag (f07 §10, engine-truth fix).
	if core.is_protected(placepos, placer:get_player_name()) then
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

	-- Engine truth (S06): ItemStack has no `remove_item` (l_item.cpp
	-- method table); `take_item(n)` removes and returns the taken
	-- items, and `itemstack` itself is the remainder.
	itemstack:take_item(1)
	return itemstack
end

----------------------------------------------------------------------
-- Stacking (f07 §4.6.2, §7 `spawners.stack_mode`)
-- Sneak + right-click with a same-type spawner item adds the held
-- stack — the whole stack for `all` (LIVE [S24], the default), one
-- spawner for `one`. Other types are rejected. Requires protection
-- access.
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
	if core.is_protected(pos, name) then
		core.chat_send_player(name, S("This area is protected"))
		return itemstack
	end

	-- f07 §4.5: accrue before the state object that gets written
	-- (F07-7). Cheap refusals above stay free.
	smp_spawners.accrue(pos)

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
	-- f07 §7 spawners.stack_mode: "all" (LIVE [S24], default) merges
	-- the whole held stack; "one" adds a single spawner per click.
	-- Any other value warned at load and behaves as "all".
	if cfg.stack_mode == "one" then
		held = math.min(held, 1)
	end
	if state.stack + held > MAX_STACK then
		core.chat_send_player(name,
			S("The stack would exceed the maximum size"))
		return itemstack
	end

	-- Mutate. No yields.
	state.stack = state.stack + held
	smp_spawners.write_state(state)
	-- Engine truth (S06): ItemStack has no `remove_item` — the method
	-- table is l_item.cpp:535-566 and the mutation is `take_item(n)`
	-- (returns the REMOVED items; lua_api.md, ItemStack section). The
	-- old `itemstack:remove_item(held)` raised in a real engine.
	itemstack:take_item(held)
	return itemstack
end

----------------------------------------------------------------------
-- Menu open (f07 §4.6.3, §4.6.6)
----------------------------------------------------------------------

function smp_spawners.interaction.open_menu(pos, player)
	local name = player:get_player_name()
	if cfg.open_requires_access and
	   core.is_protected(pos, name) then
		core.chat_send_player(name, S("This area is protected"))
		return
	end
	-- f07 §4.5: a menu always shows accrual up to now (F07-7), and it
	-- happens before the state object that render/open uses.
	smp_spawners.accrue(pos)
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
-- within 8 nodes. Returns the fresh state or nil (a second return
-- value of `"protected"` says the refusal was S06/SP-4). The fresh
-- state is what every action acts on — a second collector always sees
-- the first one's updated counts (T6).
--
-- `need_access` (S06/SP-4) is passed by the MUTATING actions only
-- (take, Collect XP, Sell all): those additionally require
-- `core.is_protected(pos, name) == false`. Viewing (render, paging,
-- menu open) stays open — see f07 §10 for the ESCALATE proposal to
-- flip `spawners.open_requires_access` to true.
--
-- The protection check runs BEFORE the accrual conversion, so a
-- refused action mutates nothing at all (validate, then mutate,
-- shared §2.3).
--
-- Every caller also converts elapsed time here (f07 §4.5 "every
-- interaction converts elapsed time", F07-7), so takes, Collect XP and
-- Sell all can never show or pay less than what the spawner produced
-- since last_update.
----------------------------------------------------------------------

function smp_spawners.revalidate(pos, opened_type, player, need_access)
	local node = core.get_node_or_nil(pos)
	if not node or node.name ~= "smp_spawners:spawner" then return nil end
	if not smp_spawners.within_menu_range(pos, player) then return nil end
	if need_access then
		local name = player and player.get_player_name and
			player:get_player_name()
		-- Fail closed without a player name (S06/SP-4).
		if type(name) ~= "string" or name == "" then return nil end
		if core.is_protected(pos, name) then
			core.chat_send_player(name, S("This area is protected"))
			return nil, "protected"
		end
	end
	smp_spawners.accrue(pos)
	local state = smp_spawners.read_state(pos)
	if not state then return nil end
	if opened_type and state.type_id ~= opened_type then return nil end
	return state
end

----------------------------------------------------------------------
-- Taking stored output
--
-- Integer boundary: virtual counts are floats; a take is
-- math.floor(count) items, never more, and can only take what is
-- whole. Fractional remainders stay stored (f07 §4.2, §4.4).
--
-- S06/SP-3: one ItemStack holds at most `stack_max` items and
-- `ItemStack:set_count(n)` CLEARS the stack for n > 65535
-- (l_item.cpp:91-96), so the take is capped at what the inventory can
-- hold (stack_max x free space) and delivered in chunks of at most
-- stack_max.
--
-- S06/SP-2: the store is decremented only by what was actually
-- delivered; anything the inventory refused stays stored (the old code
-- decremented first and then destroyed the leftover).
--
-- Returns (taken, state) or (0, nil) when the re-validation failed
-- (T10: an action on a dug node fails safely; S06/SP-4: so does a
-- protected one).
----------------------------------------------------------------------

-- Whole items of `item_name` that `inv` can absorb right now: every
-- empty slot holds one stack, a partial stack of the same item absorbs
-- the rest of its stack. Only whole items are counted (integer
-- boundary).
local function inv_room(inv, item_name, stack_max)
	local cap = 0
	local size = inv:get_size("main")
	for i = 1, size do
		local s = inv:get_stack("main", i)
		if not s or s:is_empty() then
			cap = cap + stack_max
		elseif s:get_name() == item_name then
			cap = cap + math.max(0, stack_max - s:get_count())
		end
	end
	return cap
end

function smp_spawners.take(pos, player, opened_type, item_name, n)
	local state = smp_spawners.revalidate(pos, opened_type, player, true)
	if not state then return 0, nil end
	local count = state.store[item_name] or 0
	local want = math.min(math.floor(count + 0.5 - 1e-9), n or math.huge)
	if want < 1 then
		-- Nothing whole to take; the node is unchanged.
		return 0, state
	end

	-- S06/SP-3: cap at stack_max x free space and add in chunks.
	local stack_max = math.max(1,
		math.min(ItemStack(item_name):get_stack_max(), 65535))
	local take = want
	if player then
		local inv = player:get_inventory()
		take = math.min(take, inv_room(inv, item_name, stack_max))
		if take < 1 then
			-- Inventory full: nothing delivered, so nothing removed.
			return 0, state
		end
	end

	-- Deliver first; only what landed leaves the store (S06/SP-2).
	local delivered = 0
	if player then
		local inv = player:get_inventory()
		while delivered < take do
			local chunk = math.min(stack_max, take - delivered)
			local stack = ItemStack(item_name)
			stack:set_count(chunk)
			local left = inv:add_item("main", stack)
			local landed = chunk - (left and left:get_count() or 0)
			-- A chunk that lands nothing means the room estimate was
			-- wrong; stop and keep the remainder stored (never lost).
			if landed <= 0 then break end
			delivered = delivered + landed
		end
	end
	if delivered < 1 then
		-- Nothing landed (full inventory or a nil player): the store
		-- is untouched and no version bump happens.
		return 0, state
	end

	state.store[item_name] = count - delivered
	smp_spawners.write_state(state)
	return delivered, state
end

----------------------------------------------------------------------
-- Collect XP (f07 §4.4)
----------------------------------------------------------------------

function smp_spawners.collect_xp(pos, player, opened_type)
	-- Mutating action: S06/SP-4 protection check applies.
	local state = smp_spawners.revalidate(pos, opened_type, player, true)
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
