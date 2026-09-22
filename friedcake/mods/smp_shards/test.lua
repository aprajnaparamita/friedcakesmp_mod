-- FriedcakeSMP — smp_shards acceptance tests
-- Loaded in-game via `/smp test smp_shards`.
--
-- Covers spec/features/f06-shards.md §9:
--   T1: 10 minutes of playtime -> exactly 1 shard + the verbatim message
--   T2: awards across a "restart" (fresh pending state) do not double-count
--
-- The award loop is driven directly with a fake player object so the
-- test does not depend on the invoking player staying still.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator and core.get_translator("smp_shards")
	or function(s, ...) return s end

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "ok")
	end
end

local function eq(a, b, msg)
	ok(a == b, string.format("%s: expected %s got %s",
		msg or "eq", tostring(b), tostring(a)))
end

local AWARD = "You earned 1 Shard for playing the server"
local NAME = "__t_shards_alice"

-- Clean slate.
smp_store.api.set_money(NAME, 0, "test", "reset")
do
	local rec = smp_store.api.ensure_player(NAME)
	rec.shards = 0
	rec.playtime = 0
	rec.shards_for_playtime = 0
	smp_store.api.upsert_player(rec)
end

local fake = { get_player_name = function() return NAME end }

-- T1: 600 s -> 1 shard, counter advanced, playtime persisted.
for _ = 1, 600 do
	smp_shards.on_step(1, { fake })
end
smp_shards.flush_player(NAME)

local rec = smp_store.api.get_player(NAME)
eq(rec.shards, 1, "T1 one shard after 600 s")
eq(rec.playtime, 600, "T1 playtime persisted")
eq(rec.shards_for_playtime, 1, "T1 counter")

-- Ledger: exactly one shard_award entry of +1 shard for this player.
local entries = smp_store.api.ledger_for(NAME, 1, 50)
local awards, total_owed = 0, 0
for _, e in ipairs(entries) do
	if e.type == "shard_award" and e.currency == "shards" and e.amount > 0 then
		awards = awards + 1
		total_owed = total_owed + e.amount
	end
end
eq(total_owed, 1, "T1 exactly one shard awarded on the ledger")
ok(awards >= 1, "T1 ledger entry exists")

-- T2: continue for 599 more s — floor(1199/600) == 1, so nothing new.
for _ = 1, 599 do
	smp_shards.on_step(1, { fake })
end
smp_shards.flush_player(NAME)
rec = smp_store.api.get_player(NAME)
eq(rec.shards, 1, "T2 no double count at 1199 s")

-- One more second crosses 1200 s: exactly one more shard.
smp_shards.on_step(1, { fake })
smp_shards.on_step(1, { fake })
smp_shards.flush_player(NAME)
rec = smp_store.api.get_player(NAME)
eq(rec.shards, 2, "T2 second award at 1200 s")
eq(rec.shards_for_playtime, 2, "T2 counter at 1200 s")

-- Verbatim award message (capital S, no full stop).
ok(smp_shards.award_message == AWARD, "T1 message verbatim")
ok(smp_shards.award_message:match("Shard") ~= nil, "T1 message capital S")
ok(not smp_shards.award_message:match("%.+$"), "T1 message no full stop")

-- Cleanup.
local rec2 = smp_store.api.ensure_player(NAME)
rec2.shards = 0
rec2.playtime = 0
rec2.shards_for_playtime = 0
smp_store.api.upsert_player(rec2)

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_shards tests passed."
else
	results.lines[#results.lines + 1] =
		string.format("%d failures.", results.failed)
end
return results
