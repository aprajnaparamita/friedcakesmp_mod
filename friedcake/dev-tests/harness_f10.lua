-- FriedcakeSMP dev-tests harness for f10 (smp_combat + smp_bounty).
-- NOT auto-run by tools/agent-flow.sh (only test_*.lua are): both
-- test_combat.lua and test_bounty.lua dofile this first.
--
-- Stubs the engine (`core.*`, `mcl_*`) just enough to load
-- smp_core -> smp_store -> smp_combat -> smp_bounty under luajit and
-- drive their callbacks directly with the exact engine signatures.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local H = {}

----------------------------------------------------------------------
-- Path probing (same approach as test_tp.lua): locate dev-tests/ and
-- mods/ relative to the cwd; fall back to the absolute repo path.
----------------------------------------------------------------------

local function readable(p)
	local f = io.open(p, "r")
	if f then f:close() return true end
	return false
end

local MODROOT
for _, c in ipairs({
	"../mods/",
	"mods/",
	"friedcake/mods/",
	"/Volumes/Dara/dev/coconut/friedcake/mods/",
}) do
	if readable(c .. "smp_core/init.lua") then MODROOT = c break end
end
assert(MODROOT, "harness_f10: run from the repo root (or friedcake/, or dev-tests/)")
H.MODROOT = MODROOT

----------------------------------------------------------------------
-- JSON codec (same as test_economy.lua): core.write_json / parse_json
----------------------------------------------------------------------

local function json_encode(v)
	local t = type(v)
	if t == "nil"     then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number"  then
		if v == math.floor(v) then
			return string.format("%.0f", v)
		end
		return tostring(v)
	end
	if t == "string"  then
		return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
	end
	if t == "table" then
		local n = 0
		for k in pairs(v) do
			if type(k) ~= "number" then n = -1; break end
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
			for i = 1, n do p[#p + 1] = json_encode(v[i]) end
			return "[" .. table.concat(p, ",") .. "]"
		end
	end
	return "null"
end

local json_decode
local function skip_ws(s, i)
	while i <= #s do
		local c = s:sub(i, i)
		if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
			i = i + 1
		else
			break
		end
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

function parse_val(s, i)
	i = skip_ws(s, i)
	local c = s:sub(i, i)
	if c == '"' then return parse_str(s, i) end
	if c == '{' then return parse_obj(s, i) end
	if c == '[' then return parse_arr(s, i) end
	if c == '-' or c:match('%d') or c == 't' or c == 'f' or c == 'n' then
		local j = i
		while j <= #s and s:sub(j, j):match('[%-%d%.eE%+a-zA-Z]') do
			j = j + 1
		end
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
	local v, _ = parse_val(s, 1)
	return v
end

----------------------------------------------------------------------
-- Fake time, engine `after`, captures
----------------------------------------------------------------------

local now = 1700000000
os.time = function() return now end

function H.now() return now end
function H.advance(dt) now = now + math.floor(dt) end

local pending = {}

local captures = {
	chat = {},          -- [name] = { msgs }
	all_chat = {},      -- { msgs }
	titles = {},        -- [name] = { texts set on the action bar }
	title_removes = {}, -- [name] = count
	added = {},         -- { {pos=..., name=...} } core.add_item drops
	stats = {},         -- smp_stats.add records
	storage_keys = {},  -- every key written to mod storage (via get_keys)
}
H.captures = captures
H.chat = captures.chat
H.all_chat = captures.all_chat
H.titles = captures.titles
H.title_removes = captures.title_removes
H.added = captures.added
H.stats = captures.stats

local callbacks = {
	punch = {}, hpchange = {}, chatcmd = {}, leave = {}, join = {},
	die = {}, place = {}, punchnode = {}, globalstep = {},
	receive_fields = {}, mods_loaded = {},
}
H.callbacks = callbacks

local commands = {}
local players = {}   -- online
local auth = {}      -- known to the auth database (online or offline)
H.players = players
H.commands = commands

local storage_data = {} -- one mod-storage namespace shared by all mods

local store = {
	get_string = function(_, k) return storage_data[k] or "" end,
	set_string = function(_, k, v) storage_data[k] = v end,
	get_keys = function(_)
		local out = {}
		for k in pairs(storage_data) do out[#out + 1] = k end
		table.sort(out)
		return out
	end,
}

----------------------------------------------------------------------
-- The fake engine
----------------------------------------------------------------------

local function S_factory(_)
	return function(s, ...)
		local args = {...}
		return (s:gsub("@(%d+)", function(n)
			return tostring(args[tonumber(n)] or "")
		end))
	end
end

local core = {}

core.log = function(level, msg) print("[log]", level, msg) end
core.get_translator = S_factory
core.get_current_modname = function()
	return _G.__current_modname or "smp_combat"
end
core.get_modpath = function(m) return MODROOT .. m end
core.settings = {
	get = function() return "" end,
	get_bool = function(_, _, default)
		if default == nil then return true end
		return default
	end,
}
core.get_mod_storage = function() return store end
core.write_json = json_encode
core.parse_json = json_decode
core.chat_send_player = function(name, msg)
	captures.chat[name] = captures.chat[name] or {}
	captures.chat[name][#captures.chat[name] + 1] = msg
end
core.chat_send_all = function(msg)
	captures.all_chat[#captures.all_chat + 1] = msg
end
core.get_player_by_name = function(n) return players[n] end
core.player_exists = function(n) return players[n] ~= nil or auth[n] == true end
core.get_connected_players = function()
	local out = {}
	for _, p in pairs(players) do out[#out + 1] = p end
	return out
end
core.get_player_ip = function(n)
	local p = players[n]
	return p and p._ip or nil
end
core.register_chatcommand = function(name, def) commands[name] = def end
core.registered_chatcommands = commands
core.register_privilege = function() end
core.check_player_privs = function() return true end
core.register_on_punchplayer = function(fn)
	callbacks.punch[#callbacks.punch + 1] = fn
end
core.register_on_player_hpchange = function(fn)
	callbacks.hpchange[#callbacks.hpchange + 1] = fn
end
core.register_on_chatcommand = function(fn)
	callbacks.chatcmd[#callbacks.chatcmd + 1] = fn
end
core.register_on_leaveplayer = function(fn)
	callbacks.leave[#callbacks.leave + 1] = fn
end
core.register_on_joinplayer = function(fn)
	callbacks.join[#callbacks.join + 1] = fn
end
core.register_on_dieplayer = function(fn)
	callbacks.die[#callbacks.die + 1] = fn
end
core.register_on_placenode = function(fn)
	callbacks.place[#callbacks.place + 1] = fn
end
core.register_on_punchnode = function(fn)
	callbacks.punchnode[#callbacks.punchnode + 1] = fn
end
core.register_globalstep = function(fn)
	callbacks.globalstep[#callbacks.globalstep + 1] = fn
end
core.register_on_shutdown = function() end
-- Engine-real: builtin/game/register.lua make_registration() appends,
-- and the engine fires the list after EVERY mod's main chunk has run
-- (src/server/mods.cpp: ServerModManager::loadMods -> on_mods_loaded).
-- smp_combat registers its leave handler here on purpose — the
-- combat-log drop must append after every load-time registration
-- (S07/CB-1), so the harness must reproduce that ordering exactly.
core.register_on_mods_loaded = function(fn)
	callbacks.mods_loaded[#callbacks.mods_loaded + 1] = fn
end
core.register_on_player_receive_fields = function(a, b)
	if type(a) == "function" then
		-- 5.17 single-callback API: fn(player, formname, fields)
		callbacks.receive_fields_any = a
	else
		-- legacy (formname, func) form
		callbacks.receive_fields[a] = b
	end
end
core.after = function(sec, fn)
	pending[#pending + 1] = { at = now + (sec or 0), fn = fn }
end
core.get_gametime = function() return now end
core.get_us_time = function() return 0 end
core.get_worldpath = function() return "/tmp" end
core.request_insecure_environment = function() return nil end
core.DIR_DELIM = "/"
core.show_formspec = function() end
core.close_formspec = function() end
core.get_node = function() return { name = "air" } end
core.get_item_group = function() return 0 end
core.find_nodes_in_area = function(min, max, _)
	return { { x = min.x + 3, y = min.y, z = min.z + 3 } }
end
core.line_of_sight = function() return true end
core.add_item = function(pos, stack)
	captures.added[#captures.added + 1] = {
		pos = { x = pos.x, y = pos.y, z = pos.z },
		name = stack:get_name(),
	}
end
core.registered_items = {}
core.register_on_protection_violation = function() end

core.minetest = core
_G.core = core
_G.minetest = core

----------------------------------------------------------------------
-- Engine globals the mods reference
----------------------------------------------------------------------

_G.vector = {
	offset = function(pos, dx, dy, dz)
		return { x = pos.x + dx, y = pos.y + dy, z = pos.z + dz }
	end,
	new = function(x, y, z)
		if type(x) == "table" then return { x = x.x, y = x.y, z = x.z } end
		return { x = x or 0, y = y or 0, z = z or 0 }
	end,
	distance = function(a, b)
		local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
	equals = function(a, b)
		return a.x == b.x and a.y == b.y and a.z == b.z
	end,
}

_G.mcl_death_drop = {
	registered_dropped_lists = {},
	register_dropped_list = function(inv, listname, drop)
		table.insert(_G.mcl_death_drop.registered_dropped_lists,
			{ inv = inv, listname = listname, drop = drop })
	end,
}
_G.mcl_death_drop.register_dropped_list("PLAYER", "main", true)
_G.mcl_death_drop.register_dropped_list("PLAYER", "craft", true)
_G.mcl_death_drop.register_dropped_list("PLAYER", "armor", true)
_G.mcl_death_drop.register_dropped_list("PLAYER", "offhand", true)

_G.mcl_title = {
	set = function(player, kind, data)
		local n = player:get_player_name()
		captures.titles[n] = captures.titles[n] or {}
		local list = captures.titles[n]
		list[#list + 1] = data.text
	end,
	remove = function(player, _)
		if not player then return end
		local n = player:get_player_name()
		captures.title_removes[n] = (captures.title_removes[n] or 0) + 1
	end,
}

_G.mcl_spawn = {
	get_world_spawn_pos = function(_) return { x = 0, y = 100, z = 0 } end,
}
_G.mcl_worlds = {
	pos_to_dimension = function(_) return "overworld" end,
	is_in_void = function(_) return false, false end,
}
_G.mcl_enchanting = {
	has_enchantment = function() return false end,
}
_G.mcl_armor = {
	update = function() end,
}
_G.smp_stats = {
	add = function(name, key, val)
		captures.stats[#captures.stats + 1] = { name = name, key = key, val = val }
	end,
}

----------------------------------------------------------------------
-- Fake players and entities
----------------------------------------------------------------------

function H.stack(itemname)
	return { get_name = function() return itemname end }
end

function H.player(name, pos, ip)
	local p = {
		_name = name,
		_pos = { x = pos.x, y = pos.y, z = pos.z },
		_ip = ip,
		_meta_ints = {},
		_inv = { main = {}, craft = {}, armor = {}, offhand = {} },
		_attach = nil,
	}
	function p:is_player() return true end
	function p:get_player_name() return self._name end
	function p:get_pos()
		return { x = self._pos.x, y = self._pos.y, z = self._pos.z }
	end
	function p:set_pos(v)
		self._pos = { x = v.x, y = v.y, z = v.z }
	end
	function p:get_meta()
		local ints = self._meta_ints
		return {
			get_int = function(_, k) return ints[k] or 0 end,
			set_int = function(_, k, v) ints[k] = v end,
		}
	end
	function p:get_inventory()
		local inv = self._inv
		return {
			get_list = function(_, n)
				local l = inv[n] or {}
				local out = {}
				for i = 1, #l do out[i] = l[i] end
				return out
			end,
			set_list = function(_, n, v) inv[n] = v end,
		}
	end
	function p:get_luaentity() return nil end
	function p:get_attach() return self._attach end
	function p:set_attach(entity, ...)
		self._attach = entity
	end
	function p:set_detach()
		self._attach = nil
	end
	players[name] = p
	auth[name] = true
	return p
end

-- Offline but known to the auth database.
function H.auth(name) auth[name] = true end

-- An entity such as an arrow or primed TNT: fields become the
-- luaentity's fields (_shooter, _pos, ...).
function H.entity(fields)
	local e = { _fields = fields }
	function e:is_player() return false end
	function e:get_luaentity() return self._fields end
	function e:get_pos()
		local p = self._fields._pos
		if not p then return nil end
		return { x = p.x, y = p.y, z = p.z }
	end
	return e
end

-- Fire the registered join callbacks (IP cache, combat-log flag check).
function H.join(p)
	for _, fn in ipairs(callbacks.join) do fn(p) end
end

-- Fire the on_mods_loaded callbacks in registration order, like the
-- engine does once every mod's main chunk has run (src/server/mods.cpp).
-- Call this AFTER loading the stack (and after registering any fake
-- mod's callbacks that must sit before smp_combat's deferred leave
-- registration — S07/CB-1).
function H.mods_loaded()
	for _, fn in ipairs(callbacks.mods_loaded) do fn() end
end

-- Fire every registered leave handler in registration order — exactly
-- what core.run_callbacks(registered_on_leaveplayers, ...) does
-- (builtin/common/register.lua iterates 1..#list, forward).
-- Returns true when any handler returned truthy.
function H.fire_leave(p)
	local any = false
	for _, fn in ipairs(callbacks.leave) do
		if fn(p) then any = true end
	end
	return any
end

-- Fire every registered globalstep with dtime (store flush + countdown).
function H.step(dtime)
	for _, fn in ipairs(callbacks.globalstep) do fn(dtime) end
end

-- Drain core.after() callbacks that are due, after advancing time.
function H.flush_after()
	local changed = true
	while changed do
		changed = false
		for i = #pending, 1, -1 do
			if pending[i].at <= now then
				local e = table.remove(pending, i)
				e.fn()
				changed = true
			end
		end
	end
end

-- Run the on_chatcommand hooks like builtin/game/chat.lua does:
-- truthy from any hook cancels the command.
function H.dispatch_chatcommand(name, cmd, param)
	for _, fn in ipairs(callbacks.chatcmd) do
		if fn(name, cmd, param) then return true end
	end
	return false
end

function H.last(list)
	return list and list[#list]
end

function H.storage_keys()
	local out = {}
	for k in pairs(storage_data) do out[#out + 1] = k end
	table.sort(out)
	return out
end

-- Empty a capture table in place (closures hold the same reference).
function H.wipe(t)
	if not t then return end
	for i = #t, 1, -1 do t[i] = nil end
end

function H.money(name)
	local rec = smp_store.api.get_player(name)
	return rec and rec.money or 0
end

----------------------------------------------------------------------
-- Mod loading
----------------------------------------------------------------------

function H.load(mod)
	_G.__current_modname = mod
	local f, err = loadfile(MODROOT .. mod .. "/init.lua")
	if not f then error("load " .. mod .. ": " .. tostring(err), 2) end
	local ok, err2 = pcall(f)
	_G.__current_modname = nil
	if not ok then error("run " .. mod .. ": " .. tostring(err2), 2) end
end

-- The full f10 stack, in dependency order. NOTE: this only runs each
-- mod's main chunk. Call H.mods_loaded() afterwards to fire the
-- on_mods_loaded callbacks — the engine always does (mods.cpp), and
-- smp_combat registers its combat-log leave handler from there
-- (S07/CB-1), so a test that needs leave handlers must fire it.
function H.load_stack()
	H.load("smp_core")
	H.load("smp_store")
	H.load("smp_combat")
	H.load("smp_bounty")
end

----------------------------------------------------------------------
-- Assertions: fail fast with a clear message (non-zero exit)
----------------------------------------------------------------------

function H.eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("FAIL %s: expected %q got %q",
			msg or "eq", tostring(expected), tostring(actual)), 2)
	end
end

function H.yes(cond, msg)
	if not cond then
		error("FAIL " .. (msg or "condition"), 2)
	end
end

function H.no(cond, msg)
	if cond then
		error("FAIL " .. (msg or "condition should be false"), 2)
	end
end

function H.done(label)
	print("ALL OK " .. (label or ""))
end

return H
