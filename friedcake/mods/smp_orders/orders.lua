-- FriedcakeSMP — smp_orders / orders.lua
-- Orders data layer: CRUD over an in-memory table indexed by id, by
-- buyer and by M1 key, persisted through this mod's own mod storage.
-- Schema per spec/features/f04-orders.md §5.
--
-- NOTE on persistence: shared/02-architecture.md §2.2 places orders in
-- smp_store tables, but smp_store exposes no order API and feature mods
-- must not edit it. Until the integrator lands an orders table there
-- (see f04 §10 Proposed shared changes), smp_orders persists orders in
-- its own mod-storage namespace with the same dirty-flag/flush pattern
-- smp_store uses. Money and ledger always go through smp_store.api.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_orders.S
local cfg = smp_orders.cfg

local db = {
	next_id = 1,
	orders = {},    -- [id] = record
	by_buyer = {},  -- [buyer_name] = { id, ... }
	by_key = {},    -- [m1_key]     = { id, ... }
	dirty = {},     -- [id] = true
	_storage = nil,
}
smp_orders.db = db

local function storage()
	if not db._storage then
		db._storage = core.get_mod_storage()
	end
	return db._storage
end

----------------------------------------------------------------------
-- Records
----------------------------------------------------------------------

local function normalize(o)
	o.id = tonumber(o.id)
	o.version = tonumber(o.version) or 1
	o.state = o.state or "open"          -- open | filled | cancelled | expired
	o.buyer = o.buyer or ""
	o.key = o.key or ""
	o.template = o.template or ""
	o.ench = o.ench or {}
	o.qty = math.floor(tonumber(o.qty) or 0)
	o.delivered = math.floor(tonumber(o.delivered) or 0)
	o.collected = math.floor(tonumber(o.collected) or 0)
	o.unit_price = math.floor(tonumber(o.unit_price) or 0)
	o.escrow = math.floor(tonumber(o.escrow) or 0)
	o.created = tonumber(o.created) or os.time()
	o.expires = tonumber(o.expires) or (o.created + cfg.duration)
	o.suppliers = o.suppliers or {}
	return o
end

local function index_add(o)
	local b = db.by_buyer[o.buyer]
	if not b then b = {}; db.by_buyer[o.buyer] = b end
	for _, id in ipairs(b) do if id == o.id then return end end
	b[#b + 1] = o.id

	local k = db.by_key[o.key]
	if not k then k = {}; db.by_key[o.key] = k end
	for _, id in ipairs(k) do if id == o.id then return end end
	k[#k + 1] = o.id
end

function smp_orders.mark_dirty(id)
	db.dirty[id] = true
end

-- Insert a new order record. `rec` must carry buyer, key, template,
-- ench, qty, unit_price and escrow; the rest is defaulted. Returns id.
function smp_orders.insert_order(rec)
	local id = db.next_id
	db.next_id = id + 1
	rec.id = id
	normalize(rec)
	db.orders[id] = rec
	index_add(rec)
	smp_orders.mark_dirty(id)
	storage():set_string("next_id", tostring(db.next_id))
	return id
end

function smp_orders.get_order(id)
	return db.orders[tonumber(id) or -1]
end

----------------------------------------------------------------------
-- Persistence
----------------------------------------------------------------------

function smp_orders.save_dirty()
	local st = storage()
	for id in pairs(db.dirty) do
		local o = db.orders[id]
		if o then
			st:set_string("order:" .. id, core.write_json(o))
		end
	end
	db.dirty = {}
end

function smp_orders.load_all()
	local st = storage()
	db.next_id = math.max(tonumber(st:get_string("next_id")) or 1, 1)
	-- Ids are dense (1..next_id-1); scanning them avoids key parsing and
	-- is bounded by the number of orders ever created.
	for id = 1, db.next_id - 1 do
		local raw = st:get_string("order:" .. id)
		if raw ~= "" then
			local o = core.parse_json(raw)
			if type(o) == "table" and o.id then
				normalize(o)
				db.orders[o.id] = o
				index_add(o)
				if o.id >= db.next_id then db.next_id = o.id + 1 end
			end
		end
	end
	core.log("action", string.format(
		"[smp_orders] loaded %d order(s), next id %d",
		(function() local n = 0 for _ in pairs(db.orders) do n = n + 1 end return n end)(),
		db.next_id))
end

----------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------

-- Orders sorts (OBSERVED [F0180]): the board's three, NOT the auction's.
-- Semantics (PROPOSED):
--   most_per_item   highest unit price first — suppliers want the best payer
--   most_paid       largest total commitment (unit_price × qty) first
--   recently_listed newest first
local SORTERS = {
	most_per_item = function(a, b)
		if a.unit_price ~= b.unit_price then return a.unit_price > b.unit_price end
		return a.id < b.id
	end,
	most_paid = function(a, b)
		local ta, tb = a.unit_price * a.qty, b.unit_price * b.qty
		if ta ~= tb then return ta > tb end
		return a.id < b.id
	end,
	recently_listed = function(a, b)
		if a.created ~= b.created then return a.created > b.created end
		return a.id < b.id
	end,
}
smp_orders.SORTERS = SORTERS

function smp_orders.sort_names()
	return cfg.sorts
end

function smp_orders.open_orders(sort)
	local out = {}
	for _, o in pairs(db.orders) do
		if o.state == "open" then out[#out + 1] = o end
	end
	table.sort(out, SORTERS[sort] or SORTERS.most_per_item)
	return out
end

-- Open orders for one M1 key, ascending id (creation order).
function smp_orders.open_orders_for_key(key)
	local out = {}
	for _, id in ipairs(db.by_key[key] or {}) do
		local o = db.orders[id]
		if o and o.state == "open" then out[#out + 1] = o end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- Orders shown under `Your Orders` and counted against the slot limit:
-- open orders, plus any order with uncollected deliveries (PROPOSED —
-- the reference slot accounting is unobserved, V-09).
function smp_orders.orders_for(name)
	local out = {}
	for _, id in ipairs(db.by_buyer[name] or {}) do
		local o = db.orders[id]
		if o and (o.state == "open" or o.delivered > o.collected) then
			out[#out + 1] = o
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

function smp_orders.remaining(o)
	return math.max(0, o.qty - o.delivered)
end

----------------------------------------------------------------------
-- Slot limits (LIVE [S17]: tier1 45, tier2 90; default PROPOSED 9)
----------------------------------------------------------------------

function smp_orders.slot_limit(name)
	-- Prefer smp_ranks for effective tier (honours expires_at lazily).
	-- Fall back to the stored rank.tier when smp_ranks is absent OR
	-- when smp_ranks.tier returns nil (e.g. player not in ranks system).
	-- f04 O5: consumer item from f13 — expired ranks must not grant capacity.
	local tier = "default"
	if smp_ranks and type(smp_ranks.tier) == "function" then
		local ok, t = pcall(smp_ranks.tier, name)
		if ok and t then
			tier = t
		else
			-- smp_ranks present but returned nil/error -> fallback to stored
			local rec = smp_store.api.get_player(name)
			if rec and rec.rank and rec.rank.tier then tier = rec.rank.tier end
		end
	else
		local rec = smp_store.api.get_player(name)
		if rec and rec.rank and rec.rank.tier then tier = rec.rank.tier end
	end
	return cfg.slots[tier] or cfg.slots.default
end

function smp_orders.can_create(name)
	return #smp_orders.orders_for(name) < smp_orders.slot_limit(name)
end

----------------------------------------------------------------------
-- Blacklist (LIVE [S9]: amethyst items cannot be ordered)
----------------------------------------------------------------------

local function name_from_key(key)
	local parsed = smp_items.parse_key(key)
	return parsed and parsed.name or key
end

function smp_orders.blacklisted(key_or_name)
	local name = name_from_key(key_or_name)
	for _, prefix in ipairs(cfg.blacklist) do
		if prefix ~= "" and name:sub(1, #prefix) == prefix then
			return true
		end
	end
	-- f06 contract (smp_amethyst/blacklist.lua): exact itemstrings for the
	-- timed shard tools. Runtime import; degrades to the configured
	-- prefixes when smp_amethyst is absent.
	if smp_amethyst and type(smp_amethyst.blacklist) == "table" then
		for _, exact in ipairs(smp_amethyst.blacklist) do
			if name == exact then return true end
		end
	end
	return false
end

----------------------------------------------------------------------
-- Expiry (§4.10: orders expire after orders.duration; refund unspent
-- escrow, delivered items stay collectible)
----------------------------------------------------------------------

function smp_orders.expire_due(now)
	now = now or os.time()
	local expired = 0
	for _, o in pairs(db.orders) do
		if o.state == "open" and o.expires and o.expires <= now then
			local refund = o.escrow
			smp_orders.escrow.refund(o, refund)
			o.state = "expired"
			o.version = o.version + 1
			smp_orders.mark_dirty(o.id)
			expired = expired + 1
			smp_orders.notify_buyer(o, S("Your order for @1 expired, @2 refunded",
				smp_orders.display.order_name(o),
				smp_core.fmt_money(refund, "body")))
			core.log("action", string.format(
				"[smp_orders] order %d expired, refunded %d cents to %s",
				o.id, refund, o.buyer))
		end
	end
	return expired
end
