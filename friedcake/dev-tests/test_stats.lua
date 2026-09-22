-- dev-tests/test_stats.lua — headless test for smp_stats (f14).
--
-- Runs under plain luajit, no engine: loads smp_core + smp_store +
-- smp_economy + smp_settings + smp_stats over a minimal `core` stub,
-- then walks f14 §9 T1–T11 through the real hook and command paths:
--   T1  dig/place hooks increment broken_blocks/placed_blocks once
--   T2  kill/death attribution incl. the f10 combat-log credit path
--   T3  mobs_mc:* on_die wrapping credits mobs_killed for the killer
--   T4  f02's direct rec.stats write and add() agree (money_made_from_sell)
--   T5  f05's ObjectRef add() lands in rec.stats (money_spent_on_shop)
--   T6  scoreboard HUD: lower-case suffix, hud_change on balance change
--   T7  ten official leaderboard categories, claim labels
--   T8  10,000-record rebuild under 50 ms (also in mods/smp_stats/test.lua)
--   T9  offline players appear on the boards and in the snapshots
--   T10 /api issues once, re-shows, revokes; snapshot files written
--   T11 playtime accumulates in memory and flushes on interval/leave/
--       shutdown — at most stats.persist_interval lost to a crash
-- Plus: /stats and /leaderboard menus (V-23), the /baltop snapshot
-- override, and the f12 scoreboard.show wiring.
--
-- Usage:  luajit friedcake/dev-tests/test_stats.lua

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
	if t == "number" or t == "boolean" then
		if t == "number" and v == math.floor(v) and math.abs(v) < 1e15 then
			return string.format("%.0f", v)
		end
		return tostring(v)
	end
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
	return parse_value()
end

----------------------------------------------------------------------
-- Minimal engine stub.
local modname = nil
local commands = {}
local shutdown_handlers, globalstep_handlers = {}, {}
local join_handlers, leave_handlers, die_handlers = {}, {}, {}
local dig_handlers, place_handlers, mods_loaded_handlers = {}, {}, {}
local field_handlers = {}, {}
local shown, chats = {}, {}
local players = {}
local connected = {}
local afters = {}
local logs = {}
local fs_writes = {}
local hud_events = {}
local us_time = 1758500000000000

local S_factory = function()
	return function(s, ...)
		local args = { ... }
		return (s:gsub("@(%d+)", function(d)
			return tostring(args[tonumber(d)] or "")
		end))
	end
end

-- In-memory mod storage (smp_store backend: mod_storage).
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

-- Deterministic 40-hex stand-in for core.sha1 (the engine's is real;
-- tests only rely on the fcsmp_ + 40-hex form and per-call uniqueness).
local function stub_sha1(s)
	local v1, v2, v3, v4, v5 = 2166136261, 5381, 0, 1013904223, 7
	for i = 1, #s do
		local b = s:byte(i)
		v1 = (v1 * 16777619 + b) % 4294967296
		v2 = (v2 * 33 + b) % 4294967296
		v3 = (v3 + b * i) % 4294967296
		v4 = (v4 * 65599 + (v1 % 65536)) % 4294967296
		v5 = (v5 + (v2 % 1000003) * (i + 1)) % 4294967296
	end
	return string.format("%08x%08x%08x%08x%08x", v1, v2, v3, v4, v5)
end

core = {
	get_current_modname = function() return modname end,
	get_translator = function(_) return S_factory() end,
	get_modpath = function(m) return ROOT .. "/friedcake/mods/" .. m end,
	log = function(level, msg) logs[#logs + 1] = tostring(level) .. ":" .. tostring(msg) end,
	write_json = json_enc,
	parse_json = json_dec,
	settings = {
		-- server.name = Voire: the observed sidebar title (F0287).
		get = function(_, k)
			local known = { ["server.name"] = "Voire" }
			return known[k]
		end,
		get_bool = function(_, _, default) return default end,
	},
	formspec_escape = function(s)
		-- mirrors engine formspec_escape: backslash, semicolon, newline
		return (tostring(s):gsub('[%\\%;%\n]', "\\%0"))
	end,
	show_formspec = function(pname, formname, spec)
		shown[pname] = { formname = formname, spec = spec }
	end,
	close_formspec = function(pname, _)
		shown[pname] = nil
	end,
	get_player_by_name = function(n) return players[n] end,
	get_player_names = function()
		local out = {}
		for n in pairs(players) do out[#out + 1] = n end
		table.sort(out)
		return out
	end,
	get_connected_players = function() return connected end,
	register_chatcommand = function(name, def) commands[name] = def end,
	registered_chatcommands = commands,
	override_chatcommand = function(name, redef)
		local def = commands[name]
		if def then
			for k, v in pairs(redef) do def[k] = v end
		end
	end,
	register_privilege = function() end,
	register_on_shutdown = function(fn) shutdown_handlers[#shutdown_handlers + 1] = fn end,
	register_on_globalstep = function(fn) globalstep_handlers[#globalstep_handlers + 1] = fn end,
	register_on_joinplayer = function(fn) join_handlers[#join_handlers + 1] = fn end,
	register_on_leaveplayer = function(fn) leave_handlers[#leave_handlers + 1] = fn end,
	register_on_dieplayer = function(fn) die_handlers[#die_handlers + 1] = fn end,
	register_on_dignode = function(fn) dig_handlers[#dig_handlers + 1] = fn end,
	register_on_placenode = function(fn) place_handlers[#place_handlers + 1] = fn end,
	register_on_mods_loaded = function(fn) mods_loaded_handlers[#mods_loaded_handlers + 1] = fn end,
	register_on_player_receive_fields = function(fn) field_handlers[#field_handlers + 1] = fn end,
	get_gametime = function() return 0 end,
	chat_send_player = function(pname, msg) chats[#chats + 1] = pname .. ":" .. msg end,
	chat_send_all = function(msg) chats[#chats + 1] = "*" .. msg end,
	get_worldpath = function() return "/tmp/friedcake_stats_world" end,
	mkdir = function() return true end,
	safe_file_write = function(path, content)
		fs_writes[path] = content
		return true
	end,
	request_insecure_environment = function() return nil end,
	get_mod_storage = function() return store end,
	get_us_time = function()
		us_time = us_time + 12345
		return us_time
	end,
	sha1 = stub_sha1,
	after = function(t, fn)
		afters[#afters + 1] = { t = t, fn = fn }
		return true
	end,
	DIR_DELIM = "/",
	registered_entities = {},
}
core.registered_chatcommands = commands

local function load_mod(name)
	modname = name
	local chunk, err = loadfile(ROOT .. "/friedcake/mods/" .. name .. "/init.lua")
	assert(chunk, "load " .. name .. ": " .. tostring(err))
	local ok, lerr = pcall(chunk)
	modname = nil
	assert(ok, "run " .. name .. ": " .. tostring(lerr))
end

----------------------------------------------------------------------
-- Player stubs: meta survives leave/join (world on disk), HUD calls
-- are recorded so T6 can observe hud_add vs hud_change.
local meta_store = {}
local function join(name)
	local data = meta_store[name] or {}
	meta_store[name] = data
	local p = {}
	function p:get_player_name() return name end
	function p:is_player() return true end
	function p:get_meta()
		return {
			get_string = function(_, k) return data[k] or "" end,
			set_string = function(_, k, v) data[k] = v end,
			get_int = function(_, k) return tonumber(data[k]) or 0 end,
			set_int = function(_, k, v) data[k] = v end,
		}
	end
	p.huds = {}
	function p:hud_add(def)
		local id = #p.huds + 1
		p.huds[id] = { text = def.text, def = def }
		hud_events[#hud_events + 1] = "add:" .. name
		return id
	end
	function p:hud_change(id, attr, value)
		if p.huds[id] then p.huds[id][attr] = value end
		hud_events[#hud_events + 1] = "change:" .. name
	end
	function p:hud_remove(id)
		p.huds[id] = nil
		hud_events[#hud_events + 1] = "remove:" .. name
	end
	players[name] = p
	connected[#connected + 1] = p
	for _, h in ipairs(join_handlers) do h(p) end
	return p
end

local function leave(name)
	local p = players[name]
	if not p then return end
	for i, q in ipairs(connected) do
		if q == p then table.remove(connected, i) break end
	end
	for _, h in ipairs(leave_handlers) do h(p, "leave") end
	players[name] = nil
end

local function step(dtime)
	for _, h in ipairs(globalstep_handlers) do h(dtime) end
end

local function send_fields(pname, fields)
	local f = shown[pname]
	if not f then return end
	local p = players[pname]
	for _, h in ipairs(field_handlers) do
		h(p, f.formname, fields)
	end
end

local function spec_of(pname)
	return shown[pname] and shown[pname].spec or ""
end

local function count(s, needle)
	local n = 0
	for _ in s:gmatch(needle) do n = n + 1 end
	return n
end

local function last_chat()
	return chats[#chats] or ""
end

local function player_ref(name)
	return { is_player = function() return true end,
		get_player_name = function() return name end }
end

----------------------------------------------------------------------
print("--- load: smp_core, smp_store, smp_economy, smp_settings, smp_stats")
load_mod("smp_core")
load_mod("smp_store")
load_mod("smp_economy")
load_mod("smp_settings")
load_mod("smp_stats")
ok(smp_stats ~= nil, "smp_stats loaded")
eq(#afters, 1, "initial rebuild scheduled via core.after(2)")
eq(afters[1].t, 2, "first rebuild at t=2s (outside globalstep, §8)")

-- Engine calls register_on_mods_loaded after every mod is in.
core.registered_entities = {
	["mobs_mc:zombie"] = {
		on_die = function(self, pos, reason)
			orig_die_calls = (orig_die_calls or 0) + 1
			return "orig-return"
		end,
	},
	["mobs_mc:cow"] = {}, -- no original on_die
	["mcl_items:chest"] = { on_die = function() end }, -- not mobs_mc
}
for _, h in ipairs(mods_loaded_handlers) do h() end

----------------------------------------------------------------------
print("--- T1: dig/place hooks ---")
local alice = join("alice")
eq(#dig_handlers, 1, "T1 one dignode handler")
eq(#place_handlers, 1, "T1 one placenode handler")
dig_handlers[1]({ x = 0, y = 0, z = 0 }, { name = "mcl_core:stone" }, alice)
eq(smp_stats.get("alice", "broken_blocks"), 1, "T1 dig increments once")
place_handlers[1]({ x = 0, y = 1, z = 0 }, { name = "mcl_core:stone" },
	alice, { name = "air" })
eq(smp_stats.get("alice", "placed_blocks"), 1, "T1 place increments once")
dig_handlers[1]({ x = 1, y = 0, z = 0 }, { name = "mcl_core:stone" }, nil)
dig_handlers[1]({ x = 2, y = 0, z = 0 }, { name = "mcl_core:stone" },
	{ is_player = function() return false end })
eq(smp_stats.get("alice", "broken_blocks"), 1,
	"T1 no phantom credit without a player digger")
place_handlers[1]({ x = 0, y = 2, z = 0 }, { name = "mcl_core:stone" },
	nil, { name = "air" })
eq(smp_stats.get("alice", "placed_blocks"), 1,
	"T1 no phantom credit without a player placer")
dig_handlers[1]({ x = 3, y = 0, z = 0 }, { name = "mcl_core:stone" }, alice)
eq(smp_stats.get("alice", "broken_blocks"), 2, "T1 second dig increments")

----------------------------------------------------------------------
print("--- T2: kill/death attribution ---")
local bob = player_ref("bob")
-- Victim's death is always credited.
die_handlers[1](alice, { type = "suicide" })
eq(smp_stats.get("alice", "deaths"), 1, "T2 suicide: victim deaths +1")
eq(smp_stats.get("alice", "kills"), 0, "T2 suicide: no kill credit")
die_handlers[1](alice, { type = "punch", object = bob })
eq(smp_stats.get("alice", "deaths"), 2, "T2 punched: victim deaths +1")
eq(smp_stats.get("bob", "kills"), 1, "T2 punched: killer kills +1")
die_handlers[1](alice, { type = "punch", object = alice })
eq(smp_stats.get("alice", "deaths"), 3, "T2 self-hit still deaths +1")
eq(smp_stats.get("alice", "kills"), 0, "T2 self-hit: no kill credit")

-- With f10 present (smp_combat loaded), our hook stands down on kills:
-- its own dieplayer hook calls smp_combat.credit_kill (f10 §4.3).
_G.smp_combat = {}
die_handlers[1](alice, { type = "punch", object = bob })
eq(smp_stats.get("alice", "deaths"), 4, "T2 f10 present: deaths +1")
eq(smp_stats.get("bob", "kills"), 1, "T2 f10 present: we do NOT credit kills")
_G.smp_combat = nil

-- Combat log (f10 §4.3): logger dies, attacker's kill is f10's credit.
join("carol")
join("dave")
_G.smp_combat = {
	is_tagged = function(n) return n == "carol" end,
	last_attacker = function(n) return n == "carol" and "dave" or nil end,
}
leave("carol")
eq(smp_stats.get("carol", "deaths"), 1, "T2 combat log: logger deaths +1")
eq(smp_stats.get("dave", "kills"), 0,
	"T2 combat log: our hook does not credit the kill (f10 does)")
-- f10's credit_kill, as combatlog.lua calls it:
smp_stats.add("dave", "kills", 1)
eq(smp_stats.get("dave", "kills"), 1, "T2 f10 path credits the attacker")
_G.smp_combat = nil

local bob_rec = smp_store.api.get_player("bob")
ok(bob_rec ~= nil, "T2 killer record exists offline (shared §2.2)")
local dave_before = smp_stats.get("dave", "deaths")
leave("dave")
eq(smp_stats.get("dave", "deaths"), dave_before,
	"T2 untagged leave credits no death")

----------------------------------------------------------------------
print("--- T3: mobs_mc:* on_die wrapping ---")
local zombie = core.registered_entities["mobs_mc:zombie"]
local cow = core.registered_entities["mobs_mc:cow"]
ok(type(zombie.on_die) == "function", "T3 wrapped def has on_die")
ok(zombie._stats_wrapped, "T3 wrapped exactly once")
local ret = zombie.on_die({ name = "mobs_mc:zombie" }, { x = 0, y = 0, z = 0 },
	{ source = alice })
eq(ret, "orig-return", "T3 original return value preserved (physics.lua)")
eq(orig_die_calls, 1, "T3 original on_die called first")
eq(smp_stats.get("alice", "mobs_killed"), 1, "T3 killer credited mobs_killed")
eq(smp_stats.get("bob", "mobs_killed"), 0, "T3 only the killer credited")

cow.on_die({ name = "mobs_mc:cow" }, { x = 0, y = 0, z = 0 }, { source = bob })
eq(smp_stats.get("bob", "mobs_killed"), 1, "T3 def without original still credits")
eq(smp_stats.get("alice", "mobs_killed"), 1, "T3 cow kill not double-credited")

-- mob source (creeper kills cow): no player-backed killer -> nobody.
local creeper_obj = { get_luaentity = function()
	return { name = "mobs_mc:creeper", is_mob = true }
end }
local before_any = smp_stats.get("alice", "mobs_killed")
	+ smp_stats.get("bob", "mobs_killed")
cow.on_die({}, {}, { source = creeper_obj })
eq(smp_stats.get("alice", "mobs_killed") + smp_stats.get("bob", "mobs_killed"),
	before_any, "T3 mob-on-mob credits nobody")

-- tamed wolf: owner is credited (name_from_object walks entity.owner).
local alice_before_wolf = smp_stats.get("alice", "mobs_killed")
local wolf_obj = { get_luaentity = function()
	return { name = "mobs_mc:wolf", owner = "alice" }
end }
cow.on_die({}, {}, { source = wolf_obj })
eq(smp_stats.get("alice", "mobs_killed"), alice_before_wolf + 1,
	"tamed wolf kill credits the owner")

-- arrow: mcl_reason.source is the arrow entity, whose
-- luaentity._source_object is the shooter (mcl_damage.from_punch).
local arrow_obj = { get_luaentity = function()
	return { _is_arrow = true, _source_object = alice }
end }
cow.on_die({}, {}, { source = arrow_obj })
eq(smp_stats.get("alice", "mobs_killed"), alice_before_wolf + 2,
	"arrow source resolves to the shooter")

local not_mc = core.registered_entities["mcl_items:chest"]
ok(not_mc._stats_wrapped == nil, "T3 non-mobs_mc entities untouched")

----------------------------------------------------------------------
print("--- T4/T5: f02/f05 data paths agree ---")
-- f02 (agent/f02-sell sell.lua): writes rec.stats directly.
local rec = smp_store.api.ensure_player("alice")
rec.stats.money_made_from_sell = (tonumber(rec.stats.money_made_from_sell) or 0) + 1234
smp_store.api.upsert_player(rec)
eq(smp_stats.get("alice", "money_made_from_sell"), 1234,
	"T4 f02 direct write readable through get()")
-- Both paths land in the same field.
smp_stats.add(alice, "money_made_from_sell", 766)
eq(smp_stats.get("alice", "money_made_from_sell"), 2000,
	"T4 add() and the direct write share one field")
local rec2 = smp_store.api.get_player("alice")
eq(rec2.stats.money_made_from_sell, 2000, "T4 stored under rec.stats")

-- f05 (agent/f05-quickbuy bridges.lua): smp_stats.add(player, key, cost)
-- with an ObjectRef.
smp_stats.add(alice, "money_spent_on_shop", 500)
eq(smp_stats.get("alice", "money_spent_on_shop"), 500,
	"T5 ObjectRef add() lands in rec.stats")
smp_stats.add("alice", "money_spent_on_shop", 250)
eq(smp_stats.get("alice", "money_spent_on_shop"), 750,
	"T5 name form adds to the same counter")

-- Live fields are not counters.
eq(smp_stats.add(alice, "money", 1), nil, "add() refuses money (live field)")
eq(smp_stats.add(alice, "shards", 1), nil, "add() refuses shards (live field)")
eq(smp_stats.add(alice, "playtime", 1), nil,
	"add() refuses playtime (live field; add_playtime owns it)")
eq(smp_stats.add(nil, "kills", 1), nil, "add() refuses no player")
eq(smp_stats.add(alice, "", 1), nil, "add() refuses no key")
eq(smp_stats.get("nobody", "kills"), 0, "get() of an unknown record is 0")

----------------------------------------------------------------------
print("--- T6: scoreboard HUD ---")
local hud = alice.huds[1]
ok(hud ~= nil, "T6 HUD added on join")
eq(hud.text, "Voire\n$ 0", "T6 title from server.name + `$ 0`")
ok(hud.def.position.x == 1 and hud.def.position.y == 1,
	"T6 anchored bottom-right (§8)")
ok(hud.def.alignment.x == -1 and hud.def.alignment.y == -1,
	"T6 alignment keeps it clear of the hotbar")
eq(hud.def.type, "text", "T6 text HUD element")

smp_store.api.set_money("alice", 75400000, "test", "T6")
hud = alice.huds[1]
eq(hud.text, "Voire\n$ 754k", "T6 F0287 reading: `$ 754k` lower-case")
local changes = 0
for _, e in ipairs(hud_events) do
	if e == "change:alice" then changes = changes + 1 end
end
ok(changes >= 1, "T6 hud_change on balance change (never polls)")
eq(hud_events[1], "add:alice", "T6 exactly one hud_add, then changes")

local change_count = 0
for _, e in ipairs(hud_events) do
	if e == "change:alice" then change_count = change_count + 1 end
end
smp_store.api.add_money("alice", 100, "test", "T6")
eq(alice.huds[1].text, "Voire\n$ 754k",
	"T6 add_money refreshes (75400100c still rounds to 754k)")
local change_count2 = 0
for _, e in ipairs(hud_events) do
	if e == "change:alice" then change_count2 = change_count2 + 1 end
end
eq(change_count2, change_count + 1, "T6 exactly one hud_change per mutation")
local before_fail = alice.huds[1].text
local refused = smp_store.api.take_money("alice", 100000000000, "test", "T6")
eq(refused, nil, "T6 overdraft refused")
eq(alice.huds[1].text, before_fail, "T6 failed take_money does not refresh")

-- The money formatter difference: HUD lower-case, chat body upper-case.
eq(smp_core.fmt_money(75400000, "body"), "$ 754K", "fmt_money stays upper-case")
eq(smp_stats.fmt_scoreboard(75400000), "754k", "fmt_scoreboard lower-case")

----------------------------------------------------------------------
print("--- f12 wiring: scoreboard.show (§4.3.1) ---")
ok(smp_settings.registered["scoreboard.show"] ~= nil,
	"scoreboard.show registered in the Scoreboard category")
eq(smp_settings.registered["scoreboard.show"].category, "scoreboard",
	"registered under the observed Scoreboard category")
eq(smp_settings.get(alice, "scoreboard.show"), "ON", "default ON")
ok(smp_settings.set(alice, "scoreboard.show", "OFF"),
	"toggle OFF accepted for an online player")
eq(smp_stats.refresh_scoreboard("alice"), false,
	"refresh applies the toggle (returns false while hidden)")
eq(#alice.huds, 0, "sidebar removed when the setting is OFF")
smp_settings.set(alice, "scoreboard.show", "ON")
eq(smp_stats.refresh_scoreboard("alice"), true,
	"refresh re-adds the sidebar when the setting is ON")
eq(#alice.huds, 1, "sidebar restored when the setting is ON")
smp_settings.set(alice, "scoreboard.show", "OFF")
smp_settings.set(alice, "scoreboard.show", "ON") -- leave it ON for T6 reruns

----------------------------------------------------------------------
print("--- T7/T9: boards, offline players, snapshots ---")
join("bob") -- bob returns online (his record already exists)
-- Seed a spread of balances; some players never join (T9).
smp_store.api.set_money("rich01", 100000000, "test", "T9 seed")  -- $1M
smp_store.api.set_money("offline_carl", 50000000, "test", "T9 seed") -- $500k
for i = 2, 11 do
	smp_store.api.set_money(string.format("rich%02d", i),
		40000000 - (i - 2) * 1000000, "test", "T9 seed")
end
local off_rec = smp_store.api.ensure_player("offline_carl")
off_rec.stats.kills = 5
off_rec.playtime = 600
smp_store.api.upsert_player(off_rec)
ok(players["offline_carl"] == nil, "T9 offline_carl never joined")

eq(#smp_stats.CATEGORIES, 10, "T7 ten categories")
local WANT = { "brokenblocks", "deaths", "kills", "mobskilled", "money",
	"placedblocks", "playtime", "sell", "shards", "shop" }
for i, key in ipairs(WANT) do
	eq(smp_stats.CATEGORIES[i].key, key, "T7 category " .. i)
end

smp_stats.rebuild()
local boards = smp_stats.boards
for _, key in ipairs(WANT) do
	ok(type(boards[key]) == "table", "T7 board exists: " .. key)
end
eq(boards.money[1].name, "rich01", "T9 money board top is an offline player")
eq(boards.money[1].value, 100000000, "T9 seeded balance on the board")
local found_carl = false
for _, e in ipairs(boards.kills) do
	if e.name == "offline_carl" and e.value == 5 then found_carl = true end
end
ok(found_carl, "T9 offline player appears on the kills board")
eq(boards.playtime[1].value, 600, "T7 playtime board reads rec.playtime")
ok(#boards.money <= smp_stats.cfg.size, "boards capped at leaderboards.size")

----------------------------------------------------------------------
print("--- T10: /api + snapshot files ---")
local api_cmd = commands["api"]
ok(api_cmd ~= nil, "/api registered")
local r, m = api_cmd.func("alice", "")
eq(r, true, "T10 /api succeeds in snapshot mode")
ok(tostring(m):find("fcsmp_", 1, true) ~= nil, "T10 key shown: " .. tostring(m))
local key1 = smp_stats.api.key_of("alice")
ok(key1 and key1:match("^fcsmp_[0-9a-f]+$"), "T10 key stored in the record")
r, m = api_cmd.func("alice", "")
eq(r, true, "T10 second /api succeeds")
ok(tostring(m):find(key1, 1, true) ~= nil, "T10 existing key re-shown")
eq(smp_stats.api.key_of("alice"), key1, "T10 issue once: key not rotated")

r, m = api_cmd.func("alice", "delete")
eq(r, true, "T10 delete revokes")
eq(smp_stats.api.key_of("alice"), nil, "T10 key gone from the record")
r, m = api_cmd.func("alice", "delete")
eq(r, false, "T10 second delete reports no key")
r, m = api_cmd.func("alice", "")
local key2 = smp_stats.api.key_of("alice")
ok(key2 and key2 ~= key1, "T10 re-issue produces a new key")

-- mode-dependent behaviour (T10): off and push refuse.
smp_stats.cfg.api_mode = "off"
r, m = api_cmd.func("alice", "")
eq(r, false, "T10 off mode refuses")
ok(tostring(m):find("disabled", 1, true) ~= nil,
	"T10 off message: " .. tostring(m))
smp_stats.cfg.api_mode = "push"
r, m = api_cmd.func("alice", "")
eq(r, false, "T10 push mode is a warned stub")
smp_stats.cfg.api_mode = "snapshot"

-- Snapshot files land in the world directory after a rebuild.
smp_stats.rebuild()
local lb_path = "/tmp/friedcake_stats_world/friedcake_api/leaderboards.json"
local pl_path = "/tmp/friedcake_stats_world/friedcake_api/players.json"
ok(fs_writes[lb_path] ~= nil, "T10 leaderboards.json written")
ok(fs_writes[pl_path] ~= nil, "T10 players.json written")
local lb = json_dec(fs_writes[lb_path])
ok(lb ~= nil and type(lb.boards) == "table", "T10 leaderboards.json parses")
eq(lb.boards.money[1].name, "rich01", "T10 board top exported")
local pl = json_dec(fs_writes[pl_path])
local exported_carl = false
for _, e in ipairs(pl.players or {}) do
	if e.name == "offline_carl" and e.stats.kills == 5 then
		exported_carl = true
	end
end
ok(exported_carl, "T10 offline player exported with stats")

----------------------------------------------------------------------
print("--- /baltop snapshot override (§4.2.2, PROPOSED) ---")
r = commands["baltop"].func("alice", "1")
eq(r, true, "/baltop works from the snapshot")
ok(last_chat():find("--- Money Top (page 1/", 1, true) ~= nil,
	"/baltop keeps f01's exact header: " .. last_chat())
local row = last_chat():match("\n(2%. [^\n]+)") or ""
eq(row, "2. alice — $ 754K", "/baltop keeps f01's exact row format: " .. row)
-- Until the first rebuild publishes a board, f01's live path serves.
local saved_boards = smp_stats.boards
smp_stats.boards = {}
r = commands["baltop"].func("alice", "1")
eq(r, true, "/baltop falls back to f01's implementation (empty snapshot)")
smp_stats.boards = saved_boards
-- The alias delegates (registered by f01 to the overridden command).
eq(type(commands.moneytop.func), "function", "/moneytop alias present")

----------------------------------------------------------------------
print("--- /stats menu (V-23, PROPOSED) ---")
r, m = commands["stats"].func("alice", "")
eq(r, true, "/stats opens")
eq(shown.alice.formname, "smp_stats:stats", "/stats formname")
local spec = spec_of("alice")
ok(spec:find("Stats", 1, true) ~= nil, "menu title Stats")
for _, needle in ipairs({ "Broken Blocks: 2", "Placed Blocks: 1",
	"Kills: 0", "Deaths: 4", "Mob Kills: 3", "Money: $ 754K",
	"Shards: 0", "Playtime: ", "Money from Selling: $ 20",
	"Spent in Shop: $ 7.50", ";back;Back" }) do
	ok(spec:find(needle, 1, true) ~= nil, "/stats row `" .. needle .. "`")
end
r, m = commands["stats"].func("alice", "bob")
eq(r, true, "/stats for another player opens")
ok(spec_of("alice"):find("Stats - bob", 1, true) ~= nil,
	"title `Stats - <name>` when viewing another player")
r, m = commands["stats"].func("alice", "nobody")
eq(r, false, "/stats unknown player refused")
ok(tostring(m):find("does not exist", 1, true) ~= nil, "unknown player message")

----------------------------------------------------------------------
print("--- /leaderboard menus (V-23, PROPOSED) ---")
r = commands["leaderboard"].func("alice", "")
eq(r, true, "/leaderboard opens the picker")
eq(shown.alice.formname, "smp_stats:leaderboard", "picker formname")
local picker = spec_of("alice")
eq(count(picker, ";cat_"), 10, "picker has exactly ten category buttons")
local prev = 0
for _, key in ipairs(WANT) do
	local pos = picker:find(";cat_" .. key .. ";", 1, true)
	ok(pos ~= nil and pos > prev, "picker button " .. key .. " in §4.2.1 order")
	prev = pos or 0
end

r = commands["leaderboard"].func("alice", "bogus")
eq(r, false, "unknown category refused")
r = commands["lb"].func("alice", "money")
eq(r, true, "/lb alias delegates")
eq(shown.alice.formname, "smp_stats:board", "board formname")
local board_spec = spec_of("alice")
ok(board_spec:find("Money (Page 1)", 1, true) ~= nil,
	"container title `<Category> (Page N)`")
ok(board_spec:find("1. rich01 — $ 1M", 1, true) ~= nil,
	"textlist row `1. name — value`")
ok(board_spec:find("textlist[", 1, true) ~= nil, "rows are a textlist")
ok(board_spec:find(";back;Back", 1, true) ~= nil, "Back on the board")

local money_pages = math.max(1, math.ceil(#boards.money / 10))
if money_pages >= 2 then
	send_fields("alice", { next_page = "true" })
	ok(spec_of("alice"):find("Money (Page 2)", 1, true) ~= nil,
		"next_page advances to page 2")
	ok(spec_of("alice"):find("11. ", 1, true) ~= nil,
		"page 2 ranks continue at 11")
	send_fields("alice", { prev_page = "true" })
	ok(spec_of("alice"):find("Money (Page 1)", 1, true) ~= nil,
		"prev_page returns to page 1")
	send_fields("alice", { prev_page = "true" })
	ok(spec_of("alice"):find("Money (Page 1)", 1, true) ~= nil,
		"page 1 clamps (no page 0)")
end
send_fields("alice", { back = "true" })
eq(shown.alice.formname, "smp_stats:leaderboard",
	"Back from a board returns to the picker")

-- Forged category ids are ignored (session survives, no navigation).
send_fields("alice", { cat_madeup = "true" })
eq(shown.alice.formname, "smp_stats:leaderboard", "forged cat_* ignored")
ok(smp_core.get_session("alice", "smp_stats:leaderboard") ~= nil,
	"forged field keeps the session")
send_fields("alice", { quit = true })
eq(smp_core.get_session("alice", "smp_stats:leaderboard"), nil,
	"quit closes the session")

-- The picker navigates on a real click.
commands["leaderboard"].func("alice", "")
send_fields("alice", { cat_kills = "true" })
eq(shown.alice.formname, "smp_stats:board", "picker click opens the board")
ok(spec_of("alice"):find("Kills (Page 1)", 1, true) ~= nil,
	"kills board title")

----------------------------------------------------------------------
print("--- rebuild chain (§8: core.after, never globalstep) ---")
local before_count = #afters
afters[1].fn() -- fire the initial t=2 callback
eq(#afters, before_count + 1, "chain schedules the next rebuild")
eq(afters[#afters].t, smp_stats.cfg.refresh,
	"next rebuild at leaderboards.refresh (300s)")

----------------------------------------------------------------------
print("--- T11: playtime cadence ---")
eq(smp_stats.cfg.persist, 60, "stats.persist_interval defaults to 60s")
-- Sub-second ticks carry their remainder; the store is untouched.
step(0.4)
step(0.4)
step(0.4)
eq(smp_stats.get("alice", "playtime"), 1,
	"T11 3 x 0.4s carries 1 whole second to pending")
eq(smp_store.api.get_player("alice").playtime or 0, 0,
	"T11 store untouched before the interval (crash bound)")
step(0.6) -- remainder 0.2 + 0.6 = 0.8: still pending
eq(smp_store.api.get_player("alice").playtime or 0, 0,
	"T11 still unflushed under the interval")

-- Crossing the interval flushes (61s simulated, O(online) adds).
step(61)
local stored = smp_store.api.get_player("alice").playtime
ok(stored >= 60, "T11 flushed at the interval (stored " .. tostring(stored) .. ")")
eq(smp_stats.get("alice", "playtime"), stored,
	"T11 get() == stored after the flush (pending zeroed)")

-- Leave flushes immediately: nothing waits for the next interval.
smp_stats.add_playtime("alice", 3)
eq(smp_stats.get("alice", "playtime"), stored + 3, "pending before leave")
leave("alice")
eq(smp_store.api.get_player("alice").playtime, stored + 3,
	"T11 leave flushes pending immediately")

-- Shutdown flushes whatever remains.
local alice2 = join("alice")
smp_stats.add_playtime("alice", 5)
for _, h in ipairs(shutdown_handlers) do h() end
eq(smp_store.api.get_player("alice").playtime, stored + 3 + 5,
	"T11 shutdown flushes pending")
eq(smp_stats._pending_playtime["alice"], nil, "pending cleared on shutdown")

-- add_playtime signature per §6: name or ObjectRef. The shutdown
-- flush cleared the pending table, so these start from zero.
eq(smp_stats.add_playtime(alice2, 2), 2, "add_playtime accepts an ObjectRef")
eq(smp_stats.add_playtime("alice", 0), 2, "zero seconds is a no-op")
ok(smp_stats.flush_playtime() >= 1, "explicit flush writes players")
eq(smp_store.api.get_player("alice").playtime, stored + 3 + 5 + 2,
	"explicit flush lands the last 2 seconds")

----------------------------------------------------------------------
print("== in-game test suite (mods/smp_stats/test.lua) ==")
do
	local chunk, lerr = loadfile(ROOT .. "/friedcake/mods/smp_stats/test.lua")
	ok(chunk ~= nil, "test.lua loads: " .. tostring(lerr))
	if chunk then
		local good, res = pcall(chunk)
		ok(good, "test.lua runs: " .. tostring(res))
		if good and type(res) == "table" then
			eq(res.failed, 0, "in-game suite has no failures ("
				.. tostring(res.passed) .. " passed)")
			for _, l in ipairs(res.lines or {}) do print("  " .. l) end
		end
	end
end

----------------------------------------------------------------------
print(string.format("passed=%d failed=%d", passed, failed))
if failed > 0 then
	print("TEST_STATS FAILED")
	os.exit(1)
end
print("ALL OK")
