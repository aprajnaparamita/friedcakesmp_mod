-- FriedcakeSMP — smp_store mod_storage backend
--
-- Storage layout (all keys live in smp_store's core.get_mod_storage()):
--
--   player:<name>   -> JSON record
--   ledger:nextid   -> integer string, next id to assign
--   ledger:NNNNN    -> JSON entry
--   history:<kind>:<name>:nextid -> integer string, next id for this list
--   history:<kind>:<name>:NNNNN  -> JSON history entry
--
-- All access goes through core.write_json / core.parse_json / get_string /
-- set_string. Writes are cheap; reads are O(N) over all keys when we need
-- to enumerate.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = S or function(s, ...) return s end

local mod_storage = core.get_mod_storage()

----------------------------------------------------------------------
-- JSON helpers
----------------------------------------------------------------------

local function read_json(key)
	local s = mod_storage:get_string(key)
	if s == "" then return nil end
	local ok, t = pcall(core.parse_json, s)
	if not ok or type(t) ~= "table" then return nil end
	return t
end

local function write_json(key, value)
	mod_storage:set_string(key, core.write_json(value))
end

local function read_int(key, default)
	local s = mod_storage:get_string(key)
	if s == "" then return default end
	local n = tonumber(s)
	if not n then return default end
	return math.floor(n)
end

local function write_int(key, n)
	mod_storage:set_string(key, tostring(math.floor(n)))
end

local function new_record(name)
	return {
		name = name,
		first_join = os.time(),
		money = 0,
		shards = 0,
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
	-- Nothing to do. Keys are created on demand.
	return true
end

function driver.get_player(name)
	if not name or name == "" then return nil end
	local r = read_json("player:" .. name)
	if not r then return nil end
	-- Defensive defaults for fields added after a record was first written.
	r.name = name
	r.money = tonumber(r.money) or 0
	r.shards = tonumber(r.shards) or 0
	r.playtime = tonumber(r.playtime) or 0
	r.rank = type(r.rank) == "table" and r.rank or {}
	r.homes = type(r.homes) == "table" and r.homes or {}
	r.stats = type(r.stats) == "table" and r.stats or {}
	r.social = type(r.social) == "table" and r.social or {}
	r.quickbuy = type(r.quickbuy) == "table" and r.quickbuy or {}
	r.keys = type(r.keys) == "table" and r.keys or {}
	return r
end

function driver.upsert_player(record)
	if not record or not record.name then return end
	write_json("player:" .. record.name, record)
end

function driver.all_player_names()
	local out = {}
	local list = mod_storage:get_keys()
	for _, k in ipairs(list) do
		local n = k:match("^player:(.+)$")
		if n then out[#out + 1] = n end
	end
	return out
end

function driver.update_player_field(name, key, value)
	local r = driver.get_player(name)
	if not r then return end
	r[key] = value
	driver.upsert_player(r)
end

function driver.append_ledger(entry)
	local next_id = read_int("ledger:nextid", 1)
	entry.id = next_id
	entry.time = entry.time or os.time()
	-- Serialize nested flags as JSON.
	if type(entry.flags) ~= "string" then
		entry.flags_json = core.write_json(entry.flags or {})
		entry.flags = nil
	else
		entry.flags_json = entry.flags
		entry.flags = nil
	end
	write_json("ledger:" .. string.format("%010d", next_id), entry)
	write_int("ledger:nextid", next_id + 1)
	return next_id
end

function driver.ledger_for(actor, page, size)
	size = size or 20
	page = page or 1
	-- We walk all ledger keys newest-first. This is O(N) per page; the
	-- mod_storage backend is meant for small servers. SQLite/Postgres
	-- replace this with an index.
	local list = mod_storage:get_keys()
	local ids = {}
	for _, k in ipairs(list) do
		local n = tonumber(k:match("^ledger:(%d+)$"))
		if n then ids[#ids + 1] = n end
	end
	table.sort(ids, function(a, b) return a > b end)

	-- Collect the actor-filtered set newest-first, THEN page over it. The
	-- previous code paged by the global id position while filtering by
	-- actor, so pages ≥ 2 could duplicate or omit rows.
	local all = {}
	for _, id in ipairs(ids) do
		local e = read_json("ledger:" .. string.format("%010d", id))
		if e and (actor == nil or actor == "" or e.actor == actor) then
			all[#all + 1] = e
		end
	end
	local total = #all
	local start = (page - 1) * size + 1
	local entries = {}
	for i = start, math.min(start + size - 1, total) do
		entries[#entries + 1] = all[i]
	end
	return entries, math.max(1, math.ceil(total / size))
end

function driver.append_history(kind, name, entry, cap)
	-- One append-only list per (kind, name), keyed exactly like the ledger,
	-- scoped to the owner. Ids are monotonic per (kind, name): the nextid
	-- key is never rewound by pruning.
	cap = math.max(1, math.floor(tonumber(cap) or 100))
	local prefix = "history:" .. kind .. ":" .. name .. ":"
	local next_id = read_int(prefix .. "nextid", 1)
	entry.id = next_id
	entry.t = entry.t or os.time()
	write_json(prefix .. string.format("%010d", next_id), entry)
	write_int(prefix .. "nextid", next_id + 1)

	-- FIFO prune: keep the newest `cap` entries, drop the oldest ids.
	-- set_string(key, "") removes the key, as the engine does.
	local ids = {}
	for _, k in ipairs(mod_storage:get_keys()) do
		if k:sub(1, #prefix) == prefix then
			local n = tonumber(k:sub(#prefix + 1))   -- nil for the nextid key
			if n then ids[#ids + 1] = n end
		end
	end
	if #ids > cap then
		table.sort(ids)
		for i = 1, #ids - cap do
			mod_storage:set_string(prefix .. string.format("%010d", ids[i]), "")
		end
	end
	return next_id
end

function driver.flush()
	-- mod_storage writes are immediate; nothing to flush.
end

function driver.close()
	-- Nothing to close.
end

return driver
