-- FriedcakeSMP — smp_shardshop
--
-- The shard shop: grid -> offer -> confirm -> shard debit -> delivery
-- (spec/features/f06-shards.md §4.2).
--
-- Entry points:
--   * smp_shardshop.open(player) — the contract f04's orders board calls
--     from its amethyst shard control (tooltip `Shard Shop` /
--     `Click to view` [F0179, F0182]). T9.
--   * /shardshop — PROPOSED standalone command (V-60/V-27).
--
-- Purchase (shared §2.3, no yields between validate and mutate):
--   1. validate: offer exists and is available, balance covers it, the
--      inventory has room (T8: a full inventory refuses and debits
--      nothing)
--   2. mutate: take_shards (ledger `shard_spend`), then deliver
--   3. notify: `You bought 1 <Item> for <qty> Shards`, generalising the
--      observed `You bought 1 Ender Chest for $ 5.1K` [F0037, F0055]
--
-- Layout is PROPOSED throughout (the shop was never opened; V-60).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())
local modpath = core.get_modpath("smp_shardshop")

smp_shardshop = {}
smp_shardshop.S = S

smp_shardshop.catalogue = dofile(modpath .. "/catalogue.lua")
dofile(modpath .. "/formspec.lua")
local fs = smp_shardshop.fs
fs.set_translator(S)

local FORM_SHOP = "smp_shardshop:shop"
local FORM_CONFIRM = "smp_shardshop:confirm"

local function balance_of(name)
	local rec = smp_store.api.get_player(name)
	return rec and (rec.shards or 0) or 0
end

local function show_shop(player_name)
	local session = smp_core.open_session(player_name, FORM_SHOP, {})
	if not session then return false end
	core.show_formspec(player_name, FORM_SHOP,
		fs.shop_form(balance_of(player_name)))
	return true
end

----------------------------------------------------------------------
-- smp_shardshop.open(player) — the f04 orders-board entry point.
--
-- `player` is a Player object (as f04 passes it from the control's
-- field handler). Also accepts a player name string for convenience.
----------------------------------------------------------------------

function smp_shardshop.open(player)
	if not player then return false end
	local player_name
	if type(player) == "string" then
		player_name = player
	else
		player_name = player:get_player_name()
	end
	if not player_name or not core.get_player_by_name(player_name) then
		return false
	end
	return show_shop(player_name)
end

-- The observed affordance on the orders board control: clicking the
-- amethyst shard opens the shop. f04 renders the control; this is what
-- it calls.
smp_shardshop.SHARD_CONTROL = {
	item = "mcl_amethyst:amethyst_shard",
	tooltip = { S("Shard Shop"), S("Click to view") },
}

----------------------------------------------------------------------
-- Purchase
----------------------------------------------------------------------

local function purchase(player_name, offer_id)
	local offer = smp_shardshop.catalogue.find_offer(offer_id)
	if not offer then return end
	local item = smp_shardshop.catalogue.resolve_item(offer)
	if not item or not core.registered_items[item] then
		core.chat_send_player(player_name, S("This item is not available"))
		return
	end

	local rec = smp_store.api.get_player(player_name)
	if not rec or (rec.shards or 0) < offer.shards then
		core.chat_send_player(player_name,
			S("You do not have enough shards"))
		return
	end

	local inv = core.get_player_by_name(player_name):get_inventory()
	-- Build the stack up front so the room check matches the delivery.
	local stack = smp_shardshop.catalogue.make_stack(offer)
	if not stack or not inv:room_for_item("main", stack) then
		core.chat_send_player(player_name, S("Your inventory is full"))
		return
	end

	-- No yields from here (shared §2.3): debit, then deliver.
	local removed = smp_store.api.take_shards(player_name, offer.shards,
		"shard_spend", "shardshop:" .. offer.id)
	if not removed then
		core.chat_send_player(player_name,
			S("You do not have enough shards"))
		return
	end
	local left = inv:add_item("main", stack)
	if not left:is_empty() then
		-- Cannot happen after room_for_item in the same tick; refund so
		-- the invariant never breaks.
		smp_store.api.add_shards(player_name, offer.shards, "admin",
			"shardshop:refund:" .. offer.id)
		core.chat_send_player(player_name, S("Your inventory is full"))
		return
	end

	local def = core.registered_items[item]
	local display = def and def.description or offer.name
	core.chat_send_player(player_name,
		S("You bought @1 @2 for @3 Shards", 1, display,
			smp_core.fmt_qty(offer.shards)))
end

----------------------------------------------------------------------
-- Exposed for tests (in-game `/smp test smp_shardshop` and dev-tests):
-- the purchase path, callable with a player name and an offer id.
----------------------------------------------------------------------
smp_shardshop._purchase = purchase

----------------------------------------------------------------------
-- Formspec handlers (R4: re-validate every action; client fields are
-- untrusted)
----------------------------------------------------------------------

core.register_on_player_receive_fields(function(player_name, formname, fields)
	if formname == FORM_SHOP then
		smp_core.handle_fields(player_name, formname, fields,
			function(session, f)
			if f.quit then return "close" end
			-- Grid buttons are field-named offer_<id>; the client value is
			-- untrusted, so resolve the id against the catalogue.
			for _, offer in ipairs(smp_shardshop.catalogue.offers) do
				if f["offer_" .. offer.id] then
					smp_core.open_session(player_name, FORM_CONFIRM,
						{ offer_id = offer.id })
					core.show_formspec(player_name, FORM_CONFIRM,
						fs.confirm_form(offer, balance_of(player_name)))
					return "stay"
				end
			end
			return "stay"
		end)
	elseif formname == FORM_CONFIRM then
		smp_core.handle_fields(player_name, formname, fields,
			function(session, f)
			if f.cancel then return "close" end
			if f.buy then
				-- Re-validate the offer from the server-side session;
				-- the client field is never trusted for the debit.
				purchase(player_name, session.offer_id)
				return "close"
			end
			return "stay"
		end)
	end
end)

core.register_on_leaveplayer(function(player_name)
	smp_core.close_session(player_name, FORM_SHOP)
	smp_core.close_session(player_name, FORM_CONFIRM)
end)

----------------------------------------------------------------------
-- /shardshop (PROPOSED)
----------------------------------------------------------------------

core.register_chatcommand("shardshop", {
	params = "",
	description = S("Open the shard shop."),
	func = function(player_name, _)
		local player = core.get_player_by_name(player_name)
		if not player then
			return false, S("Player not found.")
		end
		smp_shardshop.open(player)
		return true
	end,
})

core.log("action", "[smp_shardshop] loaded: " ..
	#smp_shardshop.catalogue.offers .. " offers; entry point " ..
	"smp_shardshop.open() ready for f04")
