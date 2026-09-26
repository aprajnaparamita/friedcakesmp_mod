-- Standalone smoke test for smp_admin (rulings D9 + D10) — runs under
-- plain luajit, no engine. Stubs `core`, then loads smp_admin and
-- exercises the ten moderation cases: the flag ring buffer (T1–T4), the
-- mute trio (T5–T8) and /mute + /unmute (T9–T10). The in-mod suite
-- (friedcake/mods/smp_admin/test.lua) runs last, inside the same stub.
--
-- Run: luajit friedcake/dev-tests/test_admin.lua
-- Exits non-zero on any failure (tools/agent-flow.sh test).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

-- Locate the repository root from the script path so the harness also
-- works from a git worktree checkout (same approach as test_ranks.lua).
local function find_root()
	local script = (arg and arg[0]) or ""
	local prefix = script:match("^(.-)friedcake/dev%-tests/[^/]*$")
	if prefix and prefix ~= "" then
		return (prefix:gsub("/+$", ""))
	end
	local probe = io.open("friedcake/mods/modpack.conf", "r")
	if probe then
		probe:close()
		return "."
	end
	error("cannot locate the repo root: run from the repo root or pass an absolute script path")
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
-- Minimal JSON codec (same shape as test_ranks.lua / test_economy.lua):
-- the flag ring round-trips through core.write_json / core.parse_json.
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
	if t == "string" then
		return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
			local esc = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
				['\r'] = '\\r', ['\t'] = '\\t' }
			return esc[c] or string.format("\\u%04x", c:byte())
		end) .. '"'
	end
	if t == "table" then
		local has_str, n = false, 0
		for k in pairs(v) do
			if type(k) == "string" then has_str = true
			elseif type(k) == "number" and k > n then n = k end
		end
		if not has_str and n > 0 then
			local arr = true
			for i = 1, n do
				if v[i] == nil then arr = false break end
			end
			if arr then
				local p = {}
				for i = 1, n do p[i] = json_encode(v[i]) end
				return "[" .. table.concat(p, ",") .. "]"
			end
		end
		local p = {}
		for k, vv in pairs(v) do
			p[#p + 1] = json_encode(tostring(k)) .. ":" .. json_encode(vv)
		end
		return "{" .. table.concat(p, ",") .. "}"
	end
	return "null"
end

local json_decode
do
	local s, i = "", 1
	local function ws()
		local c = s:sub(i, i)
		while c == " " or c == "\t" or c == "\n" or c == "\r" do
			i = i + 1
			c = s:sub(i, i)
		end
	end
	local function parse_string()
		i = i + 1 -- opening quote
		local out = {}
		while true do
			local c = s:sub(i, i)
			if c == "" then error("unterminated string") end
			if c == '"' then i = i + 1 break end
			if c == "\\" then
				local nc = s:sub(i + 1, i + 1)
				i = i + 2
				if     nc == "n" then out[#out + 1] = "\n"
				elseif nc == "t" then out[#out + 1] = "\t"
				elseif nc == "r" then out[#out + 1] = "\r"
				elseif nc == "u" then
					out[#out + 1] = string.char(tonumber(s:sub(i, i + 3), 16) % 256)
					i = i + 4
				else out[#out + 1] = nc end
			else
				out[#out + 1] = c
				i = i + 1
			end
		end
		return table.concat(out)
	end
	local parse_value
	local function parse_object()
		i = i + 1 -- {
		local out = {}
		ws()
		if s:sub(i, i) == "}" then i = i + 1 return out end
		while true do
			ws()
			if s:sub(i, i) ~= '"' then error("expected key at " .. i) end
			local k = parse_string()
			ws()
			if s:sub(i, i) ~= ":" then error("expected : at " .. i) end
			i = i + 1
			out[k] = parse_value()
			ws()
			local c = s:sub(i, i)
			if c == "," then i = i + 1
			elseif c == "}" then i = i + 1 return out
			else error("expected , or } at " .. i) end
		end
	end
	local function parse_array()
		i = i + 1 -- [
		local out = {}
		ws()
		if s:sub(i, i) == "]" then i = i + 1 return out end
		while true do
			out[#out + 1] = parse_value()
			ws()
			local c = s:sub(i, i)
			if c == "," then i = i + 1
			elseif c == "]" then i = i + 1 return out
			else error("expected , or ] at " .. i) end
		end
	end
	parse_value = function()
		ws()
		local c = s:sub(i, i)
		if c == "{" then return parse_object() end
		if c == "[" then return parse_array() end
		if c == '"' then return parse_string() end
		if s:sub(i, i + 3) == "true"  then i = i + 4 return true end
		if s:sub(i, i + 4) == "false" then i = i + 5 return false end
		if s:sub(i, i + 3) == "null"  then i = i + 4 return nil end
		local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
		if not num or num == "" then error("unexpected char at " .. i) end
		i = i + #num
		return tonumber(num)
	end
	json_decode = function(str)
		if type(str) ~= "string" or str == "" then return nil end
		s, i = str, 1
		return parse_value()
	end
end

----------------------------------------------------------------------
-- Engine stub — only the names smp_admin/init.lua touches (all present
-- in dev-tests/engine_api_surface.txt; test_engine_apis.lua checks).
----------------------------------------------------------------------

local store_data = {}   -- mod_storage contents ("" removes a key, as engine)
local logs    = {}      -- { level, msg } records
local chats   = {}      -- player -> messages
local privs   = {}      -- player -> privs table
local online  = {}      -- set of connected names
local commands = {}     -- chatcommand name -> def
local privileges = {}   -- registered privileges

core = {
	get_mod_storage = function()
		return {
			get_string = function(_, k) return store_data[k] or "" end,
			set_string = function(_, k, v)
				if v == nil or v == "" then store_data[k] = nil
				else store_data[k] = v end
			end,
			get_keys = function(_)
				local out = {}
				for k in pairs(store_data) do out[#out + 1] = k end
				return out
			end,
		}
	end,
	write_json = json_encode,
	parse_json = json_decode,
	get_translator = function(_)
		return function(msg, ...)
			local args = { ... }
			return (tostring(msg):gsub("@(%d+)", function(n)
				return tostring(args[tonumber(n)] or "")
			end))
		end
	end,
	get_current_modname = function() return _G.__current_modname or "smp_admin" end,
	log = function(level, msg)
		logs[#logs + 1] = { level = level, msg = msg }
	end,
	chat_send_player = function(name, msg)
		chats[name] = chats[name] or {}
		chats[name][#chats[name] + 1] = msg
	end,
	get_connected_players = function()
		local out = {}
		for name in pairs(online) do
			local n = name
			out[#out + 1] = { get_player_name = function() return n end }
		end
		return out
	end,
	get_player_privs = function(name) return privs[name] or {} end,
	register_privilege = function(name, _) privileges[name] = true end,
	register_chatcommand = function(name, def) commands[name] = def end,
	registered_chatcommands = commands,
}
_G.core = core

----------------------------------------------------------------------
-- Load the mod under test
----------------------------------------------------------------------

local function load_mod(mod)
	_G.__current_modname = mod
	local f, err = loadfile(ROOT .. "/friedcake/mods/" .. mod .. "/init.lua")
	assert(f, "loadfile " .. mod .. ": " .. tostring(err))
	f()
	_G.__current_modname = nil
end

load_mod("smp_admin")

ok(type(smp_admin) == "table", "load: smp_admin global exists")
ok(privileges.smp_admin and privileges.smp_moderator,
	"load: both privileges registered")
ok(commands.mute ~= nil and commands.unmute ~= nil,
	"load: /mute and /unmute registered")

local function wipe_all()
	for k in pairs(store_data) do store_data[k] = nil end
	logs = {}
	chats = {}
	privs = {}
	online = {}
end

local function set_connected(name, privs_for_name)
	online[name] = true
	privs[name] = privs_for_name or {}
end

local function total_messages()
	local n = 0
	for _, list in pairs(chats) do n = n + #list end
	return n
end

----------------------------------------------------------------------
-- T1 — flag appends, returns an id, persists across a simulated reload
----------------------------------------------------------------------
print("--- T1: flag appends and persists ---")
wipe_all()
local id1 = smp_admin.flag("large_transfer_to_new_account",
	"alice -> bob, $2,000,000.00")
ok(type(id1) == "number", "T1 flag returns an id: " .. tostring(id1))
local list = smp_admin.flags()
eq(#list, 1, "T1 one entry after one flag")
eq(list[1].id, id1, "T1 entry carries the returned id")
eq(list[1].kind, "large_transfer_to_new_account", "T1 kind stored")
eq(list[1].detail, "alice -> bob, $2,000,000.00",
	"T1 detail stored verbatim (no money math)")
-- Simulated reload: a fresh chunk of init.lua over the same storage.
load_mod("smp_admin")
local reloaded = smp_admin.flags()
eq(#reloaded, 1, "T1 entry survives a reload")
eq(reloaded[1].id, id1, "T1 id survives a reload")
eq(reloaded[1].detail, list[1].detail, "T1 detail survives a reload")
local id2 = smp_admin.flag("second_kind", "second detail")
ok(id2 > id1, "T1 ids keep counting after the reload")

----------------------------------------------------------------------
-- T2 — ring cap evicts the oldest (create 501)
----------------------------------------------------------------------
print("--- T2: ring cap evicts oldest (501 appends) ---")
wipe_all()
local ids = {}
for i = 1, 501 do
	ids[#ids + 1] = smp_admin.flag("test_ring", "entry " .. i)
end
list = smp_admin.flags()
eq(#list, 500, "T2 ring holds 500 entries after 501 appends")
eq(list[1].id, ids[2], "T2 eviction drops exactly the oldest entry")
eq(list[#list].id, ids[501], "T2 newest entry kept")
local has_first = false
for _, e in ipairs(list) do
	if e.id == ids[1] then has_first = true end
end
ok(not has_first, "T2 first entry (id 1) is gone from the ring")

----------------------------------------------------------------------
-- T3 — logs a warning and notifies exactly the online staff
----------------------------------------------------------------------
print("--- T3: warning log + exactly the online staff notified ---")
wipe_all()
set_connected("boss", { smp_admin = true })
set_connected("cop", { smp_moderator = true })
set_connected("civilian", {})
privs["offline_staff"] = { smp_admin = true } -- registered, not online
smp_admin.flag("test_notify", "look here")
local warned = 0
for _, rec in ipairs(logs) do
	if rec.level == "warning"
			and rec.msg == "[smp_admin] flag test_notify look here" then
		warned = warned + 1
	end
end
eq(warned, 1, "T3 exactly one warning in the mandated format")
ok(chats["boss"] ~= nil and #chats["boss"] == 1, "T3 boss notified once")
ok(chats["cop"] ~= nil and #chats["cop"] == 1, "T3 cop notified once")
eq(chats["boss"][1], "Flag test_notify: look here",
	"T3 notice is a translated string")
eq(total_messages(), 2, "T3 exactly the online staff notified")

----------------------------------------------------------------------
-- T4 — does NOT notify offline or unprivileged players
----------------------------------------------------------------------
print("--- T4: offline and unprivileged players hear nothing ---")
wipe_all()
privs["ghost_admin"] = { smp_admin = true }    -- staff, offline
privs["ghost_mod"] = { smp_moderator = true }  -- staff, offline
set_connected("bystander", {})                 -- online, no privs
set_connected("shouter", { shout = true })     -- online, unrelated priv
smp_admin.flag("test_quiet", "nobody should see this")
ok(next(chats) == nil, "T4 no chat message sent at all")
ok(chats["ghost_admin"] == nil and chats["ghost_mod"] == nil,
	"T4 offline staff not notified")
ok(chats["bystander"] == nil and chats["shouter"] == nil,
	"T4 unprivileged players not notified")
local warned4 = 0
for _, rec in ipairs(logs) do
	if rec.level == "warning" and rec.msg:find("test_quiet", 1, true) then
		warned4 = warned4 + 1
	end
end
eq(warned4, 1, "T4 the warning is still logged with no audience")

----------------------------------------------------------------------
-- T5 — mute -> is_muted true, with remaining seconds
----------------------------------------------------------------------
print("--- T5: mute reads back with remaining seconds ---")
wipe_all()
eq(smp_admin.mute("alice", 90), true, "T5 mute returns true")
local muted, rem = smp_admin.is_muted("alice") -- alice is offline
ok(muted == true, "T5 is_muted true for a fresh 90s mute (offline name)")
ok(type(rem) == "number" and rem > 0 and rem <= 90,
	"T5 remaining seconds in (0, 90] (got " .. tostring(rem) .. ")")
eq(smp_admin.is_muted("never_muted"), false, "T5 unknown name reads false")

----------------------------------------------------------------------
-- T6 — permanent mute (no seconds) -> true with no expiry
----------------------------------------------------------------------
print("--- T6: permanent mutes ---")
wipe_all()
smp_admin.mute("bob") -- no seconds at all
local m, r = smp_admin.is_muted("bob")
ok(m == true, "T6 mute without seconds is active")
ok(r == nil, "T6 permanent mute reports no remaining seconds")
eq(store_data["mute:bob"], "0", "T6 permanent stored as expiry 0")
smp_admin.mute("carol", 0)
m, r = smp_admin.is_muted("carol")
ok(m == true and r == nil, "T6 seconds=0 is permanent too")

----------------------------------------------------------------------
-- T7 — lazy expiry under a stubbed clock (save/restore os.time)
----------------------------------------------------------------------
print("--- T7: lazy expiry under a stubbed os.time ---")
wipe_all()
local real_time = os.time
local base = real_time()
local now = base
local fut_m, fut_r, past_m, clean_m
os.time = function() return now end
local okc, err = pcall(function()
	smp_admin.mute("dave", 100)
	now = base + 50
	fut_m, fut_r = smp_admin.is_muted("dave")
	now = base + 200
	past_m = smp_admin.is_muted("dave")
	now = base + 50 -- a moment at which the entry would still be live
	clean_m = smp_admin.is_muted("dave")
end)
os.time = real_time
ok(okc, "T7 ran under the stubbed clock: " .. tostring(err))
ok(fut_m == true, "T7 future expiry reads muted")
eq(fut_r, 50, "T7 remaining = 50s at base+50")
ok(past_m == false, "T7 past expiry reads not muted")
eq(store_data["mute:dave"], nil, "T7 expired entry cleaned up on read")
ok(clean_m == false, "T7 re-read at a live moment stays not-muted")

----------------------------------------------------------------------
-- T8 — unmute clears; second unmute is a safe no-op
----------------------------------------------------------------------
print("--- T8: unmute clears, second unmute is safe ---")
wipe_all()
smp_admin.mute("erin", 60)
eq(smp_admin.unmute("erin"), true, "T8 first unmute returns true")
eq(smp_admin.is_muted("erin"), false, "T8 not muted after unmute")
eq(store_data["mute:erin"], nil, "T8 storage entry cleared")
eq(smp_admin.unmute("erin"), false, "T8 second unmute returns false")
eq(smp_admin.unmute("nobody_at_all"), false,
	"T8 unknown name returns false without throwing")
eq(smp_admin.is_muted(nil), false, "T8 is_muted(nil) is false, no throw")

----------------------------------------------------------------------
-- T9 — /mute parses 90, permanent/omitted, rejects 'abc', needs priv
----------------------------------------------------------------------
print("--- T9: /mute parsing and privilege ---")
wipe_all()
local mute_cmd = commands["mute"]
ok(mute_cmd ~= nil, "T9 /mute registered")
privs["mod"] = { smp_moderator = true }
privs["admin"] = { smp_admin = true }
privs["peasant"] = {}
local r, msg = mute_cmd.func("mod", "alice 90")
ok(r == true, "T9 /mute alice 90 succeeds: " .. tostring(msg))
ok(msg ~= nil and msg:find("alice", 1, true) ~= nil
		and msg:find("90", 1, true) ~= nil,
	"T9 reply names target and duration: " .. tostring(msg))
local m9, r9 = smp_admin.is_muted("alice")
ok(m9 == true and type(r9) == "number" and r9 <= 90,
	"T9 90s mute applied with remaining seconds")
r = mute_cmd.func("admin", "bob 60")
ok(r == true, "T9 smp_admin alone passes the check (no priv hierarchy)")
r, msg = mute_cmd.func("mod", "carol permanent")
ok(r == true and msg ~= nil and msg:find("permanent", 1, true) ~= nil,
	"T9 literal 'permanent' accepted: " .. tostring(msg))
m9, r9 = smp_admin.is_muted("carol")
ok(m9 == true and r9 == nil, "T9 'permanent' is a permanent mute")
r, msg = mute_cmd.func("mod", "dave")
ok(r == true and msg ~= nil and msg:find("permanent", 1, true) ~= nil,
	"T9 omitted duration means permanent: " .. tostring(msg))
m9, r9 = smp_admin.is_muted("dave")
ok(m9 == true and r9 == nil, "T9 omitted duration stored as permanent")
r, msg = mute_cmd.func("mod", "eve abc")
ok(r == false and msg ~= nil and msg:find("Usage", 1, true) ~= nil,
	"T9 'abc' rejected with the usage message: " .. tostring(msg))
eq(smp_admin.is_muted("eve"), false, "T9 rejected duration changes no state")
r, msg = mute_cmd.func("mod", "frank -5")
ok(r == false and msg ~= nil and msg:find("Usage", 1, true) ~= nil,
	"T9 negative duration rejected with the usage message: " .. tostring(msg))
eq(smp_admin.is_muted("frank"), false, "T9 negative duration changes no state")
r, msg = mute_cmd.func("mod", "")
ok(r == false and msg ~= nil and msg:find("Usage", 1, true) ~= nil,
	"T9 missing target rejected with the usage message")
r, msg = mute_cmd.func("peasant", "mallory 60")
ok(r == false and msg ~= nil and msg:find("privilege", 1, true) ~= nil,
	"T9 player without either privilege gets the deny message: "
		.. tostring(msg))
eq(smp_admin.is_muted("mallory"), false, "T9 denied call changes no state")

----------------------------------------------------------------------
-- T10 — /unmute requires priv and reports 'not muted'
----------------------------------------------------------------------
print("--- T10: /unmute privilege and 'not muted' ---")
wipe_all()
local unmute_cmd = commands["unmute"]
ok(unmute_cmd ~= nil, "T10 /unmute registered")
privs["mod"] = { smp_moderator = true }
privs["peasant"] = {}
r, msg = unmute_cmd.func("peasant", "mallory")
ok(r == false and msg ~= nil and msg:find("privilege", 1, true) ~= nil,
	"T10 player without either privilege gets the deny message: "
		.. tostring(msg))
smp_admin.mute("mallory", 30)
r, msg = unmute_cmd.func("mod", "mallory")
ok(r == true, "T10 /unmute clears an existing mute: " .. tostring(msg))
eq(smp_admin.is_muted("mallory"), false, "T10 target reads not muted")
r, msg = unmute_cmd.func("mod", "mallory")
ok(r == false and msg ~= nil and msg:find("not muted", 1, true) ~= nil,
	"T10 second /unmute reports 'not muted': " .. tostring(msg))
r, msg = unmute_cmd.func("mod", "")
ok(r == false and msg ~= nil and msg:find("Usage", 1, true) ~= nil,
	"T10 missing target rejected with the usage message")

----------------------------------------------------------------------
-- In-game suite (mods/smp_admin/test.lua) — must also pass
----------------------------------------------------------------------
print("== in-game test suite (mods/smp_admin/test.lua) ==")
wipe_all()
set_connected("boss", { smp_admin = true })
set_connected("cop", { smp_moderator = true })
set_connected("civilian", {})
do
	local chunk, lerr = loadfile(ROOT .. "/friedcake/mods/smp_admin/test.lua")
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
	print("TEST_ADMIN FAILED")
	os.exit(1)
end
print("ALL OK")
os.exit(0)
