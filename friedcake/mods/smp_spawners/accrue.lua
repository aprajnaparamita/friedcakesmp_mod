-- FriedcakeSMP — smp_spawners / accrue.lua
-- Production curve and lazy accrual. f07 §4.3, §4.4, §4.5, §6.
--
-- kills_per_min(n) = C * (1 - (1 - r/C)^n)
--
--   * skeleton C = 1505.35 is the ONLY published number [S24, LIVE];
--   * r = 6 and every non-skeleton C are PROPOSED, uncalibrated;
--   * the curve shape itself is V-62: only the asymptote is published.
--
-- Cardinal rules honoured here:
--   * accrual uses floats for fractional kills; the integer boundary is
--     the moment a virtual count crosses 1.0 (menu rendering and takes);
--   * every tick is clamped so a long log-off cannot produce a long
--     payout (f07 §4.5, default mode active_only: 2 x timer_interval);
--   * production pauses at capacity; the overflow is discarded, and the
--     pause is visible in the menu (stored/capacity line), never silent
--     (f07 §4.4, T5);
--   * the metadata version counter increments on every change (T6,
--     shared §2.6 R7).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local cfg = smp_spawners.cfg

----------------------------------------------------------------------
-- The curve (pure; testable without an engine — T1/T2/T3)
----------------------------------------------------------------------

-- kills_per_min(n) = C * (1 - (1 - r/C)^n)
--
-- Properties: f(1) = r exactly (up to float rounding); strictly
-- increasing in n; marginal output f(n) - f(n-1) strictly decreases;
-- limit as n -> inf is C, approached from below.
function smp_spawners.curve(n, r, C)
	if type(n) ~= "number" or type(r) ~= "number" or type(C) ~= "number" then
		return 0
	end
	if n <= 0 or r <= 0 or C <= 0 then return 0 end
	-- r >= C would break the (1 - r/C) base; clamp the base to (0, 1].
	local base = 1 - math.min(r, C) / C
	return C * (1 - base ^ n)
end

-- Stack rate for a spawner type using its configured r and C. C is
-- read through cfg.C so the "spawners.C" setting can override the
-- (PROPOSED) per-type defaults; f07 §6 uses cfg.spawners.C[def.id].
function smp_spawners.kills_per_min(type_id, n)
	local def = smp_spawners.types.get(type_id)
	if not def or not n or n <= 0 then return 0 end
	local C = smp_spawners.cfg.C[type_id] or def.C
	return smp_spawners.curve(n, def.r, C)
end

----------------------------------------------------------------------
-- Storage helpers
----------------------------------------------------------------------

-- Total stored count (sum of the fractional table).
function smp_spawners.store_total(store)
	local total = 0
	for _, count in pairs(store or {}) do
		total = total + (count or 0)
	end
	return total
end

-- Capacity: min(hard_cap, per_spawner * n). f07 §4.4.
function smp_spawners.capacity(n)
	return math.min(cfg.storage.hard_cap, cfg.storage.per_spawner * (n or 0))
end

-- XP cap: per_spawner_cap * n. f07 §4.4.
function smp_spawners.xp_cap(n)
	return cfg.xp.per_spawner_cap * (n or 0)
end

----------------------------------------------------------------------
-- Metadata read/write (f07 §5)
----------------------------------------------------------------------

-- Read the whole spawner state. Returns a table or nil if the node at
-- pos is not a valid spawner (wrong type id, missing, empty stack).
function smp_spawners.read_state(pos)
	local node = core.get_node_or_nil(pos)
	if not node or node.name ~= "smp_spawners:spawner" then return nil end
	local meta = core.get_meta(pos)
	local type_id = meta:get_string("smp:type")
	local def = smp_spawners.types.get(type_id)
	if not def then return nil end
	local n = meta:get_int("smp:stack")
	if n <= 0 then return nil end
	local store = core.deserialize(meta:get_string("smp:store"))
	if type(store) ~= "table" then store = {} end
	return {
		pos = pos,
		type_id = type_id,
		def = def,
		stack = n,
		last_update = meta:get_float("smp:last_update"),
		store = store,
		xp = meta:get_float("smp:xp"),
		version = meta:get_int("smp:version"),
	}
end

-- Write state back. Bumps the version counter. Shared §2.3: call only
-- after all validation has succeeded; never yield inside.
function smp_spawners.write_state(state)
	local meta = core.get_meta(state.pos)
	meta:set_int("smp:stack", state.stack)
	meta:set_float("smp:last_update", state.last_update)
	meta:set_float("smp:xp", state.xp)
	meta:set_string("smp:store", core.serialize(state.store))
	meta:set_int("smp:version", state.version + 1)
	state.version = state.version + 1
end

----------------------------------------------------------------------
-- Accrual
----------------------------------------------------------------------

-- Elapsed seconds for the last_update -> now interval under the active
-- accrual mode. f07 §4.5.
--
--   active_only (default): clamped to 2 x timer_interval. The node
--     timer only fires while the map block is active; on reactivation
--     the callback may report the whole inactive period, so we clamp.
--   always: unclamped wall-clock (capacity is the only limit).
--   capped: wall-clock up to offline_cap_hours.
function smp_spawners.clamp_elapsed(elapsed, mode)
	if elapsed <= 0 then return 0 end
	if mode == "always" then return elapsed end
	if mode == "capped" then
		return math.min(elapsed, cfg.offline_cap_hours * 3600)
	end
	-- active_only (and any unknown value: fail closed)
	return math.min(elapsed, 2 * cfg.timer_interval)
end

-- Accrue a spawner node at pos. Lazy: converts elapsed time since
-- smp:last_update into output. Returns the summary table
--   { kills = ..., added = ..., xp_added = ..., paused_full = bool,
--     elapsed = ... }
-- or nil when there is nothing to do (no time elapsed or no stack).
--
-- Capacity pause: items that would exceed capacity are discarded and
-- the menu shows the spawner full, so the pause is never silent (T5).
-- last_update always advances while the node exists, so a full spawner
-- does not bank output in the background.
function smp_spawners.accrue(pos, now)
	now = now or os.time()
	local state = smp_spawners.read_state(pos)
	if not state then return nil end

	local elapsed = smp_spawners.clamp_elapsed(now - state.last_update,
		cfg.accrual_mode)
	if elapsed <= 0 then return nil end
	local mins = elapsed / 60
	local kills = smp_spawners.kills_per_min(state.type_id, state.stack) * mins
	if kills <= 0 then
		state.last_update = now
		smp_spawners.write_state(state)
		return { kills = 0, added = 0, xp_added = 0,
		         paused_full = false, elapsed = elapsed }
	end

	-- Capacity pause (f07 §4.4, T5).
	local cap   = smp_spawners.capacity(state.stack)
	local total = smp_spawners.store_total(state.store)
	local room  = math.max(cap - total, 0)
	local added = 0
	-- Room is shared across loot entries in table order; each entry
	-- takes min(kills * per_kill, remaining room) exactly as f07 §6.
	local remaining = room
	for item, per_kill in pairs(state.def.loot) do
		local want = kills * per_kill
		local take = math.min(want, remaining)
		if take > 0 then
			state.store[item] = (state.store[item] or 0) + take
			remaining = remaining - take
			added = added + take
		end
	end
	local paused_full = room <= 0 or added < kills - 1e-9

	-- XP accrues to the cap; it does not pause the item loop.
	local xp_before = state.xp
	state.xp = math.min(state.xp + kills * state.def.xp,
		smp_spawners.xp_cap(state.stack))

	state.last_update = now
	smp_spawners.write_state(state)
	return {
		kills = kills,
		added = added,
		xp_added = state.xp - xp_before,
		paused_full = paused_full,
		elapsed = elapsed,
	}
end
