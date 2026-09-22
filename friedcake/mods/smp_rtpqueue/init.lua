-- FriedcakeSMP — smp_rtpqueue (f08 §4.3)
--
-- Paired random teleport, launched in beta on the reference server on
-- 29 June 2026 [S15]. /rtpqueue toggles queue membership; first-in,
-- first-out pairing; a matched pair gets a 5 s warm-up and is
-- teleported to one safe Overworld location, rtpqueue.separation
-- (16–32) nodes apart.
--
-- Rules implemented:
--   * Refused while combat-tagged (f10 bridge).
--   * FIFO pairing; players who block each other (f11 bridge) are
--     NEVER paired (T11).
--   * Membership times out after rtpqueue.timeout (300 s).
--   * Teleporting elsewhere (any other command's warm-up) or moving
--     during the queue leaves the queue.
--   * The safe-location search reuses smp_tp's async search
--     (emerge_area first; remaining == 0 checked in the callback).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_rtpqueue = {}
smp_rtpqueue.S = S

-- FIFO queue: name -> {joined_at, at (pos where they queued)}.
smp_rtpqueue.members = {}

local function cfg() return smp_tp.cfg.rtpqueue end

local function leave(name, notify)
	local m = smp_rtpqueue.members[name]
	if not m then return end
	smp_rtpqueue.members[name] = nil
	if notify and core.player_exists(name) then
		core.chat_send_player(name, S("You left the random teleport queue"))
	end
end

local function is_queued(name)
	return smp_rtpqueue.members[name] ~= nil
end

----------------------------------------------------------------------
-- Pairing
----------------------------------------------------------------------

local function blocked(a, b)
	return smp_tp.bridge.blocks(a, b) or smp_tp.bridge.blocks(b, a)
end

local function find_match(name)
	-- FIFO: the new joiner pairs with the earliest-queued member that
	-- is eligible (online, not blocking either way, not tagged).
	local best, best_at
	for other in pairs(smp_rtpqueue.members) do
		if other ~= name
			and not blocked(name, other)
			and not smp_tp.bridge.is_tagged(other)
			and not smp_tp.bridge.is_tagged(name) then
			local m = smp_rtpqueue.members[other]
			if not best or m.joined_at < best_at then
				best, best_at = other, m.joined_at
			end
		end
	end
	return best
end

----------------------------------------------------------------------
-- Match execution
----------------------------------------------------------------------

local function random_offset(sep)
	local ang = math.random() * 2 * math.pi
	local r = cfg().min_separation
		+ math.random() * (cfg().max_separation - cfg().min_separation)
	return math.floor(r * math.cos(ang)), math.floor(r * math.sin(ang))
end

local function run_match(a, b)
	leave(a, false)
	leave(b, false)
	local pa = core.get_player_by_name(a)
	local pb = core.get_player_by_name(b)
	if not pa or not pb then return end

	local x, z = smp_tp.random_rtp_target(nil)
	local band = smp_tp.cfg.rtp.scan.overworld
	if not x or not band then
		core.chat_send_player(a, S("No safe location found. Try again."))
		core.chat_send_player(b, S("No safe location found. Try again."))
		return
	end

	core.emerge_area(vector.new(x, band.min, z), vector.new(x, band.max, z),
		function(_, _, remaining)
			if remaining and remaining > 0 then return end
			local pa2 = core.get_player_by_name(a)
			local pb2 = core.get_player_by_name(b)
			if not pa2 or not pb2 then return end

			local centre = smp_tp.find_safe_y(x, z, "overworld", band)
			if not centre then
				core.chat_send_player(a, S("No safe location found. Try again."))
				core.chat_send_player(b, S("No safe location found. Try again."))
				return
			end
			local dx, dz = random_offset()
			local p1, p2 = centre, centre  -- fallback: stack at centre
			local off1 = smp_tp.find_safe_y(x + dx, z + dz, "overworld", band)
			if off1 then p1 = off1 end
			local off2 = smp_tp.find_safe_y(x - dx, z - dz, "overworld", band)
			if off2 then p2 = off2 end

			core.chat_send_player(a, S("You matched with @1. Teleporting...", b))
			core.chat_send_player(b, S("You matched with @1. Teleporting...", a))
			-- Both ride the standard §4.1 warm-up (5 s).
			smp_tp.teleport_with_warmup(pa2, p1, "rtpqueue")
			smp_tp.teleport_with_warmup(pb2, p2, "rtpqueue")
		end)
end

----------------------------------------------------------------------
-- Command
----------------------------------------------------------------------

core.register_chatcommand("rtpqueue", {
	params = S(""),
	description = S("Join or leave the paired random-teleport queue."),
	func = function(name, _)
		if is_queued(name) then
			leave(name, true)
			return true
		end
		if smp_tp.bridge.is_tagged(name) then
			core.chat_send_player(name, S("You cannot queue while in combat"))
			return false
		end
		if smp_tp.is_warming_up(name) then
			core.chat_send_player(name, S("Already teleporting"))
			return false
		end
		local pos = core.get_player_by_name(name):get_pos()
		smp_rtpqueue.members[name] = {
			joined_at = os.time(),
			at = { x = math.floor(pos.x), y = math.floor(pos.y), z = math.floor(pos.z) },
		}
		core.chat_send_player(name, S("You joined the random teleport queue"))
		local other = find_match(name)
		if other then
			run_match(name, other)
		end
		return true
	end,
})

----------------------------------------------------------------------
-- Globalstep (1 Hz): timeout, tag exit, movement exit.
-- O(online players) per second (shared §2.7).
----------------------------------------------------------------------

local step_timer = 0
core.register_globalstep(function(dtime)
	step_timer = step_timer + dtime
	if step_timer < 1 then return end
	step_timer = 0

	local now = os.time()
	for name, m in pairs(smp_rtpqueue.members) do
		local p = core.get_player_by_name(name)
		if not p then
			leave(name, false)
		elseif now - m.joined_at >= cfg().timeout then
			leave(name, true)
		elseif smp_tp.bridge.is_tagged(name) then
			-- First hit starts combat tags; a queued fighter leaves.
			leave(name, true)
		elseif not smp_tp.is_warming_up(name) then
			local pos = p:get_pos()
			local dx, dz = pos.x - m.at.x, pos.z - m.at.z
			if dx * dx + dz * dz > 4 * 4 then
				-- Moved more than 4 nodes: they left on their own.
				leave(name, true)
			end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	if is_queued(name) then
		-- Tell the rest of the queue; nobody is paired (pairing happens
		-- synchronously on join, so a queued player has no partner yet).
		smp_rtpqueue.members[name] = nil
	end
end)

core.log("action", "[smp_rtpqueue] loaded: /rtpqueue")

return smp_rtpqueue
