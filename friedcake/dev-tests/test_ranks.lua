-- Standalone smoke test for smp_ranks (f13) — runs under plain luajit,
-- no engine. Stubs core, then loads smp_core, smp_store and smp_ranks
-- and exercises the f13 acceptance tests T1–T8 (the halves this feature
-- owns; consumption beyond the default is enforced by f09/f03/f04 and
-- chat prefixing by f11).
--
-- Run: luajit friedcake/dev-tests/test_ranks.lua
-- Exits non-zero on any failure (tools/agent-flow.sh test).

-- Locate the repository root from the script path so the harness also
-- works from a git worktree checkout.
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
		if c == "{" then return parse_object()
		elseif c == "[" then return parse_array()
		elseif c == '"' then return parse_string()
		elseif s:sub(i, i + 3) == "true"  then i = i + 4 return true
		elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
		elseif s:sub(i, i + 3) == "null"  then i = i + 4 return nil
		end
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
-- Engine stub
----------------------------------------------------------------------

local store_data = {}     -- mod_storage contents
local chats = {}          -- player -> messages
local forms = {}          -- player -> {formname, spec}
local commands = {}
local join_handlers = {}
local field_handlers = {}
local after_fns = {}      -- captured core.after callbacks
local online = {}         -- names treated as connected
local gametime = 0

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
	serialize = function(v) return "return " .. tostring(v) end,
	deserialize = function() return nil end,
	get_translator = function(_)
		return function(msg, ...)
			local args = { ... }
			return (tostring(msg):gsub("@(%d+)", function(n)
				return tostring(args[tonumber(n)] or "")
			end))
		end
	end,
	get_current_modname = function() return _G.__current_modname or "smp_ranks" end,
	get_modpath = function(m) return ROOT .. "/friedcake/mods/" .. m end,
	log = function(level, msg)
		if level == "error" or level == "warning" then
			print("[" .. tostring(level) .. "] " .. tostring(msg))
		end
	end,
	chat_send_player = function(name, msg)
		chats[name] = chats[name] or {}
		chats[name][#chats[name] + 1] = msg
	end,
	show_formspec = function(name, formname, spec)
		forms[name] = { formname = formname, spec = spec }
	end,
	close_formspec = function(name, _)
		forms[name] = nil
	end,
	formspec_escape = function(str)
		if type(str) ~= "string" then return str end
		return (str:gsub("\\", "\\\\"):gsub("%]", "\\]"):gsub("%[", "\\["):gsub(";", "\\;"))
	end,
	settings = {
		get = function(_, _) return "" end,   -- every key uses its default
		get_bool = function(_, _) return nil end,
	},
	get_worldpath = function() return "/tmp" end,
	get_gametime = function() return gametime end,
	register_chatcommand = function(name, def) commands[name] = def end,
	registered_chatcommands = commands,
	register_privilege = function(_, _) end,
	register_on_shutdown = function(_) end,
	register_globalstep = function(_) end,
	register_on_leaveplayer = function(_) end,
	register_on_joinplayer = function(fn) join_handlers[#join_handlers + 1] = fn end,
	register_on_player_receive_fields = function(fn)
		field_handlers[#field_handlers + 1] = fn
	end,
	get_player_by_name = function(name) return online[name] or nil end,
	get_connected_players = function()
		local out = {}
		for name in pairs(online) do
			out[#out + 1] = { get_player_name = function() return name end }
		end
		return out
	end,
	after = function(_, fn) after_fns[#after_fns + 1] = fn end,
	check_player_privs = function(_, _) return true end,
}
_G.core = core

----------------------------------------------------------------------
-- Load the mods under test
----------------------------------------------------------------------

local function load(mod)
	_G.__current_modname = mod
	local f, err = loadfile(ROOT .. "/friedcake/mods/" .. mod .. "/init.lua")
	assert(f, "loadfile " .. mod .. ": " .. tostring(err))
	f()
	_G.__current_modname = nil
end

load("smp_core")  -- formatter + menu sessions
load("smp_store") -- player records (mod_storage backend)
load("smp_ranks") -- the mod under test

local DAY = 86400
local A = "__t13_a"
local B = "__t13_b"
local OFF = "__t13_off"

local function reset(name)
	local rec = smp_store.api.ensure_player(name)
	rec.rank = {}
	smp_store.api.upsert_player(rec)
	smp_ranks.unwatch(name)
	smp_ranks._notified[name] = nil
end
for _, n in ipairs({ A, B, OFF }) do reset(n) end

----------------------------------------------------------------------
-- T1 — perk API moves limits with the tier
----------------------------------------------------------------------
print("--- T1: limits through the perk API ---")
eq(smp_ranks.tier(A), "default", "T1 fresh record reads default")
eq(smp_ranks.home_limit(A), 2,  "T1 default homes")
eq(smp_ranks.ah_limit(A), 9,    "T1 default auction slots")
eq(smp_ranks.order_limit(A), 9, "T1 default order slots")

smp_ranks.grant(A, "tier1")
eq(smp_ranks.tier(A), "tier1", "T1 tier1 after grant")
eq(smp_ranks.home_limit(A), 9,   "T1 tier1 homes")
eq(smp_ranks.ah_limit(A), 45,    "T1 tier1 auction slots")
eq(smp_ranks.order_limit(A), 45, "T1 tier1 order slots")

smp_ranks.clear(A)
eq(smp_ranks.tier(A), "default", "T1 default after clear")
eq(smp_ranks.home_limit(A), 2,  "T1 homes revert")
eq(smp_ranks.ah_limit(A), 9,    "T1 auction slots revert")
eq(smp_ranks.order_limit(A), 9, "T1 order slots revert")

-- Higher tiers and media alias (§4.1): media = tier3.
smp_ranks.grant(A, "tier3")
eq(smp_ranks.home_limit(A), 90, "T1 tier3 homes")
eq(smp_ranks.ah_limit(A), 90,   "T1 tier3 auction slots (PROPOSED, V-72)")
smp_ranks.grant(A, "media")
eq(smp_ranks.home_limit(A), smp_ranks.slots_for("homes", "tier3"),
	"T1 media aliases tier3 homes")
eq(smp_ranks.tier(A), "media", "T1 media tier id")
smp_ranks.clear(A)

-- Name-or-player normalisation (f08 passes names, f09 passes refs).
local ref = { get_player_name = function() return A end }
smp_ranks.grant(A, "tier2")
eq(smp_ranks.tier(ref), smp_ranks.tier(A), "tier() accepts a player ref")
eq(smp_ranks.home_limit(ref), smp_ranks.home_limit(A),
	"home_limit() accepts a player ref")
eq(smp_ranks.rtp_cooldown(ref), smp_ranks.rtp_cooldown(A),
	"rtp_cooldown() accepts a player ref")
eq(smp_ranks.tier(nil), "default", "tier(nil) is default")
eq(smp_ranks.tier(""), "default", "tier('') is default")
smp_ranks.clear(A)

----------------------------------------------------------------------
-- T2 — lazy expiry, no record mutation
----------------------------------------------------------------------
print("--- T2: lazy expiry ---")
local rec = smp_store.api.get_player(A)
rec.rank = { tier = "tier2", expires_at = os.time() - 10 }
smp_store.api.upsert_player(rec)
local before = json_encode(smp_store.api.get_player(A).rank)

eq(smp_ranks.tier(A), "default", "T2 expired tier reads default")
eq(json_encode(smp_store.api.get_player(A).rank), before,
	"T2 tier() never mutates the record")
local watched = 0
for _ in pairs(smp_ranks._watch) do watched = watched + 1 end
eq(watched, 0, "T2 tier() does not touch the watch set")

----------------------------------------------------------------------
-- T4 (API half) — expired tier loses the raised limits; join check
-- notifies without mutating
----------------------------------------------------------------------
print("--- T4: expired limits + join notification ---")
eq(smp_ranks.home_limit(A), 2,  "T4 expired homes back to default")
eq(smp_ranks.ah_limit(A), 9,    "T4 expired auction slots back to default")
eq(smp_ranks.order_limit(A), 9, "T4 expired order slots back to default")

smp_ranks.check_join(A)
ok(smp_ranks._notified[A] == true, "T4 join check notifies expiry")
eq(smp_ranks._watch[A], nil, "T4 expired record leaves the watch set")
eq(json_encode(smp_store.api.get_player(A).rank), before,
	"T4 join check never mutates the record")

-- The sweep emits for an expired candidate and clears it (§8).
online[A] = true
smp_ranks._notified[A] = nil -- fresh server run for the sweep check
smp_ranks.watch(A, os.time() - 1)
smp_ranks.sweep()
ok(smp_ranks._watch[A] == nil, "T4 sweep drops expired candidates")
ok(chats[A] ~= nil and #chats[A] > 0, "T4 sweep emits the notification")
ok(smp_ranks._notified[A] == true, "T4 sweep notification recorded")
eq(json_encode(smp_store.api.get_player(A).rank), before,
	"T4 sweep never mutates the record")
online[A] = nil

----------------------------------------------------------------------
-- T3 — consecutive same-tier grants stack
----------------------------------------------------------------------
print("--- T3: grant stacking ---")
smp_ranks.clear(A)
local g1 = smp_ranks.grant(A, "tier1", 30)
local g2 = smp_ranks.grant(A, "tier1", 30)
eq(g2.expires_at - g1.expires_at, 30 * DAY, "T3 second grant adds 30d")
local delta = g2.expires_at - os.time()
ok(delta >= 60 * DAY - 10 and delta <= 60 * DAY + 10,
	"T3 two grants give now + 60d (delta " .. tostring(delta) .. ")")

local g3 = smp_ranks.grant(A, "tier2", 30)
ok(g3.expires_at - os.time() <= 30 * DAY + 10,
	"T3 tier change does not inherit the old expiry")

-- Grants default to ranks.grant_days = 30 when days is omitted.
local g4 = smp_ranks.grant(A, "tier1")
eq(g4.expires_at - os.time(), 30 * DAY, "T3 default grant is 30 days")

----------------------------------------------------------------------
-- T5 — no chat prefix by default (V-24)
----------------------------------------------------------------------
print("--- T5: chat_prefix default ---")
eq(smp_ranks.chat_prefix(A), "", "T5 chat_prefix is empty by default")
eq(smp_ranks.chat_prefix(ref), "", "T5 chat_prefix accepts a player ref")

----------------------------------------------------------------------
-- T6 — offline grant via /rank set
----------------------------------------------------------------------
print("--- T6: offline grant ---")
local cmd = commands["rank"]
ok(cmd ~= nil, "T6 /rank registered")
local okr, msg = cmd.func("__t13_admin", "set " .. OFF .. " tier1")
ok(okr == true, "T6 /rank set succeeds: " .. tostring(msg))
ok(core.get_player_by_name(OFF) == nil, "T6 player is offline during grant")
eq(smp_ranks.tier(OFF), "tier1", "T6 tier() sees the offline grant")

local bad, badmsg = cmd.func("__t13_admin", "set " .. OFF .. " nope")
ok(bad == false, "T6 unknown tier refused")
ok(badmsg and badmsg:find("Unknown tier", 1, true) ~= nil,
	"T6 unknown tier message")
bad = cmd.func("__t13_admin", "set " .. OFF .. " tier1 0")
ok(bad == false, "T6 days=0 refused")
ok(cmd.func("__t13_admin", "clear " .. OFF) == true, "T6 /rank clear works")

-- Applies on next join: the join handler adds a live rank to the sweep.
smp_ranks.grant(OFF, "tier1")
for _, fn in ipairs(join_handlers) do
	fn({ get_player_name = function() return OFF end })
end
ok(smp_ranks._watch[OFF] ~= nil, "T6 join handler watches the live tier")
ok(smp_ranks._notified[OFF] ~= true,
	"T6 join handler does not notify a live tier")
smp_ranks.clear(OFF)

----------------------------------------------------------------------
-- T7 — /ranks renders every configured tier from live config
----------------------------------------------------------------------
print("--- T7: /ranks formspec ---")
local rows = smp_ranks.tier_rows()
eq(#rows, #smp_ranks.tier_order, "T7 one row per configured tier")
eq(#rows, 5, "T7 five tiers")
local fs = smp_ranks.formspec()
for _, row in ipairs(rows) do
	ok(fs:find(row.label, 1, true) ~= nil, "T7 row rendered: " .. row.tier)
end
ok(fs:find("Back", 1, true) ~= nil, "T7 Back button")
ok(fs:find("Store", 1, true) ~= nil, "T7 store field label")
ok(fs:find("Ranks", 1, true) ~= nil, "T7 menu titled Ranks")

-- Numbers come from live config, not literals in the formspec.
local saved = smp_ranks.slots.homes.tier2
smp_ranks.slots.homes.tier2 = 99
ok(smp_ranks.formspec():find("99 homes", 1, true) ~= nil,
	"T7 reflects live config edits")
smp_ranks.slots.homes.tier2 = saved

local rcmd = commands["ranks"]
ok(rcmd ~= nil, "T7 /ranks registered")
ok(rcmd.func(A, "") == true, "T7 /ranks opens for a player")
ok(forms[A] ~= nil and forms[A].formname == smp_ranks.FORMNAME,
	"T7 /ranks shows the ranks formspec")
ok(#field_handlers > 0, "T7 receive-fields handler registered")

----------------------------------------------------------------------
-- T8 — tier1 /rtp cooldown shorter than default
----------------------------------------------------------------------
print("--- T8: rtp cooldown ---")
reset(B)
local default_cd = smp_ranks.rtp_cooldown(B)
eq(default_cd, 60, "T8 default cooldown 60s")
smp_ranks.grant(B, "tier1")
local t1_cd = smp_ranks.rtp_cooldown(B)
eq(t1_cd, 30, "T8 tier1 cooldown 30s")
ok(t1_cd < default_cd, "T8 tier1 cooldown shorter than default")
smp_ranks.clear(B)
eq(smp_ranks.rtp_cooldown(B), 60, "T8 cooldown reverts after clear")

----------------------------------------------------------------------
-- Config sanity (f13 §7 defaults)
----------------------------------------------------------------------
eq(smp_ranks.cfg.grant_days, 30, "cfg.ranks.grant_days default 30")
eq(smp_ranks.cfg.chat_prefix, "", "cfg.ranks.chat_prefix default empty")
eq(smp_ranks.cfg.expiry_check_interval, 3600, "cfg sweep interval 3600s")
ok(#after_fns >= 1, "hourly sweep loop scheduled with core.after")

----------------------------------------------------------------------
-- In-game suite (mods/smp_ranks/test.lua) — must also pass
----------------------------------------------------------------------
print("== in-game test suite (mods/smp_ranks/test.lua) ==")
do
	local chunk, lerr = loadfile(ROOT .. "/friedcake/mods/smp_ranks/test.lua")
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
	print("TEST_RANKS FAILED")
	os.exit(1)
end
print("ALL OK")
