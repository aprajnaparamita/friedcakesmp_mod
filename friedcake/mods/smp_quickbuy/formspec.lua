-- FriedcakeSMP — smp_quickbuy formspecs
--
-- Every screen here is PROPOSED — no frame shows /shop (f05 §1). Layouts,
-- tooltip lines and affordances follow the observed container-menu grammar
-- (shared/04-ui-kit.md) but are unverified guesses to be replaced the moment
-- a screenshot lands.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())
local cfg = smp_quickbuy.cfg

smp_quickbuy.formspec = {}

-- One formname for the whole menu. The main / entries / add / warn screens
-- are all shown under this single name so the engine's formname check never
-- drops a click as a "possible exploitation attempt" (see init.lua §Menu
-- state). The active screen is tracked in the session, not in the formname.
smp_quickbuy.formspec.MENU = "smp_quickbuy:menu"

----------------------------------------------------------------------
-- Small shared helpers (all PROPOSED)
----------------------------------------------------------------------

local function esc(s)
	return (core.formspec_escape and core.formspec_escape(s)) or
		tostring(s):gsub("\\", "\\\\"):gsub("%[", "\\["):gsub("%]", "\\]")
end

local ROMAN = {
	{1000, "M"}, {900, "CM"}, {500, "D"}, {400, "CD"}, {100, "C"},
	{90, "XC"}, {50, "L"}, {40, "XL"}, {10, "X"}, {9, "IX"},
	{5, "V"}, {4, "IV"}, {1, "I"},
}

local function roman(n)
	n = math.floor(tonumber(n) or 0)
	if n < 1 then return tostring(n) end
	local out = {}
	for _, p in ipairs(ROMAN) do
		while n >= p[1] do out[#out + 1] = p[2]; n = n - p[1] end
	end
	return table.concat(out)
end

-- Format an enchantment map { id = level } as "Sharpness V, Unbreaking III".
-- Prefer Mineclonia's own naming when available; otherwise capitalise the id
-- and append a roman level (PROPOSED fallback for dev-tests).
local function format_ench(ench)
	if not ench then return nil end
	local parts = {}
	for id, level in pairs(ench) do
		if mcl_enchanting and mcl_enchanting.get_enchantment_description then
			parts[#parts + 1] = mcl_enchanting.get_enchantment_description(id, level)
		else
			local name = id:gsub("_", " ")
			name = name:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
			if level and level > 1 then name = name .. " " .. roman(level) end
			parts[#parts + 1] = name
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- Display name for an itemstring. Registered item description when present.
local function display_name(key)
	if core.registered_items and core.registered_items[key]
	   and core.registered_items[key].description then
		return core.registered_items[key].description
	end
	return key
end

-- Entry tooltip (§3): display name, enchantments (if any), price,
-- "Click to buy", itemstring. Five lines when enchanted, four otherwise.
local function entry_tooltip(entry, price_cents)
	local lines = { display_name(entry.key) }
	local ench_line = format_ench(entry.ench)
	if ench_line and ench_line ~= "" then lines[#lines + 1] = ench_line end
	lines[#lines + 1] = price_cents and smp_core.fmt_money(price_cents, "body")
		or S("No listings")
	lines[#lines + 1] = S("Click to buy")
	lines[#lines + 1] = entry.key
	return table.concat(lines, "\n")
end

local function preamble(size)
	return "formspec_version[6]" .. "size[" .. size .. "]"
end

----------------------------------------------------------------------
-- Main container menu (PROPOSED layout, §3)
--
-- "Quick Buy (Page @1)" title; a grid of entry item-buttons ("Click to
-- buy"); an [Add entry] sign and a [Your entries] chest in the control row;
-- the player inventory below an "Inventory" label.
----------------------------------------------------------------------

-- Geometry follows Mineclonia's chest formspecs (mcl_chests) and matches
-- smp_ah's six-row board: 11.75 wide, slots on a 1.25 pitch, margins at
-- 0.375. Under formspec_version 6 a 9-wide list[] is 11 units across, so
-- anything narrower clips the player inventory.
local G = {
	x0 = 0.375, pitch = 1.25, cols = 9, rows = 5,
	w = 11.75, h = 14.15, grid_y = 0.75,
	inv_label_y = 8.45, inv_y = 8.825, hot_y = 12.775,
}

local function c(v) return string.format("%.6g", v) end
local function sx(col) return G.x0 + (col - 1) * G.pitch end
local function sy(row) return G.grid_y + (row - 1) * G.pitch end

local function slot_bg(x, y, w, h)
	if mcl_formspec and type(mcl_formspec.get_itemslot_bg_v4) == "function" then
		return mcl_formspec.get_itemslot_bg_v4(x, y, w, h)
	end
	local out = {}
	for j = 0, h - 1 do
		for i = 0, w - 1 do
			out[#out + 1] = "image[" .. c(x + i * G.pitch - 0.05) .. "," ..
				c(y + j * G.pitch - 0.05) .. ";1.1,1.1;mcl_formspec_itemslot.png]"
		end
	end
	return table.concat(out)
end

local function btn(kind, col, row, a, b)
	return string.format("%s[%s,%s;%s,%s;%s;%s;]", kind, c(sx(col)), c(sy(row)),
		c(G.pitch), c(G.pitch), a, b)
end

function smp_quickbuy.formspec.main(player, session)
	session = session or {}
	local name = player:get_player_name()
	local list = smp_quickbuy.entries.list(name)
	session.page = session.page or 1
	session.prices = session.prices or {}

	local slots = G.cols * G.rows
	local page_size = math.min(cfg.page_size, slots)
	local total = #list
	local page = session.page
	local total_pages = math.max(1, math.ceil(total / page_size))
	if page > total_pages then page = total_pages end
	session.page = page

	local first = (page - 1) * page_size

	local out = { preamble(c(G.w) .. "," .. c(G.h)) }
	out[#out + 1] = "label[" .. c(G.x0) .. ",0.375;"
		.. esc(S("Quick Buy (Page @1)", page)) .. "]"

	-- Entry grid: 5 rows x 9 columns, one item button per entry, aligned
	-- with the inventory columns below.
	out[#out + 1] = slot_bg(G.x0, G.grid_y, G.cols, G.rows)
	for slot = 1, page_size do
		local absidx = first + slot
		local entry = list[absidx]
		if entry then
			local col = (slot - 1) % G.cols + 1
			local row = math.floor((slot - 1) / G.cols) + 1
			-- Recompute the live price on every redraw (never cache across
			-- a redraw — f05 §8). Store it so the buy click has a baseline.
			local price = smp_quickbuy.price.lookup(entry.key, entry.ench, entry.qty)
			session.prices[absidx] = price
			out[#out + 1] = btn("item_image_button", col, row, esc(entry.key),
				"entry_" .. absidx)
			out[#out + 1] = "tooltip[entry_" .. absidx .. ";"
				.. esc(entry_tooltip(entry, price)) .. "]"
		end
	end

	-- Control row (sixth row): Add entry sign at the far left, Your entries
	-- chest at the far right, pager in the middle.
	local ctrl = G.rows + 1
	out[#out + 1] = btn("item_image_button", 1, ctrl, "mcl_signs:wall_sign_oak", "add")
	out[#out + 1] = "tooltip[add;" .. esc(S("Add entry")) .. "\n"
		.. esc(S("Click to add the held item")) .. "]"
	out[#out + 1] = btn("item_image_button", G.cols, ctrl, "mcl_chests:chest",
		"your_entries")
	out[#out + 1] = "tooltip[your_entries;" .. esc(S("Your entries")) .. "\n"
		.. esc(S("Click to view")) .. "]"

	-- Pagination (PROPOSED): only shown when the entry list overflows.
	if total_pages > 1 then
		out[#out + 1] = string.format("button[%s,%s;%s,%s;prev;<]",
			c(sx(4)), c(sy(ctrl)), c(G.pitch), c(G.pitch))
		out[#out + 1] = string.format("button[%s,%s;%s,%s;next;>]",
			c(sx(6)), c(sy(ctrl)), c(G.pitch), c(G.pitch))
	end

	-- Player inventory: 3 main rows, then the hotbar (shared §4.1).
	out[#out + 1] = "label[" .. c(G.x0) .. "," .. c(G.inv_label_y) .. ";"
		.. esc(S("Inventory")) .. "]"
	out[#out + 1] = slot_bg(G.x0, G.inv_y, G.cols, 3)
	out[#out + 1] = "list[current_player;main;" .. c(G.x0) .. "," .. c(G.inv_y)
		.. ";9,3;9]"
	out[#out + 1] = slot_bg(G.x0, G.hot_y, G.cols, 1)
	out[#out + 1] = "list[current_player;main;" .. c(G.x0) .. "," .. c(G.hot_y)
		.. ";9,1;]"

	return table.concat(out)
end

----------------------------------------------------------------------
-- "Your entries" manage screen (PROPOSED prompt menu)
--
-- Lists each entry with a Remove button and an Edit-amount button; Back
-- returns to the main panel.
----------------------------------------------------------------------

function smp_quickbuy.formspec.entries(player)
	local name = player:get_player_name()
	local list = smp_quickbuy.entries.list(name)

	local out = { preamble("9,10") }
	out[#out + 1] = "label[0.5,0.2;" .. esc(S("Your entries")) .. "]"

	if #list == 0 then
		out[#out + 1] = "label[0.5,1.2;" .. esc(S("You have no Quick Buy entries.")) .. "]"
	end

	local y = 0.7
	for i, entry in ipairs(list) do
		if y > 8.2 then break end
		local price = smp_quickbuy.price.lookup(entry.key, entry.ench, entry.qty)
		local label = entry.key
		if core.registered_items then
			label = string.format("%s x%s — %s", display_name(entry.key),
				smp_core.fmt_qty(entry.qty),
				price and smp_core.fmt_money(price, "body") or S("No listings"))
		else
			label = string.format("%s x%s", entry.key, smp_core.fmt_qty(entry.qty))
		end
		out[#out + 1] = string.format("item_image_button[0.5,%s;1,1;%s;row_%d;]",
			y, esc(entry.key), i)
		out[#out + 1] = "tooltip[row_" .. i .. ";" .. esc(entry_tooltip(entry, price)) .. "]"
		out[#out + 1] = string.format("label[1.7,%s;%s]", y + 0.3, esc(label))
		out[#out + 1] = string.format("button[5.5,%s;1.6,0.8;edit_%d;%s]",
			y, i, esc(S("Edit")))
		out[#out + 1] = string.format("button[7.1,%s;1.6,0.8;remove_%d;%s]",
			y, i, esc(S("Remove")))
		y = y + 1.1
	end

	out[#out + 1] = "button[3.5,9.1;2,0.9;back;" .. esc(S("Back")) .. "]"
	return table.concat(out)
end

----------------------------------------------------------------------
-- "How many?" add/edit prompt (PROPOSED, follows §4.6 numeric prompt)
----------------------------------------------------------------------

function smp_quickbuy.formspec.add_qty(session)
	local default = session.qty_default or 1
	local out = { preamble("7,4.5") }
	out[#out +1 ] = "label[1,0.3;" .. esc(S("How many?")) .. "]"
	out[#out + 1] = "label[1,1.0;" .. esc(S("Amount")) .. "]"
	out[#out + 1] = string.format("field[1,1.4;5,0.9;amount;;%d]",
		math.max(1, default))
	out[#out + 1] = "field_close_on_enter[amount;false]"
	out[#out + 1] = "button[1,2.6;2,0.9;cancel;" .. esc(S("Cancel")) .. "]"
	out[#out + 1] = "button[3.5,2.6;2,0.9;add;" .. esc(S("Add")) .. "]"
	return table.concat(out)
end

----------------------------------------------------------------------
-- 3× price-guard re-confirm screen (PROPOSED, follows the Review Order
-- pattern in shared/04-ui-kit.md §4.7)
----------------------------------------------------------------------

function smp_quickbuy.formspec.warn(player, session)
	local entry = smp_quickbuy.entries.get(player:get_player_name(), session.entry_index)
	local title = entry and display_name(entry.key) or S("Quick Buy")
	local shown = session.shown_price or 0
	local cost  = session.cost or 0

	local out = { preamble("8,7") }
	out[#out + 1] = "label[0.5,0.2;" .. esc(title) .. "]"
	out[#out + 1] = string.format("item_image_button[0.5,0.6;1,1;%s;icon;]",
		esc(entry and entry.key or ""))
	out[#out + 1] = string.format("label[2,0.6;" .. esc(S("Item: @1", title)) .. "]")
	out[#out + 1] = string.format("label[2,1.2;" .. esc(S("Amount: @1",
		entry and smp_core.fmt_qty(entry.qty) or "1")) .. "]")
	out[#out + 1] = string.format("label[2,1.8;" .. esc(S("Shown price: @1",
		smp_core.fmt_money(shown, "body"))) .. "]")
	out[#out + 1] = string.format("label[2,2.4;" .. esc(S("Current price: @1",
		smp_core.fmt_money(cost, "body"))) .. "]")
	out[#out + 1] = string.format("label[2,3.0;" .. esc(S("Total: @1",
		smp_core.fmt_money(cost, "body"))) .. "]")
	out[#out + 1] = "label[2,3.8;" .. esc(S(
		"The price rose beyond three times what was shown. Confirm to buy anyway.")) .. "]"

	-- "Cancel!" keeps its observed exclamation mark (§0.5); the commit button
	-- is named for the action (§4.7).
	out[#out + 1] = "button[0.5,5.4;2,0.9;cancel_warn;" .. esc(S("Cancel!")) .. "]"
	out[#out + 1] = "button[5.5,5.4;2,0.9;confirm;" .. esc(S("Confirm")) .. "]"
	return table.concat(out)
end

----------------------------------------------------------------------
-- Screen dispatch
--
-- Renders whichever screen the session is on. All screens share the one
-- MENU formname; init.lua routes incoming fields by the same `screen` key.
----------------------------------------------------------------------

function smp_quickbuy.formspec.render(player, session)
	local screen = session and session.screen or "main"
	if screen == "entries" then
		return smp_quickbuy.formspec.entries(player)
	elseif screen == "add" then
		return smp_quickbuy.formspec.add_qty(session)
	elseif screen == "warn" then
		return smp_quickbuy.formspec.warn(player, session)
	end
	return smp_quickbuy.formspec.main(player, session)
end
