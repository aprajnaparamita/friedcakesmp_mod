-- FriedcakeSMP — smp_quickbuy buy path (§6)
--
-- The purchase algorithm, kept free of formspec concerns so the dev-tests
-- and the in-game tests can exercise it with the bridges stubbed.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_quickbuy.buy = {}

local function chat(player, msg)
	core.chat_send_player(player:get_player_name(), msg)
end

-- Refuse with a reason (chat already sent) and return nothing.
local function refuse(player, msg)
	chat(player, msg)
	return nil
end

-- Core purchase for one entry (§6).
--
--   player      : ObjectRef
--   entry_index : 1-based index into the player's Quick Buy list
--   shown_price : integer cents displayed at the last redraw (guard baseline)
--   confirmed   : true once the player has re-confirmed the 3× warning screen
--
-- Returns:
--   true, spent_cents, bought_qty   on success (all or part of the entry)
--   "warn", entry_index, shown_price, cost   when the guard trips and the
--         caller must open the re-confirm screen
--   nil, message                    on refusal (chat already sent)
--
-- No yields anywhere between validate and mutate (shared §2.3). Every
-- listing is bought through smp_ah.buy() so a listing bought out from under
-- the purchase fails cleanly (T7) and the remaining listings still complete.
function smp_quickbuy.buy.entry(player, entry_index, shown_price, confirmed)
	local name = player:get_player_name()

	-- T5: Quick Buy is unavailable while combat-tagged (§4.4).
	if smp_quickbuy.combat.is_tagged(player) then
		return refuse(player, S("Quick Buy is unavailable during combat."))
	end

	local entry = smp_quickbuy.entries.get(name, entry_index)
	if not entry then
		return refuse(player, S("That Quick Buy entry no longer exists."))
	end

	local result = smp_quickbuy.au.cheapest_for(entry.key, entry.ench, entry.qty)
	if not result then
		return refuse(player, S("There are not enough listings to fill this entry."))
	end
	local cost = result.cost_cents

	-- 3× price guard (T2/T3). A purchase may spend up to three times the
	-- displayed live price; above that a warning screen needs re-confirmation
	-- [S7]. Only guarded when a positive price was actually displayed.
	if not confirmed
	   and shown_price and shown_price > 0
	   and not smp_quickbuy.price.within_guard(shown_price, cost) then
		return "warn", entry_index, shown_price, cost
	end

	-- Insufficient funds.
	local rec = smp_store.api.get_player(name)
	if not rec or (rec.money or 0) < cost then
		return refuse(player, S("Insufficient funds."))
	end

	-- Mutate. Each listing re-validates its own version inside smp_ah.buy;
	-- a nil return means the listing was bought out from under us (T7) and
	-- we simply skip it — the buyer is not charged for it.
	local spent = 0
	local bought = 0
	for _, l in ipairs(result.listings) do
		local r = smp_quickbuy.au.buy(player, l.id, l.version)
		if r then
			spent = spent + (l.price or 0)
			bought = bought + 1
		end
	end

	if bought == 0 then
		return refuse(player, S("This item was already bought."))
	end

	-- T6: money_spent_on_shop increments by exactly the amount paid.
	smp_quickbuy.stats.add(player, "money_spent_on_shop", spent)
	return true, spent, bought
end

core.log("action", "[smp_quickbuy] buy path ready")
