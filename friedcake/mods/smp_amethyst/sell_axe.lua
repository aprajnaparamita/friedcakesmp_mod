-- FriedcakeSMP — smp_amethyst/sell_axe.lua
--
-- Amethyst Sell Axe (LIVE, undocumented — PROPOSED, f06 §10 V-22).
-- Named in the June 9 routing rules [S2]: punching a container routes
-- its eligible contents into the economy:
--
--   1. Orders first: for each stack, its M1 key
--      (shared §2.5, via smp_items) is offered to
--      smp_orders.best_open_order(key); a hit is filled through
--      smp_orders.fill_from_stack(order, player, stack) (f04).
--   2. Otherwise sell routing: smp_sell.sell(player, stack) (f02).
--   3. Otherwise the stack stays in the container — a stack is never
--      removed unless a route accepted it.
--
-- Both cross-mod calls are stubbed here: smp_orders (f04) does not
-- exist on this branch yet, and smp_sell's entry point is being built
-- in parallel. Each is guarded so the mod loads and degrades safely.
-- Protection-checked; refused while tagged.

local S = core.get_translator(core.get_current_modname())
local am = smp_amethyst

local function stack_key(stack)
	-- M1 key (name + enchantments + meta hash); nil for named stacks,
	-- which M1 rejects (shared §2.5).
	if smp_items and type(smp_items.key) == "function" then
		return smp_items.key(stack, "M1")
	end
	return nil
end

-- Fill a stack into the best open order for its key. Returns true only
-- when the order accepted the stack and was paid for it.
local function route_to_order(player, stack, key)
	if not (smp_orders and type(smp_orders.best_open_order) == "function") then
		return false
	end
	local order = smp_orders.best_open_order(key)
	if not order then return false end
	if type(smp_orders.fill_from_stack) ~= "function" then return false end
	local ok, accepted = pcall(smp_orders.fill_from_stack, order, player, stack)
	-- S05/AX-1: fill_from_stack REFUSES with `nil, reason` (changed / own
	-- order / no match / "full") and accepts with `{ accepted = n, ... }`.
	-- The old `accepted ~= false` was true for nil, so a refused fill was
	-- reported as routed and the stack was deleted from the container
	-- without payment (the axe is caller-side of the same misread as
	-- AH-1/OR-2). pcall success is not the call's success: read both.
	return ok and type(accepted) == "table"
		and (accepted.accepted or 0) > 0
end

-- Base-price sell routing (f02). Contract PROPOSED:
--   smp_sell.sell(player, stack) -> true when the stack was paid for.
local function route_to_sell(player, stack)
	if not (smp_sell and type(smp_sell.sell) == "function") then
		return false
	end
	local ok, sold = pcall(smp_sell.sell, player, stack)
	return ok and sold == true
end

core.register_tool("smp_amethyst:sell_axe", {
	description = S("Amethyst Sell Axe"),
	inventory_image = "mcl_amethyst_shard.png",
	wield_image = "mcl_amethyst_shard.png",
	stack_max = 1,
	groups = {
		rarity = 2,
	},
	tool_capabilities = {
		full_punch_interval = 0.8,
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
		local pos = pointed_thing.under

		-- Protection-checked, like every other amethyst tool.
		if core.is_protected(pos, name) then
			core.chat_send_player(name, S("That area is protected"))
			return itemstack
		end

		local inv = core.get_meta(pos):get_inventory()
		if not inv then
			core.chat_send_player(name, S("That is not a container"))
			return itemstack
		end

		local routed, skipped = 0, 0
		local size = inv:get_size("main") or 0
		-- S05/AX-2: inventory lists are 1-based from Lua (l_inventory.cpp
		-- subtracts 1 and rejects index < 0). The old `0, size - 1` read an
		-- empty slot 0 and never touched the last slot.
		for i = 1, size do
			local stack = inv:get_stack("main", i)
			if not stack:is_empty() then
				local key = stack_key(stack)
				local went = false
				if key then
					went = route_to_order(player, stack, key)
						or route_to_sell(player, stack)
				end
				if went then
					inv:set_stack("main", i, "")
					routed = routed + 1
				else
					-- No route: the stack stays; nothing is lost.
					skipped = skipped + 1
				end
			end
		end

		if routed > 0 then
			core.chat_send_player(name,
				S("Routed @1 stacks from the container.", routed))
		elseif skipped > 0 then
			core.chat_send_player(name,
				S("No order or buyer for these items"))
		end

		am.refresh_description(itemstack)
		player:set_wielded_item(itemstack)
		return itemstack
	end,
})
