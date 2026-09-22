-- FriedcakeSMP — smp_tp teleport requests (f08 §4.4)
--
-- /tpa, /tpahere, /tpaccept, /tpadeny, /tpacancel, /tpauto,
-- /tpatoggle, /tpaheretoggle.
--
-- Privacy rule (T7): a target who is offline, ignores/blocks the
-- sender, or has the request type disabled produces ONE generic
-- refusal that reveals nothing about which rule fired — the chat
-- analogue of the observed privacy refusal style (F0276–F0285).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_tp.S

smp_tp.requests = {}

local function expiry() return os.time() + smp_tp.cfg.tpa.expiry end

----------------------------------------------------------------------
-- Invalidation (f08 §4.4.6): a request is cancelled if either party
-- is combat-tagged, dies or disconnects.
----------------------------------------------------------------------

-- Called by init.lua on leaveplayer/dieplayer for both the sending
-- and the receiving side.
function smp_tp.cancel_requests_of(name)
	local st = smp_tp.state[name]
	if not st then return end
	for target, types in pairs(st.requests_out) do
		for t in pairs(types) do
			if core.player_exists(target) then
				core.chat_send_player(target,
					S("Teleport request from @1 cancelled", name))
				smp_tp.drop_request(target, name, t)
			end
		end
	end
	for sender, types in pairs(st.requests_in) do
		for t in pairs(types) do
			if core.player_exists(sender) then
				core.chat_send_player(sender,
					S("Teleport request to @1 cancelled", name))
				smp_tp.drop_request(sender, name, t)
			end
		end
	end
	st.requests_out = {}
	st.requests_in = {}
end

-- Remove one stored request from the target's (for `from` / `type`).
function smp_tp.drop_request(target_name, from, type)
	local tst = smp_tp.get_state(target_name)
	local types = tst.requests_in[from]
	if types then types[type] = nil; if not next(types) then tst.requests_in[from] = nil end end
end

-- The sender-side mirror of drop_request.
function smp_tp.drop_request_out(sender_name, target, type)
	local st = smp_tp.get_state(sender_name)
	local types = st.requests_out[target]
	if types then types[type] = nil; if not next(types) then st.requests_out[target] = nil end end
end

-- Called by init.lua when a party dies or leaves: cancel every
-- request that involves the name, on both sides, with chat notice.
function smp_tp.invalidate_requests_involving(name)
	smp_tp.cancel_requests_of(name)
end

----------------------------------------------------------------------
-- The generic refusal (T7)
--
-- One message for every privacy rule. It must NOT name the rule:
-- "offline" would confirm presence; "you blocked them" would confirm
-- the block. PROPOSED house-style string.
----------------------------------------------------------------------

local GENERIC_REFUSAL = "This player cannot be asked for a teleport"

local function send_request(sender, target, type)
	-- Validation order matters: all privacy checks before any side
	-- effect, and the refusal string is identical for every rule (T7).
	if not core.player_exists(target) then
		core.chat_send_player(sender, S(GENERIC_REFUSAL))
		return false
	end
	local tstate = smp_tp.get_state(target)
	local accept_key = (type == "tpa") and "accept_tpa" or "accept_tpahere"
	if tstate[accept_key] == false then
		core.chat_send_player(sender, S(GENERIC_REFUSAL))
		return false
	end
	if smp_tp.bridge.blocks(target, sender) then
		core.chat_send_player(sender, S(GENERIC_REFUSAL))
		return false
	end
	if smp_tp.bridge.blocks(sender, target) then
		core.chat_send_player(sender, S(GENERIC_REFUSAL))
		return false
	end
	-- Sender already asking this target for the same type? Refresh.
	local sstate = smp_tp.get_state(sender)
	sstate.requests_out[target] = sstate.requests_out[target] or {}
	sstate.requests_out[target][type] = expiry()
	tstate.requests_in[sender] = tstate.requests_in[sender] or {}
	tstate.requests_in[sender][type] = expiry()

	-- f12: chat privacy Friends/Followed SHOULD apply to requests too
	-- (f08 §4.4.7). The bridge returns nil until smp_settings lands.
	local privacy = smp_tp.bridge.get_name(target, "chat.privacy")
	if privacy and privacy ~= "on" and not smp_tp._is_friend_or_followed(target, sender) then
		-- Roll back the stored request; same generic refusal.
		smp_tp.drop_request(target, sender, type)
		smp_tp.drop_request_out(sender, target, type)
		core.chat_send_player(sender, S(GENERIC_REFUSAL))
		return false
	end

	if tstate.auto_accept then
		-- /tpauto: accept immediately, no dialog (f08 §4.4.4).
		local ok = smp_tp.accept_request(target, sender, type)
		if not ok then
			core.chat_send_player(sender, S(GENERIC_REFUSAL))
		end
		return ok
	end
	if smp_tp.cfg.tp.confirm_menu then
		smp_tp.show_request_dialog(target, sender, type)
	else
		core.chat_send_player(target,
			S("@1 wants to teleport to you. Use /tpaccept or /tpadeny", sender))
	end
	core.chat_send_player(sender, S("Teleport request sent to @1", target))
	return true
end

-- f11 owns the friend graph; bridge placeholder (permissive default:
-- privacy restriction not applied until f11 lands).
smp_tp._is_friend_or_followed = function(a, b)
	-- TODO(f11): smp_social.is_friend_or_followed when it lands.
	return false
end

smp_tp.requests.send_request = send_request

----------------------------------------------------------------------
-- Accept / deny
----------------------------------------------------------------------

local function move_party(mover, destination_pos, kind)
	local p = core.get_player_by_name(mover)
	if not p then return false end
	if smp_tp.bridge.is_tagged(mover) then
		core.chat_send_player(mover, S("You cannot teleport while in combat"))
		return false
	end
	-- Drop the request pair before warming up (T8: acceptance warms up
	-- the moving party only).
	return smp_tp.teleport_with_warmup(p, destination_pos, kind)
end

-- Accepts the request from `from` of `type`. Returns success.
function smp_tp.accept_request(name, from, type)
	local st = smp_tp.get_state(name)
	local types = st.requests_in[from]
	if not types or not types[type] then
		core.chat_send_player(name, S("You have no such teleport request from @1", from))
		return false
	end
	-- Re-validate at accept time: sender still online, not tagged.
	if not core.player_exists(from) or smp_tp.bridge.is_tagged(from) then
		core.chat_send_player(name, S("You have no such teleport request from @1", from))
		smp_tp.drop_request(name, from, type)
		return false
	end
	if smp_tp.bridge.is_tagged(name) then
		core.chat_send_player(name, S("You cannot teleport while in combat"))
		return false
	end
	smp_tp.drop_request(name, from, type)
	smp_tp.drop_request_out(from, name, type)

	local p_from = core.get_player_by_name(from)
	local p_to = core.get_player_by_name(name)
	if not p_from or not p_to then return false end
	if type == "tpa" then
		-- /tpa: the sender moves to the TARGET's position.
		return move_party(from, p_to:get_pos(), "tpa")
	elseif type == "tpahere" then
		-- /tpahere: the target moves to the SENDER's position.
		return move_party(name, p_from:get_pos(), "tpahere")
	end
	return false
end

function smp_tp.deny_request(name, from, type)
	local st = smp_tp.get_state(name)
	local types = st.requests_in[from]
	if types and types[type] then
		smp_tp.drop_request(name, from, type)
		smp_tp.drop_request_out(from, name, type)
		if core.player_exists(from) then
			core.chat_send_player(from, S("@1 declined your teleport request", name))
		end
		return true
	end
	core.chat_send_player(name, S("You have no such teleport request from @1", from))
	return false
end

function smp_tp.cancel_request_out(name, target)
	local st = smp_tp.get_state(name)
	local types = st.requests_out[target]
	if not types or not next(types) then
		core.chat_send_player(name, S("You have no pending request to @1", target))
		return false
	end
	local had = false
	for t in pairs(types) do
		smp_tp.drop_request(target, name, t)
		had = true
	end
	st.requests_out[target] = nil
	if had and core.player_exists(target) then
		core.chat_send_player(target, S("Teleport request from @1 cancelled", name))
	end
	return true
end

-- Argument-free /tpaccept: accept the newest request (PROPOSED).
function smp_tp.newest_request(name)
	local st = smp_tp.get_state(name)
	local newest, newest_from, newest_type
	for from, types in pairs(st.requests_in) do
		for t, exp in pairs(types) do
			if not newest or exp > newest then
				newest, newest_from, newest_type = exp, from, t
			end
		end
	end
	return newest_from, newest_type
end

function smp_tp.toggle_setting(name, key, label)
	local st = smp_tp.get_state(name)
	st[key] = not (st[key] == true)
	if st[key] == false then
		core.chat_send_player(name, S(label .. ": OFF"))
	else
		core.chat_send_player(name, S(label .. ": ON"))
	end
end

return smp_tp
