-- FriedcakeSMP — smp_social graph
--
-- The follow / ignore / block graphs over the player record (f11 §5):
--
--   social = { following = {...}, ignored = {...}, blocked = {...} }
--
-- Friendship is derived, never stored: A and B are friends iff each
-- follows the other (§4.4).
--
-- Read path: a small per-name cache of the three lists as lower-case
-- sets. Records are only ever written by this mod, and every write
-- invalidates the entry, so the cache cannot go stale. The negative
-- case (no record) is deliberately NOT cached.
--
-- Write path always re-reads the record fresh, mutates, upserts and
-- invalidates — with no yield in between (shared §2.3).
--
-- Public predicates (the f08/f10 contract):
--   smp_social.ignores(a, b)               a has b on their ignore list
--   smp_social.blocks(a, b)                a blocks OR ignores b
--   smp_social.blocks_only(a, b)           a blocks b — BLOCK graph only
--   smp_social.is_blocked(a, b)            a blocks b (strict)
--   smp_social.is_friend_or_followed(a, b) b is a friend of a, or followed by a
--   smp_social.follows(a, b), smp_social.is_friend(a, b)
--
-- Which predicate owns which effect is the §4.3 table (f11): chat,
-- messages and teleport requests accept block OR ignore (`blocks`);
-- payments, follows and RTP-queue pairing are block-only
-- (`blocks_only`). Decision record: f11 §10.2 (V-48).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

local CACHE_LIMIT = 4096
local cache = {}      -- [name] = { following = set, ignored = set, blocked = set }
local cache_n = 0

function smp_social._invalidate(name)
	if cache[name] ~= nil then
		cache[name] = nil
		cache_n = math.max(0, cache_n - 1)
	end
end

local function to_set(list)
	local s = {}
	for _, v in ipairs(type(list) == "table" and list or {}) do
		s[tostring(v):lower()] = true
	end
	return s
end

local function entry(name)
	if type(name) ~= "string" or name == "" then return nil end
	local e = cache[name]
	if e ~= nil then return e end
	local rec = smp_store.api.get_player(name)
	if not rec then return nil end -- no record: not cached (see header)
	local soc = type(rec.social) == "table" and rec.social or {}
	e = {
		following = to_set(soc.following),
		ignored    = to_set(soc.ignored),
		blocked    = to_set(soc.blocked),
	}
	if cache_n >= CACHE_LIMIT then
		cache = {}
		cache_n = 0
	end
	cache[name] = e
	cache_n = cache_n + 1
	return e
end

----------------------------------------------------------------------
-- Follows and derived friendship
----------------------------------------------------------------------

function smp_social.follows(a, b)
	local e = entry(a)
	return (e and e.following[tostring(b):lower()]) and true or false
end

function smp_social.is_friend(a, b)
	return smp_social.follows(a, b) and smp_social.follows(b, a)
end

-- f11 §4.2: delivered only if the sender (b) is a friend of, or followed
-- by, the recipient (a). Friendship implies a follows b, so this is
-- exactly "a follows b"; the friend term is kept explicit to match the
-- spec sentence. One-way "b follows a" does NOT qualify (PROPOSED
-- reading, recorded in f11 §10).
function smp_social.is_friend_or_followed(a, b)
	return smp_social.follows(a, b) or smp_social.is_friend(a, b)
end

----------------------------------------------------------------------
-- Ignore and block
----------------------------------------------------------------------

function smp_social.ignores(a, b)
	local e = entry(a)
	return (e and e.ignored[tostring(b):lower()]) and true or false
end

function smp_social.is_blocked(a, b)
	local e = entry(a)
	return (e and e.blocked[tostring(b):lower()]) and true or false
end

-- blocks() covers BOTH graphs. f08 gates teleport requests on blocks
-- alone (smp_tp.bridge.blocks) and the /ignore narration says ignore
-- covers messages AND teleport requests [F0287], so folding ignore in
-- here is what makes T6 hold.
--
-- Effects the §4.3 table marks BLOCK-ONLY — payments, follows and
-- RTP-queue pairing — must NOT fold ignore in: see blocks_only() below.
-- The RTP consumer still reaches this function through
-- smp_tp.bridge.blocks (smp_rtpqueue/init.lua:50); switching it to
-- blocks_only() is ESCALATED to the f08 brief and recorded in f11
-- §10.2. (An earlier version of this comment asserted that the
-- ignore/RTP contradiction had already been captured in f11 §10 when
-- no such entry existed — that assertion was false; §10.2 is the real
-- entry. Do not restore it.)
function smp_social.blocks(a, b)
	return smp_social.is_blocked(a, b) or smp_social.ignores(a, b)
end

-- Block graph ONLY (no ignore). f11 §4.3: /ignore hides chat and
-- refuses messages and teleport requests; it does NOT refuse payments,
-- follows or RTP-queue pairing — only /block does. PROPOSED row, tied
-- to V-48; decision record in f11 §10.2.
function smp_social.blocks_only(a, b)
	return smp_social.is_blocked(a, b)
end

----------------------------------------------------------------------
-- Write path
----------------------------------------------------------------------

local function normalize(soc)
	if type(soc) ~= "table" then return {} end
	soc.following = type(soc.following) == "table" and soc.following or {}
	soc.ignored = type(soc.ignored) == "table" and soc.ignored or {}
	soc.blocked = type(soc.blocked) == "table" and soc.blocked or {}
	return soc
end

-- Read the social table of an existing/new record (display path).
function smp_social.get_social(name)
	local rec = smp_store.api.ensure_player(name)
	return normalize(rec.social)
end

-- fn mutates the social table; this writes and invalidates with no
-- yield in between (shared §2.3).
function smp_social.mutate_social(name, fn)
	local rec = smp_store.api.ensure_player(name)
	local soc = normalize(rec.social)
	fn(soc)
	rec.social = soc
	smp_store.api.upsert_player(rec)
	smp_social._invalidate(name)
	return soc
end

-- Case-insensitive membership against a name list (display lists store
-- canonical names; comparisons must not care about case).
function smp_social.list_has(list, name)
	local lower = tostring(name):lower()
	for _, v in ipairs(list or {}) do
		if tostring(v):lower() == lower then return true end
	end
	return false
end

return true
