-- FriedcakeSMP — smp_social external bridges
--
-- Three cross-mod lookups owned by other mods. Each bridge calls the
-- real implementation when that mod is loaded and otherwise falls back
-- to a PERMISSIVE default so f11 works standalone.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_social.bridges = {}

----------------------------------------------------------------------
-- f12 — player settings.
--
-- Contract (f12 landed with this in smp_settings/accessor.lua):
--   smp_settings.get(player_or_name, id)  -> value | nil   (canonical)
--   smp_settings.get_name(name, id)       -> value | nil   (legacy
--                                             shape f08 assumed; the
--                                             integrator normalises it
--                                             to `get`)
-- Both are tried; unknown ids return nil and fall through to the
-- permissive default.
--
-- Defaults are permissive (f12 §4.7: every setting defaults to its most
-- permissive value), i.e. "ON".
----------------------------------------------------------------------

local SETTING_DEFAULTS = {
	["chat.public"]          = "ON",
	["chat.private_messages"] = "ON",
	["chat.server_messages"] = "ON",
	["chat.hotbar_messages"]  = "ON",
	["chat.death_messages"]   = "ON",
	["chat.advancements"]     = "ON",
	["chat.join_leave"]       = "ON",
}

function smp_social.get_setting(player, key)
	-- Accept either an ObjectRef or a name (callers have both); the
	-- canonical smp_settings.get takes both, so pass the best we have.
	local name, arg
	if type(player) == "table" and player.get_player_name then
		arg, name = player, player:get_player_name()
	else
		name = player
		arg = (core.get_player_by_name and core.get_player_by_name(name)) or player
	end
	if smp_settings ~= nil and type(smp_settings) == "table" then
		if smp_settings.get ~= nil and arg ~= nil then
			local ok, v = pcall(smp_settings.get, arg, key)
			if ok and v ~= nil then return v end
		end
		if smp_settings.get_name ~= nil and name ~= nil then
			local ok, v = pcall(smp_settings.get_name, name, key)
			if ok and v ~= nil then return v end
		end
	end
	-- TODO(f12): permissive default until smp_settings lands.
	return SETTING_DEFAULTS[key] or "ON"
end

----------------------------------------------------------------------
-- f13 — rank chat prefix (gated behind chat.rank_prefix, default false
-- because no observed chat line carries a prefix; V-24).
----------------------------------------------------------------------

function smp_social.rank_prefix(name)
	if type(smp_ranks) == "table" and smp_ranks.chat_prefix ~= nil then
		local ok, prefix = pcall(smp_ranks.chat_prefix, name)
		if ok and type(prefix) == "string" and prefix ~= "" then
			return prefix
		end
	end
	-- TODO(f13): no prefix until smp_ranks ships one.
	return ""
end

-- Display form of a player's rank for /findplayer (§4.5 exposes rank).
function smp_social.rank_display(name)
	if type(smp_ranks) == "table" and smp_ranks.tier ~= nil then
		local ok, tier = pcall(smp_ranks.tier, name)
		if ok and type(tier) == "string" and tier ~= "" and tier ~= "default" then
			return tier
		end
	end
	-- TODO(f13): default tier has no display name.
	return S("None")
end

----------------------------------------------------------------------
-- Moderation mute. f01's admin helpers do not ship a mute yet; the
-- hook exists so /mute lands without touching smp_social (§4.1.3).
----------------------------------------------------------------------

function smp_social.is_muted(name)
	if type(smp_admin) == "table" and smp_admin.is_muted ~= nil then
		local ok, v = pcall(smp_admin.is_muted, name)
		if ok then return v and true or false end
	end
	-- TODO(admin): no mute graph yet.
	return false
end

return smp_social.bridges
