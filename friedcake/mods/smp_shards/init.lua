-- FriedcakeSMP — smp_shards
--
-- Playtime shard awards. Every online player receives 1 shard per 600 s
-- of playtime; no rank required [S8]. The award message is OBSERVED
-- verbatim and MUST be reproduced exactly, including the capital S and
-- the absence of a full stop [F0037, F0055, F0088–F0092]:
--
--     You earned 1 Shard for playing the server
--
-- Spec: spec/features/f06-shards.md §4.1, §6, §7.
--
-- Design notes
-- ------------
-- * `shards` and `shards_for_playtime` live in the player record (f01
--   §5.1). The award is `floor(playtime / interval) - shards_for_playtime`,
--   and both values persist, so a restart can never double-count (T2).
-- * Playtime is accumulated in memory per online player and flushed to the
--   record on award, on leave and every `flush_interval` seconds. Losing a
--   crash's unflushed seconds only delays an award, never duplicates one:
--   the persisted pair (playtime, shards_for_playtime) always satisfies
--   `shards_for_playtime <= floor(playtime / interval)`.
-- * No yields between validate and mutate (shared/02-architecture.md §2.3):
--   the record is upserted (persisting the counter) before the shards are
--   granted via smp_store.api.add_shards, which appends the ledger entry.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_shards = {}

----------------------------------------------------------------------
-- Configuration (spec f06 §7)
----------------------------------------------------------------------

local cfg = {
	-- LIVE [S8]: 1 shard per 600 s of playtime.
	interval = tonumber(core.settings:get("shards.interval")) or 600,
	-- PROPOSED: false — Donut pays for presence, not activity. When true
	-- the award would require f16's AFK tracking, which does not exist;
	-- f16 is descoped permanently (D8, 2026-09-24); V-61 closed.
	-- This key is still read so operators can set it, but it has no effect.
	require_activity = core.settings:get_bool("shards.require_activity", false),
	-- PROPOSED: false — shards cannot be transferred between players.
	transferable = core.settings:get_bool("shards.transferable", false),
	-- PROPOSED: persist accumulated playtime at most this often (seconds).
	flush_interval = tonumber(core.settings:get("shards.flush_interval")) or 30,
}

if cfg.interval < 1 then
	core.log("warning", "[smp_shards] shards.interval must be >= 1; using 600")
	cfg.interval = 600
end

-- F06-4: loud warning when require_activity is enabled (V-61/D8:
-- f16 descoped permanently; AFK tracking does not exist).
if cfg.require_activity then
	core.log("warning", "[smp_shards] shards.require_activity = true but AFK tracking is unimplemented (V-61/D8: f16 descoped permanently). The key is read but has no effect.")
end

function smp_shards.reload_cfg()
	cfg.interval = tonumber(core.settings:get("shards.interval")) or cfg.interval
	cfg.require_activity = core.settings:get_bool("shards.require_activity", false)
	cfg.transferable = core.settings:get_bool("shards.transferable", false)
	cfg.flush_interval = tonumber(core.settings:get("shards.flush_interval")) or cfg.flush_interval
	-- F06-4: warn on reload too
	if cfg.require_activity then
		core.log("warning", "[smp_shards] shards.require_activity = true but AFK tracking is unimplemented (V-61/D8: f16 descoped permanently). The key is read but has no effect.")
	end
end

smp_shards.cfg = cfg

----------------------------------------------------------------------
-- The award
--
-- AWARD_MSG is the OBSERVED string. It must never be altered: capital S
-- in "Shard", no terminal full stop. T1 asserts it byte-for-byte.
----------------------------------------------------------------------

local AWARD_MSG = S("You earned 1 Shard for playing the server")
smp_shards.award_message = AWARD_MSG

-- Grant `owed` shards to `name` and emit one chat line per shard
-- (spec f06 §6). `rec` must already carry the counter for this award:
-- `shards_for_playtime` is updated by the caller before this is called.
local function grant(name, rec, owed)
	if owed <= 0 then return end
	-- Validate, then mutate, in a fixed order (shared §2.3), no yields:
	-- 1. persist the (playtime, shards_for_playtime) pair
	-- 2. grant the balance + append the ledger entry
	-- 3. notify — exactly one line per shard
	smp_store.api.upsert_player(rec)
	smp_store.api.add_shards(name, owed, "shard_award",
		string.format("playtime:%d", rec.shards_for_playtime))
	for _ = 1, owed do
		core.chat_send_player(name, AWARD_MSG)
	end
end

-- In-memory playtime since the last flush, per online player. We store
-- ONLY the accumulated seconds, never the record: a held record could go
-- stale (its `shards` field is owned by smp_store.api.add_shards) and a
-- later upsert of the stale table would clobber an award. The record is
-- always re-read fresh at flush time.
local pending = {}   -- name -> seconds
local flush_tick = 0

-- Add `dt` seconds to `rec.playtime` and recompute the award owed
-- (f06 §6). Returns the number of shards owed (>= 0). Sets
-- `rec.shards_for_playtime` when owed > 0. Does NOT upsert or grant —
-- the caller persists and grants, keeping the mutation order fixed.
local function accrue(rec, dt)
	rec.playtime = (rec.playtime or 0) + dt
	local earned = math.floor(rec.playtime / cfg.interval)
	local base = rec.shards_for_playtime or 0
	local owed = earned - base
	if owed > 0 then
		rec.shards_for_playtime = earned
	end
	return owed
end

-- Flush one player's accumulated playtime: persist, and grant when owed.
-- Re-reads the record fresh so no stale field is written.
local function flush(name, dt)
	if dt < 1 then return 0 end
	local rec = smp_store.api.get_player(name)
	if not rec then rec = smp_store.api.ensure_player(name) end
	local owed = accrue(rec, dt)
	if owed > 0 then
		grant(name, rec, owed)
	else
		smp_store.api.upsert_player(rec)
	end
	return owed
end

function smp_shards.on_step(dtime, players)
	if type(dtime) ~= "number" or dtime <= 0 then return end
	players = players or core.get_connected_players()
	for _, player in ipairs(players) do
		local name = player:get_player_name()
		if name then
			pending[name] = (pending[name] or 0) + dtime
		end
	end
	-- Flush on the interval. Awards are granted within one interval of
	-- the moment they come due; the (playtime, shards_for_playtime) pair
	-- is persisted atomically, so a restart can at most delay an award,
	-- never double-count it (T2).
	flush_tick = flush_tick + dtime
	if flush_tick >= cfg.flush_interval then
		flush_tick = 0
		for name, dt in pairs(pending) do
			flush(name, dt)
			pending[name] = 0
		end
	end
end

-- Persist any unflushed playtime for a player (called on leave),
-- granting a due award on the way out.
function smp_shards.flush_player(name)
	local dt = pending[name]
	if dt and dt >= 1 then
		flush(name, dt)
	end
	pending[name] = nil
end

----------------------------------------------------------------------
-- /shardsadmin (PROPOSED, f06 §2)
--
--   /shardsadmin give|take|set <player> <amount>
--
-- `amount` is an integer shard count; per shared §0.6 it accepts the same
-- lower-case suffixes (250k, 1.5m). Shards are integer counts, never
-- float, never money.
----------------------------------------------------------------------

local function parse_shard_amount(text)
	if type(text) ~= "string" then return nil, "not a string" end
	local body = text:match("^%s*(.-)%s*$") or ""
	if body == "" then return nil, "empty" end
	local mult = 1
	local last = body:sub(-1):lower()
	if     last == "k" then body, mult = body:sub(1, -2), 1000
	elseif last == "m" then body, mult = body:sub(1, -2), 1000000
	elseif last == "b" then body, mult = body:sub(1, -2), 1000000000
	elseif last == "t" then body, mult = body:sub(1, -2), 1000000000000
	end
	local n = tonumber(body)
	if n == nil        then return nil, "not a number" end
	if n ~= n          then return nil, "NaN" end
	if n == math.huge  then return nil, "too large" end
	if n < 0           then return nil, "negative" end
	return math.floor(n * mult + 0.5), nil
end

smp_shards.parse_shard_amount = parse_shard_amount

local function resolve_target(raw)
	if not raw or raw == "" then return nil end
	if smp_store.api.get_player(raw) then return raw end
	-- `core.get_player_names` is client-only (nil on a server); resolve
	-- against the connected players the server API actually exposes.
	for _, p in ipairs(core.get_connected_players()) do
		local n = p:get_player_name()
		if n:lower() == raw:lower() then return n end
	end
	return nil
end

core.register_chatcommand("shardsadmin", {
	params = S("give|take|set <player> <amount>"),
	description = S("Adjust a player's shard balance (admin)."),
	privs = { smp_admin = true },
	func = function(player_name, param)
		param = param and param:match("^%s*(.-)%s*$") or ""
		local sub, target_raw, amount_raw = param:match("^(%S+)%s+(%S+)%s+(%S+)$")
		if not sub then
			return false, S("Usage: /shardsadmin give|take|set <player> <amount>")
		end
		sub = sub:lower()
		local target = resolve_target(target_raw)
		if not target then
			return false, S("Player @1 does not exist", target_raw)
		end
		local n, perr = parse_shard_amount(amount_raw)
		if not n then
			return false, S("Invalid amount: @1", perr or "?")
		end
		if sub == "give" then
			smp_store.api.add_shards(target, n, "admin", "shardsadmin:give:" .. player_name)
			return true, S("Gave @1 shards to @2.",
				smp_core.fmt_qty(n), target)
		elseif sub == "take" then
			local removed = smp_store.api.take_shards(target, n, "admin",
				"shardsadmin:take:" .. player_name)
			if not removed then
				return false, S("@1 does not have that many shards.", target)
			end
			return true, S("Took @1 shards from @2.",
				smp_core.fmt_qty(n), target)
		elseif sub == "set" then
			local rec = smp_store.api.ensure_player(target)
			local delta = n - (rec.shards or 0)
			rec.shards = n
			smp_store.api.upsert_player(rec)
			if delta ~= 0 then
				smp_store.api.append_ledger({
					time = os.time(),
					type = "admin",
					actor = target,
					counterparty = "",
					amount = delta,
					currency = "shards",
					item_key = "",
					qty = 0,
					ref = "shardsadmin:set:" .. player_name,
					flags = {},
				})
			end
			return true, S("Set @1's shards to @2.", target, smp_core.fmt_qty(n))
		end
		return false, S("Unknown subcommand: @1", sub)
	end,
})

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

core.register_globalstep(function(dtime)
	smp_shards.on_step(dtime)
end)

core.register_on_leaveplayer(function(player_name)
	smp_shards.flush_player(player_name)
end)

core.log("action", string.format(
	"[smp_shards] loaded: 1 shard per %d s; message: %q",
	cfg.interval, AWARD_MSG))
