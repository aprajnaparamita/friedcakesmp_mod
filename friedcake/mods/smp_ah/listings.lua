-- FriedcakeSMP — smp_ah/listings.lua
--
-- In-memory listing store with the indexes f03 §4.15 requires, plus
-- JSON persistence through the mod's own StorageRef.
--
--   "Indexes. In-memory maps from item key to listing ids sorted by unit
--    price, and from search token to listing ids, so routing, Quick Buy and
--    search avoid full scans."                                       (f03 §4.15)
--
-- Indexes maintained here:
--
--   by_id      [id]           -> listing record
--   by_seller  [name]         -> { [id] = true }
--   by_m1      [M1 key]       -> array of {id, unit}, kept sorted by unit price
--                                ascending (routing for f04, Quick Buy for f05)
--   by_m2      [M2 key]       -> { [id] = true }
--   tokens     [token]        -> { [id] = true }   (search vocabulary)
--   id_tokens  [id]           -> { token, ... }    (for index removal)
--
-- Every index holds ACTIVE listings only. Expiry is evaluated lazily as well
-- (`is_active`), so a listing that has passed `expires` but has not been
-- swept yet is never sold, routed or rendered.
--
-- Money is integer cents everywhere (shared §0.7). Nothing in this file
-- yields (shared §2.3): it is pure table manipulation plus synchronous
-- storage writes.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_ah = smp_ah or {}

local listings = {}
smp_ah.listings = listings

----------------------------------------------------------------------
-- Tunables (set by init.lua from the ah.* settings; defaults are the
-- PROPOSED values of f03 §7)
----------------------------------------------------------------------

local cfg = {
	page_size       = 45,
	history_page    = 100,   -- f03 §7 `ah.history` LIVE [S23]
	history_pages   = 10,    -- f03 §7 `ah.history` LIVE [S23]
	listing_duration = 172800,
	reclaim_days    = 30,
}

function listings.configure(t)
	for k, v in pairs(t or {}) do
		if cfg[k] ~= nil and type(cfg[k]) == type(v) then cfg[k] = v end
	end
	return cfg
end

function listings.config() return cfg end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local state = {
	next_id   = 1,
	next_txid = 1,
	by_id     = {},
	by_seller = {},
	by_m1     = {},
	by_m2     = {},
	tokens    = {},
	id_tokens = {},
	tx        = {},   -- newest first, capped at history_page * history_pages
	tx_ids    = {},   -- oldest first, for trimming storage keys
	sweep_at  = 1,    -- amortised sweep cursor (shared §2.7)
	dirty     = {},   -- [storage_key] = json_string | false (false = delete)
}

local storage = nil   -- StorageRef (attached by init.lua)

-- Forward declaration: `load` (below) rebuilds the indexes record by record.
local index_insert

function listings.attach_storage(ref)
	storage = ref
end

function listings.storage() return storage end

--- Millisecond wall-clock timestamp for `sold_at_ms` (f03 §5, api.PurchaseItem
-- [S23]). `os.time()` has one-second resolution, so the sub-second part comes
-- from the engine's microsecond clock. Integer arithmetic only.
function listings.now_ms()
	local us = 0
	if core and type(core.get_us_time) == "function" then
		us = core.get_us_time() % 1000000
	end
	return os.time() * 1000 + math.floor(us / 1000)
end

----------------------------------------------------------------------
-- Persistence helpers
----------------------------------------------------------------------

local function lkey(id) return "ah:l:" .. tostring(id) end
local function tkey(id) return "ah:t:" .. tostring(id) end

local function mark(key, value)
	state.dirty[key] = value
end

local function encode(v)
	if not core or type(core.write_json) ~= "function" then return nil end
	local ok, s = pcall(core.write_json, v)
	if not ok then return nil end
	return s
end

local function decode(s)
	if type(s) ~= "string" or s == "" then return nil end
	if not core or type(core.parse_json) ~= "function" then return nil end
	local ok, v = pcall(core.parse_json, s)
	if not ok then return nil end
	return v
end

-- Money and counter fields must come back as integers: JSON has no integer
-- type and a float cent value would violate shared §0.7.
local INT_FIELDS = { "price", "unit_price", "qty", "created", "expires", "sold_at_ms" }

local function normalise(rec)
	if type(rec) ~= "table" then return nil end
	rec.id       = math.floor(tonumber(rec.id) or 0)
	rec.version  = math.floor(tonumber(rec.version) or 1)
	rec.state    = rec.state or "active"
	rec.seller   = rec.seller or ""
	rec.stack    = rec.stack or ""
	rec.key      = rec.key or ""
	rec.key_m1   = rec.key_m1 or ""
	rec.key_m2   = rec.key_m2 or rec.key or ""
	rec.name     = rec.name or ""
	rec.count    = math.floor(tonumber(rec.count) or 1)
	for _, f in ipairs(INT_FIELDS) do
		rec[f] = math.floor(tonumber(rec[f]) or 0)
	end
	if type(rec.display) ~= "table" then rec.display = { name = rec.name } end
	rec.display.name = rec.display.name or rec.name
	if type(rec.display.ench) ~= "table" then rec.display.ench = {} end
	if type(rec.display.lore) ~= "table" then rec.display.lore = {} end
	return rec
end

function listings.flush()
	if not storage then return 0 end
	local n = 0
	for key, value in pairs(state.dirty) do
		if value == false then
			if type(storage.remove) == "function" then
				storage:remove(key)
			else
				storage:set_string(key, "")
			end
		else
			storage:set_string(key, value)
		end
		n = n + 1
	end
	state.dirty = {}
	storage:set_string("ah:seq", tostring(state.next_id))
	storage:set_string("ah:txseq", tostring(state.next_txid))
	return n
end

function listings.dirty_count()
	local n = 0
	for _ in pairs(state.dirty) do n = n + 1 end
	return n
end

--- Rebuild the in-memory tables and every index from storage.
-- Called once at start-up (shared §2.2: "In-memory indexes are rebuilt at
-- start-up").
function listings.load()
	listings.reset(true)
	if not storage then return 0 end
	local keys_list
	if type(storage.get_keys) == "function" then
		keys_list = storage:get_keys()
	else
		keys_list = {}
	end
	local loaded = 0
	local seq = tonumber(storage:get_string("ah:seq")) or 1
	local txseq = tonumber(storage:get_string("ah:txseq")) or 1
	for _, key in ipairs(keys_list or {}) do
		local id = key:match("^ah:l:(%d+)$")
		if id then
			local rec = normalise(decode(storage:get_string(key)))
			if rec and rec.id > 0 then
				index_insert(rec)
				loaded = loaded + 1
			end
		end
	end
	-- Transactions, newest first.
	local txs = {}
	for _, key in ipairs(keys_list or {}) do
		local id = key:match("^ah:t:(%d+)$")
		if id then
			local rec = decode(storage:get_string(key))
			if type(rec) == "table" and rec.id then
				rec.id = math.floor(tonumber(rec.id) or 0)
				rec.price = math.floor(tonumber(rec.price) or 0)
				txs[#txs + 1] = rec
			end
		end
	end
	table.sort(txs, function(a, b)
		if (a.sold_at_ms or 0) == (b.sold_at_ms or 0) then return a.id > b.id end
		return (a.sold_at_ms or 0) > (b.sold_at_ms or 0)
	end)
	local cap = cfg.history_page * cfg.history_pages
	for i = 1, math.min(#txs, cap) do
		state.tx[#state.tx + 1] = txs[i]
		state.tx_ids[#state.tx_ids + 1] = txs[i].id
	end
	state.next_id = math.max(seq, listings.max_id() + 1)
	state.next_txid = math.max(txseq, (state.tx[1] and state.tx[1].id or 0) + 1)
	state.dirty = {}
	return loaded
end

function listings.max_id()
	local m = 0
	for id in pairs(state.by_id) do
		if id > m then m = id end
	end
	return m
end

--- Drop everything. `keep_storage` leaves the persisted records alone.
function listings.reset(keep_storage)
	state.by_id, state.by_seller, state.by_m1, state.by_m2 = {}, {}, {}, {}
	state.tokens, state.id_tokens, state.tx, state.tx_ids = {}, {}, {}, {}
	state.sweep_at = 1
	state.dirty = {}
	if not keep_storage then
		state.next_id, state.next_txid = 1, 1
	end
end

----------------------------------------------------------------------
-- Search tokens
----------------------------------------------------------------------

-- Lower-case alphanumeric tokens of a display name plus the itemstring's own
-- components, so `/ah diamond`, `/ah diamon` (the observed query [F0114]) and
-- `/ah mcl_core:diamond` all find the same listings.
local function tokens_for(rec)
	local out, seen = {}, {}
	local function add(s)
		for tok in tostring(s):lower():gmatch("[%w]+") do
			if #tok >= 1 and not seen[tok] then
				seen[tok] = true
				out[#out + 1] = tok
			end
		end
	end
	add(rec.display and rec.display.name or "")
	add(rec.name or "")
	return out
end

local function index_tokens(rec)
	local toks = tokens_for(rec)
	state.id_tokens[rec.id] = toks
	for _, tok in ipairs(toks) do
		state.tokens[tok] = state.tokens[tok] or {}
		state.tokens[tok][rec.id] = true
	end
end

local function deindex_tokens(id)
	local toks = state.id_tokens[id]
	if not toks then return end
	for _, tok in ipairs(toks) do
		local set = state.tokens[tok]
		if set then
			set[id] = nil
			if next(set) == nil then state.tokens[tok] = nil end
		end
	end
	state.id_tokens[id] = nil
end

----------------------------------------------------------------------
-- M1 index (sorted by unit price, ascending)
----------------------------------------------------------------------

local function m1_insert(rec)
	if rec.key_m1 == "" then return end
	local arr = state.by_m1[rec.key_m1]
	if not arr then
		arr = {}
		state.by_m1[rec.key_m1] = arr
	end
	-- Binary search for the first entry with a greater unit price, so equal
	-- prices keep insertion order (oldest first) and the array stays sorted.
	local lo, hi = 1, #arr + 1
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if arr[mid].unit < rec.unit_price or
		   (arr[mid].unit == rec.unit_price and arr[mid].id < rec.id) then
			lo = mid + 1
		else
			hi = mid
		end
	end
	table.insert(arr, lo, { id = rec.id, unit = rec.unit_price })
end

local function m1_remove(rec)
	if rec.key_m1 == "" then return end
	local arr = state.by_m1[rec.key_m1]
	if not arr then return end
	for i, e in ipairs(arr) do
		if e.id == rec.id then
			table.remove(arr, i)
			break
		end
	end
	if #arr == 0 then state.by_m1[rec.key_m1] = nil end
end

----------------------------------------------------------------------
-- Index maintenance
----------------------------------------------------------------------

index_insert = function(rec)
	state.by_id[rec.id] = rec
	state.by_seller[rec.seller] = state.by_seller[rec.seller] or {}
	state.by_seller[rec.seller][rec.id] = true
	if rec.key_m2 ~= "" then
		state.by_m2[rec.key_m2] = state.by_m2[rec.key_m2] or {}
		state.by_m2[rec.key_m2][rec.id] = true
	end
	if rec.state == "active" then
		m1_insert(rec)
		index_tokens(rec)
	end
	return rec
end

-- The seller index is **complete**: every listing of the seller is reachable
-- here, regardless of state, so `Your Items` can offer expired ones for
-- reclaim. State filtering happens at query time (Your Items, reclaimable,
-- count_active). The M1 / M2 / search indexes hold only ACTIVE listings;
-- routing, Quick Buy and the board view must never offer a sold/expired one.
local function index_remove(rec, full)
	m1_remove(rec)
	deindex_tokens(rec.id)
	if rec.key_m2 and state.by_m2[rec.key_m2] then
		state.by_m2[rec.key_m2][rec.id] = nil
		if next(state.by_m2[rec.key_m2]) == nil then state.by_m2[rec.key_m2] = nil end
	end
	if full then
		if state.by_seller[rec.seller] then
			state.by_seller[rec.seller][rec.id] = nil
			if next(state.by_seller[rec.seller]) == nil then
				state.by_seller[rec.seller] = nil
			end
		end
		state.by_id[rec.id] = nil
	end
end

----------------------------------------------------------------------
-- Records
----------------------------------------------------------------------

-- `ItemStack:to_string()` is lossless — it carries name, count, wear and the
-- full metadata blob — so a listing can be persisted as one string and
-- rebuilt exactly (f03 §5 `stack = "mcl_core:diamond 64"`).
local function stack_count(itemstring)
	if type(ItemStack) == "function" then
		local ok, s = pcall(ItemStack, itemstring)
		if ok and s and not s:is_empty() then
			return math.max(1, math.floor(tonumber(s:get_count()) or 1))
		end
	end
	return tonumber(tostring(itemstring):match("^%S+%s+(%d+)")) or 1
end

local function stack_name(itemstring)
	if type(ItemStack) == "function" then
		local ok, s = pcall(ItemStack, itemstring)
		if ok and s and not s:is_empty() then return s:get_name() end
	end
	return tostring(itemstring):match("^(%S+)") or ""
end

--- Insert a new listing. `rec` follows f03 §5; missing bookkeeping fields are
-- filled in here. Returns the record (with `id`), or nil + reason.
function listings.insert(rec)
	if type(rec) ~= "table" then return nil, "no record" end
	if type(rec.stack) ~= "string" or rec.stack == "" then return nil, "no stack" end
	if type(rec.seller) ~= "string" or rec.seller == "" then return nil, "no seller" end
	rec.price = math.floor(tonumber(rec.price) or 0)
	if rec.price <= 0 then return nil, "no price" end
	local count = math.floor(tonumber(rec.count) or 0)
	if count <= 0 then count = stack_count(rec.stack) end
	rec.count = count
	-- Total asking price / stack size, rounded DOWN: a derived unit price must
	-- never advertise more than the listing actually charges (shared §0.7
	-- "Fees round down in the payer's favour" — same direction here).
	rec.unit_price = math.floor(rec.price / count)
	rec.id = state.next_id
	state.next_id = state.next_id + 1
	rec.version = 1
	rec.state = rec.state or "active"
	rec.created = math.floor(tonumber(rec.created) or os.time())
	rec.expires = math.floor(tonumber(rec.expires) or (rec.created + cfg.listing_duration))
	rec.key = rec.key or ""
	rec.key_m2 = rec.key
	rec.key_m1 = rec.key_m1 or ""
	rec.display = rec.display or {}
	rec.display.name = rec.display.name or rec.name or ""
	rec.name = rec.name or stack_name(rec.stack)
	normalise(rec)
	-- `key` stays the M2 key (f03 §5); `key_m2` is the indexed alias.
	rec.key_m2 = rec.key
	index_insert(rec)
	mark(lkey(rec.id), encode(rec) or false)
	return rec, nil
end

function listings.get(id)
	id = math.floor(tonumber(id) or 0)
	if id <= 0 then return nil end
	return state.by_id[id]
end

--- A listing is sellable only while it is active AND unexpired. Expiry is
-- checked lazily so the sweep interval never widens the window in which a
-- stale listing could be bought (f03 §6.2 re-validation).
function listings.is_active(rec, now)
	if type(rec) ~= "table" then return false end
	if rec.state ~= "active" then return false end
	now = now or os.time()
	return (rec.expires or 0) > now
end

function listings.get_active(id, now)
	local rec = listings.get(id)
	if rec and listings.is_active(rec, now) then return rec end
	return nil
end

--- Move a listing to a new state, bumping its version (the client's copy of a
-- listing is identified by `{id, version}`; f03 §6.2).
function listings.set_state(id, new_state)
	local rec = listings.get(id)
	if not rec then return nil end
	if rec.state == new_state then return rec end
	local was_active = (rec.state == "active")
	rec.state = new_state
	rec.version = (rec.version or 1) + 1
	if was_active and new_state ~= "active" then
		index_remove(rec, false)
	end
	if not was_active and new_state == "active" then
		m1_insert(rec)
		index_tokens(rec)
	end
	mark(lkey(rec.id), encode(rec) or false)
	return rec
end

--- Bump the version without changing state (used when a record is edited).
function listings.touch(id)
	local rec = listings.get(id)
	if not rec then return nil end
	rec.version = (rec.version or 1) + 1
	mark(lkey(rec.id), encode(rec) or false)
	return rec
end

--- Remove a record completely: after reclaim, or an admin removal.
function listings.purge(id)
	local rec = listings.get(id)
	if not rec then return false end
	index_remove(rec, true)
	mark(lkey(rec.id), false)
	return true
end

function listings.count_active(seller, now)
	now = now or os.time()
	local set = state.by_seller[seller]
	if not set then return 0 end
	local n = 0
	for id in pairs(set) do
		if listings.is_active(state.by_id[id], now) then n = n + 1 end
	end
	return n
end

--- Every listing of one seller, including expired/sold ones awaiting reclaim.
function listings.for_seller(seller, opts)
	opts = opts or {}
	local out = {}
	local set = state.by_seller[seller]
	if not set then return out end
	local now = opts.now or os.time()
	for id in pairs(set) do
		local rec = state.by_id[id]
		if rec then
			if opts.states then
				if opts.states[rec.state] then out[#out + 1] = rec end
			elseif opts.active_only then
				if listings.is_active(rec, now) then out[#out + 1] = rec end
			else
				out[#out + 1] = rec
			end
		end
	end
	table.sort(out, function(a, b)
		if (a.created or 0) ~= (b.created or 0) then return (a.created or 0) > (b.created or 0) end
		return a.id > b.id
	end)
	return out
end

----------------------------------------------------------------------
-- Querying: sorts, paging, search
----------------------------------------------------------------------

-- The three OBSERVED sorts, in the order the `Filter` control cycles them
-- [F0118–F0123]. `ah.sorts` in f03 §7.
listings.SORTS = { "lowest_price", "highest_price", "recently_listed" }

listings.SORT_LABELS = {
	lowest_price     = "Lowest Price",
	highest_price    = "Highest Price",
	recently_listed  = "Recently Listed",
}

--- Update the sort order from configuration (f03 §7 `ah.sorts`).
-- @param sorts array of sort ids (validated by caller)
function listings.set_sorts(sorts)
	if type(sorts) == "table" and #sorts > 0 then
		listings.SORTS = sorts
	end
end

local function compare(sort)
	if sort == "highest_price" then
		return function(a, b)
			if a.unit_price ~= b.unit_price then return a.unit_price > b.unit_price end
			if a.price ~= b.price then return a.price > b.price end
			return a.id > b.id
		end
	elseif sort == "recently_listed" then
		return function(a, b)
			if (a.created or 0) ~= (b.created or 0) then return a.created > b.created end
			return a.id > b.id
		end
	end
	-- lowest_price (default): by unit price, so a stack of 64 competes with a
	-- stack of 1. PROPOSED reading of the observed `Lowest Price` sort; the
	-- board tooltip shows the total, the index is per-unit (f03 §4.15).
	return function(a, b)
		if a.unit_price ~= b.unit_price then return a.unit_price < b.unit_price end
		if a.price ~= b.price then return a.price < b.price end
		return a.id < b.id
	end
end

--- Ids matching a search query, or nil when the query is empty.
--
-- Prefix match against the token vocabulary first (the observed query
-- `diamon` [F0114] is a prefix of `Diamond`); substring as a fallback. The
-- scan is over distinct tokens, not over listings (f03 §4.15).
function listings.search_ids(text, now)
	if type(text) ~= "string" then return nil end
	text = text:lower():match("^%s*(.-)%s*$") or ""
	if text == "" then return nil end
	local words = {}
	for w in text:gmatch("[%w]+") do words[#words + 1] = w end
	if #words == 0 then return nil end
	local result
	for _, w in ipairs(words) do
		local matched = {}
		for tok, set in pairs(state.tokens) do
			if tok:sub(1, #w) == w then
				for id in pairs(set) do matched[id] = true end
			end
		end
		if next(matched) == nil then
			for tok, set in pairs(state.tokens) do
				if tok:find(w, 1, true) then
					for id in pairs(set) do matched[id] = true end
				end
			end
		end
		if result == nil then
			result = matched
		else
			local both = {}
			for id in pairs(result) do
				if matched[id] then both[id] = true end
			end
			result = both
		end
	end
	-- Drop anything no longer sellable so a stale index entry cannot surface.
	if result then
		for id in pairs(result) do
			if not listings.is_active(state.by_id[id], now) then result[id] = nil end
		end
	end
	return result
end

--- The board query. Returns one page plus the totals the title and the pager
-- need.
--
-- @param opts table `{sort, page, page_size, search, seller, states, active_only, now}`
function listings.query(opts)
	opts = opts or {}
	local now = opts.now or os.time()
	local page_size = math.max(1, math.floor(tonumber(opts.page_size) or cfg.page_size))
	local pool
	if opts.seller then
		pool = listings.for_seller(opts.seller, opts)
	elseif opts.search and opts.search ~= "" then
		pool = {}
		local ids = listings.search_ids(opts.search, now)
		for id in pairs(ids or {}) do
			local rec = state.by_id[id]
			if rec then pool[#pool + 1] = rec end
		end
	else
		pool = {}
		for _, rec in pairs(state.by_id) do
			if opts.states then
				if opts.states[rec.state] then pool[#pool + 1] = rec end
			elseif opts.active_only == false then
				pool[#pool + 1] = rec
			elseif listings.is_active(rec, now) then
				pool[#pool + 1] = rec
			end
		end
	end
	table.sort(pool, compare(opts.sort))
	local total = #pool
	local pages = math.max(1, math.ceil(total / page_size))
	local page = math.floor(tonumber(opts.page) or 1)
	if page < 1 then page = 1 end
	if page > pages then page = pages end
	local first = (page - 1) * page_size + 1
	local items = {}
	for i = first, math.min(first + page_size - 1, total) do
		items[#items + 1] = pool[i]
	end
	return { items = items, total = total, pages = pages, page = page,
		page_size = page_size }
end

--- f04 contract (f04 §6.1): every ACTIVE listing whose M1 key matches and
-- whose unit price is at or below `unit_price`, cheapest first. `smp_orders`
-- absorbs them until the order is filled.
function listings.listings_at_or_below(m1_key, unit_price, now)
	local out = {}
	if type(m1_key) ~= "string" or m1_key == "" then return out end
	unit_price = math.floor(tonumber(unit_price) or 0)
	local arr = state.by_m1[m1_key]
	if not arr then return out end
	for _, e in ipairs(arr) do
		if e.unit > unit_price then break end          -- sorted: stop early
		local rec = state.by_id[e.id]
		if rec and listings.is_active(rec, now) then out[#out + 1] = rec end
	end
	return out
end

--- f05 contract (Quick Buy): the cheapest active listing for an M1 key.
function listings.cheapest(m1_key, now)
	local list = listings.listings_at_or_below(m1_key, math.huge, now)
	return list[1]
end

--- f05 contract (Quick Buy): the cheapest ACTIVE listings for an item that,
-- taken together, fill `qty` items.
--
-- Quick Buy matches on the item name plus its enchantment set (f05 §4.2:
-- "exact item including enchantments"). The M1 index is keyed by the full
-- canonical M1 key (`m1|<name>|<ench>|<meta_hash>`), so this matches on the
-- `m1|<name>|<ench>|` prefix and ignores the meta hash — exactly the width
-- f05's spec wants.
--
-- Listings are bought WHOLE (f05 bridges.lua): the last one may overshoot
-- `qty` by less than a stack. `cost_cents` is the exact total the purchase
-- will cost (sum of each listing's asking price).
--
-- @param name       registered itemstring (e.g. "mcl_tools:sword_netherite")
-- @param ench_string sorted "id:level,..." list ("" when unenchanted)
-- @param qty        integer number of items wanted
-- @param now        os.time() (optional)
-- @return table `{listings = {...}, cost_cents = N}` | nil when the
--         listings cannot fill `qty`
function listings.cheapest_for(name, ench_string, qty, now)
	if type(name) ~= "string" or name == "" then return nil end
	qty = math.floor(tonumber(qty) or 0)
	if qty <= 0 then return nil end
	now = now or os.time()

	local prefix = "m1|" .. name .. "|" .. (ench_string or "") .. "|"

	-- Collect every {id, unit} entry whose M1 key matches the (name, ench)
	-- prefix, then merge-sort cheapest first (each per-key array is already
	-- sorted, but matches may come from several meta-hash variants).
	local candidates = {}
	for m1_key, arr in pairs(state.by_m1) do
		if m1_key:sub(1, #prefix) == prefix then
			for _, e in ipairs(arr) do
				candidates[#candidates + 1] = e
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.unit ~= b.unit then return a.unit < b.unit end
		return a.id < b.id
	end)

	local out = {}
	local total_count = 0
	local cost = 0
	for _, e in ipairs(candidates) do
		local rec = state.by_id[e.id]
		if rec and listings.is_active(rec, now) then
			out[#out + 1] = rec
			total_count = total_count + rec.count
			cost = cost + rec.price
			if total_count >= qty then
				return { listings = out, cost_cents = cost }
			end
		end
	end
	return nil
end

--- Number of active listings sharing an M2 key (grouping/display, f03 §2.5).
function listings.count_by_m2(m2_key)
	local set = state.by_m2[m2_key]
	if not set then return 0 end
	local n = 0
	for id in pairs(set) do
		if listings.is_active(state.by_id[id]) then n = n + 1 end
	end
	return n
end

----------------------------------------------------------------------
-- Transactions (f03 §5, api.PurchaseItem [S23])
----------------------------------------------------------------------

function listings.insert_transaction(rec)
	if type(rec) ~= "table" then return nil end
	rec.id = state.next_txid
	state.next_txid = state.next_txid + 1
	rec.price = math.floor(tonumber(rec.price) or 0)
	rec.qty = math.floor(tonumber(rec.qty) or 0)
	rec.sold_at_ms = math.floor(tonumber(rec.sold_at_ms) or listings.now_ms())
	table.insert(state.tx, 1, rec)              -- newest first [S23]
	state.tx_ids[#state.tx_ids + 1] = rec.id
	mark(tkey(rec.id), encode(rec) or false)
	-- Cap the retained history at `ah.history` (100 per page, 10 pages).
	local cap = cfg.history_page * cfg.history_pages
	while #state.tx > cap do
		table.remove(state.tx, #state.tx)
		local old = table.remove(state.tx_ids, 1)
		if old then mark(tkey(old), false) end
	end
	return rec
end

--- One page of the global transaction log, newest first.
function listings.history(page, per_page)
	per_page = math.floor(tonumber(per_page) or cfg.history_page)
	local pages = math.max(1, math.ceil(#state.tx / per_page))
	if pages > cfg.history_pages then pages = cfg.history_pages end
	page = math.floor(tonumber(page) or 1)
	if page < 1 then page = 1 end
	if page > pages then page = pages end
	local first = (page - 1) * per_page + 1
	local out = {}
	for i = first, math.min(first + per_page - 1, #state.tx) do
		out[#out + 1] = state.tx[i]
	end
	return out, pages, page
end

----------------------------------------------------------------------
-- Expiry sweep
----------------------------------------------------------------------

--- Amortised expiry sweep: flips at most `budget` listings per call so a
-- globalstep never pays O(n) (shared §2.7). Expiry itself is enforced lazily
-- by `is_active`, so the sweep is bookkeeping, not correctness.
--
-- @return number of listings expired, number purged after the reclaim window
function listings.sweep(now, budget)
	now = now or os.time()
	budget = math.floor(tonumber(budget) or 200)
	local expired, purged, seen = 0, 0, 0
	local ids = {}
	for id in pairs(state.by_id) do ids[#ids + 1] = id end
	table.sort(ids)
	local n = #ids
	if n == 0 then return 0, 0 end
	if state.sweep_at > n then state.sweep_at = 1 end
	local i = state.sweep_at
	while seen < budget and seen < n do
		local rec = state.by_id[ids[i]]
		if rec then
			seen = seen + 1
			if rec.state == "active" and (rec.expires or 0) <= now then
				listings.set_state(rec.id, "expired")
				expired = expired + 1
			elseif rec.state == "expired" and cfg.reclaim_days > 0 and
			   (rec.expires or 0) + cfg.reclaim_days * 86400 <= now then
				listings.purge(rec.id)
				purged = purged + 1
			end
		end
		i = i + 1
		if i > n then i = 1 end
	end
	state.sweep_at = i
	return expired, purged
end

--- Listings of one seller that can be reclaimed (expired, or sold-but-never-
-- collected — f03 has no collection step, so only expired ones).
function listings.reclaimable(seller, now)
	return listings.for_seller(seller, { states = { expired = true }, now = now })
end

----------------------------------------------------------------------
-- Introspection (tests, /ahadmin)
----------------------------------------------------------------------

function listings.stats()
	local active, other = 0, 0
	for _, rec in pairs(state.by_id) do
		if rec.state == "active" and listings.is_active(rec) then
			active = active + 1
		else
			other = other + 1
		end
	end
	local m1_keys, tokens = 0, 0
	for _ in pairs(state.by_m1) do m1_keys = m1_keys + 1 end
	for _ in pairs(state.tokens) do tokens = tokens + 1 end
	return {
		listings = active + other, active = active, inactive = other,
		transactions = #state.tx, m1_keys = m1_keys, tokens = tokens,
		next_id = state.next_id, dirty = listings.dirty_count(),
	}
end

--- Raw view of an index, for tests only.
function listings._index(name, key)
	if name == "m1" then return state.by_m1[key] end
	if name == "m2" then return state.by_m2[key] end
	if name == "tokens" then return state.tokens[key] end
	if name == "seller" then return state.by_seller[key] end
	return nil
end

function listings._state() return state end

if core and type(core.log) == "function" then
	core.log("action", "[smp_ah] listings.lua: store + M1/M2/seller/search indexes ready")
end
