-- FriedcakeSMP — smp_spawners / routing.lua
-- Sell all: sells the spawner's stored output through the f02 sell
-- routing so higher-paying orders are served first (f07 §4.6.4 [S2]).
--
-- f02's routing-in contract (f02-sell.md §6):
--
--   smp_sell.sell(player, stacks)
--
-- takes a list of ItemStacks, groups them by M0, routes each group to
-- better-paying open orders first and the remainder to the server at
-- base price, writes the ledger and returns the receipt lines (it does
-- not display them — the caller does). Spawner output
-- is plain (M0) loot, so that is exactly what Sell all needs.
--
-- f02 (smp_sell) is not on main yet. When it lands this module calls
-- it as above; until then Sell all refunds the items to storage and
-- reports that selling is unavailable. The TODO(f02) marker stays on
-- the routing call.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_spawners.S

smp_spawners.routing = {}

----------------------------------------------------------------------
-- Sell all
--
-- Returns (ok, message). The message is a string for our own refusals
-- and a list of lines when f02's receipt or refusal lines are relayed
-- (f02 returns them without showing them — only the caller can show
-- them), so the caller must be able to handle either (F07-1).
-- The caller closes the menu on ok.
----------------------------------------------------------------------

function smp_spawners.routing.sell_all(pos, player, opened_type)
	-- Re-validate; the action is part of the menu contract (R7, T10).
	-- S06/SP-4: Sell all is mutating, so the protection check applies.
	-- It also converts elapsed time first (f07 §4.5, F07-7), so a sale
	-- takes everything produced since last_update.
	local state, why = smp_spawners.revalidate(pos, opened_type, player,
		true)
	if not state then
		-- "protected" already reached the player as a chat line
		-- (revalidate); do not follow it with a wrong "removed".
		if why == "protected" then return false, nil end
		return false, S("This spawner has been removed")
	end

	-- Whole items only (integer boundary, f07 §4.2).
	local lots = {}
	local total = 0
	for name, count in pairs(state.store) do
		local n = math.floor(count + 0.5 - 1e-9)
		if n >= 1 then
			lots[#lots + 1] = { name = name, count = n }
			total = total + n
		end
	end
	if total < 1 then
		return false, S("Nothing stored to sell")
	end

	if not (smp_sell and type(smp_sell.sell) == "function") then
		-- TODO(f02): sell routing lands with the f02 branch. Nothing
		-- is taken out of storage until it does.
		return false, S("Selling is not available yet")
	end

	-- S06/SP-3: `ItemStack:set_count(n)` CLEARS the stack for
	-- n > 65535 (l_item.cpp:91-96), so one oversized lot used to
	-- become an empty stack, sell "the rest" and then have EVERY lot
	-- subtracted from the store. Split each lot into stacks of at most
	-- stack_max (u16, hence the 65535 clamp) before handing it over,
	-- and remember exactly what was handed.
	local stacks = {}
	local handed = {}
	for _, lot in ipairs(lots) do
		local stack_max = math.max(1,
			math.min(ItemStack(lot.name):get_stack_max(), 65535))
		local left = lot.count
		while left > 0 do
			local c = math.min(stack_max, left)
			local stack = ItemStack(lot.name)
			stack:set_count(c)
			stacks[#stacks + 1] = stack
			handed[lot.name] = (handed[lot.name] or 0) + c
			left = left - c
		end
	end

	-- f02 routes better-paying orders first, then the server [S2]. It
	-- owns the money/item movement and its contract (f02 §6,
	-- smp_sell/init.lua:180-186) is: `true` = every stack was consumed
	-- and paid for, `false` = nothing moved. So storage is decremented
	-- only after a `true` — validate, then mutate (shared §2.3) — and
	-- there is no yield between the two.
	--
	-- f02 returns its receipt/refusal lines as the second value without
	-- displaying them (smp_sell/sell.lua:294-342, init.lua:195-213), so
	-- the caller is the only place they can be shown: relay them.
	local ok, lines = smp_sell.sell(player, stacks)
	if not ok then
		-- `false` = nothing moved (f02 all-or-nothing contract), so
		-- NOTHING is subtracted from the store (S06/SP-3).
		if type(lines) == "table" and #lines > 0 then
			return false, lines
		end
		return false, S("Spawner output could not be sold")
	end

	-- `true` = every stack handed over was consumed and paid for, so
	-- subtract exactly the handed counts — never more (S06/SP-3).
	for name, n in pairs(handed) do
		state.store[name] = (state.store[name] or 0) - n
	end
	smp_spawners.write_state(state)

	local out = { S("Spawner output sent to sell routing (@1 items)",
		smp_core.fmt_qty(total)) }
	if type(lines) == "table" then
		for _, line in ipairs(lines) do
			out[#out + 1] = tostring(line)
		end
	end
	return true, out
end
