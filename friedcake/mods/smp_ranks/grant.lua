-- FriedcakeSMP — smp_ranks grant/clear (f13 §6).
--
-- The record is {tier, expires_at} and lives in smp_store, so offline
-- grants work without touching player meta (T6). A tier lasts 30 days
-- per grant [S17]; consecutive same-tier grants stack by extending
-- expires_at (PROPOSED, V-74 — T3).
--
-- No yields between validate and mutate (shared §2.3): the whole
-- read-modify-write of expires_at happens in one synchronous pass, so
-- two rapid /rank set calls cannot clobber the stacking.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local DAY = 86400

-- Returns the new rank record {tier, expires_at}, or nil + reason
-- ("no_player" | "bad_tier" | "bad_days").
function smp_ranks.grant(who, tier, days)
	local name = smp_ranks.name_of(who)
	if not name then return nil, "no_player" end
	if not smp_ranks.is_tier(tier) then return nil, "bad_tier" end
	days = tonumber(days) or smp_ranks.cfg.grant_days
	if days ~= days or days == math.huge then return nil, "bad_days" end
	days = math.floor(days)
	if days < 1 then return nil, "bad_days" end

	local rec = smp_store.api.ensure_player(name) -- works offline (T6)
	local now = os.time()
	local r = rec.rank
	local base = now
	if type(r) == "table" and r.tier == tier
			and type(r.expires_at) == "number" and r.expires_at > now then
		base = r.expires_at -- consecutive same-tier grant stacks (T3)
	end
	local expires_at = base + days * DAY
	rec.rank = { tier = tier, expires_at = expires_at }
	smp_store.api.upsert_player(rec) -- single read-modify-write, no yields
	smp_ranks.watch(name, expires_at)
	return rec.rank
end

-- Clearing reverts every perk to the default limits immediately (T1).
function smp_ranks.clear(who)
	local name = smp_ranks.name_of(who)
	if not name then return nil, "no_player" end
	local rec = smp_store.api.get_player(name)
	if rec then
		rec.rank = {}
		smp_store.api.upsert_player(rec)
	end
	smp_ranks.unwatch(name)
	return true
end
