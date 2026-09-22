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

	local parts = {
		"formspec_version[6]",
		"size[12,8.4]",
		-- Header: <Type> Spawner ×n (f07 §4.6.3)
		"label[0,0," .. esc(S("@1 Spawner x@2", state.def.display,
			state.stack)) .. "]",
		-- Stored versus capacity and stored XP (f07 §4.6.3)
		"label[0,0.5," .. esc(S("Stored @1 / @2    XP @3 / @4",
			smp_spawners.fmt_int(stored), smp_spawners.fmt_int(cap),
			smp_spawners.fmt_int(state.xp),
			smp_spawners.fmt_int(smp_spawners.xp_cap(state.stack)))) .. "]",
		-- Rate per minute
		"label[0,1," .. esc(S("Rate: @1 kills/min", string.format("%.1f",
			rate))) .. "]",
	}

	if stored >= cap and stored > 0 then
		parts[#parts + 1] =
			"label[6,0.5," .. esc(S("Storage full")) .. "]"
	end

	-- 5 x 9 virtual storage grid.
	local grid_y = 1.7
	for row = 0, 4 do
		for col = 0, 8 do
			local slot = row * 9 + col
			local idx = (page - 1) * PAGE_SIZE + slot + 1
			local x = col * 1.0
			local y = grid_y + row * 0.9
			local name = names[idx]
			if name then
				local count = state.store[name]
				-- Clickable item image: field name slot<idx>, the
				-- label carries the whole count (integer boundary).
				parts[#parts + 1] = string.format(
					"item_image_button[%s,%s,1,1,%s,slot%d,%s]",
					tostring(x), tostring(y), esc(name), idx,
					esc(smp_spawners.fmt_int(math.floor(count + 0.5 - 1e-9))))
				parts[#parts + 1] = string.format(
					"tooltip[%s,%s,%s]",
					tostring(x), tostring(y),
					esc(item_desc(name) .. " — Click to take one stack"))
			end
		end
	end

	-- Footer: paging, actions.
	local fy = grid_y + 5 * 0.9 + 0.1
	parts[#parts + 1] =
		string.format("button[0,%s,1.5,1,prev,%s]",
			tostring(fy), esc(S("< Prev")))
	parts[#parts + 1] =
		string.format("label[4,%s,%s]",
			tostring(fy), esc(S("Page @1 of @2", page, max_pages)))
	parts[#parts + 1] =
		string.format("button[6.5,%s,1.5,1,next,%s]",
			tostring(fy), esc(S("Next >")))
	parts[#parts + 1] =
		string.format("button[8.5,%s,2,1,sell_all,%s]",
			tostring(fy), esc(S("Sell all")))
	parts[#parts + 1] =
		string.format("button[8.5,%s,2,1,xp,%s]",
			tostring(fy + 1.1), esc(S("Collect XP")))
	parts[#parts + 1] =
		string.format("button[0,%s,2,1,take_all,%s]",
			tostring(fy + 1.1), esc(S("Take all")))
	parts[#parts + 1] =
		string.format("button[4,%s,2,1,quit,%s]",
			tostring(fy + 1.1), esc(S("Close")))

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
		-- success; the store is emptied by the sale.
		if fields.sell_all then
			local ok, msg = smp_spawners.routing.sell_all(pos, player,
				state.type_id)
			if ok then
				smp_core.close_session(name, FORMNAME)
				core.close_formspec(name, FORMNAME)
				core.chat_send_player(name, msg)
				return
			else
				core.chat_send_player(name, msg)
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
