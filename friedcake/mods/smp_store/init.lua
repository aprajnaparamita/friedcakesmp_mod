-- FriedcakeSMP — smp_store
-- Backend-agnostic persistence. Player records, append-only ledger,
-- dirty-flag flush, schema migration. Implements
-- spec/shared/02-architecture.md §2.2–2.3.
--
-- See STORAGE.md for the driver contract, the schema, and the list of
-- operations every backend must implement.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_store = {}

----------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------

local SETTING_KEYS = {
	backend            = "auto",   -- auto | mod_storage | sqlite | postgres
	postgres_proxy_url = "http://127.0.0.1:8457", -- HTTP endpoint of pg_proxy.py
	flush_interval     = "10",     -- seconds; spec PROPOSED 10s
	max_balance        = "1000000000000000", -- 10^15 cents = $10^13
	ledger_page_size   = "20",
}

local cfg = {}
for k, v in pairs(SETTING_KEYS) do
	local raw = core.settings:get("store." .. k)
	cfg[k] = raw and raw ~= "" and raw or v
end
cfg.flush_interval   = tonumber(cfg.flush_interval)   or 10
cfg.max_balance      = tonumber(cfg.max_balance)      or 1e15
cfg.ledger_page_size = tonumber(cfg.ledger_page_size) or 20

----------------------------------------------------------------------
-- Backend selection
----------------------------------------------------------------------

smp_store._chosen_backend = nil -- string

-- E-21 (ruled 2026-09-25): `auto` must actually probe for lsqlite3.
-- The old guard tested `package.loaded["lsqlite3"] ~= nil`, which is
-- false unless something already required the library — nobody does —
-- so `auto` silently never chose sqlite. Probe exactly the way
-- `backends/sqlite.lua:41` loads it: pcall(require, …), guarded on the
-- insecure environment (without it the sqlite backend refuses to start
-- anyway), and cache the result. A build without the library answers
-- false and `auto` falls back to mod_storage; a successful probe also
-- populates `package.loaded`, so the backend finds it warm.
local sqlite_probe -- nil = not tried yet
local function sqlite_available()
	if package.loaded and package.loaded["lsqlite3"] ~= nil then
		return true
	end
	if sqlite_probe ~= nil then
		return sqlite_probe
	end
	if not core.request_insecure_environment
	   or not core.request_insecure_environment() then
		sqlite_probe = false
		return false
	end
	local ok, mod = pcall(require, "lsqlite3")
	sqlite_probe = ok and mod ~= nil
	return sqlite_probe
end

local function pick_backend()
	local want = cfg.backend
	if want == "auto" then
		-- Try sqlite first if available; otherwise mod_storage.
		if sqlite_available() then
			return "sqlite"
		end
		return "mod_storage"
	elseif want == "sqlite" then
		return "sqlite"
	elseif want == "mod_storage" then
		return "mod_storage"
	elseif want == "postgres" then
		return "postgres"
	end
	-- Unknown value: behave like auto.
	core.log("warning", "[smp_store] unknown store.backend=" .. tostring(want)
		.. " — falling back to auto")
	if sqlite_available() then
		return "sqlite"
	end
	return "mod_storage"
end

-- A driver is a table of functions (see STORAGE.md). Backends live in
-- backends/<name>.lua and either return a driver or nil + reason.
local function try_load(name)
	local modpath = core.get_modpath("smp_store")
	local path = modpath .. "/backends/" .. name .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then
		return nil, "loadfile failed: " .. tostring(err)
	end
	local env = setmetatable({
		core = core,
		S    = S,
		cfg  = cfg,
	}, { __index = _G })
	setfenv(chunk, env)
	local ok, driver = pcall(chunk)
	if not ok then
		return nil, "backend error: " .. tostring(driver)
	end
	if type(driver) ~= "table" then
		return nil, "backend did not return a driver table"
	end
	if type(driver.migrate) ~= "function" or
	   type(driver.get_player) ~= "function" then
		return nil, "backend missing required methods"
	end
	return driver, nil
end

local function load_backend(name)
	local driver, err = try_load(name)
	if not driver then
		core.log("error", "[smp_store] backend '" .. name .. "' unavailable: " .. tostring(err))
		return nil
	end
	return driver
end

smp_store._backend_name = nil
smp_store._driver = nil

local function start_backend()
	local want = pick_backend()
	local driver = load_backend(want)
	if not driver and want ~= "mod_storage" then
		core.log("warning", "[smp_store] falling back to mod_storage")
		want = "mod_storage"
		driver = load_backend(want)
	end
	if not driver then
		error("[smp_store] no backend could be started")
	end
	local ok, err = pcall(driver.migrate)
	if not ok then
		error("[smp_store] migrate failed: " .. tostring(err))
	end
	smp_store._driver = driver
	smp_store._backend_name = want
	core.log("action", "[smp_store] backend active: " .. want)
end

----------------------------------------------------------------------
-- Public API (the only thing feature mods touch)
----------------------------------------------------------------------

smp_store.api = {}

function smp_store.api.get_player(name)
	assert(smp_store._driver, "store not started")
	return smp_store._driver.get_player(name)
end

function smp_store.api.upsert_player(record)
	assert(smp_store._driver, "store not started")
	return smp_store._driver.upsert_player(record)
end

function smp_store.api.all_player_names()
	assert(smp_store._driver, "store not started")
	return smp_store._driver.all_player_names()
end

function smp_store.api.update_player_field(name, key, value)
	assert(smp_store._driver, "store not started")
	return smp_store._driver.update_player_field(name, key, value)
end

function smp_store.api.append_ledger(entry)
	assert(smp_store._driver, "store not started")
	return smp_store._driver.append_ledger(entry)
end

function smp_store.api.ledger_for(actor, page, size)
	assert(smp_store._driver, "store not started")
	size = size or cfg.ledger_page_size
	return smp_store._driver.ledger_for(actor, page, size)
end

-- History lists (D12, 2026-09-24): one append-only list per (kind, name),
-- backed by every driver.
--   kind     string namespace — "sell", "auction", ... (extensible)
--   name     player name; offline names work, like the rest of the store
--   entry    plain table, stored verbatim; the driver stamps `t = os.time()`
--            unless the caller set one
--   cap      optional prune window; default 100 (sell.history_size default)
-- Appends are FIFO-pruned to `cap`, keeping the newest entries. Returns
-- `id`: a monotonic integer *per (kind, name)* — 1, 2, 3, ..., continuing
-- across appends and prunes (and restarts), never a float. Money anywhere
-- inside an entry is integer cents; it is stored verbatim, never computed
-- on. No yields anywhere in this path (shared §2.3).
function smp_store.api.append_history(kind, name, entry, cap)
	assert(smp_store._driver, "store not started")
	assert(type(kind) == "string" and kind ~= "", "append_history: bad kind")
	assert(type(name) == "string" and name ~= "", "append_history: bad name")
	assert(type(entry) == "table", "append_history: bad entry")
	cap = cap or 100
	return smp_store._driver.append_history(kind, name, entry, cap)
end

function smp_store.api.begin()
	if smp_store._driver.begin then smp_store._driver.begin() end
end

function smp_store.api.commit()
	if smp_store._driver.commit then smp_store._driver.commit() end
end

function smp_store.api.rollback()
	if smp_store._driver.rollback then smp_store._driver.rollback() end
end

-- Convenience: load-or-create a player record with sane defaults.
-- Returns the record (possibly freshly created).
function smp_store.api.ensure_player(name)
	local r = smp_store.api.get_player(name)
	if r then return r end
	r = {
		name = name,
		first_join = os.time(),
		money = 0,
		shards = 0,
		shards_for_playtime = 0,
		playtime = 0,
		rank = {},
		homes = {},
		stats = {},
		social = {},
		quickbuy = {},
		keys = {},
	}
	smp_store.api.upsert_player(r)
	return r
end

-- Add money to a player with a cap. Used by every mod that grants cash.
-- Returns the actual delta applied (which may be less than requested if
-- the cap would be exceeded). 0 means nothing changed.
function smp_store.api.add_money(name, cents, reason, ref)
	local rec = smp_store.api.ensure_player(name)
	local cap = cfg.max_balance - rec.money
	local delta = cents
	if delta > cap then delta = cap end
	if delta <= 0 then return 0 end
	rec.money = rec.money + delta
	smp_store.api.upsert_player(rec)
	smp_store.api.append_ledger({
		time = os.time(),
		type = reason or "admin",
		actor = name,
		counterparty = "",
		amount = delta,
		currency = "money",
		item_key = "",
		qty = 0,
		ref = ref or "",
		flags = {},
	})
	return delta
end

-- Remove money, refusing if it would go negative. Returns the actual
-- delta removed (negative cents) or nil if the player can't afford it.
function smp_store.api.take_money(name, cents, reason, ref)
	local rec = smp_store.api.ensure_player(name)
	if rec.money < cents then return nil end
	rec.money = rec.money - cents
	smp_store.api.upsert_player(rec)
	smp_store.api.append_ledger({
		time = os.time(),
		type = reason or "admin",
		actor = name,
		counterparty = "",
		amount = -cents,
		currency = "money",
		item_key = "",
		qty = 0,
		ref = ref or "",
		flags = {},
	})
	return cents
end

-- Set money to an exact value (admin only — feature mods never call this).
-- Used by /eco set and by the leaderboard rebuild path.
function smp_store.api.set_money(name, cents, reason, ref)
	local rec = smp_store.api.ensure_player(name)
	local before = rec.money
	rec.money = cents
	smp_store.api.upsert_player(rec)
	smp_store.api.append_ledger({
		time = os.time(),
		type = reason or "admin",
		actor = name,
		counterparty = "",
		amount = cents - before,
		currency = "money",
		item_key = "",
		qty = 0,
		ref = ref or "",
		flags = {},
	})
	return cents
end

-- Same three helpers for shards.
function smp_store.api.add_shards(name, n, reason, ref)
	local rec = smp_store.api.ensure_player(name)
	rec.shards = rec.shards + n
	smp_store.api.upsert_player(rec)
	smp_store.api.append_ledger({
		time = os.time(),
		type = reason or "shard_award",
		actor = name,
		counterparty = "",
		amount = n,
		currency = "shards",
		item_key = "",
		qty = 0,
		ref = ref or "",
		flags = {},
	})
	return n
end

function smp_store.api.take_shards(name, n, reason, ref)
	local rec = smp_store.api.ensure_player(name)
	if rec.shards < n then return nil end
	rec.shards = rec.shards - n
	smp_store.api.upsert_player(rec)
	smp_store.api.append_ledger({
		time = os.time(),
		type = reason or "shard_spend",
		actor = name,
		counterparty = "",
		amount = -n,
		currency = "shards",
		item_key = "",
		qty = 0,
		ref = ref or "",
		flags = {},
	})
	return n
end

----------------------------------------------------------------------
-- /smp backend — read-only status for operators.
----------------------------------------------------------------------

core.register_chatcommand("smp_backend", {
	params = "",
	description = S("Show the active storage backend (FriedcakeSMP admin)."),
	privs = { smp_admin = true },
	func = function(player_name, _)
		-- E-12 (ruled 2026-09-25): player-facing output goes through
		-- the translator (AGENTS hard rule 7); the raw tag stays in
		-- the server log, which is not player-facing. Unobserved
		-- wording, so no terminal full stop (shared 00-conventions
		-- §0.5).
		local backend_name = smp_store._backend_name or "?"
		core.chat_send_player(player_name,
			S("Storage backend: @1", backend_name))
		core.log("action", "[smp_store] backend = " .. backend_name)
		return true
	end,
})

----------------------------------------------------------------------
-- Flush + shutdown wiring
----------------------------------------------------------------------

local function flush_all()
	if smp_store._driver and smp_store._driver.flush then
		pcall(smp_store._driver.flush)
	end
end

core.register_on_shutdown(function()
	flush_all()
	if smp_store._driver and smp_store._driver.close then
		pcall(smp_store._driver.close)
	end
end)

local flush_timer = 0
core.register_globalstep(function(dtime)
	flush_timer = flush_timer + dtime
	if flush_timer >= cfg.flush_interval then
		flush_timer = 0
		flush_all()
	end
end)

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------

start_backend()
