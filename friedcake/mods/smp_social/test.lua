-- FriedcakeSMP — smp_social acceptance tests
-- Loaded by `/smp test smp_social` in-game (once the integrator wires a
-- generic test loader — see f11 §10), and by the standalone harness in
-- friedcake/dev-tests/test_social.lua. Returns {passed, failed, lines}.
--
-- Covers what is safely re-runnable on a live server: the exact chat
-- format (T1), the two OBSERVED literals (T3/T5, T8), the coarse
-- /findplayer buckets (T9) and the derived-friendship rules (T10).
-- The delivery paths (T2, T4, T6, T7) need a second player and live in
-- the standalone harness.
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

local REFUSAL = "This user only accepts messages from friends or followed players"

----------------------------------------------------------------------
-- T1 — public chat is exactly `<Name> message`, no prefix
----------------------------------------------------------------------
eq(smp_social.cfg.chat.rank_prefix, false, "T1 rank_prefix defaults false")
eq(smp_social.format_chat("FoxBuddy2", "ah"), "<FoxBuddy2> ah",
	"T1 observed line exact")
eq(smp_social.format_chat("robieto_faze", "TPA FOR TEAM OR 1V1"),
	"<robieto_faze> TPA FOR TEAM OR 1V1", "T1 second observed line exact")
ok(smp_social.format_chat("alice", "hi"):find("[Rank]", 1, true) == nil,
	"T1 no [Rank] prefix (v0.1 was wrong; V-24)")

----------------------------------------------------------------------
-- T3/T5 — the generic refusal is one literal, used by both branches
----------------------------------------------------------------------
eq(smp_social.generic_refusal(), REFUSAL, "T3 OBSERVED refusal literal")
ok(smp_social.generic_refusal() ~= "This user is not accepting private messages",
	"T5 the OFF refusal stays a separate string")

----------------------------------------------------------------------
-- T8 — unknown command answers `This command does not exist`
----------------------------------------------------------------------
do
	local captured = {}
	local orig = core.chat_send_player
	core.chat_send_player = function(n, m)
		captured[#captured + 1] = m
	end
	local handled = smp_social._on_unknown_command(
		"__f11_probe__", "frobnicate", "")
	core.chat_send_player = orig
	eq(handled, true, "T8 callback cancels the builtin handler")
	eq(captured[1], "This command does not exist", "T8 verbatim literal")
end

----------------------------------------------------------------------
-- T9 — /findplayer regions are coarse buckets, never coordinates
----------------------------------------------------------------------
do
	local whitelist = {
		["Center"] = true,
		["North"] = true, ["South"] = true,
		["East"] = true, ["West"] = true,
		["North-East"] = true, ["North-West"] = true,
		["South-East"] = true, ["South-West"] = true,
	}
	local samples = {
		{ 0, 0 }, { 5000, 0 }, { -5000, 0 }, { 0, 5000 }, { 0, -5000 },
		{ 5000, -7000 }, { -6000, 9000 }, { 3000, 3000 }, { -3000, 3000 },
	}
	for _, pos in ipairs(samples) do
		local r = smp_social.region_of(pos[1], pos[2])
		ok(whitelist[r] == true, "T9 region is a coarse bucket: " .. tostring(r))
		ok(r:find("%d") == nil, "T9 region carries no digits: " .. tostring(r))
	end
end

----------------------------------------------------------------------
-- T10 — one-way follow is not friendship; mutual follows are friends
-- (against the real store, using clearly-marked test records)
----------------------------------------------------------------------
do
	local A, B = "__f11_t10_a", "__f11_t10_b"
	smp_social.mutate_social(A, function(soc)
		soc.following[#soc.following + 1] = B
	end)
	ok(smp_social.follows(A, B), "T10 one-way edge visible")
	ok(not smp_social.is_friend(A, B), "T10 one-way is not friendship")
	ok(smp_social.is_friend_or_followed(A, B),
		"T10 first edge grants friend-or-followed")
	ok(not smp_social.is_friend_or_followed(B, A),
		"T10 the reverse one-way edge does not grant")
	smp_social.mutate_social(B, function(soc)
		soc.following[#soc.following + 1] = A
	end)
	ok(smp_social.is_friend(A, B) and smp_social.is_friend(B, A),
		"T10 mutual follows are friends in both directions")
	-- clean the test records back to empty lists
	for _, n in ipairs({ A, B }) do
		smp_social.mutate_social(n, function(soc)
			soc.following, soc.ignored, soc.blocked = {}, {}, {}
		end)
	end
end

----------------------------------------------------------------------
-- The command surface is registered
----------------------------------------------------------------------
for _, c in ipairs({ "msg", "r", "ignore", "block", "friend", "findplayer",
	"fp", "kill", "nightvision", "nv", "help", "rules", "discord", "media",
	"link", "buy", "store", "website", "ranks", "medal", "ping", "list",
	"who", "online", "report", "helpop", "ac" }) do
	ok(core.registered_chatcommands[c] ~= nil, "registered: /" .. c)
end

return results
