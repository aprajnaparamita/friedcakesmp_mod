-- FriedcakeSMP — smp_social /nightvision (f11 §4.6)
--
-- Toggles mcl_potions night_vision and persists the choice in player
-- meta; it is re-applied on join and respawn. The recording shows a
-- Night Vision HUD effect throughout [F0122, F0142] — a client-rendered
-- effect indicator, not server UI.
--
-- Level 1 with an "INF" duration, following the §4.6 algorithm
-- (mcl_potions converts "INF" to an infinite timer internally).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

local META_KEY = "smp_social:nightvision"

local function apply(player)
	if player:get_meta():get_int(META_KEY) ~= 1 then return end
	if type(mcl_potions) ~= "table" or not mcl_potions.give_effect_by_level then
		return -- TODO(minemods): mcl_potions absent; meta stays, nothing to apply
	end
	mcl_potions.give_effect_by_level("night_vision", player, 1, "INF")
end

local function clear(player)
	if type(mcl_potions) ~= "table" or not mcl_potions.clear_effect then
		return
	end
	mcl_potions.clear_effect(player, "night_vision")
end

smp_social.register_cmd("nightvision", {
	params = "",
	description = S("Toggle night vision"),
	func = function(name, _param)
		local player = core.get_player_by_name(name)
		if not player then
			return smp_social.say(name, S("That player is not online"))
		end
		if type(mcl_potions) ~= "table" or not mcl_potions.give_effect_by_level then
			return smp_social.say(name, S("Night vision is not available"))
		end
		local meta = player:get_meta()
		if meta:get_int(META_KEY) == 1 then
			meta:set_int(META_KEY, 0)
			clear(player)
			return smp_social.say(name, S("Night vision disabled"))
		end
		meta:set_int(META_KEY, 1)
		mcl_potions.give_effect_by_level("night_vision", player, 1, "INF")
		return smp_social.say(name, S("Night vision enabled"))
	end,
}, { "nv" })

-- Persisted choice survives reconnects and deaths.
core.register_on_joinplayer(apply)
core.register_on_respawnplayer(apply)

return true
