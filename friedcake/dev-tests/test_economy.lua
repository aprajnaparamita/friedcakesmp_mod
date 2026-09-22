-- Smoke test: load smp_economy + smp_store + smp_core + smp_admin under
-- a minimal core stub and exercise the /pay command path.

-- Stub core.get_translator with @N substitution so we can see real output.
local S_factory = function(mod)
	return function(s, ...)
		local args = {...}
		return (s:gsub("@(%d+)", function(n)
			return tostring(args[tonumber(n)] or "")
		end))
	end
end

-- In-memory mod storage
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

-- Minimal JSON encoder/decoder. The encoder writes valid JSON; the
-- decoder only handles the shapes smp_store actually round-trips
-- (objects with string keys and primitives or nested objects).
local function json_encode(v)
	local t = type(v)
	if t == "nil"     then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number"  then
		-- Use %.0f for integers, %g for floats, to preserve precision.
		if v == math.floor(v) then
			return string.format("%.0f", v)
		end
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
			for i = 1, n do p[#p + 1] = json_encode(v[i]) end
			return "[" .. table.concat(p, ",") .. "]"
		end
	end
	return "null"
end

local json_decode
-- forward declarations done via the function statements below
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
	local v, _ = parse_val(s, 1)
	return v
end

-- Smoke test the JSON.
do
	local s = json_encode({name="alice", money=12345, friends={"bob","carol"},
		nested={a=1, b=true}})
	local t = json_decode(s)
	assert(t.name == "alice", "encode/decode name")
	assert(t.money == 12345, "encode/decode money")
	assert(t.friends[1] == "bob", "encode/decode array")
	assert(t.nested.b == true, "encode/decode nested bool")
end

core = {
	get_mod_storage = function() return store end,
	write_json = json_encode,
	parse_json = json_decode,
	get_translator = S_factory,
	get_current_modname = function() return _G.__current_modname or "smp_economy" end,
	log = function(...) print("[log]", ...) end,
	chat_send_player = function(name, msg) print("[" .. name .. "]", msg) end,
	request_insecure_environment = function() return nil end,
	settings = {
		get = function(_, k)
			local defaults = {
				store_backend = "mod_storage",
				store_flush_interval = "10",
				store_max_balance = "1000000000000000",
				economy_min_pay = "1",
				economy_max_balance = "1000000000000000",
				economy_flag_threshold = "100000000",
				economy_flag_min_playtime = "7200",
				ledger_page_size = "20",
				economy_tab_complete = "true",
			}
			return defaults[k] or ""
		end,
		get_bool = function(_, k) return true end,
	},
	get_worldpath = function() return "/tmp" end,
	get_modpath = function(m)
		-- Real path so smp_store can loadfile its backends.
		return "/Volumes/Dara/dev/coconut/friedcake/mods/" .. m
	end,
	DIR_DELIM = "/",
	register_chatcommand = function(name, def) end,
	register_privilege = function() end,
	register_on_shutdown = function() end,
	register_on_globalstep = function() end,
	register_on_leaveplayer = function() end,
	get_player_by_name = function() return nil end,
	get_player_names = function() return {} end,
}

-- Sanity: settings.get_bool exists on this core
print("DEBUG: settings.get_bool type =", type(core.settings.get_bool))

-- We need to actually populate registered_chatcommands, so swap in a real one.
local commands = {}
core.register_chatcommand = function(name, def)
	commands[name] = def
end
core.registered_chatcommands = commands

-- Load mod files in dependency order.
local function load(mod)
	local path = "/Volumes/Dara/dev/coconut/friedcake/mods/" .. mod .. "/init.lua"
	_G.__current_modname = mod
	-- smp_store does loadfile("backends/<name>.lua") relative to modpath;
	-- setfenv in the backend file uses modpath from core.get_modpath. We
	-- pass modpath through our stub. Backends are loaded by smp_store via
	-- loadfile(path) where path = modpath .. "/backends/<name>.lua".
	-- Our stub returns "/tmp/mods/<mod>" — we make that real by symlinking.
	_G.__loaded_mod = mod
	local f, err = loadfile(path)
	assert(f, "loadfile " .. mod .. ": " .. tostring(err))
	f()
	_G.__current_modname = nil
	_G.__loaded_mod = nil
end

load("smp_admin")    -- no deps
load("smp_core")     -- no deps (mcl_init/mcl_util not stubbed; only uses core)
load("smp_store")    -- depends on smp_core (ok)
load("smp_economy")  -- depends on smp_store

print("--- /pay T4: self ---")
local pay = commands["pay"]
-- Seed alice so resolve_player_name finds her.
smp_store.api.set_money("alice", 10000, "test", "T4 setup")
smp_store.api.set_money("bob",   10000, "test", "T4 setup")
local r, msg = pay.func("alice", "alice 100")
print("result:", tostring(r), "msg:", tostring(msg))
assert(r == false, "self refused")
assert(msg and msg:lower():find("yourself"), "self msg names 'yourself'")

print("--- /pay T4: unknown ---")
r, msg = pay.func("alice", "no_one 100")
print("result:", tostring(r), "msg:", tostring(msg))
assert(r == false, "unknown refused")

print("--- /pay T5: success ---")
-- Manually seed balances through the store API.
-- Money is in CENTS: 50000 cents = $500, 20000 cents = $200.
smp_store.api.set_money("alice", 50000, "test", "seed")  -- $500
smp_store.api.set_money("bob",   20000, "test", "seed")  -- $200
local a0 = smp_store.api.get_player("alice")
local b0 = smp_store.api.get_player("bob")
print("alice before:", a0 and a0.money, "bob before:", b0 and b0.money)
local before_total = a0.money + b0.money
print("before_total:", before_total)
-- parse_amount treats the input as DOLLARS, so "1" means 100 cents.
r, msg = pay.func("alice", "bob 1")
print("result:", tostring(r), "msg:", tostring(msg))
assert(r == true, "successful pay")
local a = smp_store.api.get_player("alice")
local b = smp_store.api.get_player("bob")
print("alice money:", a.money, "bob money:", b.money)
assert(a.money == 49900, "alice debited (was 50000, sent 100 cents)")
assert(b.money == 20100, "bob credited (was 20000, received 100 cents)")
local after_total = a.money + b.money
assert(after_total == before_total, "supply conserved")

print("--- /bal ---")
local bal = commands["bal"]
local r2, m2 = bal.func("alice", "")
print("alice /bal:", tostring(r2), tostring(m2))
assert(m2:find("499") or m2:find("$ 499"), "bal shows alice balance")

print("--- /ledger alice page 1 ---")
local led = commands["ledger"]
local r3, m3 = led.func("alice", "alice 1")
print("ledger result:", tostring(r3))
print("ledger msg:", tostring(m3))

print("--- T6: large transfer to low-playtime account ---")
local rec = smp_store.api.get_player("bob")
rec.playtime = 100  -- < 7200
smp_store.api.upsert_player(rec)
-- $2M = 200000000 cents. parse_amount("2000000") -> 200000000 cents.
smp_store.api.set_money("alice", 200000000, "test", "T6 seed")  -- $2M
r, msg = pay.func("alice", "bob 1000000")  -- $1M
print("T6 result:", tostring(r), tostring(msg))
assert(r == true, "T6 large transfer succeeds (flagged, not blocked)")

print("--- T10: cap respected ---")
local cap = 1000000000000000
local seed_value = cap - 1
print(string.format("seed_value: %.0f", seed_value))
print(string.format("seed_value == cap-1: %s", tostring(seed_value == cap - 1)))
smp_store.api.set_money("alice", seed_value, "test", "T10 seed")
local r10 = smp_store.api.get_player("alice")
print(string.format("alice money after set: %.0f  cap: %.0f",
	r10 and r10.money or -1, cap))
local applied = smp_store.api.add_money("alice", 100, "test", "T10 over")
print(string.format("T10 applied: %.0f", applied))
local r10b = smp_store.api.get_player("alice")
print(string.format("alice money after add: %.0f", r10b and r10b.money or -1))
assert(applied == 1, "T10 capped to remaining room")

print("--- T9 (smoke): take_money refuses overdraft ---")
-- alice now has 1e15 cents. Attempt to take more than that.
local taken = smp_store.api.take_money("alice", 1000000000000001, "test", "T9")
print("T9 taken:", taken and string.format("%.0f", taken) or "nil")
assert(taken == nil, "T9 refused overdraft")

print("ALL OK")
