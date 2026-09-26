-- FriedcakeSMP — smp_quickbuy
--
-- /shop Quick Buy. Implements spec/features/f05-quickbuy.md.
--
--   /shop               open the Quick Buy container menu
--   /smp test smp_quickbuy   run the in-game acceptance tests (smp_admin)
--
-- Every visual element is PROPOSED — no frame shows /shop (f05 §1).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_quickbuy = {}

----------------------------------------------------------------------
-- Configuration (spec §7)
----------------------------------------------------------------------

smp_quickbuy.cfg = {
	price_guard = tonumber(core.settings:get("quickbuy.price_guard")) or 3.0,
	max_entries = tonumber(core.settings:get("quickbuy.max_entries")) or 45,
	page_size   = tonumber(core.settings:get("quickbuy.page_size"))   or 45,
}

local modpath = core.get_modpath("smp_quickbuy")
dofile(modpath .. "/bridges.lua")
dofile(modpath .. "/entries.lua")
dofile(modpath .. "/price.lua")
dofile(modpath .. "/buy.lua")
dofile(modpath .. "/formspec.lua")

local F = smp_quickbuy.formspec
local MENU = F.MENU   -- one formname for the whole menu (see formspec.lua)

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function chat(player, msg)
	core.chat_send_player(player:get_player_name(), msg)
end

local function item_label(key)
	local def = core.registered_items and core.registered_items[key]
	if def and type(def.description) == "string" and def.description ~= "" then
		return def.description
	end
	return key
end

-- Parse a quantity input. Plain integers, plus the k/m/b suffixes accepted
-- everywhere in FriedcakeSMP (shared §0.6). Rejects non-integers, negatives
-- and junk. Returns an integer or nil.
local function parse_qty(text)
	if type(text) ~= "string" then return nil end
	text = text:match("^%s*(.-)%s*$") or ""
	if text == "" then return nil end
	local body, mult = text, 1
	local last = text:sub(-1)
	if last:match("[kKmMbB]") then
		body = text:sub(1, -2)
		local lc = last:lower()
		if     lc == "k" then mult = 1000
		elseif lc == "m" then mult = 1000000
		elseif lc == "b" then mult = 1000000000 end
	end
	local n = tonumber(body)
	if n == nil or n ~= n or n == math.huge or n < 1 then return nil end
	n = n * mult
	if n ~= math.floor(n) then return nil end
	return n
end

----------------------------------------------------------------------
-- Menu state
--
-- Every screen (main / entries / add / warn) is shown under ONE formname.
-- Luanti drops any field submission whose formname differs from the last
-- formname the server sent ("possible exploitation attempt"), so switching
-- formnames mid-menu caused rapid clicks — and even a single click followed
-- by a re-open — to be silently discarded. A single formname never changes,
-- so the engine check always passes; the current screen is tracked here in
-- the session instead.
----------------------------------------------------------------------

local function session_for(name, screen)
	return smp_core.open_session(name, MENU, { screen = screen })
end

local function show(player, session)
	core.show_formspec(player:get_player_name(), MENU, F.render(player, session))
end

local function goto_main(player)
	local name = player:get_player_name()
	local s = session_for(name, "main")
	s.screen = "main"
	s.prices = {}   -- force a fresh live price lookup on this redraw
	show(player, s)
end

local function goto_entries(player)
	local name = player:get_player_name()
	local s = session_for(name, "entries")
	s.screen = "entries"
	show(player, s)
end

local function goto_warn(player, entry_index, shown_price, cost)
	local name = player:get_player_name()
	local s = session_for(name, "warn")
	s.screen = "warn"
	s.entry_index = entry_index
	s.shown_price = shown_price
	s.cost = cost
	show(player, s)
end

-- Add (or replace) one entry, with capacity feedback. Returns true on success.
local function commit_entry(player, key, ench, qty, edit_index)
	local name = player:get_player_name()
	if edit_index then
		local cur = smp_quickbuy.entries.get(name, edit_index)
		if not cur then return false end
		smp_quickbuy.entries.set(name, edit_index,
			{ key = cur.key, ench = cur.ench, qty = qty })
		return true
	end
	local ok, err = smp_quickbuy.entries.add(name,
		{ key = key, ench = ench, qty = qty })
	if not ok and err == "capacity" then
		chat(player, S("You reached the Quick Buy entry limit."))
		return false
	end
	if ok then chat(player, S("Added @1 to Quick Buy.", item_label(key))) end
	return ok and true or false
end

-- Open the "add current item" flow. One item in hand → add it directly and
-- return to the main panel (no prompt). More than one → ask for a quantity,
-- capped at the number actually held.
local function goto_add(player)
	local name = player:get_player_name()
	local held = player:get_wielded_item()
	local key = held and held:get_name() or ""
	if key == "" then
		chat(player, S("Hold the item you want to add."))
		goto_main(player)
		return
	end

	local ench = {}
	if mcl_enchanting and mcl_enchanting.get_enchantments then
		local e = mcl_enchanting.get_enchantments(held)
		if type(e) == "table" then ench = e end
	end

	local count = (held.get_count and held:get_count()) or 1
	if count <= 1 then
		commit_entry(player, key, ench, 1, nil)
		goto_main(player)
		return
	end

	local s = session_for(name, "add")
	s.screen = "add"
	s.key = key
	s.ench = ench
	s.qty_default = count
	s.qty_max = count
	s.edit_index = nil
	show(player, s)
end

-- Open the "How many?" prompt for an existing entry (Edit button).
local function goto_edit(player, ei)
	local name = player:get_player_name()
	local entry = smp_quickbuy.entries.get(name, ei)
	if not entry then
		goto_entries(player)
		return
	end
	local s = session_for(name, "add")
	s.screen = "add"
	s.key = entry.key
	s.ench = entry.ench
	s.qty_default = entry.qty
	s.qty_max = nil   -- editing an existing listing: no held-stack cap
	s.edit_index = ei
	show(player, s)
end

-- Called from the main panel (and again from the warn screen on confirm).
local function try_buy(player, entry_index, shown_price, confirmed)
	local name = player:get_player_name()
	local r, a, b, c = smp_quickbuy.buy.entry(player, entry_index, shown_price, confirmed)

	if r == "warn" then
		-- a = entry_index, b = shown_price, c = live cost.
		goto_warn(player, a, b, c)
		return
	end

	-- Success or refusal both redraw the main panel so the prices shown are
	-- always the live ones (a refusal message has already been sent).
	goto_main(player)
end

----------------------------------------------------------------------
-- Screen handlers (client fields are untrusted; every action re-validates)
----------------------------------------------------------------------

local function on_main(player, fields)
	local name = player:get_player_name()
	local s = smp_core.get_session(name, MENU)
	if not s then return end

	if fields.add then goto_add(player); return end
	if fields.your_entries then goto_entries(player); return end
	if fields.prev then
		s.page = math.max(1, (s.page or 1) - 1)
		show(player, s); return
	end
	if fields.next then
		s.page = (s.page or 1) + 1
		show(player, s); return
	end

	for fname, _ in pairs(fields) do
		local idx = fname:match("^entry_(%d+)$")
		if idx then
			local i = tonumber(idx)
			local shown = s.prices and s.prices[i]
			try_buy(player, i, shown, false)
			return
		end
	end
end

local function on_entries(player, fields)
	local name = player:get_player_name()
	local s = smp_core.get_session(name, MENU)
	if not s then return end

	if fields.back then
		goto_main(player)
		return
	end

	for fname, _ in pairs(fields) do
		local ri = tonumber(fname:match("^remove_(%d+)$"))
		if ri then
			smp_quickbuy.entries.remove(name, ri)
			show(player, s)
			return
		end
		local ei = tonumber(fname:match("^edit_(%d+)$"))
		if ei then
			goto_edit(player, ei)
			return
		end
	end
end

local function on_add(player, fields)
	local name = player:get_player_name()
	local s = smp_core.get_session(name, MENU)
	if not s then return end

	if fields.cancel then
		goto_main(player)
		return
	end

	if fields.add then
		local qty = parse_qty(fields.amount)
		if not qty then
			chat(player, S("Enter a whole number of at least 1."))
			show(player, s)
			return
		end
		if s.qty_max and qty > s.qty_max then
			qty = s.qty_max
			chat(player, S("You only have @1 to add.", smp_core.fmt_qty(s.qty_max)))
		end
		commit_entry(player, s.key, s.ench, qty, s.edit_index)
		goto_main(player)
		return
	end
end

local function on_warn(player, fields)
	local name = player:get_player_name()
	local s = smp_core.get_session(name, MENU)
	if not s then return end

	if fields.cancel_warn then
		goto_main(player)
		return
	end
	if fields.confirm then
		local idx = s.entry_index
		local shown = s.shown_price
		try_buy(player, idx, shown, true)   -- confirmed: guard bypassed
		return
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= MENU then return false end
	local name = player:get_player_name()
	local s = smp_core.get_session(name, MENU)
	if not s then return false end

	if fields.quit then
		smp_core.close_session(name, MENU)
		return false
	end

	local screen = s.screen or "main"
	if screen == "main" then on_main(player, fields)
	elseif screen == "entries" then on_entries(player, fields)
	elseif screen == "add" then on_add(player, fields)
	elseif screen == "warn" then on_warn(player, fields)
	end
	return false
end)

----------------------------------------------------------------------
-- /shop
----------------------------------------------------------------------

core.register_chatcommand("shop", {
	params = "",
	description = S("Open Quick Buy."),
	func = function(player_name, _)
		local player = core.get_player_by_name(player_name)
		if not player then return false, S("Player not found.") end
		goto_main(player)
		return true
	end,
})

----------------------------------------------------------------------
-- /smp test smp_quickbuy — in-game acceptance tests (smp_admin)
--
-- The /smp dispatcher in smp_economy only knows smp_core today; we intercept
-- the chat command so smp_quickbuy's own test.lua is reachable. The
-- integrator folds this into a generic test registry later (see §10).
----------------------------------------------------------------------

function smp_quickbuy.run_tests(player)
	local chunk, err = loadfile(core.get_modpath("smp_quickbuy") .. "/test.lua")
	local results
	if chunk then
		local ok, res = pcall(chunk)
		if ok and type(res) == "table" then
			results = res
		else
			core.chat_send_player(player:get_player_name(),
				S("Tests crashed: @1", tostring(res)))
			return
		end
	else
		core.chat_send_player(player:get_player_name(),
			S("Could not load test.lua: @1", tostring(err)))
		return
	end

	local lines = { S("--- smp_quickbuy tests ---") }
	lines[#lines + 1] = S("Passed: @1", results.passed)
	lines[#lines + 1] = S("Failed: @1", results.failed)
	for _, l in ipairs(results.lines or {}) do lines[#lines + 1] = l end
	core.chat_send_player(player:get_player_name(), table.concat(lines, "\n"))
end

core.register_on_chatcommand(function(name, command, params)
	if command ~= "smp" then return false end
	local target = (params or ""):match("^%s*test%s+(%S+)")
	if target ~= "smp_quickbuy" and target ~= "quickbuy" then return false end

	local player = core.get_player_by_name(name)
	if not player then return false end
	local privs = (core.get_player_privs and core.get_player_privs(name)) or {}
	if not (privs.smp_admin or privs.server) then return false end

	smp_quickbuy.run_tests(player)
	return true
end)

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

core.register_on_leaveplayer(function(player)
	smp_core.close_all_sessions(player:get_player_name())
end)

core.log("action", "[smp_quickbuy] loaded: /shop Quick Buy ready")
