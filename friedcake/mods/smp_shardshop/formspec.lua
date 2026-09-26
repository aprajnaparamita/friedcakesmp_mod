-- FriedcakeSMP — smp_shardshop/formspec.lua
--
-- The shard shop menu, built to the shared UI kit grammar
-- (spec/shared/04-ui-kit.md) with the same geometry and item-as-button
-- idiom as smp_ah/formspec.lua.
--
-- f06 §3: the shop screen itself was NEVER opened — there is no frame
-- evidence for its layout (V-60). Everything about the layout below is
-- therefore PROPOSED: a container menu titled `Shard Shop`, a 2x9 offer
-- grid above the player's inventory, offer tooltips in the listing
-- shape (name / price / affordance / itemstring), and a lighter
-- confirm prompt before the shard debit.
--
-- Only the ENTRY POINT is observed: the orders board carries an
-- amethyst shard control with the tooltip `Shard Shop` /
-- `Click to view` [F0179, F0182] that opens this screen (T9).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_shardshop = smp_shardshop or {}

local fs = {}
smp_shardshop.fs = fs

local F = core.formspec_escape
local S = smp_shardshop.S or core.get_translator(
	core.get_current_modname() or "smp_shardshop")
fs.set_translator = function(fn) S = fn end

local function c(v) return string.format("%.6g", v) end

----------------------------------------------------------------------
-- Geometry: mcl_chests proportions (as in smp_ah), 2 offer rows.
----------------------------------------------------------------------

local G = {
	x0 = 0.375,
	pitch = 1.25,
	cols = 9,
	rows = 2,
	grid_y = 0.75,
	inv_label_y = 3.7,
	inv_y = 4.1,
	hot_y = 8.05,
	w = 11.75,
	h = 9.425,
}
fs.G = G

local function sx(col) return G.x0 + (col - 1) * G.pitch end

local function slot_bg(x, y, w, h)
	if mcl_formspec and type(mcl_formspec.get_itemslot_bg_v4) == "function" then
		return mcl_formspec.get_itemslot_bg_v4(x, y, w, h)
	end
	return "image[" .. c(x) .. "," .. c(y) .. ";" .. c(w) .. "," .. c(h) ..
		";default_slot.png]"
end

----------------------------------------------------------------------
-- Offer tooltip (listing shape, shared §4.4; PROPOSED wording)
--
--   Shard Pickaxe
--   3k Shards
--   Click to buy
--   smp_amethyst:pickaxe
----------------------------------------------------------------------

function fs.tooltip(name, lines)
	local out = {}
	for i, line in ipairs(lines) do
		out[i] = F(tostring(line))
	end
	return "tooltip[" .. F(name) .. ";" .. table.concat(out, "\n") .. "]"
end

local function price_line(shards)
	return smp_core.fmt_qty(shards) .. " Shards"
end

----------------------------------------------------------------------
-- The shop grid (container menu)
----------------------------------------------------------------------

function fs.shop_form(balance)
	local cat = smp_shardshop.catalogue
	local out = {
		"formspec_version[6]",
		"size[" .. c(G.w) .. "," .. c(G.h) .. "]",
		"label[" .. c(G.x0) .. ",0.375;" .. F(S("Shard Shop")) .. "]",
		"label[" .. c(sx(7)) .. ",0.375;" ..
			F(S("Shards: @1", smp_core.fmt_qty(balance or 0))) .. "]",
		slot_bg(G.x0, G.grid_y, G.cols, G.rows),
	}
	for i, offer in ipairs(cat.offers) do
		local col = (i - 1) % G.cols + 1
		local row = math.floor((i - 1) / G.cols) + 1
		local x = sx(col)
		local y = G.grid_y + (row - 1) * G.pitch
		local btn = "offer_" .. offer.id
		local item = cat.resolve_item(offer)
		if item and core.registered_items[item] then
			out[#out + 1] = "item_image_button[" .. c(x) .. "," .. c(y) ..
				";" .. c(G.pitch) .. "," .. c(G.pitch) .. ";" ..
				F(item) .. ";" .. F(btn) .. ";]"
			out[#out + 1] = fs.tooltip(btn, {
				S(offer.name),
				price_line(offer.shards),
				S("Click to buy"),
				item,
			})
		else
			-- Unavailable in this engine (e.g. mcl_armor absent): a plain
			-- button that explains why, so the grid keeps its shape.
			out[#out + 1] = "button[" .. c(x) .. "," .. c(y) .. ";" ..
				c(G.pitch) .. "," .. c(G.pitch) .. ";" .. F(btn) .. ";?]"
			out[#out + 1] = fs.tooltip(btn, {
				S(offer.name),
				price_line(offer.shards),
				S("Not available"),
			})
		end
	end
	out[#out + 1] = "label[" .. c(G.x0) .. "," .. c(G.inv_label_y) .. ";" ..
		F(S("Inventory")) .. "]"
	out[#out + 1] = slot_bg(G.x0, G.inv_y, G.cols, 3)
	out[#out + 1] = "list[current_player;main;" .. c(G.x0) .. "," ..
		c(G.inv_y) .. ";9,3;9]"
	out[#out + 1] = slot_bg(G.x0, G.hot_y, G.cols, 1)
	out[#out + 1] = "list[current_player;main;" .. c(G.x0) .. "," ..
		c(G.hot_y) .. ";9,1;]"
	return table.concat(out, "")
end

----------------------------------------------------------------------
-- The confirm prompt (lighter confirmation, shared §4.7)
--
--   Confirm Purchase
--   Offer:  <name>
--   Cost:   <qty> Shards
--   Balance: <qty> Shards
--   [ Cancel! ]            [ Buy ]
----------------------------------------------------------------------

function fs.confirm_form(offer, balance)
	local out = {
		"formspec_version[6]",
		"size[8,4.4]",
		"bgcolor[#000000C0]",
		"label[0.5,0.5;" .. F(S("Confirm Purchase")) .. "]",
		"label[0.5,1.3;" .. F(S("Offer: @1", S(offer.name))) .. "]",
		"label[0.5,1.9;" .. F(S("Cost: @1", price_line(offer.shards))) .. "]",
		"label[0.5,2.5;" .. F(S("Balance: @1",
			price_line(balance or 0))) .. "]",
		"style[cancel;bgcolor=red]",
		"button[0.5,3.2;3,0.8;cancel;" .. F(S("Cancel!")) .. "]",
		"button[4.5,3.2;3,0.8;buy;" .. F(S("Buy")) .. "]",
	}
	return table.concat(out, "")
end

return fs
