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
--   * Re-validate the DESTINATION at fire time when the other party
--     chose it (tpa/tpahere): the destination position is fixed at
--     accept time, the nodes there are not (S08/TP-1).
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
-- (used when a new warm-up simply replaces the old one). msg replaces
-- the default cancellation string when the caller has a more specific
-- one ("The destination is not safe", S08/TP-1); it is passed
-- untranslated, like the default, so both go through S() exactly once.
function smp_tp.cancel_warmup(name, silent, msg)
	local w = smp_tp.warmup[name]
	if not w then return end
	smp_tp.warmup[name] = nil
	w.token.cancelled = true
	clear_actionbar(name)
	if not silent then
		core.chat_send_player(name, S(msg or "Teleport cancelled"))
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
-- Destination safety (S08/TP-1)
--
-- A `/tpa` or `/tpahere` destination is picked by the OTHER party: the
-- sender can stand somewhere harmless, get the request accepted, and
-- build a lethal trap during the 5 s warm-up — place lava at their own
-- feet, dig a void shaft, wall the spot in (brief S08, TP-1).
--
-- The destination is frozen at accept time as a POSITION; what can
-- change are the nodes at that position. The check therefore runs
-- twice against the same coordinates: when the warm-up starts (before
-- any state is committed) and again at fire time, comparing the feet
-- node against the one captured at accept.
--
-- PROPOSED scope (S08): only third-party-controlled destinations are
-- checked — kind "tpa" and "tpahere". Server-chosen destinations
-- (rtp, spawn, warp, rtpqueue: config or find_safe_y, which validates
-- its own landing) and self-chosen ones (home, world, back) keep their
-- pre-existing behaviour; a player cannot trap themselves through
-- them, and f09's /home must keep working into areas that are not
-- even loaded.
--
-- Rules (every sample goes through the injectable smp_tp._node_at):
--   * "ignore" anywhere in the sampled window means the mapblock is
--     unloaded: judge nothing, teleport blind — exactly the
--     pre-existing behaviour (/home into an unloaded area keeps
--     working).
--   * No node in the window may be damaging: damage_per_second > 0 or
--     the `lava`/`fire` group. The group test is `> 0`, never
--     `== 1`: Mineclonia lava carries group value 3.
--   * The nodes the arriver's box would occupy above the feet must not
--     be solid — a standing player's head node never is, so a solid
--     there means the destination is blocked.
--   * The feet node must not have BECOME solid since accept
--     (`captured_feet`). Feet that were already solid are legitimate:
--     a player standing on a bottom slab, stairs or stacked snow
--     occupies a walkable node themselves (collision boxes, not node
--     grids — see the f08 Q-1 notes), and so does one lying in a bed.
--   * Walkable ground within GROUND_DEPTH nodes below the feet, so a
--     void shaft dug during the countdown cancels.
--
-- Returns `true, feet_node` or `false, "unsafe"`.
----------------------------------------------------------------------

-- How deep below the feet the ground may be: "a few nodes" (brief).
local GROUND_DEPTH = 3

local function dest_damaging(name)
	local def = core.registered_nodes and core.registered_nodes[name]
	if def and (def.damage_per_second or 0) > 0 then return true end
	if core.get_item_group then
		for _, group in ipairs({ "lava", "fire" }) do
			local ok, g = pcall(core.get_item_group, name, group)
			if ok and type(g) == "number" and g > 0 then return true end
		end
	end
	return false
end

-- Same convention as rtp.lua's node_is_walkable: a node with no
-- registered definition cannot be cleared, so treat it as solid.
local function dest_solid(name)
	local def = core.registered_nodes and core.registered_nodes[name]
	return not def or def.walkable ~= false
end

-- pos may be a plain {x,y,z} table (it always is: w.to is a snapshot).
-- captured_feet is nil on the accept-time call — there is nothing to
-- compare against yet, and a live player's own position is ground
-- truth by definition.
function smp_tp.destination_is_safe(pos, captured_feet)
	local x, z = math.floor(pos.x), math.floor(pos.z)
	-- The +0.001 absorbs the boundary noise of a position that should
	-- sit exactly on a node top but comes back as 60.999999.
	local y = math.floor(pos.y + 0.001)      -- feet node
	local top = math.floor(pos.y + 1.799)     -- top of the 1.8-node box
	local feet = smp_tp._node_at(x, y, z)

	local upper = {}
	for ny = y + 1, math.max(y + 1, top) do
		upper[#upper + 1] = smp_tp._node_at(x, ny, z)
	end
	local ground = {}
	for i = 1, GROUND_DEPTH do
		ground[#ground + 1] = smp_tp._node_at(x, y - i, z)
	end

	-- Unloaded: keep the pre-existing blind teleport.
	if feet == "ignore" then return true, feet end
	for _, n in ipairs(upper) do if n == "ignore" then return true, feet end end
	for _, n in ipairs(ground) do if n == "ignore" then return true, feet end end

	-- Damaging anywhere the player would stand, breathe or land.
	if dest_damaging(feet) then return false, "unsafe" end
	for _, n in ipairs(upper) do
		if dest_damaging(n) then return false, "unsafe" end
	end
	for _, n in ipairs(ground) do
		if dest_damaging(n) then return false, "unsafe" end
	end

	-- Head room: no solid in the box above the feet.
	for _, n in ipairs(upper) do
		if dest_solid(n) then return false, "unsafe" end
	end

	-- A solid feet node that was not there at accept time is a trap
	-- block placed during the countdown.
	if captured_feet ~= nil and feet ~= captured_feet and dest_solid(feet) then
		return false, "unsafe"
	end

	-- Ground within a few nodes below: no void shaft.
	for _, n in ipairs(ground) do
		if dest_solid(n) then return true, feet end
	end
	return false, "unsafe"
end

-- Kinds whose destination the counterparty chose (PROPOSED scope,
-- above). Everything else keeps the pre-existing behaviour.
local function third_party_destination(kind)
	return kind == "tpa" or kind == "tpahere"
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

	-- Destination safety (S08/TP-1): for a counterparty-chosen
	-- destination, validate BEFORE any warm-up state is committed and
	-- remember the feet node so fire time can tell a spot the other
	-- player was legitimately standing on (a slab, a bed) from one a
	-- trap block was placed on during the countdown.
	local check_dest = third_party_destination(kind)
	local dest_feet
	if check_dest then
		local safe, feet = smp_tp.destination_is_safe(pos, nil)
		dest_feet = feet
		if not safe then
			core.chat_send_player(name, S("The destination is not safe"))
			return false, "unsafe"
		end
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
		check_dest = check_dest,
		dest_feet = dest_feet,
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
		-- The destination may have become lethal while the countdown
		-- ran: the position is frozen, the nodes at it are not
		-- (S08/TP-1).
		if w.check_dest and not smp_tp.destination_is_safe(w.to, w.dest_feet) then
			smp_tp.cancel_warmup(name, false, "The destination is not safe")
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
		-- Luanti 5.17 has no set_player_velocity; cancel any residual
		-- velocity (e.g. fall momentum) via the knockback primitive.
		local vel = p:get_velocity()
		if vel then
			p:add_velocity(vector.new(-vel.x, -vel.y, -vel.z))
		end
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
