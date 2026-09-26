-- FriedcakeSMP — smp_social /kill (f11 §4.6)
--
-- Drops items and respawns after a confirmation dialog (CLONE [C1]).
-- The dialog is a prompt menu in the observed grammar (shared §4.1,
-- §4.7): Cancel red on the left, the commit button named for the act.
--
-- Combat-tag credit (§4.6, f10 §4.4): set_hp(0) produces a normal
-- death; f10's register_on_dieplayer credits `killer_from(reason) or
-- last_attacker(victim)` and pays any bounty, so /kill cannot deny a
-- kill. No second credit is issued from here (double-credit risk).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

local FORMNAME = "smp_social:kill"
local E = core.formspec_escape

local function confirm_formspec()
	return table.concat({
		"formspec_version[6]",
		"size[7.2,3.8]",
		"bgcolor[#000000C0]",
		"label[0.6,0.7;" .. E(S("Kill")) .. "]",
		"label[0.6,1.5;6,0.8;" .. E(S("Are you sure you want to kill yourself?")) .. "]",
		"style[kill_cancel;bgcolor=red]",
		"button[0.6,2.6;2.8,0.8;kill_cancel;" .. E(S("Cancel")) .. "]",
		"button[3.8,2.6;2.8,0.8;kill_confirm;" .. E(S("Kill")) .. "]",
	}, "")
end

smp_social.register_cmd("kill", {
	params = "",
	description = S("Drop your items and respawn, after confirmation"),
	func = function(name, _param)
		local player = core.get_player_by_name(name)
		if not player then
			return smp_social.say(name, S("That player is not online"))
		end
		-- Server-side session: forged fields are re-validated against it.
		smp_core.open_session(name, FORMNAME, { pending = true })
		core.show_formspec(name, FORMNAME, confirm_formspec())
		return true
	end,
})

----------------------------------------------------------------------
-- Confirmation handling
----------------------------------------------------------------------

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORMNAME then return nil end
	local name = player:get_player_name()
	-- Every action is re-validated against the session (shared §2.4):
	-- a field without a session is ignored.
	local session = smp_core.get_session(name, FORMNAME)
	if not session then return nil end
	smp_core.close_session(name, FORMNAME)
	core.close_formspec(name, FORMNAME)
	if fields.kill_confirm then
		-- No yield between validation and mutation. Death triggers the
		-- normal Mineclonia drop/respawn path and f10's kill credit.
		local still = core.get_player_by_name(name)
		if still and still:get_hp() > 0 then
			still:set_hp(0)
		end
	end
	return true
end)

return true
