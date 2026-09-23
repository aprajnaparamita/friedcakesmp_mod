-- FriedcakeSMP — smp_store sqlite backend
--
-- Single SQLite file at <worlddir>/friedcake_store.sqlite. Schema is the
-- same shape as Postgres will use; this is the canonical reference.
--
-- Requirements:
--   * `smp_store` listed in `secure.trusted_mods` in minetest.conf
--   * The engine built with `lsqlite3` (most distributions are)
--
-- If either is missing we abort with a clear error rather than silently
-- falling back — falling back would lose the SQL contract.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = S or function(s, ...) return s end

-- Lua numbers are doubles; SQLite REAL is fine for non-money fields.
-- Money is INTEGER cents, which fits in int64.

local function die(msg)
	core.log("error", "[smp_store:sqlite] " .. msg)
	error(msg)
end

-- 1. Try to obtain the insecure environment.
if not core.request_insecure_environment then
	die("core.request_insecure_environment is not available; the engine was "
		.. "built without insecure support. Use store.backend = mod_storage instead.")
end
local insecure = core.request_insecure_environment()
if not insecure then
	die("insecure environment denied. Add `secure.trusted_mods = smp_store` "
		.. "to minetest.conf and restart the server.")
end

-- 2. Look up lsqlite3.
local sqlite3 = package.loaded["lsqlite3"] or insecure.loadlib and nil
if not sqlite3 then
	-- Try to require it from the engine's path.
	local ok, mod = pcall(require, "lsqlite3")
	if ok then sqlite3 = mod end
end
if not sqlite3 then
	die("lsqlite3 not loaded. Rebuild Luanti with -DENABLE_LUAJIT=ON "
		.. "(default) and -DBUILD_SERVER=ON; or use store.backend = mod_storage.")
end

-- 3. Open (or create) the database file in the world directory.
local worldpath = core.get_worldpath()
local dbpath = worldpath .. DIR_DELIM .. "friedcake_store.sqlite"

local db, open_err = sqlite3.open(dbpath)
if not db then
	die("sqlite3.open failed: " .. tostring(open_err))
end

-- Pragmas we want on every connection.
db:exec("PRAGMA journal_mode = WAL;")
db:exec("PRAGMA synchronous = NORMAL;")
db:exec("PRAGMA foreign_keys = ON;")

----------------------------------------------------------------------
-- Schema (canonical; Postgres mirrors this)
----------------------------------------------------------------------

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS players (
  name          TEXT PRIMARY KEY,
  first_join    INTEGER NOT NULL,
  money         INTEGER NOT NULL DEFAULT 0,
  shards        INTEGER NOT NULL DEFAULT 0,
  shards_for_playtime INTEGER NOT NULL DEFAULT 0,
  playtime      INTEGER NOT NULL DEFAULT 0,
  rank_json     TEXT NOT NULL DEFAULT '{}',
  homes_json    TEXT NOT NULL DEFAULT '{}',
  stats_json    TEXT NOT NULL DEFAULT '{}',
  social_json   TEXT NOT NULL DEFAULT '{}',
  quickbuy_json TEXT NOT NULL DEFAULT '{}',
  keys_json     TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS ledger (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  time         INTEGER NOT NULL,
  type         TEXT NOT NULL,
  actor        TEXT NOT NULL,
  counterparty TEXT NOT NULL DEFAULT '',
  amount       INTEGER NOT NULL DEFAULT 0,
  currency     TEXT NOT NULL DEFAULT 'money',
  item_key     TEXT NOT NULL DEFAULT '',
  qty          INTEGER NOT NULL DEFAULT 0,
  ref          TEXT NOT NULL DEFAULT '',
  flags_json   TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS ledger_actor_time ON ledger(actor, time DESC);
CREATE INDEX IF NOT EXISTS ledger_time       ON ledger(time DESC);
]]

----------------------------------------------------------------------
-- Prepared statements (lazily prepared)
----------------------------------------------------------------------

local stmts = {}

local function prepare(sql)
	if stmts[sql] then return stmts[sql] end
	local s, err = db:prepare(sql)
	if not s then die("prepare failed: " .. tostring(err) .. " for: " .. sql) end
	stmts[sql] = s
	return s
end

----------------------------------------------------------------------
-- JSON helpers (sqlite stores JSON in TEXT columns)
----------------------------------------------------------------------

local function to_json(v)
	if v == nil then return "{}" end
	if type(v) == "string" then return v end
	return core.write_json(v)
end

local function from_json(s)
	if not s or s == "" then return {} end
	local ok, t = pcall(core.parse_json, s)
	if ok and type(t) == "table" then return t end
	return {}
end

local function new_record(name)
	return {
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
end

----------------------------------------------------------------------
-- Driver
----------------------------------------------------------------------

local driver = {}

function driver.migrate()
	for stmt in SCHEMA:gmatch("[^;]+") do
		local s = stmt:gsub("^%s+", ""):gsub("%s+$", "")
		if s ~= "" then
			local _, err = db:exec(s .. ";")
			if err then die("schema exec failed: " .. tostring(err) .. " for: " .. s) end
		end
	end
	-- Migration for pre-`shards_for_playtime` tables: add the column if it is
	-- missing, so a world created before this field existed does not drop the
	-- shard-award counter on every upsert.
	local has_col = false
	for row in db:nrows("PRAGMA table_info(players)") do
		if row.name == "shards_for_playtime" then has_col = true end
	end
	if not has_col then
		db:exec("ALTER TABLE players ADD COLUMN shards_for_playtime INTEGER NOT NULL DEFAULT 0")
	end
	return true
end

function driver.get_player(name)
	if not name or name == "" then return nil end
	local s = prepare(
		"SELECT first_join, money, shards, shards_for_playtime, playtime, "
		.. "rank_json, homes_json, stats_json, social_json, quickbuy_json, keys_json "
		.. "FROM players WHERE name = ?")
	s:bind(1, name)
	local row = s:step()
	if row ~= sqlite3.ROW then
		s:reset()
		return nil
	end
	local r = new_record(name)
	r.first_join = s:get_value(0) or r.first_join
	r.money     = s:get_value(1) or 0
	r.shards    = s:get_value(2) or 0
	r.shards_for_playtime = s:get_value(3) or 0
	r.playtime  = s:get_value(4) or 0
	r.rank      = from_json(s:get_value(5))
	r.homes     = from_json(s:get_value(6))
	r.stats     = from_json(s:get_value(7))
	r.social    = from_json(s:get_value(8))
	r.quickbuy  = from_json(s:get_value(9))
	r.keys      = from_json(s:get_value(10))
	s:reset()
	return r
end

function driver.upsert_player(record)
	if not record or not record.name then return end
	local s = prepare([[
		INSERT INTO players
		  (name, first_join, money, shards, shards_for_playtime, playtime,
		   rank_json, homes_json, stats_json, social_json, quickbuy_json, keys_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(name) DO UPDATE SET
		  first_join    = excluded.first_join,
		  money         = excluded.money,
		  shards        = excluded.shards,
		  shards_for_playtime = excluded.shards_for_playtime,
		  playtime      = excluded.playtime,
		  rank_json     = excluded.rank_json,
		  homes_json    = excluded.homes_json,
		  stats_json    = excluded.stats_json,
		  social_json   = excluded.social_json,
		  quickbuy_json = excluded.quickbuy_json,
		  keys_json     = excluded.keys_json
	]])
	s:bind(1,  record.name)
	s:bind(2,  record.first_join or os.time())
	s:bind(3,  math.floor(record.money or 0))
	s:bind(4,  math.floor(record.shards or 0))
	s:bind(5,  math.floor(record.shards_for_playtime or 0))
	s:bind(6,  math.floor(record.playtime or 0))
	s:bind(7,  to_json(record.rank))
	s:bind(8,  to_json(record.homes))
	s:bind(9,  to_json(record.stats))
	s:bind(10, to_json(record.social))
	s:bind(11, to_json(record.quickbuy))
	s:bind(12, to_json(record.keys))
	local _, err = s:step()
	s:reset()
	if err then die("upsert_player failed: " .. tostring(err)) end
end

function driver.all_player_names()
	local s = prepare("SELECT name FROM players ORDER BY name")
	local out = {}
	for row in s:nrows() do
		out[#out + 1] = row.name
	end
	s:reset()
	return out
end

function driver.update_player_field(name, key, value)
	-- Whitelisted fields only — money / shards / playtime are atomic columns;
	-- the JSON blobs have their own column.
	local cols = {
		money    = "money",
		shards   = "shards",
		playtime = "playtime",
	}
	local col = cols[key]
	if col then
		local s = prepare("UPDATE players SET " .. col .. " = ? WHERE name = ?")
		s:bind(1, math.floor(value))
		s:bind(2, name)
		s:step(); s:reset()
	elseif key == "rank" or key == "homes" or key == "stats"
	    or key == "social" or key == "quickbuy" or key == "keys" then
		local s = prepare("UPDATE players SET " .. key .. "_json = ? WHERE name = ?")
		s:bind(1, to_json(value))
		s:bind(2, name)
		s:step(); s:reset()
	end
end

function driver.append_ledger(entry)
	entry.time = entry.time or os.time()
	local flags_json = type(entry.flags) == "string"
	                     and entry.flags or core.write_json(entry.flags or {})
	local s = prepare([[
		INSERT INTO ledger
		  (time, type, actor, counterparty, amount, currency, item_key, qty, ref, flags_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	]])
	s:bind(1,  entry.time)
	s:bind(2,  entry.type or "admin")
	s:bind(3,  entry.actor or "")
	s:bind(4,  entry.counterparty or "")
	s:bind(5,  math.floor(entry.amount or 0))
	s:bind(6,  entry.currency or "money")
	s:bind(7,  entry.item_key or "")
	s:bind(8,  math.floor(entry.qty or 0))
	s:bind(9,  entry.ref or "")
	s:bind(10, flags_json)
	local _, err = s:step()
	s:reset()
	if err then die("append_ledger failed: " .. tostring(err)) end

	-- Fetch the rowid we just inserted.
	local id_stmt = prepare("SELECT last_insert_rowid()")
	local id_val = id_stmt:step()
	id_stmt:reset()
	-- id_val is a row; pull the first column.
	if type(id_val) == "table" then
		return tonumber(id_val[1]) or tonumber(id_val.id) or 0
	end
	return tonumber(id_val) or 0
end

function driver.ledger_for(actor, page, size)
	size = size or 20
	page = page or 1
	local offset = (page - 1) * size

	local count_s = prepare(
		"SELECT COUNT(*) FROM ledger WHERE actor = ? OR ? = ''")
	count_s:bind(1, actor or "")
	count_s:bind(2, actor or "")
	local total = tonumber(count_s:step() or "0") or 0
	count_s:reset()

	local s = prepare([[
		SELECT id, time, type, actor, counterparty, amount,
		       currency, item_key, qty, ref, flags_json
		FROM ledger
		WHERE actor = ? OR ? = ''
		ORDER BY id DESC
		LIMIT ? OFFSET ?
	]])
	s:bind(1, actor or "")
	s:bind(2, actor or "")
	s:bind(3, size)
	s:bind(4, offset)

	local entries = {}
	for row in s:nrows() do
		entries[#entries + 1] = {
			id = tonumber(row.id),
			time = tonumber(row.time),
			type = row.type,
			actor = row.actor,
			counterparty = row.counterparty,
			amount = tonumber(row.amount),
			currency = row.currency,
			item_key = row.item_key,
			qty = tonumber(row.qty),
			ref = row.ref,
			flags = from_json(row.flags_json),
		}
	end
	s:reset()
	return entries, math.max(1, math.ceil(total / size))
end

function driver.flush()
	-- WAL already flushes per-commit; nothing further to do.
end

function driver.close()
	for _, s in pairs(stmts) do s:finalize() end
	stmts = {}
	db:close()
end

return driver
