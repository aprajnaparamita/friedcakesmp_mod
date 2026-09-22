-- FriedcakeSMP — smp_settings / accessor.lua
-- The canonical accessor (f12 §5): `smp_settings.get(player_or_name, id)`.
--
-- Name decision (recorded in f12-settings.md §10): `get`, not `get_name`.
-- `smp_orders/routing.lua` and f11 §6 already call `smp_settings.get`;
-- f01 §6 and claim-f08 write `get_name` and must be normalised to `get`
-- by the integrator. One canonical name, one signature:
--     smp_settings.get(player_or_name, setting_id) -> value | nil
--     smp_settings.set(player_or_name, setting_id, value) -> bool
--
-- Untrusted ids are rejected here: unknown ids return nil (get) or
-- false (set); callers must not assume an id exists (f12 §8, T8).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local function index_of(t, v)
	for i, x in ipairs(t) do
		if x == v then return i end
	end
	return nil
end
smp_settings.index_of = index_of

-- Canonical accessor (f12 §5).
--   - registered id, no stored value      -> registered default
--   - registered id, valid stored value   -> stored value
--   - registered id, unrecognised stored  -> default (leave storage alone)
--   - unregistered id, stored value       -> stored value (unknown key,
--     e.g. written by a newer build: readable, never invented)
--   - unregistered id, nothing stored     -> nil
function smp_settings.get(player_or_name, id)
	if type(id) ~= "string" then return nil end
	local def = smp_settings.registered[id]
	local stored = smp_settings.store_get(player_or_name, id)
	if stored ~= nil then
		if not def then return stored end
		if type(stored) == "string" and index_of(def.values, stored) then
			return stored
		end
		return def.default
	end
	if def then return def.default end
	return nil
end

-- Write one setting. The id is untrusted: it must resolve through the
-- registry and the value must be in the setting's value domain, or the
-- call is ignored (T8). Registry lookup and store write run back to
-- back with no yields between (shared §2.3).
function smp_settings.set(player_or_name, id, value)
	if type(id) ~= "string" then return false end
	local def = smp_settings.registered[id]
	if not def then return false end
	if type(value) ~= "string" or not index_of(def.values, value) then
		return false
	end
	return smp_settings.store_set(player_or_name, id, value)
end
