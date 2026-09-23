-- Smoke test: smp_shards award loop (f06 T1, T2) and /shardsadmin.
--
-- Covers spec/features/f06-shards.md §9:
--   T1: a player online for 10 minutes receives exactly 1 shard and
--       exactly one award message with the observed wording.
--   T2: shards awarded across a restart do not double-count.
--
-- The award message is OBSERVED and asserted byte-for-byte
-- (capital S in "Shard", no terminal full stop).

----------------------------------------------------------------------
-- core stub (pattern: test_economy.lua)
----------------------------------------------------------------------

local S_factory = function(_)
	return function(s, ...)
		local args = {...}
		return (s:gsub("@(%d+)", function(n)
			return tostring(args[tonumber(n)] or "")
		end))
	end
end

local store_data = {}
local store = {
	get_string = function(_, k) return store_data[k] or "" end,
	set_string = function(_, k, v) store_data[k] = v end,
	get_keys = function(_)
		local out = {}
		for k in pairs(store_data) do out[#out + 1] = k end
		return out
	end,
}

local function json_encode(v)
	local t = type(v)
	if t == "nil"     then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number"  then
		if v == math.floor(v) then return string.format("%.0f", v) end
		return tostring(v)
	end
	if t == "string"  then return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
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
			for i = 1, n do p[i] = json_encode(v[i]) end
			return "[" .. table.concat(p, ",") .. "]"
		end
	end
	return "null"
end

local function skip_ws(s, i)
	while i <= #s and s:sub(i, i):match("[%s]") do i = i + 1 end
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
end

local function parse_arr(s, i)
	local t, idx = {}, 1
	i = i + 1
	while true do
		i = skip_ws(s, i)
		if s:sub(i, i) == ']' then return t, i + 1 end
		local v; v, i = parse_val(s, i)
		t[idx] = v; idx = idx + 1
		i = skip_ws(s, i)
		if s:sub(i, i) == ',' then i = i + 1 end
	end
end

function parse_val(s, i)
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

local json_decode = function(s)
	if not s or s == "" then return nil end
	local v = parse_val(s, 1)
	return v
end

local chat = {}          -- name -> { messages }
local commands = {}
local connected = {}     -- list of fake player objects

core = {
	get_mod_storage = function() return store end,
	write_json = json_encode,
	parse_json = json_decode,
	get_translator = S_factory,
	get_current_modname = function() return _G.__current_modname or "smp_shards" end,
	log = function(level, ...)
		if level == "error" then print("[log-error]", ...) end
	end,
	chat_send_player = function(name, msg)
		chat[name] = chat[name] or {}
		chat[name][#chat[name] + 1] = msg
	end,
	request_insecure_environment = function() return nil end,
	settings = {
		get = function() return "" end,
		get_bool = function() return false end,
	},
	get_worldpath = function() return "/tmp" end,
	get_modpath = function(m)
		return "/Volumes/Dara/dev/coconut/friedcake/mods/" .. m
	end,
	DIR_DELIM = "/",
	register_chatcommand = function(name, def) commands[name] = def end,
	registered_chatcommands = commands,
	register_privilege = function() end,
	register_on_shutdown = function() end,
	register_globalstep = function() end,
	register_on_leaveplayer = function() end,
	register_on_joinplayer = function() end,
	get_player_by_name = function(name)
		for _, p in ipairs(connected) do
			if p:get_player_name() == name then return p end
		end
		return nil
	end,
	get_player_names = function()
		local out = {}
		for _, p in ipairs(connected) do out[#out + 1] = p:get_player_name() end
		return out
	end,
	get_connected_players = function() return connected end,
}

local ROOT = "/Volumes/Dara/dev/coconut/friedcake/mods"
local function load(mod)
	_G.__current_modname = mod
	local f, err = loadfile(ROOT .. "/" .. mod .. "/init.lua")
	assert(f, "loadfile " .. mod .. ": " .. tostring(err))
	f()
	_G.__current_modname = nil
end

load("smp_core")
load("smp_store")
load("smp_shards")

local function fake_player(name)
	return { get_player_name = function() return name end }
end

local AWARD = "You earned 1 Shard for playing the server"

----------------------------------------------------------------------
-- T1: 10 minutes of playtime -> exactly 1 shard, exactly 1 message.
----------------------------------------------------------------------

connected = { fake_player("alice") }

for _ = 1, 600 do
	smp_shards.on_step(1)
end

local rec = smp_store.api.get_player("alice")
assert(rec, "T1 record exists")
assert(rec.shards == 1, "T1 exactly one shard: got " .. tostring(rec.shards))
assert(rec.playtime == 600, "T1 playtime persisted: " .. tostring(rec.playtime))
assert(rec.shards_for_playtime == 1, "T1 counter: " .. tostring(rec.shards_for_playtime))
local msgs = chat["alice"] or {}
local count = 0
for _, m in ipairs(msgs) do
	if m == AWARD then count = count + 1 end
end
assert(count == 1, "T1 exactly one award message: got " .. count)
print("T1 ok: 10 minutes -> 1 shard, one verbatim message")

-- The message must be verbatim (capital S, no full stop).
assert(msgs[1] == AWARD, "T1 message verbatim")
assert(msgs[1]:match("Shard"), "T1 capital S")
assert(not msgs[1]:match("%.+$"), "T1 no terminal full stop")

----------------------------------------------------------------------
-- T2: a restart does not double-count.
--
-- Simulate a restart by dropping the in-memory pending map state: the
-- record is already persisted. Continue the same session for another
-- 599 s — floor(1199/600) is still 1, so no new award. Then one more
-- second brings the total to exactly 2 shards / 2 messages.
----------------------------------------------------------------------

connected = {}   -- "server restart": nobody online
connected = { fake_player("alice") }

for _ = 1, 599 do
	smp_shards.on_step(1)
end
rec = smp_store.api.get_player("alice")
assert(rec.shards == 1, "T2 no double count: got " .. tostring(rec.shards))
count = 0
for _, m in ipairs(chat["alice"] or {}) do
	if m == AWARD then count = count + 1 end
end
assert(count == 1, "T2 still one message: got " .. count)

smp_shards.on_step(1)
smp_shards.on_step(1)
rec = smp_store.api.get_player("alice")
assert(rec.shards == 2, "T2 second award after 1200 s: got " .. tostring(rec.shards))
count = 0
for _, m in ipairs(chat["alice"] or {}) do
	if m == AWARD then count = count + 1 end
end
assert(count == 2, "T2 exactly two messages total: got " .. count)
print("T2 ok: no double count across a restart")

----------------------------------------------------------------------
-- Burst: 25 minutes at once pays out 2 shards and 2 messages.
----------------------------------------------------------------------

connected = { fake_player("bob") }
smp_shards.on_step(1500)
rec = smp_store.api.get_player("bob")
assert(rec.shards == 2, "burst: 1500 s -> 2 shards: got " .. tostring(rec.shards))
count = 0
for _, m in ipairs(chat["bob"] or {}) do
	if m == AWARD then count = count + 1 end
end
assert(count == 2, "burst: one message per shard: got " .. count)
print("burst ok")

----------------------------------------------------------------------
-- /shardsadmin
----------------------------------------------------------------------

local cmd = commands["shardsadmin"]
assert(cmd, "/shardsadmin registered")

local r, msg = cmd.func("staff", "")
assert(r == false and msg:find("Usage"), "shardsadmin usage")

r, msg = cmd.func("staff", "give alice 250k")
assert(r == true, "shardsadmin give: " .. tostring(msg))
rec = smp_store.api.get_player("alice")
assert(rec.shards == 250002, "shardsadmin give 250k: got " .. tostring(rec.shards))

r, msg = cmd.func("staff", "take alice 100")
assert(r == true, "shardsadmin take")
rec = smp_store.api.get_player("alice")
assert(rec.shards == 249902, "shardsadmin take 100: got " .. tostring(rec.shards))

r, msg = cmd.func("staff", "take alice 99999999")
assert(r == false and msg:find("does not have"), "shardsadmin overdraft refused")

r, msg = cmd.func("staff", "set bob 42")
assert(r == true, "shardsadmin set")
rec = smp_store.api.get_player("bob")
assert(rec.shards == 42, "shardsadmin set 42: got " .. tostring(rec.shards))

r, msg = cmd.func("staff", "set nobody 1")
assert(r == false and msg:find("does not exist"), "shardsadmin unknown player")

r, msg = cmd.func("staff", "give alice -5")
assert(r == false and msg:find("Invalid amount"), "shardsadmin negative refused")

r, msg = cmd.func("staff", "give alice abc")
assert(r == false and msg:find("Invalid amount"), "shardsadmin non-numeric refused")

-- Ledger entries exist for the admin changes (R3).
local entries = smp_store.api.ledger_for("alice", 1, 50)
local saw_admin = false
for _, e in ipairs(entries) do
	if e.type == "admin" and e.currency == "shards" then saw_admin = true end
end
assert(saw_admin, "shardsadmin ledger entries written")
print("shardsadmin ok")

----------------------------------------------------------------------
-- parse_shard_amount
----------------------------------------------------------------------

local p = smp_shards.parse_shard_amount
assert(p("10") == 10, "parse 10")
assert(p("250k") == 250000, "parse 250k")
assert(p("1.5M") == 1500000, "parse 1.5M (case-insensitive)")
assert(p("1b") == 1000000000, "parse 1b")
local ok2, err2 = p("-5")
assert(ok2 == nil and err2 == "negative", "parse negative refused")
ok2, err2 = p("")
assert(ok2 == nil, "parse empty refused")
print("parse ok")

print("ALL OK")
