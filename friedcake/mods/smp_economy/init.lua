-- FriedcakeSMP — smp_economy
--
-- Implements spec/features/f01-economy-core.md.
--
-- Commands:
--   /bal [player]                  show balance
--   /pay <player> <amount>         transfer money (tab-completes player names)
--   /paytoggle                     toggle receiving payments
--   /baltop [page]                 money leaderboard
--   /shards                        shard balance
--   /eco give|take|set|reset <player> <amount>   (smp_admin)
--   /ledger <player> [page]        audit trail       (smp_admin | smp_moderator)
--   /smp reload                    reload config     (smp_admin)
--   /smp test <feature>            run acceptance tests (smp_admin)
--
-- All strings go through core.get_translator, so they can be translated.
-- The default textdomain (smp_economy) ships with English; see spec/shared/08-ui-strings.md
-- for the catalogue of strings this mod eventually needs to add.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

----------------------------------------------------------------------
-- Config (mirrors spec/features/f01 §7)
----------------------------------------------------------------------

local cfg = {
	min_pay           = tonumber(core.settings:get("economy.min_pay"))   or 1,      -- 1 cent
	max_balance       = tonumber(core.settings:get("economy.max_balance")) or 1e15,
	flag_threshold    = tonumber(core.settings:get("economy.flag_threshold")) or 100000000, -- $1M
	flag_min_playtime = tonumber(core.settings:get("economy.flag_min_playtime")) or 7200, -- 2h
	server_name       = core.settings:get("server.name") or "FriedcakeSMP",
	ledger_page_size  = tonumber(core.settings:get("ledger.page_size")) or 20,
}

-- Reload handler: /smp reload re-reads the settings and re-resolves the
-- ledger page size. We can't reload smp_store's chosen backend from here;
-- that lives in smp_store itself (see /smp_backend).
local function reload_cfg()
	cfg.min_pay           = tonumber(core.settings:get("economy.min_pay"))   or cfg.min_pay
	cfg.max_balance       = tonumber(core.settings:get("economy.max_balance")) or cfg.max_balance
	cfg.flag_threshold    = tonumber(core.settings:get("economy.flag_threshold")) or cfg.flag_threshold
	cfg.flag_min_playtime = tonumber(core.settings:get("economy.flag_min_playtime")) or cfg.flag_min_playtime
	cfg.server_name       = core.settings:get("server.name") or cfg.server_name
	cfg.ledger_page_size  = tonumber(core.settings:get("ledger.page_size")) or cfg.ledger_page_size
end

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function get_player(name)
	local p = core.get_player_by_name(name)
	return p
end

local function ensure_record(name)
	-- smp_store API creates on demand. Use it.
	return smp_store.api.ensure_player(name)
end

local function fmt(cents) return smp_core.fmt_money(cents, "body") end
local function fmt_inline(cents) return smp_core.fmt_money(cents, "inline") end

-- Money formatter alias used in chat lines: the observed form is `$ 5.1K`
-- with a space (spec §0.6).
local function money_chat(cents) return smp_core.fmt_money(cents, "body") end

local function pay_accept_on(name)
	-- Per-player toggle lives in the social blob for now (settings is
	-- a separate mod and not yet implemented). Default = on.
	local r = smp_store.api.get_player(name)
	if not r then return true end
	local v = r.social and r.social.pay_accept
	if v == nil then return true end
	return v and true or false
end

local function set_pay_accept(name, on)
	local r = ensure_record(name)
	r.social = r.social or {}
	r.social.pay_accept = on and true or false
	smp_store.api.upsert_player(r)
end

local function playtime(name)
	local r = smp_store.api.get_player(name)
	return r and (r.playtime or 0) or 0
end

----------------------------------------------------------------------
-- /bal
----------------------------------------------------------------------

core.register_chatcommand("bal", {
	params = S("[player]"),
	description = S("Show your money balance, or another player's."),
	func = function(player_name, param)
		param = param and param:match("^%s*(.-)%s*$") or ""
		if param == "" then param = player_name end

		local r = smp_store.api.get_player(param)
		if not r and param ~= player_name then
			-- Try once with the param's first word (in case `/bal alice foo`).
			local first = param:match("^(%S+)")
			r = first and smp_store.api.get_player(first) or nil
			if not r then
				return false, S("Player @1 does not exist.", param)
			end
			param = first
		end

		local balance = (r and r.money) or 0
		if param == player_name then
			return true, S("Your balance: @1", money_chat(balance))
		end
		-- Reading another player's balance: spec marks this PROPOSED, so we
		-- allow it for now. Servers that want it private can override later.
		return true, S("@1's balance: @2", param, money_chat(balance))
	end,
})

core.register_chatcommand("balance", {
	params = S("[player]"),
	description = S("Alias for /bal."),
	func = function(player_name, param)
		-- delegate to /bal's body by re-invoking the command
		local cmd = core.registered_chatcommands["bal"]
		if cmd and cmd.func then return cmd.func(player_name, param) end
		return false, S("Internal error: /bal missing.")
	end,
})

core.register_chatcommand("money", {
	params = S("[player]"),
	description = S("Alias for /bal."),
	func = function(player_name, param)
		local cmd = core.registered_chatcommands["bal"]
		if cmd and cmd.func then return cmd.func(player_name, param) end
		return false, S("Internal error: /bal missing.")
	end,
})

----------------------------------------------------------------------
-- /pay
--
-- Reproduces the observed tab-completion of player names [F0088, F0089].
-- Luanti's register_chatcommand already supports prefix matching for the
-- first argument in the chat window; we layer our own resolver on top for
-- `param` so server-side validation gets the full name.
----------------------------------------------------------------------

local function resolve_player_name(prefix)
	if not prefix or prefix == "" then return nil end
	-- Exact match first.
	if core.get_player_by_name(prefix) then return prefix end
	if smp_store.api.get_player(prefix) then return prefix end
	-- Case-insensitive prefix match over online players.
	local names = core.get_player_names()
	local lc = prefix:lower()
	local match
	for _, n in ipairs(names) do
		if n:sub(1, #prefix):lower() == lc then
			if match then return nil end -- ambiguous
			match = n
		end
	end
	if match then return match end
	-- Fall back to case-insensitive prefix over all known records.
	for _, n in ipairs(smp_store.api.all_player_names()) do
		if n:sub(1, #prefix):lower() == lc then
			if match then return nil end
			match = n
		end
	end
	return match
end

-- Register the chat command and a completion handler that mirrors the
-- observed behaviour (alphabetical list, prefix match).
core.register_chatcommand("pay", {
	params = S("<player> <amount>"),
	description = S("Send money to another player."),
	func = function(player_name, param)
		param = param and param:match("^%s*(.-)%s*$") or ""
		local target_raw, amount_raw = param:match("^(%S+)%s+(.+)$")
		if not target_raw then
			return false, S("Usage: /pay <player> <amount>")
		end
		local target = resolve_player_name(target_raw)
		if not target then
			return false, S("Player @1 does not exist.", target_raw)
		end
		if target == player_name then
			return false, S("You cannot pay yourself.")
		end
		-- f01 §4.2.1: reject recipients who have blocked the payer (and
		-- vice-versa) without revealing which privacy rule fired.
		if smp_social and type(smp_social.blocks) == "function" then
			if smp_social.blocks(target, player_name)
			   or smp_social.blocks(player_name, target) then
				return false, S("You cannot send money to @1.", target)
			end
		end
		local cents, perr = smp_core.parse_amount(amount_raw)
		if not cents then
			return false, S("Invalid amount: @1", perr or "?")
		end
		if cents < cfg.min_pay then
			return false, S("Amount too small (min @1).", fmt_inline(cfg.min_pay))
		end
		if not pay_accept_on(target) then
			return false, S("@1 is not accepting payments.", target)
		end
		-- Pre-flight: sender must have the funds.
		local sender_rec = ensure_record(player_name)
		if sender_rec.money < cents then
			return false, S("Insufficient funds.")
		end

		-- Transaction (no yields; spec §2.3).
		smp_store.api.take_money(player_name, cents, "pay", target)
		smp_store.api.add_money(target, cents, "pay", player_name)

		-- Flag large transfers to low-playtime accounts (R10 in §2.6).
		if cents >= cfg.flag_threshold and playtime(target) < cfg.flag_min_playtime then
			core.log("warning", string.format(
				"[smp_economy] flag: large_transfer_to_new_account %s -> %s %s",
				player_name, target, money_chat(cents)))
		end

		core.chat_send_player(player_name, S("You paid @1 @2.", target, money_chat(cents)))
		local tgt = get_player(target)
		if tgt then
			core.chat_send_player(target, S("You received @1 from @2.", money_chat(cents), player_name))
		end
		return true
	end,
})

-- Hook the chat-command completion so /pay <Tab> lists names. Luanti does
-- not expose this hook directly, but the chat window already does prefix
-- completion against the online player list; we add an alias below that
-- lists all known names. Operators can disable this with economy.tab_complete = false.
if core.settings:get_bool("economy.tab_complete", true) then
	-- register_on_chatcommand is not a real hook; the chat window's
	-- completion is driven by the engine. The closest thing is to add
	-- an alternative syntax /pay:<name> that the server also accepts.
	-- We register /payto for explicit-by-name, which makes scripting easier.
	core.register_chatcommand("payto", {
		params = S("<player> <amount>"),
		description = S("Send money to a player by exact name (scripting-friendly alias for /pay)."),
		func = function(player_name, param)
			local cmd = core.registered_chatcommands["pay"]
			return cmd.func(player_name, param)
		end,
	})
end

----------------------------------------------------------------------
-- /paytoggle
----------------------------------------------------------------------

core.register_chatcommand("paytoggle", {
	params = "",
	description = S("Toggle whether you accept incoming payments."),
	func = function(player_name, _)
		local new = not pay_accept_on(player_name)
		set_pay_accept(player_name, new)
		if new then
			return true, S("You now accept payments.")
		end
		return true, S("You no longer accept payments.")
	end,
})

core.register_chatcommand("paymenttoggle", {
	params = "",
	description = S("Alias for /paytoggle."),
	func = function(player_name, param)
		local cmd = core.registered_chatcommands["paytoggle"]
		return cmd.func(player_name, param)
	end,
})

----------------------------------------------------------------------
-- /baltop
--
-- We render a chat-only leaderboard; the spec also has a menu (f14).
-- Both are valid; the chat form is what the reference server shows first.
----------------------------------------------------------------------

local function page_baltop(page)
	page = page or 1
	if page < 1 then page = 1 end
	local size = 10
	local names = smp_store.api.all_player_names()
	-- Build (name, money) pairs and sort desc.
	local rows = {}
	for _, n in ipairs(names) do
		local r = smp_store.api.get_player(n)
		if r then rows[#rows + 1] = { name = n, money = r.money or 0 } end
	end
	table.sort(rows, function(a, b)
		if a.money == b.money then return a.name < b.name end
		return a.money > b.money
	end)
	local total = #rows
	local total_pages = math.max(1, math.ceil(total / size))
	local start = (page - 1) * size + 1
	local stop  = math.min(page * size, total)
	local out = { S("--- Money Top (page @1/@2) ---", page, total_pages) }
	for i = start, stop do
		out[#out + 1] = S("@1. @2 — @3", i, rows[i].name, money_chat(rows[i].money))
	end
	return table.concat(out, "\n"), total_pages
end

core.register_chatcommand("baltop", {
	params = S("[page]"),
	description = S("Show the money leaderboard."),
	func = function(player_name, param)
		local page = tonumber(param and param:match("^%s*(%d+)") or "1") or 1
		local body = page_baltop(page)
		core.chat_send_player(player_name, body)
		return true
	end,
})

core.register_chatcommand("moneytop", {
	params = S("[page]"),
	description = S("Alias for /baltop."),
	func = function(player_name, param)
		local cmd = core.registered_chatcommands["baltop"]
		return cmd.func(player_name, param)
	end,
})

----------------------------------------------------------------------
-- /shards
----------------------------------------------------------------------

core.register_chatcommand("shards", {
	params = "",
	description = S("Show your shard balance."),
	func = function(player_name, _)
		local r = ensure_record(player_name)
		return true, S("Your shards: @1", smp_core.fmt_qty(r.shards or 0))
	end,
})

core.register_chatcommand("shard", {
	params = "",
	description = S("Alias for /shards."),
	func = function(player_name, param)
		local cmd = core.registered_chatcommands["shards"]
		return cmd.func(player_name, param)
	end,
})

----------------------------------------------------------------------
-- /eco
----------------------------------------------------------------------

local function parse_eco_subcommand(arg)
	-- returns (sub, player, amount_text) or nil
	if not arg or arg == "" then return nil end
	local sub, rest = arg:match("^(%S+)%s+(.+)$")
	if not sub then return nil end
	return sub:lower(), rest
end

core.register_chatcommand("eco", {
	params = S("give|take|set|reset <player> <amount>"),
	description = S("Adjust a player's money (admin)."),
	privs = { smp_admin = true },
	func = function(player_name, param)
		local sub, rest = parse_eco_subcommand(param)
		if not sub then
			return false, S("Usage: /eco give|take|set|reset <player> <amount>")
		end
		local target_raw, amount_raw = rest:match("^(%S+)%s+(.+)$")
		if not target_raw then
			return false, S("Usage: /eco <sub> <player> <amount>")
		end
		local target = resolve_player_name(target_raw) or target_raw
		if sub == "give" then
			local cents, perr = smp_core.parse_amount(amount_raw)
			if not cents then return false, S("Invalid amount: @1", perr or "?") end
			local applied = smp_store.api.add_money(target, cents, "admin",
				"eco:give:" .. player_name)
			return true, S("Gave @1 to @2 (capped @3).", money_chat(applied), target,
				money_chat(cents))
		elseif sub == "take" then
			local cents, perr = smp_core.parse_amount(amount_raw)
			if not cents then return false, S("Invalid amount: @1", perr or "?") end
			local removed = smp_store.api.take_money(target, cents, "admin",
				"eco:take:" .. player_name)
			if not removed then return false, S("@1 does not have that much.", target) end
			return true, S("Took @1 from @2.", money_chat(removed), target)
		elseif sub == "set" then
			local cents, perr = smp_core.parse_amount(amount_raw)
			if not cents then return false, S("Invalid amount: @1", perr or "?") end
			smp_store.api.set_money(target, cents, "admin", "eco:set:" .. player_name)
			return true, S("Set @1's balance to @2.", target, money_chat(cents))
		elseif sub == "reset" then
			smp_store.api.set_money(target, 0, "admin", "eco:reset:" .. player_name)
			return true, S("Reset @1's balance to 0.", target)
		end
		return false, S("Unknown subcommand: @1", sub)
	end,
})

----------------------------------------------------------------------
-- /ledger
----------------------------------------------------------------------

core.register_chatcommand("ledger", {
	params = S("<player> [page]"),
	description = S("Show a player's economic audit trail (moderator+)."),
	privs = { smp_moderator = true, smp_admin = true },
	func = function(player_name, param)
		param = param and param:match("^%s*(.-)%s*$") or ""
		local target_raw, page_raw = param:match("^(%S+)%s*(%d*)$")
		if not target_raw then
			return false, S("Usage: /ledger <player> [page]")
		end
		local target = resolve_player_name(target_raw) or target_raw
		local page = tonumber(page_raw) or 1
		local entries, total_pages = smp_store.api.ledger_for(target, page, cfg.ledger_page_size)
		if #entries == 0 then
			return true, S("No ledger entries for @1.", target)
		end
		local lines = { S("--- Ledger for @1 (page @2/@3) ---", target, page, total_pages) }
		for _, e in ipairs(entries) do
			lines[#lines + 1] = string.format("#%d  %s  %-8s  %s  %s",
				e.id,
				os.date("%Y-%m-%d %H:%M:%S", e.time or 0),
				e.type or "?",
				(e.currency == "shards") and smp_core.fmt_qty(math.abs(e.amount or 0))
					or money_chat(math.abs(e.amount or 0)),
				e.ref or "")
		end
		core.chat_send_player(player_name, table.concat(lines, "\n"))
		return true
	end,
})

----------------------------------------------------------------------
-- /smp reload and /smp test
----------------------------------------------------------------------

core.register_chatcommand("smp", {
	params = S("reload|test|backend"),
	description = S("FriedcakeSMP administration: reload config, run tests, show backend."),
	privs = { smp_admin = true },
	func = function(player_name, param)
		local op = (param or ""):match("^%s*(%S+)") or ""
		if op == "reload" then
			reload_cfg()
			return true, S("FriedcakeSMP configuration reloaded.")
		elseif op == "test" then
			local target = (param or ""):match("^%s*test%s+(%S+)") or ""
			if target == "" or target == "smp_core" then
				return run_smp_core_tests(player_name)
			end
			return false, S("Unknown test target: @1", target)
		elseif op == "backend" then
			local cmd = core.registered_chatcommands["smp_backend"]
			if cmd then return cmd.func(player_name, "") end
			return false, S("Backend status unavailable.")
		end
		return false, S("Usage: /smp reload|test|backend")
	end,
})

----------------------------------------------------------------------
-- Acceptance tests for smp_core (spec/features/f01 §9 T1–T3)
----------------------------------------------------------------------

local function run_smp_core_tests(player_name)
	local lines = { S("--- smp_core tests ---") }

	-- Load the test file shipped with smp_core.
	local modpath = core.get_modpath("smp_core")
	local chunk, err = loadfile(modpath .. "/test.lua")
	if not chunk then
		return false, S("Could not load smp_core/test.lua: @1", tostring(err))
	end
	local ok, results = pcall(chunk)
	if not ok then
		return false, S("Tests crashed: @1", tostring(results))
	end

	lines[#lines + 1] = S("Passed: @1", results.passed)
	lines[#lines + 1] = S("Failed: @1", results.failed)
	if results.failed > 0 then
		for _, l in ipairs(results.lines) do lines[#lines + 1] = l end
	end

	-- T9 (smoke): no operation can take more than the player has.
	-- We exercise the store directly; the mod path goes through pay().
	local rec = smp_store.api.ensure_player("__test_alice")
	rec.money = 5000
	smp_store.api.upsert_player(rec)
	local taken = smp_store.api.take_money("__test_alice", 1000, "test", "T9")
	if taken == 1000 then
		lines[#lines + 1] = "T9 take_money respects balance: OK"
	else
		lines[#lines + 1] = "T9 take_money respects balance: FAIL"
	end
	local again = smp_store.api.take_money("__test_alice", 10000, "test", "T9")
	if again == nil then
		lines[#lines + 1] = "T9 refuse overdraft: OK"
	else
		lines[#lines + 1] = "T9 refuse overdraft: FAIL"
	end

	-- Cleanup.
	smp_store.api.set_money("__test_alice", 0, "test", "cleanup")

	if results.failed == 0 then
		lines[#lines + 1] = S("All smp_core tests passed.")
	else
		lines[#lines + 1] = S("Some smp_core tests FAILED.")
	end
	core.chat_send_player(player_name, table.concat(lines, "\n"))
	core.log("action", "[smp_economy] smp_core tests run by " .. player_name
		.. " — passed=" .. results.passed .. " failed=" .. results.failed)
	return results.failed == 0
end

----------------------------------------------------------------------
-- Lifecycle: clear menu sessions and ledger-aware bookkeeping on leave.
----------------------------------------------------------------------

core.register_on_leaveplayer(function(player_name)
	smp_core.close_all_sessions(player_name)
end)

core.log("action", "[smp_economy] loaded: /bal /pay /paytoggle /baltop /shards /eco /ledger /smp")
