-- FriedcakeSMP — smp_stats / api.lua
-- The public API (f14 §4.4, §7, T10).
--
-- Luanti mods cannot serve HTTP, so the three §4.4 options map to
-- three modes (`api.mode`; claim-f14 default `snapshot`, §10 F14-D5):
--
--   snapshot  DEFAULT — write JSON snapshots into the world directory
--             with core.safe_file_write for an external web server to
--             publish (leaderboards.json + players.json, rewritten on
--             every board rebuild)
--   push      PROPOSED stub — would push through core.request_http_api()
--             to an external service that manages keys and rate limits
--   off       disabled
--
-- `/api` issues a personal key once (`fcsmp_` + 40 hex chars from
-- SecureRandom — EC-7/S01; stored in the record as api_key = { key,
-- created } per §5), re-shows the existing key on repeat calls, and
-- `/api delete` revokes it (T10).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_stats.S

smp_stats.api = {}
local api = smp_stats.api

----------------------------------------------------------------------
-- Keys (§5): `fcsmp_` + 40 hex chars. Issue-once, revoke, re-issue —
-- every step synchronous, no yields (shared §2.3).
--
-- EC-7 (S01): the key used to be `sha1(us_time .. name .. math.random()
-- .. os.clock())` — wall-clock time, the player name, the Lua PRNG
-- (seeded from time/address by default) and a process-local timer. A
-- local or modified-client attacker can enumerate that seed space and
-- mint someone else's key. It now comes straight from the OS CSPRNG:
-- `SecureRandom():next_bytes(20)` is 160 bits
-- (doc/lua_api.md `SecureRandom`; src/script/lua_api/l_noise.cpp
-- LuaSecureRandom), hex-encoded to the same 40 characters sha1 gave, so
-- the observable `fcsmp_ + 40 hex` form is unchanged (f14 §10 F14-D5).
--
-- FAIL CLOSED: `SecureRandom()` THROWS when the OS has no secure random
-- device (l_noise.cpp create_object) and a stubbed engine may answer
-- nil instead. Either way no key is minted: `make_key` answers nil,
-- `issue_key` stores nothing and `/api` reports the failure — never a
-- predictable key.

local function to_hex(bytes)
	return (bytes:gsub(".", function(c)
		return string.format("%02x", c:byte())
	end))
end

function api.make_key(name)
	-- `name` stays in the signature (callers pass it) but the key no
	-- longer needs it: 160 fresh bits per call, no seed to enumerate.
	if type(SecureRandom) ~= "function" then
		core.log("error", "[smp_stats] SecureRandom is unavailable; "
			.. "refusing to issue an API key")
		return nil
	end
	local ok, sr = pcall(SecureRandom)
	if not ok or sr == nil then
		core.log("error", "[smp_stats] SecureRandom failed ("
			.. tostring(sr) .. "); refusing to issue an API key")
		return nil
	end
	local drew, bytes = pcall(sr.next_bytes, sr, 20)
	if not drew or type(bytes) ~= "string" or #bytes < 20 then
		core.log("error", "[smp_stats] SecureRandom:next_bytes(20) failed ("
			.. tostring(bytes) .. "); refusing to issue an API key")
		return nil
	end
	return "fcsmp_" .. to_hex(bytes:sub(1, 20))
end

function api.key_of(name)
	local rec = smp_store.api.get_player(name)
	local k = rec and rec.api_key
	if type(k) == "table" and type(k.key) == "string" and k.key ~= "" then
		return k.key
	end
	return nil
end

-- Returns (key, issued_now). An existing key is re-shown, not rotated
-- (T10: "issues a key once"). EC-7: when no secure key can be minted,
-- answers (nil, false) and stores NOTHING — fail closed.
function api.issue_key(name)
	local existing = api.key_of(name)
	if existing then return existing, false end
	local key = api.make_key(name)
	if not key then return nil, false end
	local rec = smp_store.api.ensure_player(name)
	rec.api_key = { key = key, created = os.time() }
	smp_store.api.upsert_player(rec)
	return key, true
end

function api.revoke_key(name)
	local rec = smp_store.api.get_player(name)
	if not rec or type(rec.api_key) ~= "table" then return false end
	rec.api_key = nil
	smp_store.api.upsert_player(rec)
	return true
end

----------------------------------------------------------------------
-- Snapshot files (§4.4 option 1): <worldpath>/friedcake_api/
--   leaderboards.json  { generated, boards = { cat = {name,value}... } }
--   players.json       { generated, players = {name, money, ...stats} }
-- Written after each rebuild; api.mode gates it.

function api.write_snapshots(records)
	if smp_stats.cfg.api_mode ~= "snapshot" then return false end
	local dir = core.get_worldpath() .. "/friedcake_api"
	core.mkdir(dir) -- false when it already exists: not an error

	local boards_out = {}
	for _, cat in ipairs(smp_stats.CATEGORIES) do
		local b = smp_stats.boards[cat.key] or {}
		local arr = {}
		for i = 1, #b do
			arr[i] = { name = b[i].name, value = b[i].value }
		end
		boards_out[cat.key] = arr
	end

	local players_out = {}
	for i = 1, #records do
		local rec = records[i]
		players_out[i] = {
			name     = rec.name,
			money    = tonumber(rec.money) or 0,
			shards   = tonumber(rec.shards) or 0,
			playtime = tonumber(rec.playtime) or 0,
			stats    = rec.stats or {},
		}
	end

	api.last_write = {
		leaderboards = core.safe_file_write(dir .. "/leaderboards.json",
			core.write_json({ generated = os.time(), boards = boards_out })),
		players = core.safe_file_write(dir .. "/players.json",
			core.write_json({ generated = os.time(), players = players_out })),
	}
	return api.last_write.leaderboards and api.last_write.players
end

if smp_stats.cfg.api_mode == "push" then
	core.log("warning", "[smp_stats] api.mode = push is a PROPOSED stub "
		.. "(f14 §4.4 option 2: needs core.request_http_api() and an "
		.. "external key service); snapshots are NOT written")
end

----------------------------------------------------------------------
-- /api [delete]  (f14 §2, LIVE [S23][S24]). PROPOSED message wording
-- (§10 F14-D5); the key itself is the verbatim fcsmp_ form.

core.register_chatcommand("api", {
	params = S("[delete]"),
	description = S("Issue or revoke your personal API key"),
	func = function(player_name, param)
		param = (param or ""):lower():match("^%s*(.-)%s*$")
		local mode = smp_stats.cfg.api_mode
		if mode == "off" then
			return false, S("The public API is disabled on this server")
		end
		if mode == "push" then
			core.log("warning", "[smp_stats] /api requested in push mode "
				.. "— the external key service is not configured")
			return false, S("The public API push mode is not configured yet")
		end
		if param == "delete" then
			if api.revoke_key(player_name) then
				return true, S("API key revoked")
			end
			return false, S("You have no API key")
		end
		local key, issued = api.issue_key(player_name)
		if not key then
			-- EC-7 fail-closed: no secure key, so no key at all.
			return false, S("Could not generate an API key, try again")
		end
		if issued then
			return true, S("API key issued: @1", key)
		end
		return true, S("Your API key: @1", key)
	end,
})
