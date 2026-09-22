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

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function show(player, formname, formspec)
	core.show_formspec(player:get_player_name(), formname, formspec)
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
-- Menu openers
----------------------------------------------------------------------

local function open_main(player)
	local name = player:get_player_name()
	local session = smp_core.open_session(name, F.MAIN, { page = 1, prices = {} })
	session.prices = {}   -- force a fresh live price lookup on this redraw
	show(player, F.MAIN, F.main(player, session))
end

local function open_add(player)
	local name = player:get_player_name()
	local held = (player.get_wielded_item and player:get_wielded_item()) or nil
	local key = held and held:get_name() or nil
	if not key or key == "" then
		core.chat_send_player(name, S("Hold the item you want to add."))
		open_main(player)
		return
	end

	local ench = {}
	if mcl_enchanting and mcl_enchanting.get_enchantments then
		local e = mcl_enchanting.get_enchantments(held)
		if type(e) == "table" then ench = e end
	end

	local session = smp_core.open_session(name, F.ADD_QTY, {})
	session.key        = key
	session.ench       = ench
	session.held_count = (held.get_count and held:get_count()) or 1
	session.edit_index = nil
	show(player, F.ADD_QTY, F.add_qty(session))
end

local function open_entries(player)
	local name = player:get_player_name()
	smp_core.open_session(name, F.ENTRIES, {})
	show(player, F.ENTRIES, F.entries(player))
end

-- Called from the main panel (and again from the warn screen on confirm).
local function try_buy(player, entry_index, shown_price, confirmed)
	local name = player:get_player_name()
	local r, a, b, c = smp_quickbuy.buy.entry(player, entry_index, shown_price, confirmed)

	if r == "warn" then
		-- a = entry_index, b = shown_price, c = live cost. Open the
		-- re-confirm screen (Review Order pattern, §4.7).
		local session = smp_core.open_session(name, F.WARN, {})
		session.entry_index = a
		session.shown_price = b
		session.cost        = c
		show(player, F.WARN, F.warn(player, session))
		return
	end

	-- Success or refusal both redraw the main panel so the prices shown are
	-- always the live ones (a refusal message has already been sent).
	open_main(player)
end

----------------------------------------------------------------------
-- Field handlers (client fields are untrusted; every action re-validates)
----------------------------------------------------------------------

local function on_main(player, fields)
	local name = player:get_player_name()
	if fields.quit then
		smp_core.close_session(name, F.MAIN)
		return true
	end
	local session = smp_core.get_session(name, F.MAIN)
	if not session then return true end

	if fields.add then open_add(player); return true end
	if fields.your_entries then open_entries(player); return true end
	if fields.prev then
		session.page = math.max(1, (session.page or 1) - 1)
		show(player, F.MAIN, F.main(player, session)); return true
	end
	if fields.next then
		session.page = (session.page or 1) + 1
		show(player, F.MAIN, F.main(player, session)); return true
	end

	for fname, _ in pairs(fields) do
		local idx = fname:match("^entry_(%d+)$")
		if idx then
			local i = tonumber(idx)
			local shown = session.prices and session.prices[i]
			try_buy(player, i, shown, false)
			return true
		end
	end
	return true
end

local function on_entries(player, fields)
	local name = player:get_player_name()
	if fields.quit then
		smp_core.close_session(name, F.ENTRIES)
		return true
	end
	if not smp_core.get_session(name, F.ENTRIES) then return true end

	if fields.back then
		smp_core.close_session(name, F.ENTRIES)
		open_main(player)
		return true
	end

	for fname, _ in pairs(fields) do
		local ri = tonumber(fname:match("^remove_(%d+)$"))
		if ri then
			smp_quickbuy.entries.remove(name, ri)
			show(player, F.ENTRIES, F.entries(player))
			return true
		end
		local ei = tonumber(fname:match("^edit_(%d+)$"))
		if ei then
			local entry = smp_quickbuy.entries.get(name, ei)
			if entry then
				local s = smp_core.open_session(name, F.ADD_QTY, {})
				s.key        = entry.key
				s.ench       = entry.ench
				s.held_count = entry.qty
				s.edit_index = ei
				show(player, F.ADD_QTY, F.add_qty(s))
			end
			return true
		end
	end
	return true
end

local function on_add_qty(player, fields)
	local name = player:get_player_name()
	if fields.quit then
		smp_core.close_session(name, F.ADD_QTY)
		open_main(player)
		return true
	end
	local session = smp_core.get_session(name, F.ADD_QTY)
	if not session then return true end

	if fields.cancel then
		smp_core.close_session(name, F.ADD_QTY)
		open_main(player)
		return true
	end

	if fields.add then
		local qty = parse_qty(fields.amount)
		if not qty then
			core.chat_send_player(name, S("Enter a whole number of at least 1."))
			show(player, F.ADD_QTY, F.add_qty(session))
			return true
		end
		if session.edit_index then
			local cur = smp_quickbuy.entries.get(name, session.edit_index)
			if cur then
				smp_quickbuy.entries.set(name, session.edit_index,
					{ key = cur.key, ench = cur.ench, qty = qty })
			end
		else
			local ok, err = smp_quickbuy.entries.add(name,
				{ key = session.key, ench = session.ench, qty = qty })
			if not ok and err == "capacity" then
				core.chat_send_player(name, S("You reached the Quick Buy entry limit."))
			end
		end
		smp_core.close_session(name, F.ADD_QTY)
		open_main(player)
		return true
	end
	return true
end

local function on_warn(player, fields)
	local name = player:get_player_name()
	if fields.quit then
		smp_core.close_session(name, F.WARN)
		return true
	end
	local session = smp_core.get_session(name, F.WARN)
	if not session then return true end

	if fields.cancel_warn then
		smp_core.close_session(name, F.WARN)
		open_main(player)
		return true
	end
	if fields.confirm then
		local idx = session.entry_index
		local shown = session.shown_price
		smp_core.close_session(name, F.WARN)
		try_buy(player, idx, shown, true)   -- confirmed: guard bypassed
		return true
	end
	return true
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if type(formname) ~= "string" or formname:sub(1, 13) ~= "smp_quickbuy:" then
		return false
	end
	if formname == F.MAIN then on_main(player, fields)
	elseif formname == F.ENTRIES then on_entries(player, fields)
	elseif formname == F.ADD_QTY then on_add_qty(player, fields)
	elseif formname == F.WARN then on_warn(player, fields)
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
		open_main(player)
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
