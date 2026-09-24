-- FriedcakeSMP — smp_ah/formspec.lua
--
-- Every auction-house menu, built to the observed grammar in
-- spec/shared/04-ui-kit.md and the observed strings in f03 §3.
--
-- Menu families (shared §4.1):
--
--   container menu  `Auction (Page N)`, `Auction > Your Items`, `Insert Item`,
--                   `Confirm Listing`, `Auction > Confirm Purchase`
--                   — opaque light grey, slot grid, `Inventory` label, the
--                     player's own inventory below. Controls are items with
--                     tooltips (shared §4.3).
--   prompt menu     `Search Auction`, `Edit Sign Message`
--                   — translucent dark, no inventory, real buttons.
--
-- Fidelity rules this file implements:
--
--   * Every observed string is reproduced exactly, including the auction's
--     `>` separator (not orders' `->`) — shared §4.2.
--   * The one dropped line is Java's `15 component(s)` (shared §0.5.1). The
--     Minecraft itemstring line above it is kept and translated to
--     Mineclonia's.
--   * Money spacing follows shared §0.6: the suffixed form uses a space, the
--     bare form does not. Both are reproduced; neither is normalised away.
--   * Control itemstrings are resolved against `core.registered_items` at
--     load time — the glass-pane mapping is the least certain row of shared
--     §4.3 and MUST NOT be hardcoded.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_ah = smp_ah or {}

local fs = {}
smp_ah.fs = fs

local F = core.formspec_escape
local C = core.colorize

-- Translation. init.lua installs the real translator before dofile'ing this
-- module; the fallback keeps the file loadable on its own (dev tests).
local S = smp_ah.S or core.get_translator(core.get_current_modname() or "smp_ah")
fs.set_translator = function(fn) S = fn end

----------------------------------------------------------------------
-- Geometry
--
-- Container-menu measurements follow Mineclonia's own chest formspecs
-- (mods/ITEMS/mcl_chests/init.lua): 11.75 wide, slots on a 1.25 pitch,
-- margins at 0.375, `Inventory` label above the player's 3+1 rows.
----------------------------------------------------------------------

local G = {
	x0    = 0.375,
	pitch = 1.25,
	cols  = 9,
	rows  = 6,          -- 5 listing rows (page_size 45) + 1 control row
	-- Six-row container menu: `Auction (Page N)`, `Auction > Your Items`.
	board = { w = 11.75, h = 14.15, grid_y = 0.75,
		inv_label_y = 8.45, inv_y = 8.825, hot_y = 12.775 },
	-- One-row container menu: `Insert Item`, `Confirm Listing`,
	-- `Auction > Confirm Purchase`. Mirrors mcl_hoppers' proportions.
	small = { w = 11.75, h = 8.175, row_y = 0.75,
		inv_label_y = 2.45, inv_y = 2.85, hot_y = 6.8 },
	-- Prompt menus (shared §4.1: "approximately the middle third").
	prompt = { w = 8, h = 3.6 },
	sign   = { w = 8, h = 3.2 },
}
fs.G = G

local function c(v) return string.format("%.6g", v) end

-- 1-based column/row -> formspec coordinate.
local function sx(col) return G.x0 + (col - 1) * G.pitch end
local function sy(row, y0) return (y0 or G.board.grid_y) + (row - 1) * G.pitch end
fs.sx, fs.sy = sx, sy

local function slot_bg(x, y, w, h)
	if mcl_formspec and type(mcl_formspec.get_itemslot_bg_v4) == "function" then
		return mcl_formspec.get_itemslot_bg_v4(x, y, w, h)
	end
	-- Same output, without the Mineclonia helper (shared §4.9).
	local out = {}
	for j = 0, h - 1 do
		for i = 0, w - 1 do
			out[#out + 1] = "image[" .. c(x + i * G.pitch - 0.05) .. "," ..
				c(y + j * G.pitch - 0.05) .. ";1.1,1.1;mcl_formspec_itemslot.png]"
		end
	end
	return table.concat(out)
end
fs.slot_bg = slot_bg

local LABEL_COLOR = "#313131"
local function label_color(text)
	local color = (mcl_formspec and mcl_formspec.label_color) or LABEL_COLOR
	return C(color, text)
end

local function label(x, y, text)
	return "label[" .. c(x) .. "," .. c(y) .. ";" .. F(label_color(text)) .. "]"
end

local function area_label(x, y, w, h, text)
	return "label[" .. c(x) .. "," .. c(y) .. ";" .. c(w) .. "," .. c(h) .. ";" ..
		F(text) .. "]"
end

----------------------------------------------------------------------
-- Money (shared §0.6)
--
-- "Observed spacing is inconsistent: `$700` with no space [F0108] and
--  `$ 30K` with a space [F0212] both appear. The suffixed form uses a space
--  and the bare form does not. Implementations MUST follow that rule and
--  MUST NOT normalise it away."
--
-- `smp_core.fmt_money` offers two fixed styles: `inline` never spaces
-- ("$700", "$9K") and `body` always spaces ("$ 700", "$ 9K"). Neither alone
-- satisfies §0.6, so the §0.6 rule is derived from the two sanctioned styles
-- instead of reimplemented (AGENTS.md rule 6: always `smp_core.fmt_money`).
----------------------------------------------------------------------

local function fmt(cents, style)
	if smp_core and type(smp_core.fmt_money) == "function" then
		return smp_core.fmt_money(cents, style)
	end
	return "$" .. tostring(math.floor((tonumber(cents) or 0) / 100))
end

--- The §0.6 form: `$700`, `$1`, `$ 9K`, `$ 5.1K`, `$ 4M`.
-- Standalone amounts — a board tooltip's price line, a chat line.
function fs.money(cents)
	local inline = fmt(cents, "inline")
	if inline:match("^%$[%d%.]+$") then return inline end   -- bare: no space
	return fmt(cents, "body")                                -- suffixed: space
end

--- Parenthesised and other inline amounts: `$30K` [F0222], `$1` [F0142].
function fs.money_inline(cents) return fmt(cents, "inline") end

--- The part of the amount after a literal `$` in a translated template.
-- For templates written `$@1` (no space): `$1`, `$ 9K`  -> "1", " 9K".
function fs.money_tail(cents) return (fs.money(cents):sub(2)) end

--- For templates written `$ @1` (dollar + space): "1", "9K".
-- `You bought @1 @2 for $ @3` [08-ui-strings §8.6] is this shape.
function fs.money_after(cents)
	local tail = fs.money(cents):sub(2)
	return (tail:gsub("^%s+", ""))
end

fs.fmt_money = fmt

----------------------------------------------------------------------
-- Control items (shared §4.3)
--
-- The Java item is mapped to a Mineclonia itemstring. The two glass panes are
-- the least certain row of the table, so nothing is hardcoded: candidates are
-- tried in order against `core.registered_items` / `core.registered_aliases`,
-- then the registry is probed by pattern, then a colourized fallback is used.
-- Mineclonia registers panes as `mcl_panes:pane_<mcl_dyes colour>` — verified
-- in ~/dev/mineclonia-git mods/ITEMS/mcl_panes/init.lua: the colours come
-- from `mcl_dyes.colors`, where Java's "gray" is Mineclonia's `grey`
-- (rgb #383c40) and "light gray" is `silver`.
----------------------------------------------------------------------

local CONTROLS = {
	-- `minecraft:oak_sign` — Search [F0111, F0125]
	search = {
		candidates = {
			"mcl_signs:wall_sign_oak", "mcl_signs:standing_sign_oak",
			"mcl_signs:sign_oak", "mcl_signs:wall_sign", "mcl_signs:oak_sign",
		},
		probe = "sign.*oak",
	},
	-- `minecraft:hopper` — Filter [F0118–F0123]
	filter = {
		candidates = { "mcl_hoppers:hopper", "mcl_hoppers:hopper_disabled" },
		probe = "hopper",
	},
	-- `minecraft:chest` — Your Items [F0126–F0129]
	your_items = {
		candidates = { "mcl_chests:chest", "mcl_chests:chest_small" },
		probe = "chests:chest",
	},
	-- `minecraft:gray_stained_glass_pane` — List [F0131]
	list = {
		candidates = {
			"mcl_panes:pane_grey", "mcl_panes:pane_grey_flat",
			"mcl_core:glass_pane_gray", "mcl_core:glass_pane_grey",
			"mcl_panes:pane_gray", "mcl_panes:pane_silver",
			"mcl_panes:pane_natural",
		},
		probe = "pane.*gr[ae]y",
		color = "#383c40",   -- mcl_dyes.colors.grey.rgb
	},
	-- `minecraft:lime_stained_glass_pane` — Confirm [F0222]
	confirm = {
		candidates = {
			"mcl_panes:pane_lime", "mcl_panes:pane_lime_flat",
			"mcl_core:glass_pane_lime", "mcl_panes:pane_green",
			"mcl_panes:pane_natural",
		},
		probe = "pane.*lime",
		color = "#60ac19",   -- mcl_dyes.colors.lime.rgb
	},
	-- Cancel control. Not observed in f03 (F0142 shows a red block in the
	-- `Confirm Listing` grid); red is the house colour for `Cancel` [F0114].
	-- PROPOSED — see f03 §10.
	cancel = {
		candidates = {
			"mcl_panes:pane_red", "mcl_panes:pane_red_flat",
			"mcl_core:glass_pane_red", "mcl_panes:pane_grey",
			"mcl_panes:pane_natural",
		},
		probe = "pane.*red",
		color = "#a12722",
	},
	-- `minecraft:anvil` — the `Auction` / `Buy and sell items` entry point
	-- [F0107]. Reused as the "back to the board" control on sub-screens.
	-- PROPOSED placement — see f03 §10.
	board = {
		candidates = {
			"mcl_anvils:anvil", "mcl_anvils:anvil_damaged_1",
			"mcl_anvils:anvil_damaged_2",
		},
		probe = "anvil",
	},
	-- `Match lowest` — Quick Auction Sell affordance (f03 §4.12, PROPOSED).
	-- Uses a comparator (redstone) to suggest price comparison.
	match_lowest = {
		candidates = {
			"mcl_redstone:comparator", "mcl_redstone:comparator_off",
		},
		probe = "comparator",
	},
}
fs.CONTROLS = CONTROLS

local resolved_items = {}
local registry_ready = false

--- True once every mod has registered its items. Called from
-- `core.register_on_mods_loaded`; before that, resolution is provisional and
-- not cached as final.
function fs.registry_ready(flag)
	registry_ready = flag and true or false
	if not registry_ready then resolved_items = {} end
end

local function is_registered(name)
	if type(name) ~= "string" or name == "" then return false end
	if core.registered_items and core.registered_items[name] then return true end
	if core.registered_nodes and core.registered_nodes[name] then return true end
	if core.registered_aliases then
		local target = core.registered_aliases[name]
		if target and core.registered_items and core.registered_items[target] then
			return true
		end
	end
	return false
end

--- Probe the registry for the first (alphabetically, so the choice is stable)
-- item matching a Lua pattern.
local function probe(pattern)
	if not core.registered_items or not pattern then return nil end
	local best
	for name in pairs(core.registered_items) do
		if name ~= "" and name ~= "unknown" and name:find(pattern) then
			if not best or name < best then best = name end
		end
	end
	return best
end

--- Resolve a control's itemstring. Returns `itemstring, colour_fallback`.
-- `colour_fallback` is non-nil when no coloured variant exists and the caller
-- should colourize a plain texture instead (tools/claim-f03.md, Heads-up 2).
function fs.item_info(kind)
	local def = CONTROLS[kind]
	if not def then return nil, nil end
	local hit = resolved_items[kind]
	if hit and (hit.final or not registry_ready) then
		return hit.name, hit.colorize
	end
	local name
	for _, cand in ipairs(def.candidates) do
		if is_registered(cand) then name = cand break end
	end
	local colorize
	if not name then
		name = probe(def.probe)
		if not name then
			-- Nothing in this game matches: degrade to a labelled button, and
			-- tell the operator which mapping needs fixing.
			name = nil
			if core.log then
				core.log("warning", "[smp_ah] no Mineclonia item for control '" ..
					kind .. "' (shared/04-ui-kit.md §4.3); falling back to a button")
			end
		elseif def.color then
			-- A pane exists but not in the right colour: colourize it.
			colorize = def.color
		end
	end
	resolved_items[kind] = { name = name, colorize = colorize,
		final = registry_ready }
	return name, colorize
end

function fs.item(kind)
	local name = fs.item_info(kind)
	return name or ""
end

--- Forget the cached resolution (dev tests, `/smp reload`).
function fs.reset_items()
	resolved_items = {}
end

--- The item-as-button element itself (shared §4.9 "Item-as-button").
--- `fallback_label` is used only when this game registers no matching item.
local function control_element(name, x, y, kind, fallback_label)
	local item, colorize = fs.item_info(kind)
	local size = c(G.pitch) .. "," .. c(G.pitch)
	if item then
		if colorize then
			-- No coloured pane in this game: colourize a texture instead.
			local def = core.registered_items[item]
			local tex = def and (def.inventory_image or
				(def.tiles and def.tiles[1])) or nil
			if tex and type(tex) == "string" and tex ~= "" then
				tex = tex:gsub("%^.*$", "") .. "^[colorize:" .. colorize
				return "image_button[" .. c(x) .. "," .. c(y) .. ";" .. size .. ";" ..
					F(tex) .. ";" .. F(name) .. ";]"
			end
		end
		return "item_image_button[" .. c(x) .. "," .. c(y) .. ";" .. size .. ";" ..
			F(item) .. ";" .. F(name) .. ";]"
	end
	-- Last resort: a plain button carrying the control's own label.
	return "button[" .. c(x) .. "," .. c(y) .. ";" .. size .. ";" .. F(name) .. ";" ..
		F(fallback_label or kind) .. "]"
end
fs.control_element = control_element

----------------------------------------------------------------------
-- Tooltips
----------------------------------------------------------------------

--- Multi-line tooltip for a named element (shared §4.9). Each line is
-- escaped separately and joined with a literal `\n`, which the formspec
-- parser turns into a line break.
function fs.tooltip(name, lines, bgcolor, fontcolor)
	local out = {}
	for i, line in ipairs(lines) do
		out[i] = F(tostring(line))
	end
	local s = "tooltip[" .. F(name) .. ";" .. table.concat(out, "\\n")
	if bgcolor then s = s .. ";" .. F(bgcolor) end
	if fontcolor then s = s .. ";" .. F(fontcolor) end
	return s .. "]"
end

--- Item-as-button control with its observed tooltip lines (shared §4.3).
function fs.control(name, x, y, kind, lines)
	return control_element(name, x, y, kind, lines and lines[1]) ..
		fs.tooltip(name, lines)
end

----------------------------------------------------------------------
-- Listing tooltips (f03 §3.1, shared §4.4)
--
--   Ender Pearl                 <- singular display name
--   $700                        <- total price
--   minecraft:ender_pearl       <- itemstring (translated to Mineclonia)
--   15 component(s)             <- DROP (shared §0.5.1)
--
-- Not present on the observed board: seller, time remaining, unit price.
----------------------------------------------------------------------

local HIGHLIGHT = "#FFFF55"

--- Enchantment lines in Mineclonia's own convention (shared §4.4 rule 4:
-- vanilla stat lines are not cloned). PROPOSED; see f03 §10.
local function ench_lines(rec)
	local out = {}
	local ench = rec.display and rec.display.ench
	if type(ench) ~= "table" then return out end
	for _, e in ipairs(ench) do
		local text
		if mcl_enchanting and type(mcl_enchanting.get_enchantment_description) == "function" then
			local ok, desc = pcall(mcl_enchanting.get_enchantment_description, e.id, e.level)
			if ok and type(desc) == "string" and desc ~= "" then text = desc end
		end
		if not text then
			local roman
			if mcl_util and type(mcl_util.to_roman) == "function" then
				roman = mcl_util.to_roman(e.level)
			end
			text = tostring(e.id):gsub("_", " ")
			if roman and (tonumber(e.level) or 1) > 1 then text = text .. " " .. roman end
		end
		out[#out + 1] = C("#AAAAAA", text)
	end
	return out
end
fs.ench_lines = ench_lines

--- The observed three lines (+ any enchantment lines), in order.
-- `extra` lines (an affordance hint) go between the price and the itemstring,
-- matching the order-tooltip grammar of shared §4.4.
function fs.listing_tooltip_lines(rec, extra)
	local lines = {}
	local display = rec.display or {}
	lines[#lines + 1] = display.name or rec.name or ""
	for _, l in ipairs(ench_lines(rec)) do lines[#lines + 1] = l end
	lines[#lines + 1] = fs.money(rec.price or 0)
	for _, l in ipairs(extra or {}) do lines[#lines + 1] = l end
	-- The Java itemstring becomes the Mineclonia one (shared §0.5.1).
	lines[#lines + 1] = C("#AAAAAA", rec.name or "")
	-- The `15 component(s)` line is the one observed line that is dropped.
	return lines
end

--- One listing rendered as a clickable slot: icon, tooltip, and the stack
-- count badge the observed board shows on the icon [F0108, F0111].
-- @param name element name (carries no trust: the handler re-validates)
function fs.listing_cell(rec, x, y, name, extra_lines)
	local out = {
		"item_image_button[" .. c(x) .. "," .. c(y) .. ";" .. c(G.pitch) .. "," ..
			c(G.pitch) .. ";" .. F(rec.name or "") .. ";" .. F(name) .. ";]",
		fs.tooltip(name, fs.listing_tooltip_lines(rec, extra_lines)),
	}
	local count = math.floor(tonumber(rec.count) or 1)
	if count > 1 then
		-- Count badge, bottom-right of the slot. A label passes clicks through
		-- to the button below (irrlicht's static text consumes no events) and
		-- the colour escape overrides the game's label colour.
		out[#out + 1] = "label[" .. c(x + 0.70) .. "," .. c(y + 0.78) .. ";" ..
			F(C("#FFFFFF", tostring(count))) .. "]"
	end
	return table.concat(out)
end

----------------------------------------------------------------------
-- Shared pieces
----------------------------------------------------------------------

local function preamble(size_w, size_h)
	return "formspec_version[6]size[" .. c(size_w) .. "," .. c(size_h) .. "]"
end

--- The player's inventory + `Inventory` label (shared §4.1: shown in every
--- container menu).
function fs.player_inventory(g)
	return table.concat({
		label(g.x0 or G.x0, g.inv_label_y, S("Inventory")),
		slot_bg(g.x0 or G.x0, g.inv_y, G.cols, 3),
		"list[current_player;main;" .. c(g.x0 or G.x0) .. "," .. c(g.inv_y) .. ";9,3;9]",
		slot_bg(g.x0 or G.x0, g.hot_y, G.cols, 1),
		"list[current_player;main;" .. c(g.x0 or G.x0) .. "," .. c(g.hot_y) .. ";9,1;]",
	})
end

--- Previous/next pager (shared §4.9 "Paged list"). Not observed in f03; the
--- strings are PROPOSED in the house style of shared §0.5.4.
function fs.pager(x, y, page, pages, prefix)
	prefix = prefix or "ah"
	local out = {}
	local disabled = pages <= 1
	out[#out + 1] = "button[" .. c(x) .. "," .. c(y) .. ";" .. c(G.pitch) .. "," ..
		c(G.pitch) .. ";" .. F(prefix .. "_prev") .. ";<]"
	out[#out + 1] = fs.tooltip(prefix .. "_prev", {
		S("Previous page"), S("Click to view the previous page") })
	out[#out + 1] = "button[" .. c(x + G.pitch) .. "," .. c(y) .. ";" .. c(G.pitch) ..
		"," .. c(G.pitch) .. ";" .. F(prefix .. "_next") .. ";>]"
	out[#out + 1] = fs.tooltip(prefix .. "_next", {
		S("Next page"), S("Click to view the next page") })
	if disabled then
		out[#out + 1] = "style[" .. F(prefix .. "_prev") .. "," .. F(prefix .. "_next") ..
			";textcolor=#AAAAAA]"
	end
	return table.concat(out)
end

----------------------------------------------------------------------
-- `Auction (Page 1)` — the board [F0107–F0129]
----------------------------------------------------------------------

--- @param q table `{page, pages, items, sort, total, query}`
function fs.board(q)
	q = q or {}
	local items = q.items or {}
	local page = q.page or 1
	local pages = q.pages or 1
	local out = {
		preamble(G.board.w, G.board.h),
		-- Title: OBSERVED `Auction (Page 1)` [F0108].
		label(G.x0, 0.375, S("Auction (Page @1)", page)),
		slot_bg(G.x0, G.board.grid_y, G.cols, G.rows),
	}

	-- Listings: 5 rows of 9 (page_size 45, f03 §4.2).
	for i, rec in ipairs(items) do
		if i > (G.rows - 1) * G.cols then break end
		local col = (i - 1) % G.cols + 1
		local row = math.floor((i - 1) / G.cols) + 1
		out[#out + 1] = fs.listing_cell(rec, sx(col), sy(row), "ah_l" .. tostring(rec.id))
	end

	-- Control row (the sixth row of the grid).
	local cy = sy(G.rows)
	-- Pager on the left, the three observed controls on the right [F0111,
	-- F0118, F0126].
	out[#out + 1] = fs.pager(sx(1), cy, page, pages, "ah")
	out[#out + 1] = fs.control("ah_search", sx(7), cy, "search", {
		S("Search"), S("Click to search"), C("#AAAAAA", fs.item("search")) })
	-- The hopper tooltip carries the option list, with the current sort
	-- highlighted [F0118–F0123].
	local sorts = smp_ah.listings and smp_ah.listings.SORTS or
		{ "lowest_price", "highest_price", "recently_listed" }
	local labels = (smp_ah.listings and smp_ah.listings.SORT_LABELS) or {}
	local filter_lines = { S("Filter"), S("Click to change") }
	for _, id in ipairs(sorts) do
		local text = S(labels[id] or id)
		if id == (q.sort or "lowest_price") then text = C(HIGHLIGHT, text) end
		filter_lines[#filter_lines + 1] = "\226\128\162 " .. text   -- U+2022 bullet
	end
	filter_lines[#filter_lines + 1] = C("#AAAAAA", fs.item("filter"))
	out[#out + 1] = fs.control("ah_filter", sx(8), cy, "filter", filter_lines)
	out[#out + 1] = fs.control("ah_your_items", sx(9), cy, "your_items", {
		S("Your Items"), S("Click to view"), C("#AAAAAA", fs.item("your_items")) })

	out[#out + 1] = fs.player_inventory(G.board)
	return table.concat(out)
end

----------------------------------------------------------------------
-- `Auction > Your Items` [F0131]
--
-- Note the separator: `>`, not the `->` that orders uses (shared §4.2).
----------------------------------------------------------------------

function fs.your_items(q)
	q = q or {}
	local items = q.items or {}
	local page = q.page or 1
	local pages = q.pages or 1
	local out = {
		preamble(G.board.w, G.board.h),
		label(G.x0, 0.375, S("Auction > Your Items")),
		slot_bg(G.x0, G.board.grid_y, G.cols, G.rows),
	}

	for i, rec in ipairs(items) do
		if i > (G.rows - 1) * G.cols then break end
		local col = (i - 1) % G.cols + 1
		local row = math.floor((i - 1) / G.cols) + 1
		local extra
		if rec.state == "expired" then
			-- PROPOSED (V-42: cancellation and reclaim were never observed).
			extra = { C("#FFFF55", S("Click to reclaim")) }
		elseif rec.state == "active" then
			extra = { C("#FFFF55", S("Click to cancel")) }
		else
			extra = { C("#AAAAAA", S("Sold")) }
		end
		out[#out + 1] = fs.listing_cell(rec, sx(col), sy(row), "ah_y" .. tostring(rec.id), extra)
	end

	local cy = sy(G.rows)
	-- The `List` pane is the first control [F0131].
	out[#out + 1] = fs.control("ah_list", sx(1), cy, "list", {
		S("List"), S("Click to sell an item"), C("#AAAAAA", fs.item("list")) })
	out[#out + 1] = fs.pager(sx(7), cy, page, pages, "ahy")
	-- Back to the board, using the observed `Auction` entry point [F0107].
	out[#out + 1] = fs.control("ah_board", sx(9), cy, "board", {
		S("Auction"), S("Buy and sell items"), C("#AAAAAA", fs.item("board")) })

	out[#out + 1] = fs.player_inventory(G.board)
	return table.concat(out)
end

----------------------------------------------------------------------
-- `Insert Item` [F0132, F0136]
--
-- A small container menu: a row of slots backed by a detached inventory, an
-- `Inventory` label, and the player's inventory. The sign control to the
-- right of the insert row is the step into `Edit Sign Message`; its label is
-- the observed title of the next screen (shared §4.6: the forward button is
-- named for the next screen).
----------------------------------------------------------------------

--- @param inv_name string detached inventory name
--- @param slots number size of the insert row
function fs.insert(inv_name, slots)
	slots = math.max(1, math.floor(tonumber(slots) or 5))
	local g = G.small
	local row_x = 2.875
	local out = {
		preamble(g.w, g.h),
		label(G.x0, 0.375, S("Insert Item")),
		slot_bg(row_x, g.row_y, slots, 1),
		"list[detached:" .. F(inv_name) .. ";insert;" .. c(row_x) .. "," .. c(g.row_y) ..
			";" .. slots .. ",1;]",
		fs.control("ah_price", sx(8), g.row_y, "search", {
			S("Edit Sign Message"), S("Click to type a price") }),
		label(G.x0, g.inv_label_y, S("Inventory")),
		slot_bg(G.x0, g.inv_y, G.cols, 3),
		"list[current_player;main;" .. c(G.x0) .. "," .. c(g.inv_y) .. ";9,3;9]",
		slot_bg(G.x0, g.hot_y, G.cols, 1),
		"list[current_player;main;" .. c(G.x0) .. "," .. c(g.hot_y) .. ";9,1;]",
		"listring[detached:" .. F(inv_name) .. ";insert]",
		"listring[current_player;main]",
	}
	return table.concat(out)
end

----------------------------------------------------------------------
-- Prompt menus
----------------------------------------------------------------------

local function prompt_preamble(g)
	-- Translucent dark, no inventory (shared §4.1, §4.9). `no_prepend[]`
	-- suppresses Mineclonia's light-grey container background.
	return "formspec_version[6]size[" .. c(g.w) .. "," .. c(g.h) .. "]" ..
		"no_prepend[]bgcolor[#000000C0;both]style_type[label;halign=center]"
end

--- `Search Auction` [F0114].
--
--   Search Auction
--         Search
--     [ diamon            ]
--     [ Cancel ]  [ Search ]
--         red        green
--
-- `Cancel` renders in red and `Search` in green — colour is observed and is
-- reproduced with `style[...;bgcolor=...]` (shared §4.6, §4.9).
function fs.search(query)
	local g = G.prompt
	return table.concat({
		prompt_preamble(g),
		area_label(0.5, 0.30, g.w - 1, 0.6, S("Search Auction")),
		-- The label above the field is `Search` [08-ui-strings §8.3].
		"field[1.5,1.45;5,0.8;ah_query;" .. F(S("Search")) .. ";" ..
			F(query or "") .. "]",
		"field_close_on_enter[ah_query;false]",
		"style[ah_cancel;bgcolor=#B03030;textcolor=#FFFFFF]",
		"style[ah_go;bgcolor=#3E8C3E;textcolor=#FFFFFF]",
		"button[1.5,2.55;2.4,0.8;ah_cancel;" .. F(S("Cancel")) .. "]",
		"button[4.1,2.55;2.4,0.8;ah_go;" .. F(S("Search")) .. "]",
		"set_focus[ah_query;true]",
	})
end

--- `Edit Sign Message` [F0139–F0141] — Minecraft's sign editor repurposed as
-- a price prompt. Luanti has no sign-edit screen; the substitution decided in
-- shared §3.3 keeps the strings and changes the widget: a prompt menu with a
-- `field[]` labelled `Type price` and a `Done` button.
function fs.price(default)
	local g = G.sign
	return table.concat({
		prompt_preamble(g),
		area_label(0.5, 0.25, g.w - 1, 0.6, S("Edit Sign Message")),
		"field[1.5,1.25;5,0.8;ah_price;" .. F(S("Type price")) .. ";" ..
			F(default or "") .. "]",
		"field_close_on_enter[ah_price;false]",
		"button[2.75,2.25;2.5,0.8;ah_done;" .. F(S("Done")) .. "]",
		"set_focus[ah_price;true]",
	})
end

----------------------------------------------------------------------
-- `Confirm Listing` [F0142] and `Auction > Confirm Purchase`
--
-- Container menus showing the stack about to change hands. The observed
-- tooltip states the outcome in the second person:
--
--   Dirt
--   You're going to sell this item for $1
--   minecraft:dirt
--   13 component(s)          <- DROP
--
-- The `Confirm` control is the lime pane of shared §4.3, with the amount in
-- parentheses on the affordance line (`Click to deliver items ($30K)`
-- [F0222] is the observed model).
----------------------------------------------------------------------

--- The single displayed stack, as a non-interactive image with a positional
--- tooltip, plus the Confirm/Cancel controls, and optionally a Match Lowest control.
local function confirm_grid(stack_name, tooltip_lines, confirm_name, confirm_lines,
		cancel_name, cancel_lines, match_lowest_name, match_lowest_lines)
	local g = G.small
	local y = g.row_y
	local out = {
		slot_bg(G.x0, y, G.cols, 1),
		-- Observed positions in F0142: a control in column 3 and the stack in
		-- column 5.
		"item_image[" .. c(sx(5)) .. "," .. c(y) .. ";" .. c(G.pitch) .. "," ..
			c(G.pitch) .. ";" .. F(stack_name or "") .. "]",
		"tooltip[" .. c(sx(5)) .. "," .. c(y) .. ";" .. c(G.pitch) .. "," ..
			c(G.pitch) .. ";" .. (function()
				local esc = {}
				for i, l in ipairs(tooltip_lines) do esc[i] = F(tostring(l)) end
				return table.concat(esc, "\\n")
			end)() .. "]",
		fs.control(confirm_name, sx(3), y, "confirm", confirm_lines),
		fs.control(cancel_name, sx(7), y, "cancel", cancel_lines),
		fs.player_inventory(g),
	}
	if match_lowest_name and match_lowest_lines then
		-- Place Match Lowest at column 1 (left of Confirm)
		out[#out + 1] = fs.control(match_lowest_name, sx(1), y, "match_lowest", match_lowest_lines)
	end
	return table.concat(out)
end

--- @param rec table listing-like record `{name, count, display}`
--- @param price number total asking price in cents
function fs.confirm_listing(rec, price)
	rec = rec or {}
	local g = G.small
	local lines = {
		(rec.display and rec.display.name) or rec.name or "",
	}
	for _, l in ipairs(ench_lines(rec)) do lines[#lines + 1] = l end
	-- OBSERVED second-person phrasing [F0142]; `$@1` carries the §0.6 tail.
	lines[#lines + 1] = S("You're going to sell this item for $@1", fs.money_tail(price))
	lines[#lines + 1] = C("#AAAAAA", rec.name or "")
	-- (`13 component(s)` dropped — shared §0.5.1.)
	return table.concat({
		preamble(g.w, g.h),
		label(G.x0, 0.375, S("Confirm Listing")),
		confirm_grid(rec.name, lines,
			"ah_confirm", { S("Confirm"), S("Click to list item (@1)", fs.money_inline(price)) },
			"ah_cancel", { S("Cancel"), S("Click to go back") },
			"ah_match_lowest", { S("Match lowest"), S("Click to match lowest price") }),
	})
end

--- PROPOSED screen: f03 §4.7 — "Clicking a listing opens a confirmation
--- (PROPOSED; never observed)". Title follows the auction tree's `>`
--- separator (shared §4.2). See f03 §10 V-40.
function fs.confirm_purchase(rec)
	rec = rec or {}
	local g = G.small
	local price = rec.price or 0
	return table.concat({
		preamble(g.w, g.h),
		label(G.x0, 0.375, S("Auction > Confirm Purchase")),
		confirm_grid(rec.name, fs.listing_tooltip_lines(rec), "ah_buy", {
			S("Confirm"), S("Click to buy item (@1)", fs.money_inline(price)) },
			"ah_cancel", { S("Cancel"), S("Click to go back") }),
	})
end

if core and type(core.log) == "function" then
	core.log("action", "[smp_ah] formspec.lua: menus ready (control items resolved at runtime)")
end
