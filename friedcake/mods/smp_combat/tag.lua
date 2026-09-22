-- FriedcakeSMP — smp_combat / tag.lua
-- The combat tag itself: an in-memory table keyed by player name.
--
-- spec/features/f10-combat.md §5.1:
--   smp_combat.tags[name] = { expires, last_attacker, last_attacker_at }
--
-- Tags MUST NOT survive a restart (T11). Nothing in this file — or
-- anywhere else in smp_combat — writes a tag to storage: a crashed
-- process cannot run the logout path, so a crash is a combat log, and a
-- rejoining player whose tag would have been live joins normally.
--
-- Public contract (f05, f06 and f08 stub these with TODO(f10)):
--   smp_combat.is_tagged(name_or_player) -> boolean
--   smp_combat.tag(victim, attacker)     -- names or ObjectRefs, both sides
--                                         -- are tagged by the callers
--   smp_combat.untag(name_or_player)     -> boolean
--   smp_combat.last_attacker(name_or_player) -> string | nil
--   smp_combat.seconds_left(name_or_player)  -> number | nil
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_combat.tags = smp_combat.tags or {}

----------------------------------------------------------------------
-- Name normalisation. Consumers pass either a player name (f06, f08)
-- or an ObjectRef (f05's bridge forwards the player object), so both
-- must work. pcall guards odd ObjectRef-like userdata.
----------------------------------------------------------------------

local function ref_is_player(o)
	return o.is_player and o:is_player() or false
end

local function ref_name(o)
	return o:get_player_name()
end

function smp_combat.name_of(x)
	local t = type(x)
	if t == "string" then
		if x ~= "" then return x end
		return nil
	end
	if t == "userdata" or t == "table" then
		local ok, is_p = pcall(ref_is_player, x)
		if ok and is_p then
			local ok2, nm = pcall(ref_name, x)
			if ok2 and type(nm) == "string" and nm ~= "" then return nm end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Core tag operations
----------------------------------------------------------------------

function smp_combat.is_tagged(who)
	local name = smp_combat.name_of(who)
	if not name then return false end
	local t = smp_combat.tags[name]
	if not t then return false end
	if t.expires <= os.time() then
		smp_combat.tags[name] = nil -- lazy expiry
		return false
	end
	return true
end

-- Tag one player. `victim` receives `attacker` as its last attacker;
-- both may be names or ObjectRefs. A repeat call refreshes the timer
-- (T1) and re-records the attacker (§5.1 "refreshed per hit").
function smp_combat.tag(victim, attacker)
	local vname = smp_combat.name_of(victim)
	if not vname then return false end
	local aname = smp_combat.name_of(attacker)
	if aname == vname then aname = nil end
	local now = os.time()
	local t = smp_combat.tags[vname]
	if not t then
		t = {}
		smp_combat.tags[vname] = t
	end
	t.expires = now + (smp_combat.cfg.combat.tag_seconds or 20)
	if aname then
		t.last_attacker = aname
		t.last_attacker_at = now
	end
	if smp_combat.countdown then smp_combat.countdown.show(vname) end
	return true
end

function smp_combat.untag(who)
	local name = smp_combat.name_of(who)
	if not name then return false end
	if not smp_combat.tags[name] then return false end
	smp_combat.tags[name] = nil
	if smp_combat.countdown then smp_combat.countdown.clear(name) end
	return true
end

function smp_combat.last_attacker(who)
	local name = smp_combat.name_of(who)
	if not name then return nil end
	local t = smp_combat.tags[name]
	if not t then return nil end
	if t.expires <= os.time() then
		smp_combat.tags[name] = nil
		return nil
	end
	return t.last_attacker
end

function smp_combat.seconds_left(who)
	local name = smp_combat.name_of(who)
	if not name then return nil end
	local t = smp_combat.tags[name]
	if not t then return nil end
	local left = t.expires - os.time()
	if left <= 0 then
		smp_combat.tags[name] = nil
		return nil
	end
	return left
end

----------------------------------------------------------------------
-- Tag both sides of a hit, honouring the spawn safe zone (f15 §4.2.1:
-- PvP is disabled inside it, so no tag forms there — X10).
----------------------------------------------------------------------

function smp_combat.try_tag_exchange(victim, attacker)
	local vname = smp_combat.name_of(victim)
	local aname = smp_combat.name_of(attacker)
	if not vname or not aname or vname == aname then return false end
	if not smp_combat.pvp_allowed(victim, aname) then return false end
	smp_combat.tag(vname, aname)
	smp_combat.tag(aname, vname)
	return true
end
