-- FriedcakeSMP — smp_settings / store.lua
-- Storage: one JSON blob under the player-meta key `smp:settings`
-- (f12 §4). NOT smp_store — these are presentation values, not money,
-- and f12 §4 explicitly places them in player meta.
--
-- Every write is read-modify-write of the whole object, so keys this
-- build does not know (a newer build's settings) survive a downgrade
-- round-trip (f12 §4.6, T7). Unknown keys are preserved on write.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local META_KEY = "smp:settings"

-- Resolve a PlayerRef or a player name to a player name, or nil.
function smp_settings.player_name(player_or_name)
	if type(player_or_name) == "string" and player_or_name ~= "" then
		return player_or_name
	end
	if type(player_or_name) == "table"
	   and type(player_or_name.get_player_name) == "function" then
		local ok, n = pcall(player_or_name.get_player_name, player_or_name)
		if ok and type(n) == "string" and n ~= "" then return n end
	end
	return nil
end

-- Resolve a PlayerRef or player name to a meta object, or nil when the
-- player is offline (player meta only exists for online players).
local function meta_of(player_or_name)
	local p = player_or_name
	if type(p) == "string" then
		p = core.get_player_by_name(p)
	end
	if type(p) ~= "table" or type(p.get_meta) ~= "function" then
		return nil
	end
	local ok, meta = pcall(p.get_meta, p)
	if ok and meta then return meta end
	return nil
end

-- Read the whole stored object. Returns nil when the player is not
-- online, {} when nothing (valid) is stored.
function smp_settings.raw_table(player_or_name)
	local meta = meta_of(player_or_name)
	if not meta then return nil end
	local raw = meta:get_string(META_KEY)
	if type(raw) ~= "string" or raw == "" then return {} end
	local t = core.parse_json(raw)
	if type(t) ~= "table" then
		core.log("warning", "[smp_settings] " .. META_KEY
			.. " is not a JSON object; starting fresh")
		return {}
	end
	return t
end

-- Read one key (unknown keys readable: a newer build's setting).
function smp_settings.store_get(player_or_name, key)
	if type(key) ~= "string" then return nil end
	local t = smp_settings.raw_table(player_or_name)
	if not t then return nil end
	return t[key]
end

-- Write one key, preserving every other key (f12 §4.6, T7).
-- No yields anywhere between read and write (shared §2.3).
function smp_settings.store_set(player_or_name, key, value)
	if type(key) ~= "string" then return false end
	local meta = meta_of(player_or_name)
	if not meta then return false end
	local t = smp_settings.raw_table(player_or_name)
	if not t then return false end
	t[key] = value
	local json = core.write_json(t)
	if type(json) ~= "string" then return false end
	meta:set_string(META_KEY, json)
	return true
end
