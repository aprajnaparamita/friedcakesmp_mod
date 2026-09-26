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
-- * S05/SH-2 (integrator ruling 2026-09-27): when `shards.require_activity`
--   is true (the new default) an award also requires the player to have
--   moved or interacted within the award interval; an idle interval is
--   forfeited rather than banked. Activity is tracked in this mod (see the
--   "activity tracking" block below) because the engine has no
--   `register_on_player_movement` callback.
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
	-- S05/SH-2 (integrator ruling 2026-09-27): an award now REQUIRES the
	-- player to have moved or interacted within the award interval. The
	-- default flips false -> true, which overturns D8's "inert" reading
	-- (the reason it was inert — "AFK tracking does not exist", f16 — no
	-- longer holds: the tracking lives here, in smp_shards, not in f16).
	-- Default change + spec/shared/06 mirror row are ESCALATEd in
	-- spec/features/f06-shards.md §10. Operators can still set false to
	-- restore presence-only awards.
	require_activity = core.settings:get_bool("shards.require_activity", true),
	-- PROPOSED: false — shards cannot be transferred between players.
	transferable = core.settings:get_bool("shards.transferable", false),
	-- PROPOSED: persist accumulated playtime at most this often (seconds).
	flush_interval = tonumber(core.settings:get("shards.flush_interval")) or 30,
}

if cfg.interval < 1 then
	core.log("warning", "[smp_shards] shards.interval must be >= 1; using 600")
	cfg.interval = 600
end

-- F06-4 superseded by S05/SH-2: the key used to be read and ignored (V-61
-- closed by D8 while f16's AFK zone was the only tracker). It is now
-- implemented below, so say so loudly either way.
local function log_activity_mode()
	if cfg.require_activity then
		core.log("action", "[smp_shards] shards.require_activity = true: "
			.. "a playtime award needs movement or interaction within the "
			.. "last interval; idle intervals are forfeited")
	else
		core.log("warning", "[smp_shards] shards.require_activity = false: "
			.. "shards are awarded for presence alone (SH-2 AFK pipe open)")
	end
end
log_activity_mode()

function smp_shards.reload_cfg()
	cfg.interval = tonumber(core.settings:get("shards.interval")) or cfg.interval
	cfg.require_activity = core.settings:get_bool("shards.require_activity", true)
	cfg.transferable = core.settings:get_bool("shards.transferable", false)
	cfg.flush_interval = tonumber(core.settings:get("shards.flush_interval")) or cfg.flush_interval
	-- F06-4 / S05-SH-2: report the mode on reload too
	log_activity_mode()
end

smp_shards.cfg = cfg

----------------------------------------------------------------------
-- S05/SH-2 — activity tracking (AFK gate)
--
-- No award unless the player moved or interacted during the award
-- interval. Tracked here, in smp_shards, because f16's AFK zone is
-- descoped permanently (D8) and `core.register_on_player_movement` DOES
-- NOT EXIST in this engine (verified against ~/dev/luanti: absent from
-- builtin/game/register.lua and from dev-tests/engine_api_surface.txt),
-- so a movement callback cannot be the heartbeat.
--
-- Cheapest approach that still works on a full server:
--   * an O(1) timestamp write per event for interactions (dig, place,
--     punch, pickup, chat, formspec fields, chat command);
--   * one position sample per player per second, piggybacked on the
--     globalstep loop smp_shards already runs (1 `get_pos` per player
--     per second — negligible next to the existing per-step bookkeeping).
--
-- `last_activity[name]` is the Unix second of the last observed
-- movement/interaction; it is seeded at join.
----------------------------------------------------------------------

local last_activity = {}   -- name -> Unix second
local last_pos = {}        -- name -> { x, y, z } at the last sample
smp_shards._last_activity = last_activity   -- exposed for dev-tests

-- Mark `who` (ObjectRef or player name) active now. Writes are skipped
-- within the same second: movement and formspec callbacks fire often and
-- one write per second is all the 600 s window can distinguish.
function smp_shards.mark_active(who, now)
	local name = who
	if type(name) ~= "string" then
		if type(name) ~= "table" and type(name) ~= "userdata" then
			return nil
		end
		local getter = name.get_player_name
		if type(getter) ~= "function" then return nil end
		name = getter(name)
	end
	if type(name) ~= "string" or name == "" then return nil end
	now = now or os.time()
	local prev = last_activity[name]
	if not prev or now - prev >= 1 then
		last_activity[name] = now
	end
	return name
end

local MOVE_EPS2 = 0.25 * 0.25   -- blocks^2 between samples; a standing
                                -- player never covers this, a walking one
                                -- always does

-- Position sample for one player (S05/SH-2 "moved").
local function sample_position(player, name)
	if type(player.get_pos) ~= "function" then return end
	local ok, pos = pcall(player.get_pos, player)
	if not ok or type(pos) ~= "table" then return end
	local prev = last_pos[name]
	last_pos[name] = pos
	if not prev then return end
	local dx = (pos.x or 0) - (prev.x or 0)
	local dy = (pos.y or 0) - (prev.y or 0)
	local dz = (pos.z or 0) - (prev.z or 0)
	if dx * dx + dy * dy + dz * dz >= MOVE_EPS2 then
		last_activity[name] = os.time()
	end
end
smp_shards._sample_position = sample_position

-- Has this player moved or interacted within the last `cfg.interval`
-- seconds? nil last_activity means "never seen active" -> inactive.
local function active_in_window(name, now)
	local last = last_activity[name]
	return last ~= nil and (now - last) < cfg.interval
end
smp_shards.active_in_window = active_in_window

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

-- S05/SH-2: position-sampling cadence for the AFK gate (seconds).
local SAMPLE_INTERVAL = 1
local sample_tick = 0

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
	if owed > 0 and cfg.require_activity
			and not active_in_window(name, os.time()) then
		-- S05/SH-2: no movement or interaction in the award interval, so
		-- no award. `accrue` has already advanced shards_for_playtime, so
		-- the idle interval is FORFEITED, not banked: AFK time can never
		-- be cashed in after the player comes back (an un-gated "skip"
		-- would leave owed > 0 and pay the whole idle stretch at once).
		smp_store.api.upsert_player(rec)
		return 0
	end
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
	-- S05/SH-2: one position sample per second, inside the loop the step
	-- already runs (no second pass over the player list).
	sample_tick = sample_tick + dtime
	local sampling = sample_tick >= SAMPLE_INTERVAL
	if sampling then sample_tick = sample_tick % SAMPLE_INTERVAL end
	for _, player in ipairs(players) do
		local name = player:get_player_name()
		if name then
			pending[name] = (pending[name] or 0) + dtime
			if sampling then sample_position(player, name) end
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

-- S05/SH-2: seed activity at join (a joining player is, by definition,
-- not AFK yet) and clear it on leave so the table cannot grow.
core.register_on_joinplayer(function(player)
	smp_shards.mark_active(player)
end)

core.register_on_leaveplayer(function(player)
	-- S05/SH-1b: the engine passes an ObjectRef, not a name. The old
	-- `flush_player(player_name)` was a silent no-op (pending[ObjectRef]
	-- is always nil), so the leave-time flush never ran. Resolve the name.
	local name = player
	if type(name) ~= "string" then
		if type(name) ~= "table" and type(name) ~= "userdata" then return end
		local getter = name.get_player_name
		if type(getter) ~= "function" then return end
		name = getter(name)
	end
	if type(name) ~= "string" or name == "" then return end
	smp_shards.flush_player(name)
	last_activity[name] = nil
	last_pos[name] = nil
end)

-- S05/SH-2: "moved or interacted" — every one of these is a player doing
-- something. Each callback is an O(1) timestamp write.
core.register_on_dignode(function(_pos, _oldnode, digger)
	if digger then smp_shards.mark_active(digger) end
end)

core.register_on_placenode(function(_pos, _newnode, placer)
	if placer then smp_shards.mark_active(placer) end
end)

core.register_on_punchplayer(function(_punched, hitter)
	if hitter then smp_shards.mark_active(hitter) end
end)

core.register_on_item_pickup(function(_stack, player)
	if player then smp_shards.mark_active(player) end
end)

core.register_on_chat_message(function(name)
	smp_shards.mark_active(name)
end)

core.register_on_chatcommand(function(name)
	smp_shards.mark_active(name)
end)

core.register_on_player_receive_fields(function(player)
	smp_shards.mark_active(player)
end)

core.log("action", string.format(
	"[smp_shards] loaded: 1 shard per %d s; message: %q",
	cfg.interval, AWARD_MSG))
