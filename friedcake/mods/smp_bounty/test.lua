-- FriedcakeSMP — smp_bounty acceptance tests
-- Loaded by `/smp test smp_bounty` in-game (the /smp test dispatcher in
-- smp_economy needs the generic loader proposed in f10 §10; until it
-- lands, run the standalone smoke tests:
--   luajit friedcake/dev-tests/test_bounty.lua  covers T8, T9, T10)
--
-- This file exercises escrow stacking, the ledger codes, the refund and
-- the abuse predicates against the LIVE engine and the live store.
-- Uses __f10_* scratch players and resets their money afterwards.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

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

local C, C2, POOR, T = "__f10_c", "__f10_c2", "__f10_poor", "__f10_t"

local function seed(name, cents)
	smp_store.api.ensure_player(name)
	smp_store.api.set_money(name, cents, "admin", "f10 test setup")
end
local function money(name)
	local r = smp_store.api.get_player(name)
	return r and r.money or 0
end
local function has_ledger(name, ltype, amount)
	local entries = smp_store.api.ledger_for(name, 1, 100)
	for _, e in ipairs(entries or {}) do
		if e.type == ltype and e.amount == amount then return true end
	end
	return false
end

-- Fresh scratch state (a previous aborted run must not leak).
if smp_bounty.get(T) then smp_bounty.escrow_refund(smp_bounty.get(T)) end
seed(C, 5000000)
seed(C2, 5000000)
seed(POOR, 0)
smp_store.api.ensure_player(T)

-- T8: escrow debits the contributor and stacks.
local c0 = money(C)
local b, err = smp_bounty.escrow_deposit(C, T, 500000)
yes(b and not err, "T8 deposit succeeds")
eq(money(C), c0 - 500000, "T8 contributor debited immediately")
eq(b.total, 500000, "T8 escrow equals the contribution")
yes(has_ledger(C, "bounty_escrow", -500000),
	"T8 ledger code bounty_escrow")

local c2_0 = money(C2)
b, err = smp_bounty.escrow_deposit(C2, T, 300000)
yes(b and not err, "T8 second deposit succeeds")
eq(money(C2), c2_0 - 300000, "T8 second contributor debited")
eq(b.total, 800000, "T8 contributions stack into one total")
eq(b.contributors[C], 500000, "T8 contributor 1 recorded")
eq(b.contributors[C2], 300000, "T8 contributor 2 recorded")

-- Refusals: min, self, funds.
local _, e_min = smp_bounty.escrow_deposit(C, T, 500)
eq(e_min, "min", "T8 below-minimum refused")
local _, e_self = smp_bounty.escrow_deposit(T, T, 500000)
eq(e_self, "self", "T8 self-bounty refused")
local _, e_funds = smp_bounty.escrow_deposit(POOR, T, 100000)
eq(e_funds, "funds", "T8 insufficient funds refused")
eq(money(POOR), 0, "T8 refused deposit debits nothing")

-- T10: refund every contributor in full, remove the bounty.
local r0, r2 = money(C), money(C2)
local refunded = smp_bounty.escrow_refund(b)
eq(refunded, 800000, "T10 refund equals the escrow")
eq(money(C), r0 + 500000, "T10 contributor 1 refunded in full")
eq(money(C2), r2 + 300000, "T10 contributor 2 refunded in full")
eq(smp_bounty.get(T), nil, "T10 bounty removed")
yes(has_ledger(C, "bounty_payout", 500000),
	"T10 refund ledger code bounty_payout")

-- T9: abuse predicates (zone and cooldown; the IP rule needs two
-- connected players and is covered by dev-tests/test_bounty.lua).
yes(smp_bounty.is_abuse(C, T, { x = 0, y = 8, z = 0 }),
	"T9 no payout inside the safe zone")
yes(not smp_bounty.is_abuse(C2, T, { x = 1000, y = 8, z = 1000 }),
	"T9 payout allowed outside the safe zone")

smp_bounty.abuse.record_claim("__f10_k", "__f10_v")
yes(smp_bounty.is_abuse("__f10_k", "__f10_v", { x = 1000, y = 8, z = 1000 }),
	"T9 pair cooldown refuses a repeat claim")
smp_bounty.db.claims["__f10_k|__f10_v"] = nil
smp_bounty.save()
yes(not smp_bounty.is_abuse("__f10_k", "__f10_v", { x = 1000, y = 8, z = 1000 }),
	"T9 cooldown record clears")

-- No claim without a bounty.
eq(smp_bounty.try_claim(C, T, { x = 1000, y = 8, z = 1000 }), false,
	"claim with no bounty does nothing")

-- Cleanup scratch money.
smp_store.api.set_money(C, 0, "admin", "f10 test cleanup")
smp_store.api.set_money(C2, 0, "admin", "f10 test cleanup")
if smp_bounty.get(T) then smp_bounty.escrow_refund(smp_bounty.get(T)) end

results.lines[#results.lines + 1] = string.format(
	"smp_bounty: passed=%d failed=%d", results.passed, results.failed)
return results
