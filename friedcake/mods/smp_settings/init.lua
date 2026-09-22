-- FriedcakeSMP — smp_settings (spec: features/f12-settings.md)
--
-- Player settings: storage, the setting registry, the observed
-- /settings menus, and the canonical accessor other features call
-- (f01, f08, f10, f11, smp_orders). Storage and presentation only —
-- smp_settings enforces nothing (f12 §2); the consumer enforces.
--
--   smp_settings.get(player_or_name, id)  -> value | nil   (canonical)
--   smp_settings.set(player_or_name, id, value) -> bool
--
-- Layout (claim-f12, 8-step order): store -> accessor -> registry ->
-- the seven Chat settings -> category menu -> category screen ->
-- toggle handler -> /settings.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local MODNAME = core.get_current_modname() or "smp_settings"

smp_settings = {}
smp_settings.modname = MODNAME
smp_settings.S = core.get_translator(MODNAME)
local S = smp_settings.S

----------------------------------------------------------------------
-- Configuration (f12 §7). A comma-separated list setting, or `default`.
local function list_setting(key, default)
	local raw = core.settings:get(key)
	if type(raw) ~= "string" or raw == "" then return default end
	local out = {}
	for token in raw:gmatch("[^,]+") do
		token = token:match("^%s*(.-)%s*$")
		if token ~= "" then out[#out + 1] = token end
	end
	if #out == 0 then return default end
	return out
end

smp_settings.cfg = {
	-- §7 `settings.cycle_order` (PROPOSED, V-29):
	-- ON -> FRIENDS_FOLLOWED -> OFF. Tri-state settings cycle in this
	-- order; binary settings are fixed ON -> OFF (§5.1).
	cycle_order = list_setting("settings.cycle_order",
		{ "ON", "FRIENDS_FOLLOWED", "OFF" }),
}

-- The one genericised string (f12 §4.4): the subtitle reads
-- `Choose a category to change your <name> settings`. Config key
-- `server.name`, default `Donut SMP` (§7 default, OBSERVED [F0236]).
-- Note: the engine's own key is `server_name` — deliberately not
-- aliased (§10 F12-D).
function smp_settings.server_name()
	local raw = core.settings:get("server.name")
	if type(raw) == "string" then
		raw = raw:match("^%s*(.-)%s*$")
		if raw ~= "" then return raw end
	end
	return "Donut SMP"
end

----------------------------------------------------------------------
-- Submodules (same load pattern as smp_orders).
local MP = core.get_modpath(MODNAME)
local files = {
	"registry.lua",
	"store.lua",
	"accessor.lua",
	"chat.lua",
	"formspec.lua",
}
for _, file in ipairs(files) do
	local chunk, err = loadfile(MP .. "/" .. file)
	if not chunk then
		error("[smp_settings] cannot load " .. file .. ": " .. tostring(err))
	end
	local ok, lerr = pcall(chunk)
	if not ok then
		error("[smp_settings] error in " .. file .. ": " .. tostring(lerr))
	end
end

local fs = smp_settings.fs

----------------------------------------------------------------------
-- The seven observed categories (f12 §3.1), in observed order. Only
-- Chat has settings today: the other six stay registered-but-empty —
-- f12 §5.1 forbids inventing rows before evidence lands (§10).
local CATEGORIES = {
	{ "notifications", "Notifications", 2 },
	{ "pvp", "PvP", 3 },
	{ "visuals", "Visuals", 4 },
	{ "privacy", "Privacy", 5 },
	{ "scoreboard", "Scoreboard", 6 },
	{ "general", "General", 7 },
}
for _, c in ipairs(CATEGORIES) do
	smp_settings.register_category(c[1], {
		title = S(c[2]),
		order = c[3],
	})
end

local fs = smp_settings.fs

----------------------------------------------------------------------
-- Presentation (f12 §4.2/§4.3): open a screen through an smp_core
-- menu session, so quitting the interface closes the session (§4.8).

function smp_settings.show_menu(player_or_name)
	local pname = smp_settings.player_name(player_or_name)
	if not pname or not core.get_player_by_name(pname) then return false end
	smp_core.open_session(pname, fs.FORMNAME.menu, {})
	smp_core.show_formspec(pname, fs.FORMNAME.menu, fs.menu())
	return true
end

function smp_settings.show_category(player_or_name, category_key)
	if not smp_settings.categories[category_key] then return false end
	local pname = smp_settings.player_name(player_or_name)
	if not pname or not core.get_player_by_name(pname) then return false end
	local session = smp_core.open_session(pname, fs.FORMNAME.category, {})
	session.category = category_key
	smp_core.show_formspec(pname, fs.FORMNAME.category,
		fs.category(category_key, pname))
	return true
end

----------------------------------------------------------------------
-- Toggle (f12 §6): registry lookup and the store write happen in one
-- uninterrupted callback — no yields between validate and mutate
-- (shared §2.3) — then the screen redraws in place (§4.5).

function smp_settings.next_value(id, current)
	local def = smp_settings.registered[id]
	if not def then return nil end
	local i = smp_settings.index_of(def.values, current) or 0
	return def.values[(i % #def.values) + 1]
end

function smp_settings.on_toggle(player, id)
	local def = smp_settings.registered[id]
	if not def then return false end -- untrusted id: ignored (T8)
	local nxt = smp_settings.next_value(id, smp_settings.get(player, id))
	if not nxt then return false end
	if not smp_settings.set(player, id, nxt) then return false end
	smp_settings.show_category(player, def.category)
	return true
end

----------------------------------------------------------------------
-- Field handlers (f12 §4.5, §4.8). Every received field is untrusted:
-- the id must resolve through the registry (§8), and a click outside
-- an open session is ignored.

function smp_settings.menu_fields(player, fields)
	local pname = smp_settings.player_name(player)
	if not pname then return end
	if not smp_core.get_session(pname, fs.FORMNAME.menu) then return end
	if fields.quit then
		smp_core.close_session(pname, fs.FORMNAME.menu)
		return
	end
	for k in pairs(fields) do
		local key = type(k) == "string" and k:match("^cat_([%w_]+)$") or nil
		if key then
			if smp_settings.categories[key] then
				smp_core.close_session(pname, fs.FORMNAME.menu)
				smp_settings.show_category(player, key)
			end
			return
		end
	end
end

function smp_settings.category_fields(player, fields)
	local pname = smp_settings.player_name(player)
	if not pname then return end
	if not smp_core.get_session(pname, fs.FORMNAME.category) then return end
	if fields.quit then
		smp_core.close_session(pname, fs.FORMNAME.category)
		return
	end
	if fields.back then
		smp_core.close_session(pname, fs.FORMNAME.category)
		smp_settings.show_menu(player)
		return
	end
	for k in pairs(fields) do
		local id = type(k) == "string" and k:match("^toggle_(.+)$") or nil
		if id then
			smp_settings.on_toggle(player, id) -- unknown ids ignored (T8)
			return
		end
	end
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if type(formname) ~= "string" or type(fields) ~= "table" then return end
	if formname == fs.FORMNAME.menu then
		smp_settings.menu_fields(player, fields)
	elseif formname == fs.FORMNAME.category then
		smp_settings.category_fields(player, fields)
	end
end)

core.register_on_leaveplayer(function(player, _)
	local pname = smp_settings.player_name(player)
	if not pname then return end
	smp_core.close_session(pname, fs.FORMNAME.menu)
	smp_core.close_session(pname, fs.FORMNAME.category)
end)

----------------------------------------------------------------------
-- /settings (f12 §4.7). House-style description (PROPOSED, §10); the
-- observed entry point was a menu button [F0234], command form
-- declared by f12 §4.7.

core.register_chatcommand("settings", {
	params = "",
	description = S("Open the settings menu."),
	func = function(pname, _)
		smp_settings.show_menu(pname)
		return true
	end,
})

----------------------------------------------------------------------
local ncat, nset = 0, 0
for _ in pairs(smp_settings.categories) do ncat = ncat + 1 end
for _ in pairs(smp_settings.registered) do nset = nset + 1 end
core.log("action", "[smp_settings] loaded: /settings — "
	.. ncat .. " categories, " .. nset .. " settings")
