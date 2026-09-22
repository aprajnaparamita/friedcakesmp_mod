-- FriedcakeSMP — smp_stats / playtime.lua
-- Playtime accumulator (f14 §4.1 table, §6 algorithm, T11).
--
-- One globalstep, O(online players) per whole second, fractional
-- remainders carried. Seconds accumulate in memory
-- (smp_stats._pending_playtime) and are flushed into rec.playtime:
--   * every `stats.persist_interval` (60 s, PROPOSED §7),
--   * when the player leaves,
--   * on shutdown — upsert first, then flush the driver, because
--     smp_store's own shutdown callback (registered earlier: it loads
--     first) has already flushed and possibly closed the backend.
--
-- A crash loses at most one persist_interval of playtime (T11);
-- everything already flushed survives because it is in the store.
--
-- get("playtime") reads rec.playtime + pending, so a reader never
-- sees less than it should and never has to guess flush timing.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local pending = {}
smp_stats._pending_playtime = pending

-- Public per spec §6: smp_stats.add_playtime(player, seconds).
function smp_stats.add_playtime(player_or_name, seconds)
	local name = smp_stats.name_of(player_or_name)
	if not name then return nil end
	seconds = math.floor(tonumber(seconds) or 0)
	if seconds <= 0 then return pending[name] or 0 end
	pending[name] = (pending[name] or 0) + seconds
	return pending[name]
end

-- Write every player's pending seconds into rec.playtime. Integer
-- arithmetic only; ensure -> mutate -> upsert per player, one player
-- per uninterrupted sequence (shared §2.3). Returns players written.
function smp_stats.flush_playtime()
	local wrote = 0
	for name, seconds in pairs(pending) do
		if seconds and seconds > 0 then
			local rec = smp_store.api.ensure_player(name)
			rec.playtime = math.floor((tonumber(rec.playtime) or 0) + seconds)
			smp_store.api.upsert_player(rec)
			wrote = wrote + 1
		end
		pending[name] = nil -- nil-ing during traversal is sanctioned
	end
	return wrote
end

----------------------------------------------------------------------
-- The accumulator (§6): one globalstep, O(online players) per whole
-- second — never a per-tick per-player store write.

local acc, flush_acc = 0, 0
smp_stats._playtime_acc = function() return acc end -- test seam

core.register_on_globalstep(function(dtime)
	acc = acc + dtime
	flush_acc = flush_acc + dtime
	if acc >= 1 then
		local whole = math.floor(acc)
		acc = acc - whole
		for _, p in ipairs(core.get_connected_players()) do
			smp_stats.add_playtime(p, whole)
		end
	end
	if flush_acc >= smp_stats.cfg.persist then
		flush_acc = 0
		smp_stats.flush_playtime()
	end
end)

-- Leave: this player's pending must not wait for the next interval.
core.register_on_leaveplayer(function(player, _)
	local name = player.get_player_name and player:get_player_name()
	if not name or not pending[name] then return end
	local seconds = pending[name]
	pending[name] = nil
	local rec = smp_store.api.ensure_player(name)
	rec.playtime = math.floor((tonumber(rec.playtime) or 0) + seconds)
	smp_store.api.upsert_player(rec)
end)

-- Shutdown: smp_store's callback (registered first) already flushed
-- the driver; flush our owed seconds into the store, then ask the
-- driver to flush again so they reach disk (T11).
core.register_on_shutdown(function()
	smp_stats.flush_playtime()
	if smp_store._driver and smp_store._driver.flush then
		pcall(smp_store._driver.flush)
	end
end)
