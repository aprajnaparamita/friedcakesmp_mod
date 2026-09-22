-- FriedcakeSMP — smp_stats / counters.lua
-- smp_stats.add / smp_stats.get over rec.stats (f14 §4.1, §5) plus the
-- two block hooks (T1).
--
-- One store, two writers (claim-f14):
--   * f02 assigns rec.stats.money_made_from_sell directly;
--   * f05 (ObjectRef) and f10 (name) call smp_stats.add().
-- Both land in rec.stats[key] of the smp_store player record, so
-- leaderboards can enumerate offline players (shared §2.2).
--
-- `money`, `shards` and `playtime` are live fields at the top level of
-- the record: get() reads them there (playtime including this server's
-- unflushed pending seconds), add() refuses them — money moves through
-- smp_store.api, playtime through add_playtime.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

-- Name-or-player normalisation: every public entry point accepts an
-- ObjectRef (f05) or a player name (f10) and yields a name.
function smp_stats.name_of(player_or_name)
	if type(player_or_name) == "string" then
		if player_or_name ~= "" then return player_or_name end
		return nil
	end
	local p = player_or_name
	if p and type(p) == "table"
	   and p.is_player and p:is_player()
	   and p.get_player_name then
		return p:get_player_name()
	end
	return nil
end
local name_of = smp_stats.name_of

local LIVE = { money = true, shards = true, playtime = true }

-- Increment a counter. Returns the new total, or nil + reason.
-- Counters are integers (claim rule 6): money in cents, playtime in
-- seconds, event counts whole. No yields between read and write
-- (shared §2.3): ensure -> mutate -> upsert in one sequence.
function smp_stats.add(player_or_name, key, value)
	local name = name_of(player_or_name)
	if not name then return nil, "no player" end
	if type(key) ~= "string" or key == "" then return nil, "no key" end
	if LIVE[key] then return nil, key .. " is a live field" end
	value = tonumber(value)
	if not value or value ~= value or value == math.huge then
		return nil, "not a number"
	end
	local rec = smp_store.api.ensure_player(name)
	rec.stats = rec.stats or {}
	local new = math.floor((tonumber(rec.stats[key]) or 0) + value)
	rec.stats[key] = new
	smp_store.api.upsert_player(rec)
	return new
end

-- Read a counter. Live fields come from the top level of the record;
-- `playtime` adds the seconds this server has not flushed yet, so the
-- menu, the board and the API all agree with what has been persisted
-- plus what is owed.
function smp_stats.get(player_or_name, key)
	local name = name_of(player_or_name)
	if not name then return 0 end
	local rec = smp_store.api.get_player(name)
	if not rec then return 0 end
	if key == "money" then return tonumber(rec.money) or 0 end
	if key == "shards" then return tonumber(rec.shards) or 0 end
	if key == "playtime" then
		local pending = smp_stats._pending_playtime
		return (tonumber(rec.playtime) or 0)
			+ (pending and tonumber(pending[name]) or 0)
	end
	return tonumber(rec.stats and rec.stats[key]) or 0
end

----------------------------------------------------------------------
-- Block hooks (f14 §4.1 table, T1): exactly one increment per event.
-- The actor may be absent (piston, autodigger) — then nobody is
-- credited rather than a phantom player.

core.register_on_dignode(function(pos, oldnode, digger)
	if digger and digger.is_player and digger:is_player() then
		smp_stats.add(digger, "broken_blocks", 1)
	end
end)

core.register_on_placenode(function(pos, newnode, placer, oldnode)
	if placer and placer.is_player and placer:is_player() then
		smp_stats.add(placer, "placed_blocks", 1)
	end
end)
