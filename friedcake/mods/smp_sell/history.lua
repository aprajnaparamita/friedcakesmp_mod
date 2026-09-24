-- FriedcakeSMP — smp_sell/history.lua
--
-- Per-player sell history (f02 §4.7, §5, §7 `sell.history_size`).
--
-- WHY THIS IS NOT IN smp_store
-- ----------------------------
-- shared §2.2 puts sell history in a `smp_store` table and f02 §6 calls
-- `smp_store.append_sell_history(player, receipt)`. `smp_store` today exposes
-- no such operation, and its sqlite/postgres backends persist exactly six
-- nested player blobs (rank, homes, stats, social, quickbuy, keys), so a new
-- top-level `sell_history` field on the player record would be silently
-- dropped by those backends. Rather than half-implement persistence that
-- breaks on the recommended backend, smp_sell keeps the history in its OWN
-- mod-storage namespace and the smp_store extension is proposed to the
-- integrator in f02 §11.
--
-- The seam is deliberate: `_read` / `_write` are the only two places that
-- touch storage, so moving this to a store table later is a local change.
--
-- WIRING (D12, 2026-09-24): `append()` now delegates to
-- `smp_store.api.append_history(kind, name, entry, cap) -> id` when the API
-- is present (mod loaded after `smp_store`), falling back to local mod storage.
-- Reads stay local until `smp_store.api.sell_history_for` lands.
--
-- Layout (keys in smp_sell's core.get_mod_storage()):
--   sellhist:<player>  ->  { version = 1, next_id = N, entries = { ... } }
--   entries are stored NEWEST FIRST and trimmed to `history_size`.
--
-- Entry schema is exactly f02 §5, plus two additive per-line money fields
-- (server_cents, order_cents) so `/sellhistory` can render a line without
-- re-deriving unit prices. Those two are PROPOSED (f02 §10 V-90).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local cfg = ...   -- loadfile'd with the config table as the single argument

local H = {}

local storage = core.get_mod_storage()

local KEY_PREFIX = "sellhist:"

----------------------------------------------------------------------
-- Storage seam
----------------------------------------------------------------------

function H._read(name)
	local raw = storage:get_string(KEY_PREFIX .. name)
	if raw == nil or raw == "" then return nil end
	local ok, doc = pcall(core.parse_json, raw)
	if not ok or type(doc) ~= "table" then
		core.log("warning", "[smp_sell] unreadable sell history for " .. name)
		return nil
	end
	if type(doc.entries) ~= "table" then doc.entries = {} end
	doc.next_id = tonumber(doc.next_id) or 1
	doc.version = tonumber(doc.version) or 1
	return doc
end

function H._write(name, doc)
	storage:set_string(KEY_PREFIX .. name, core.write_json(doc))
end

----------------------------------------------------------------------
-- Normalisation
----------------------------------------------------------------------

-- Coerce an entry to the §5 schema. Money fields are integer cents;
-- quantities are integers. Anything else is dropped rather than stored.
local function sanitize_line(l)
	if type(l) ~= "table" then return nil end
	return {
		item         = tostring(l.item or ""),
		qty          = math.floor(tonumber(l.qty) or 0),
		server       = math.floor(tonumber(l.server) or 0),
		order        = math.floor(tonumber(l.order) or 0),
		order_ids    = l.order_ids or {},
		server_cents = math.floor(tonumber(l.server_cents) or 0),
		order_cents  = math.floor(tonumber(l.order_cents) or 0),
	}
end

local function sanitize_entry(e, fallback_id, fallback_time)
	local lines = {}
	for _, l in ipairs(e.lines or {}) do
		local sl = sanitize_line(l)
		if sl then lines[#lines + 1] = sl end
	end
	return {
		id           = math.floor(tonumber(e.id) or fallback_id),
		time         = math.floor(tonumber(e.time) or fallback_time),
		source       = tostring(e.source or "container"),
		lines        = lines,
		server_total = math.floor(tonumber(e.server_total) or 0),
		order_total  = math.floor(tonumber(e.order_total) or 0),
	}
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Append one sale. Returns the stored entry (with its id).
-- Delegates to smp_store.api.append_history when available (D12),
-- otherwise falls back to local mod storage.
-- During transition, writes to BOTH so local reads still work.
function H.append(name, entry)
	if type(name) ~= "string" or name == "" then return nil end

	local stored = nil
	local used_store = false

	-- Try the smp_store history API first (D12: append_history(kind, name, entry, cap) -> id).
	if smp_store and smp_store.api and smp_store.api.append_history then
		local cap = math.max(1, math.floor(tonumber(cfg.history_size) or 100))
		local ok, result = pcall(smp_store.api.append_history, "sell", name, entry, cap)
		if ok and result then
			-- The store API returns the assigned id (integer).
			-- Build a normalized entry for callers.
			stored = sanitize_entry(entry or {}, result, os.time())
			stored.id = result
			used_store = true
		elseif not ok then
			core.log("warning", "[smp_sell] smp_store append_history failed for " .. name
				.. ": " .. tostring(result) .. " — falling back to local storage")
		end
	end

	-- Always write to local mod storage so reads (list/page) work during transition.
	-- When smp_store.api.sell_history_for lands, we can stop writing here.
	local doc = H._read(name) or { version = 1, next_id = 1, entries = {} }
	local local_stored = sanitize_entry(entry or {}, doc.next_id, os.time())
	local_stored.id = doc.next_id
	doc.next_id = doc.next_id + 1

	-- Newest first.
	table.insert(doc.entries, 1, local_stored)

	-- Trim to the configured window (f02 §7, default 100).
	local keep = math.max(1, math.floor(tonumber(cfg.history_size) or 100))
	while #doc.entries > keep do
		table.remove(doc.entries)
	end

	H._write(name, doc)

	-- Return the store entry if we used it (it has the global monotonic ID),
	-- otherwise return the local entry.
	if used_store and stored then
		return stored
	end
	return local_stored
end

-- All entries, newest first.
function H.list(name)
	local doc = H._read(name)
	return doc and doc.entries or {}
end

function H.count(name)
	return #H.list(name)
end

-- One page of history. Returns (entries, total_pages, total_entries).
function H.page(name, page, size)
	size = math.max(1, math.floor(tonumber(size) or cfg.history_page_size or 5))
	page = math.max(1, math.floor(tonumber(page) or 1))
	local all = H.list(name)
	local total_pages = math.max(1, math.ceil(#all / size))
	if page > total_pages then page = total_pages end
	local out = {}
	local first = (page - 1) * size + 1
	for i = first, math.min(first + size - 1, #all) do
		out[#out + 1] = all[i]
	end
	return out, total_pages, #all
end

function H.clear(name)
	storage:set_string(KEY_PREFIX .. name, "")
end

return H