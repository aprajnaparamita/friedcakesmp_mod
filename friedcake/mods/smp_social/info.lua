-- FriedcakeSMP — smp_social informational commands (f11 §4.6)
--
-- /help, /rules, /discord, /media, /link, /buy, /website, /ranks,
-- /medal display configured text. Luanti cannot open URLs, so links go
-- into a read-only formspec field the player can copy from — a prompt
-- menu (shared §4.1) ending in `Back` (shared §4.5).
--
-- Text comes from the `info.*` configuration keys (PROPOSED, added to
-- f11 §7). /help falls back to a generated command list so it is never
-- empty; an unset link answers `This link is not configured`.
--
-- /help keeps the builtin behaviour for `/help <command>` — the
-- information screen only replaces the bare form.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

local FORMNAME = "smp_social:info"

local function get_info(key)
	local v = core.settings:get(key)
	if v == nil then return "" end
	return v
end

local function auto_help()
	local names = {}
	for cname in pairs(core.registered_chatcommands) do
		names[#names + 1] = cname
	end
	table.sort(names)
	local lines = {}
	for _, cname in ipairs(names) do
		local d = core.registered_chatcommands[cname]
		local line = "/" .. cname
		if d.params and d.params ~= "" then line = line .. " " .. d.params end
		if d.description and d.description ~= "" then
			line = line .. " - " .. d.description
		end
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

local function show_formspec(name, title, content)
	smp_core.open_session(name, FORMNAME, { title = title })
	core.show_formspec(name, FORMNAME, table.concat({
		"formspec_version[6]",
		"size[9,7]",
		"bgcolor[#000000C0]",
		"label[0.5,0.6;" .. core.formspec_escape(title) .. "]",
		"textarea[0.5,1.4;8,4.6;info_text;;"
			.. core.formspec_escape(content) .. "]",
		"button[3.7,6.1;1.6,0.8;info_back;" .. S("Back") .. "]",
	}, ""))
end

-- key: config key; title: screen title; link: link-not-configured
-- wording (otherwise text-not-configured).
local function register_info(name, def, aliases)
	local func = function(pname, _param)
		local content = get_info(def.key)
		if content == "" then
			-- PROPOSED fallback wording (§10).
			return smp_social.say(pname, def.link
				and S("This link is not configured")
				or  S("This text is not configured"))
		end
		show_formspec(pname, def.title, content)
		return true
	end
	smp_social.register_cmd(name, {
		params = "",
		description = def.description,
		func = func,
	}, aliases)
end

local function info_back_handler()
	core.register_on_player_receive_fields(function(player, formname, fields)
		if formname ~= FORMNAME then return nil end
		local name = player:get_player_name()
		return smp_core.handle_fields(name, formname, fields, function(_s, f)
			if f.quit or f.info_back then return "close" end
			return "stay"
		end)
	end)
end

----------------------------------------------------------------------
-- /help — information screen, with builtin `/help <command>` retained
----------------------------------------------------------------------

local builtin_help = core.registered_chatcommands["help"]
local builtin_help_func = builtin_help and builtin_help.func or nil

smp_social.register_cmd("help", {
	params = S("[<command>]"),
	description = S("Show the server's command list, or help for one command"),
	func = function(name, param)
		param = (param or ""):match("^%s*(.-)%s*$") or ""
		if param ~= "" then
			if builtin_help_func then
				return builtin_help_func(name, param)
			end
			local d = core.registered_chatcommands[param]
			if d then
				local line = "/" .. param
				if d.params ~= "" then line = line .. " " .. d.params end
				if d.description ~= "" then
					line = line .. ": " .. d.description
				end
				return smp_social.say(name, line)
			end
			return smp_social.say(name, S("This command does not exist"))
		end
		show_formspec(name, S("Help"),
			get_info("info.help") ~= "" and get_info("info.help") or auto_help())
		return true
	end,
})

----------------------------------------------------------------------
-- The rest
----------------------------------------------------------------------

register_info("rules", {
	key = "info.rules",
	title = S("Rules"),
	description = S("Show the server rules"),
})

register_info("discord", {
	key = "info.discord", title = S("Discord"), link = true,
	description = S("Show the server's Discord link"),
})

register_info("media", {
	key = "info.media", title = S("Media"), link = true,
	description = S("Show the server's media link"),
})

register_info("link", {
	key = "info.link", title = S("Link"), link = true,
	description = S("Show the server's main link"),
})

register_info("buy", {
	key = "info.store", title = S("Store"), link = true,
	description = S("Show the server's store link"),
}, { "store" })

register_info("website", {
	key = "info.website", title = S("Website"), link = true,
	description = S("Show the server's website"),
})

-- /ranks is listed in both f11 §2 and f13 §2. Respect f13 if it has
-- already registered its perk-table screen (§10).
if not core.registered_chatcommands["ranks"] then
	register_info("ranks", {
		key = "info.ranks", title = S("Ranks"),
		description = S("Show information about the server ranks"),
	})
end

register_info("medal", {
	key = "info.medal", title = S("Medal"), link = true,
	description = S("Show the server's MedalTV link"),
})

info_back_handler()

return true
