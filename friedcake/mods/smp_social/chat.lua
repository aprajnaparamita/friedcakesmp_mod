-- FriedcakeSMP — smp_social public chat (f11 §4.1)
--
-- Format `<@1> @2` — angle brackets, name, space, message [F0269].
-- NO rank prefix: none appears on any of the ~30 observed chat lines
-- (V-24 stays open; chat.rank_prefix defaults false). Do not resurrect
-- v0.1's `[Rank] Name: message`.
--
-- core.register_on_chat_message returns true and we deliver the line
-- ourselves, per recipient: the observed settings are per-player, so
-- there is no single broadcast (shared §3.2 substitution table, f11 §8).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

----------------------------------------------------------------------
-- Formatting (T1)
----------------------------------------------------------------------

function smp_social.format_chat(sender, message)
	local prefix = ""
	if smp_social.cfg.chat.rank_prefix then
		-- PROPOSED placement: the prefix sits outside the brackets
		-- (`[Rank] <Name> message`) and only when explicitly enabled.
		prefix = smp_social.rank_prefix(sender)
	end
	return prefix .. S(smp_social.cfg.chat.format, sender, message)
end

----------------------------------------------------------------------
-- Delivery (T2, T6, T7)
----------------------------------------------------------------------

local function may_receive_public(viewer, viewer_player, sender)
	-- Ignore/block first: they win over every setting value (§4.1.2).
	if smp_social.ignores(viewer, sender) then return false end
	if smp_social.blocks(viewer, sender) then return false end
	local pref = smp_social.get_setting(viewer_player, "chat.public")
	if pref == "OFF" then return false end
	if pref == "FRIENDS_FOLLOWED" then
		-- Not an observed value for Public Chat (the domain is ON/OFF),
		-- accepted forward-compat: only graph members are shown.
		return smp_social.is_friend_or_followed(viewer, sender)
	end
	return true -- ON
end

-- Delivers one public message to every eligible recipient. Exported so
-- the smoke tests can drive it without the chat callback chain.
function smp_social.broadcast_public(sender, message)
	local line = smp_social.format_chat(sender, message)
	local hint = smp_social.cfg.social.tpa_hint
		and S("Click to send @1 a teleport request", sender)
		or nil
	-- One synchronous pass, no yields (shared §2.3): the recipient set
	-- must not change under us mid-loop.
	for _, p in ipairs(core.get_connected_players()) do
		local viewer = p:get_player_name()
		if may_receive_public(viewer, p, sender) then
			core.chat_send_player(viewer, line)
			-- Substitution for clickable chat (shared §0.3, §4.8): the
			-- hint is a SECOND chat line naming the sender, never a fake
			-- hover/click decoration. The sender does not get the hint
			-- about their own name (T7).
			if hint and viewer ~= sender then
				core.chat_send_player(viewer, hint)
			end
		end
	end
	return true
end

----------------------------------------------------------------------
-- The chat callback: mute, anti-spam, duplicate filter, then deliver.
----------------------------------------------------------------------

local function clock()
	if core.get_gametime then return core.get_gametime() end
	return os.time()
end

core.register_on_chat_message(function(name, message)
	if message:sub(1, 1) == "/" then
		return nil -- commands belong to the builtin handler (registered first)
	end

	-- Players without shout keep the engine's own refusal path.
	if core.check_player_privs and not core.check_player_privs(name, { shout = true }) then
		return nil
	end

	-- §4.1.3: mutes are enforced here.
	if smp_social.is_muted(name) then
		core.chat_send_player(name, S("You are muted"))
		return true
	end

	local cfgc = smp_social.cfg.chat
	local st = smp_social._chat_state[name]
	if not st then
		st = {}
		smp_social._chat_state[name] = st
	end
	local now = clock()

	-- PROPOSED anti-spam: at most one message per chat.rate_limit seconds.
	if cfgc.rate_limit > 0 and st.last_time ~= nil
			and now - st.last_time < cfgc.rate_limit then
		core.chat_send_player(name, S("You are sending messages too quickly"))
		return true
	end

	-- PROPOSED duplicate filter: drop a verbatim repeat of your own
	-- previous message.
	if cfgc.duplicate_filter and st.last_msg == message then
		core.chat_send_player(name, S("Do not repeat yourself"))
		return true
	end

	st.last_time = now
	st.last_msg = message

	smp_social.broadcast_public(name, message)
	return true -- eaten: we delivered it ourselves
end)

return true
