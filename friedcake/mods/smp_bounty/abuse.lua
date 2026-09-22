-- FriedcakeSMP — smp_bounty / abuse.lua
-- Bounty anti-abuse checks. spec/features/f10-combat.md §4.4.4 (all
-- PROPOSED; V-19 unverified):
--
--   ip        killer and target share an IP address -> no payout
--   cooldown  a killer–target pair has claimed within
--             bounty.pair_cooldown (3,600 s) -> no payout
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
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_bounty.abuse = {}

local A = smp_bounty.abuse
local ip_cache = {} -- [name] = { ip = ..., at = ... }
A.ip_cache = ip_cache -- exposed for tests

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

local function pair_key(killer, victim)
	return killer:lower() .. "|" .. victim:lower()
end

-- Returns nil (payout allowed) or "ip" | "cooldown" | "zone".
-- `pos` is the kill position; nil skips the safe-zone check (the §6
-- pseudo-code calls is_abuse with two arguments).
function A.check(killer, victim, pos)
	local kip = A.ip_of(killer)
	local vip = A.ip_of(victim)
	if kip and vip and kip == vip then return "ip" end

	local t = smp_bounty.db.claims[pair_key(killer, victim)]
	if t and os.time() - t < smp_bounty.cfg.pair_cooldown then
		return "cooldown"
	end

	if pos and smp_combat and smp_combat.in_safe_zone
		and smp_combat.in_safe_zone(pos) then
		return "zone"
	end
	return nil
end

function A.record_claim(killer, victim)
	smp_bounty.db.claims[pair_key(killer, victim)] = os.time()
	smp_bounty.save()
end
