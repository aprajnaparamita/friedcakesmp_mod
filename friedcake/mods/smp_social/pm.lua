-- FriedcakeSMP — smp_social private messages (f11 §4.2)
--
-- /msg replaces the builtin via core.override_chatcommand; /r replies
-- to the last private message (CLONE [C1]).
--
-- The refusal rule: the ignore branch and the FRIENDS_FOLLOWED branch
-- MUST be indistinguishable — revealing "you have been ignored" is
-- itself information, and the observed server gives one generic
-- refusal [F0276–F0285] (T3, T5). Both call generic_refusal(), so
-- identity is structural, not coincidental.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

local GENERIC = "This user only accepts messages from friends or followed players"

-- Exported for the acceptance tests (T3/T5 compare against this).
function smp_social.generic_refusal()
	return S(GENERIC)
end

local function deliver_pm(sender, target_player, message)
	local tname = target_player:get_player_name()
	-- PROPOSED delivery format: the observed corpus shows only the
	-- refusal, never a delivered PM (see §10).
	core.chat_send_player(tname, S("@1 whispers to you: @2", sender, message))
	core.chat_send_player(sender, S("You whisper to @1: @2", tname, message))
end

function smp_social.send_pm(sender, target_name, message)
	local target = core.get_player_by_name(target_name)
	if not target then
		return smp_social.say(sender, S("That player is not online"))
	end
	local tname = target:get_player_name()

	-- §4.2.4: ignore and block are checked BEFORE the setting, and
	-- answer with the SAME generic refusal as the privacy branch.
	if smp_social.ignores(tname, sender) or smp_social.blocks(tname, sender) then
		return smp_social.say(sender, smp_social.generic_refusal())
	end

	local pref = smp_social.get_setting(target, "chat.private_messages")
	if pref == "OFF" then
		return smp_social.say(sender, S("This user is not accepting private messages"))
	elseif pref == "FRIENDS_FOLLOWED"
			and not smp_social.is_friend_or_followed(tname, sender) then
		return smp_social.say(sender, smp_social.generic_refusal())
	end

	-- Both sides may now reply to each other (§5: last_pm, not persisted).
	smp_social._last_pm[sender] = tname
	smp_social._last_pm[tname] = sender

	deliver_pm(sender, target, message)
	return true
end

----------------------------------------------------------------------
-- /msg and its observed-era aliases
----------------------------------------------------------------------

smp_social.register_cmd("msg", {
	params = S("<player> <message>"),
	description = S("Send a private message to a player"),
	privs = { shout = true },
	func = function(name, param)
		local target, message = (param or ""):match("^(%S+)%s+(.+)$")
		if not target then return false end -- engine prints the usage line
		return smp_social.send_pm(name, target, message)
	end,
}, { "message", "tell", "w", "whisper", "pm" })

----------------------------------------------------------------------
-- /r — reply to the last private message
----------------------------------------------------------------------

smp_social.register_cmd("r", {
	params = S("<message>"),
	description = S("Reply to the last private message"),
	privs = { shout = true },
	func = function(name, param)
		param = (param or ""):match("^%s*(.-)%s*$") or ""
		if param == "" then return false end
		local target = smp_social._last_pm[name]
		if not target then
			return smp_social.say(name, S("You have no one to reply to"))
		end
		return smp_social.send_pm(name, target, param)
	end,
}, { "reply" })

return true
