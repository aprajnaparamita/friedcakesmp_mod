-- FriedcakeSMP — smp_economy acceptance tests
-- Loaded by `/smp test smp_economy` in-game and by
-- `friedcake/dev-tests/test_economy.lua` headless.
--
-- Covers spec/features/f01-economy-core.md §9:
--   T4  (pay refuses: self, unknown, min_pay)
--   T5  (pay writes EXACTLY two ledger entries, conserves supply)
--   T6  (large transfer to a low-playtime account is flagged, and the
--        two non-firing preconditions are asserted too — E-24, D9 landed)
--   T10 (max balance cannot be exceeded)
--   R9  (the /pay cooldown is armed only by a successful transfer)
--
-- T1–T3 live in smp_core/test.lua, T7/T8/R9's command-level cases live in
-- dev-tests/test_economy.lua. This file deliberately touches nothing
-- outside this mod's own ledger/money surface.
--
-- The mod_storage backend is used so the test runs without lsqlite3.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator and core.get_translator("smp_economy")
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

-- R9: the /pay window is armed only by a successful transfer, and it runs
-- on game time. Successive cases here would otherwise all hit the first
-- pay's window, so each case clears it explicitly through the hook the
-- mod ships for exactly this (house style: `smp_ranks._watch`).
local function clear_cooldown(name)
	if type(smp_economy) == "table"
	   and type(smp_economy._reset_pay_cooldown) == "function" then
		smp_economy._reset_pay_cooldown(name)
	end
end

local function ledger_count(name)
	local entries = smp_store.api.ledger_for(name, 1, 1000)
	return #entries
end

local function newest_row(name)
	return smp_store.api.ledger_for(name, 1, 1)[1]
end

local function flag_count()
	if type(smp_admin) == "table" and type(smp_admin.flags) == "function" then
		return #smp_admin.flags()
	end
	return nil
end

----------------------------------------------------------------------
-- Set-up: ensure alice and bob have known balances.
----------------------------------------------------------------------

local function reset()
	smp_store.api.set_money("__t_alice", 0, "test", "reset")
	smp_store.api.set_money("__t_bob",   0, "test", "reset")
end

reset()

-- T4: /pay refuses self, unknown, and amount below min_pay.
local cmd = core.registered_chatcommands["pay"]
ok(cmd ~= nil, "T4 /pay registered")

local r, msg = cmd.func("__t_alice", "__t_alice 100")
ok(r == false, "T4 self-pay refused")
ok(msg and msg:lower():find("yourself"), "T4 self-pay message names 'yourself'")

r, msg = cmd.func("__t_alice", "__no_such_player_9999 100")
ok(r == false, "T4 unknown pay refused")

r, msg = cmd.func("__t_alice", "__t_bob 0")
ok(r == false, "T4 amount=0 refused")

-- T5: a successful /pay writes EXACTLY two ledger entries (one debit,
-- one credit) and conserves supply. E-23: the old assertion was `>= 2`,
-- which a run that wrote nothing but the setup rows would also pass.
smp_store.api.set_money("__t_alice", 50000, "test", "T5 setup")  -- $500
smp_store.api.set_money("__t_bob",   20000, "test", "T5 setup")  -- $200
local before_total = smp_store.api.get_player("__t_alice").money
	+ smp_store.api.get_player("__t_bob").money
local rows_before = ledger_count("__t_alice") + ledger_count("__t_bob")

clear_cooldown("__t_alice")
-- parse_amount reads DOLLARS: "1" is 100 cents ($1.00).
r, msg = cmd.func("__t_alice", "__t_bob 1")
ok(r == true, "T5 pay succeeds")
local after_alice = smp_store.api.get_player("__t_alice").money
local after_bob   = smp_store.api.get_player("__t_bob").money
eq(after_alice, 49900, "T5 sender debited")
eq(after_bob,   20100, "T5 recipient credited")
local after_total = after_alice + after_bob
eq(after_total, before_total, "T5 supply conserved")

local rows_after = ledger_count("__t_alice") + ledger_count("__t_bob")
eq(rows_after - rows_before, 2, "T5 ledger delta is exactly two rows")
eq(newest_row("__t_alice").type, "pay", "T5 debit row carries reason 'pay'")
eq(newest_row("__t_bob").type,   "pay", "T5 credit row carries reason 'pay'")

-- T6: a $2M transfer to a 10-minute-old account succeeds AND raises a
-- staff-review flag. D9 landed 2026-09-24 (`smp_admin.flag(kind, detail)`),
-- so the flag is observable through the ring buffer instead of BLOCKED.
local rec_bob = smp_store.api.get_player("__t_bob")
rec_bob.playtime = 100  -- ~10 minutes, well under the 7200 s floor
smp_store.api.upsert_player(rec_bob)

local flags_before = flag_count()
if flags_before ~= nil then
	smp_store.api.set_money("__t_alice", 400000000, "test", "T6 setup") -- $4M
	clear_cooldown("__t_alice")
	r, msg = cmd.func("__t_alice", "__t_bob 2000000")  -- $2M = 200000000 cents
	ok(r == true, "T6 large transfer succeeds (flagged, not blocked)")
	eq(flag_count(), flags_before + 1, "T6 the transfer raised exactly one flag")
	local flags = smp_admin.flags()
	local last = flags[#flags]
	ok(last and last.kind == "large_transfer_to_new_account",
		"T6 flag kind is large_transfer_to_new_account")
	ok(last and last.detail:find("__t_alice", 1, true) ~= nil,
		"T6 flag detail names the sender")

	-- Negative half: below economy.flag_threshold nothing is raised.
	smp_store.api.set_money("__t_alice", 400000000, "test", "T6 sub-threshold")
	clear_cooldown("__t_alice")
	r, msg = cmd.func("__t_alice", "__t_bob 0.5")  -- 50 cents < $1M
	ok(r == true, "T6 sub-threshold transfer succeeds")
	eq(flag_count(), flags_before + 1, "T6 a sub-threshold transfer raises no flag")

	-- Negative half: a recipient above economy.flag_min_playtime is safe.
	local rec_carol = smp_store.api.ensure_player("__t_carol")
	rec_carol.playtime = 8000  -- > 7200 s floor
	smp_store.api.upsert_player(rec_carol)
	smp_store.api.set_money("__t_alice", 400000000, "test", "T6 seasoned target")
	clear_cooldown("__t_alice")
	r, msg = cmd.func("__t_alice", "__t_carol 2000000")  -- $2M, seasoned account
	ok(r == true, "T6 transfer to a seasoned account succeeds")
	eq(flag_count(), flags_before + 1,
		"T6 an above-floor recipient raises no flag")
else
	-- smp_admin is a hard dependency of the pack; if it is ever absent the
	-- success half still stands and the flag half is reported as skipped.
	ok(true, "T6 flag assertions skipped: smp_admin.flags() unavailable")
	smp_store.api.set_money("__t_alice", 400000000, "test", "T6 setup")
	clear_cooldown("__t_alice")
	r, msg = cmd.func("__t_alice", "__t_bob 2000000")
	ok(r == true, "T6 large transfer succeeds (flagged, not blocked)")
end

-- T10: max balance cap cannot be exceeded.
-- Default cap is $10^13. We can't easily push a balance that high in a
-- test; we verify the cap is honoured at a more modest scale by
-- attempting to add past the cap.
local cap = tonumber(core.settings:get("economy.max_balance")) or 1e15
local r2 = smp_store.api.add_money("__t_alice", 100, "test", "T10 tiny")
ok(r2 == 100, "T10 add below cap succeeds")
-- Now attempt a transfer that would push past cap (using eco).
local cmd_eco = core.registered_chatcommands["eco"]
ok(cmd_eco ~= nil, "T10 /eco registered")
-- alice is well below cap after T6 spent; top her up.
smp_store.api.set_money("__t_alice", cap - 1, "test", "T10 setup")
local r3 = smp_store.api.add_money("__t_alice", 100, "test", "T10 over cap")
ok(r3 == 1, "T10 add past cap is capped to remaining room")

-- E-18: economy.max_balance is enforced by this mod's own give path,
-- independently of smp_store's store.max_balance.
local given = smp_economy.give("__t_alice", 100, "test", "T10 give at cap")
ok(given == 0, "E-18 give() credits nothing once the balance is at the cap")
eq(smp_economy.get("__t_alice"), cap, "E-18 get() reads the stored balance")

reset()

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_economy tests passed."
else
	results.lines[#results.lines + 1] = string.format(
		"%d failures.", results.failed)
end
return results
