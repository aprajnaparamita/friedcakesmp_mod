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

-- Repo root from the script path, so this harness runs from a git
-- worktree checkout too (pattern: dev-tests/test_economy.lua).
local function find_root()
	local script = (arg and arg[0]) or ""
	local prefix = script:match("^(.-)friedcake/dev%-tests/[^/]*$")
	if prefix and prefix ~= "" then
		return (prefix:gsub("/+$", ""))
	end
	return "."
end

local MODS = find_root() .. "/friedcake/mods"

local chat = {}          -- name -> { messages }
local commands = {}
local connected = {}     -- list of fake player objects

-- Engine callbacks the mods under test register. Captured so the tests
-- can fire them exactly as the engine does — with an ObjectRef.
local hooks = {}
local function cap(hook)
	return function(fn)
		hooks[hook] = hooks[hook] or {}
		table.insert(hooks[hook], fn)
	end
end
local function fire(hook, ...)
	for _, fn in ipairs(hooks[hook] or {}) do fn(...) end
end

core = {
	get_mod_storage = function() return store end,
	write_json = json_encode,
	parse_json = json_decode,
	get_translator = S_factory,
	get_current_modname = function() return _G.__current_modname or "smp_shards" end,
	log = function(level, ...)
		if level == "error" then print("[log-error]", ...) end
	end,
	-- STRICT engine stubs (S05/QB-1 harness requirement): the engine runs
	-- luaL_checkstring on both and RAISES on a non-string first argument
	-- (l_env.cpp:648, l_server.cpp:92).
	chat_send_player = function(name, msg)
		if type(name) ~= "string" then
			error(string.format(
				"engine parity: core.chat_send_player expects a string name, got %s",
				type(name)), 2)
		end
		chat[name] = chat[name] or {}
		chat[name][#chat[name] + 1] = msg
	end,
	request_insecure_environment = function() return nil end,
	settings = {
		-- Engine parity: an unset setting yields the DEFAULT, not "".
		-- This matters for S05/SH-2: shards.require_activity now defaults
		-- to TRUE, and a stub that returned false for every key would
		-- silently disable the AFK gate under test.
		get = function(_, _, default) return default or "" end,
		get_bool = function(_, _, default) return default or false end,
	},
	get_worldpath = function() return "/tmp" end,
	get_modpath = function(m) return MODS .. "/" .. m end,
	DIR_DELIM = "/",
	register_chatcommand = function(name, def) commands[name] = def end,
	registered_chatcommands = commands,
	register_privilege = function() end,
	register_on_shutdown = function() end,
	register_globalstep = cap("globalstep"),
	register_on_leaveplayer = cap("leave"),
	register_on_joinplayer = cap("join"),
	register_on_dignode = cap("dig"),
	register_on_placenode = cap("place"),
	register_on_punchplayer = cap("punch"),
	register_on_item_pickup = cap("pickup"),
	register_on_chat_message = cap("chat"),
	register_on_chatcommand = cap("chatcommand"),
	register_on_player_receive_fields = cap("fields"),
	get_player_by_name = function(name)
		if type(name) ~= "string" then
			error(string.format(
				"engine parity: core.get_player_by_name expects a string name, got %s",
				type(name)), 2)
		end
		for _, p in ipairs(connected) do
			if p:get_player_name() == name then return p end
		end
		return nil
	end,
	get_connected_players = function() return connected end,
}

local ROOT = MODS
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

-- Put players online the way the engine does: hand them to the connected
-- list AND fire the join callbacks (S05/SH-2 seeds activity at join, so a
-- restart or a fresh module load must re-seed it too).
local function bring_online(list)
	connected = list
	for _, p in ipairs(list) do fire("join", p) end
	return list
end

local AWARD = "You earned 1 Shard for playing the server"

----------------------------------------------------------------------
-- T1: 10 minutes of playtime -> exactly 1 shard, exactly 1 message.
----------------------------------------------------------------------

bring_online({ fake_player("alice") })

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
-- Simulate a real restart by reloading the module: the persisted record
-- (playtime, shards_for_playtime) is re-read, the in-memory pending map
-- is fresh, and the award logic continues from the persisted counters.
-- This ensures the floor(playtime/interval) - shards_for_playtime formula
-- works across restarts without double-counting.
----------------------------------------------------------------------

-- First, advance to 1199 s (still only 1 shard owed)
bring_online({ fake_player("alice") })
for _ = 1, 599 do
	smp_shards.on_step(1)
end
smp_shards.flush_player("alice")
rec = smp_store.api.get_player("alice")
assert(rec.shards == 1, "T2 pre-restart: 1 shard at 1199 s")
assert(rec.playtime == 1199, "T2 playtime persisted: " .. rec.playtime)
assert(rec.shards_for_playtime == 1, "T2 counter: " .. rec.shards_for_playtime)

-- SIMULATE RESTART: reload the module (clears pending, re-reads settings)
-- The store_data persists across the reload.
package.loaded["smp_shards"] = nil
_G.smp_shards = nil
load("smp_shards")

-- After restart, player is back online. Continue from 1199 s.
bring_online({ fake_player("alice") })
for _ = 1, 599 do  -- advance to 1798 s; floor(1798/600)=2, owed=1
	smp_shards.on_step(1)
end
smp_shards.flush_player("alice")
rec = smp_store.api.get_player("alice")
assert(rec.shards == 2, "T2 no double count after restart: got " .. tostring(rec.shards))
assert(rec.shards_for_playtime == 2, "T2 counter advanced to 2")

-- One more second crosses 1800 s (3 intervals): exactly one more shard.
smp_shards.on_step(1)
smp_shards.on_step(1)
smp_shards.flush_player("alice")
rec = smp_store.api.get_player("alice")
assert(rec.shards == 3, "T2 third award at 1800 s: got " .. tostring(rec.shards))
assert(rec.shards_for_playtime == 3, "T2 counter at 1800 s")
count = 0
for _, m in ipairs(chat["alice"] or {}) do
	if m == AWARD then count = count + 1 end
end
assert(count == 3, "T2 exactly three messages total: got " .. count)
print("T2 ok: no double count across a module reload (restart)")

----------------------------------------------------------------------
-- Burst: 25 minutes at once pays out 2 shards and 2 messages.
----------------------------------------------------------------------

bring_online({ fake_player("bob") })
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

-- Reset alice for admin tests (T2 left her with 3 shards)
do
	local rec = smp_store.api.ensure_player("alice")
	rec.shards = 0
	rec.playtime = 0
	rec.shards_for_playtime = 0
	smp_store.api.upsert_player(rec)
end

local cmd = commands["shardsadmin"]
assert(cmd, "/shardsadmin registered")

local r, msg = cmd.func("staff", "")
assert(r == false and msg:find("Usage"), "shardsadmin usage")

r, msg = cmd.func("staff", "give alice 250k")
assert(r == true, "shardsadmin give: " .. tostring(msg))
rec = smp_store.api.get_player("alice")
assert(rec.shards == 250000, "shardsadmin give 250k: got " .. tostring(rec.shards))

r, msg = cmd.func("staff", "take alice 100")
assert(r == true, "shardsadmin take")
rec = smp_store.api.get_player("alice")
assert(rec.shards == 249900, "shardsadmin take 100: got " .. tostring(rec.shards))

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

----------------------------------------------------------------------
-- S05/SH-2: an award now requires movement or interaction in the window
-- (integrator ruling 2026-09-27). An idle interval is FORFEITED, never
-- banked — otherwise AFK time would be cashed in after the player
-- returns.
----------------------------------------------------------------------

assert(smp_shards.cfg.require_activity == true,
	"SH-2 shards.require_activity defaults to true")

bring_online({ fake_player("carol") })
-- Join seeded the activity stamp; simulate a long AFK by backdating it
-- past the award interval.
smp_shards._last_activity["carol"] = os.time() - smp_shards.cfg.interval - 5
for _ = 1, 600 do
	smp_shards.on_step(1)
end
smp_shards.flush_player("carol")
local rec = smp_store.api.get_player("carol")
assert(rec, "SH-2 carol has a record")
assert(rec.playtime == 600,
	"SH-2 playtime still accrues while idle: " .. tostring(rec.playtime))
assert((rec.shards or 0) == 0,
	"SH-2 no shard for an idle interval: " .. tostring(rec.shards))
assert(rec.shards_for_playtime == 1,
	"SH-2 the idle interval is forfeited, not skipped: counter = "
	.. tostring(rec.shards_for_playtime))
for _, m in ipairs(chat["carol"] or {}) do
	assert(m ~= AWARD, "SH-2 no award message while idle")
end

-- Coming back does NOT cash in the forfeited interval: the next active
-- interval pays exactly one shard, not two.
smp_shards.mark_active("carol")
for _ = 1, 600 do
	smp_shards.on_step(1)
end
smp_shards.flush_player("carol")
rec = smp_store.api.get_player("carol")
assert(rec.shards == 1,
	"SH-2 forfeited time is never banked: got " .. tostring(rec.shards)
	.. " shards (2 would mean the idle interval was paid out later)")
assert(rec.shards_for_playtime == 2, "SH-2 counter at 1200 s")
local carol_awards = 0
for _, m in ipairs(chat["carol"] or {}) do
	if m == AWARD then carol_awards = carol_awards + 1 end
end
assert(carol_awards == 1, "SH-2 exactly one award message: " .. carol_awards)
print("SH-2 ok: idle interval forfeited, active interval paid once")

----------------------------------------------------------------------
-- S05/SH-2 activity inputs: interaction, movement, stillness.
----------------------------------------------------------------------
do
	-- An interaction marks the player active.
	fire("chat", "frank")
	assert(smp_shards.active_in_window("frank", os.time()),
		"SH-2 a chat message marks the player active")

	-- An activity older than the window does not.
	smp_shards._last_activity["idle"] = os.time() - smp_shards.cfg.interval
	assert(not smp_shards.active_in_window("idle", os.time()),
		"SH-2 activity older than the interval is inactive")
	-- Neither does never having been active.
	assert(not smp_shards.active_in_window("never_seen", os.time()),
		"SH-2 a player never seen active is inactive")

	-- Movement: the first sample only seeds the position; a second
	-- sample that moved far enough marks the player active.
	local mover = fake_player("mover")
	mover.get_pos = function() return { x = 0, y = 0, z = 0 } end
	smp_shards._sample_position(mover, "mover")
	assert(not smp_shards.active_in_window("mover", os.time()),
		"SH-2 the first position sample only seeds")
	mover.get_pos = function() return { x = 5, y = 0, z = 0 } end
	smp_shards._sample_position(mover, "mover")
	assert(smp_shards.active_in_window("mover", os.time()),
		"SH-2 moving marks the player active")

	-- Standing still (a sub-epsilon wobble) does not.
	local stander = fake_player("stander")
	stander.get_pos = function() return { x = 1, y = 0, z = 0 } end
	smp_shards._sample_position(stander, "stander")
	stander.get_pos = function() return { x = 1.05, y = 0, z = 0 } end
	smp_shards._sample_position(stander, "stander")
	assert(not smp_shards.active_in_window("stander", os.time()),
		"SH-2 standing still does not mark the player active")

	-- Every interaction callback the mod registers is captured.
	for _, hook in ipairs({ "dig", "place", "punch", "pickup", "chat",
			"chatcommand", "fields", "join", "leave" }) do
		assert(hooks[hook] and #hooks[hook] > 0,
			"SH-2 core.register_on_" .. hook .. " callback registered")
	end
	print("SH-2 activity ok: interaction, movement, stillness, callbacks")
end

----------------------------------------------------------------------
-- S05/SH-1b: the leave callback is handed an ObjectRef, not a name.
----------------------------------------------------------------------
do
	local erin = fake_player("erin")
	bring_online({ erin })
	for _ = 1, 10 do
		smp_shards.on_step(1)      -- under the 30 s flush interval
	end
	local before = smp_store.api.get_player("erin")
	assert((before and before.playtime or 0) == 0,
		"SH-1b playtime not flushed yet")

	fire("leave", erin)           -- ObjectRef, exactly like the engine
	local after = smp_store.api.get_player("erin")
	assert(after and after.playtime == 10,
		"SH-1b leaving with an ObjectRef flushes the playtime: got "
		.. tostring(after and after.playtime))
	assert(smp_shards._last_activity["erin"] == nil,
		"SH-1b the activity stamp is cleared on leave")
	print("SH-1b ok: leave flushes with an ObjectRef")
end

print("ALL OK")
