-- FriedcakeSMP — smp_tp formspecs (f08 §3.2, §8)
--
-- The Accept/Deny dialog is a PROMPT menu (shared/04-ui-kit.md §4.1):
-- formspec_version[6], bgcolor[#000000C0], two coloured buttons —
-- Deny red on the left, Accept green on the right (the observed
-- Cancel/Search colour convention, §4.6).
--
-- All state is server-side in an smp_core session; client fields are
-- untrusted and every action is re-validated (R4).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_tp.S

smp_tp.fs = {}

local FORMNAME = "smp_tp:request"

-- U+26A0 warning triangle, as homes.lua renders it (the correct three-byte
-- UTF-8 sequence, not the lone \241 byte the old label carried).
local TRIANGLE = "\226\154\160"

local function E(s)
	s = tostring(s)
	if core.formspec_escape then return core.formspec_escape(s) end
	return (s:gsub("[\\%[%];,]", "\\%0"))
end

function smp_tp.show_request_dialog(target, sender, type)
	local session = smp_core.open_session(target, FORMNAME, {
		sender = sender,
		type = type,
	})
	local line
	if type == "tpa" then
		line = S("@1 wants to teleport to you.", sender)
	else
		line = S("@1 wants you to teleport to them.", sender)
	end
	-- formspec_version 6 labels are placed by their vertical centre; the
	-- request line is an area label so long player names wrap instead of
	-- running off the dialog.
	local fs = table.concat({
		"formspec_version[6]",
		"size[8,3.2]",
		"bgcolor[#000000C0]",
		"label[2.65,0.45;" .. E(S("Teleport Request")) .. " " .. TRIANGLE .. "]",
		"label[0.4,0.9;7.2,1;" .. E(line) .. "]",
		"style[deny;bgcolor=red]",
		"style[accept;bgcolor=green]",
		"button[0.4,2.1;3.4,0.8;deny;" .. E(S("Deny")) .. "]",
		"button[4.2,2.1;3.4,0.8;accept;" .. E(S("Accept")) .. "]",
	})
	smp_core.show_formspec(target, FORMNAME, fs)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORMNAME then return end
	local name = player:get_player_name()
	smp_core.handle_fields(name, FORMNAME, fields, function(s, f)
		-- Re-validate: the request may have expired or been cancelled
		-- while the dialog was open.
		local st = smp_tp.get_state(name)
		local types = st.requests_in[s.sender]
		local live = types and types[s.type]
		if f.accept then
			if live then
				smp_tp.accept_request(name, s.sender, s.type)
			else
				core.chat_send_player(name,
					S("You have no such teleport request from @1", s.sender))
			end
			return "close"
		end
		if f.deny then
			if live then
				smp_tp.deny_request(name, s.sender, s.type)
			end
			return "close"
		end
		-- Any other field (a stray click): close, keep the request.
		return "close"
	end)
end)

----------------------------------------------------------------------
-- /spawn lobby menu (f08 §4.5.1) — a prompt menu of named lobbies.
----------------------------------------------------------------------

local LOBBY_FORMNAME = "smp_tp:spawn"

function smp_tp.show_spawn_menu(name)
	local lobbies = smp_tp.cfg.lobbies
	-- "main" always exists (the world spawn).
	local n = 0
	for _ in pairs(lobbies) do n = n + 1 end
	-- main first (world spawn), then configured lobbies in a stable order.
	local rows = { { id = "main", label = S("Main") } }
	local ids = {}
	for id in pairs(lobbies) do
		if id ~= "main" then ids[#ids + 1] = id end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		rows[#rows + 1] = { id = id, label = id:sub(1, 1):upper() .. id:sub(2) }
	end
	-- The dialog grows with the lobby list so every button stays inside it.
	local fs = {
		"formspec_version[6]",
		string.format("size[4,%s]", 0.8 + #rows * 0.9 + 0.1),
		"bgcolor[#000000C0]",
		"label[1.4,0.45;" .. E(S("Spawn")) .. "]",
	}
	local y = 0.8
	for _, row in ipairs(rows) do
		fs[#fs + 1] = string.format("button[0.2,%s;3.6,0.8;lobby_%s;%s]", y,
			row.id, E(row.label))
		y = y + 0.9
	end
	local session = smp_core.open_session(name, LOBBY_FORMNAME, {})
	smp_core.show_formspec(name, LOBBY_FORMNAME, table.concat(fs))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= LOBBY_FORMNAME then return end
	local name = player:get_player_name()
	smp_core.handle_fields(name, LOBBY_FORMNAME, fields, function(_, f)
		for field in pairs(f) do
			-- Field names are lobby_<id>; no pattern matching (this
			-- engine's pattern matcher is unreliable — see f08 §10).
			if type(field) == "string" and field:sub(1, 6) == "lobby_" then
				local id = field:sub(7)
				if id ~= "" then
					smp_tp.go_to_lobby(name, id)
					return "close"
				end
			end
		end
		return "close"
	end)
end)

return smp_tp
