-- FriedcakeSMP — smp_rtpqueue acceptance tests
-- Loaded by `/smp test smp_rtpqueue` in-game.
--
-- In-game-safe slice of spec/features/f08-teleport.md §4.3 and
-- spec/plan/acceptance-tests.md T11. Pairing, timeout and exit
-- behaviour are covered by friedcake/dev-tests/test_tp.lua (fake
-- engine); this file checks the live surface:
--   * /rtpqueue is registered (a join/leave TOGGLE — no parameter)
--   * the queue state table and the configured limits
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

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

ok(core.registered_chatcommands["rtpqueue"] ~= nil,
	"/rtpqueue registered")
ok(smp_rtpqueue ~= nil, "smp_rtpqueue present")
ok(type(smp_rtpqueue.members) == "table", "queue member table present")

-- Config lives in smp_tp.cfg.rtpqueue (smp_rtpqueue has no own config).
local qcfg = smp_tp and smp_tp.cfg and smp_tp.cfg.rtpqueue
ok(type(qcfg) == "table", "smp_tp.cfg.rtpqueue present")
if qcfg then
	eq(qcfg.timeout, 300, "queue timeout is 300 s")
	eq(qcfg.min_separation, 16, "min pair separation is 16")
	eq(qcfg.max_separation, 32, "max pair separation is 32")
end

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_rtpqueue tests passed."
else
	results.lines[#results.lines + 1] = string.format(
		"%d failures.", results.failed)
end
return results
