-- FriedcakeSMP dev smoke test: smp_tp + smp_rtpqueue
--
-- Covers the parts of spec/features/f08-teleport.md §9 that are testable
-- without a live server:
--   T1  /rtp opens no menu and begins a warm-up immediately
--   T3  moving > 1 node during the warm-up cancels; player is told
--   T4  taking damage during the warm-up cancels
--   T5  failed search sends the failure message and starts no cooldown
--   T6  cooldown blocks a second /rtp; tier1 cooldown is shorter
--   T7  /tpa to a blocking target produces one generic refusal that
--       reveals nothing about which rule fired
--   T8  accepting /tpa warms up the sender; /tpahere warms up the target
--   T9  a request where either party is tagged before acceptance dies
--   T10 /world returns to the position before the last teleport and
--       does not chain
--   T11 two mutually blocking players are never paired by /rtpqueue
--   T12 the RTP zone teleports after rtp.zone_delay, not on pass-through
--   T13 tp.confirm_menu shows Deny left/red, Accept right/green
--
-- The safe-y finder is exercised against a fake world column (T2's
-- reject list: water, lava, fire, cactus, magma, campfire, sweet berry,
-- powder snow, leaves; two breathable nodes above; End end-stone rule;
-- Nether downward search).
--
-- Run: luajit friedcake/dev-tests/test_tp.lua
-- Exits non-zero on any failure.

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
		error("vector.new: bad arg v=" .. tostring(v) .. " y=" .. tostring(y) .. " z=" .. tostring(z))
	end,
	distance = vdist,
	offset = function(v, dx, dy, dz) return vnew(v.x + dx, v.y + dy, v.z + dz) end,
}

----------------------------------------------------------------------
-- Fake time + fake core.after
----------------------------------------------------------------------

local now = 1000000
os.time = function() return now end

local fake = {
	pending = {},          -- { {at, fn}, ... }
	chat = {},             -- per-player chat log: {[name] = {msgs}}
	formspecs = {},        -- {[name] = {fs strings}}
	titles = {},           -- action bar log: {[name] = {texts}}
	hpchange = nil,        -- the registered callback
	globalsteps = {},      -- registered globalstep fns
	leaves = {}, die = {}, fields = {},
	players = {},          -- name -> fake player object (connected)
	authdb = {},           -- name -> true: exists in the auth DB, online or not
	connected = {},        -- list of names
	node_at = function() return "air" end,
}

----------------------------------------------------------------------
-- MS-3: strict player-name stubs
--
-- The engine's name-taking functions are bound with luaL_checkstring,
-- so a nil or numeric player name raises a Lua error there. A fake
-- that silently tolerates it would hide exactly that class of bug
-- (the harness encoding the bug — see test_engine_apis.lua), so these
-- stubs raise the same way. Each test file carries its own copy on
-- purpose: dev-tests share no harness module.
----------------------------------------------------------------------

local function check_name(fn, name)
	if type(name) ~= "string" then
		error(string.format(
			"bad argument #1 to '%s' (string expected, got %s)",
			fn, type(name)), 0)
	end
end

local function advance(dt)
	now = now + math.floor(dt)
	while true do
		local due = nil
		for i, p in ipairs(fake.pending) do
			if p.at <= now and (not due or p.at < due.at) then
				due = p
			end
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

local core = {
	log = function(_, ...) end,
	get_translator = S_factory,
	get_current_modname = function() return "smp_tp" end,
	after = function(sec, fn)
		fake.pending[#fake.pending + 1] = { at = now + math.max(1, math.floor(sec)), fn = fn }
	end,
	chat_send_player = function(name, msg)
		check_name("chat_send_player", name)
		fake.chat[name] = fake.chat[name] or {}
		fake.chat[name][#fake.chat[name] + 1] = msg
	end,
	get_player_by_name = function(name)
		check_name("get_player_by_name", name)
		return fake.players[name]
	end,
	player_exists = function(name)
		check_name("player_exists", name)
		return fake.players[name] ~= nil or fake.authdb[name] == true
	end,
	get_connected_players = function()
		local out = {}
		for name in pairs(fake.players) do out[#out + 1] = fake.players[name] end
		return out
	end,
	get_node = function(pos) return { name = fake.node_at(pos.x, pos.y, pos.z) } end,
	get_item_group = function(name, group)
		local def = core.registered_nodes and core.registered_nodes[name]
		if def and type(def.groups) == "table" then
			return def.groups[group] or 0
		end
		return 0
	end,
	emerge_area = function(_, _, cb) cb(nil, nil, 0) end,
	show_formspec = function(name, formname, fs)
		check_name("show_formspec", name)
		fake.formspecs[name] = fake.formspecs[name] or {}
		fake.formspecs[name][#fake.formspecs[name] + 1] = fs
	end,
	close_formspec = function(name, formname)
		check_name("close_formspec", name)
	end,
	get_gametime = function() return now end,
	settings = nil,
	register_chatcommand = function(name, def)
		core.registered_chatcommands[name] = def
	end,
	registered_chatcommands = {},
	register_on_player_hpchange = function(fn) fake.hpchange = fn end,
	register_globalstep = function(fn) fake.globalsteps[#fake.globalsteps + 1] = fn end,
	register_on_leaveplayer = function(fn) fake.leaves[#fake.leaves + 1] = fn end,
	register_on_dieplayer = function(fn) fake.die[#fake.die + 1] = fn end,
	register_on_player_receive_fields = function(a, b)
		if type(a) == "function" then
			-- 5.17 single-callback API: fn(player, formname, fields)
			fake.receive_fields = a
		else
			-- legacy (formname, func) form
			fake.fields[a] = function(player, formname, fields)
				if formname == a then return b(player, fields) end
			end
		end
	end,
}
minetest = core
core_global = core
_G.core = core

-- Node definitions, so destination safety (S08/TP-1) and rtp.lua see
-- what the engine would report. Values mirror Mineclonia: lava
-- damage_per_second 8 with group lava=3, fire damage_per_second 1 with
-- group fire=1. Registering them changes no /rtp result — every name
-- below is already on find_safe_y's reject list, and unregistered
-- names keep the "unknown = solid" fallback.
core.registered_nodes = {
	["air"]                    = { walkable = false },
	["ignore"]                 = { walkable = false },  -- unloaded mapblock
	["mcl_core:dirt"]          = { walkable = true },
	["mcl_core:stone"]         = { walkable = true },
	["mcl_core:water_source"]  = { walkable = false, groups = { liquid = 3 } },
	["mcl_core:lava_source"]   = { walkable = false, damage_per_second = 8,
	                                groups = { liquid = 2, lava = 3 } },
	["mcl_fire:fire"]          = { walkable = false, damage_per_second = 1,
	                                groups = { fire = 1 } },
	-- Damaging by GROUP only: catches a get_item_group-only path.
	["mcl_campfires:campfire"] = { walkable = true, groups = { fire = 1 } },
	-- Bottom slab: walkable, and a standing player occupies its node
	-- (collision boxes — the legitimate solid-feet case).
	["mcl_stairs:slab_stone"]  = { walkable = true },
}

local mcl_title = {
	set = function(player, type, data)
		local name = player:get_player_name()
		fake.titles[name] = fake.titles[name] or {}
		fake.titles[name][#fake.titles[name] + 1] = data.text
	end,
}
mcl_title_global = mcl_title
-- mcl_title is referenced as a global by the mod.
_G.mcl_title = mcl_title

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
	function p:get_velocity() return vnew(self._vel.x, self._vel.y, self._vel.z) end
	function p:add_velocity(v) self._vel = vnew(self._vel.x + v.x, self._vel.y + v.y, self._vel.z + v.z) end
	function p:get_meta()
		return { get = function() return "" end, set = function() end }
	end
	fake.players[name] = p
	_G[name] = p  -- the test body references players by bare name
	return p
end

----------------------------------------------------------------------
-- Load the mods under the fake engine
----------------------------------------------------------------------

-- Path resolution WITHOUT string pattern matching: this engine's
-- pattern-mode string.find is unreliable for strings containing the
-- byte sequence "b-" (present in "friedcake/dev-tests/"), so locate
-- the mods directory by probing candidate paths.
local function readable(p)
	local f = io.open(p, "r")
	if f then f:close() return true end
	return false
end
local MODROOT
for _, c in ipairs({
	"../mods/smp_tp/",          -- cwd is friedcake/dev-tests/
	"mods/smp_tp/",             -- cwd is friedcake/
	"friedcake/mods/smp_tp/",   -- cwd is the repo root (the documented way)
}) do
	if readable(c .. "config.lua") then MODROOT = c break end
end
assert(MODROOT, "run this test as friedcake/dev-tests/test_tp.lua from the repo root (or inside it)")
core.get_modpath = function(m) return MODROOT:sub(1, -2) end

dofile(MODROOT .. "../smp_core/init.lua")
dofile(MODROOT .. "init.lua")
dofile(MODROOT .. "../smp_rtpqueue/init.lua")

----------------------------------------------------------------------
-- Test harness
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
local function chat_contains(name, needle)
	for _, m in ipairs(fake.chat[name] or {}) do
		if m:find(needle, 1, true) then return true end
	end
	return false
end
local function reset_chat()
	fake.chat = {}
	fake.formspecs = {}
	fake.titles = {}
end

----------------------------------------------------------------------
-- Fake world for the safe-y finder
--
-- column(x, z) = list of y -> node name. The default world (set in
-- "Setup" below) is flat dirt at y=60 everywhere, so /rtp searches
-- succeed at any random (x, z).
----------------------------------------------------------------------

local cols = {}
local function setcol(x, z, tbl)
	cols[x .. "," .. z] = tbl
end
-- Default world: flat dirt at y=60 everywhere, unless a column is set.
local function default_node_at(px, py, pz)
	local c = cols[px .. "," .. pz]
	if c then return c[py] or "air" end
	if py == 60 then return "mcl_core:dirt" end
	return "air"
end
fake.node_at = default_node_at
local function plain_cols()
	cols = {}
	fake.node_at = function() return "air" end
end

----------------------------------------------------------------------
-- Setup: players in a flat dirt overworld (y=60).
----------------------------------------------------------------------

local function fresh_world()
	cols = {}
	fake.node_at = default_node_at
end

fresh_world()
make_player("alice", { x = 100, y = 70, z = 100 })

----------------------------------------------------------------------
-- T1 — /rtp opens no menu and begins a warm-up immediately
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	local cmd = core.registered_chatcommands["rtp"]
	ok(cmd ~= nil, "T1 /rtp registered")
	local r = cmd.func("alice", "")
	ok(r == true, "T1 /rtp accepted")
	local w = smp_tp.warmup["alice"]
	ok(w ~= nil, "T1 warm-up started immediately")
	ok(w and w.kind == "rtp", "T1 warm-up kind is rtp")
	ok(next(fake.formspecs["alice"] or {}) == nil,
		"T1 no formspec (menu) opened by /rtp")
	ok(smp_tp.cfg.rtp.menu_enabled == false, "T1 rtp.menu_enabled is false")
	-- The warm-up fires and alice lands on her dirt column.
	advance(6)
	eq(math.floor(alice._pos.y), 61, "T1 alice landed on top of dirt")
	ok(smp_tp.warmup["alice"] == nil, "T1 warm-up cleared after firing")
	-- Action bar was used for the countdown.
	ok(#(fake.titles["alice"] or {}) >= 1, "T1 action-bar countdown issued")
end

----------------------------------------------------------------------
-- T3 — movement > 1 node during warm-up cancels; player is told
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("bob", { x = 200, y = 70, z = 200 })
	core.registered_chatcommands["rtp"].func("bob", "")
	ok(smp_tp.warmup["bob"] ~= nil, "T3 warm-up started")
	-- Bob moves 3 nodes.
	bob._pos = vnew(203, 70, 200)
	advance(6)
	ok(smp_tp.warmup["bob"] == nil, "T3 warm-up cancelled on movement")
	eq(math.floor(bob._pos.x), 203, "T3 bob was NOT moved")
	ok(chat_contains("bob", "Teleport cancelled"), "T3 bob told the teleport was cancelled")
end

----------------------------------------------------------------------
-- T4 — damage during the warm-up cancels
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("cara", { x = 300, y = 70, z = 300 })
	core.registered_chatcommands["rtp"].func("cara", "")
	ok(smp_tp.warmup["cara"] ~= nil, "T4 warm-up started")
	ok(fake.hpchange ~= nil, "T4 hpchange hook registered")
	fake.hpchange(cara, -2, { type = "combat" })
	ok(smp_tp.warmup["cara"] == nil, "T4 warm-up cancelled on damage")
	ok(chat_contains("cara", "Teleport cancelled"), "T4 cara told")
	advance(6)
	eq(math.floor(cara._pos.y), 70, "T4 cara was not teleported")
end

----------------------------------------------------------------------
-- Warm-up: combat-tagged refusal
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("dan", { x = 400, y = 70, z = 400 })
	local tagged = { dan = true }
	_G.smp_combat = { is_tagged = function(n) return tagged[n] == true end }
	local r = core.registered_chatcommand and nil
	-- Direct API: the framework itself refuses.
	local okw, reason = smp_tp.teleport_with_warmup(dan, vnew(400, 71, 400), "warp")
	ok(okw == false and reason == "combat", "combat-tagged warm-up refused")
	_G.smp_combat = nil
end

----------------------------------------------------------------------
-- T5 — failed search: failure message, NO cooldown starts
----------------------------------------------------------------------

do
	reset_chat()
	-- A world with no walkable node anywhere in the scan band.
	setcol(100, 100, { [200] = "mcl_core:water_source" })
	fake.node_at = function() return "mcl_core:lava_source" end  -- everything lava
	make_player("eve", { x = 100, y = 70, z = 100 })
	local r = core.registered_chatcommands["rtp"].func("eve", "")
	ok(r == true, "T5 /rtp accepted (search started)")
	ok(chat_contains("eve", "No safe location found"), "T5 failure message sent")
	local st = smp_tp.get_state("eve")
	ok(st.cooldowns.rtp == nil, "T5 no cooldown after total failure")
	-- And eve can immediately retry (no cooldown blocks her).
	fresh_world()
	local r2 = core.registered_chatcommands["rtp"].func("eve", "")
	ok(r2 == true, "T5 retry immediately allowed")
	ok(smp_tp.warmup["eve"] ~= nil, "T5 retry starts a warm-up")
	advance(6)
end

----------------------------------------------------------------------
-- T6 — cooldown blocks a second /rtp; tier1 is shorter
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("frank", { x = 500, y = 70, z = 500 })
	core.registered_chatcommands["rtp"].func("frank", "")
	advance(6)  -- lands
	local st = smp_tp.get_state("frank")
	ok(st.cooldowns.rtp ~= nil, "T6 cooldown started after success")
	local r = core.registered_chatcommands["rtp"].func("frank", "")
	ok(r == false, "T6 second /rtp blocked by cooldown")
	ok(chat_contains("frank", "again in"), "T6 cooldown message names the wait")

	-- Cooldown values: default 60, tier1 30.
	eq(smp_tp.cooldown_secs("frank", "rtp"), 60, "T6 default tier cooldown 60s")
	_G.smp_ranks = { tier = function(n) return "tier1" end }
	eq(smp_tp.cooldown_secs("frank", "rtp"), 30, "T6 tier1 cooldown 30s")
	_G.smp_ranks = nil
	advance(61)  -- let frank's cooldown lapse
end

----------------------------------------------------------------------
-- T7 — /tpa generic refusal reveals nothing
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("gina", { x = 600, y = 70, z = 600 })
	make_player("hank", { x = 610, y = 70, z = 600 })
	-- hank blocks gina (f11 stub).
	_G.smp_social = {
		blocks = function(a, b) return a == "hank" and b == "gina" end,
	}
	local r = core.registered_chatcommands["tpa"].func("gina", "hank")
	ok(r == false, "T7 /tpa to blocking target refused")
	local blocked_msg = last_chat("gina")
	ok(blocked_msg:find("cannot be asked") ~= nil, "T7 refusal is the generic message")
	ok(blocked_msg:lower():find("block") == nil, "T7 message does not mention blocking")
	ok(blocked_msg:lower():find("offline") == nil, "T7 message does not reveal online state")

	-- Offline target produces the IDENTICAL message (reveals nothing).
	reset_chat()
	local r2 = core.registered_chatcommands["tpa"].func("gina", "nobody_here")
	ok(r2 == false, "T7 /tpa to unknown player refused")
	eq(last_chat("gina"), blocked_msg, "T7 offline and blocked refusals are identical")
	_G.smp_social = nil
end

----------------------------------------------------------------------
-- T8 — /tpa accept warms up the SENDER; /tpahere warms up the TARGET
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	-- y=61: standing on the dirt at y=60, so the /tpa destinations are
	-- real, safe spots (S08 destination safety checks them).
	make_player("iris", { x = 700, y = 61, z = 700 })
	make_player("joe",  { x = 710, y = 61, z = 700 })

	-- /tpa: iris asks joe; joe accepts; iris (sender) warms up.
	core.registered_chatcommands["tpa"].func("iris", "joe")
	local w = smp_tp.warmup["iris"]
	ok(w == nil, "T8 no warm-up before acceptance")
	ok(smp_tp.accept_request("joe", "iris", "tpa") == true, "T8 joe accepts iris's /tpa")
	w = smp_tp.warmup["iris"]
	ok(w ~= nil and w.kind == "tpa", "T8 /tpa acceptance warms up the sender")
	eq(math.floor(w.to.x), 710, "T8 sender destination is the target's position")
	ok(w.check_dest == true, "T8 counterparty destination is safety-checked")
	advance(6)
	eq(math.floor(iris._pos.x), 710, "T8 sender moved to target")

	-- /tpahere: iris asks joe to come; joe accepts; joe (target) warms
	-- up to IRIS's current position. (Let iris's /tpa cooldown lapse
	-- first.)
	reset_chat()
	advance(31)
	iris._pos = vnew(700, 61, 700)
	joe._pos  = vnew(710, 61, 700)
	core.registered_chatcommands["tpahere"].func("iris", "joe")
	ok(smp_tp.warmup["joe"] == nil, "T8 no warm-up before /tpahere acceptance")
	ok(smp_tp.accept_request("joe", "iris", "tpahere") == true, "T8 joe accepts /tpahere")
	local wj = smp_tp.warmup["joe"]
	ok(wj ~= nil and wj.kind == "tpahere", "T8 /tpahere acceptance warms up the target")
	advance(6)
	eq(math.floor(joe._pos.x), 700, "T8 target moved to sender")
end

----------------------------------------------------------------------
-- T9 — request cancelled when a party is combat-tagged before accept
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("kim",  { x = 800, y = 70, z = 800 })
	make_player("luke", { x = 810, y = 70, z = 810 })
	core.registered_chatcommands["tpa"].func("kim", "luke")
	-- kim gets tagged before luke accepts.
	_G.smp_combat = { is_tagged = function(n) return n == "kim" end }
	ok(smp_tp.accept_request("luke", "kim", "tpa") == false,
		"T9 acceptance refused while sender is tagged")
	_G.smp_combat = nil
	-- The request pair was dropped.
	local st = smp_tp.get_state("luke")
	ok(st.requests_in["kim"] == nil, "T9 request removed from target")
end

----------------------------------------------------------------------
-- T10 — /world returns to the pre-teleport position and does not chain
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("mia", { x = 900, y = 70, z = 900 })
	local pre = { x = 900, y = 70, z = 900 }
	core.registered_chatcommands["rtp"].func("mia", "")
	advance(6)
	local st = smp_tp.get_state("mia")
	ok(st.last_teleport_from ~= nil, "T10 origin recorded")
	eq(st.last_teleport_from.x, pre.x, "T10 origin x matches")
	eq(st.last_teleport_from.y, pre.y, "T10 origin y matches")

	local r = core.registered_chatcommands["world"].func("mia", "")
	ok(r == true, "T10 /world accepted")
	local w = smp_tp.warmup["mia"]
	ok(w ~= nil and w.kind == "world", "T10 /world uses the warm-up")
	eq(math.floor(w.to.y), 70, "T10 /world destination is the origin (y=70)")
	advance(6)
	eq(math.floor(mia._pos.y), 70, "T10 mia back at her origin height")
	-- One level deep: /world did NOT refresh the origin, so a second
	-- /world goes to the SAME place (no chaining backwards).
	eq(st.last_teleport_from.y, 70, "T10 origin unchanged after /world")
	local r2 = core.registered_chatcommands["world"].func("mia", "")
	local w2 = smp_tp.warmup["mia"]
	ok(r2 == true and w2 and w2.to.y == 70, "T10 second /world does not chain")
	advance(6)
end

----------------------------------------------------------------------
-- RTP zone (T12)
----------------------------------------------------------------------

do
	reset_chat()
	-- nina stands just inside the default zone box (spawn 0,72,0,
	-- box -4..4).
	make_player("nina", { x = 2, y = 72, z = 2 })
	make_player("oscar", { x = 100, y = 72, z = 100 })
	-- Stand inside for zone_delay (3 s): checked once per second.
	smp_tp.rtp_zone_step(1)
	local st = smp_tp.get_state("nina")
	ok(st.zone_entered_at ~= nil, "T12 zone entry recorded")
	eq(math.floor(nina._pos.x), 2, "T12 not teleported on first check")
	advance(1)
	smp_tp.rtp_zone_step(1)
	eq(math.floor(nina._pos.x), 2, "T12 not teleported at 1 s")
	advance(1)
	smp_tp.rtp_zone_step(1)
	eq(math.floor(nina._pos.x), 2, "T12 not teleported at 2 s")
	advance(1)
	smp_tp.rtp_zone_step(1)
	eq(math.floor(nina._pos.x), 0, "T12 teleported to spawn after 3 s")
	eq(math.floor(nina._pos.y), 72, "T12 teleported to spawn height")
	ok(st.zone_entered_at == nil, "T12 zone timer reset after teleport")

	-- Pass-through: oscar steps in and out within the delay.
	oscar._pos = vnew(0, 72, 0)
	advance(1)
	smp_tp.rtp_zone_step(1)
	local st2 = smp_tp.get_state("oscar")
	ok(st2.zone_entered_at ~= nil, "T12 pass-through: entry recorded")
	oscar._pos = vnew(50, 72, 50)  -- leaves before the delay
	advance(1)
	smp_tp.rtp_zone_step(1)
	ok(st2.zone_entered_at == nil, "T12 pass-through: timer reset on exit")
	oscar._pos = vnew(51, 72, 51)
	eq(math.floor(oscar._pos.x), 51, "T12 pass-through did NOT teleport")
end

----------------------------------------------------------------------
-- T13 — Accept/Deny formspec: Deny left/red, Accept right/green
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("pat", { x = 1000, y = 70, z = 1000 })
	make_player("quinn", { x = 1010, y = 70, z = 1010 })
	core.registered_chatcommands["tpa"].func("pat", "quinn")
	local fss = fake.formspecs["quinn"]
	ok(fss and #fss == 1, "T13 confirm_menu dialog shown to the recipient")
	local fs = fss and fss[#fss] or ""
	ok(fs:find("style[deny;bgcolor=red]", 1, true) ~= nil, "T13 Deny is red")
	ok(fs:find("style[accept;bgcolor=green]", 1, true) ~= nil, "T13 Accept is green")
	-- Parse button x-positions without pattern matching (this engine's
	-- pattern matcher is unreliable; see f08 §10).
	local function button_x(fspec, fieldname)
		local pos = 1
		while true do
			local b = fspec:find("button[", pos, true)
			if not b then return nil end
			local e = fspec:find("]", b, true)
			if not e then return nil end
			local spec = fspec:sub(b + 7, e - 1)  -- "x,y;w,h;field;label"
			local sep1 = spec:find(";", 1, true)
			local sep2 = spec:find(";", sep1 + 1, true)
			local sep3 = spec:find(";", sep2 + 1, true)
			if sep1 and sep2 and sep3 then
				if spec:sub(sep2 + 1, sep3 - 1) == fieldname then
					local comma = spec:find(",", 1, true)
					if comma then return tonumber(spec:sub(1, comma - 1)) end
				end
			end
			pos = b + 7
		end
	end
	local deny_x, accept_x = button_x(fs, "deny"), button_x(fs, "accept")
	ok(deny_x and accept_x, "T13 both buttons parsed from the formspec")
	ok(deny_x and accept_x and deny_x < accept_x, "T13 Deny is left of Accept")
	ok(fs:find("Teleport Request") ~= nil, "T13 dialog title")
end

----------------------------------------------------------------------
-- T11 — mutually blocking players are never paired
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("rosie", { x = 1100, y = 70, z = 1100 })
	make_player("sam", { x = 1105, y = 70, z = 1105 })
	-- Mutual block.
	_G.smp_social = {
		blocks = function(a, b)
			return (a == "rosie" and b == "sam") or (a == "sam" and b == "rosie")
		end,
	}
	core.registered_chatcommands["rtpqueue"].func("rosie", "")
	ok(smp_rtpqueue.members["rosie"] ~= nil, "T11 rosie queued")
	core.registered_chatcommands["rtpqueue"].func("sam", "")
	ok(smp_rtpqueue.members["sam"] ~= nil, "T11 sam queued")
	ok(smp_rtpqueue.members["rosie"] ~= nil and smp_rtpqueue.members["sam"] ~= nil,
		"T11 both still queued (no match happened)")
	ok(not chat_contains("rosie", "You matched"), "T11 rosie not matched")
	ok(not chat_contains("sam", "You matched"), "T11 sam not matched")
	-- A non-blocking player DOES pair with the head of the queue.
	make_player("tina", { x = 1110, y = 70, z = 1110 })
	_G.smp_social = { blocks = function(a, b)
		return (a == "rosie" and b == "sam") or (a == "sam" and b == "rosie")
	end }
	core.registered_chatcommands["rtpqueue"].func("tina", "")
	-- tina should pair with the earliest non-blocking member.
	local matched_rosie = chat_contains("rosie", "You matched")
	local matched_sam = chat_contains("sam", "You matched")
	ok(matched_rosie or matched_sam, "T11 non-blocking pair formed")
	_G.smp_social = nil
end

----------------------------------------------------------------------
-- Safe-y finder: the reject list (T2's node-level rules)
----------------------------------------------------------------------

do
	local band = { min = 50, max = 64 }
	local function test_col(tbl, expect_y, msg)
		setcol(10, 10, tbl)
		local pos = smp_tp.find_safe_y(10, 10, "overworld", band)
		if expect_y == nil then
			ok(pos == nil, msg .. " (rejected)")
		else
			ok(pos ~= nil and math.floor(pos.y) == expect_y,
				string.format("%s (expected y=%d, got %s)", msg, expect_y,
					pos and tostring(math.floor(pos.y)) or "nil"))
		end
	end
	test_col({ [60] = "mcl_core:dirt", [59] = "mcl_core:stone" }, 61, "plain dirt")
	test_col({ [60] = "mcl_core:water_source" }, nil, "water")
	test_col({ [60] = "mcl_core:lava_source" }, nil, "lava")
	test_col({ [60] = "mcl_fire:fire" }, nil, "fire")
	test_col({ [60] = "mcl_core:cactus" }, nil, "cactus")
	test_col({ [60] = "mcl_nether:magma" }, nil, "magma")
	test_col({ [60] = "mcl_campfires:campfire" }, nil, "campfire")
	test_col({ [60] = "mcl_farming:sweet_berry_bush_2" }, nil, "sweet berry")
	test_col({ [60] = "mcl_powder_snow:powder_snow" }, nil, "powder snow")
	test_col({ [60] = "mcl_trees:leaves_oak" }, nil, "leaves")
	-- Two blocked nodes above: water at 62.
	test_col({ [60] = "mcl_core:dirt", [62] = "mcl_core:water_source" }, nil,
		"blocked node above")
	-- Fire above the dirt.
	test_col({ [60] = "mcl_core:dirt", [61] = "mcl_fire:fire" }, nil,
		"fire above landing")
	-- Landing under a lava ceiling is fine (lava is not a breathable
	-- hazard above? it IS liquid -> rejected).
	test_col({ [60] = "mcl_core:dirt", [61] = "mcl_core:lava_source" }, nil,
		"lava above landing")
	-- Regression: the nodes above the landing must be NON-SOLID. A solid
	-- seafloor/beach under water used to pass the old "breathable" check
	-- and bury the player in sand/gravel.
	test_col({ [60] = "mcl_core:sand", [59] = "mcl_core:sand",
		[58] = "mcl_core:sand", [61] = "mcl_core:water_source",
		[62] = "mcl_core:water_source", [63] = "mcl_core:water_source",
		[64] = "mcl_core:water_source" }, nil, "underwater seafloor rejected")
	test_col({ [61] = "mcl_core:gravel", [60] = "mcl_core:gravel",
		[59] = "mcl_core:gravel", [62] = "mcl_core:water_source",
		[63] = "mcl_core:water_source", [64] = "mcl_core:water_source" },
		nil, "gravel beach under water rejected")
	-- End: only end stone.
	local pos = smp_tp.find_safe_y(10, 10, "end", band)
	ok(pos == nil, "end: non-end-stone landing rejected")
	setcol(10, 10, { [60] = "mcl_end:end_stone" })
	pos = smp_tp.find_safe_y(10, 10, "end", band)
	ok(pos ~= nil and math.floor(pos.y) == 61, "end: end stone lands")
	-- Nether: downward search from below the ceiling.
	setcol(10, 10, { [210] = "mcl_nether:netherrack", [209] = "mcl_nether:netherrack" })
	local nband = { min = 190, max = 212 }
	pos = smp_tp.find_safe_y(10, 10, "nether", nband)
	ok(pos ~= nil and math.floor(pos.y) == 211, "nether: downward search lands on top")
	-- Nether: lava ceiling directly above the rock is rejected.
	setcol(10, 10, { [210] = "mcl_nether:netherrack", [211] = "mcl_core:lava_source",
		[205] = "mcl_nether:netherrack" })
	pos = smp_tp.find_safe_y(10, 10, "nether", nband)
	ok(pos ~= nil and math.floor(pos.y) == 206,
		"nether: skips lava-ceiling column, lands on lower rock")
end

----------------------------------------------------------------------
-- Warm-up: player logs off during the warm-up (no crash, no move)
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("uma", { x = 1200, y = 70, z = 1200 })
	core.registered_chatcommands["rtp"].func("uma", "")
	ok(smp_tp.warmup["uma"] ~= nil, "offline-test: warm-up started")
	-- uma disconnects: the leave hook clears state.
	for _, fn in ipairs(fake.leaves) do fn(uma) end
	advance(6)
	eq(math.floor(uma._pos.y), 70, "offline-test: uma not teleported after leaving")
	ok(smp_tp.warmup["uma"] == nil, "offline-test: no dangling warm-up")
end

----------------------------------------------------------------------
-- /back is disabled by default
----------------------------------------------------------------------

do
	reset_chat()
	make_player("vic", { x = 1300, y = 70, z = 1300 })
	local r = core.registered_chatcommands["back"].func("vic", "")
	ok(r == false, "back: /back refused while disabled")
end

----------------------------------------------------------------------
-- S08/TP-1a — /tpauto accepts /tpa only; /tpahere always prompts
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("tara", { x = 1400, y = 61, z = 1400 })
	make_player("vince", { x = 1410, y = 61, z = 1400 })
	smp_tp.get_state("vince").auto_accept = true   -- vince ran /tpauto

	-- Control: /tpa (the requester comes TO you) still auto-accepts.
	core.registered_chatcommands["tpa"].func("tara", "vince")
	local w = smp_tp.warmup["tara"]
	ok(w ~= nil and w.kind == "tpa", "TP1a /tpa is still auto-accepted with /tpauto on")
	ok(next(fake.formspecs["vince"] or {}) == nil,
		"TP1a no dialog for the auto-accepted /tpa")
	advance(6)
	eq(math.floor(tara._pos.x), 1410, "TP1a auto-accepted /tpa teleports the sender")

	-- The fix: /tpahere (YOU go where the sender stands) never
	-- auto-accepts — it prompts, and nothing moves.
	reset_chat()
	make_player("wanda", { x = 1420, y = 61, z = 1400 })
	core.registered_chatcommands["tpahere"].func("wanda", "vince")
	ok(smp_tp.warmup["vince"] == nil, "TP1a /tpahere does NOT auto-accept: no warm-up")
	local fss = fake.formspecs["vince"]
	ok(fss and #fss == 1, "TP1a /tpahere prompt shown to the target instead")
	ok(fss and fss[1]:find("Teleport Request", 1, true) ~= nil,
		"TP1a prompt is the Accept/Deny dialog")
	local tst = smp_tp.get_state("vince")
	ok(tst.requests_in["wanda"] ~= nil and tst.requests_in["wanda"]["tpahere"] ~= nil,
		"TP1a the request stays pending for an explicit /tpaccept")
	-- No timer runs on its own.
	advance(6)
	eq(math.floor(vince._pos.x), 1410, "TP1a target did not move")
	ok(smp_tp.warmup["vince"] == nil, "TP1a still no warm-up after the countdown")
end

----------------------------------------------------------------------
-- S08/TP-1b..d — the destination is re-checked at FIRE time
--
-- The trapper types /tpahere and stands where the victim will land;
-- the victim accepts, then the trapper rebuilds the spot during the
-- 5 s countdown.
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	local n = 0
	-- Returns the victim's name and the destination.
	local function trap_run(label, expected_feet, dest_y, before, after)
		n = n + 1
		local dest = { x = 1500 + n * 10, y = dest_y, z = 1500 }
		local trapper, victim = "evil" .. n, "prey" .. n
		if before then before(dest) end
		make_player(trapper, dest)
		make_player(victim, { x = dest.x - 3, y = 61, z = dest.z })
		core.registered_chatcommands["tpahere"].func(trapper, victim)
		local acc = smp_tp.accept_request(victim, trapper, "tpahere")
		ok(acc == true, label .. ": acceptance starts the warm-up")
		local w = smp_tp.warmup[victim]
		ok(w ~= nil, label .. ": warm-up recorded")
		ok(w ~= nil and w.dest_feet == expected_feet,
			label .. ": feet node captured at accept (" .. tostring(expected_feet) .. ")")
		if after then after(dest) end
		advance(6)
		return victim, dest
	end

	-- TP-1b: lava poured onto the destination during the countdown.
	local victim, dest = trap_run("TP1b", "air", 61, nil, function(d)
		setcol(d.x, d.z, { [61] = "mcl_core:lava_source", [60] = "mcl_core:dirt" })
	end)
	eq(math.floor(victim == "prey1" and prey1._pos.x or -1), dest.x - 3,
		"TP1b victim NOT teleported into the lava")
	eq(last_chat(victim), "The destination is not safe",
		"TP1b victim told the destination is not safe")

	-- TP-1c: a void shaft dug under the destination.
	victim, dest = trap_run("TP1c", "air", 61, nil, function(d)
		setcol(d.x, d.z, {})   -- the dirt at y=60 is gone: no ground left
	end)
	eq(math.floor(victim == "prey2" and prey2._pos.x or -1), dest.x - 3,
		"TP1c victim NOT teleported into the void")
	eq(last_chat(victim), "The destination is not safe",
		"TP1c victim told the destination is not safe")

	-- TP-1d: a solid block placed at the victim's feet node.
	victim, dest = trap_run("TP1d", "air", 61, nil, function(d)
		setcol(d.x, d.z, { [61] = "mcl_core:stone", [60] = "mcl_core:dirt" })
	end)
	eq(math.floor(victim == "prey3" and prey3._pos.x or -1), dest.x - 3,
		"TP1d victim NOT teleported into the trap block")
	eq(last_chat(victim), "The destination is not safe",
		"TP1d victim told the destination is not safe")

	-- Control: a destination that is ALREADY solid at the feet is a
	-- legitimate standing spot (bottom slab: the player occupies its
	-- node), and it must still work.
	victim, dest = trap_run("TP1-control", "mcl_stairs:slab_stone", 60.5,
		function(d)
			setcol(d.x, d.z, { [59] = "mcl_core:dirt", [60] = "mcl_stairs:slab_stone" })
		end, nil)
	eq(math.floor(victim == "prey4" and prey4._pos.x or -1), dest.x,
		"TP1-control slab destination still teleports (no false positive)")
	ok(last_chat(victim) == nil or last_chat(victim) ~= "The destination is not safe",
		"TP1-control no safety refusal")
end

----------------------------------------------------------------------
-- S08/TP-1 — an already-lethal destination is refused at ACCEPT time
-- (no warm-up is started, no request state left dangling)
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	-- The trapper stands in a void column when the request is accepted.
	local dest = { x = 1700, y = 61, z = 1700 }
	setcol(dest.x, dest.z, {})
	make_player("evil_v", dest)
	make_player("prey_v", { x = dest.x - 3, y = 61, z = dest.z })
	core.registered_chatcommands["tpahere"].func("evil_v", "prey_v")
	ok(smp_tp.accept_request("prey_v", "evil_v", "tpahere") == false,
		"TP1 accept refused when the destination is already unsafe")
	ok(smp_tp.warmup["prey_v"] == nil, "TP1 no warm-up started")
	eq(last_chat("prey_v"), "The destination is not safe",
		"TP1 accept-time refusal names the reason")
	eq(math.floor(prey_v._pos.x), dest.x - 3, "TP1 victim did not move")
end

----------------------------------------------------------------------
-- S08/TP-2 — an offline account gets the generic refusal and NO state
----------------------------------------------------------------------

do
	reset_chat()
	fresh_world()
	make_player("yuri", { x = 1600, y = 61, z = 1600 })
	-- Exists in the auth database (core.player_exists is true) but
	-- nobody is connected under that name.
	fake.authdb["ghost_player"] = true

	local r = core.registered_chatcommands["tpa"].func("yuri", "ghost_player")
	ok(r == false, "TP2 /tpa to an offline account refused")
	local ghost_msg = last_chat("yuri")
	eq(ghost_msg, "This player cannot be asked for a teleport",
		"TP2 refusal is the T7 generic string, verbatim")
	ok(smp_tp.state["ghost_player"] == nil, "TP2 no state allocated for the offline target")

	-- Identical to the unknown-name refusal: one string, every rule.
	reset_chat()
	local r2 = core.registered_chatcommands["tpa"].func("yuri", "nobody_here")
	ok(r2 == false, "TP2 /tpa to an unknown name refused")
	eq(last_chat("yuri"), ghost_msg, "TP2 offline and unknown refusals are identical")
	ok(smp_tp.state["ghost_player"] == nil, "TP2 still no state for the offline target")
end

----------------------------------------------------------------------
-- MS-3 — the name-taking stubs raise on a non-string player name,
-- exactly as the engine's luaL_checkstring bindings do
----------------------------------------------------------------------

do
	local function raises(fn, ...)
		return not pcall(fn, ...)
	end
	ok(raises(core.chat_send_player, nil, "x"),
		"MS-3 chat_send_player raises on a nil name")
	ok(raises(core.get_player_by_name, 42),
		"MS-3 get_player_by_name raises on a number name")
	ok(raises(core.player_exists, {}),
		"MS-3 player_exists raises on a table name")
	ok(raises(core.show_formspec, nil, "form", ""),
		"MS-3 show_formspec raises on a nil name")
	ok(raises(core.close_formspec, nil, "form"),
		"MS-3 close_formspec raises on a nil name")
	-- ... and still accepts a real name.
	reset_chat()
	local good = pcall(core.chat_send_player, "__ms3_probe", "hello")
	ok(good, "MS-3 a string name is accepted")
	reset_chat()
end

----------------------------------------------------------------------

print(string.format("smp_tp dev-tests: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
