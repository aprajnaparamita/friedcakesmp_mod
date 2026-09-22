-- FriedcakeSMP — smp_stats / boards.lua
-- Snapshot leaderboards (f14 §4.2, §5, T7/T8/T9).
--
-- Ten categories, the official API's key set in the spec's order
-- (§4.2.1): brokenblocks, deaths, kills, mobskilled, money,
-- placedblocks, playtime, sell, shards, shop.
--
-- Rebuilds run outside globalstep on a core.after chain (§8), never
-- on the hot path, and never yield mid-pass (shared §2.3): gather ->
-- build -> publish is one synchronous sequence.
--
-- Selection is a partial top-N, NOT a full sort (T8 hard gate: 50 ms
-- at 10,000 records — §2.7): each board keeps a sorted array capped
-- at leaderboards.size with binary insertion; once full, a record
-- that does not beat the last slot costs one comparison. Ties break
-- by name ascending so pages are deterministic.
--
-- Offline players are included by construction: records come from
-- smp_store.api.all_player_names (T9).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local CATEGORIES = {
	-- key           display label (PROPOSED, claim string list)  value kind
	{ key = "brokenblocks", label = "Broken Blocks",      fmt = "qty"   },
	{ key = "deaths",       label = "Deaths",             fmt = "qty"   },
	{ key = "kills",        label = "Kills",              fmt = "qty"   },
	{ key = "mobskilled",   label = "Mob Kills",          fmt = "qty"   },
	{ key = "money",        label = "Money",              fmt = "money" },
	{ key = "placedblocks", label = "Placed Blocks",      fmt = "qty"   },
	{ key = "playtime",     label = "Playtime",           fmt = "secs"  },
	{ key = "sell",         label = "Money from Selling", fmt = "money" },
	{ key = "shards",       label = "Shards",             fmt = "qty"   },
	{ key = "shop",         label = "Spent in Shop",      fmt = "money" },
}
smp_stats.CATEGORIES = CATEGORIES

-- Value getters, parallel to CATEGORIES (§6): money/shards read the
-- live top-level balances, sell/shop the two economy counters,
-- playtime the store plus this server's pending seconds.
local GET = {
	function(rec) return tonumber(rec.stats and rec.stats.broken_blocks) or 0 end,
	function(rec) return tonumber(rec.stats and rec.stats.deaths) or 0 end,
	function(rec) return tonumber(rec.stats and rec.stats.kills) or 0 end,
	function(rec) return tonumber(rec.stats and rec.stats.mobs_killed) or 0 end,
	function(rec) return tonumber(rec.money) or 0 end,
	function(rec) return tonumber(rec.stats and rec.stats.placed_blocks) or 0 end,
	function(rec)
		local pending = smp_stats._pending_playtime
		return (tonumber(rec.playtime) or 0)
			+ (pending and tonumber(pending[rec.name]) or 0)
	end,
	function(rec) return tonumber(rec.stats and rec.stats.money_made_from_sell) or 0 end,
	function(rec) return tonumber(rec.shards) or 0 end,
	function(rec) return tonumber(rec.stats and rec.stats.money_spent_on_shop) or 0 end,
}

function smp_stats.category_by_key(key)
	for _, cat in ipairs(CATEGORIES) do
		if cat.key == key then return cat end
	end
	return nil
end

-- Display value for a category (§4.2.4): money in the body chat
-- spacing, counts with the lower-case quantity suffix, playtime in
-- raw seconds (§0.6 — unobserved, PROPOSED §10 F14-D8).
function smp_stats.format_value(cat, value)
	if cat.fmt == "money" then
		return smp_core.fmt_money(value, "body")
	end
	if cat.fmt == "secs" then
		return tostring(math.floor(tonumber(value) or 0))
	end
	return smp_core.fmt_qty(tonumber(value) or 0)
end

----------------------------------------------------------------------
-- Partial top-N: descending by value, ties by name ascending.

local function insert_top(t, name, value, size)
	local n = #t
	if n >= size then
		local last = t[n]
		-- Full: accept only a candidate that beats the last slot
		-- (one comparison for the common case — the T8 budget).
		if value < last.value then return end
		if value == last.value and name >= last.name then return end
		t[n] = nil
		n = n - 1
	end
	-- Binary-search the insertion point.
	local lo, hi = 1, n
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		local e = t[mid]
		if e.value > value or (e.value == value and e.name < name) then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	for i = n, lo, -1 do t[i + 1] = t[i] end
	t[lo] = { name = name, value = value }
end

-- Build every board from an array of player records (testable in
-- isolation — T8 times this function directly).
function smp_stats.build_from(records, size)
	size = tonumber(size) or smp_stats.cfg.size
	if size < 1 then size = 1 end
	local n = #records
	local ncat = #CATEGORIES
	local keys, getters, buckets = {}, {}, {}
	for ci = 1, ncat do
		keys[ci] = CATEGORIES[ci].key
		getters[ci] = GET[ci]
		buckets[ci] = {}
	end
	for ri = 1, n do
		local rec = records[ri]
		local name = rec.name
		if name then
			for ci = 1, ncat do
				insert_top(buckets[ci], name, getters[ci](rec), size)
			end
		end
	end
	local out = {}
	for ci = 1, ncat do out[keys[ci]] = buckets[ci] end
	return out
end

----------------------------------------------------------------------
-- Live boards + the rebuild chain.

smp_stats.boards = {} -- [category] = { {name=..., value=...}, ... } (§5)

function smp_stats.gather_records()
	local names = smp_store.api.all_player_names()
	local out = {}
	for i = 1, #names do
		local rec = smp_store.api.get_player(names[i])
		if rec then out[#out + 1] = rec end
	end
	return out
end

function smp_stats.rebuild()
	local records = smp_stats.gather_records()
	-- One uninterrupted pass: no yields between reading the record
	-- set and publishing the boards (shared §2.3).
	smp_stats.boards = smp_stats.build_from(records, smp_stats.cfg.size)
	smp_stats.last_rebuild = os.time()
	if smp_stats.api and type(smp_stats.api.write_snapshots) == "function" then
		pcall(smp_stats.api.write_snapshots, records) -- api.mode gates it
	end
	return smp_stats.boards
end

-- The rebuild chain (§8): core.after, never globalstep. The first
-- rebuild lands shortly after server start, then every
-- leaderboards.refresh seconds.
local function schedule_next()
	core.after(smp_stats.cfg.refresh, function()
		local ok, err = pcall(smp_stats.rebuild)
		if not ok then
			core.log("error", "[smp_stats] rebuild failed: " .. tostring(err))
		end
		schedule_next()
	end)
end

core.after(2, function()
	local ok, err = pcall(smp_stats.rebuild)
	if not ok then
		core.log("error", "[smp_stats] initial rebuild failed: "
			.. tostring(err))
	end
	schedule_next()
end)

----------------------------------------------------------------------
-- Paging (§4.2.4): 10 rows per page, clamped, deterministic.

smp_stats.PAGE_SIZE = 10

-- Returns (page_rows, clamped_page, total_pages) for a board.
function smp_stats.board_page(board, page)
	board = board or {}
	local total = #board
	local total_pages = math.max(1, math.ceil(total / smp_stats.PAGE_SIZE))
	page = math.floor(tonumber(page) or 1)
	if page < 1 then page = 1 end
	if page > total_pages then page = total_pages end
	local rows = {}
	local start = (page - 1) * smp_stats.PAGE_SIZE
	for i = start + 1, math.min(start + smp_stats.PAGE_SIZE, total) do
		rows[#rows + 1] = board[i]
	end
	return rows, page, total_pages
end
