-- FriedcakeSMP — smp_social
--
-- Public chat, private messages, ignore/block, friends and follows,
-- /findplayer, /kill, /nightvision, informational commands and the
-- unknown-command response.
--
-- Implements spec/features/f11-social.md. The three load-bearing
-- OBSERVED strings reproduced here:
--   * `<@1> @2` public chat format with NO rank prefix (§3.1, T1)
--   * `This user only accepts messages from friends or followed players`
--     — the one generic /msg refusal for both privacy and ignore (§4.2,
--     §6, T3/T5)
--   * `This command does not exist` (§4.7, T8)
--
-- Public surface consumed by f08 (smp_tp) and f10 (smp_combat):
--   smp_social.blocks(a, b)                — a blocks or ignores b
--   smp_social.ignores(a, b)               — a ignores b
--   smp_social.is_friend_or_followed(a, b) — b is a friend of a or followed by a
--   smp_social.send_pm(sender, target, message)
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_social = {
	S = S,
	-- Commands this mod owns, for re-assertion after all mods load
	-- (Mineclonia's mcl_commands re-registers /kill and /list).
	_mine = {},
	-- /r reply targets (in-memory only; f11 §5 last_pm is not persisted)
	_last_pm = {},
	-- public chat rate-limit / duplicate state, cleared on leave
	_chat_state = {},
}

----------------------------------------------------------------------
-- Configuration (f11 §7)
----------------------------------------------------------------------

local function get_str(key, default)
	local v = core.settings:get(key)
	if v == nil or v == "" then return default end
	return v
end

local function get_num(key, default)
	return tonumber(core.settings:get(key)) or default
end

local function get_bool(key, default)
	local v = core.settings:get_bool(key)
	if v == nil then return default end
	return v and true or false
end

local cfg = {
	chat = {
		format          = get_str("chat.format", "<@1> @2"),   -- OBSERVED [F0269]
		rank_prefix     = get_bool("chat.rank_prefix", false), -- PROPOSED; V-24 stays open
		rate_limit      = get_num("chat.rate_limit", 1),       -- seconds between messages
		duplicate_filter = get_bool("chat.duplicate_filter", true),
	},
	social = {
		max_follows     = get_num("social.max_follows", 200),
		friend_notify   = get_bool("social.friend_notify", true),
		tpa_hint        = get_bool("social.tpa_hint", true),
	},
	findplayer = {
		spawn_radius    = get_num("findplayer.spawn_radius", 512),
		region_band     = get_num("findplayer.region_band", 2048),
	},
}
smp_social.cfg = cfg

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

-- Send one chat line. Always returns true so command funcs can
-- `return say(...)` without the engine printing a usage error.
function smp_social.say(name, msg)
	core.chat_send_player(name, msg)
	return true
end

-- Register (or override) a command and its aliases. Aliases are plain
-- delegating commands: Luanti has no native chatcommand aliases, and a
-- runtime delegate picks up a later override of the main command.
function smp_social.register_cmd(name, def, aliases)
	smp_social._mine[name] = def
	if core.registered_chatcommands[name] then
		core.override_chatcommand(name, def)
	else
		core.register_chatcommand(name, def)
	end
	for _, a in ipairs(aliases or {}) do
		if not core.registered_chatcommands[a] then
			local adef = {
				params = def.params,
				description = def.description,
				privs = def.privs,
				func = function(pname, param)
					local main = core.registered_chatcommands[name]
					if not main then
						-- Cannot happen while smp_social is loaded.
						return false, S("This command does not exist")
					end
					return main.func(pname, param)
				end,
			}
			smp_social._mine[a] = adef
			core.register_chatcommand(a, adef)
		end
	end
end

----------------------------------------------------------------------
-- Load order: bridges first, then the feature files. Every file needs
-- its own S (dofile runs in the global environment).
----------------------------------------------------------------------

local MP = core.get_modpath("smp_social")

dofile(MP .. "/bridges.lua")       -- f12 settings, f13 rank prefix, mutes
dofile(MP .. "/graph.lua")         -- follow / ignore / block predicates
dofile(MP .. "/ignore.lua")        -- /ignore /block
dofile(MP .. "/friends.lua")       -- /friend + join/leave notices
dofile(MP .. "/chat.lua")          -- public chat delivery
dofile(MP .. "/pm.lua")            -- /msg /r with the generic refusal
dofile(MP .. "/findplayer.lua")    -- coarse /findplayer
dofile(MP .. "/kill.lua")          -- /kill with confirmation
dofile(MP .. "/nightvision.lua")   -- /nightvision
dofile(MP .. "/info.lua")          -- /help /rules and the link commands
dofile(MP .. "/misc.lua")          -- /ping /list /report /helpop

----------------------------------------------------------------------
-- §4.7 Unknown commands: `This command does not exist` [F0055]
-- replaces the engine's `Invalid command: <name>`.
--
-- The builtin chat handler runs core.registered_on_chatcommands BEFORE
-- the command lookup; returning true there cancels the rest of the
-- builtin handler, so the engine's own message is never printed.
----------------------------------------------------------------------

local function on_unknown_command(name, cmd, _param)
	if core.registered_chatcommands[cmd] then
		return nil -- registered: let the builtin handler continue
	end
	core.chat_send_player(name, S("This command does not exist"))
	return true
end

core.register_on_chatcommand(on_unknown_command)
smp_social._on_unknown_command = on_unknown_command

-- Re-assert every command we own once all mods have loaded.
-- Mineclonia's mcl_commands unconditionally re-registers /kill and /list;
-- if it loads after smp_social it would otherwise shadow ours.
core.register_on_mods_loaded(function()
	for n, def in pairs(smp_social._mine) do
		if core.registered_chatcommands[n] then
			core.override_chatcommand(n, def)
		else
			core.register_chatcommand(n, def)
		end
	end
end)

core.log("action", "[smp_social] loaded: chat, pm, ignore/block, friends, "
	.. "findplayer, kill, nightvision, info, misc")
