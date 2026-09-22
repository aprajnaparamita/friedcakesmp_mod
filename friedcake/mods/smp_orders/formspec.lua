-- FriedcakeSMP — smp_orders / formspec.lua
-- Every menu formspec, built with the observed strings and the shared
-- menu grammar (shared/04-ui-kit.md §4.1–§4.9).
--
-- Families (shared §4.1):
--   container menus (chest inventories, player inventory shown):
--     Orders (Page @1), Orders -> Your Orders,
--     Orders -> Deliver Items, Orders -> Confirm Delivery
--   prompt menus (translucent dark, no inventory):
--     Choose Item, How many?, Price per item?, Review Order, order manage
--
-- Item-as-button vocabulary (shared §4.3), Mineclonia substitutions
-- verified against ~/dev/mineclonia-git @ 5bdce566:
--   book            mcl_books:book                Orders / Request and deliver items
--   hopper          mcl_hoppers:hopper            Filter / Click to change + options
--   chest           mcl_chests:chest              Your Orders
--   amethyst shard  mcl_amethyst:amethyst_shard   Shard Shop / Click to view
--   lime pane       mcl_panes:pane_lime           Confirm / Click to deliver items ($N)
-- (shared/04-ui-kit.md §4.3 guessed mcl_core:glass_pane_lime; the real
--  itemstring is mcl_panes:pane_lime — flagged in f04 §10.)
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_orders.S
local cfg = smp_orders.cfg
local display = smp_orders.display
local F = core.formspec_escape

smp_orders.fs = {}
local fs = smp_orders.fs

----------------------------------------------------------------------
-- Geometry (mcl_chests / mcl_formspec grammar)
----------------------------------------------------------------------

fs.FORMNAME = {
	board   = "smp_orders:board",
	your    = "smp_orders:your",
	manage  = "smp_orders:manage",
	wizard  = "smp_orders:wizard",
	deliver = "smp_orders:deliver",
	confirm = "smp_orders:confirm",
}

-- Control items (shared §4.3)
fs.ITEM = {
	book   = "mcl_books:book",
	hopper = "mcl_hoppers:hopper",
	chest  = "mcl_chests:chest",
	shard  = "mcl_amethyst:amethyst_shard",
	lime   = "mcl_panes:pane_lime",
	gray   = "mcl_panes:pane_grey",
}

local X0 = 0.375          -- grid left margin (mcl_chests grammar)
local PITCH = 1.25        -- slot pitch
local BTN = 1.1           -- slot/button cell size
local OFF = -0.05         -- slot-bg border offset

local LABEL_COLOR = (mcl_formspec and mcl_formspec.label_color) or "#313131"
local RED = "#B02020"
local GREEN = "#2E8B57"

local function slot_bg(x, y, w, h)
	if mcl_formspec and mcl_formspec.get_itemslot_bg_v4 then
		return mcl_formspec.get_itemslot_bg_v4(x, y, w, h)
	end
	return ""
end

-- 1-based cell coordinates. Buttons sit exactly on the slot backgrounds
-- get_itemslot_bg_v4 draws (which start at x-0.05 and span 1.1).
local function btn_x(col) return X0 + OFF + (col - 1) * PITCH end
local function btn_y(row, y0) return (y0 or 0.75) + OFF + (row - 1) * PITCH end

-- item_image_button + multi-line tooltip (real newlines, then escaped —
-- the formspec parser unescapes backslashes; cf. mcl_craftguide)
local function item_button(col, row, itemstring, name, tooltip_lines, y0)
	local out = string.format("item_image_button[%f,%f;%f,%f;%s;%s;]",
		btn_x(col), btn_y(row, y0), BTN, BTN, itemstring, name)
	if tooltip_lines and #tooltip_lines > 0 then
		out = out .. "tooltip[" .. name .. ";" ..
			F(table.concat(tooltip_lines, "\n")) .. "]"
	end
	return out
end

local function label(x, y, text, color)
	return string.format("label[%f,%f;%s]", x, y,
		F(color and (color .. text) or text))
end

-- Coloured button (shared §4.6: Cancel red, forward green)
local function button(x, y, w, h, name, text, color)
	local out = string.format("button[%f,%f;%f,%f;%s;%s]",
		x, y, w, h, name, F(text))
	if color then
		out = out .. string.format("style[%s;bgcolor=%s]", name, color)
	end
	return out
end

-- Player inventory block for container menus (mcl_chests grammar).
-- Returns (elements, total form height when starting at y).
local function player_inventory(y)
	local hot_y = y + 0.375 + 3 * PITCH + 0.2
	local out = table.concat({
		label(X0 + OFF, y, S("Inventory"), LABEL_COLOR),
		slot_bg(X0, y + 0.375, 9, 3),
		"list[current_player;main;" .. X0 .. "," .. (y + 0.375) .. ";9,3;9]",
		slot_bg(X0, hot_y, 9, 1),
		"list[current_player;main;" .. X0 .. "," .. hot_y .. ";9,1;]",
		"listring[current_player;main]",
	}, "")
	return out, hot_y + PITCH + 0.125
end

local function head_container(title, size_h)
	return table.concat({
		"formspec_version[6]",
		string.format("size[11.75,%f]", size_h),
		label(X0 + OFF, 0.375, title, LABEL_COLOR),
	}, "")
end

local function head_prompt(title, w, h)
	return table.concat({
		"formspec_version[6]",
		string.format("size[%f,%f]", w, h),
		"bgcolor[#000000C0]",
		string.format("label[%f,0.3;%s]", math.max(0.3, (w - #title * 0.16) / 2),
			F(title)),
	}, "")
end

local function page_buttons(row, page, total_pages, y0)
	local y = btn_y(row, y0)
	return table.concat({
		button(btn_x(7), y, BTN, BTN, "prev_page", "<"),
		string.format("label[%f,%f;%s]", btn_x(8) + 0.15, y + 0.35,
			F(S("@1/@2", page, total_pages))),
		button(btn_x(9), y, BTN, BTN, "next_page", ">"),
	}, "")
end

----------------------------------------------------------------------
-- Board: Orders (Page @1)  [F0156–F0187, F0209–F0212]
----------------------------------------------------------------------

-- orders_page: array of order records for this page.
-- session: {page, sort, total_pages}
function fs.board(orders_page, session)
	local grid_rows = math.ceil(cfg.page_size / 9)          -- 5 for 45
	local rows = grid_rows + 1                              -- + control row
	local inv_y = 0.75 + rows * PITCH + 0.2
	local _, size_h = player_inventory(inv_y)

	local parts = {
		head_container(S("Orders (Page @1)", session.page), size_h),
		slot_bg(X0, 0.75, 9, rows),
	}

	for i, o in ipairs(orders_page) do
		if i > cfg.page_size then break end
		local col = (i - 1) % 9 + 1
		local row = math.floor((i - 1) / 9) + 1
		parts[#parts + 1] = item_button(col, row, o.template,
			"order_" .. o.id, display.order_tooltip_lines(o))
	end

	-- Control row (shared §4.3): book, hopper, chest, amethyst shard.
	local crow = rows
	parts[#parts + 1] = item_button(1, crow, fs.ITEM.book, "ctl_orders",
		{ S("Orders"), S("Request and deliver items") })
	local filter_lines = { S("Filter"), S("Click to change") }
	for _, s in ipairs(cfg.sorts) do
		filter_lines[#filter_lines + 1] = "• " .. S(fs.sort_label(s))
	end
	parts[#parts + 1] = item_button(2, crow, fs.ITEM.hopper, "ctl_filter",
		filter_lines)
	parts[#parts + 1] = item_button(3, crow, fs.ITEM.chest, "ctl_your",
		{ S("Your Orders") })
	parts[#parts + 1] = item_button(4, crow, fs.ITEM.shard, "ctl_shard",
		{ S("Shard Shop"), S("Click to view") })

	parts[#parts + 1] = page_buttons(crow, session.page,
		session.total_pages or 1)

	local inv = player_inventory(inv_y)
	parts[#parts + 1] = inv
	return table.concat(parts, "")
end

-- Sort enum -> observed option labels [F0180]
function fs.sort_label(sort)
	if sort == "most_per_item" then return "Most Per Item" end
	if sort == "most_paid" then return "Most Paid" end
	if sort == "recently_listed" then return "Recently Listed" end
	return sort
end

----------------------------------------------------------------------
-- Your Orders: Orders -> Your Orders  [F0190]
-- (slot layout unobserved — PROPOSED: occupied slots show the order,
--  empty slots offer "New Order", house style after f09's "New Home")
----------------------------------------------------------------------

function fs.your(orders, session, slot_limit)
	local page_size = cfg.page_size
	local total_pages = math.max(1, math.ceil(slot_limit / page_size))
	local shown = math.min(page_size, slot_limit)
	local grid_rows = math.ceil(shown / 9)
	local rows = grid_rows + 1
	local inv_y = 0.75 + rows * PITCH + 0.2
	local _, size_h = player_inventory(inv_y)

	local parts = {
		head_container(S("Orders -> Your Orders"), size_h),
		slot_bg(X0, 0.75, 9, rows),
	}

	local first = (session.page - 1) * page_size
	for i = 1, shown do
		local o = orders[first + i]
		local col = (i - 1) % 9 + 1
		local row = math.floor((i - 1) / 9) + 1
		if o then
			-- Own order: same tooltip as the board, but the affordance is
			-- manage, not deliver (PROPOSED — §3.5 unobserved).
			local lines = display.order_tooltip_lines(o)
			lines[#lines - 1] = S("Click to manage")
			parts[#parts + 1] = item_button(col, row, o.template,
				"order_" .. o.id, lines)
		else
			parts[#parts + 1] = item_button(col, row, fs.ITEM.book,
				"new_order", { S("New Order"), S("Click to create") })
		end
	end

	-- Back control (chest = Orders) + paging on the control row.
	local crow = rows
	parts[#parts + 1] = item_button(1, crow, fs.ITEM.chest, "ctl_back",
		{ S("Orders") })
	if total_pages > 1 then
		parts[#parts + 1] = page_buttons(crow, session.page, total_pages)
	end

	parts[#parts + 1] = player_inventory(inv_y)
	return table.concat(parts, "")
end

----------------------------------------------------------------------
-- Order manage (PROPOSED screen — cancellation/collection unobserved,
-- f04 §3.5, V-43/V-44). Prompt menu, house style per shared §4.5/§4.7.
----------------------------------------------------------------------

function fs.manage(o)
	local parts = {
		string.format("item_image[3.5,0.9;1,1;%s]", o.template),
	}
	local y = 2.2
	parts[#parts + 1] = label(0.5, y, S("Item: @1", display.item_name(o)))
	y = y + 0.5
	local ench = display.ench_line(o.ench)
	if ench ~= "" then
		parts[#parts + 1] = label(0.5, y, ench)
		y = y + 0.5
	end
	parts[#parts + 1] = label(0.5, y, S("@1 requested", display.qty(o.qty)))
	y = y + 0.5
	parts[#parts + 1] = label(0.5, y, S("@1/@2 Delivered",
		display.qty(o.delivered), display.qty(o.qty)))
	y = y + 0.5
	parts[#parts + 1] = label(0.5, y, S("Price: $ @1 each",
		display.money_num(o.unit_price)))
	y = y + 0.5
	parts[#parts + 1] = label(0.5, y, S("Escrow: $ @1",
		display.money_num(o.escrow)))
	y = y + 0.5
	parts[#parts + 1] = label(0.5, y, S("@1 collected", display.qty(o.collected)))
	y = y + 0.8

	parts[#parts + 1] = button(0.5, y, 3.4, 0.8, "collect_items",
		S("Collect Items"), GREEN)
	parts[#parts + 1] = button(4.1, y, 3.4, 0.8, "cancel_order",
		S("Cancel Order"), RED)
	y = y + 1.0
	parts[#parts + 1] = button(2.3, y, 3.4, 0.8, "back", S("Back"))

	return table.concat({
		head_prompt(display.order_name(o), 8, y + 1.2),
		table.concat(parts, ""),
	}, "")
end

----------------------------------------------------------------------
-- Wizard step 1: Choose Item  [F0191–F0198]
----------------------------------------------------------------------

fs.CATALOG_COLS = 4
fs.CATALOG_ROWS = 6
fs.CATALOG_PAGE = fs.CATALOG_COLS * fs.CATALOG_ROWS   -- 24

-- session: {search, searched, results (array of item names), page}
function fs.choose_item(session)
	local results = session.results or {}
	local title
	if session.searched then
		-- "(1 results)" — the ungrammatical plural is a requirement
		-- (shared §0.5, T4)
		title = S("Choose Item (@1 results)", #results)
	else
		title = S("Choose Item")
	end

	local y0 = 2.4
	local grid_h = fs.CATALOG_ROWS * PITCH
	local h = y0 + grid_h + 1.0
	local parts = {
		head_prompt(title, 11.75, h),
		-- Search field (shared §4.6: label above the field)
		string.format("label[%f,0.8;%s]", X0 + OFF, F(S("Search"))),
		string.format("field[%f,1.2;6,0.8;search;;%s]", X0 + OFF,
			F(session.search or "")),
		"field_close_on_enter[search;false]",
		button(7.0, 1.2, 2.0, 0.8, "do_search", S("Search"), GREEN),
		button(9.2, 1.2, 2.0, 0.8, "wiz_cancel", S("Cancel"), RED),
		slot_bg(X0, y0, fs.CATALOG_COLS, fs.CATALOG_ROWS),
	}

	local total_pages = math.max(1, math.ceil(#results / fs.CATALOG_PAGE))
	local page = math.min(session.page or 1, total_pages)
	local first = (page - 1) * fs.CATALOG_PAGE
	for i = 1, fs.CATALOG_PAGE do
		local name = results[first + i]
		if not name then break end
		local col = (i - 1) % fs.CATALOG_COLS + 1
		local row = math.floor((i - 1) / fs.CATALOG_COLS) + 1
		local lines = { smp_items.display_name(name) }
		local worth = smp_orders.worth_of(name)
		if worth then
			-- "Acacia Boat / Worth: $ 12" [F0192] (V-46: meaning open)
			lines[#lines + 1] = S("Worth: @1", display.money(worth))
		end
		parts[#parts + 1] = item_button(col, row, name, "item_" .. i, lines, y0)
	end

	if total_pages > 1 then
		local py = y0 + grid_h + 0.05
		parts[#parts + 1] = button(X0, py, 1.1, 0.8, "prev_page", "<")
		parts[#parts + 1] = string.format("label[%f,%f;%s]", X0 + 1.5, py + 0.2,
			F(S("@1/@2", page, total_pages)))
		parts[#parts + 1] = button(X0 + 3.2, py, 1.1, 0.8, "next_page", ">")
	end

	return table.concat(parts, "")
end

----------------------------------------------------------------------
-- Wizard step 2: How many?  [F0199]
----------------------------------------------------------------------

function fs.how_many(session)
	local default = tostring(session.amount or cfg.default_amount)
	return table.concat({
		head_prompt(S("How many?"), 8, 3.6),
		string.format("label[0.5,0.9;%s]", F(S("Amount"))),
		string.format("field[0.5,1.3;7,0.8;amount;;%s]", F(default)),
		"field_close_on_enter[amount;false]",
		button(0.5, 2.5, 3.2, 0.8, "wiz_cancel", S("Cancel"), RED),
		button(4.3, 2.5, 3.2, 0.8, "wiz_next", S("Next"), GREEN),
	}, "")
end

----------------------------------------------------------------------
-- Wizard step 3: Price per item?  [F0202, F0203]
----------------------------------------------------------------------

function fs.price_per_item(session)
	local item = session.item
	local default = session.price and display.money_num(session.price) or ""
	return table.concat({
		head_prompt(S("Price per item?"), 8, 5.6),
		string.format("item_image[3.5,0.8;1,1;%s]", item and item.name or ""),
		label(0.5, 2.1, S("Amount: @1", display.qty(session.amount or 0))),
		label(0.5, 2.6, S("Minimum: $ @1", display.money_num(cfg.min_price))),
		string.format("field[0.5,3.3;7,0.8;price;%s;%s]",
			F(S("Price")), F(default)),
		"field_close_on_enter[price;false]",
		button(0.5, 4.5, 3.2, 0.8, "wiz_cancel", S("Cancel"), RED),
		button(4.3, 4.5, 3.2, 0.8, "wiz_review", S("Review Order"), GREEN),
	}, "")
end

----------------------------------------------------------------------
-- Wizard step 4: Review Order  [F0204–F0208] (shared §4.7 model)
----------------------------------------------------------------------

function fs.review(session)
	local item = session.item
	local total = (session.price or 0) * (session.amount or 0)
	return table.concat({
		head_prompt(S("Review Order"), 9, 7.6),
		string.format("item_image[4,0.8;1,1;%s]", item and item.name or ""),
		label(0.7, 2.1, S("Item: @1",
			smp_items.display_name(item and item.name or ""))),
		label(0.7, 2.6, S("Amount: @1", display.qty(session.amount or 0))),
		label(0.7, 3.1, S("Price: $ @1 each", display.money_num(session.price or 0))),
		label(0.7, 3.6, S("Total: $ @1", display.money_num(total))),
		button(0.7, 4.4, 3.6, 0.8, "wiz_cancel_bang", S("Cancel!"), RED),
		button(4.7, 4.4, 3.6, 0.8, "change_item", S("Change Item")),
		button(0.7, 5.4, 3.6, 0.8, "change_amount", S("Change Amount")),
		button(4.7, 5.4, 3.6, 0.8, "change_price", S("Change Price")),
		button(2.7, 6.4, 3.6, 0.8, "create_order", S("Create Order"), GREEN),
	}, "")
end

----------------------------------------------------------------------
-- Delivery: Orders -> Deliver Items  [F0214–F0216]
----------------------------------------------------------------------

local function detached_list_name(player_name)
	return "smp_orders_deliver_" .. player_name
end
fs.detached_list_name = detached_list_name

-- payout_preview: cents the Confirm pane would pay right now
function fs.deliver_items(player_name, payout_preview)
	local grid_rows = 3
	local control_y = 0.75 + grid_rows * PITCH
	local inv_y = control_y + PITCH + 0.2
	local _, size_h = player_inventory(inv_y)

	return table.concat({
		head_container(S("Orders -> Deliver Items"), size_h),
		slot_bg(X0, 0.75, 9, grid_rows),
		"list[" .. detached_list_name(player_name) .. ";main;" ..
			X0 .. ",0.75;9," .. grid_rows .. ";]",
		-- Confirm control: lime pane (shared §4.3, [F0222])
		item_button(9, 1, fs.ITEM.lime, "to_confirm",
			{ S("Confirm"),
			  S("Click to deliver items ($@1)", display.money_num(payout_preview)) },
			control_y),
		player_inventory(inv_y),
		"listring[" .. detached_list_name(player_name) .. ";main]",
		"listring[current_player;main]",
	}, "")
end

----------------------------------------------------------------------
-- Delivery: Orders -> Confirm Delivery  [F0218, F0219, F0222]
----------------------------------------------------------------------

function fs.confirm_delivery(player_name, order, delivering_count, payout_preview)
	local grid_rows = 3
	local control_y = 0.75 + grid_rows * PITCH
	local inv_y = control_y + PITCH + 0.2
	local _, size_h = player_inventory(inv_y)
	size_h = math.max(size_h, 6.4)

	-- Detail panel [F0219]: plural name, "300k requested", "$30K each",
	-- "You're delivering 1 Totems of Undying" (PLURAL at qty 1), itemstring.
	-- The Java "15 component(s)" line is dropped (shared §0.5.1).
	local panel_lines = display.confirm_lines(order, delivering_count)
	local panel = {
		string.format("box[12.0,0.6;3.5,%f;#2A0A3A]", 0.5 * #panel_lines + 0.4),
	}
	for i, line in ipairs(panel_lines) do
		panel[#panel + 1] = string.format("label[12.2,%f;%s]",
			0.8 + (i - 1) * 0.5, F(line))
	end

	return table.concat({
		"formspec_version[6]",
		string.format("size[%f,%f]", 15.75, size_h),
		label(X0 + OFF, 0.375, S("Orders -> Confirm Delivery"), LABEL_COLOR),
		slot_bg(X0, 0.75, 9, grid_rows),
		"list[" .. detached_list_name(player_name) .. ";main;" ..
			X0 .. ",0.75;9," .. grid_rows .. ";]",
		-- Confirm control: lime pane [F0222]
		item_button(9, 1, fs.ITEM.lime, "confirm_delivery",
			{ S("Confirm"),
			  S("Click to deliver items ($@1)", display.money_num(payout_preview)) },
			control_y),
		table.concat(panel, ""),
		player_inventory(inv_y),
		"listring[" .. detached_list_name(player_name) .. ";main]",
		"listring[current_player;main]",
	}, "")
end
