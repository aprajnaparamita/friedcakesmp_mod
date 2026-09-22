-- FriedcakeSMP — smp_stats / formspec.lua
-- /stats and /leaderboard menus (f14 §8, grammar per shared/04-ui-kit
-- §4.1–§4.9; both layouts PROPOSED — V-23, §10 F14-D6).
--
-- Families:
--   prompt menus (translucent dark, no inventory):
--     Stats, Stats - <name>, Leaderboard
--   container menus (player inventory shown):
--     <Category> (Page N)   — the leaderboard itself, textlist rows
--                             `@1. @2 — @3` (§4.2.4)
--
-- Geometry copied from smp_orders/formspec.lua (mcl_chests /
-- mcl_formspec grammar): X0 grid margin, slot pitch, control row,
-- player inventory, Back button.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_stats.S
local F = core.formspec_escape

smp_stats.fs = {}
local fs = smp_stats.fs

fs.FORMNAME = {
	stats = "smp_stats:stats",
	pick  = "smp_stats:leaderboard",
	board = "smp_stats:board",
}

----------------------------------------------------------------------
-- Geometry (mcl_chests / mcl_formspec grammar, cf. smp_orders)
----------------------------------------------------------------------

local X0 = 0.375          -- grid left margin
local PITCH = 1.25        -- slot/button pitch
local BTN = 1.1           -- slot/button cell size
local OFF = -0.05         -- slot-bg border offset
local LABEL_COLOR = (mcl_formspec and mcl_formspec.label_color) or "#313131"

local function slot_bg(x, y, w, h)
	if mcl_formspec and mcl_formspec.get_itemslot_bg_v4 then
		return mcl_formspec.get_itemslot_bg_v4(x, y, w, h)
	end
	return ""
end

local function label(x, y, text, color)
	return string.format("label[%f,%f;%s]", x, y,
		F(color and (color .. text) or text))
end

local function button(x, y, w, h, name, text)
	return string.format("button[%f,%f;%f,%f;%s;%s]",
		x, y, w, h, name, F(text))
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
		string.format("label[%f,0.3;%s]",
			math.max(0.3, (w - #title * 0.16) / 2), F(title)),
	}, "")
end

-- Player inventory block for container menus (shared §4.1).
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

----------------------------------------------------------------------
-- /stats screen (PROPOSED, V-23): a prompt menu of `<Field>: <Value>`
-- lines, house grammar per shared §4.5. Field labels are the claim's
-- verbatim strings.
----------------------------------------------------------------------

-- { display label, rec.stats key } (live fields go through get()).
fs.STATS_ROWS = {
	{ "Broken Blocks",      "broken_blocks"           },
	{ "Placed Blocks",      "placed_blocks"           },
	{ "Kills",              "kills"                   },
	{ "Deaths",             "deaths"                  },
	{ "Mob Kills",          "mobs_killed"             },
	{ "Money",              "money"                   },
	{ "Shards",             "shards"                  },
	{ "Playtime",           "playtime"                },
	{ "Money from Selling", "money_made_from_sell"    },
	{ "Spent in Shop",      "money_spent_on_shop"     },
}

local function stat_value(key, target)
	local v = smp_stats.get(target, key)
	if key == "money" or key == "money_made_from_sell"
	   or key == "money_spent_on_shop" then
		return smp_core.fmt_money(v, "body")
	end
	if key == "playtime" then
		return tostring(math.floor(v)) -- raw seconds (§0.6, F14-D8)
	end
	return smp_core.fmt_qty(v)
end

-- viewer sees `Stats` for self, `Stats - <name>` for others (§4.1.1).
function fs.stats(viewer, target)
	local title = (target == viewer) and S("Stats")
		or S("Stats - @1", target)
	local parts = { head_prompt(title, 8, 7.4) }
	local y = 0.9
	for _, row in ipairs(fs.STATS_ROWS) do
		parts[#parts + 1] = string.format("label[0.5,%f;%s]", y,
			F(S("@1: @2", S(row[1]), stat_value(row[2], target))))
		y = y + 0.5
	end
	parts[#parts + 1] = button(2.3, y + 0.3, 3.4, 0.8, "back", S("Back"))
	return table.concat(parts, "")
end

----------------------------------------------------------------------
-- /leaderboard picker (PROPOSED, V-23): a prompt menu with one button
-- per official category, then Back.
----------------------------------------------------------------------

function fs.picker()
	local cats = smp_stats.CATEGORIES
	local h = 0.9 + #cats * 0.85 + 1.4
	local parts = { head_prompt(S("Leaderboard"), 8, h) }
	local y = 0.9
	for _, cat in ipairs(cats) do
		parts[#parts + 1] = string.format("button[0.5,%f;7,0.7;cat_%s;%s]",
			y, cat.key, F(S(cat.label)))
		y = y + 0.85
	end
	parts[#parts + 1] = button(2.3, y + 0.1, 3.4, 0.8, "back", S("Back"))
	return table.concat(parts, "")
end

----------------------------------------------------------------------
-- Leaderboard container: `<Category> (Page N)` + textlist rows
-- `@1. @2 — @3` (§4.2.4), prev/next/Back, player inventory (shared
-- §4.1 container grammar).
----------------------------------------------------------------------

local TEXTLIST_H = 3.75

function fs.board(cat, rows, page, total_pages)
	-- textlist cells: `1. Notch — $ 1.2B` (house style, §4.2.4).
	local cells = {}
	for i, e in ipairs(rows) do
		local rank = (page - 1) * smp_stats.PAGE_SIZE + i
		cells[#cells + 1] = F(S("@1. @2 — @3", rank, e.name,
			smp_stats.format_value(cat, e.value)))
	end

	local control_y = 0.75 + TEXTLIST_H + 0.15
	local inv_y = control_y + 0.9
	local inv, size_h = player_inventory(inv_y)

	return table.concat({
		head_container(S("@1 (Page @2)", S(cat.label), page), size_h),
		string.format("textlist[%f,%f;%f,%f;rows;%s;;true]",
			X0 + OFF, 0.75, 11.0, TEXTLIST_H, table.concat(cells, ",")),
		button(X0, control_y, BTN, BTN, "prev_page", "<"),
		label(X0 + BTN + 0.25, control_y + 0.35,
			S("@1/@2", page, total_pages)),
		button(X0 + BTN + 1.9, control_y, BTN, BTN, "next_page", ">"),
		button(X0 + 4.5, control_y, 3.0, BTN, "back", S("Back")),
		inv,
	}, "")
end

----------------------------------------------------------------------
-- Openers (smp_core session per formname, smp_economy leave hook
-- closes them all on disconnect).

function fs.show_stats(viewer, target)
	if not smp_store.api.get_player(target) then
		return false, S("Player @1 does not exist.", target)
	end
	local pname = smp_stats.name_of(viewer)
	if not pname or not core.get_player_by_name(pname) then
		return false, S("Player @1 does not exist.", tostring(viewer))
	end
	smp_core.open_session(pname, fs.FORMNAME.stats, {})
	smp_core.show_formspec(pname, fs.FORMNAME.stats, fs.stats(pname, target))
	return true
end

function fs.show_picker(viewer)
	local pname = smp_stats.name_of(viewer)
	if not pname or not core.get_player_by_name(pname) then
		return false, S("Player @1 does not exist.", tostring(viewer))
	end
	smp_core.open_session(pname, fs.FORMNAME.pick, {})
	smp_core.show_formspec(pname, fs.FORMNAME.pick, fs.picker())
	return true
end

function fs.show_board(viewer, cat_key, page)
	local cat = smp_stats.category_by_key(cat_key)
	if not cat then
		return false, S("Unknown leaderboard category: @1", tostring(cat_key))
	end
	local pname = smp_stats.name_of(viewer)
	if not pname or not core.get_player_by_name(pname) then
		return false, S("Player @1 does not exist.", tostring(viewer))
	end
	local session = smp_core.open_session(pname, fs.FORMNAME.board, {})
	session.cat = cat_key
	local rows, clamped, total_pages = smp_stats.board_page(
		smp_stats.boards[cat_key], page)
	session.page = clamped
	smp_core.show_formspec(pname, fs.FORMNAME.board,
		fs.board(cat, rows, clamped, total_pages))
	return true
end

----------------------------------------------------------------------
-- Field handlers: every field is untrusted and re-validated against
-- the open session (shared §2.4); unknown ids do nothing.

core.register_on_player_receive_fields(function(player, formname, fields)
	if type(formname) ~= "string" or type(fields) ~= "table" then return end
	local FORM = fs.FORMNAME
	if formname ~= FORM.stats and formname ~= FORM.pick
	   and formname ~= FORM.board then return end
	local pname = player.get_player_name and player:get_player_name()
	if not pname then return end
	local session = smp_core.get_session(pname, formname)
	if not session then return end -- click outside an open session
	if fields.quit then
		smp_core.close_session(pname, formname)
		return
	end
	if fields.back then
		smp_core.close_session(pname, formname)
		if formname == FORM.board then
			fs.show_picker(pname) -- Back from a board returns to the picker
		end
		return
	end
	if formname == FORM.pick then
		for k in pairs(fields) do
			local key = type(k) == "string" and k:match("^cat_(%w+)$") or nil
			if key and smp_stats.category_by_key(key) then
				smp_core.close_session(pname, formname)
				fs.show_board(pname, key, 1)
				return
			end
		end
		return
	end
	if formname == FORM.board then
		local page = tonumber(session.page) or 1
		if fields.prev_page then
			fs.show_board(pname, session.cat, page - 1)
		elseif fields.next_page then
			fs.show_board(pname, session.cat, page + 1)
		end
		-- textlist CHG/DCL events carry no action (scroll only).
		return
	end
	-- FORM.stats: only Back and quit act.
end)
