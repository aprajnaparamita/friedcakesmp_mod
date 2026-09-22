-- FriedcakeSMP — smp_quickbuy entries
--
-- CRUD over the player's Quick Buy entry list. Entries persist in the player
-- record under `quickbuy` (§5) and use the shape { key=, ench={}, qty= }.
-- Capacity is cfg.max_entries (default 45).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local cfg = smp_quickbuy.cfg

smp_quickbuy.entries = {}

local function record(name)
	return smp_store.api.ensure_player(name)
end

local function normalize(entry)
	return {
		key  = entry.key,
		ench = entry.ench or {},
		qty  = math.max(1, math.floor(tonumber(entry.qty) or 1)),
	}
end

-- The raw array (read-only from the caller's perspective; mutate via the
-- helpers so the record is upserted).
function smp_quickbuy.entries.list(name)
	local r = record(name)
	r.quickbuy = r.quickbuy or {}
	return r.quickbuy
end

function smp_quickbuy.entries.count(name)
	return #smp_quickbuy.entries.list(name)
end

-- 1-based lookup; returns the entry table or nil.
function smp_quickbuy.entries.get(name, index)
	return smp_quickbuy.entries.list(name)[index]
end

-- Add an entry. Returns true, or nil plus a reason ("capacity").
function smp_quickbuy.entries.add(name, entry)
	local r = record(name)
	r.quickbuy = r.quickbuy or {}
	if #r.quickbuy >= cfg.max_entries then
		return nil, "capacity"
	end
	r.quickbuy[#r.quickbuy + 1] = normalize(entry)
	smp_store.api.upsert_player(r)
	return true
end

-- Remove the entry at index (1-based). Returns the removed entry or nil.
function smp_quickbuy.entries.remove(name, index)
	local r = record(name)
	r.quickbuy = r.quickbuy or {}
	local e = table.remove(r.quickbuy, index)
	if e then smp_store.api.upsert_player(r) end
	return e
end

-- Replace the entry at index. Returns true, or nil if out of range.
function smp_quickbuy.entries.set(name, index, entry)
	local r = record(name)
	r.quickbuy = r.quickbuy or {}
	if index < 1 or index > #r.quickbuy then return nil end
	r.quickbuy[index] = normalize(entry)
	smp_store.api.upsert_player(r)
	return true
end

core.log("action", "[smp_quickbuy] entries CRUD ready (max_entries=" .. cfg.max_entries .. ")")
