-- FriedcakeSMP — smp_social utility commands (f11 §2)
--
-- /ping   latency from core.get_player_information().avg_rtt (the API
--         example in Luanti's lua_api.md is in seconds; convert to ms)
-- /list   online players (overrides Mineclonia's mcl_commands /list)
-- /report send a report to online staff (CLONE [C1])
-- /helpop send a message to online staff (alias /ac, CLONE [C1])
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

----------------------------------------------------------------------
-- /ping
----------------------------------------------------------------------

smp_social.register_cmd("ping", {
	params = "",
	description = S("Show your connection latency"),
	func = function(name, _param)
		local info = core.get_player_information
			and core.get_player_information(name) or nil
		local rtt = info and info.avg_rtt
		if type(rtt) ~= "number" or rtt < 0 then
			-- PROPOSED wording; stats can be missing right after join.
			return smp_social.say(name, S("Ping is not available yet"))
		end
		return smp_social.say(name,
			S("Ping: @1 ms", math.floor(rtt * 1000 + 0.5)))
	end,
})

----------------------------------------------------------------------
-- /list  (/who, /online)
----------------------------------------------------------------------

local function list_online(name)
	local names = {}
	for _, p in ipairs(core.get_connected_players()) do
		names[#names + 1] = p:get_player_name()
	end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	return smp_social.say(name,
		S("Players online (@1): @2", #names, table.concat(names, ", ")))
end

smp_social.register_cmd("list", {
	params = "",
	description = S("List the online players"),
	func = list_online,
}, { "who", "online" })

----------------------------------------------------------------------
-- Staff contact
----------------------------------------------------------------------

local function is_staff(name)
	if not core.check_player_privs then return false end
	return core.check_player_privs(name, { smp_admin = true })
		or core.check_player_privs(name, { smp_moderator = true })
end

local function notify_staff(reporter, line)
	core.log("action", line)
	local sent = false
	for _, p in ipairs(core.get_connected_players()) do
		local staff = p:get_player_name()
		if staff ~= reporter and is_staff(staff) then
			core.chat_send_player(staff, line)
			sent = true
		end
	end
	-- Always confirm to the reporter (PROPOSED wording); if no staff is
	-- online the line is still logged for the audit trail.
	smp_social.say(reporter, S("Your report was sent to staff"))
	return sent
end

smp_social.register_cmd("report", {
	params = S("<player> <reason>"),
	description = S("Report a player to the staff"),
	func = function(name, param)
		local target, reason = (param or ""):match("^(%S+)%s+(.+)$")
		if not target then return false end
		notify_staff(name, S("@1 reported @2: @3", name, target, reason))
		return true
	end,
})

smp_social.register_cmd("helpop", {
	params = S("<message>"),
	description = S("Send a message to the staff"),
	func = function(name, param)
		param = (param or ""):match("^%s*(.-)%s*$") or ""
		if param == "" then return false end
		notify_staff(name, S("HelpOp from @1: @2", name, param))
		return true
	end,
}, { "ac" })

return true
