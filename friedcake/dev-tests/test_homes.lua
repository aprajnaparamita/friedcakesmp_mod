-- FriedcakeSMP dev smoke test: smp_tp homes subsystem (f09)
--
-- Standalone harness (no engine): stubs `core` just enough to load
-- smp_core, smp_store, smp_tp and smp_tp/homes.lua, then exercises
-- spec/features/f09-homes.md §9 at the COMMAND level:
--
--   T1  /sethome at the slot limit produces exactly
--       `You reached home limits` and creates nothing — including the
--       two-rapid-calls race (no yields between validate and mutate)
--   T2  /sethome below the limit produces exactly `Home set` and the
--       new tab is named `Home <n>`
--   T5  /homes <unknown> produces exactly `Home does not exist`
--   T8  a home id deleted while its submenu is open fails safely on
--       the next click (no warm-up, no crash, back to the Homes row)
--
-- It also runs T7 (icon persists through an smp_store reboot) and then
-- executes friedcake/mods/smp_tp/test_homes.lua for T2/T3/T4/T6/T7/T9
-- at the data/render level plus the verbatim-string checks.
--
-- Run: luajit friedcake/dev-tests/test_homes.lua
-- Exits non-zero on any failure.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

----------------------------------------------------------------------
-- Minimal vector (the engine provides this; luajit does not)
----------------------------------------------------------------------

function vnew(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end
local function vdist(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end
vector = {  -- the mods reference the engine's global
	new = function(v, y, z)
		if type(v) == "number" then return vnew(v, y, z) end
		if type(v) == "table" and v.x then return vnew(v.x, v.y, v.z) end
		if type(v) == "table" then return vnew(v[1], v[2], v[3]) end
		error("vector.new: bad args")
	end,
	distance = vdist,
	offset = function(v, dx, dy, dz) return vnew(v.x + dx, v.y + dy, v.z + dz) end,
}

----------------------------------------------------------------------
-- Fake time + fake core.after
----------------------------------------------------------------------

local now = 1758500000
os.time = function() return now end

local fake = {
	pending = {},          -- { {at, fn}, ... }
	chat = {},             -- [name] = { msgs }
	formspecs = {},        -- [name] = { fs strings }
	titles = {},           -- action-bar log
	hpchange = nil,
	globalsteps = {},
	leaves = {}, die = {}, fields = {},
	players = {},          -- name -> fake player
	node_at = function() return "air" end,
}

local function advance(dt)
	now = now + math.floor(dt)
	while true do
		local due = nil
		for _, p in ipairs(fake.pending) do
			if p.at <= now and (not due or p.at < due.at) then due = p end
		end
		if not due then break end
		for i, p in ipairs(fake.pending) do
			if p == due then table.remove(fake.pending, i) break end
		end
		due.fn()
	end
end

local function S_factory(_)
	return function(s, ...)
		local args = {...}
		return (s:gsub("@(%d+)", function(n)
			return tostring(args[tonumber(n)] or "")
		end))
	end
end

----------------------------------------------------------------------
-- JSON round-trip (what core.write_json / core.parse_json do for the
-- mod_storage backend; copied from test_economy.lua)
----------------------------------------------------------------------

local function json_encode(v)
	local t = type(v)
	if t == "nil"     then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number"  then
		if v == math.floor(v) then return string.format("%.0f", v) end
		return tostring(v)
	end
	if t == "string" then
		return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"')
			:gsub("\n", "\\n"):gsub("\t", "\\t") .. '"'
	end
	if t == "table" then
		local n = 0
		for k in pairs(v) do
			if type(k) ~= "number" then n = -1; break end
			if k > n then n = k end
		end
		if n == -1 then
			local p = {}
			for k, vv in pairs(v) do p[#p + 1] = string.format('"%s":%s', tostring(k), json_encode(vv)) end
			return "{" .. table.concat(p, ",") .. "}"
		end
		local p = {}
		for i = 1, n do p[#p + 1] = json_encode(v[i]) end
		return "[" .. table.concat(p, ",") .. "]"
	end
	return "null"
end

local json_decode
local function skip_ws(s, i)
	while i <= #s do
		local c = s:sub(i, i)
		if c == ' ' or c == '\t' or c == '\n' or c == '\r' then i = i + 1 else break end
	end
	return i
end
local function parse_str(s, i)
	assert(s:sub(i, i) == '"', "expected string")
	local out, j = "", i + 1
	while j <= #s do
		local c = s:sub(j, j)
		if c == '"' then return out, j + 1 end
		if c == '\\' then
			local nc = s:sub(j + 1, j + 1)
			if nc == '"' then out = out .. '"'
			elseif nc == '\\' then out = out .. '\\'
			elseif nc == 'n' then out = out .. '\n'
			elseif nc == 't' then out = out .. '\t'
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
		local k; k, i = parse_str(s, i)
		i = skip_ws(s, i)
		assert(s:sub(i, i) == ':', "expected : at " .. i)
		i = skip_ws(s, i + 1)
		local v; v, i = parse_val(s, i)
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
		local v; v, i = parse_val(s, i)
		t[idx] = v; idx = idx + 1
		i = skip_ws(s, i)
		if s:sub(i, i) == ',' then i = i + 1 end
	end
	error("unterminated array")
end
parse_val = function(s, i)
	i = skip_ws(s, i)
	local c = s:sub(i, i)
	if c == '"' then return parse_str(s, i) end
	if c == '{' then return parse_obj(s, i) end
	if c == '[' then return parse_arr(s, i) end
	if c == '-' or c:match('%d') or c == 't' or c == 'f' or c == 'n' then
		local j = i
		while j <= #s and s:sub(j, j):match('[%-%d%.eE%+a-zA-Z]') do j = j + 1 end
		local tok = s:sub(i, j - 1)
		if tok == "true" then return true, j end
		if tok == "false" then return false, j end
		if tok == "null" then return nil, j end
		return tonumber(tok), j
	end
	error("unexpected '" .. c .. "' at " .. i)
end
json_decode = function(s)
	if not s or s == "" then return nil end
	local v = parse_val(s, 1)
	return v
end

----------------------------------------------------------------------
-- In-memory mod storage (survives the fake "reboot" below)
----------------------------------------------------------------------

local store_data = {}

----------------------------------------------------------------------
-- Fake core
----------------------------------------------------------------------

-- What core.formspec_escape does (builtin/common/misc_helpers.lua):
-- escape \ [ ] ; , $ with a backslash.
local BS = "\\"
local FS_ESCAPES = {
	[BS]  = BS .. BS,
	["["] = BS .. "[",
	["]"] = BS .. "]",
	[";"] = BS .. ";",
	[","] = BS .. ",",
	["$"] = BS .. "$",
}

local core = {
	log = function(_, ...) end,
	get_translator = S_factory,
	get_current_modname = function() return _G.__current_modname or "smp_tp" end,
	after = function(sec, fn)
		fake.pending[#fake.pending + 1] = { at = now + math.max(1, math.floor(sec)), fn = fn }
	end,
	chat_send_player = function(name, msg)
		fake.chat[name] = fake.chat[name] or {}
		fake.chat[name][#fake.chat[name] + 1] = msg
	end,
	get_player_by_name = function(name) return fake.players[name] end,
	player_exists = function(name) return fake.players[name] ~= nil end,
	get_connected_players = function()
		local out = {}
		for name in pairs(fake.players) do out[#out + 1] = fake.players[name] end
		return out
	end,
	get_node = function(pos) return { name = fake.node_at(pos.x, pos.y, pos.z) } end,
	get_item_group = function() return 0 end,
	emerge_area = function(_, _, cb) cb(nil, nil, 0) end,
	show_formspec = function(name, formname, fs)
		fake.formspecs[name] = fake.formspecs[name] or {}
		fake.formspecs[name][#fake.formspecs[name] + 1] = fs
	end,
	close_formspec = function() end,
	get_gametime = function() return math.floor((now - 1758500000)) end,
	settings = {
		get = function() return "" end,
		get_bool = function() return false end,
	},
	get_worldpath = function() return "/tmp" end,
	DIR_DELIM = "/",
	register_chatcommand = function(name, def)
		core.registered_chatcommands[name] = def
	end,
	registered_chatcommands = {},
	register_privilege = function() end,
	register_on_player_hpchange = function(fn) fake.hpchange = fn end,
	register_globalstep = function(fn) fake.globalsteps[#fake.globalsteps + 1] = fn end,
	register_on_leaveplayer = function(fn) fake.leaves[#fake.leaves + 1] = fn end,
	register_on_dieplayer = function(fn) fake.die[#fake.die + 1] = fn end,
	register_on_shutdown = function() end,
	register_on_player_receive_fields = function(formname, fn)
		fake.fields[formname] = fn
	end,
	request_insecure_environment = function() return nil end,
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
	formspec_escape = function(text)
		if text == nil then return "" end
		return (tostring(text):gsub("[\\%[%];,$]", function(c)
			return FS_ESCAPES[c] or ("\\" .. c)
		end))
	end,
	strip_colors = function(s) return (s:gsub("\27%([bc]@[^)]+%)", "")) end,
	registered_items = {},
}
minetest = core
_G.core = core

local mcl_title = {
	set = function(player, _, data)
		local name = player:get_player_name()
		fake.titles[name] = fake.titles[name] or {}
		fake.titles[name][#fake.titles[name] + 1] = data.text
	end,
}
_G.mcl_title = mcl_title

-- A small item universe for the Choose Icon screen; the alphabetical
-- head mirrors the observed list [F0066].
local function reg_item(name, desc)
	core.registered_items[name] = { name = name, description = desc }
end
reg_item("mcl_beds:bed_red_bottom", "Red Bed")
reg_item("mcl_core:acacia", "Acacia Planks")
reg_item("mcl_core:acacia_2", "Acacia Button")
reg_item("mcl_core:acacia_boat", "Acacia Chest Boat")
reg_item("mcl_core:acacia_door", "Acacia Door")
reg_item("mcl_core:diamond", "Diamond")
reg_item("mcl_core:obsidian", "Obsidian")
reg_item("mcl_core:stone", "Stone")
reg_item("mcl_throwing:ender_pearl", "Ender Pearl")
reg_item("mcl_books:book", "Book")
reg_item("mcl_beds:bed", "\27(c@#ff0000)Bed")

----------------------------------------------------------------------
-- Path resolution WITHOUT pattern matching (see f08 §10: this engine's
-- pattern-mode string.find is unreliable for the "b-" byte sequence in
-- "friedcake/"). Probe candidate bases instead.
----------------------------------------------------------------------

local function readable(p)
	local f = io.open(p, "r")
	if f then f:close() return true end
	return false
end
local BASE
for _, c in ipairs({ "", "../", "../../" }) do
	if readable(c .. "friedcake/mods/smp_tp/config.lua") then BASE = c break end
end
assert(BASE, "run as friedcake/dev-tests/test_homes.lua from the repo root (or inside it)")
local MODROOT = BASE .. "friedcake/mods/smp_tp/"

core.get_modpath = function(m) return BASE .. "friedcake/mods/" .. m end

----------------------------------------------------------------------
-- Fake player
----------------------------------------------------------------------

local function make_player(name, pos)
	local p = {
		_name = name,
		_pos = vnew(pos.x, pos.y, pos.z),
		_vel = vnew(),
	}
	function p:get_player_name() return self._name end
	function p:get_pos() return self._pos end
	function p:set_pos(pos) self._pos = vnew(pos.x, pos.y, pos.z) end
	function p:set_player_velocity(v) self._vel = vnew(v.x, v.y, v.z) end
	function p:get_meta()
		return { get = function() return "" end, set = function() end }
	end
	fake.players[name] = p
	_G[name] = p
	return p
end

----------------------------------------------------------------------
-- Load the mods under the fake engine
----------------------------------------------------------------------

dofile(BASE .. "friedcake/mods/smp_core/init.lua")
dofile(BASE .. "friedcake/mods/smp_store/init.lua")
-- init.lua now wires homes.lua itself (f09 §11 integrator edit), so the
-- harness no longer loads the subsystem directly.
dofile(MODROOT .. "init.lua")

----------------------------------------------------------------------
-- Test harness helpers
----------------------------------------------------------------------

local passed, failed = 0, 0
local function ok(cond, msg)
	if cond then passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, string.format("%s: expected %q got %q", msg or "eq", tostring(b), tostring(a)))
end
local function last_chat(name)
	local l = fake.chat[name]
	return l and l[#l]
end
local function chat_delta(name, before)
	local l = fake.chat[name] or {}
	local out = {}
	for i = before + 1, #l do out[#out + 1] = l[i] end
	return out
end
local function reset_chat()
	fake.chat = {}
	fake.formspecs = {}
	fake.titles = {}
end
local function last_fs(name)
	local l = fake.formspecs[name]
	return l and l[#l] or ""
end
local function find_plain(hay, needle)
	return hay:find(needle, 1, true)
end
local function cmd(name)
	local c = core.registered_chatcommands[name]
	ok(c ~= nil, "command /" .. name .. " registered")
	return c and c.func
end

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------

local A = "f09_alice"
make_player(A, { x = 100, y = 70, z = 100 })
local H = smp_tp.homes

reset_chat()

----------------------------------------------------------------------
-- T2 — /sethome below the limit: exactly `Home set`, tab `Home <n>`
----------------------------------------------------------------------

do
	local f = cmd("sethome")
	local before = #(fake.chat[A] or {})
	local r = f(A, "")
	ok(r == true, "T2 /sethome accepted")
	local msgs = chat_delta(A, before)
	eq(#msgs, 1, "T2 exactly one chat line")
	eq(msgs[1], "Home set", "T2 verbatim Home set")
	local homes = H.list(A)
	eq(#homes, 1, "T2 one home")
	eq(homes[1].name, "Home 1", "T2 auto-named Home 1")
	eq(homes[1].id, 1, "T2 id 1")

	-- The menu the /sethome message accompanies: tab row with the tab.
	local fm = cmd("homes")
	reset_chat()
	fm(A, "")
	local fs = last_fs(A)
	ok(find_plain(fs, "Homes"), "T2 menu titled Homes")
	ok(find_plain(fs, "home_1"), "T2 tab button home_1")
	ok(find_plain(fs, "Home 1"), "T2 tab label Home 1")
	ok(find_plain(fs, "Click to manage"), "T2 tab tooltip line 2")
	ok(find_plain(fs, "New Home"), "T2 New Home tab follows the homes")

	-- Second home is `Home 2`.
	before = #(fake.chat[A] or {})
	f(A, "")
	msgs = chat_delta(A, before)
	eq(#msgs, 1, "T2 second /sethome: one line")
	eq(msgs[1], "Home set", "T2 second Home set")
	eq(H.list(A)[2].name, "Home 2", "T2 auto-named Home 2")

	reset_chat()
	fm(A, "")
	fs = last_fs(A)
	ok(find_plain(fs, "home_2") and find_plain(fs, "Home 2"), "T2 second tab Home 2")
end

----------------------------------------------------------------------
-- T1 — at the limit: exactly `You reached home limits`, nothing made
--      (including the two-rapid-calls race)
----------------------------------------------------------------------

do
	local f = cmd("sethome")
	local before = #(fake.chat[A] or {})
	f(A, "")
	local msgs = chat_delta(A, before)
	eq(#msgs, 1, "T1 exactly one chat line at the limit")
	eq(msgs[1], "You reached home limits", "T1 verbatim (plural limits)")
	eq(#H.list(A), 2, "T1 nothing created")

	-- The race: one slot free, two /sethome calls in the SAME tick.
	local d = cmd("delhome")
	reset_chat()
	d(A, "1")
	eq(last_chat(A), "Home deleted", "T1 slot freed via /delhome")
	reset_chat()
	f(A, "")            -- takes the free slot
	f(A, "")            -- must be refused, synchronously
	local all = fake.chat[A] or {}
	eq(#all, 2, "T1 two rapid calls produce two lines")
	eq(all[1], "Home set", "T1 first call won the slot")
	eq(all[2], "You reached home limits", "T1 second call refused")
	eq(#H.list(A), 2, "T1 limit never exceeded by the race")
end

----------------------------------------------------------------------
-- T5 — /homes <unknown>: exactly `Home does not exist`
--      (/home alias behaves identically)
----------------------------------------------------------------------

do
	local f = cmd("homes")
	local before = #(fake.chat[A] or {})
	local r = f(A, "definitely_not_a_home")
	ok(r == true, "T5 command handled (engine adds no usage error)")
	local msgs = chat_delta(A, before)
	eq(#msgs, 1, "T5 exactly one chat line")
	eq(msgs[1], "Home does not exist", "T5 verbatim message")
	ok(next(fake.formspecs[A] or {}) == nil, "T5 no menu opened")

	local fa = cmd("home")
	reset_chat()
	before = #(fake.chat[A] or {})
	fa(A, "nope")
	msgs = chat_delta(A, before)
	eq(#msgs, 1, "T5 /home alias one line")
	eq(msgs[1], "Home does not exist", "T5 /home alias verbatim")
end

----------------------------------------------------------------------
-- T8 — home id deleted while its submenu is open fails safely
--      (positive control first: a LIVE id teleports through the f08
--      warm-up)
----------------------------------------------------------------------

do
	reset_chat()
	local homes = H.list(A)
	local id = homes[1].id
	local pos = homes[1].pos

	-- Positive control: submenu open, Teleport pressed, home exists.
	H.show_sub(A, id)
	local P = fake.players[A]
	P._pos = vnew(150, 70, 100)   -- stand away so the move is real
	local fs = last_fs(A)
	ok(find_plain(fs, "Teleport") and find_plain(fs, "Change Icon"),
		"T8 submenu rendered (2x2 grid)")
	ok(find_plain(fs, "style[delete;textcolor=red]"), "T8 Delete styled red [F0068]")
	ok(find_plain(fs, "Back"), "T8 Back centred beneath")
	local handler = fake.fields[H.FORMNAME]
	ok(handler ~= nil, "T8 homes fields handler registered")
	reset_chat()
	handler(fake.players[A], { teleport = "true" })
	local w = smp_tp.warmup[A]
	ok(w ~= nil and w.kind == "home", "T8 live id starts the home warm-up")
	advance(6)
	eq(math.floor(P._pos.x), pos.x, "T8 arrived at the home (f08 warm-up path)")

	-- T8 proper: open the submenu again, delete the home BEHIND it,
	-- then press Teleport on the stale id.
	H.show_sub(A, id)
	local sess = smp_core.get_session(A, H.FORMNAME)
	ok(sess ~= nil and sess.screen == "sub", "T8 submenu session open")
	reset_chat()
	local d = cmd("delhome")
	d(A, tostring(id))
	eq(last_chat(A), "Home deleted", "T8 home deleted while submenu open")
	reset_chat()
	handler(fake.players[A], { teleport = "true" })
	local msgs = chat_delta(A, 0)
	eq(#msgs, 1, "T8 exactly one chat line")
	eq(msgs[1], "Home does not exist", "T8 verbatim refusal")
	ok(smp_tp.warmup[A] == nil, "T8 no warm-up started for the stale id")
	sess = smp_core.get_session(A, H.FORMNAME)
	ok(sess ~= nil and sess.screen == "row", "T8 fell back to the Homes row")
	ok(find_plain(last_fs(A), "Homes"), "T8 row re-rendered after the refusal")

	-- A forged submenu key on a STALE submenu session dies the same way.
	H.set_screen(A, { screen = "sub", id = id })
	reset_chat()
	handler(fake.players[A], { rename = "true" })
	msgs = chat_delta(A, 0)
	eq(#msgs, 1, "T8 forged rename click also fails safely")
	eq(msgs[1], "Home does not exist", "T8 forged click refusal")
	ok(smp_tp.warmup[A] == nil, "T8 forged click starts no warm-up")
end

----------------------------------------------------------------------
-- T7 (harness half) — icon choice survives an smp_store reboot
----------------------------------------------------------------------

do
	reset_chat()
	local homes = H.list(A)
	ok(#homes > 0, "T7 a home exists")
	local id = homes[1].id
	ok(H.set_icon(A, id, "mcl_core:obsidian"), "T7 icon set")
	eq(H.get(A, id).icon, "mcl_core:obsidian", "T7 icon visible in the record")
	-- "Restart": boot a fresh smp_store against the same storage; the
	-- driver re-reads every record from disk-equivalent state.
	dofile(BASE .. "friedcake/mods/smp_store/init.lua")
	eq(H.get(A, id).icon, "mcl_core:obsidian", "T7 icon survives a store reboot")
end

----------------------------------------------------------------------
-- /home alias opens the menu; /homes with no argument opens the menu
----------------------------------------------------------------------

do
	reset_chat()
	local fa = cmd("home")
	fa(A, "")
	ok(find_plain(last_fs(A), "Homes"), "alias /home opens the Homes menu")
end

----------------------------------------------------------------------
-- In-game acceptance file: test_homes.lua (T2–T9 at data/render level,
-- verbatim strings, Show More, rename, delete, privacy)
----------------------------------------------------------------------

do
	local chunk, err = loadfile(MODROOT .. "test_homes.lua")
	ok(chunk ~= nil, "test_homes.lua loads" .. (err and (": " .. err) or ""))
	if chunk then
		local okrun, res = pcall(chunk)
		ok(okrun, "test_homes.lua ran" .. (not okrun and (": " .. tostring(res)) or ""))
		if okrun and type(res) == "table" then
			passed = passed + (res.passed or 0)
			failed = failed + (res.failed or 0)
			for _, l in ipairs(res.lines or {}) do
				print("FAIL " .. l)
			end
		else
			failed = failed + 1
		end
	end
end

----------------------------------------------------------------------

print(string.format("smp_tp homes dev-tests: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
