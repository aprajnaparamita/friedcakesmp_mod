-- FriedcakeSMP dev smoke test: smp_social (f11)
--
-- Covers the parts of spec/features/f11-social.md §9 that are testable
-- without a live server:
--   T1  public chat renders exactly `<Name> message`, no prefix
--   T2  Public Chat: OFF receives no public lines; everyone else does
--   T3  /msg to a FRIENDS_FOLLOWED stranger: verbatim refusal, nothing delivered
--   T4  /msg to a friend of a FRIENDS_FOLLOWED recipient is delivered
--   T5  /msg to someone who ignored you returns the SAME refusal
--   T6  /ignore suppresses public chat, private messages and (via
--       smp_social.blocks, the hook f08 gates /tpa on) teleport requests
--   T7  a public message is followed by the teleport hint naming the sender
--   T8  an unknown command answers `This command does not exist`
--   T9  /findplayer never returns exact coordinates
--   T10 mutual follows are friends both ways; a one-way follow is not
--
-- Plus the surrounding behaviour: anti-spam and duplicate filter, the
-- /msg /r alias family, OFF refusal, join/leave notices, /kill confirm,
-- /nightvision persistence, info screens, /ping /list /report /helpop,
-- the f12 settings bridge (both assumed contract shapes) and the
-- follow limit.
--
-- The builtin chat pipeline (command dispatch, on_chatcommand
-- callbacks, default broadcast) is reproduced faithfully from
-- builtin/game/chat.lua so the unknown-command override is exercised
-- the way the engine runs it.
--
-- Run: luajit friedcake/dev-tests/test_social.lua
-- Exits non-zero on any failure (tools/agent-flow.sh test).

----------------------------------------------------------------------
-- Repository root (works from a worktree checkout too)
----------------------------------------------------------------------

local function find_root()
	local script = (arg and arg[0]) or ""
	local prefix = script:match("^(.-)friedcake/dev%-tests/[^/]*$")
	if prefix and prefix ~= "" then
		return (prefix:gsub("/+$", ""))
	end
	local probe = io.open("friedcake/modpack.conf", "r")
	if probe then
		probe:close()
		return "."
	end
	return "/Volumes/Dara/dev/coconut"
end

local ROOT = find_root()

local passed, failed = 0, 0
local function ok(cond, msg)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. tostring(msg))
	end
end
local function eq(a, b, msg)
	if a == b then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("FAIL: %s — expected %q got %q",
			tostring(msg), tostring(b), tostring(a)))
	end
end

----------------------------------------------------------------------
-- Minimal JSON codec (same shape as test_economy.lua / test_orders.lua)
----------------------------------------------------------------------

local function json_encode(v)
	local t = type(v)
	if t == "nil"     then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number"  then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if v == math.floor(v) then return string.format("%.0f", v) end
		return tostring(v)
	end
	if t == "string"  then
		return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
	end
	if t == "table" then
		local n = 0
		for k in pairs(v) do
			if type(k) ~= "number" then n = -1 break end
			if k > n then n = k end
		end
		if n == -1 then
			local p = {}
			for k, vv in pairs(v) do
				p[#p + 1] = string.format('"%s":%s', tostring(k), json_encode(vv))
			end
			return "{" .. table.concat(p, ",") .. "}"
		else
			local p = {}
			for i = 1, n do p[i] = json_encode(v[i]) end
			return "[" .. table.concat(p, ",") .. "]"
		end
	end
	return "null"
end

local function skip_ws(s, i)
	while i <= #s do
		local c = s:sub(i, i)
		if c == ' ' or c == '\t' or c == '\n' or c == '\r' then i = i + 1
		else break end
	end
	return i
end

local function parse_str(s, i)
	local out, j = "", i + 1
	while j <= #s do
		local c = s:sub(j, j)
		if c == '"' then return out, j + 1 end
		if c == '\\' then
			local nc = s:sub(j + 1, j + 1)
			if     nc == '"' then out = out .. '"'
			elseif nc == '\\' then out = out .. '\\'
			elseif nc == '/' then out = out .. '/'
			elseif nc == 'n' then out = out .. '\n'
			elseif nc == 't' then out = out .. '\t'
			elseif nc == 'r' then out = out .. '\r'
			elseif nc == 'b' then out = out .. '\b'
			elseif nc == 'f' then out = out .. '\f'
			else out = out .. nc end
			j = j + 2
		else
			out = out .. c
			j = j + 1
		end
	end
	error("unterminated string")
end

local parse_val
local function parse_obj(s, i)
	local t = {}
	i = i + 1
	while true do
		i = skip_ws(s, i)
		if i > #s then break end
		if s:sub(i, i) == '}' then return t, i + 1 end
		local k
		k, i = parse_str(s, i)
		i = skip_ws(s, i)
		i = skip_ws(s, i + 1) -- ':'
		local v
		v, i = parse_val(s, i)
		t[k] = v
		i = skip_ws(s, i)
		if s:sub(i, i) == ',' then i = i + 1 end
	end
	error("unterminated object")
end

local function parse_arr(s, i)
	local t, idx = {}, 1
	i = i + 1
	while true do
		i = skip_ws(s, i)
		if i > #s then break end
		if s:sub(i, i) == ']' then return t, i + 1 end
		local v
		v, i = parse_val(s, i)
		t[idx] = v
		idx = idx + 1
		i = skip_ws(s, i)
		if s:sub(i, i) == ',' then i = i + 1 end
	end
	error("unterminated array")
end

function parse_val(s, i)
	i = skip_ws(s, i)
	local c = s:sub(i, i)
	if c == '"' then return parse_str(s, i) end
	if c == '{' then return parse_obj(s, i) end
	if c == '[' then return parse_arr(s, i) end
	local j = i
	while j <= #s and s:sub(j, j):match('[^%s,}%]%)]') do j = j + 1 end
	local tok = s:sub(i, j - 1)
	if tok == "true" then return true, j end
	if tok == "false" then return false, j end
	if tok == "null" then return nil, j end
	return tonumber(tok), j
end

local function json_decode(s)
	if not s or s == "" then return nil end
	local v = parse_val(s, 1)
	return v
end

local function ser_value(v)
	local t = type(v)
	if t == "number" then
		if v == math.floor(v) then return string.format("%.0f", v) end
		return string.format("%.17g", v)
	elseif t == "boolean" then return tostring(v)
	elseif t == "string" then return string.format("%q", v)
	elseif t == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local parts = {}
		for _, k in ipairs(keys) do
			parts[#parts + 1] = "[" .. ser_value(k) .. "]=" .. ser_value(v[k])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "nil"
end

----------------------------------------------------------------------
-- Fake world
----------------------------------------------------------------------

local store_data = {}
local commands = {}            -- core.registered_chatcommands
local fake = {
	chat = {},                  -- [name] = { line, ... }
	forms = {},                 -- [name] = { formname, spec }
	players = {},               -- name -> player object (online)
	auth = {},                  -- names that exist (online or former)
	gametime = 1000,
	on_chat = {},               -- registered_on_chat_message callbacks
	on_cmd = {},                -- registered_on_chatcommand callbacks
	on_join = {}, on_leave = {}, on_respawn = {},
	on_fields = {}, on_mods_loaded = {}, on_shutdown = {}, on_globalstep = {},
	settings_values = { ["store.backend"] = "mod_storage" },
	settings_bool = {},
	privs = {},                 -- [name] = { priv = true }
	info = {},                  -- [name] = { avg_rtt = ... }
	nv_give = {}, nv_clear = {},
}

local function advance(n)
	fake.gametime = fake.gametime + (n or 1)
end

local function chat_to(name, msg)
	fake.chat[name] = fake.chat[name] or {}
	fake.chat[name][#fake.chat[name] + 1] = msg
end

local function chat_log(name) return fake.chat[name] or {} end
local function last_chat(name)
	local l = chat_log(name)
	return l[#l]
end
local function chat_contains(name, s)
	for _, l in ipairs(chat_log(name)) do
		if l:find(s, 1, true) then return true end
	end
	return false
end
local function chat_index_of(name, s)
	for i, l in ipairs(chat_log(name)) do
		if l:find(s, 1, true) then return i end
	end
	return nil
end
local function count_chat(name, s)
	local n = 0
	for _, l in ipairs(chat_log(name)) do
		if l:find(s, 1, true) then n = n + 1 end
	end
	return n
end
local function any_chat_contains(s)
	for name in pairs(fake.chat) do
		if chat_contains(name, s) then return true end
	end
	return false
end
local function reset_chat() fake.chat = {} end
local function reset_forms() fake.forms = {} end

local function make_player(name, pos)
	fake.auth[name] = true
	local ints, strs = {}, {}
	local p = { _name = name, _hp = 20, _pos = pos or { x = 0, y = 64, z = 0 } }
	function p:get_player_name() return self._name end
	function p:get_pos() return self._pos end
	function p:set_pos(v) self._pos = v end
	function p:get_hp() return self._hp end
	function p:set_hp(h) self._hp = h end
	function p:is_player() return true end
	function p:get_meta()
		return {
			get_int = function(_, k) return ints[k] or 0 end,
			set_int = function(_, k, v) ints[k] = v end,
			get_string = function(_, k) return strs[k] or "" end,
			set_string = function(_, k, v) strs[k] = v end,
		}
	end
	fake.players[name] = p
	return p
end

local function granted_privs(name)
	local g = fake.privs[name]
	if not g then g = { shout = true, interact = true } end
	return g
end

----------------------------------------------------------------------
-- core stub (engine semantics mirrored from builtin/game/chat.lua)
----------------------------------------------------------------------

local function check_player_privs(name, privs)
	local g = granted_privs(name)
	local missing = {}
	for k in pairs(privs or {}) do
		if not g[k] then missing[k] = true end
	end
	if next(missing) then return false, missing end
	return true, {}
end

core = {
	DIR_DELIM = "/",
	get_mod_storage = function()
		return {
			get_string = function(_, k) return store_data[k] or "" end,
			set_string = function(_, k, v) store_data[k] = v end,
			get_keys = function(_)
				local out = {}
				for k in pairs(store_data) do out[#out + 1] = k end
				return out
			end,
		}
	end,
	write_json = json_encode,
	parse_json = json_decode,
	serialize = ser_value,
	deserialize = function(s)
		if type(s) ~= "string" or s == "" then return nil end
		local f = loadstring("return " .. s)
		if not f then return nil end
		local good, val = pcall(f)
		return good and val or nil
	end,
	get_translator = function(_)
		return function(s, ...)
			local args = { ... }
			return (s:gsub("@(%d+)", function(n)
				return tostring(args[tonumber(n)] or "")
			end))
		end
	end,
	get_current_modname = function() return _G.__current_modname or "smp_social" end,
	get_modpath = function(m) return ROOT .. "/friedcake/mods/" .. m end,
	log = function(level, msg)
		if level == "error" then print("[engine error] " .. tostring(msg)) end
	end,
	chat_send_player = chat_to,
	chat_send_all = function(msg)
		for name in pairs(fake.players) do chat_to(name, msg) end
	end,
	show_formspec = function(name, formname, spec)
		fake.forms[name] = { formname = formname, spec = spec }
	end,
	close_formspec = function(name, formname)
		local f = fake.forms[name]
		if f and f.formname == formname then fake.forms[name] = nil end
	end,
	formspec_escape = function(s)
		if type(s) ~= "string" then return s end
		return (s:gsub("\\", "\\\\"):gsub("%]", "\\]"):gsub("%[", "\\["):gsub(";", "\\;"))
	end,
	settings = {
		get = function(_, k) return fake.settings_values[k] end,
		get_bool = function(_, k) return fake.settings_bool[k] end,
		set = function(_, k, v) fake.settings_values[k] = v end,
	},
	request_insecure_environment = function() return nil end,
	get_worldpath = function() return "/tmp" end,
	get_gametime = function() return fake.gametime end,
	after = function(_, fn) fn() end, -- tests need no deferred work
	get_player_by_name = function(n) return fake.players[n] end,
	player_exists = function(n) return fake.auth[n] == true end,
	get_connected_players = function()
		local out = {}
		for _, p in pairs(fake.players) do out[#out + 1] = p end
		table.sort(out, function(a, b) return a._name < b._name end)
		return out
	end,
	check_player_privs = check_player_privs,
	get_player_information = function(n) return fake.info[n] end,
	register_privilege = function() end,
	register_chatcommand = function(name, def) commands[name] = def end,
	registered_chatcommands = commands,
	override_chatcommand = function(name, redef)
		assert(commands[name], "Attempt to override non-existent chatcommand " .. name)
		for k, v in pairs(redef) do
			rawset(commands[name], k, v)
		end
	end,
	unregister_chatcommand = function(name) commands[name] = nil end,
	register_on_chat_message = function(fn)
		fake.on_chat[#fake.on_chat + 1] = fn
	end,
	register_on_chatcommand = function(fn)
		fake.on_cmd[#fake.on_cmd + 1] = fn
	end,
	registered_on_chatcommands = fake.on_cmd,
	register_on_joinplayer = function(fn) fake.on_join[#fake.on_join + 1] = fn end,
	register_on_leaveplayer = function(fn) fake.on_leave[#fake.on_leave + 1] = fn end,
	register_on_respawnplayer = function(fn) fake.on_respawn[#fake.on_respawn + 1] = fn end,
	register_on_player_receive_fields = function(fn)
		fake.on_fields[#fake.on_fields + 1] = fn
	end,
	register_on_mods_loaded = function(fn)
		fake.on_mods_loaded[#fake.on_mods_loaded + 1] = fn
	end,
	register_on_shutdown = function(fn) fake.on_shutdown[#fake.on_shutdown + 1] = fn end,
	register_on_globalstep = function(fn) fake.on_globalstep[#fake.on_globalstep + 1] = fn end,
	registered_aliases = {},
}

----------------------------------------------------------------------
-- Builtin chat pipeline (builtin/game/chat.lua, faithful subset)
----------------------------------------------------------------------

-- Command dispatch: on_chatcommand callbacks (mode 5: first truthy
-- wins), then lookup, then privs, then func. This is what makes T8's
-- override observable.
local function run_command(name, message)
	local cmd, param = string.match(message, "^/([^ ]+) *(.*)")
	if not cmd then
		chat_to(name, "-!- Empty command.")
		return true
	end
	param = param or ""
	for _, cb in ipairs(fake.on_cmd) do
		if cb(name, cmd, param) then return true end
	end
	local def = commands[cmd]
	if not def then
		chat_to(name, "-!- Invalid command: " .. cmd)
		return true
	end
	local has_privs = check_player_privs(name, def.privs or {})
	if not has_privs then
		chat_to(name, "-!- You don't have permission to run this command.")
		return true
	end
	local success, result = def.func(name, param)
	if success == false and result == nil then
		chat_to(name, "-!- Invalid command usage.")
		chat_to(name, "/" .. cmd .. " " .. (def.params or ""))
	elseif result then
		chat_to(name, result)
	end
	return true
end

-- The builtin's own on_chat_message handler: registered FIRST, exactly
-- like the engine (mods load after builtin).
table.insert(fake.on_chat, function(name, message)
	if message:sub(1, 1) ~= "/" then return nil end
	return run_command(name, message)
end)

-- send_chat: engine chat entry point. If no callback eats the message
-- the engine broadcasts its default `<@name> @message` line.
local function send_chat(name, message)
	for _, cb in ipairs(fake.on_chat) do
		if cb(name, message) then return true end
	end
	local line = "<" .. name .. "> " .. message
	for _, p in ipairs(core.get_connected_players()) do
		chat_to(p:get_player_name(), line)
	end
	return false
end

local function fire_join(p) for _, cb in ipairs(fake.on_join) do cb(p) end end
local function fire_leave(p) for _, cb in ipairs(fake.on_leave) do cb(p) end end
local function fire_respawn(p) for _, cb in ipairs(fake.on_respawn) do cb(p) end end
local function fire_fields(p, formname, fields)
	for _, cb in ipairs(fake.on_fields) do cb(p, formname, fields) end
end

----------------------------------------------------------------------
-- mcl_* stubs
----------------------------------------------------------------------

mcl_worlds = {
	pos_to_dimension = function(pos)
		if pos.y <= -100 then return "nether" end
		if pos.y >= 400 then return "end" end
		return "overworld"
	end,
}

mcl_spawn = {
	get_world_spawn_pos = function(_) return { x = 0, y = 64, z = 0 } end,
}

mcl_potions = {
	give_effect_by_level = function(name, obj, lvl, dur)
		fake.nv_give[#fake.nv_give + 1] =
			{ name = name, obj = obj, lvl = lvl, dur = dur }
		return true
	end,
	clear_effect = function(obj, name)
		fake.nv_clear[#fake.nv_clear + 1] = { name = name, obj = obj }
		return true
	end,
	has_effect = function() return false end,
}

----------------------------------------------------------------------
-- f12 settings stub: both contract shapes (f11 §6 get, f08 get_name)
----------------------------------------------------------------------

smp_settings = {
	values = {}, -- [player][key] = value
	get = function(player, key)
		local n
		if type(player) == "table" and player.get_player_name then
			n = player:get_player_name()
		else
			n = player
		end
		local t = smp_settings.values[n]
		return t and t[key] or nil
	end,
}

local function set_setting(name, key, value)
	smp_settings.values[name] = smp_settings.values[name] or {}
	smp_settings.values[name][key] = value
end

----------------------------------------------------------------------
-- Load the mods
----------------------------------------------------------------------

local function load_mod(mod)
	_G.__current_modname = mod
	local f, err = loadfile(ROOT .. "/friedcake/mods/" .. mod .. "/init.lua")
	assert(f, "loadfile " .. mod .. ": " .. tostring(err))
	local good, lerr = pcall(f)
	_G.__current_modname = nil
	assert(good, mod .. " init failed: " .. tostring(lerr))
end

load_mod("smp_core")
load_mod("smp_store")
load_mod("smp_social")

for _, cb in ipairs(fake.on_mods_loaded) do cb() end

local REFUSAL = "This user only accepts messages from friends or followed players"

----------------------------------------------------------------------
-- T1 — public chat format, no rank prefix
----------------------------------------------------------------------

eq(smp_social.cfg.chat.rank_prefix, false, "T1 chat.rank_prefix defaults false")
eq(smp_social.format_chat("FoxBuddy2", "ah"), "<FoxBuddy2> ah",
	"T1 observed line 1 exact")
eq(smp_social.format_chat("robieto_faze", "TPA FOR TEAM OR 1V1"),
	"<robieto_faze> TPA FOR TEAM OR 1V1", "T1 observed line 2 exact")
eq(smp_social.format_chat("loldarr",
	"rating bases and neth ingot each and dragon head for very good base"),
	"<loldarr> rating bases and neth ingot each and dragon head for very good base",
	"T1 long line wraps without re-indenting (one logical line)")
ok(smp_social.format_chat("alice", "hi"):sub(1, 1) == "<", "T1 angle brackets")
ok(smp_social.format_chat("alice", "hi"):find("[Rank]", 1, true) == nil,
	"T1 no [Rank] prefix")

local alice = make_player("alice")
local bob = make_player("bob")
local carol = make_player("carol")
local dave = make_player("dave")

reset_chat()
send_chat("alice", "hello world")
ok(chat_contains("bob", "<alice> hello world"), "T1 delivered line is exact")
ok(chat_contains("alice", "<alice> hello world"), "T1 sender sees own message")
ok(not chat_contains("bob", "Invalid command"), "no engine noise")

----------------------------------------------------------------------
-- T2 — Public Chat: OFF receives nothing, ON receives the line
----------------------------------------------------------------------

set_setting("carol", "chat.public", "OFF")
reset_chat()
advance(1)
send_chat("alice", "second line")
ok(chat_contains("bob", "<alice> second line"), "T2 ON recipient receives")
ok(chat_contains("dave", "<alice> second line"), "T2 second ON recipient receives")
eq(#chat_log("carol"), 0, "T2 OFF recipient receives no public lines")

----------------------------------------------------------------------
-- T7 — the teleport hint follows the message and names the sender
----------------------------------------------------------------------

reset_chat()
advance(1)
send_chat("alice", "hint please")
local i = chat_index_of("bob", "<alice> hint please")
ok(i ~= nil, "T7 base line delivered")
eq(chat_log("bob")[i + 1], "Click to send alice a teleport request",
	"T7 hint is the next line, naming the sender")
ok(not chat_contains("alice", "Click to send alice a teleport request"),
	"T7 sender does not get the hint about themselves")
ok(not chat_contains("carol", "hint please"),
	"T7 OFF recipient gets neither line")

----------------------------------------------------------------------
-- T3 — /msg to a FRIENDS_FOLLOWED stranger: verbatim refusal
----------------------------------------------------------------------

local dana = make_player("dana")
local eve = make_player("eve")
set_setting("dana", "chat.private_messages", "FRIENDS_FOLLOWED")

reset_chat()
run_command("eve", "/msg dana supersecret")
eq(last_chat("eve"), REFUSAL, "T3 refusal is verbatim")
eq(last_chat("eve"),
	"This user only accepts messages from friends or followed players",
	"T3 refusal matches the OBSERVED literal")
ok(not chat_contains("dana", "supersecret"), "T3 nothing delivered")
eq(#chat_log("dana"), 0, "T3 recipient is not notified at all")

----------------------------------------------------------------------
-- T4 — /msg to a friend of a FRIENDS_FOLLOWED recipient is delivered
----------------------------------------------------------------------

local fran = make_player("fran")
local okf = smp_social.follow("dana", "fran")
local okf2 = smp_social.follow("fran", "dana")
eq(okf, true, "T4 dana follows fran")
eq(okf2, true, "T4 fran follows dana")
ok(smp_social.is_friend("dana", "fran"), "T4 mutual follows are friends")

reset_chat()
run_command("fran", "/msg dana hi friend")
ok(chat_contains("dana", "fran whispers to you: hi friend"), "T4 delivered")
ok(chat_contains("fran", "You whisper to dana: hi friend"), "T4 sender echo")
ok(not chat_contains("fran", "only accepts"), "T4 no refusal for a friend")

----------------------------------------------------------------------
-- T5 — /msg to someone who ignored you: the SAME refusal
----------------------------------------------------------------------

local grace = make_player("grace")
local hank = make_player("hank")
reset_chat()
run_command("grace", "/ignore hank")
ok(chat_contains("grace", "You are now ignoring hank"), "T5 ignore acknowledged")

reset_chat()
run_command("hank", "/msg grace secret via ignore")
eq(last_chat("hank"), REFUSAL, "T5 ignore refusal identical to privacy refusal")
ok(not chat_contains("grace", "secret via ignore"), "T5 recipient not notified")
eq(#chat_log("grace"), 0, "T5 ignore branch is indistinguishable (silent target)")

----------------------------------------------------------------------
-- T6 — /ignore suppresses chat, PMs and teleport requests
----------------------------------------------------------------------

local irene = make_player("irene")
local jack = make_player("jack")
reset_chat()
run_command("irene", "/ignore jack")
ok(chat_contains("irene", "You are now ignoring jack"), "T6 ignore ack")

-- public chat
reset_chat()
advance(1)
send_chat("jack", "public from jack")
ok(not chat_contains("irene", "public from jack"), "T6 public chat hidden")
ok(chat_contains("bob", "public from jack"), "T6 others still see the line")

-- private messages
reset_chat()
run_command("jack", "/msg irene pm to ignored")
eq(last_chat("jack"), REFUSAL, "T6 PM answered with the generic refusal")
ok(not chat_contains("irene", "pm to ignored"), "T6 PM not delivered")

-- teleport requests: f08 gates /tpa on smp_social.blocks alone
ok(smp_social.ignores("irene", "jack"), "T6 ignores(ignorer, sender)")
ok(smp_social.blocks("irene", "jack"),
	"T6 blocks() covers ignore so f08's /tpa gate refuses")

-- block covers the same surface plus itself
local kim = make_player("kim")
local liam = make_player("liam")
reset_chat()
run_command("kim", "/block liam")
ok(smp_social.blocks("kim", "liam"), "T6 blocks() covers /block")
ok(not smp_social.ignores("kim", "liam"), "T6 pure block is not an ignore")
ok(smp_social.is_blocked("kim", "liam"), "T6 strict is_blocked for block only")

-- un-ignore restores everything
run_command("irene", "/ignore jack")
ok(not smp_social.blocks("irene", "jack"), "T6 un-ignore restores delivery")
ok(not smp_social.ignores("irene", "jack"), "T6 ignore list emptied")

----------------------------------------------------------------------
-- T8 — unknown command
----------------------------------------------------------------------

reset_chat()
run_command("alice", "/frobnicate extra")
eq(last_chat("alice"), "This command does not exist", "T8 verbatim response")
ok(not any_chat_contains("Invalid command"),
	"T8 engine's Invalid command: <name> never appears")
ok(smp_social._on_unknown_command("alice", "frobnicate", "extra") == true,
	"T8 the registered callback cancels the builtin handler")

-- registered commands still dispatch through the same chain
reset_chat()
advance(1)
send_chat("alice", "/ping")
ok(chat_contains("alice", "Ping"), "T8 registered commands unaffected")

----------------------------------------------------------------------
-- T9 — /findplayer is always coarse
----------------------------------------------------------------------

fake.auth["gone_player"] = true -- existed once, now offline
local function location_line(name)
	local out = last_chat(name) or ""
	for line in out:gmatch("[^\n]+") do
		if line:sub(1, 10) == "Location: " then return line:sub(11) end
	end
	return nil
end

reset_chat()
run_command("alice", "/findplayer gone_player")
ok((last_chat("alice") or ""):find("Name: gone_player", 1, true) ~= nil,
	"T9 username exposed")
ok((last_chat("alice") or ""):find("Rank: ", 1, true) ~= nil, "T9 rank exposed")
eq(location_line("alice"), "Offline", "T9 offline location")

reset_chat()
run_command("alice", "/findplayer bob")
eq(location_line("alice"), "Spawn", "T9 at world spawn")

make_player("farah", { x = 100000, y = 64, z = -70000 })
reset_chat()
run_command("alice", "/findplayer farah")
local far = location_line("alice")
eq(far, "Overworld – North-East", "T9 dimension – region")
ok(far:find("%d") == nil, "T9 no digits: never exact coordinates")

make_player("neth", { x = 5000, y = -2000, z = 5000 })
reset_chat()
run_command("alice", "/findplayer neth")
local ned = location_line("alice")
eq(ned, "Nether – South-East", "T9 nether coarse")
ok(ned:find("%d") == nil, "T9 nether has no digits")

make_player("ender", { x = 8000, y = 500, z = 8000 })
reset_chat()
run_command("alice", "/findplayer ender")
eq(location_line("alice"), "The End – South-East", "T9 end coarse")

make_player("cent", { x = 1000, y = 64, z = 1000 })
reset_chat()
run_command("alice", "/findplayer cent")
eq(location_line("alice"), "Overworld – Center",
	"T9 inside the region band but outside spawn radius")

reset_chat()
run_command("alice", "/findplayer nobody_real")
eq(last_chat("alice"), "Player nobody_real does not exist", "T9 unknown name")

----------------------------------------------------------------------
-- T10 — follows and derived friendship
----------------------------------------------------------------------

local mia = make_player("mia")
local noah = make_player("noah")
local omar = make_player("omar")

local fr, frmsg = smp_social.follow("mia", "noah")
eq(fr, true, "T10 one-way follow accepted")
ok(smp_social.follows("mia", "noah"), "T10 follows edge visible")
ok(not smp_social.is_friend("mia", "noah"), "T10 one-way follow is not friendship")
ok(smp_social.is_friend_or_followed("mia", "noah"),
	"T10 recipient-follows edge grants access")
ok(not smp_social.is_friend_or_followed("noah", "mia"),
	"T10 the reverse one-way edge does not grant access")

reset_chat()
smp_social.follow("noah", "mia")
ok(smp_social.is_friend("mia", "noah") and smp_social.is_friend("noah", "mia"),
	"T10 mutual follows are friends in both directions")
ok(chat_contains("mia", "You are now friends with noah"),
	"T10 friendship notice to the first follower")
ok(chat_contains("noah", "You are now friends with mia"),
	"T10 friendship notice to the second follower")

smp_social.follow("omar", "mia")
ok(not smp_social.is_friend("mia", "omar") and not smp_social.is_friend("omar", "mia"),
	"T10 a one-way follow does not create friendship")

-- follow limit (social.max_follows = 200)
do
	local maxer = make_player("maxer")
	for n = 1, 200 do fake.auth["filler" .. n] = true end
	local refused = nil
	for n = 1, 200 do
		local okmax = smp_social.follow("maxer", "filler" .. n)
		if not okmax then refused = n break end
	end
	eq(refused, nil, "follow limit not hit at exactly 200")
	local ok201, err201 = smp_social.follow("maxer", "alice")
	eq(ok201, false, "201st follow refused")
	local _ = err201
	reset_chat()
	run_command("maxer", "/friend addsearch alice")
	eq(last_chat("maxer"), "You reached the follow limit",
		"follow-limit message via /friend")
end

----------------------------------------------------------------------
-- /friend subcommands
----------------------------------------------------------------------

reset_chat()
run_command("mia", "/friend following")
ok(chat_contains("mia", "Following (1): noah"), "friend following list")
reset_chat()
run_command("mia", "/friend friends")
ok(chat_contains("mia", "Friends (1): noah"), "friend friends list")
reset_chat()
run_command("noah", "/friend followers")
ok(chat_contains("noah", "Followers (1): mia"), "friend followers list")
reset_chat()
run_command("alice", "/friend search mi")
ok(chat_contains("alice", "mia"), "friend search finds names")
reset_chat()
run_command("alice", "/friend addsearch omar")
ok(chat_contains("alice", "You are now following omar"), "addsearch follows")
reset_chat()
run_command("alice", "/friend remove omar")
ok(chat_contains("alice", "You no longer follow omar"), "remove unfollows")
reset_chat()
run_command("alice", "/friend list")
ok(chat_contains("alice", "Friends: "), "friend list summary")
reset_chat()
run_command("alice", "/friend bogus")
ok(chat_contains("alice", "Invalid command usage"),
	"unknown subcommand falls back to the engine usage line")

----------------------------------------------------------------------
-- /msg variants: offline, OFF, aliases, /r
----------------------------------------------------------------------

reset_chat()
run_command("alice", "/msg ghost hello")
eq(last_chat("alice"), "That player is not online", "offline target message")

local offtarget = make_player("offtarget")
set_setting("offtarget", "chat.private_messages", "OFF")
reset_chat()
run_command("alice", "/msg offtarget hi")
eq(last_chat("alice"), "This user is not accepting private messages",
	"OFF refusal (distinct from the generic one)")
ok(REFUSAL ~= "This user is not accepting private messages",
	"the two refusals stay distinguishable as specified")

reset_chat()
advance(1)
run_command("alice", "/tell bob aliased hello")
ok(chat_contains("bob", "alice whispers to you: aliased hello"),
	"alias /tell delegates to /msg")
reset_chat()
run_command("bob", "/reply aliased back")
ok(chat_contains("alice", "bob whispers to you: aliased back"),
	"/r replies to the other party")
reset_chat()
run_command("carol", "/r lonely")
eq(last_chat("carol"), "You have no one to reply to",
	"/r without history")

----------------------------------------------------------------------
-- Anti-spam and duplicate filter
----------------------------------------------------------------------

reset_chat()
advance(1)
send_chat("dave", "spam one")
ok(chat_contains("alice", "spam one"), "first message delivered")
send_chat("dave", "spam two") -- same second: rate limited
eq(last_chat("dave"), "You are sending messages too quickly", "rate refusal")
ok(not chat_contains("alice", "spam two"), "rate-limited message not delivered")
advance(1)
send_chat("dave", "spam three")
ok(chat_contains("alice", "spam three"), "next message after 1s delivered")
advance(1)
send_chat("dave", "spam three") -- verbatim repeat: duplicate filter
eq(last_chat("dave"), "Do not repeat yourself", "duplicate refusal")
eq(count_chat("alice", "spam three"), 1, "duplicate not delivered twice")

----------------------------------------------------------------------
-- Join / leave notices (viewer-side Friends/Followed filter)
----------------------------------------------------------------------

local joe = make_player("joe")
smp_social.follow("bob", "joe")
set_setting("bob", "chat.join_leave", "FRIENDS_FOLLOWED")
set_setting("carol", "chat.join_leave", "FRIENDS_FOLLOWED")
-- dave keeps the permissive default (ON)

reset_chat()
fire_join(joe)
ok(chat_contains("bob", "joe joined the game"), "join notice to a follower")
ok(not chat_contains("carol", "joe joined the game"),
	"no join notice to a non-follower under Friends/Followed")
ok(chat_contains("dave", "joe joined the game"),
	"ON sees every join notice")

reset_chat()
fire_leave(joe)
ok(chat_contains("bob", "joe left the game"), "leave notice to a follower")
ok(not chat_contains("carol", "joe left the game"), "leave filtered too")
fake.players["joe"] = nil -- keep /list counts stable below

----------------------------------------------------------------------
-- /kill confirmation dialog
----------------------------------------------------------------------

reset_forms()
reset_chat()
local bobp = fake.players["bob"]
bobp._hp = 20
run_command("bob", "/kill")
local kfs = fake.forms["bob"]
ok(kfs ~= nil and kfs.formname == "smp_social:kill", "kill confirm opens")
ok(kfs and kfs.spec:find("kill_confirm", 1, true), "confirm button present")
ok(kfs and kfs.spec:find("kill_cancel", 1, true), "cancel button present")
ok(kfs and kfs.spec:find("bgcolor=red", 1, true), "Cancel is red (shared §4.6)")
ok(kfs and kfs.spec:find("Are you sure you want to kill yourself?", 1, true),
	"confirmation question shown")

fire_fields(bobp, "smp_social:kill", { kill_cancel = true })
eq(bobp:get_hp(), 20, "cancel leaves the player alive")

run_command("bob", "/kill")
fire_fields(bobp, "smp_social:kill", { kill_confirm = true })
eq(bobp:get_hp(), 0, "confirm kills (items drop through the normal death path)")

bobp._hp = 20
fire_fields(bobp, "smp_social:kill", { kill_confirm = true })
eq(bobp:get_hp(), 20, "forged field without a session is ignored")
bobp._hp = 20

----------------------------------------------------------------------
-- /nightvision toggle, persistence, respawn re-application
----------------------------------------------------------------------

reset_chat()
local give_before = #fake.nv_give
run_command("alice", "/nightvision")
eq(last_chat("alice"), "Night vision enabled", "night vision on")
eq(fake.players["alice"]:get_meta():get_int("smp_social:nightvision"), 1,
	"night vision persisted in meta")
eq(#fake.nv_give, give_before + 1, "effect granted once")
ok(fake.nv_give[#fake.nv_give].dur == "INF", "infinite duration")
ok(fake.nv_give[#fake.nv_give].lvl == 1, "level 1 (f11 §4.6)")

reset_chat()
run_command("alice", "/nightvision")
eq(last_chat("alice"), "Night vision disabled", "night vision off")
eq(fake.players["alice"]:get_meta():get_int("smp_social:nightvision"), 0,
	"meta cleared")
eq(#fake.nv_clear, 1, "effect cleared once")

-- re-apply on join and respawn while the flag is set
fake.players["alice"]:get_meta():set_int("smp_social:nightvision", 1)
local give2 = #fake.nv_give
fire_join(fake.players["alice"])
eq(#fake.nv_give, give2 + 1, "re-applied on join")
local give3 = #fake.nv_give
fire_respawn(fake.players["alice"])
eq(#fake.nv_give, give3 + 1, "re-applied on respawn")

----------------------------------------------------------------------
-- Informational commands
----------------------------------------------------------------------

reset_chat()
reset_forms()
run_command("alice", "/discord")
eq(last_chat("alice"), "This link is not configured", "unset link fallback")

fake.settings_values["info.discord"] = "https://discord.gg/example"
reset_forms()
run_command("alice", "/discord")
local dfs = fake.forms["alice"]
ok(dfs ~= nil and dfs.formname == "smp_social:info", "info formspec opens")
ok(dfs and dfs.spec:find("https://discord.gg/example", 1, true),
	"URL sits in the read-only field")
ok(dfs and dfs.spec:find("Back", 1, true), "prompt menu ends with Back")
ok(dfs and dfs.spec:find("Discord", 1, true), "title")

fire_fields(fake.players["alice"], "smp_social:info", { info_back = true })
eq(fake.forms["alice"], nil, "Back closes the screen")

reset_forms()
run_command("alice", "/help")
local hfs = fake.forms["alice"]
ok(hfs and hfs.spec:find("/msg", 1, true), "auto help lists /msg")
ok(hfs and hfs.spec:find("/findplayer", 1, true), "auto help lists /findplayer")

reset_chat()
run_command("alice", "/help msg")
ok(chat_contains("alice", "/msg <player> <message>"),
	"/help <command> keeps per-command help")

reset_chat()
run_command("alice", "/help frobnicate")
eq(last_chat("alice"), "This command does not exist",
	"/help names unknown commands the observed way")

reset_chat()
run_command("alice", "/rules")
eq(last_chat("alice"), "This text is not configured", "unset text fallback")

----------------------------------------------------------------------
-- /ping /list /report /helpop
----------------------------------------------------------------------

reset_chat()
fake.info["alice"] = { avg_rtt = 0.0256 }
run_command("alice", "/ping")
eq(last_chat("alice"), "Ping: 26 ms", "/ping converts seconds to ms")
fake.info["alice"] = nil
run_command("alice", "/ping")
eq(last_chat("alice"), "Ping is not available yet", "/ping without stats")

reset_chat()
run_command("alice", "/list")
local names = {}
for name in pairs(fake.players) do names[#names + 1] = name end
table.sort(names, function(a, b) return a:lower() < b:lower() end)
eq(last_chat("alice"),
	"Players online (" .. #names .. "): " .. table.concat(names, ", "),
	"/list format")
reset_chat()
run_command("alice", "/who")
ok(chat_contains("alice", "Players online ("), "/who aliases /list")

fake.privs["dave"] = { shout = true, smp_moderator = true }
reset_chat()
run_command("alice", "/report bob being suspicious")
ok(chat_contains("alice", "Your report was sent to staff"),
	"report confirmation")
ok(chat_contains("dave", "alice reported bob: being suspicious"),
	"report reaches staff")
ok(not chat_contains("bob", "reported"), "the reported player is not told")

reset_chat()
run_command("alice", "/helpop please check base 42")
ok(chat_contains("alice", "Your report was sent to staff"), "helpop confirmation")
ok(chat_contains("dave", "HelpOp from alice: please check base 42"),
	"helpop reaches staff")
reset_chat()
run_command("alice", "/report bob")
ok(chat_contains("alice", "Invalid command usage"),
	"/report without a reason falls back to usage")

----------------------------------------------------------------------
-- Settings bridge (both f12 contract shapes + permissive default)
----------------------------------------------------------------------

do
	local saved = _G.smp_settings
	_G.smp_settings = nil
	eq(smp_social.get_setting(fake.players["alice"], "chat.private_messages"),
		"ON", "bridge permissive default without f12")
	_G.smp_settings = { -- f08's assumed shape only
		get_name = function(n, k)
			if n == "zed" and k == "chat.public" then return "OFF" end
			return nil
		end,
	}
	eq(smp_social.get_setting("zed", "chat.public"), "OFF",
		"bridge honours smp_settings.get_name (f08 shape)")
	eq(smp_social.get_setting("zed", "chat.join_leave"), "ON",
		"bridge falls back to the permissive default for unknown keys")
	_G.smp_settings = saved
end

----------------------------------------------------------------------
-- Rank-prefix bridge stays empty (V-24: no prefix observed)
----------------------------------------------------------------------

eq(smp_social.rank_prefix("alice"), "", "no rank prefix without f13")
eq(smp_social.rank_display("alice"), "None", "default rank displays as None")

----------------------------------------------------------------------
-- Commands and aliases are all registered
----------------------------------------------------------------------

for _, c in ipairs({ "msg", "r", "ignore", "block", "friend", "findplayer",
	"fp", "kill", "nightvision", "nv", "help", "rules", "discord", "media",
	"link", "buy", "store", "website", "ranks", "medal", "ping", "list",
	"who", "online", "report", "helpop", "ac", "message", "tell", "w",
	"whisper", "pm", "reply", "friends" }) do
	ok(commands[c] ~= nil, "command registered: /" .. c)
end

----------------------------------------------------------------------
-- In-game suite (mods/smp_social/test.lua) also runs here
----------------------------------------------------------------------

print("== in-game test suite (mods/smp_social/test.lua) ==")
do
	local chunk, lerr = loadfile(ROOT .. "/friedcake/mods/smp_social/test.lua")
	ok(chunk ~= nil, "test.lua loads: " .. tostring(lerr))
	if chunk then
		local good, res = pcall(chunk)
		ok(good, "test.lua runs: " .. tostring(res))
		if good and type(res) == "table" then
			eq(res.failed, 0, "in-game suite has no failures (" ..
				tostring(res.passed) .. " passed)")
			for _, l in ipairs(res.lines or {}) do print("  " .. l) end
		end
	end
end

----------------------------------------------------------------------
print(string.format("passed=%d failed=%d", passed, failed))
if failed > 0 then
	print("TEST_SOCIAL FAILED")
	os.exit(1)
end
print("ALL OK")
