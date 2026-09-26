-- FriedcakeSMP — smp_bounty / abuse.lua
-- Bounty anti-abuse checks. spec/features/f10-combat.md §4.4.4
-- (PROPOSED; V-19 unverified) plus the S07/CB-2 hardening:
--
--   source    the kill credit came from the last-attacker FALLBACK on
--             a reason-less death (fall, lava, void, set_hp(0) / /kill)
--             -> no payout; a bounty needs a DIRECT kill (killer_from
--             named the puncher/shooter) or a combat log (CB-2.1)
--   ip        killer and target share an IP address -> no payout
--   friend    killer and target are friends in smp_social (mutual
--             follows, smp_social.is_friend — public API, graph.lua)
--             -> no payout (CB-2.2; collusion needs a second account
--             that is NOT a friend, is slower to set up and shares no
--             graph edge)
--   playtime  the killer's recorded playtime is below
--             MIN_KILLER_PLAYTIME -> no payout (CB-2.2: fresh alt
--             accounts cannot collect)
--   cooldown  the VICTIM has had a bounty paid out within
--             bounty.pair_cooldown (3,600 s) -> no payout, whoever the
--             killer is (CB-2.4: one payout per victim per window, not
--             per pair — a paid-out victim cannot be relayed through a
--             second killer an hour later)
--   zone      the kill happened inside the spawn safe zone -> no payout
--             (X10: no bounty payout inside the spawn radius)
--
-- A refused payout leaves the bounty and its escrow untouched: the
-- bounty simply stays claimable by a legitimate killer.
--
-- IP caveat: core.get_player_ip only answers for connected players, so
-- a combat-logged victim's IP is served from a join-time cache. The
-- cache entry survives while the player is online (prune skips online
-- names), which covers the combat-log window. When either IP is
-- unknowable the check fails OPEN (payout allowed) — recorded in f10 §10.
--
-- Playtime caveat (PROPOSED, f10 §10): the metric is rec.playtime in
-- seconds, accrued by smp_stats' f14 accumulator (flushed at most
-- stats.persist_interval late). The threshold only stands up while
-- smp_stats is present — without the accrual mod there is no playtime
-- data at all, and the check steps aside rather than refusing every
-- payout. A missing player record counts as 0 playtime (fail CLOSED):
-- that is a fresh account, exactly what the threshold targets.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_bounty.abuse = {}

local A = smp_bounty.abuse
local ip_cache = {} -- [name] = { ip = ..., at = ... }
A.ip_cache = ip_cache -- exposed for tests

-- CB-2.2: seconds of recorded playtime a killer needs before a bounty
-- may be paid to them. PROPOSED rule choice, recorded in f10 §10 —
-- deliberately a constant, not a settings key: a new `bounty.*` read
-- would have to land in spec/shared/06-config-reference.md first
-- (dev-tests/test_config_mirror.lua D7 guard, integrator-owned).
-- Set to 0 to disable.
local MIN_KILLER_PLAYTIME = 3600
A.MIN_KILLER_PLAYTIME = MIN_KILLER_PLAYTIME -- exposed for tests

local function prune(now)
	local window = smp_bounty.cfg.pair_cooldown
	for name, e in pairs(ip_cache) do
		if now - (e.at or 0) >= window
			and not (core.get_player_by_name and core.get_player_by_name(name)) then
			ip_cache[name] = nil
		end
	end
end

function A.remember_ip(name)
	if not name or not core.get_player_ip then return end
	local ok, ip = pcall(core.get_player_ip, name)
	if ok and type(ip) == "string" and ip ~= "" then
		ip_cache[name] = { ip = ip, at = os.time() }
		prune(os.time())
	end
end

function A.ip_of(name)
	if not name then return nil end
	local p = core.get_player_by_name and core.get_player_by_name(name)
	if p then
		local ok, ip = pcall(core.get_player_ip, name)
		if ok and type(ip) == "string" and ip ~= "" then return ip end
	end
	local e = ip_cache[name]
	return e and e.ip or nil
end

-- CB-2.4: claims are keyed per VICTIM (one payout per victim per
-- window), not per killer–victim pair. `killer` is kept in the
-- signature for callers but no longer part of the key.
local function victim_key(victim)
	return victim:lower()
end

-- CB-2.2: the killer's recorded playtime, in seconds (see header).
-- Returns 0 when there is no record: no record = no playtime.
local function playtime_of(name)
	local rec = smp_store.api.get_player(name)
	return (rec and tonumber(rec.playtime)) or 0
end

-- Returns nil (payout allowed) or one of:
--   "source" | "ip" | "friend" | "playtime" | "cooldown" | "zone".
-- `pos` is the kill position; nil skips the safe-zone check (the §6
-- pseudo-code calls is_abuse with two arguments).
-- `source` is smp_combat's attribution ladder (CB-2.1); nil is a
-- direct/legacy call and passes this rule (documented in f10 §10).
function A.check(killer, victim, pos, source)
	if source == "fallback" then return "source" end

	local kip = A.ip_of(killer)
	local vip = A.ip_of(victim)
	if kip and vip and kip == vip then return "ip" end

	-- CB-2.2: friend collusion. smp_social.is_friend is mutual (it is
	-- follows(a,b) and follows(b,a), so one call covers both orders).
	-- Absent when smp_social is not part of the pack -> stands down.
	if smp_social and type(smp_social.is_friend) == "function"
		and smp_social.is_friend(killer, victim) then
		return "friend"
	end

	-- CB-2.2: established accounts only (see header for the caveat).
	if smp_stats and MIN_KILLER_PLAYTIME > 0
		and playtime_of(killer) < MIN_KILLER_PLAYTIME then
		return "playtime"
	end

	local t = smp_bounty.db.claims[victim_key(victim)]
	if t and os.time() - t < smp_bounty.cfg.pair_cooldown then
		return "cooldown"
	end

	if pos and smp_combat and smp_combat.in_safe_zone
		and smp_combat.in_safe_zone(pos) then
		return "zone"
	end
	return nil
end

-- `killer` kept for call compatibility / logs: the window belongs to
-- the VICTIM now (CB-2.4).
function A.record_claim(killer, victim)
	smp_bounty.db.claims[victim_key(victim)] = os.time()
	smp_bounty.save()
end
