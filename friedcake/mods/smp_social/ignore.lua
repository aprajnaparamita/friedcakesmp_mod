-- FriedcakeSMP — smp_social ignore and block (f11 §4.3)
--
-- The narration [F0287] is the only evidence for what /ignore does: it
-- covers messages AND teleport requests. The remaining split (payments,
-- follows, RTP-queue pairing) is block-only and PROPOSED; see §4.3 and
-- §10 (V-48).
--
-- Effect enforcement lives where the effects live:
--   * public chat hiding  — chat.lua (per-recipient filter)
--   * private messages    — pm.lua (generic refusal)
--   * teleport requests   — smp_social.blocks(), which f08 gates on
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

local USAGE = S("<player>")

local function player_exists(name)
	if core.player_exists then return core.player_exists(name) end
	return true -- engine always provides this; permissive in tests
end

-- Shared /ignore //block behaviour. verb = "ignore" | "block".
local function toggle(name, param, key, list_key)
	param = (param or ""):match("^%s*(.-)%s*$") or ""
	if param == "" then
		-- Argument-free form: show the current list (PROPOSED).
		local list = smp_social.get_social(name)[list_key]
		if #list == 0 then
			return smp_social.say(name, key == "ignored"
				and S("You are not ignoring anyone")
				or S("You are not blocking anyone"))
		end
		local sorted = {}
		for _, v in ipairs(list) do sorted[#sorted + 1] = v end
		table.sort(sorted)
		return smp_social.say(name,
			S("@1 (@2): @3", key == "ignored" and S("Ignored")
				or S("Blocked"), #sorted, table.concat(sorted, ", ")))
	end
	if param:lower() == name:lower() then
		return smp_social.say(name, key == "ignored"
			and S("You cannot ignore yourself")
			or S("You cannot block yourself"))
	end
	if not player_exists(param) then
		return smp_social.say(name, S("Player @1 does not exist", param))
	end
	local adding = false
	smp_social.mutate_social(name, function(soc)
		if smp_social.list_has(soc[list_key], param) then
			-- remove
			for i = #soc[list_key], 1, -1 do
				if tostring(soc[list_key][i]):lower() == param:lower() then
					table.remove(soc[list_key], i)
				end
			end
		else
			soc[list_key][#soc[list_key] + 1] = param
			adding = true
		end
	end)
	if adding then
		return smp_social.say(name, key == "ignored"
			and S("You are now ignoring @1", param)
			or S("You are now blocking @1", param))
	end
	return smp_social.say(name, key == "ignored"
		and S("You are no longer ignoring @1", param)
		or S("You are no longer blocking @1", param))
end

smp_social.register_cmd("ignore", {
	params = USAGE,
	description = S("Ignore a player: hides their chat and refuses their messages and teleport requests"),
	func = function(name, param)
		return toggle(name, param, "ignored", "ignored")
	end,
})

smp_social.register_cmd("block", {
	params = USAGE,
	description = S("Block a player: ignore plus payments, follows and queue pairing"),
	func = function(name, param)
		return toggle(name, param, "blocked", "blocked")
	end,
})

return true
