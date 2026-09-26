-- FriedcakeSMP — smp_spawners / formspecs.lua
-- The spawner container menu. PROPOSED layout (f07 §3): no frames, so
-- the grammar follows shared/04-ui-kit.md container-menu rules — a
-- virtual storage grid over the player inventory, one page of 45 slots,
-- and a footer with paging, Sell all and Collect XP.
--
-- Every slot is one stored item type with its count; clicking a slot
-- takes one stack (up to 64 whole items), "Take all" takes as much as
-- fits (the formspec substitute for the clone's shift-click, f07
-- §10). Menu contents are re-read from node metadata on every render
-- and every action — the client is untrusted (shared §2.4, R4).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_spawners.S
local cfg = smp_spawners.cfg

smp_spawners.formspecs = {}

local FORMNAME = "smp_spawners:menu"
local PAGE_SIZE = 45
local MAX_PAGES = 5
local STACK_SIZE = 64

----------------------------------------------------------------------
-- Number rendering
----------------------------------------------------------------------

-- Plain integer with thousand separators: 12,480 (the observed
-- "Stored 12,480 / 368,640" style, f07 §3).
function smp_spawners.fmt_int(n)
	if type(n) ~= "number" then n = 0 end
	n = math.floor(n + 0.5)
	local s = tostring(n)
	local groups = {}
	while #s > 3 do
		table.insert(groups, 1, s:sub(-3))
		s = s:sub(1, -4)
	end
	table.insert(groups, 1, s)
	return table.concat(groups, ",")
end

local function esc(s)
	return core.formspec_escape and core.formspec_escape(s) or tostring(s)
end

local function item_desc(name)
	local reg = core.registered_items and core.registered_items[name]
	if reg and reg.description and reg.description ~= "" then
		return reg.description
	end
	return (name:gsub("^[a-z_]+:", ""))
end

-- Container geometry (mcl_chests proportions, as in smp_ah).
local G = {
	x0 = 0.375, pitch = 1.25, w = 11.75, h = 15.2,
	grid_y = 1.75, footer_y = 8.25,
	inv_label_y = 9.5, inv_y = 9.875, hot_y = 13.825,
}
smp_spawners.formspecs.G = G

local function slot_bg(x, y, w, h)
	if mcl_formspec and type(mcl_formspec.get_itemslot_bg_v4) == "function" then
		return mcl_formspec.get_itemslot_bg_v4(x, y, w, h)
	end
	local out = {}
	for j = 0, h - 1 do
		for i = 0, w - 1 do
			out[#out + 1] = string.format(
				"image[%s,%s;1.1,1.1;mcl_formspec_itemslot.png]",
				x + i * G.pitch - 0.05, y + j * G.pitch - 0.05)
		end
	end
	return table.concat(out)
end

-- Chat helper for messages that are either a single string or a list of
-- lines. f02's Sell-all receipt/refusal lines arrive as a list
-- (routing.lua relays them; f02 itself never shows them), our own
-- refusals arrive as a string.
local function send_lines(name, msg)
	if msg == nil then return end
	if type(msg) == "table" then
		for _, line in ipairs(msg) do
			core.chat_send_player(name, tostring(line))
		end
		return
	end
	core.chat_send_player(name, tostring(msg))
end

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------

-- Build the formspec for the spawner at pos, at the session's page.
-- Returns (spec, page) or (nil, reason).
function smp_spawners.formspecs.render(pos, session)
	local state = smp_spawners.read_state(pos)
	if not state then return nil, "gone" end

	local page = math.max(1, session.page or 1)

	-- Deterministic slot order.
	local names = {}
	for name in pairs(state.store) do
		if (state.store[name] or 0) >= 1 then
			names[#names + 1] = name
		end
	end
	table.sort(names)

	local max_pages = math.max(1, math.ceil(#names / PAGE_SIZE))
	if max_pages > MAX_PAGES then max_pages = MAX_PAGES end
	page = math.min(page, max_pages)

	local cap = smp_spawners.capacity(state.stack)
	local stored = smp_spawners.store_total(state.store)
	local rate = smp_spawners.kills_per_min(state.type_id, state.stack)

	-- Geometry follows Mineclonia's chest menu (mcl_chests): 11.75 wide,
	-- slots on a 1.25 pitch, 0.375 margins. Labels in formspec_version 6
	-- are positioned by their vertical centre.
	local X0, P = G.x0, G.pitch
	local function c(v) return string.format("%.6g", v) end
	local function sx(col) return X0 + col * P end

	local parts = {
		"formspec_version[6]",
		"size[" .. c(G.w) .. "," .. c(G.h) .. "]",
		-- Header: <Type> Spawner x<n> (f07 §4.6.3)
		"label[" .. c(X0) .. ",0.375;" .. esc(S("@1 Spawner x@2",
			state.def.display, state.stack)) .. "]",
		-- Stored versus capacity and stored XP (f07 §4.6.3)
		"label[" .. c(X0) .. ",0.85;" .. esc(S("Stored @1 / @2    XP @3 / @4",
			smp_spawners.fmt_int(stored), smp_spawners.fmt_int(cap),
			smp_spawners.fmt_int(state.xp),
			smp_spawners.fmt_int(smp_spawners.xp_cap(state.stack)))) .. "]",
		-- Rate per minute
		"label[" .. c(X0) .. ",1.3;" .. esc(S("Rate: @1 kills/min",
			string.format("%.1f", rate))) .. "]",
	}

	if stored >= cap and stored > 0 then
		parts[#parts + 1] = "label[" .. c(sx(6)) .. ",0.85;" ..
			esc(S("Storage full")) .. "]"
	end

	-- 5 x 9 virtual storage grid over slot backgrounds.
	parts[#parts + 1] = slot_bg(X0, G.grid_y, 9, 5)
	for row = 0, 4 do
		for col = 0, 8 do
			local slot = row * 9 + col
			local idx = (page - 1) * PAGE_SIZE + slot + 1
			local x, y = sx(col), G.grid_y + row * P
			local name = names[idx]
			if name then
				local count = math.floor(state.store[name] + 0.5 - 1e-9)
				local field = "slot" .. idx
				-- Clickable item image: field name slot<idx>; the count
				-- sits in the corner like a stack count (integer
				-- boundary).
				parts[#parts + 1] = string.format(
					"item_image_button[%s,%s;%s,%s;%s;%s;]",
					c(x), c(y), c(P), c(P), esc(name), field)
				parts[#parts + 1] = string.format("label[%s,%s;%s]",
					c(x + 0.1), c(y + 1.0),
					esc(smp_spawners.fmt_int(count)))
				parts[#parts + 1] = "tooltip[" .. field .. ";" ..
					esc(item_desc(name)) .. "\n" ..
					esc(S("Stored: @1", smp_spawners.fmt_int(count))) .. "\n" ..
					esc(S("Click to take one stack")) .. "]"
			end
		end
	end

	-- Footer: paging and actions, one row under the grid. Esc sends
	-- `quit`, so no separate Close button is drawn.
	local fy = G.footer_y
	parts[#parts + 1] = string.format("button[%s,%s;0.8,0.8;prev;<]",
		c(X0), c(fy))
	parts[#parts + 1] = string.format("label[%s,%s;%s]",
		c(X0 + 0.95), c(fy + 0.4), esc(S("Page @1 of @2", page, max_pages)))
	parts[#parts + 1] = string.format("button[%s,%s;0.8,0.8;next;>]",
		c(3.0), c(fy))
	parts[#parts + 1] = string.format("button[%s,%s;2.2,0.8;take_all;%s]",
		c(4.35), c(fy), esc(S("Take all")))
	parts[#parts + 1] = string.format("button[%s,%s;2.2,0.8;sell_all;%s]",
		c(6.7), c(fy), esc(S("Sell all")))
	parts[#parts + 1] = string.format("button[%s,%s;2.325,0.8;xp;%s]",
		c(9.05), c(fy), esc(S("Collect XP")))

	-- Player inventory under the storage grid, per the shared container
	-- grammar (shared/04:22 — the menu shows the player inventory under
	-- an `Inventory` label). These are real, functional list[]s; the
	-- storage grid above stays a set of take-request buttons (f07 §8).
	-- Slot backgrounds are drawn first so the items render on top.
	parts[#parts + 1] = "label[" .. c(X0) .. "," .. c(G.inv_label_y) .. ";" ..
		esc(S("Inventory")) .. "]"
	parts[#parts + 1] = slot_bg(X0, G.inv_y, 9, 3)
	parts[#parts + 1] = "list[current_player;main;" .. c(X0) .. "," ..
		c(G.inv_y) .. ";9,3;9]"
	parts[#parts + 1] = slot_bg(X0, G.hot_y, 9, 1)
	parts[#parts + 1] = "list[current_player;main;" .. c(X0) .. "," ..
		c(G.hot_y) .. ";9,1;]"

	return table.concat(parts, "\n"), page
end

----------------------------------------------------------------------
-- Open
----------------------------------------------------------------------

function smp_spawners.formspecs.open(pos, player, state)
	local name = player:get_player_name()
	local session = smp_core.open_session(name, FORMNAME, {
		pos = { x = pos.x, y = pos.y, z = pos.z },
		opened_type = state.type_id,
		page = 1,
	})
	local spec, page = smp_spawners.formspecs.render(session.pos, session)
	if not spec then
		smp_core.close_session(name, FORMNAME)
		core.chat_send_player(name, S("This spawner has changed"))
		return
	end
	session.page = page
	core.show_formspec(name, FORMNAME, spec)
end

----------------------------------------------------------------------
-- Field handler
--
-- Every action re-validates the node (exists, same type, positive
-- stack, within 8 nodes) before mutating (f07 §4.8, R7). On failure
-- the menu closes with a notice; nothing is mutated (T10).
----------------------------------------------------------------------

function smp_spawners.formspecs.register_handler()
	core.register_on_player_receive_fields(function(player, formname, fields)
		if formname ~= FORMNAME then return end
		local name = player:get_player_name()
		local session = smp_core.get_session(name, FORMNAME)
		if not session then
			core.close_formspec(name, FORMNAME)
			return
		end
		local pos = session.pos

		if fields.quit then
			smp_core.close_session(name, FORMNAME)
			core.close_formspec(name, FORMNAME)
			return
		end

		-- Re-validate on EVERY action (R7, T10).
		local state = smp_spawners.revalidate(pos, session.opened_type,
			player)
		if not state then
			smp_core.close_session(name, FORMNAME)
			core.close_formspec(name, FORMNAME)
			core.chat_send_player(name,
				S("This spawner has been removed"))
			return
		end

		-- Paging.
		local page = session.page or 1
		if fields.prev then page = page - 1 end
		if fields.next then page = page + 1 end
		page = math.max(1, page)

		-- Slot clicks (fields.slotN, N = global slot index).
		for field, _ in pairs(fields) do
			local idx = field:match("^slot(%d+)$")
			if idx then
				idx = tonumber(idx)
				if idx >= 1 and idx <= 10000 then
					-- Resolve the name from the LIVE state; the client
					-- only supplies the slot index.
					local names = {}
					for n in pairs(state.store) do
						if (state.store[n] or 0) >= 1 then
							names[#names + 1] = n
						end
					end
					table.sort(names)
					local item_name = names[idx]
					if item_name then
						local taken = smp_spawners.take(pos, player,
							state.type_id, item_name, STACK_SIZE)
						if taken > 0 then
							core.chat_send_player(name,
								S("You took @1", smp_core.fmt_qty(taken)))
						end
					end
				end
			end
		end

		-- Take all (shift-click substitute, f07 §10).
		if fields.take_all then
			local total = 0
			for item_name, count in pairs(state.store) do
				if count >= 1 then
					local taken = smp_spawners.take(pos, player,
						state.type_id, item_name, math.huge)
					total = total + taken
				end
			end
			if total > 0 then
				core.chat_send_player(name,
					S("You took @1", smp_core.fmt_qty(total)))
			end
		end

		-- Collect XP (f07 §4.4).
		if fields.xp then
			local xp = smp_spawners.collect_xp(pos, player, state.type_id)
			if xp and xp > 0 then
				core.chat_send_player(name,
					S("You collected @1 XP",
						smp_spawners.fmt_int(xp)))
			end
		end

		-- Sell all: routes into f02 (routing.lua). Closes the menu on
		-- success; the store is emptied by the sale. The message may be
		-- f02's line list (relayed, never shown by f02 itself).
		if fields.sell_all then
			local ok, msg = smp_spawners.routing.sell_all(pos, player,
				state.type_id)
			if ok then
				smp_core.close_session(name, FORMNAME)
				core.close_formspec(name, FORMNAME)
				send_lines(name, msg)
				return
			else
				send_lines(name, msg)
			end
		end

		-- Re-render (contents are always read fresh).
		local spec, npage = smp_spawners.formspecs.render(pos, session)
		if not spec then
			smp_core.close_session(name, FORMNAME)
			core.close_formspec(name, FORMNAME)
			core.chat_send_player(name,
				S("This spawner has been removed"))
			return
		end
		session.page = npage
		core.show_formspec(name, FORMNAME, spec)
	end)
end

-- Close the session when the player leaves (shared §2.6 R6).
function smp_spawners.formspecs.register_leave()
	core.register_on_leaveplayer(function(player)
		smp_core.close_session(player:get_player_name(), FORMNAME)
	end)
end

smp_spawners.formspecs.FORMNAME = FORMNAME
smp_spawners.formspecs.PAGE_SIZE = PAGE_SIZE
