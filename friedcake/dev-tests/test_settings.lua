-- dev-tests/test_settings.lua — headless test for smp_settings (f12).
--
-- Runs under plain luajit, no engine: loads smp_core + smp_settings
-- over a minimal `core` stub, then walks f12 §9 T1–T8 through the real
-- receive-fields path (T9 is f11's stranger-/msg test, not ours — the
-- f12 T9 leg lives in dev-tests/test_social.lua's T3 block, F12-4).
--   T1 seven categories in observed order (menu buttons)
--   T2 per-category tooltip `Open <Category> settings`
--   T3 subtitle `Choose a category to change your <server.name> settings`
--   T4 Settings - Chat: seven observed toggles in order, then Back;
--      unopened categories render empty
--   T5 toggle cycles and redraws in place (session survives)
--   T6 cycle order + wrap-around (binary and tri-state)
--   T7 persistence across restart + unknown keys preserved on write
--   T8 forged field names ignored (no write, no redraw)
--
-- Usage:  luajit friedcake/dev-tests/test_settings.lua

local passed, failed = 0, 0
local function ok(cond, msg)
	if cond then
		passed = passed + 1
		print("ok   " .. msg)
	else
		failed = failed + 1
		print("FAIL " .. msg)
	end
	return cond
end
local function eq(got, want, msg)
	return ok(got == want, msg .. " (got " .. tostring(got)
		.. ", want " .. tostring(want) .. ")")
end

-- Locate the repo root from the script path (works from any cwd).
local source = arg and arg[0] or ""
local ROOT = source:match("^(.*)/friedcake/dev%-tests/") or "."

----------------------------------------------------------------------
-- JSON codec: enough for Lua <-> engine JSON (objects, arrays, scalars).
local json_escape_map = {
	['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b",
	["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}
local function json_enc(v)
	local t = type(v)
	if v == nil then return "null" end
	if t == "string" then
		return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
			return json_escape_map[c] or string.format("\\u%04x", c:byte())
		end) .. '"'
	end
	if t == "number" or t == "boolean" then return tostring(v) end
	if t == "table" then
		local n, is_array = 0, true
		for k in pairs(v) do
			n = n + 1
			if type(k) ~= "number" then is_array = false end
		end
		if is_array and n == #v then
			local out = {}
			for i = 1, n do out[i] = json_enc(v[i]) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local out = {}
		for k, val in pairs(v) do
			out[#out + 1] = json_enc(tostring(k)) .. ":" .. json_enc(val)
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

local function json_dec(s)
	if type(s) ~= "string" then return nil end
	local i, n = 1, #s
	local function skip()
		while i <= n and s:sub(i, i):match("%s") do i = i + 1 end
	end
	local function parse_value()
		skip()
		local c = s:sub(i, i)
		if c == "{" then
			i = i + 1
			local out = {}
			skip()
			if s:sub(i, i) == "}" then i = i + 1 return out end
			while true do
				skip()
				local k = parse_value()
				skip()
				if s:sub(i, i) ~= ":" then return nil end
				i = i + 1
				local v = parse_value()
				if k == nil or v == nil then return nil end
				out[k] = v
				skip()
				local d = s:sub(i, i)
				i = i + 1
				if d == "}" then return out end
				if d ~= "," then return nil end
			end
		elseif c == "[" then
			i = i + 1
			local out = {}
			skip()
			if s:sub(i, i) == "]" then i = i + 1 return out end
			while true do
				local v = parse_value()
				if v == nil and s:sub(i, i) ~= "n" then return nil end
				out[#out + 1] = v
				skip()
				local d = s:sub(i, i)
				i = i + 1
				if d == "]" then return out end
				if d ~= "," then return nil end
			end
		elseif c == '"' then
			i = i + 1
			local buf = {}
			while i <= n do
				local ch = s:sub(i, i)
				if ch == '"' then i = i + 1 return table.concat(buf) end
				if ch == "\\" then
					local e = s:sub(i + 1, i + 1)
					local map = { n = "\n", t = "\t", r = "\r", b = "\b",
						f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
					if map[e] then
						buf[#buf + 1] = map[e]
						i = i + 2
					elseif e == "u" then
						local hex = s:sub(i + 2, i + 5)
						local code = tonumber(hex, 16) or 63
						buf[#buf + 1] = code < 128
							and string.char(code) or "?"
						i = i + 6
					else
						return nil
					end
				else
					buf[#buf + 1] = ch
					i = i + 1
				end
			end
			return nil
		elseif s:sub(i, i + 3) == "true" then i = i + 4 return true
		elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
		elseif s:sub(i, i + 3) == "null" then i = i + 4 return nil
		end
		local num = s:match("^-?%d+%.?%d*[eE]?[+%-]?%d*", i)
		if num and #num > 0 then
			local v = tonumber(num)
			if v then i = i + #num return v end
		end
		return nil
	end
	local v = parse_value()
	return v
end

----------------------------------------------------------------------
-- Minimal engine stub.
local modname = nil
local field_handlers, leave_handlers, commands = {}, {}, {}
local shown, chats = {}, {}
local players = {}

local S_factory = function()
	return function(s, ...)
		local args = { ... }
		return (s:gsub("@(%d+)", function(d)
			return tostring(args[tonumber(d)] or "")
		end))
	end
end

core = {
	get_current_modname = function() return modname end,
	get_translator = function(_) return S_factory() end,
	get_modpath = function(m) return ROOT .. "/friedcake/mods/" .. m end,
	log = function() end,
	write_json = json_enc,
	parse_json = json_dec,
	settings = {
		get = function(_, k)
			local known = { ["server.name"] = "TestSMP" }
			return known[k]
		end,
		get_bool = function() return nil end,
	},
	formspec_escape = function(s)
		return (tostring(s):gsub('[%\\%\n]', "\\%0"))
	end,
	show_formspec = function(pname, formname, spec)
		shown[pname] = { formname = formname, spec = spec }
	end,
	close_formspec = function(pname, _)
		shown[pname] = nil
	end,
	get_player_by_name = function(n) return players[n] end,
	register_chatcommand = function(name, def)
		commands[name] = def
	end,
	registered_chatcommands = nil, -- patched after load
	register_on_player_receive_fields = function(fn)
		field_handlers[#field_handlers + 1] = fn
	end,
	register_on_leaveplayer = function(fn)
		leave_handlers[#leave_handlers + 1] = fn
	end,
	get_gametime = function() return 0 end,
	chat_send_player = function(pname, msg) chats[#chats + 1] = pname .. ":" .. msg end,
}
core.registered_chatcommands = commands

----------------------------------------------------------------------
-- Player stubs. `meta_store` is the world on disk: it survives an
-- engine restart (PlayerRefs do not, but their meta does).
local meta_store = {}
local function join(name)
	meta_store[name] = meta_store[name] or {}
	local data = meta_store[name]
	local p = {}
	function p:get_player_name() return name end
	function p:get_meta()
		return {
			get_string = function(_, k) return data[k] or "" end,
			set_string = function(_, k, v) data[k] = v end,
		}
	end
	players[name] = p
	return p
end

local function engine_restart()
	-- mods are unloaded; player meta survives on disk
	field_handlers, leave_handlers, commands = {}, {}, {}
	core.registered_chatcommands = commands
	shown, chats, players = {}, {}, {}
	if smp_core then smp_core._sessions = {} end
	smp_settings = nil
end

local function load_mod(name)
	modname = name
	local chunk, err = loadfile(ROOT .. "/friedcake/mods/" .. name .. "/init.lua")
	assert(chunk, "load " .. name .. ": " .. tostring(err))
	local ok, lerr = pcall(chunk)
	modname = nil
	assert(ok, "run " .. name .. ": " .. tostring(lerr))
end

load_mod("smp_core")
load_mod("smp_settings")

local FS_MENU = "smp_settings:menu"
local FS_CAT = "smp_settings:category"

local function send_fields(pname, fields)
	local f = shown[pname]
	if not ok(f ~= nil, "form is open for " .. pname) then return end
	for _, h in ipairs(field_handlers) do
		h(players[pname], f.formname, fields)
	end
end

local function spec_of(pname)
	return shown[pname] and shown[pname].spec or ""
end

local function meta_json(pname)
	return meta_store[pname] and meta_store[pname]["smp:settings"]
end

local function count(s, needle)
	local n = 0
	for _ in s:gmatch(needle) do n = n + 1 end
	return n
end

local alice = join("alice")

local CAT_KEYS = {
	"chat", "notifications", "pvp", "visuals",
	"privacy", "scoreboard", "general",
}
local CAT_TITLES = {
	"Chat", "Notifications", "PvP", "Visuals",
	"Privacy", "Scoreboard", "General",
}

----------------------------------------------------------------------
print("--- T1/T2/T3: category menu ---")
ok(smp_settings.show_menu(alice), "show_menu opens")
eq(shown.alice and shown.alice.formname, FS_MENU, "menu formname")

local menu = spec_of("alice")
local cats = smp_settings.ordered_categories()
eq(#cats, 7, "T1 seven categories registered")
for i, key in ipairs(CAT_KEYS) do
	eq(cats[i] and cats[i].key, key, "T1 category " .. i .. " key")
	eq(cats[i] and cats[i].title, CAT_TITLES[i], "T1 category " .. i .. " title")
end
eq(count(menu, ";cat_"), 7, "T1 exactly seven category buttons")
local prev = 0
for _, key in ipairs(CAT_KEYS) do
	local p = menu:find(";cat_" .. key .. ";", 1, true)
	ok(p ~= nil and p > prev, "T1 button cat_" .. key .. " in order")
	prev = p or 0
end

for i, key in ipairs(CAT_KEYS) do
	ok(menu:find("tooltip[cat_" .. key .. ";Open " .. CAT_TITLES[i]
		.. " settings]", 1, true) ~= nil, "T2 tooltip cat_" .. key)
end

local subtitle = "Choose a category to change your TestSMP settings"
ok(menu:find(subtitle, 1, true) ~= nil, "T3 subtitle rendered")
eq(smp_settings.S("Choose a category to change your @1 settings",
	smp_settings.server_name()), subtitle, "T3 subtitle verbatim")
eq(smp_settings.server_name(), "TestSMP", "T3 server.name read from config")

----------------------------------------------------------------------
print("--- T4: category screen ---")
send_fields("alice", { cat_chat = "true" })
eq(shown.alice.formname, FS_CAT, "navigated to category screen")
ok(smp_core.get_session("alice", FS_CAT) ~= nil, "category session open")
ok(smp_core.get_session("alice", FS_MENU) == nil, "menu session closed")

local screen = spec_of("alice")
ok(screen:find("Settings - Chat", 1, true) ~= nil, "T4 title Settings - Chat")
local ROWS = {
	"Public Chat: ON",
	"Private Messages: Friends/Followed",
	"Server Chat Messages: ON",
	"Server Hotbar Messages: ON",
	"Death Messages: Friends/Followed",
	"Advancement Messages: Friends/Followed",
	"Join/Leave Messages: Friends/Followed",
}
eq(count(screen, ";toggle_"), 7, "T4 seven toggle rows")
prev = 0
for _, row in ipairs(ROWS) do
	local p = screen:find(row, 1, true)
	ok(p ~= nil and p > prev, "T4 row `" .. row .. "` in order")
	prev = p or 0
end
local back = screen:find(";back;Back", 1, true)
ok(back ~= nil and back > prev, "T4 Back after the last toggle")
ok(not screen:find(";toggle_privacy", 1, true), "T4 no rows from other categories")

----------------------------------------------------------------------
-- F12-1: the yellow warning triangle sits right of the title on BOTH
-- prompt menus (f12 §3.1/§3.2; shared/04 §4.2, [F0236, F0242]).
-- Assert the exact three UTF-8 bytes of U+26A0 — never a truncated
-- single byte — inside the rendered title element of each screen.
----------------------------------------------------------------------
local TRIANGLE = "\226\154\160"
eq(#TRIANGLE, 3, "F12-1 triangle constant is the full 3-byte UTF-8 sequence")
eq(TRIANGLE:byte(1), 0xE2, "F12-1 U+26A0 byte 1 is 0xE2")
eq(TRIANGLE:byte(2), 0x9A, "F12-1 U+26A0 byte 2 is 0x9A")
eq(TRIANGLE:byte(3), 0xA0, "F12-1 U+26A0 byte 3 is 0xA0")
ok(menu:find("label[", 1, true) ~= nil
	and menu:find("Settings " .. TRIANGLE, 1, true) ~= nil,
	"F12-1 triangle element in the category-menu render (right of `Settings`)")
ok(screen:find("label[", 1, true) ~= nil
	and screen:find("Settings - Chat " .. TRIANGLE, 1, true) ~= nil,
	"F12-1 triangle element in the `Settings - Chat` render")
ok(menu:find("\241", 1, true) == nil and screen:find("\241", 1, true) == nil,
	"F12-1 no truncated lone 0xF1 byte in either render")

----------------------------------------------------------------------
print("--- T5: toggle cycles and redraws in place ---")
screen = spec_of("alice")
send_fields("alice", { ["toggle_chat.public"] = "true" })
local after = spec_of("alice")
ok(after ~= screen, "T5 screen redrawn")
ok(after:find("Public Chat: OFF", 1, true) ~= nil, "T5 value ON -> OFF")
ok(not after:find("Public Chat: ON", 1, true), "T5 old label gone")
eq(shown.alice.formname, FS_CAT, "T5 still on the category screen")
ok(smp_core.get_session("alice", FS_CAT) ~= nil, "T5 session survives")
ok(meta_json("alice"):find('"chat.public":"OFF"', 1, true) ~= nil,
	"T5 stored OFF")

----------------------------------------------------------------------
print("--- T6: cycle order and wrap-around ---")
local priv = { "chat.private_messages", "FRIENDS_FOLLOWED" }
eq(smp_settings.next_value("chat.public", "ON"), "OFF", "T6 binary ON -> OFF")
eq(smp_settings.next_value("chat.public", "OFF"), "ON", "T6 binary wraps")
eq(smp_settings.next_value(priv[1], priv[2]), "OFF",
	"T6 tri FRIENDS_FOLLOWED -> OFF")
eq(smp_settings.next_value(priv[1], "OFF"), "ON", "T6 tri OFF -> ON")
eq(smp_settings.next_value(priv[1], "ON"), "FRIENDS_FOLLOWED",
	"T6 tri wraps to FRIENDS_FOLLOWED")

-- drive it through the UI: start from FRIENDS_FOLLOWED (default)
screen = spec_of("alice")
ok(screen:find("Private Messages: Friends/Followed", 1, true) ~= nil,
	"T6 starts at Friends/Followed")
send_fields("alice", { ["toggle_chat.private_messages"] = "true" })
ok(spec_of("alice"):find("Private Messages: OFF", 1, true) ~= nil,
	"T6 UI click -> OFF")
send_fields("alice", { ["toggle_chat.private_messages"] = "true" })
ok(spec_of("alice"):find("Private Messages: ON", 1, true) ~= nil,
	"T6 UI click -> ON")
send_fields("alice", { ["toggle_chat.private_messages"] = "true" })
ok(spec_of("alice"):find("Private Messages: Friends/Followed", 1, true) ~= nil,
	"T6 UI click wraps back to Friends/Followed")

----------------------------------------------------------------------
print("--- T8: forged field names ---")
local before_spec = spec_of("alice")
local before_meta = meta_json("alice")
send_fields("alice", { ["toggle_made.up"] = "true" })
eq(spec_of("alice"), before_spec, "T8 forged id does not redraw")
eq(meta_json("alice"), before_meta, "T8 forged id does not write")
send_fields("alice", { ["toggle_chat.nope"] = "true" })
eq(meta_json("alice"), before_meta, "T8 forged chat.* id does not write")
eq(smp_settings.set("alice", "forged.id", "ON"), false,
	"T8 set() rejects unknown id")
eq(smp_settings.on_toggle(alice, "forged.id"), false,
	"T8 on_toggle() rejects unknown id")

----------------------------------------------------------------------
print("--- navigation: Back and quit (f12 §4.8) ---")
send_fields("alice", { back = "true" })
eq(shown.alice.formname, FS_MENU, "Back returns to the menu")
ok(smp_core.get_session("alice", FS_MENU) ~= nil, "menu session reopened")
ok(smp_core.get_session("alice", FS_CAT) == nil, "category session closed")

send_fields("alice", { cat_madeup = "true" })
eq(shown.alice.formname, FS_MENU, "forged category keeps the menu")
ok(smp_core.get_session("alice", FS_MENU) ~= nil,
	"forged category keeps the session")

send_fields("alice", { quit = true })
ok(smp_core.get_session("alice", FS_MENU) == nil, "quit closes the session")

local after_quit = meta_json("alice")
send_fields = function(pname, fields) -- no form open: must be ignored
	local f = shown[pname]
	if f == nil then return end
	for _, h in ipairs(field_handlers) do h(players[pname], f.formname, fields) end
end
shown["alice"] = { formname = FS_MENU, spec = "" } -- forged: no session
for _, h in ipairs(field_handlers) do
	h(alice, FS_MENU, { ["toggle_chat.public"] = "true" })
end
shown.alice = nil
eq(meta_json("alice"), after_quit, "fields without a session are ignored")

----------------------------------------------------------------------
print("--- unopened categories render empty (f12 §5.1) ---")
ok(smp_settings.show_menu(alice), "menu reopens")
send_fields("alice", { cat_notifications = "true" })
eq(shown.alice.formname, FS_CAT, "opened Notifications")
screen = spec_of("alice")
ok(screen:find("Settings - Notifications", 1, true) ~= nil,
	"empty category title")
eq(count(screen, ";toggle_"), 0, "empty category has no invented rows")
ok(screen:find(";back;Back", 1, true) ~= nil, "empty category has Back")

----------------------------------------------------------------------
print("--- T7: persistence and unknown-key preservation ---")
-- seed a key from a hypothetical newer build
local stored = core.parse_json(meta_json("alice"))
stored["future.brand_new"] = "keep-me"
meta_store.alice["smp:settings"] = core.write_json(stored)

engine_restart()
load_mod("smp_core")
load_mod("smp_settings")
alice = join("alice")

eq(smp_settings.get("alice", "chat.public"), "OFF",
	"T7 stored value survives restart")
local p = core.get_player_by_name("alice")
eq(smp_settings.get(p, "chat.private_messages"),
	smp_settings.get("alice", "chat.private_messages"),
	"T7 PlayerRef and name forms agree (f01/f11 contract)")

-- a post-restart write must not drop the unknown key
ok(smp_settings.set("alice", "chat.hotbar_messages", "OFF"),
	"T7 post-restart write succeeds")
stored = core.parse_json(meta_json("alice"))
eq(stored["future.brand_new"], "keep-me", "T7 unknown key preserved on write")
eq(stored["chat.hotbar_messages"], "OFF", "T7 new key written")
eq(stored["chat.public"], "OFF", "T7 other keys preserved")
eq(smp_settings.get("alice", "future.brand_new"), "keep-me",
	"T7 unknown key readable")

-- restart, reload, toggle once through the UI: write path still good
ok(smp_settings.show_menu(alice), "menu opens after restart")
send_fields("alice", { cat_chat = "true" })
send_fields("alice", { ["toggle_chat.public"] = "true" })
stored = core.parse_json(meta_json("alice"))
eq(stored["chat.public"], "ON", "T7 toggle after restart writes")
eq(stored["future.brand_new"], "keep-me",
	"T7 unknown key survives the post-restart toggle")

----------------------------------------------------------------------
print("--- offline players and consumer contract ---")
eq(smp_settings.get("nobody", "chat.public"), "ON",
	"offline read falls back to the default")
eq(smp_settings.set("nobody", "chat.public", "OFF"), false,
	"offline write refuses")
local good, v = pcall(smp_settings.get, "alice", "eco.order_alerts")
ok(good and v == nil, "unregistered id returns nil (smp_orders contract)")
eq(smp_settings.get("alice", "privacy.show_money"), nil,
	"unopened-category key not registered")
eq(smp_settings.get("alice", "tp.tpa_enabled"), nil,
	"unopened-category key not registered")
eq(smp_settings.get("alice", "combat.keep_pearls_on_death"), nil,
	"unopened-category key not registered")

----------------------------------------------------------------------
-- F12-5: /settings description is sentence case with no terminal full
-- stop (shared §0.5 rule 4 — house style for unobserved strings).
----------------------------------------------------------------------
print("--- F12-5: /settings description ---")
eq(core.registered_chatcommands.settings.description, "Open the settings menu",
	"F12-5 description is `Open the settings menu` (no terminal full stop)")

----------------------------------------------------------------------
print("== in-game test suite (mods/smp_settings/test.lua) ==")
do
	local chunk, lerr = loadfile(ROOT .. "/friedcake/mods/smp_settings/test.lua")
	ok(chunk ~= nil, "test.lua loads: " .. tostring(lerr))
	if chunk then
		local good2, res = pcall(chunk)
		ok(good2, "test.lua runs: " .. tostring(res))
		if good2 and type(res) == "table" then
			eq(res.failed, 0, "in-game suite has no failures ("
				.. tostring(res.passed) .. " passed)")
			for _, l in ipairs(res.lines or {}) do print("  " .. l) end
		end
	end
end

----------------------------------------------------------------------
print(string.format("passed=%d failed=%d", passed, failed))
if failed > 0 then
	print("TEST_SETTINGS FAILED")
	os.exit(1)
end
print("ALL OK")
