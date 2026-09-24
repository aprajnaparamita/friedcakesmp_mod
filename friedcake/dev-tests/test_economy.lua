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

-- Repo root from the script path so this harness also runs from a git
-- worktree checkout (E-fix: the paths used to be hardcoded to
-- /Volumes/Dara/dev/coconut, so the suite silently tested a *different*
-- checkout). Pattern: dev-tests/test_orders.lua, dev-tests/test_config_mirror.lua.
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
	return "."
end

local ROOT = find_root()
local MODS = ROOT .. "/friedcake/mods"

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
		print(string.format("FAIL: %s — expected %s got %s",
			tostring(msg), tostring(b), tostring(a)))
	end
end
local function has(haystack, needle, msg)
	ok(type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil,
		msg or ("message contains " .. tostring(needle)))
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

-- Harness state the economy mod's lifecycle hooks need (E-02, E-04, E-07).
local join_handlers = {}   -- core.register_on_joinplayer callbacks
local leave_handlers = {}  -- core.register_on_leaveplayer callbacks
local gametime = 1000      -- core.get_gametime clock (R9 cooldown uses it)
local privs_of = {}        -- [name] = { priv = true, ... }
local online = {}          -- [name] = player object
local sent = {}            -- [name] = { msg, ... } from core.chat_send_player
local settings_values = {} -- [key] = raw string, mutable so tests can move cfg

local function advance(seconds) gametime = gametime + (seconds or 1) end

-- Reset the `/pay` cooldown without waiting on the clock (the mod ships
-- this as a test hook; production code never calls it).
local function clear_pay_cooldown(name)
	if smp_economy and smp_economy._reset_pay_cooldown then
		smp_economy._reset_pay_cooldown(name)
	end
end

core = {
	get_mod_storage = function() return store end,
	write_json = json_encode,
	parse_json = json_decode,
	get_translator = S_factory,
	get_current_modname = function() return _G.__current_modname or "smp_economy" end,
	log = function(...) print("[log]", ...) end,
	chat_send_player = function(name, msg)
		print("[" .. name .. "]", msg)
		sent[name] = sent[name] or {}
		sent[name][#sent[name] + 1] = msg
	end,
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
			-- Dotted spellings first: that is how production code reads them.
			if settings_values[k] ~= nil then return settings_values[k] end
			return defaults[k] or ""
		end,
		get_bool = function(_, k, default)
			local v = settings_values[k]
			if v == nil then return default end
			return v == "true" or v == "1"
		end,
	},
	get_worldpath = function() return "/tmp" end,
	get_modpath = function(m)
		-- Real path so smp_store can loadfile its backends.
		return MODS .. "/" .. m
	end,
	DIR_DELIM = "/",
	register_privilege = function() end,
	register_on_shutdown = function() end,
	-- B4-1 (00-P0-blockers.md): this fake stands in for the globalstep
	-- hook smp_store registers at load — spelled with the engine's real
	-- name below, which is the only spelling this guard allows. It must
	-- NOT be deleted until B1-1 (the integrator-owned globalstep
	-- registration in smp_store) is fixed — see §10 of
	-- spec/features/f01-economy-core.md.
	register_globalstep = function() end,
	register_on_leaveplayer = function(fn)
		leave_handlers[#leave_handlers + 1] = fn
	end,
	register_on_joinplayer = function(fn)
		join_handlers[#join_handlers + 1] = fn
	end,
	get_gametime = function() return gametime end,
	get_player_privs = function(name) return privs_of[name] or {} end,
	get_player_by_name = function(name) return online[name] end,
	get_connected_players = function()
		local out = {}
		for _, p in pairs(online) do out[#out + 1] = p end
		return out
	end,
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
	local path = MODS .. "/" .. mod .. "/init.lua"
	_G.__current_modname = mod
	-- smp_store does loadfile("backends/<name>.lua") relative to modpath;
	-- setfenv in the backend file uses modpath from core.get_modpath. We
	-- pass modpath through our stub.
	_G.__loaded_mod = mod
	local f, err = loadfile(path)
	assert(f, "loadfile " .. mod .. ": " .. tostring(err))
	f()
	_G.__current_modname = nil
	_G.__loaded_mod = nil
end

----------------------------------------------------------------------
-- Counterpart-mod stubs: REAL APIs only (never an engine name the
-- engine lacks). E-01 wires `smp_social.blocks`; E-22 reads and writes
-- f12's `smp_settings.get/set/store_get` accessor trio.
----------------------------------------------------------------------

-- f11 §6 / §4.3: `blocks(a, b)` is `is_blocked(a,b) OR ignores(a,b)`,
-- while `blocks_only(a, b)` is the BLOCK graph alone. Both sets are keyed
-- "<actor>|<target>" and start empty, so `/pay` in the default state is
-- unblocked. (V-48, ruled 2026-09-25: payments consult `blocks_only` —
-- ignore must NOT refuse a payment.)
local block_pairs = {}
local ignore_pairs = {}

smp_social = {}
function smp_social.blocks(a, b)
	local k = tostring(a) .. "|" .. tostring(b)
	return block_pairs[k] == true or ignore_pairs[k] == true
end
function smp_social.blocks_only(a, b)
	return block_pairs[tostring(a) .. "|" .. tostring(b)] == true
end
function smp_social.ignores(a, b)
	return ignore_pairs[tostring(a) .. "|" .. tostring(b)] == true
end

-- f12 §5 accessor semantics: an unregistered id answers nil from `get`
-- and false from `set` when nothing is stored, but a stored value is
-- readable (a newer build's setting). `eco.pay_accept` is NOT registered
-- by f12 yet (f12 §10), which is the state the migration in
-- smp_economy's join handler has to cope with.
smp_settings = {}
local settings_store = {}   -- [name] = { [id] = value }
function smp_settings.store_get(name, id)
	local t = settings_store[name]
	return t and t[id] or nil
end
function smp_settings.store_set(name, id, value)
	settings_store[name] = settings_store[name] or {}
	settings_store[name][id] = value
	return true
end
function smp_settings.get(name, id)
	return smp_settings.store_get(name, id)
end
function smp_settings.set(_name, _id, _value)
	return false -- unregistered id: refused, exactly like the real f12
end

local function make_player(name)
	local p = { _name = name }
	function p:get_player_name() return self._name end
	return p
end

local function set_online(name)
	online[name] = make_player(name)
	return online[name]
end

local function set_offline(name)
	online[name] = nil
end

local function join(name)
	local p = online[name] or make_player(name)
	for _, fn in ipairs(join_handlers) do fn(p) end
end

local function leave(name)
	for _, fn in ipairs(leave_handlers) do fn(name) end
end

local function privs(name, ...)
	local set = {}
	for _, p in ipairs({ ... }) do set[p] = true end
	privs_of[name] = set
	return set
end

local function ledger_rows(actor)
	local entries = smp_store.api.ledger_for(actor, 1, 1000)
	return #entries
end

local function ledger_total(a, b)
	return ledger_rows(a) + ledger_rows(b)
end

local function money(name)
	local r = smp_store.api.get_player(name)
	return r and r.money or 0
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
local rows_before = ledger_total("alice", "bob")
-- R9: the previous refused attempts never armed the window; this one
-- will, so every later /pay in this file clears it first.
clear_pay_cooldown("alice")
-- parse_amount treats the input as DOLLARS, so "1" means 100 cents.
r, msg = pay.func("alice", "bob 1")
print("result:", tostring(r), "msg:", tostring(msg))
assert(r == true, "successful pay")
-- T5 (E-23): exactly two rows — one debit, one credit — both `pay`.
local rows_after = ledger_total("alice", "bob")
eq(rows_after - rows_before, 2, "T5 ledger delta is exactly 2")
do
	for _, actor in ipairs({ "alice", "bob" }) do
		local entries = smp_store.api.ledger_for(actor, 1, 1000)
		eq(entries[1] and entries[1].type, "pay",
			"T5 newest " .. actor .. " row has reason 'pay'")
	end
end
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
-- E-07: the command registers WITHOUT a privs table (Luanti's table is
-- an AND gate) and checks the OR inside func. Give alice the moderator
-- privilege so this read succeeds.
privs("alice", "smp_moderator")
local led = commands["ledger"]
ok(commands["ledger"].privs == nil,
	"E-07 /ledger registers no AND-gate privs table")
local r3, m3 = led.func("alice", "alice 1")
print("ledger result:", tostring(r3))
print("ledger msg:", tostring(m3))
assert(r3 == true, "moderator may read /ledger")

print("--- T6: large transfer to low-playtime account ---")
local rec = smp_store.api.get_player("bob")
rec.playtime = 100  -- < 7200
smp_store.api.upsert_player(rec)
-- $2M = 200000000 cents. parse_amount("2000000") -> 200000000 cents.
smp_store.api.set_money("alice", 200000000, "test", "T6 seed")  -- $2M
clear_pay_cooldown("alice")
local flags_before = #smp_admin.flags()
r, msg = pay.func("alice", "bob 1000000")  -- $1M
print("T6 result:", tostring(r), tostring(msg))
assert(r == true, "T6 large transfer succeeds (flagged, not blocked)")
-- E-24 / D9: the flag is observable through smp_admin's ring buffer.
local flags = smp_admin.flags()
eq(#flags, flags_before + 1, "T6 exactly one new staff-review flag")
local last = flags[#flags]
ok(last and last.kind == "large_transfer_to_new_account",
	"T6 flag kind is large_transfer_to_new_account")
has(last and last.detail or "", "alice", "T6 flag detail names the sender")

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

----------------------------------------------------------------------
-- T7 (E-25): /pay prefix resolution
--
-- The OBSERVED dropdown [F0089] is the client's own completion over the
-- connected-player list; the server side can only resolve the prefix the
-- player typed. That limitation is documented at the resolver
-- (smp_economy/init.lua, E-10) — this drives the resolver itself.
----------------------------------------------------------------------

print("--- T7 (E-25): /pay prefix resolution ---")
for _, n in ipairs({ "carl", "carla" }) do
	smp_store.api.set_money(n, 10000, "test", "T7 setup")
end

clear_pay_cooldown("alice")
local bob_before = money("bob")
r, msg = pay.func("alice", "b 1")            -- unique prefix
ok(r == true, "T7 unique prefix resolves")
eq(money("bob"), bob_before + 100, "T7 the unique prefix paid bob")

clear_pay_cooldown("alice")
local carl_before = money("carl")
r, msg = pay.func("alice", "ca 1")           -- carl AND carla
ok(r == false, "T7 ambiguous prefix refused")
has(msg, "does not exist", "T7 ambiguous prefix answers unknown-player")
eq(money("carl"), carl_before, "T7 ambiguous prefix moved nothing")
eq(money("bob"), bob_before + 100, "T7 ambiguous prefix moved nothing (bob)")

clear_pay_cooldown("alice")
r, msg = pay.func("alice", "carla 1")         -- exact name wins over prefix
ok(r == true, "T7 exact name beats its own ambiguity")

clear_pay_cooldown("alice")
r, msg = pay.func("alice", "BOB 1")           -- case-insensitive
ok(r == true, "T7 matching is case-insensitive")
eq(money("bob"), bob_before + 200, "T7 the case-insensitive hit paid bob")

----------------------------------------------------------------------
-- R9 (E-04): /pay rate limit — one per second, armed only by success
----------------------------------------------------------------------

print("--- R9 (E-04): /pay rate limit ---")
clear_pay_cooldown("alice")
local r9_rows = ledger_total("alice", "bob")
local r9_bob = money("bob")
r, msg = pay.func("alice", "bob 1")
ok(r == true, "R9 the first pay succeeds")
-- The first pay armed the window; no clear here on purpose.
r, msg = pay.func("alice", "bob 1")
ok(r == false, "R9 a second pay inside the window is refused")
has(msg, "Too fast, slow down", "R9 refusal string")
eq(ledger_total("alice", "bob"), r9_rows + 2,
	"R9 the refused pay wrote no ledger rows")
eq(money("bob"), r9_bob + 100, "R9 the refused pay moved no money")
advance(1)
r, msg = pay.func("alice", "bob 1")
ok(r == true, "R9 a pay after the window succeeds")
eq(ledger_total("alice", "bob"), r9_rows + 4, "R9 the later pay wrote two rows")

----------------------------------------------------------------------
-- E-01: blocks wiring (X9 /pay leg)
----------------------------------------------------------------------

print("--- E-01: /pay honours smp_social.blocks ---")
block_pairs["bob|alice"] = true             -- bob has blocked alice
local e1_alice, e1_bob = money("alice"), money("bob")
local e1_rows = ledger_total("alice", "bob")
clear_pay_cooldown("alice")
r, msg = pay.func("alice", "bob 1")
ok(r == false, "E-01 a recipient who blocked the payer is refused")
has(msg, "cannot send money", "E-01 refusal names the recipient only")
ok(not (msg or ""):lower():find("block"), "E-01 refusal reveals no privacy rule")
eq(money("alice"), e1_alice, "E-01 sender balance unchanged")
eq(money("bob"), e1_bob, "E-01 recipient balance unchanged")
eq(ledger_total("alice", "bob"), e1_rows, "E-01 no ledger rows written")
block_pairs["bob|alice"] = nil

block_pairs["alice|bob"] = true             -- the other direction
clear_pay_cooldown("alice")
r, msg = pay.func("alice", "bob 1")
ok(r == false, "E-01 a payer who blocked the recipient is refused too")
block_pairs["alice|bob"] = nil

----------------------------------------------------------------------
-- V-48: payments are BLOCK-only — `/ignore` does not refuse them
-- (f11 §4.3 payments row; ruled 2026-09-25, the guard consults
-- `blocks_only()`).
----------------------------------------------------------------------

print("--- V-48: ignore does not refuse /pay ---")
ignore_pairs["bob|alice"] = true            -- bob ignores alice
ignore_pairs["alice|bob"] = true            -- and alice ignores bob
ok(smp_social.blocks("bob", "alice") == true,
	"V-48 blocks() folds ignore in (chat/messages predicate)")
ok(smp_social.blocks_only("bob", "alice") == false,
	"V-48 blocks_only() does not (payments predicate)")
local v48_alice, v48_bob = money("alice"), money("bob")
local v48_rows = ledger_total("alice", "bob")
clear_pay_cooldown("alice")
r, msg = pay.func("alice", "bob 1")
ok(r == true, "V-48 a payment between mutual ignorers SUCCEEDS")
eq(money("alice"), v48_alice - 1, "V-48 the payment moved 1 cent")
eq(ledger_total("alice", "bob"), v48_rows + 2, "V-48 it wrote two rows")
ignore_pairs["bob|alice"] = nil
ignore_pairs["alice|bob"] = nil

----------------------------------------------------------------------
-- E-02: offline-recipient summary (§4.2.4) — both halves
----------------------------------------------------------------------

print("--- E-02: offline recipient summary on join ---")
set_online("bob")
local e2_carl = money("carl")
clear_pay_cooldown("alice")
r = pay.func("alice", "bob 1")
ok(r == true, "E-02 pay to an ONLINE recipient succeeds")
has(sent["bob"][#sent["bob"]] or "", "received", "E-02 the online recipient is notified")
set_offline("bob")

clear_pay_cooldown("alice")
local e2_carl_rows = ledger_rows("carl")
r = pay.func("alice", "carl 1")
ok(r == true, "E-02 pay to an OFFLINE recipient succeeds")
eq(ledger_rows("carl"), e2_carl_rows + 1, "E-02 the credit lands in the ledger")
eq(money("carl"), e2_carl + 100, "E-02 the offline recipient was credited")
ok(sent["carl"] == nil, "E-02 nothing is chat-sent while the recipient is offline")

sent["carl"] = {}
join("carl")
eq(#(sent["carl"] or {}), 1, "E-02 exactly one summary line on join")
has(sent["carl"][1] or "", "Payments received while you were offline",
	"E-02 summary header")
has(sent["carl"][1] or "", "alice", "E-02 summary names the sender")

sent["carl"] = {}
join("carl")
eq(#(sent["carl"] or {}), 0, "E-02 read-and-clear: the second join is silent")

----------------------------------------------------------------------
-- E-22: recipient toggle chain settings -> record.social -> default ON
----------------------------------------------------------------------

print("--- E-22: recipient payment toggle ---")
clear_pay_cooldown("alice")
r, msg = pay.func("alice", "carla 1")
ok(r == true, "E-22 nil settings value + unset record defaults to ON")

local rec_bob = smp_store.api.ensure_player("bob")
rec_bob.social = rec_bob.social or {}
rec_bob.social.pay_accept = false
smp_store.api.upsert_player(rec_bob)
clear_pay_cooldown("alice")
r, msg = pay.func("alice", "bob 1")
ok(r == false, "E-22 an explicit OFF in the record refuses an offline recipient")
has(msg, "not accepting payments", "E-22 OFF refusal string")

local tog = commands["paytoggle"]
local tr = tog.func("bob", "")
ok(tr == true, "E-22 /paytoggle succeeds")
clear_pay_cooldown("alice")
r = pay.func("alice", "bob 1")
ok(r == true, "E-22 /paytoggle round-trip accepts again")

-- A stored settings value outranks the record (f12 §5 semantics), which
-- is the branch that only opens once f12 registers `eco.pay_accept`.
smp_settings.store_set("bob", "eco.pay_accept", "OFF")
clear_pay_cooldown("alice")
r = pay.func("alice", "bob 1")
ok(r == false, "E-22 a readable settings value wins over the record")
settings_store["bob"] = nil
clear_pay_cooldown("alice")
r = pay.func("alice", "bob 1")
ok(r == true, "E-22 clearing the settings value falls back to the record")

----------------------------------------------------------------------
-- E-07: /ledger OR-privs, /eco stays admin-only
----------------------------------------------------------------------

print("--- E-07: /ledger admin OR moderator ---")
smp_store.api.set_money("dana", 100000, "test", "E-07 setup")
privs("mod_only", "smp_moderator")
privs("admin_only", "smp_admin")
privs("plain", "shout")
ok(commands["ledger"].privs == nil, "E-07 /ledger registers no privs table")

r, msg = led.func("mod_only", "dana 1")
ok(r == true, "E-07 a moderator-only holder may read the ledger")
r, msg = led.func("admin_only", "dana 1")
ok(r == true, "E-07 an admin holder may read the ledger")
r, msg = led.func("plain", "dana 1")
ok(r == false, "E-07 a holder of neither is denied")
eq(msg,
	"You don't have permission to run this command (missing privileges: smp_admin, smp_moderator).",
	"E-07 denial is the engine's verbatim sentence")
r, msg = led.func("", "dana 1")
ok(r == true, "E-07 the server console is allowed")
ok(type(commands["eco"].privs) == "table"
	and commands["eco"].privs.smp_admin == true,
	"E-07 /eco remains smp_admin-only")
privs("plain")   -- drop the fixture

----------------------------------------------------------------------
-- E-08: /eco reset consumes <amount>
----------------------------------------------------------------------

print("--- E-08: /eco reset consumes <amount> ---")
local eco = commands["eco"]
smp_store.api.set_money("dana", 999999, "test", "E-08 setup")
r, msg = eco.func("root", "reset dana 12.34")
ok(r == true, "E-08 /eco reset <player> <amount> succeeds")
eq(money("dana"), 1234, "E-08 reset sets the balance to the amount, not 0")
do
	local newest = smp_store.api.ledger_for("dana", 1, 1)[1]
	eq(newest and newest.ref, "eco:reset:root", "E-08 reset writes its ledger reason")
end
r, msg = eco.func("root", "reset dana")
ok(r == false, "E-08 reset with no amount is rejected")
eq(money("dana"), 1234, "E-08 a rejected reset changes nothing")
r, msg = eco.func("root", "reset dana -5")
ok(r == false, "E-08 reset with an invalid amount is rejected")
eq(money("dana"), 1234, "E-08 an invalid amount changes nothing")

----------------------------------------------------------------------
-- E-18: economy.max_balance is a live, enforced key
----------------------------------------------------------------------

print("--- E-18: economy.max_balance enforced ---")
settings_values["economy.max_balance"] = "10000"
commands["smp"].func("root", "reload")
smp_store.api.set_money("dana", 0, "test", "E-18 setup")
r, msg = eco.func("root", "give dana 1000000")
ok(r == true, "E-18 /eco give succeeds")
eq(money("dana"), 10000, "E-18 give clamps to economy.max_balance")
has(msg, "capped", "E-18 the clamp is reported to the admin")
eq(smp_economy.give("dana", 5000, "test", "E-18 at cap"), 0,
	"E-18 give at the cap credits nothing")
eq(smp_economy.get("dana"), 10000, "E-18 get() reads the capped balance")
settings_values["economy.max_balance"] = nil
commands["smp"].func("root", "reload")

----------------------------------------------------------------------
-- E-11 / E-13: every player-facing string is translated and period-free
----------------------------------------------------------------------

print("--- E-11 / E-13: string audit ---")
do
	local raw = io.open(MODS .. "/smp_economy/init.lua", "r"):read("*a")
	local untranslated = 0
	for line in raw:gmatch("[^\n]+") do
		-- A bare return-false/true message that is not an S(...) call.
		if line:match("return false, %[\"") or line:match("return true, %[\"") then
			untranslated = untranslated + 1
			print("E-11 untranslated: " .. line)
		end
	end
	eq(untranslated, 0, "E-11 no raw player-facing string in smp_economy")
	-- E-13: the engine-verbatim denial keeps its full stop; nothing else
	-- that this mod invents may end in one.
	for s in raw:gmatch('S%("([^"]*)"') do
		local verbatim = s:find("permission to run this command") ~= nil
		if s:find("%.$") and not verbatim then
			failed = failed + 1
			print("FAIL: E-13 invented string ends in a full stop: " .. s)
		end
	end
end

----------------------------------------------------------------------
-- Leave handler smoke (the lifecycle pair of E-02)
----------------------------------------------------------------------

local leave_ok = pcall(leave, "alice")
ok(leave_ok, "leave handler runs")

----------------------------------------------------------------------
-- T8 (E-26): balances survive a restart
----------------------------------------------------------------------

print("--- T8 (E-26): balances survive a restart ---")
local t8_money = money("alice")
local t8_alice_rows = ledger_rows("alice")
local t8_bob_rows = ledger_rows("bob")
-- Re-instantiate the store driver over the SAME storage stub: that is
-- exactly what a restart does, because the mod_storage driver re-reads
-- `core.get_mod_storage()` when smp_store boots.
--
-- The crash half of T8 ("loses at most store.flush_interval") is
-- satisfied a fortiori today: the mod_storage backend is write-through,
-- so there is no buffer to lose — `flush()` is a documented no-op
-- (E-17, escalated). A true crash simulation needs R12's pending marker
-- (E-06), which is integrator-owned, so it is out of scope here.
load("smp_store")
eq(money("alice"), t8_money, "T8 balance survives the restart")
eq(ledger_rows("alice"), t8_alice_rows, "T8 ledger survives the restart")
eq(ledger_rows("bob"), t8_bob_rows, "T8 counterparty ledger survives the restart")
ok(smp_store._backend_name == "mod_storage", "T8 the same backend comes back")

----------------------------------------------------------------------
-- E-09: /smp test dispatcher + the in-mod suite
----------------------------------------------------------------------

print("--- E-09: /smp test ---")
local smp_cmd = commands["smp"]
ok(smp_cmd ~= nil, "E-09 /smp registered")
sent["root"] = {}
local ran, ret = pcall(smp_cmd.func, "root", "test smp_economy")
ok(ran, "E-09 /smp test runs to completion (no 'attempt to call a nil value')")
eq(ret, true, "E-09 /smp test reports success")
local out = table.concat(sent["root"] or {}, "\n")
ok(not out:find("nil value"), "E-09 no nil-call in the output")
has(out, "Passed:", "E-09 test output reaches the invoker")
local unknown_ran, unknown_ret = pcall(smp_cmd.func, "root", "test smp_nope")
ok(unknown_ran and unknown_ret == false, "E-09 an unknown target is refused")

-- Direct run of the in-mod suite so failures are counted, not just shown.
print("== in-game test suite (mods/smp_economy/test.lua) ==")
do
	local chunk, lerr = loadfile(MODS .. "/smp_economy/test.lua")
	ok(chunk ~= nil, "smp_economy/test.lua loads: " .. tostring(lerr))
	if chunk then
		local good, res = pcall(chunk)
		ok(good, "smp_economy/test.lua runs: " .. tostring(res))
		if good and type(res) == "table" then
			eq(res.failed, 0, "in-mod suite has no failures (" ..
				tostring(res.passed) .. " passed)")
			for _, l in ipairs(res.lines or {}) do print("  " .. l) end
		end
	end
end

----------------------------------------------------------------------
print(string.format("passed=%d failed=%d", passed, failed))
if failed > 0 then
	print("TEST_ECONOMY FAILED")
	os.exit(1)
end
print("ALL OK")
