-- FriedcakeSMP — smp_ranks acceptance tests
-- Loaded by `/smp test smp_ranks` in-game (once the integrator wires a
-- generic test loader), and by the standalone harness in
-- friedcake/dev-tests/test_ranks.lua. Returns {passed, failed, lines}.
--
-- Covers spec/features/f13-ranks.md §9:
--   T1  grant raises home/auction/order limits; clear reverts them
--   T2  expired tier reads "default" with no record mutation
--   T3  two consecutive 30-day grants stack to now + 60d
--   T4  (API half) expired tier loses the raised limits; consumption
--       beyond the default is enforced by f09/f03/f04
--   T5  chat_prefix is "" with the default configuration
--   T6  /rank set works on an offline player
--   T7  /ranks renders every configured tier from the live config
--   T8  tier1's /rtp cooldown is shorter than the default
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "assertion")
	end
end

local function eq(a, b, msg)
	ok(a == b, string.format("%s: expected %q got %q",
		msg or "eq", tostring(b), tostring(a)))
end

local DAY = 86400
local A = "__t13_a"      -- main test record
local B = "__t13_b"      -- rtp cooldown record
local OFF = "__t13_off"  -- offline-grant record

local function reset(name)
	local rec = smp_store.api.ensure_player(name)
	rec.rank = {}
	smp_store.api.upsert_player(rec)
	smp_ranks.unwatch(name)
	smp_ranks._notified[name] = nil
end

for _, n in ipairs({ A, B, OFF }) do reset(n) end

----------------------------------------------------------------------
-- T1 — limits move with the tier through the perk API
----------------------------------------------------------------------
eq(smp_ranks.tier(A), "default", "T1 fresh record reads default")
eq(smp_ranks.home_limit(A), 2,  "T1 default homes")
eq(smp_ranks.ah_limit(A), 9,    "T1 default auction slots")
eq(smp_ranks.order_limit(A), 9, "T1 default order slots")

smp_ranks.grant(A, "tier1")
eq(smp_ranks.tier(A), "tier1", "T1 tier1 after grant")
eq(smp_ranks.home_limit(A), 9,  "T1 tier1 homes")
eq(smp_ranks.ah_limit(A), 45,   "T1 tier1 auction slots")
eq(smp_ranks.order_limit(A), 45, "T1 tier1 order slots")

smp_ranks.clear(A)
eq(smp_ranks.tier(A), "default", "T1 default after clear")
eq(smp_ranks.home_limit(A), 2,  "T1 homes revert")
eq(smp_ranks.ah_limit(A), 9,    "T1 auction slots revert")
eq(smp_ranks.order_limit(A), 9, "T1 order slots revert")

-- Name-or-player normalisation: every perk function accepts both.
local ref = { get_player_name = function() return A end }
smp_ranks.grant(A, "tier2")
eq(smp_ranks.tier(ref), smp_ranks.tier(A), "tier() accepts a player ref")
eq(smp_ranks.home_limit(ref), smp_ranks.home_limit(A),
	"home_limit() accepts a player ref")
eq(smp_ranks.rtp_cooldown(ref), smp_ranks.rtp_cooldown(A),
	"rtp_cooldown() accepts a player ref")
smp_ranks.clear(A)

----------------------------------------------------------------------
-- T2 — lazy expiry: expired reads default, record untouched
----------------------------------------------------------------------
local rec = smp_store.api.get_player(A)
rec.rank = { tier = "tier2", expires_at = os.time() - 10 }
smp_store.api.upsert_player(rec)
local before = rec.rank.tier .. "@" .. rec.rank.expires_at

eq(smp_ranks.tier(A), "default", "T2 expired tier reads default")
local after_rec = smp_store.api.get_player(A)
eq(after_rec.rank.tier .. "@" .. after_rec.rank.expires_at, before,
	"T2 tier() never mutates the record")

----------------------------------------------------------------------
-- T4 (API half) — expired tier loses the raised limits
----------------------------------------------------------------------
eq(smp_ranks.home_limit(A), 2,  "T4 expired homes back to default")
eq(smp_ranks.ah_limit(A), 9,    "T4 expired auction slots back to default")
eq(smp_ranks.order_limit(A), 9, "T4 expired order slots back to default")

-- Join-time check on an expired rank notifies without mutating.
smp_ranks.check_join(A)
ok(smp_ranks._notified[A] == true, "T4 join check notifies expiry")
eq(smp_ranks._watch[A], nil, "T4 expired record leaves the watch set")
local untouched = smp_store.api.get_player(A)
eq(untouched.rank.tier .. "@" .. untouched.rank.expires_at, before,
	"T4 join check never mutates the record")

----------------------------------------------------------------------
-- T3 — consecutive same-tier grants stack
----------------------------------------------------------------------
smp_ranks.clear(A)
local g1 = smp_ranks.grant(A, "tier1", 30)
local g2 = smp_ranks.grant(A, "tier1", 30)
eq(g2.expires_at - g1.expires_at, 30 * DAY, "T3 second grant adds 30d")
local delta = g2.expires_at - os.time()
ok(delta >= 60 * DAY - 10 and delta <= 60 * DAY + 10,
	"T3 two grants give now + 60d (got delta " .. tostring(delta) .. ")")

-- A different-tier grant restarts the clock instead of stacking.
local g3 = smp_ranks.grant(A, "tier2", 30)
ok(g3.expires_at - os.time() <= 30 * DAY + 10,
	"T3 tier change does not inherit the old expiry")

----------------------------------------------------------------------
-- T5 — no chat prefix by default (V-24)
----------------------------------------------------------------------
eq(smp_ranks.chat_prefix(A), "", "T5 chat_prefix is empty by default")

----------------------------------------------------------------------
-- T6 — offline grant
----------------------------------------------------------------------
local cmd = core.registered_chatcommands["rank"]
ok(cmd ~= nil, "T6 /rank registered")
local okr, msg = cmd.func("__t13_admin", "set " .. OFF .. " tier1")
ok(okr == true, "T6 /rank set succeeds: " .. tostring(msg))
ok(core.get_player_by_name(OFF) == nil, "T6 player is offline during grant")
eq(smp_ranks.tier(OFF), "tier1", "T6 grant visible through tier() offline")
smp_ranks.check_join(OFF)
ok(smp_ranks._watch[OFF] ~= nil, "T6 applies on next join (watched)")
ok(smp_ranks.clear(OFF), "T6 cleanup")

----------------------------------------------------------------------
-- T7 — /ranks renders every configured tier from the live config
----------------------------------------------------------------------
local rows = smp_ranks.tier_rows()
eq(#rows, #smp_ranks.tier_order, "T7 one row per configured tier")
local fs = smp_ranks.formspec()
for _, row in ipairs(rows) do
	ok(fs:find(row.label, 1, true) ~= nil, "T7 row rendered: " .. row.tier)
end
ok(fs:find("Back", 1, true) ~= nil, "T7 Back button")
ok(fs:find("Store", 1, true) ~= nil, "T7 store field label")

-- Prove the numbers come from live config, not literals.
local saved = smp_ranks.slots.homes.tier2
smp_ranks.slots.homes.tier2 = 99
local fs2 = smp_ranks.formspec()
ok(fs2:find("99 homes", 1, true) ~= nil, "T7 reflects live config edits")
smp_ranks.slots.homes.tier2 = saved

local rcmd = core.registered_chatcommands["ranks"]
ok(rcmd ~= nil, "T7 /ranks registered")
local rok = rcmd.func(A, "")
ok(rok == true, "T7 /ranks opens for a player")

----------------------------------------------------------------------
-- T8 — tier1 /rtp cooldown is shorter than the default
----------------------------------------------------------------------
reset(B)
local default_cd = smp_ranks.rtp_cooldown(B)
eq(default_cd, 60, "T8 default cooldown 60s")
smp_ranks.grant(B, "tier1")
local t1_cd = smp_ranks.rtp_cooldown(B)
eq(t1_cd, 30, "T8 tier1 cooldown 30s")
ok(t1_cd < default_cd, "T8 tier1 cooldown shorter than default")
smp_ranks.clear(B)
eq(smp_ranks.rtp_cooldown(B), 60, "T8 cooldown reverts after clear")

----------------------------------------------------------------------
-- CONTRACT — f13 §4.2.4 perk API contract tests (C1 R-01, C2 R-02)
----------------------------------------------------------------------
-- C1: expired tier reads default via perk API, raw record unchanged
local C1 = "__t13_c1"
reset(C1)
local rec_c1 = smp_store.api.get_player(C1)
rec_c1.rank = { tier = "tier1", expires_at = os.time() - 1 }
smp_store.api.upsert_player(rec_c1)
local before_c1 = rec_c1.rank.tier .. "@" .. rec_c1.rank.expires_at

eq(smp_ranks.tier(C1), "default", "C1 expired tier reads default")
eq(smp_ranks.order_limit(C1), 9, "C1 order_limit expired -> default (9)")
eq(smp_ranks.home_limit(C1), 2, "C1 home_limit expired -> default (2)")
-- Raw record still says tier1 — this is why raw reads are wrong
local raw_rec = smp_store.api.get_player(C1)
eq(raw_rec.rank.tier, "tier1", "C1 raw rec.rank.tier still tier1")
eq(raw_rec.rank.expires_at, os.time() - 1, "C1 raw expires_at unchanged")
-- Record must be byte-identical (no mutation by tier()/limit calls)
eq(raw_rec.rank.tier .. "@" .. raw_rec.rank.expires_at, before_c1,
	"C1 record unmutated after perk API calls")

-- C2: rtp_cooldown never nil; live tier2/media fall back to default (60s)
local C2 = "__t13_c2"
reset(C2)
-- Live tier2 record
local rec_c2 = smp_store.api.get_player(C2)
rec_c2.rank = { tier = "tier2", expires_at = os.time() + 86400 }
smp_store.api.upsert_player(rec_c2)
local cd_tier2 = smp_ranks.rtp_cooldown(C2)
eq(cd_tier2, 60, "C2 tier2 rtp_cooldown falls back to default (60s), never nil")

-- Live media record (aliases tier3)
local C2m = "__t13_c2m"
reset(C2m)
local rec_c2m = smp_store.api.get_player(C2m)
rec_c2m.rank = { tier = "media", expires_at = os.time() + 86400 }
smp_store.api.upsert_player(rec_c2m)
local cd_media = smp_ranks.rtp_cooldown(C2m)
eq(cd_media, 60, "C2 media rtp_cooldown falls back to default (60s)")

-- Counterpart: live tier1 returns 30s (already covered by T8, but pin here)
reset(C2)
smp_ranks.grant(C2, "tier1")
eq(smp_ranks.rtp_cooldown(C2), 30, "C2 tier1 rtp_cooldown 30s")

----------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------
for _, n in ipairs({ A, B, OFF, C1, C2, C2m }) do reset(n) end

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_ranks tests passed."
else
	results.lines[#results.lines + 1] =
		string.format("%d failures.", results.failed)
end
return results
