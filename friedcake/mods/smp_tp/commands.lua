-- FriedcakeSMP — smp_tp command registration (f08 §2, §4.5)
--
-- /rtp, /tpa family, /spawn, /warp, /world, /back.
-- Every command-initiated teleport goes through the §4.1 warm-up.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_tp.S

local function trim(s)
	s = s or ""
	local start = 1
	while start <= #s do
		local b = s:byte(start)
		if b ~= 32 and b ~= 9 then break end
		start = start + 1
	end
	local finish = #s
	while finish >= start do
		local b = s:byte(finish)
		if b ~= 32 and b ~= 9 then break end
		finish = finish - 1
	end
	return s:sub(start, finish)
end

local function require_player(name)
	local p = core.get_player_by_name(name)
	if not p then
		core.chat_send_player(name, S("You are not online"))
		return nil
	end
	return p
end

local function combat_refuse(name)
	core.chat_send_player(name, S("You cannot teleport while in combat"))
	return false
end

local function busy_refuse(name)
	core.chat_send_player(name, S("Already teleporting"))
	return false
end

----------------------------------------------------------------------
-- /rtp (registered here; logic in rtp.lua)
----------------------------------------------------------------------

core.register_chatcommand("rtp", {
	params = S("[overworld|nether|end|region]"),
	description = S("Teleport to a random location."),
	func = function(name, param)
		return smp_tp.cmd_rtp(name, trim(param))
	end,
})

----------------------------------------------------------------------
-- /tpa family
----------------------------------------------------------------------

local function cmd_tpa(name, target, type)
	if not target or target == "" then
		core.chat_send_player(name, S("Usage: /tpa <player>"))
		return false
	end
	target = trim(target)
	if target == name then
		core.chat_send_player(name, S("You cannot request yourself"))
		return false
	end
	if smp_tp.bridge.is_tagged(name) then
		return combat_refuse(name)
	end
	if smp_tp.is_warming_up(name) then
		return busy_refuse(name)
	end
	local rem = smp_tp.cooldown_remaining(name, "tpa")
	if rem > 0 then
		core.chat_send_player(name, S("You can send a request again in @1s", rem))
		return false
	end
	local ok = smp_tp.requests.send_request(name, target, type)
	if ok then
		smp_tp.start_cooldown(name, "tpa")
	end
	return ok
end

core.register_chatcommand("tpa", {
	params = S("<player>"),
	description = S("Ask a player to let you teleport to them."),
	func = function(name, param)
		return cmd_tpa(name, trim(param), "tpa")
	end,
})

core.register_chatcommand("tp", {
	params = S("<player>"),
	description = S("Alias for /tpa (as on the reference server)."),
	func = function(name, param)
		return cmd_tpa(name, trim(param), "tpa")
	end,
})

core.register_chatcommand("tpahere", {
	params = S("<player>"),
	description = S("Ask a player to teleport to you."),
	func = function(name, param)
		return cmd_tpa(name, trim(param), "tpahere")
	end,
})

core.register_chatcommand("tpaccept", {
	params = S("[player]"),
	description = S("Accept a teleport request (newest if no name)."),
	func = function(name, param)
		local target = trim(param)
		if target == "" then
			local from, type = smp_tp.newest_request(name)
			if not from then
				core.chat_send_player(name, S("You have no pending teleport requests"))
				return false
			end
			return smp_tp.accept_request(name, from, type) and true or false
		end
		-- Named form: accept the newest of that sender's requests.
		local st = smp_tp.get_state(name)
		local types = st.requests_in[target]
		if not types or not next(types) then
			core.chat_send_player(name,
				S("You have no such teleport request from @1", target))
			return false
		end
		local newest, newest_type
		for t, exp in pairs(types) do
			if not newest or exp > newest then newest, newest_type = exp, t end
		end
		return smp_tp.accept_request(name, target, newest_type) and true or false
	end,
})

core.register_chatcommand("tpadeny", {
	params = S("<player>"),
	description = S("Deny a teleport request."),
	func = function(name, param)
		local target = trim(param)
		if target == "" then
			core.chat_send_player(name, S("Usage: /tpadeny <player>"))
			return false
		end
		local st = smp_tp.get_state(name)
		local types = st.requests_in[target]
		local ok = false
		if types then
			for t in pairs(types) do
				smp_tp.deny_request(name, target, t)
				ok = true
			end
		end
		if not ok then
			core.chat_send_player(name,
				S("You have no such teleport request from @1", target))
		end
		return ok
	end,
})

core.register_chatcommand("tpdeny", {
	params = S("<player>"),
	description = S("Alias for /tpadeny."),
	func = function(name, param)
		local cmd = core.registered_chatcommands["tpadeny"]
		if cmd and cmd.func then return cmd.func(name, param) end
		return false, S("Internal error: /tpadeny missing.")
	end,
})

core.register_chatcommand("tpacancel", {
	params = S("[player]"),
	description = S("Cancel a teleport request you sent."),
	func = function(name, param)
		local target = trim(param)
		if target == "" then
			local st = smp_tp.get_state(name)
			local had = false
			for t in pairs(st.requests_out) do
				smp_tp.cancel_request_out(name, t)
				had = true
			end
			if not had then
				core.chat_send_player(name, S("You have no pending teleport requests"))
				return false
			end
			return true
		end
		return smp_tp.cancel_request_out(name, target) and true or false
	end,
})

core.register_chatcommand("tpauto", {
	params = S(""),
	description = S("Toggle automatic acceptance of teleport requests."),
	func = function(name, _)
		smp_tp.toggle_setting(name, "auto_accept", "Auto accept")
		return true
	end,
})

core.register_chatcommand("tpatoggle", {
	params = S(""),
	description = S("Toggle whether /tpa requests are accepted from you."),
	func = function(name, _)
		smp_tp.toggle_setting(name, "accept_tpa", "Teleport requests")
		return true
	end,
})

core.register_chatcommand("tpaheretoggle", {
	params = S(""),
	description = S("Toggle whether /tpahere requests are accepted from you."),
	func = function(name, _)
		smp_tp.toggle_setting(name, "accept_tpahere", "Teleport-here requests")
		return true
	end,
})

----------------------------------------------------------------------
-- /spawn, /warp (f08 §4.5)
----------------------------------------------------------------------

function smp_tp.go_to_lobby(name, id)
	local p = require_player(name)
	if not p then return false end
	if smp_tp.bridge.is_tagged(name) then
		return combat_refuse(name)
	end
	if smp_tp.is_warming_up(name) then
		return busy_refuse(name)
	end
	local pos
	if id == "main" then
		pos = smp_tp._spawn_position()
	else
		local l = smp_tp.cfg.lobbies[id]
		if not l then
			core.chat_send_player(name, S("Unknown lobby: @1", id))
			return false
		end
		pos = vector.new(l.x, l.y, l.z)
	end
	smp_tp.teleport_with_warmup(p, pos, "spawn")
	smp_tp.start_cooldown(name, "spawn")
	return true
end

core.register_chatcommand("spawn", {
	params = S("[lobby]"),
	description = S("Open the spawn lobby menu, or go to a named lobby."),
	func = function(name, param)
		local lobby = trim(param)
		if lobby == "" then
			-- No argument: lobby menu (f08 §4.5.1).
			smp_tp.show_spawn_menu(name)
			return true
		end
		return smp_tp.go_to_lobby(name, lobby)
	end,
})

core.register_chatcommand("warp", {
	params = S("<location>"),
	description = S("Teleport to a spawn utility location."),
	func = function(name, param)
		local id = trim(param):lower()
		if id == "" then
			core.chat_send_player(name, S("Usage: /warp <location>"))
			return false
		end
		local w = smp_tp.cfg.warps[id]
		if not w then
			core.chat_send_player(name, S("Unknown warp: @1", id))
			return false
		end
		local p = require_player(name)
		if not p then return false end
		if smp_tp.bridge.is_tagged(name) then
			return combat_refuse(name)
		end
		if smp_tp.is_warming_up(name) then
			return busy_refuse(name)
		end
		smp_tp.teleport_with_warmup(p, vector.new(w.x, w.y, w.z), "warp")
		smp_tp.start_cooldown(name, "warp")
		return true
	end,
})

----------------------------------------------------------------------
-- /world, /back (f08 §4.5.3–4)
--
-- /world: the position before the LAST command-initiated teleport.
-- One level deep: /world itself must NOT refresh last_teleport_from,
-- or it would chain backwards (PROPOSED, f08 §4.5.3).
----------------------------------------------------------------------

core.register_chatcommand("world", {
	params = S(""),
	description = S("Return to the position before your last teleport."),
	func = function(name, _)
		local st = smp_tp.get_state(name)
		local from = st.last_teleport_from
		if not from then
			core.chat_send_player(name, S("You have no teleport to return from"))
			return false
		end
		local p = require_player(name)
		if not p then return false end
		if smp_tp.bridge.is_tagged(name) then
			return combat_refuse(name)
		end
		if smp_tp.is_warming_up(name) then
			return busy_refuse(name)
		end
		smp_tp.teleport_with_warmup(p, from, "world", { record_from = false })
		smp_tp.start_cooldown(name, "world")
		return true
	end,
})

core.register_chatcommand("back", {
	params = S(""),
	description = S("Return to your last death or teleport location."),
	func = function(name, _)
		if not smp_tp.cfg.tp.back_enabled then
			core.chat_send_player(name, S("/back is disabled on this server"))
			return false
		end
		local st = smp_tp.get_state(name)
		local pos = st.last_death or st.last_teleport_from
		if not pos then
			core.chat_send_player(name, S("You have no location to return to"))
			return false
		end
		local p = require_player(name)
		if not p then return false end
		if smp_tp.bridge.is_tagged(name) then
			return combat_refuse(name)
		end
		if smp_tp.is_warming_up(name) then
			return busy_refuse(name)
		end
		smp_tp.teleport_with_warmup(p, pos, "back", { record_from = false })
		smp_tp.start_cooldown(name, "back")
		return true
	end,
})

core.register_chatcommand("return", {
	params = S(""),
	description = S("Alias for /back."),
	func = function(name, param)
		local cmd = core.registered_chatcommands["back"]
		if cmd and cmd.func then return cmd.func(name, param) end
		return false, S("Internal error: /back missing.")
	end,
})

return smp_tp
