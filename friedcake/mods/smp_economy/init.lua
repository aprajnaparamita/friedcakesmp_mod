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
--   /smp test <mod>                run acceptance tests (smp_admin)
--
-- Behaviour notes (fixes/f01-economy-core.md):
--   * every `/pay` validation runs before the first mutation and nothing
--     yields in between (shared §2.3) — blocks, rate limit, amount,
--     recipient toggle, funds;
--   * payments to an OFFLINE recipient are queued in this mod's own mod
--     storage and summarised on the recipient's next join (§4.2.4);
--   * large transfers to low-playtime accounts are recorded through
--     `smp_admin.flag` (D9), flagged, never blocked (§4.2.5);
--   * `economy.max_balance` is enforced in this mod's give/set paths
--     (E-18); `/pay` still moves money through `smp_store.api`, whose
--     own cap (`store.max_balance`) covers direct callers.
--
-- All strings go through core.get_translator, so they can be translated.
-- The default textdomain (smp_economy) ships with English; see spec/shared/08-ui-strings.md
-- for the catalogue of strings this mod eventually needs to add.
-- Invented strings follow shared §0.5.4: sentence case, NO terminal full
-- stop (E-13).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

-- This mod's own storage: offline-recipient payment summaries (§4.2.4).
-- Captured at load time — `core.get_mod_storage()` resolves the calling
-- mod, so it must not be re-fetched from inside a callback.
local storage = core.get_mod_storage()

-- Reusable reference to the sanctioned mutation entry points declared in
-- the "Money helpers" section below (f01 §6/§8, E-18).
local smp_economy = smp_economy or {}
_G.smp_economy = smp_economy

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

local function playtime(name)
	local r = smp_store.api.get_player(name)
	return r and (r.playtime or 0) or 0
end

----------------------------------------------------------------------
-- Money helpers (f01 §6/§8 — E-18)
--
-- §8 makes these the sanctioned mutation entry points: no mod writes
-- `player_record.money` directly. `give` enforces `economy.max_balance`
-- (the key was read but dead before this build; T10 proves it moves),
-- `take` refuses an overdraft with nil, `get` is the balance read §6
-- uses. Every call is synchronous — no yields (shared §2.3) — and the
-- ledger is written by `smp_store`, so each mutation still lands as one
-- append-only entry (shared §2.6 R3).
----------------------------------------------------------------------

function smp_economy.get(name)
	local r = smp_store.api.get_player(name)
	return r and (r.money or 0) or 0
end

-- Returns the amount actually taken, or nil when the balance is short.
function smp_economy.take(name, cents, reason, ref)
	cents = tonumber(cents) or 0
	if cents <= 0 then return nil end
	return smp_store.api.take_money(name, cents, reason or "admin", ref)
end

-- Returns the amount actually credited: clamped to `economy.max_balance`,
-- so it can be less than requested (0 when the balance is already at the
-- cap). Callers that must not lose money validate the headroom first.
function smp_economy.give(name, cents, reason, ref)
	cents = math.floor(tonumber(cents) or 0)
	if cents <= 0 then return 0 end
	local headroom = cfg.max_balance - smp_economy.get(name)
	if headroom <= 0 then return 0 end
	if cents > headroom then cents = headroom end
	return smp_store.api.add_money(name, cents, reason or "admin", ref)
end

----------------------------------------------------------------------
-- Recipient payment toggle (f01 §6, E-22)
--
-- Canonical id `eco.pay_accept`, read and written through f12's
-- accessor. f12 does not register the id yet (f12 §10: candidate keys
-- are unregistered until their category opens with evidence), so `get`
-- answers nil and `set` answers false today; `record.social.pay_accept`
-- therefore stays the offline-authoritative fallback, and the default is
-- ON — the current, spec-consistent chain.
--
-- Read chain: settings value -> record.social value -> default on.
-- A nil or unrecognised settings value NEVER flips the default (f12 §8).
----------------------------------------------------------------------

local SETTINGS_ID = "eco.pay_accept"

local function settings_pay_accept(name)
	if type(smp_settings) ~= "table" or type(smp_settings.get) ~= "function" then
		return nil
	end
	local ok, value = pcall(smp_settings.get, name, SETTINGS_ID)
	if not ok or value == nil then return nil end
	if value == "ON" or value == true then return true end
	if value == "OFF" or value == false then return false end
	return nil -- unrecognised token: fall through to the fallback chain
end

local function pay_accept_on(name)
	local from_settings = settings_pay_accept(name)
	if from_settings ~= nil then return from_settings end
	local r = smp_store.api.get_player(name)
	local legacy = r and r.social and r.social.pay_accept
	if legacy == nil then return true end
	return legacy and true or false
end

local function set_pay_accept(name, on)
	local rec = ensure_record(name)
	rec.social = rec.social or {}
	rec.social.pay_accept = on and true or false
	smp_store.api.upsert_player(rec)
	-- Mirror into f12's storage when it accepts the id. `set` answers
	-- false for an unregistered id (f12 §5) and for an offline holder
	-- (player meta only exists online) — the record written above is the
	-- fallback in both cases, so nothing is lost.
	if type(smp_settings) == "table" and type(smp_settings.set) == "function" then
		pcall(smp_settings.set, name, SETTINGS_ID, on and "ON" or "OFF")
	end
	return true
end

-- One-time migration: copy an explicit legacy value into f12's storage
-- the first time the holder is online after this build ships. Runs from
-- the join handler, when player meta is reachable. `store_get` is the raw
-- read — `get` cannot tell "unset" from "set to the registered default" —
-- and an explicit stored setting is never overwritten.
local function migrate_pay_accept(name)
	if type(smp_settings) ~= "table" then return end
	if type(smp_settings.store_get) ~= "function"
	   or type(smp_settings.set) ~= "function" then
		return
	end
	local rec = smp_store.api.get_player(name)
	local legacy = rec and rec.social and rec.social.pay_accept
	if legacy == nil then return end
	local ok, stored = pcall(smp_settings.store_get, name, SETTINGS_ID)
	if not ok or stored ~= nil then return end
	pcall(smp_settings.set, name, SETTINGS_ID, legacy and "ON" or "OFF")
end

----------------------------------------------------------------------
-- Rate limit (shared §2.6 R9: PROPOSED one `/pay` per second)
--
-- Checked in the validate phase, before any mutation; the window is armed
-- only by a SUCCESSFUL transfer, so a refused attempt never blocks the
-- next one and no ledger row is written for a refused pay. Game time, not
-- wall time, so `/set_year`-style jumps cannot desync it.
-- `_reset_pay_cooldown` is a test hook (house style: `smp_ranks._watch`);
-- production code never calls it.
----------------------------------------------------------------------

local pay_cooldown = {}
local PAY_COOLDOWN_SECONDS = 1

local function now_seconds()
	if type(core.get_gametime) == "function" then return core.get_gametime() end
	return os.time()
end

local function cooldown_active(name)
	local until_t = pay_cooldown[name]
	return until_t ~= nil and now_seconds() < until_t
end

function smp_economy._reset_pay_cooldown(name)
	pay_cooldown[name] = nil
end

----------------------------------------------------------------------
-- Offline-recipient summaries (f01 §4.2.4, PROPOSED)
--
-- The ledger cannot answer "what did I receive while offline": its
-- `counterparty` field is always "" (E-15, integrator-owned) and
-- `ledger_for` pagination was the E-16 defect. So this mod keeps its own
-- pending list — one mod-storage key per recipient — appended at pay time
-- when the target is offline and drained by the join handler with no
-- yield between read and clear (shared §2.3).
----------------------------------------------------------------------

local function pending_key(name) return "pending:" .. name end

local function add_pending(target, from, cents)
	local key = pending_key(target)
	local list = {}
	local raw = storage:get_string(key)
	if raw ~= "" then
		local ok, decoded = pcall(core.parse_json, raw)
		if ok and type(decoded) == "table" then list = decoded end
	end
	list[#list + 1] = { from = tostring(from or ""), amount = tonumber(cents) or 0 }
	storage:set_string(key, core.write_json(list))
end

local function take_pending(name)
	local key = pending_key(name)
	local raw = storage:get_string(key)
	if raw == "" then return nil end
	-- Read and clear back to back: no callback, no yield in between.
	storage:set_string(key, "")
	local ok, list = pcall(core.parse_json, raw)
	if not ok or type(list) ~= "table" then return nil end
	return list
end

----------------------------------------------------------------------
-- /bal
----------------------------------------------------------------------

core.register_chatcommand("bal", {
	params = S("[player]"),
	description = S("Show your money balance, or another player's"),
	func = function(player_name, param)
		param = param and param:match("^%s*(.-)%s*$") or ""
		if param == "" then param = player_name end

		local r = smp_store.api.get_player(param)
		if not r and param ~= player_name then
			-- Try once with the param's first word (in case `/bal alice foo`).
			local first = param:match("^(%S+)")
			r = first and smp_store.api.get_player(first) or nil
			if not r then
				return false, S("Player @1 does not exist", param)
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
	description = S("Alias for /bal"),
	func = function(player_name, param)
		-- delegate to /bal's body by re-invoking the command
		local cmd = core.registered_chatcommands["bal"]
		if cmd and cmd.func then return cmd.func(player_name, param) end
		return false, S("Internal error: /bal missing")
	end,
})

core.register_chatcommand("money", {
	params = S("[player]"),
	description = S("Alias for /bal"),
	func = function(player_name, param)
		local cmd = core.registered_chatcommands["bal"]
		if cmd and cmd.func then return cmd.func(player_name, param) end
		return false, S("Internal error: /bal missing")
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

-- E-10 (engine limit, verified against the local engine clone):
--
-- The observed dropdown [F0089] is the CLIENT's own prefix completion over
-- the players it knows about — `ChatPrompt::nickCompletion`
-- (src/chat.cpp:559) called from the chat console
-- (src/gui/guiChatConsole.cpp:655-659) over the connected-player list.
-- `doc/lua_api.md` exposes NO server-driven argument-completion hook for
-- `core.register_chatcommand`, so a dedicated server cannot populate or
-- extend that list, and `core.get_player_names` is registered only by
-- l_client.cpp (client mods), i.e. nil on a dedicated server. Server-side
-- work is therefore limited to resolving the typed prefix to a full name
-- below (T7 proves it): the dropdown itself is client behaviour the
-- server can neither drive nor replace. Improve only against a real
-- engine API.
local function resolve_player_name(prefix)
	if not prefix or prefix == "" then return nil end
	-- Exact match first.
	if core.get_player_by_name(prefix) then return prefix end
	if smp_store.api.get_player(prefix) then return prefix end
	-- Case-insensitive prefix match over online players.
	local names = {}
	for _, p in ipairs(core.get_connected_players()) do
		names[#names + 1] = p:get_player_name()
	end
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
			if match then return nil end -- ambiguous
			match = n
		end
	end
	return match
end

-- Register the chat command and a completion handler that mirrors the
-- observed behaviour (alphabetical list, prefix match).
core.register_chatcommand("pay", {
	params = S("<player> <amount>"),
	description = S("Send money to another player"),
	func = function(player_name, param)
		param = param and param:match("^%s*(.-)%s*$") or ""
		local target_raw, amount_raw = param:match("^(%S+)%s+(.+)$")
		if not target_raw then
			return false, S("Usage: /pay <player> <amount>")
		end
		local target = resolve_player_name(target_raw)
		if not target then
			return false, S("Player @1 does not exist", target_raw)
		end
		if target == player_name then
			return false, S("You cannot pay yourself")
		end
		-- f01 §4.2.1: reject recipients who have blocked the payer (and
		-- vice-versa) without revealing which privacy rule fired (X9).
		-- V-48 ruled 2026-09-25: payments are BLOCK-only — `/ignore`
		-- does not refuse them (f11 §4.3 payments row), so this tests
		-- `blocks_only()`, not `blocks()` (which folds ignore in).
		if smp_social and type(smp_social.blocks_only) == "function" then
			if smp_social.blocks_only(target, player_name)
			   or smp_social.blocks_only(player_name, target) then
				return false, S("You cannot send money to @1", target)
			end
		end
		-- R9 rate limit: second of two pays inside the window is refused
		-- before anything mutates (shared §2.6 R9, PROPOSED 1/s).
		if cooldown_active(player_name) then
			return false, S("Too fast, slow down")
		end
		local cents, perr = smp_core.parse_amount(amount_raw)
		if not cents then
			return false, S("Invalid amount: @1", perr or "?")
		end
		if cents < cfg.min_pay then
			return false, S("Amount too small (min @1)", fmt_inline(cfg.min_pay))
		end
		if not pay_accept_on(target) then
			return false, S("@1 is not accepting payments", target)
		end
		-- Pre-flight: sender must have the funds.
		local sender_rec = ensure_record(player_name)
		if sender_rec.money < cents then
			return false, S("Insufficient funds")
		end

		-- Transaction (no yields; spec §2.3).
		smp_store.api.take_money(player_name, cents, "pay", target)
		smp_store.api.add_money(target, cents, "pay", player_name)

		-- Flag large transfers to low-playtime accounts (f01 §4.2.5,
		-- shared §2.6 R10): flagged, never blocked. D9 landed 2026-09-24,
		-- so the entry goes to smp_admin's staff-review ring buffer; the
		-- 2-argument signature means this side formats `detail` itself
		-- (fixes/f01-economy-core.md E-03).
		if cents >= cfg.flag_threshold
		   and playtime(target) < cfg.flag_min_playtime then
			local detail = string.format("%s -> %s %s",
				player_name, target, money_chat(cents))
			if smp_admin and type(smp_admin.flag) == "function" then
				smp_admin.flag("large_transfer_to_new_account", detail)
			else
				core.log("warning",
					"[smp_economy] flag: large_transfer_to_new_account " .. detail)
			end
		end

		core.chat_send_player(player_name, S("You paid @1 @2", target, money_chat(cents)))
		local tgt = get_player(target)
		if tgt then
			core.chat_send_player(target, S("You received @1 from @2", money_chat(cents), player_name))
		else
			-- Offline recipient: queue the summary for the next join (E-02).
			add_pending(target, player_name, cents)
		end
		pay_cooldown[player_name] = now_seconds() + PAY_COOLDOWN_SECONDS
		return true
	end,
})

-- Hook the chat-command completion so /pay <Tab> lists names. Luanti does
-- not expose this hook directly (E-10: no server-side completion API in
-- `doc/lua_api.md`), but the chat window already does prefix completion
-- against the online player list; we layer an alias below that resolves
-- an exact name. Operators can disable this with economy.tab_complete = false.
if core.settings:get_bool("economy.tab_complete", true) then
	-- register_on_chatcommand is not a real hook; the chat window's
	-- completion is driven by the engine. The closest thing is to add
	-- an alternative syntax /pay:<name> that the server also accepts.
	-- We register /payto for explicit-by-name, which makes scripting easier.
	core.register_chatcommand("payto", {
		params = S("<player> <amount>"),
		description = S("Send money to a player by exact name (scripting-friendly alias for /pay)"),
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
	description = S("Toggle whether you accept incoming payments"),
	func = function(player_name, _)
		local new = not pay_accept_on(player_name)
		set_pay_accept(player_name, new)
		if new then
			return true, S("You now accept payments")
		end
		return true, S("You no longer accept payments")
	end,
})

core.register_chatcommand("paymenttoggle", {
	params = "",
	description = S("Alias for /paytoggle"),
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
	description = S("Show the money leaderboard"),
	func = function(player_name, param)
		local page = tonumber(param and param:match("^%s*(%d+)") or "1") or 1
		local body = page_baltop(page)
		core.chat_send_player(player_name, body)
		return true
	end,
})

core.register_chatcommand("moneytop", {
	params = S("[page]"),
	description = S("Alias for /baltop"),
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
	description = S("Show your shard balance"),
	func = function(player_name, _)
		local r = ensure_record(player_name)
		return true, S("Your shards: @1", smp_core.fmt_qty(r.shards or 0))
	end,
})

core.register_chatcommand("shard", {
	params = "",
	description = S("Alias for /shards"),
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
	description = S("Adjust a player's money (admin)"),
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
			-- give clamps to economy.max_balance (E-18) and reports what
			-- actually landed, so an admin is never told more than moved.
			local applied = smp_economy.give(target, cents, "admin",
				"eco:give:" .. player_name)
			if applied < cents then
				return true, S("Gave @1 to @2 (capped)", money_chat(applied), target)
			end
			return true, S("Gave @1 to @2", money_chat(applied), target)
		elseif sub == "take" then
			local cents, perr = smp_core.parse_amount(amount_raw)
			if not cents then return false, S("Invalid amount: @1", perr or "?") end
			local removed = smp_store.api.take_money(target, cents, "admin",
				"eco:take:" .. player_name)
			if not removed then return false, S("@1 does not have that much", target) end
			return true, S("Took @1 from @2", money_chat(removed), target)
		elseif sub == "set" then
			local cents, perr = smp_core.parse_amount(amount_raw)
			if not cents then return false, S("Invalid amount: @1", perr or "?") end
			-- Economy's own cap applies here too (E-18): a set can never
			-- push a balance past economy.max_balance.
			local applied = math.min(cents, cfg.max_balance)
			smp_store.api.set_money(target, applied, "admin", "eco:set:" .. player_name)
			return true, S("Set @1's balance to @2", target, money_chat(applied))
		elseif sub == "reset" then
			-- E-08: §2 gives reset the shared `<player> <amount>`
			-- signature, so <amount> is CONSUMED: reset sets the balance
			-- to it (a reset to 1234 cents, not to 0). A missing or
			-- invalid amount is rejected — never accepted and ignored.
			local cents, perr = smp_core.parse_amount(amount_raw)
			if not cents then return false, S("Invalid amount: @1", perr or "?") end
			local applied = math.min(cents, cfg.max_balance)
			smp_store.api.set_money(target, applied, "admin", "eco:reset:" .. player_name)
			return true, S("Reset @1's balance to @2", target, money_chat(applied))
		end
		return false, S("Unknown subcommand: @1", sub)
	end,
})

----------------------------------------------------------------------
-- /ledger
--
-- f01 §8:188-194: admin OR moderator. Luanti's `privs` table is an AND
-- gate over every entry (builtin/game/chat.lua:79 `check_player_privs`),
-- so registering `{smp_moderator = true, smp_admin = true}` would demand
-- BOTH privileges and lock out admins. The command therefore registers
-- without a privs table and checks the pair here, answering with the
-- engine's own denial sentence (builtin/game/chat.lua:103-106) so the OR
-- requirement leaks nothing. The server console (caller "") is allowed,
-- mirroring the engine, which never runs `func` for a console-less check.
-- `/eco` stays smp_admin-only per the same §8 row.
----------------------------------------------------------------------

local LEDGER_PRIVS = { "smp_admin", "smp_moderator" }

local function ledger_allowed(name)
	if name == nil or name == "" then return true end
	if type(core.get_player_privs) ~= "function" then return false end
	local ok, privs = pcall(core.get_player_privs, name)
	if not ok or type(privs) ~= "table" then return false end
	return privs.smp_admin == true or privs.smp_moderator == true
end

local function ledger_denial(name)
	local missing = {}
	if type(core.get_player_privs) == "function" then
		local ok, privs = pcall(core.get_player_privs, name)
		if ok and type(privs) == "table" then
			for _, p in ipairs(LEDGER_PRIVS) do
				if privs[p] ~= true then missing[#missing + 1] = p end
			end
		end
	end
	if #missing == 0 then
		for _, p in ipairs(LEDGER_PRIVS) do missing[#missing + 1] = p end
	end
	-- Engine-verbatim sentence (not invented: keep the full stop).
	return S("You don't have permission to run this command (missing privileges: @1).",
		table.concat(missing, ", "))
end

core.register_chatcommand("ledger", {
	params = S("<player> [page]"),
	description = S("Show a player's economic audit trail (moderator+)"),
	func = function(player_name, param)
		if not ledger_allowed(player_name) then
			return false, ledger_denial(player_name)
		end
		param = param and param:match("^%s*(.-)%s*$") or ""
		local target_raw, page_raw = param:match("^(%S+)%s*(%d*)$")
		if not target_raw then
			return false, S("Usage: /ledger <player> [page]")
		end
		local target = resolve_player_name(target_raw) or target_raw
		local page = tonumber(page_raw) or 1
		local entries, total_pages = smp_store.api.ledger_for(target, page, cfg.ledger_page_size)
		if #entries == 0 then
			return true, S("No ledger entries for @1", target)
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
-- Acceptance tests for smp_core (spec/features/f01 §9 T1–T3)
--
-- Declared ABOVE the `/smp` registration: the command closure captures
-- these locals, so `/smp test` never falls through to a nil global
-- (E-09: the `local function` used to be declared after the closure,
-- which is an `attempt to call a nil value` at runtime).
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
		lines[#lines + 1] = S("T9 take_money respects balance: OK")
	else
		lines[#lines + 1] = S("T9 take_money respects balance: FAIL")
	end
	local again = smp_store.api.take_money("__test_alice", 10000, "test", "T9")
	if again == nil then
		lines[#lines + 1] = S("T9 refuse overdraft: OK")
	else
		lines[#lines + 1] = S("T9 refuse overdraft: FAIL")
	end

	-- Cleanup.
	smp_store.api.set_money("__test_alice", 0, "test", "cleanup")

	if results.failed == 0 then
		lines[#lines + 1] = S("All smp_core tests passed")
	else
		lines[#lines + 1] = S("Some smp_core tests FAILED")
	end
	core.chat_send_player(player_name, table.concat(lines, "\n"))
	core.log("action", "[smp_economy] smp_core tests run by " .. player_name
		.. " — passed=" .. results.passed .. " failed=" .. results.failed)
	return results.failed == 0
end

-- Generic `<mod>/test.lua` target. PROPOSED: f01 §2 documents `/smp
-- reload` only; the dispatcher grew `test` for §9 and now runs any pack
-- mod that ships an in-mod suite (smp_economy, smp_items, …). Other mods
-- wrap this command to intercept their own target first.
local function run_mod_tests(player_name, modname)
	if type(modname) ~= "string" or not modname:match("^smp_[%w_]+$") then
		return false, S("Unknown test target: @1", tostring(modname))
	end
	local modpath = core.get_modpath(modname)
	if not modpath then
		return false, S("Unknown test target: @1", modname)
	end
	local chunk, err = loadfile(modpath .. "/test.lua")
	if not chunk then
		return false, S("Could not load @1/test.lua: @2", modname, tostring(err))
	end
	local ok, results = pcall(chunk)
	if not ok then
		return false, S("Tests crashed: @1", tostring(results))
	end
	if type(results) ~= "table" then
		return false, S("Tests returned no results")
	end
	local lines = {
		S("--- @1 tests ---", modname),
		S("Passed: @1", results.passed or 0),
		S("Failed: @1", results.failed or 0),
	}
	if (results.failed or 0) > 0 then
		for _, l in ipairs(results.lines or {}) do lines[#lines + 1] = l end
	end
	core.chat_send_player(player_name, table.concat(lines, "\n"))
	core.log("action", string.format("[smp_economy] %s tests run by %s — passed=%d failed=%d",
		modname, player_name, results.passed or 0, results.failed or 0))
	return (results.failed or 0) == 0
end

local function run_smp_test(player_name, target)
	if target == "" or target == "smp_core" then
		return run_smp_core_tests(player_name)
	end
	return run_mod_tests(player_name, target)
end

----------------------------------------------------------------------
-- /smp reload and /smp test
----------------------------------------------------------------------

core.register_chatcommand("smp", {
	params = S("reload|test|backend"),
	description = S("FriedcakeSMP administration: reload config, run tests, show backend"),
	privs = { smp_admin = true },
	func = function(player_name, param)
		local op = (param or ""):match("^%s*(%S+)") or ""
		if op == "reload" then
			reload_cfg()
			return true, S("FriedcakeSMP configuration reloaded")
		elseif op == "test" then
			local target = (param or ""):match("^%s*test%s+(%S+)") or ""
			return run_smp_test(player_name, target)
		elseif op == "backend" then
			local cmd = core.registered_chatcommands["smp_backend"]
			if cmd then return cmd.func(player_name, "") end
			return false, S("Backend status unavailable")
		end
		return false, S("Usage: /smp reload|test|backend")
	end,
})

----------------------------------------------------------------------
-- Lifecycle: clear menu sessions and ledger-aware bookkeeping on leave,
-- summarise payments received while offline on join (f01 §4.2.4).
----------------------------------------------------------------------

core.register_on_leaveplayer(function(player_name)
	smp_core.close_all_sessions(player_name)
end)

core.register_on_joinplayer(function(player)
	local name
	if type(player) == "string" then
		name = player
	elseif type(player) == "table" and type(player.get_player_name) == "function" then
		name = player:get_player_name()
	end
	if type(name) ~= "string" or name == "" then return end

	migrate_pay_accept(name)

	-- Read and clear first: no yield between the two (shared §2.3), then
	-- render. An unreadable payload is dropped rather than re-shown.
	local list = take_pending(name)
	if not list then return end
	local lines = { S("Payments received while you were offline:") }
	for _, e in ipairs(list) do
		lines[#lines + 1] = S("From @1: @2",
			tostring(e.from or "?"), money_chat(tonumber(e.amount) or 0))
	end
	core.chat_send_player(name, table.concat(lines, "\n"))
end)

core.log("action", "[smp_economy] loaded: /bal /pay /paytoggle /baltop /shards /eco /ledger /smp")
