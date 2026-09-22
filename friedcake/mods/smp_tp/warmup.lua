-- FriedcakeSMP — smp_tp warm-up framework (f08 §4.1, §6.1)
--
-- Every command-initiated teleport in smp_tp (and later f09's /home)
-- goes through smp_tp.teleport_with_warmup(player, pos, kind).
--
-- Rules implemented here (f08 §4.1):
--   * Refuse while combat-tagged (f10 owns the block list; we only
--     query the bridge).
--   * Record last_teleport_from BEFORE the player moves (for /world).
--   * Action-bar countdown, re-issued once per second through
--     mcl_title.set (same channel as the observed "Delivering...").
--   * Cancel on movement > tp.cancel_move_distance — checked at fire
--     time only, not polled (f08 §8).
--   * Cancel on damage via core.register_on_player_hpchange.
--   * Re-validate at fire time: the player may have logged off, moved,
--     or become combat-tagged during the warm-up. Client fields carry
--     nothing trusted.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_tp.S

smp_tp.warmup = {}  -- [name] = {token, kind, from, to, started}

----------------------------------------------------------------------
-- Action-bar display
----------------------------------------------------------------------

-- mcl_title.set takes `stay` in Minecraft ticks (20 per second).
-- Re-issuing once per second with stay = 20 keeps the line visible
-- continuously until the teleport fires or is cancelled.
local function show_actionbar(name, text)
	local p = core.get_player_by_name(name)
	if not p then return end
	if mcl_title and mcl_title.set then
		mcl_title.set(p, "actionbar", { text = text, stay = 20 })
	end
end

local function clear_actionbar(name)
	local p = core.get_player_by_name(name)
	if not p then return end
	if mcl_title and mcl_title.set then
		mcl_title.set(p, "actionbar", { text = "", stay = 1 })
	end
end

----------------------------------------------------------------------
-- Cancellation
----------------------------------------------------------------------

-- Cancel a running warm-up. silent = true suppresses the chat line
-- (used when a new warm-up simply replaces the old one).
function smp_tp.cancel_warmup(name, silent)
	local w = smp_tp.warmup[name]
	if not w then return end
	smp_tp.warmup[name] = nil
	w.token.cancelled = true
	clear_actionbar(name)
	if not silent then
		core.chat_send_player(name, S("Teleport cancelled"))
	end
end

local function tick_countdown(name)
	local w = smp_tp.warmup[name]
	if not w or w.token.cancelled then return end
	local elapsed = os.time() - w.started
	local remaining = math.max(1, math.ceil(w.duration - elapsed))
	show_actionbar(name, S("Teleporting in @1s", remaining))
	if remaining <= 1 then return end
	core.after(1, function()
		-- Still the same, uncancelled warm-up?
		local cur = smp_tp.warmup[name]
		if cur and cur.token == w.token and not w.token.cancelled then
			tick_countdown(name)
		end
	end)
end

----------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------

-- Start a warm-up teleport. Returns (true) or (false, reason).
-- kind is a cooldown key: "rtp", "tpa", "tpahere", "spawn", "warp",
-- "world", "back", "home".
function smp_tp.teleport_with_warmup(player, pos, kind, opts)
	local name = player:get_player_name()

	-- Combat refusal (f10 owns the blocked-command list; we query).
	if smp_tp.bridge.is_tagged(name) then
		core.chat_send_player(name, S("You cannot teleport while in combat"))
		return false, "combat"
	end

	-- A new warm-up replaces any running one.
	if smp_tp.warmup[name] then
		smp_tp.cancel_warmup(name, true)
	end

	local st = smp_tp.get_state(name)
	local from = vector.new(math.floor(player:get_pos().x + 0.5),
	                        math.floor(player:get_pos().y + 0.5),
	                        math.floor(player:get_pos().z + 0.5))
	-- Record the origin BEFORE the player moves (f08 §4.1.2, /world).
	-- /world and /back pass record_from = false: one level deep only,
	-- they must not chain backwards (f08 §4.5.3–4).
	if not (opts and opts.record_from == false) then
		st.last_teleport_from = { x = from.x, y = from.y, z = from.z }
	end

	local token = { cancelled = false }
	local w = {
		token = token,
		kind = kind,
		from = from,
		to = vector.new(pos),
		started = os.time(),
		duration = math.max(1, math.floor(smp_tp.cfg.tp.warmup)),
	}
	smp_tp.warmup[name] = w
	st.warmup = w

	tick_countdown(name)

	core.after(w.duration, function()
		if token.cancelled then return end
		local cur = smp_tp.warmup[name]
		if not cur or cur.token ~= token then return end  -- replaced

		-- Re-validate at fire time: the player may have logged off.
		local p = core.get_player_by_name(name)
		if not p then
			smp_tp.cancel_warmup(name, true)
			return
		end
		-- Tagged during the warm-up? (f10)
		if smp_tp.bridge.is_tagged(name) then
			smp_tp.cancel_warmup(name)
			return
		end
		-- Moved more than tp.cancel_move_distance? (check at fire time
		-- only, not polled — f08 §8)
		local moved = vector.distance(p:get_pos(), w.from)
		if moved > smp_tp.cfg.tp.cancel_move_distance then
			smp_tp.cancel_warmup(name)
			return
		end
		smp_tp.cancel_warmup(name, true)
		p:set_pos(vector.new(w.to))
		p:set_player_velocity(vector.new(0, 0, 0))
	end)

	return true
end

-- Is the player mid-warm-up? (for command guards)
function smp_tp.is_warming_up(name)
	local w = smp_tp.warmup[name]
	return w ~= nil and not w.token.cancelled
end

----------------------------------------------------------------------
-- Damage cancellation (f08 §4.1: "Cancel on damage: yes")
----------------------------------------------------------------------

core.register_on_player_hpchange(function(player, hp_change, reason)
	if type(hp_change) == "number" and hp_change < 0 then
		local name = player:get_player_name()
		if smp_tp.warmup[name] and not smp_tp.warmup[name].token.cancelled then
			smp_tp.cancel_warmup(name)  -- sends "Teleport cancelled"
		end
	end
end)

return smp_tp
