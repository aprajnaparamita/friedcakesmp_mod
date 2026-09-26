-- FriedcakeSMP — smp_sell/menu.lua
--
-- The observed `Sell` container menu (f02 §3.1, frames F0093/F0094/F0096).
--
-- It is a CONTAINER MENU in the sense of shared/04-ui-kit.md §4.1: a slot
-- grid over a detached inventory, the player's inventory underneath an
-- `Inventory` label, and the control vocabulary of §4.3 — an item-as-button.
-- The green square in the bottom-right corner of the sell grid [F0094] is the
-- same lime-pane `Confirm` idiom the orders delivery flow uses [F0222]; it is
-- rendered as `item_image_button[]` with the §4.3 tooltip lines.
--
-- Geometry follows Mineclonia's own chest formspecs
-- (mods/ITEMS/mcl_chests/init.lua): origin 0.375/0.75, slot pitch 1.25,
-- `Inventory` label 0.45 below the grid, player grid 0.4 below the label,
-- hotbar 0.45 below that, 0.375 bottom margin. The sell grid is FIVE rows
-- (v0.1 §4.3 "a five-row container"), so 9x5 cells: 44 drop slots and the
-- confirm pane in the 45th, bottom-right cell — exactly where [F0094] shows
-- the green square.
--
-- Item loss is the highest risk in this mod (f02 §8), so three independent
-- nets exist:
--   1. every close path (confirm, quit, /sell again, death) returns contents;
--   2. `core.register_on_leaveplayer` returns contents BEFORE the player is
--      saved (shared §2.6 R6, f02 T7);
--   3. the container is mirrored into smp_sell's mod storage on every change,
--      so a server crash between (1) and (2) is recovered on the next join
--      (shared §2.6 R12 spirit, cross-cutting test X1).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local deps = ...   -- { items, prices, history, receipt, orders, engine, cfg, S, sell_cooldown_active, set_sell_cooldown }

local items  = deps.items
local engine = deps.engine
local cfg    = deps.cfg
local S      = deps.S
local sell_cooldown_active = deps.sell_cooldown_active
local set_sell_cooldown = deps.set_sell_cooldown

local M = {}

local FORMNAME = "smp_sell:sell"
M.FORMNAME = FORMNAME

local GRID_W, GRID_H = 9, 5
local CELLS = GRID_W * GRID_H          -- 45
local X0, Y0, PITCH = 0.375, 0.75, 1.25
local INV_LABEL_Y = Y0 + GRID_H * PITCH - (PITCH - 1) + 0.45   -- 7.2
local INV_Y = INV_LABEL_Y + 0.4                                -- 7.6
local HOTBAR_Y = INV_Y + 3 * PITCH + 0.2                       -- 11.55
local SIZE_H = HOTBAR_Y + 1 + 0.375                            -- 12.925

local storage = core.get_mod_storage()
local BOX_PREFIX = "sellbox:"

-- Detached-inventory callbacks per player, kept so the acceptance tests (and
-- any future integration) can drive the container the way the engine does.
local callbacks_by_player = {}

-- Mineclonia itemstrings for the lime pane, best first. Verified against
-- ~/dev/mineclonia-git: mcl_panes registers "mcl_panes:pane_<colour>_flat"
-- and "mcl_panes:pane_<colour>" for every mcl_dyes colour, and "lime" is a
-- mcl_dyes colour. The `mcl_core:glass_pane_lime` name in shared/04-ui-kit.md
-- §4.3 does NOT exist in the game; it is kept in the list only so the
-- proposed correction is obvious, and the runtime check below makes the
-- choice safe either way (f02 §11).
local PANE_CANDIDATES = {
	"mcl_panes:pane_lime_flat",
	"mcl_panes:pane_lime",
	"mcl_core:glass_pane_lime",
	"mcl_core:glass_lime",
	"mcl_dyes:green",
	"mcl_core:glass",
}

local function registered(name)
	if type(name) ~= "string" then return false end
	if core.registered_items and core.registered_items[name] then return true end
	if core.registered_nodes and core.registered_nodes[name] then return true end
	if core.registered_craftitems and core.registered_craftitems[name] then return true end
	return false
end

local confirm_item_cache = nil
function M.confirm_item()
	if confirm_item_cache and registered(confirm_item_cache) then
		return confirm_item_cache
	end
	for _, name in ipairs(PANE_CANDIDATES) do
		if registered(name) then
			confirm_item_cache = name
			return name
		end
	end
	confirm_item_cache = PANE_CANDIDATES[#PANE_CANDIDATES]
	return confirm_item_cache
end

----------------------------------------------------------------------
-- Detached inventory
----------------------------------------------------------------------

function M.inv_name(player_name)
	return "smp_sell_" .. player_name
end

function M.get_inv(player_name)
	return core.get_inventory({ type = "detached", name = M.inv_name(player_name) })
end

-- Drop slots for the current mode: in `button` mode the bottom-right cell
-- belongs to the confirm pane, in `close` mode it is a normal slot.
function M.slot_count()
	return (cfg.mode == "button") and (CELLS - 1) or CELLS
end

local function is_owner(player, owner_name)
	-- R5: only the owning player may move items in or out. The detached
	-- inventory is scoped to one player when it is created, but every
	-- callback re-validates anyway (shared §2.6 R4).
	if not player or not owner_name then return false end
	local name = player.get_player_name and player:get_player_name()
	if name ~= owner_name then return false end
	local session = smp_core.get_session(name, FORMNAME)
	return session ~= nil and session.inv == M.inv_name(name)
end

-- Snapshot the container as an array of ItemStack copies (what the engine
-- is allowed to keep references to).
function M.snapshot(player_name)
	local out = {}
	local ok, inv = pcall(M.get_inv, player_name)
	if not ok or not inv then return out end
	local oksize, size = pcall(inv.get_size, inv, "main")
	size = (oksize and tonumber(size)) or 0
	for i = 1, size do
		local oks, s = pcall(inv.get_stack, inv, "main", i)
		if oks and s and not s:is_empty() then out[#out + 1] = ItemStack(s) end
	end
	return out
end

function M.clear(player_name)
	local ok, inv = pcall(M.get_inv, player_name)
	if not ok or not inv then
		M.unpersist(player_name)
		return
	end
	local oksize, size = pcall(inv.get_size, inv, "main")
	size = (oksize and tonumber(size)) or 0
	local empty = {}
	for i = 1, size do empty[i] = ItemStack("") end
	pcall(inv.set_list, inv, "main", empty)
	M.unpersist(player_name)
end

----------------------------------------------------------------------
-- Crash-safe mirror of the container
----------------------------------------------------------------------

function M.persist(player_name, inv)
	if not inv then
		local ok, got = pcall(M.get_inv, player_name)
		if not ok then return end
		inv = got
	end
	if not inv then return end
	local oksize, size = pcall(inv.get_size, inv, "main")
	size = (oksize and tonumber(size)) or 0
	if size == 0 then return end
	local list = {}
	local any = false
	for i = 1, size do
		local oks, s = pcall(inv.get_stack, inv, "main", i)
		if oks and s and not s:is_empty() then
			list[i] = s:to_string()
			any = true
		else
			list[i] = ""
		end
	end
	if not any then
		M.unpersist(player_name)
		return
	end
	storage:set_string(BOX_PREFIX .. player_name, core.write_json(list))
end

function M.unpersist(player_name)
	storage:set_string(BOX_PREFIX .. player_name, "")
end

-- Called on join. A leftover mirror means the server died (or the leave
-- handler could not run) with items in the container; hand them back.
function M.recover(player, player_name)
	local raw = storage:get_string(BOX_PREFIX .. player_name)
	if raw == nil or raw == "" then return false end
	storage:set_string(BOX_PREFIX .. player_name, "")

	local ok, list = pcall(core.parse_json, raw)
	if not ok or type(list) ~= "table" then
		core.log("error", "[smp_sell] corrupt sell container mirror for " .. player_name)
		return false
	end

	local stacks = {}
	for _, v in ipairs(list) do
		if type(v) == "string" and v ~= "" then
			local ok2, s = pcall(ItemStack, v)
			if ok2 and s and not s:is_empty() then stacks[#stacks + 1] = s end
		end
	end
	if #stacks == 0 then return false end

	core.log("warning", "[smp_sell] recovering " .. #stacks
		.. " item stack(s) left in the sell container for " .. player_name)
	M.give_back(player, stacks)
	core.chat_send_player(player_name,
		S("Items left in the sell menu were returned to you"))
	return true
end

----------------------------------------------------------------------
-- Returning items (f02 §4 edge cases, T8)
----------------------------------------------------------------------

-- Give stacks back to the player's inventory; anything that does not fit is
-- dropped at the player's feet so nothing ever vanishes (PROPOSED).
function M.give_back(player, stacks)
	if not stacks or #stacks == 0 then return {} end
	local dropped = {}
	local inv = player and player.get_inventory and player:get_inventory()
	for _, s in ipairs(stacks) do
		if s and not s:is_empty() then
			local left = s
			if inv then
				local ok, res = pcall(inv.add_item, inv, "main", s)
				if ok then left = res or ItemStack("") end
			end
			if left and not left:is_empty() then
				local pos = player and player.get_pos and player:get_pos()
				local ok = false
				if pos and core.item_drop then
					ok = pcall(core.item_drop, left, player, pos)
				end
				if not ok and core.add_item and pos then
					pcall(core.add_item, pos, left)
				end
				dropped[#dropped + 1] = left
			end
		end
	end
	return dropped
end

----------------------------------------------------------------------
-- Formspec
----------------------------------------------------------------------

local function colorize(text)
	local colour = (type(mcl_formspec) == "table" and mcl_formspec.label_color) or "#313131"
	if core.colorize then return core.colorize(colour, text) end
	return text
end

local function label(text)
	return core.formspec_escape(colorize(text))
end

-- Slot backgrounds for the sell grid, skipping the confirm cell when the
-- confirm pane owns it.
local function grid_backgrounds(with_confirm_cell)
	local F = mcl_formspec and mcl_formspec.get_itemslot_bg_v4
	local out = {}
	if not F then return "" end
	out[#out + 1] = F(X0, Y0, GRID_W, GRID_H - 1)                  -- rows 1-4
	out[#out + 1] = F(X0, Y0 + (GRID_H - 1) * PITCH,
		GRID_W - (with_confirm_cell and 1 or 0), 1)                -- row 5
	return table.concat(out)
end

function M.formspec(player_name, session)
	local with_confirm = (cfg.mode == "button")
	local parts = {
		"formspec_version[6]",
		string.format("size[11.75,%.3f]", SIZE_H),

		-- Title: `Sell` (shared/08-ui-strings.md §8.1, container menu).
		"label[" .. X0 .. ",0.375;" .. label(S("Sell")) .. "]",

		grid_backgrounds(with_confirm),
		"list[detached:" .. M.inv_name(player_name) .. ";main;"
			.. X0 .. "," .. Y0 .. ";" .. GRID_W .. "," .. GRID_H .. ";]",
	}

	if with_confirm then
		-- The confirm pane sits in the bottom-right cell of the sell grid
		-- [F0094], rendered as an item-as-button (shared §4.3).
		local cx = X0 + (GRID_W - 1) * PITCH
		local cy = Y0 + (GRID_H - 1) * PITCH
		parts[#parts + 1] = string.format(
			"item_image_button[%g,%g;1,1;%s;confirm;]", cx, cy, M.confirm_item())
		-- §4.3 tooltip lines. The parenthesised amount the delivery confirm
		-- carries [F0222] is deliberately omitted: it would have to change
		-- with every drag, and redrawing the formspec mid-drag risks the
		-- client losing the stack it is holding. f02 §10 V-54/V-92.
		parts[#parts + 1] = "tooltip[confirm;"
			.. core.formspec_escape(S("Confirm")) .. "\n"
			.. core.formspec_escape(S("Click to sell items")) .. "]"
	end

	-- Player inventory under an `Inventory` label (shared §8.1).
	parts[#parts + 1] = "label[" .. X0 .. "," .. INV_LABEL_Y .. ";"
		.. label(S("Inventory")) .. "]"
	if mcl_formspec and mcl_formspec.get_itemslot_bg_v4 then
		parts[#parts + 1] = mcl_formspec.get_itemslot_bg_v4(X0, INV_Y, 9, 3)
		parts[#parts + 1] = mcl_formspec.get_itemslot_bg_v4(X0, HOTBAR_Y, 9, 1)
	end
	parts[#parts + 1] = "list[current_player;main;" .. X0 .. "," .. INV_Y .. ";9,3;9]"
	parts[#parts + 1] = "list[current_player;main;" .. X0 .. "," .. HOTBAR_Y .. ";9,1;]"

	-- Shift-click moves between the sell grid and the inventory, like a chest.
	parts[#parts + 1] = "listring[detached:" .. M.inv_name(player_name) .. ";main]"
	parts[#parts + 1] = "listring[current_player;main]"

	return table.concat(parts)
end

----------------------------------------------------------------------
-- Open / confirm / close
----------------------------------------------------------------------

local function make_callbacks(player_name)
	local callbacks = {
		allow_put = function(inv, listname, index, stack, player)
			if listname ~= "main" then return 0 end
			if not is_owner(player, player_name) then return 0 end
			if index < 1 or index > M.slot_count() then return 0 end
			-- SE-4 (S02/SE-4): refuse puts while combat-tagged — a tagged
			-- player could otherwise park valuables here and retrieve them
			-- after the combat-log drop (S07/CB-1). Soft-check so the mod
			-- works without smp_combat.
			if smp_combat and smp_combat.is_tagged and smp_combat.is_tagged(player_name) then
				return 0
			end
			-- Any item may be dropped in; eligibility is decided on confirm
			-- and ineligible items are returned (f02 §4.1, T3, V-57).
			return stack:get_count()
		end,
		allow_take = function(inv, listname, index, stack, player)
			if listname ~= "main" then return 0 end
			if not is_owner(player, player_name) then return 0 end
			return stack:get_count()
		end,
		allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
			if from_list ~= "main" or to_list ~= "main" then return 0 end
			if not is_owner(player, player_name) then return 0 end
			if to_index < 1 or to_index > M.slot_count() then return 0 end
			return count
		end,
		on_put = function(inv) M.persist(player_name, inv) end,
		on_take = function(inv) M.persist(player_name, inv) end,
		on_move = function(inv) M.persist(player_name, inv) end,
	}
	callbacks_by_player[player_name] = callbacks
	return callbacks
end

-- Exposed for the acceptance tests (and for any future mod that needs to
-- drive the container the way the engine does).
function M.callbacks_for(player_name)
	return callbacks_by_player[player_name]
end

-- Open the `Sell` container for a player. Returns true on success.
function M.open(player)
	if not player then return false end
	local name = player:get_player_name()

	-- A container that is somehow still open (e.g. `/sell` twice) keeps its
	-- contents: never recreate a detached inventory that may hold items,
	-- because core.create_detached_inventory CLEARS an existing one.
	local session = smp_core.get_session(name, FORMNAME)
	if session and session.inv then
		core.show_formspec(name, FORMNAME, M.formspec(name, session))
		return true
	end

	local leftover = M.recover(player, name)   -- crash leftovers first
	local inv_name = M.inv_name(name)
	local inv = core.create_detached_inventory(inv_name, make_callbacks(name), name)
	if not inv then
		core.log("error", "[smp_sell] cannot create the detached inventory for " .. name)
		return false
	end
	inv:set_size("main", M.slot_count())

	session = smp_core.open_session(name, FORMNAME, {
		inv = inv_name,
		size = M.slot_count(),
		mode = cfg.mode,
		opened = core.get_gametime and core.get_gametime() or os.time(),
	})
	if not session then return false end
	session.inv = inv_name
	session.size = M.slot_count()

	core.show_formspec(name, FORMNAME, M.formspec(name, session))
	return true, leftover
end

-- Confirm: sell the container contents, then close (f02 §4.3, T2).
function M.confirm(player)
	local name = player:get_player_name()
	local session = smp_core.get_session(name, FORMNAME)
	if not session then return false end                 -- R4: no session

	-- SE-5: rate-limit container confirm to ~1/s
	if smp_sell._reset_sell_cooldown then
		if sell_cooldown_active(name) then
			core.chat_send_player(name, S("Please wait before selling again"))
			return false
		end
	end

	local stacks = M.snapshot(name)

	if #stacks == 0 then
		M.close(player, "empty")
		core.chat_send_player(name, S("No items to sell"))
		return true
	end

	-- The container is cleared by `consume`, which engine.transact calls only
	-- AFTER validation has passed — a refused sale (for example a player at
	-- the balance cap) must leave the container exactly as it was.
	local ok, messages = engine.transact(name, stacks, "container", {
		consume = function() M.clear(name) end,
		give_back = function(list) M.give_back(player, list) end,
	})

	M.close(player, "confirm")
	if ok then set_sell_cooldown(name) end
	for _, line in ipairs(messages or {}) do
		core.chat_send_player(name, line)
	end
	return ok
end

-- Close and return everything (f02 T6). In `close` mode the contents are
-- sold on close instead [C1].
function M.close(player, reason)
	if not player then return end
	local name = player:get_player_name()
	local session = smp_core.get_session(name, FORMNAME)

	if session and reason == "quit" and session.mode == "close" then
		-- Clone behaviour [C1]: closing sells. Kept behind `sell.mode`.
		M.confirm(player)
		return
	end

	if session then
		local stacks = M.snapshot(name)
		M.clear(name)
		if #stacks > 0 then
			M.give_back(player, stacks)
		end
		smp_core.close_session(name, FORMNAME)
	end
	if core.close_formspec then
		pcall(core.close_formspec, name, FORMNAME)
	end
	local inv_name = M.inv_name(name)
	if core.remove_detached_inventory then
		pcall(core.remove_detached_inventory, inv_name)
	end
	callbacks_by_player[name] = nil
	M.unpersist(name)
end

function M.is_open(player_name)
	return smp_core.get_session(player_name, FORMNAME) ~= nil
end

-- Drop everything back without waiting for the formspec to close. Used by
-- the leave, death and shutdown paths (R6).
function M.return_contents(player, player_name)
	local stacks = {}
	local ok, inv = pcall(M.get_inv, player_name)
	if ok and inv then
		local oksize, size = pcall(inv.get_size, inv, "main")
		size = (oksize and tonumber(size)) or 0
		for i = 1, size do
			local oks, s = pcall(inv.get_stack, inv, "main", i)
			if oks and s and not s:is_empty() then stacks[#stacks + 1] = ItemStack(s) end
		end
		if #stacks > 0 then
			local empty = {}
			for i = 1, size do empty[i] = ItemStack("") end
			pcall(inv.set_list, inv, "main", empty)
		end
	end
	if #stacks > 0 and player then
		M.give_back(player, stacks)
	end
	smp_core.close_session(player_name, FORMNAME)
	callbacks_by_player[player_name] = nil
	M.unpersist(player_name)
	return #stacks
end

return M
