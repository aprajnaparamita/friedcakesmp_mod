-- FriedcakeSMP — smp_admin acceptance tests (rulings D9 + D10)
-- Loaded by `/smp test smp_admin` in-game (once the integrator wires a
-- generic test loader), and by the standalone harness in
-- friedcake/dev-tests/test_admin.lua. Returns {passed, failed, lines}.
--
-- Case names match the harness one-for-one:
--   T1  flag appends, returns an id, flags() is oldest-first
--   T2  flag ring cap evicts the oldest of 501 appends
--   T3  flag logs one warning and notifies exactly the online staff
--   T4  flag never notifies offline or unprivileged players
--   T5  mute -> is_muted true, with remaining seconds (offline name)
--   T6  permanent mute (no seconds / 0) -> true with no expiry
--   T7  lazy expiry under a stubbed os.time: future true, past false
--       and the entry cleaned up on read
--   T8  unmute clears; second unmute is a safe no-op
--   T9  /mute parses 90, permanent and omitted; rejects 'abc' with
--       usage; requires smp_moderator OR smp_admin
--   T10 /unmute requires the privilege and reports 'not muted'
--
-- Two environment seams are swapped (chat/log capture in observe(),
-- get_player_privs in run_cmd()) and restored on every path, so an
-- in-game run never floods real staff chat with test notices and the
-- command cases are hermetic no matter who triggers the suite. Nothing
-- yields while a seam is swapped.
--
-- Known residue: the flag ring has no reset API by design, so after T2
-- the buffer's 500 entries are test flags (`test_api`/`test_ring`/...).
-- That is a dev-world-only side effect of `/smp test smp_admin`; mute
-- entries are cleaned up below.
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

local T5N = "__p4_t5"
local T6A = "__p4_t6a"
local T6B = "__p4_t6b"
local T7N = "__p4_t7"
local T8N = "__p4_t8"
local T9A, T9B, T9C, T9D, T9E, T9F, T9NEG =
	"__p4_t9a", "__p4_t9b", "__p4_t9c", "__p4_t9d", "__p4_t9e", "__p4_t9f",
	"__p4_t9neg"
local T10B, T10C = "__p4_t10b", "__p4_t10c"

local CALL_MOD     = "__p4_mod"
local CALL_ADMIN   = "__p4_admin"
local CALL_PEASANT = "__p4_peasant"
local FAKE_PRIVS = {
	[CALL_MOD]     = { smp_moderator = true },
	[CALL_ADMIN]   = { smp_admin = true },
	[CALL_PEASANT] = {},
}

-- Runs fn with core.chat_send_player and core.log captured, restoring
-- both on every path (fn runs under pcall).
local function observe(fn)
	local sent, logged = {}, {}
	local real_chat, real_log = core.chat_send_player, core.log
	core.chat_send_player = function(name, msg)
		sent[#sent + 1] = { name = name, msg = msg }
	end
	core.log = function(level, msg)
		logged[#logged + 1] = { level = level, msg = msg }
	end
	local okc, err = pcall(fn)
	core.chat_send_player, core.log = real_chat, real_log
	return sent, logged, okc, err
end

-- Runs a chatcommand as `caller` with exactly the privileges in
-- FAKE_PRIVS, restoring core.get_player_privs on every path. The mute
-- commands check smp_moderator OR smp_admin inside func (Luanti has no
-- privilege hierarchy), so the suite grants and withholds them itself.
local function run_cmd(cmd, caller, param)
	local real = core.get_player_privs
	core.get_player_privs = function(name) return FAKE_PRIVS[name] or {} end
	local okc, r, msg = pcall(cmd.func, caller, param)
	core.get_player_privs = real
	if not okc then return nil, tostring(r) end
	return r, msg
end

----------------------------------------------------------------------
-- T1 — flag appends, returns an id; flags() is oldest-first
----------------------------------------------------------------------
local id1
local _, _, okc1 = observe(function()
	id1 = smp_admin.flag("test_api", "T1 detail")
end)
ok(okc1, "T1 flag() runs cleanly")
ok(type(id1) == "number" and id1 > 0, "T1 flag returns an id: " .. tostring(id1))
local list = smp_admin.flags()
ok(#list > 0, "T1 flags() non-empty after a flag")
local found, oldest_first = nil, true
for i, e in ipairs(list) do
	if e.id == id1 then found = e end
	if i > 1 and list[i - 1].id > e.id then oldest_first = false end
end
ok(found ~= nil and found.kind == "test_api" and found.detail == "T1 detail",
	"T1 entry persisted with kind and detail")
ok(oldest_first, "T1 flags() is an oldest-first copy")

----------------------------------------------------------------------
-- T2 — ring cap: 501 appends leave 500, the oldest gone
----------------------------------------------------------------------
local ids = {}
observe(function()
	for i = 1, 501 do
		ids[#ids + 1] = smp_admin.flag("test_ring", "entry " .. i)
	end
end)
list = smp_admin.flags()
eq(#list, 500, "T2 ring cap holds 500 after 501 appends")
eq(list[#list].id, ids[501], "T2 newest entry kept")
eq(list[1].id, ids[2], "T2 eviction drops exactly the oldest new entry")
local has_oldest = false
for _, e in ipairs(list) do
	if e.id == ids[1] then has_oldest = true end
end
ok(not has_oldest, "T2 first entry evicted from the ring")

----------------------------------------------------------------------
-- T3 — one warning logged, exactly the online staff notified
----------------------------------------------------------------------
local expected = {}
for _, p in ipairs(core.get_connected_players()) do
	local who = p:get_player_name()
	local privs = core.get_player_privs(who) or {}
	if privs.smp_admin or privs.smp_moderator then expected[who] = true end
end
local sent, logged, okc3 = observe(function()
	smp_admin.flag("test_log", "T3 detail")
end)
ok(okc3, "T3 flag() runs cleanly")
local warned = 0
for _, rec in ipairs(logged) do
	if rec.level == "warning"
			and rec.msg == "[smp_admin] flag test_log T3 detail" then
		warned = warned + 1
	end
end
eq(warned, 1, "T3 exactly one warning in the mandated format")
local got, exact = {}, true
for _, s in ipairs(sent) do
	if got[s.name] then exact = false end
	got[s.name] = true
	if not expected[s.name] then exact = false end
end
for who in pairs(expected) do
	if not got[who] then exact = false end
end
ok(exact, "T3 notified exactly the online staff")

----------------------------------------------------------------------
-- T4 — nobody offline and nobody unprivileged hears about a flag
----------------------------------------------------------------------
local sent4, _, okc4 = observe(function()
	smp_admin.flag("test_offline", "T4 detail")
end)
ok(okc4, "T4 flag() runs cleanly")
local all_staff = true
for _, s in ipairs(sent4) do
	local privs = core.get_player_privs(s.name) or {}
	if not (privs.smp_admin or privs.smp_moderator) then all_staff = false end
end
ok(all_staff, "T4 no unprivileged player was notified")
local connected = {}
for _, p in ipairs(core.get_connected_players()) do
	connected[p:get_player_name()] = true
end
local all_online = true
for _, s in ipairs(sent4) do
	if not connected[s.name] then all_online = false end
end
ok(all_online, "T4 no offline player was notified")

----------------------------------------------------------------------
-- T5 — mute reads back with remaining seconds (storage-backed name)
----------------------------------------------------------------------
smp_admin.mute(T5N, 90)
local m5, r5 = smp_admin.is_muted(T5N)
ok(m5 == true, "T5 is_muted true for a fresh 90s mute")
ok(type(r5) == "number" and r5 > 0 and r5 <= 90,
	"T5 remaining seconds in (0, 90] (got " .. tostring(r5) .. ")")
eq(smp_admin.is_muted("__p4_never"), false, "T5 unknown name reads not muted")

----------------------------------------------------------------------
-- T6 — permanent mutes report no remaining time
----------------------------------------------------------------------
smp_admin.mute(T6A) -- no seconds at all
local m6, r6 = smp_admin.is_muted(T6A)
ok(m6 == true, "T6 mute without seconds is active")
ok(r6 == nil, "T6 permanent mute reports no remaining seconds")
smp_admin.mute(T6B, 0)
m6, r6 = smp_admin.is_muted(T6B)
ok(m6 == true and r6 == nil, "T6 seconds=0 is permanent too")

----------------------------------------------------------------------
-- T7 — lazy expiry under a stubbed os.time (save/restore, no yields)
----------------------------------------------------------------------
local real_time = os.time
local base = real_time()
local now = base
local fut_m, fut_r, past_m, clean_m
os.time = function() return now end
local okc7, err7 = pcall(function()
	smp_admin.mute(T7N, 100)
	now = base + 50
	fut_m, fut_r = smp_admin.is_muted(T7N)
	now = base + 200
	past_m = smp_admin.is_muted(T7N)
	now = base + 50 -- a moment at which the entry would still be live
	clean_m = smp_admin.is_muted(T7N)
end)
os.time = real_time
ok(okc7, "T7 runs under a stubbed clock: " .. tostring(err7))
ok(fut_m == true, "T7 future expiry reads muted")
eq(fut_r, 50, "T7 remaining = 50s at base+50")
ok(past_m == false, "T7 past expiry reads not muted")
ok(clean_m == false, "T7 expired entry cleaned up on read")

----------------------------------------------------------------------
-- T8 — unmute clears; second unmute is a safe no-op
----------------------------------------------------------------------
smp_admin.mute(T8N, 60)
eq(smp_admin.unmute(T8N), true, "T8 first unmute returns true")
eq(smp_admin.is_muted(T8N), false, "T8 not muted after unmute")
eq(smp_admin.unmute(T8N), false, "T8 second unmute returns false, no throw")
eq(smp_admin.unmute("__p4_never_muted"), false,
	"T8 unmute of an unknown name returns false, no throw")
eq(smp_admin.is_muted(nil), false, "T8 is_muted(nil) is false, no throw")

----------------------------------------------------------------------
-- T9 — /mute: parsing, duration and the privilege check
----------------------------------------------------------------------
local mute_cmd = core.registered_chatcommands["mute"]
ok(mute_cmd ~= nil, "T9 /mute registered")
local r, msg = run_cmd(mute_cmd, CALL_MOD, T9A .. " 90")
ok(r == true, "T9 /mute <player> 90 succeeds: " .. tostring(msg))
ok(msg ~= nil and msg:find(T9A, 1, true) ~= nil
		and msg:find("90", 1, true) ~= nil,
	"T9 reply names target and duration: " .. tostring(msg))
local m9, r9 = smp_admin.is_muted(T9A)
ok(m9 == true and type(r9) == "number" and r9 <= 90,
	"T9 90s mute applied with remaining seconds")
r = run_cmd(mute_cmd, CALL_ADMIN, T9B .. " 60")
ok(r == true, "T9 smp_admin alone passes the check (no priv hierarchy)")
r, msg = run_cmd(mute_cmd, CALL_MOD, T9C .. " permanent")
ok(r == true and msg ~= nil and msg:find("permanent", 1, true) ~= nil,
	"T9 literal 'permanent' accepted: " .. tostring(msg))
m9, r9 = smp_admin.is_muted(T9C)
ok(m9 == true and r9 == nil, "T9 'permanent' is a permanent mute")
r, msg = run_cmd(mute_cmd, CALL_MOD, T9D)
ok(r == true and msg ~= nil and msg:find("permanent", 1, true) ~= nil,
	"T9 omitted duration means permanent: " .. tostring(msg))
m9, r9 = smp_admin.is_muted(T9D)
ok(m9 == true and r9 == nil, "T9 omitted duration stored as permanent")
r, msg = run_cmd(mute_cmd, CALL_MOD, T9E .. " abc")
ok(r == false and msg ~= nil and msg:find("Usage", 1, true) ~= nil,
	"T9 non-numeric duration rejected with usage: " .. tostring(msg))
eq(smp_admin.is_muted(T9E), false, "T9 rejected duration changes no state")
r, msg = run_cmd(mute_cmd, CALL_MOD, T9NEG .. " -5")
ok(r == false and msg ~= nil and msg:find("Usage", 1, true) ~= nil,
	"T9 negative duration rejected with usage: " .. tostring(msg))
eq(smp_admin.is_muted(T9NEG), false, "T9 negative duration changes no state")
r, msg = run_cmd(mute_cmd, CALL_MOD, "")
ok(r == false and msg ~= nil and msg:find("Usage", 1, true) ~= nil,
	"T9 missing target rejected with usage")
r, msg = run_cmd(mute_cmd, CALL_PEASANT, T9F .. " 60")
ok(r == false and msg ~= nil and msg:find("privilege", 1, true) ~= nil,
	"T9 player without either privilege gets the deny message: "
		.. tostring(msg))
eq(smp_admin.is_muted(T9F), false, "T9 denied call changes no state")

----------------------------------------------------------------------
-- T10 — /unmute: privilege and the 'not muted' response
----------------------------------------------------------------------
local unmute_cmd = core.registered_chatcommands["unmute"]
ok(unmute_cmd ~= nil, "T10 /unmute registered")
r, msg = run_cmd(unmute_cmd, CALL_PEASANT, T10B)
ok(r == false and msg ~= nil and msg:find("privilege", 1, true) ~= nil,
	"T10 /unmute requires a privilege: " .. tostring(msg))
smp_admin.mute(T10C, 30)
r, msg = run_cmd(unmute_cmd, CALL_MOD, T10C)
ok(r == true, "T10 /unmute clears an existing mute: " .. tostring(msg))
eq(smp_admin.is_muted(T10C), false, "T10 target reads not muted afterwards")
r, msg = run_cmd(unmute_cmd, CALL_MOD, T10B)
ok(r == false and msg ~= nil and msg:find("not muted", 1, true) ~= nil,
	"T10 'not muted' reported when there was no entry: " .. tostring(msg))
r, msg = run_cmd(unmute_cmd, CALL_MOD, "")
ok(r == false and msg ~= nil and msg:find("Usage", 1, true) ~= nil,
	"T10 missing target rejected with usage")

----------------------------------------------------------------------
-- Cleanup — mutes only; the flag ring has no reset API (see header)
----------------------------------------------------------------------
for _, n in ipairs({ T5N, T6A, T6B, T7N, T8N, T9A, T9B, T9C, T9D, T9E,
		T9F, T9NEG, T10C }) do
	smp_admin.unmute(n)
end

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_admin tests passed."
else
	results.lines[#results.lines + 1] =
		string.format("%d failures.", results.failed)
end
return results
