-- FriedcakeSMP — smp_combat acceptance tests
-- Loaded by `/smp test smp_combat` in-game (the /smp test dispatcher in
-- smp_economy needs the generic loader proposed in f10 §10; until it
-- lands, run the standalone smoke tests:
--   luajit friedcake/dev-tests/test_combat.lua  covers T1–T7, T11, T12)
--
-- This file exercises the pure tag / block / attribution surface against
-- the LIVE engine. Tests cover spec/features/f10-combat.md §9 T1, T3 and
-- parts of T11/T12; the drop/credit paths need connected players and are
-- covered by the dev harness.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator and core.get_translator("smp_combat")
	or function(s, ...) return s end

local results = { passed = 0, failed = 0, lines = {} }

local function eq(a, b, msg)
	if a == b then
		results.passed = results.passed + 1
		return true
	end
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] =
		string.format("FAIL %s: expected %q got %q",
			msg or "eq", tostring(b), tostring(a))
	return false
end

local function yes(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "true")
	end
end

local A, B = "f10_test_a", "f10_test_b"

-- T1: tag, duration, refresh.
smp_combat.untag(A)
smp_combat.untag(B)
smp_combat.tag(A, B)
yes(smp_combat.is_tagged(A), "T1 tag sets is_tagged")
eq(smp_combat.last_attacker(A), B, "T1 last_attacker recorded")
local first = smp_combat.tags[A].expires
yes(first > os.time(), "T1 expires in the future")
yes(first <= os.time() + smp_combat.cfg.combat.tag_seconds,
	"T1 expires within combat.tag_seconds")

-- Simulate an aged tag, then refresh with a second hit.
smp_combat.tags[A].expires = os.time() + 5
smp_combat.tag(A, B)
yes(smp_combat.tags[A].expires >= first
	or smp_combat.tags[A].expires > os.time() + 5,
	"T1 second hit refreshes the timer")

-- Lazy expiry: an elapsed tag reports false and disappears.
smp_combat.tags[A].expires = os.time() - 1
eq(smp_combat.is_tagged(A), false, "T11 expired tag reports false")
eq(smp_combat.tags[A], nil, "T11 expired tag is dropped")
smp_combat.untag(B)

-- is_tagged accepts ObjectRefs (f05 bridge) as well as names.
for _, p in ipairs(core.get_connected_players()) do
	yes(smp_combat.is_tagged(p) == false or smp_combat.is_tagged(p) == true,
		"is_tagged accepts an ObjectRef without erroring")
	break
end

-- T3: the blocked-command list, and the allowed commands.
local BLOCKED = {
	"rtp", "rtpqueue", "tpa", "tp", "tpahere", "tpaccept",
	"homes", "home", "spawn", "warp", "world", "shop",
	"kill", -- S07/CB-2: no self-kill credit handover while tagged
}
for _, cmd in ipairs(BLOCKED) do
	yes(smp_combat.blocks.is_blocked(cmd), "T3 /" .. cmd .. " is blocked")
end
for _, cmd in ipairs({ "sell", "msg", "ah", "bounty" }) do
	yes(not smp_combat.blocks.is_blocked(cmd),
		"T3 /" .. cmd .. " is allowed in combat")
end

-- CB-1 (S07): the combat-log drop registered LAST — deferred to
-- on_mods_loaded, after every mod's load-time registration (the list
-- is plain append, so "last registered" is "runs last").
if core.registered_on_leaveplayers then
	eq(core.registered_on_leaveplayers[#core.registered_on_leaveplayers],
		smp_combat.on_leave,
		"CB-1 the combat-log drop is the last leave handler")
end

-- Refusals only fire while tagged.
eq(smp_combat.on_chatcommand(A, "rtp", ""), nil,
	"T3 untagged players pass through")
smp_combat.tag(A, B)
eq(smp_combat.on_chatcommand(A, "rtp", ""), true,
	"T3 /rtp cancelled while tagged")
eq(smp_combat.on_chatcommand(A, "sell", ""), nil,
	"T3 /sell works while tagged")
smp_combat.untag(A)

-- killer_from: environment reasons have no attacker.
eq(smp_combat.killer_from({ type = "fall" }), nil, "killer_from fall -> nil")
eq(smp_combat.killer_from("punch"), nil, "killer_from string -> nil")
eq(smp_combat.killer_from({ type = "punch" }), nil,
	"killer_from punch without object -> nil")

-- Explosion ring: in-window proximity, exclusion, no stale hits.
smp_combat.attribution.prune(1e12) -- empty the ring
smp_combat.attribution.record({ x = 100, y = 10, z = 100 }, "f10_test_p")
eq(smp_combat.attribution.nearest_placer({ x = 105, y = 10, z = 100 }),
	"f10_test_p", "ring: nearby placer found")
eq(smp_combat.attribution.nearest_placer({ x = 105, y = 10, z = 100 },
	"f10_test_p"), nil, "ring: victim excluded")
eq(smp_combat.attribution.nearest_placer({ x = 500, y = 10, z = 500 }),
	nil, "ring: far away -> none")

-- Safe zone predicate (X10 with f15).
yes(smp_combat.in_safe_zone({ x = 0, y = 8, z = 0 }),
	"spawn centre is inside the safe zone")
yes(not smp_combat.in_safe_zone({ x = 1000, y = 8, z = 1000 }),
	"far away is outside the safe zone")

-- Untag both helpers; never leave test state behind.
smp_combat.untag(A)
smp_combat.untag(B)
smp_combat.untag("f10_test_p")
eq(smp_combat.is_tagged(A), false, "cleanup: untagged")

results.lines[#results.lines + 1] = string.format(
	"smp_combat: passed=%d failed=%d", results.passed, results.failed)
return results
