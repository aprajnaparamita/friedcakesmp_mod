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
-- `/api` issues a personal key once (`fcsmp_` + sha1, stored in the
-- record as api_key = { key, created } per §5), re-shows the existing
-- key on repeat calls, and `/api delete` revokes it (T10).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_stats.S

smp_stats.api = {}
local api = smp_stats.api

----------------------------------------------------------------------
-- Keys (§5): fcsmp_ + sha1(time:name:random). Issue-once, revoke,
-- re-issue — every step synchronous, no yields (shared §2.3).

function api.make_key(name)
	local seed = core.get_us_time() .. ":" .. name .. ":"
		.. tostring(math.random()) .. ":" .. tostring(os.clock())
	return "fcsmp_" .. core.sha1(seed)
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
-- (T10: "issues a key once").
function api.issue_key(name)
	local existing = api.key_of(name)
	if existing then return existing, false end
	local key = api.make_key(name)
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
			return false, S("The public API is disabled on this server.")
		end
		if mode == "push" then
			core.log("warning", "[smp_stats] /api requested in push mode "
				.. "— the external key service is not configured")
			return false, S("The public API push mode is not configured yet.")
		end
		if param == "delete" then
			if api.revoke_key(player_name) then
				return true, S("API key revoked.")
			end
			return false, S("You have no API key.")
		end
		local key, issued = api.issue_key(player_name)
		if issued then
			return true, S("API key issued: @1", key)
		end
		return true, S("Your API key: @1", key)
	end,
})
