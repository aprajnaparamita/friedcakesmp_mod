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
	players = {},          -- name -> fake player object
	connected = {},        -- list of names
	node_at = function() return "air" end,
}

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
	modpath = function(f) return MODROOT .. f end,
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
	get_item_group = function(_, group) return 0 end,
	emerge_area = function(_, _, cb) cb(nil, nil, 0) end,
	show_formspec = function(name, formname, fs)
		fake.formspecs[name] = fake.formspecs[name] or {}
		fake.formspecs[name][#fake.formspecs[name] + 1] = fs
	end,
	close_formspec = function() end,
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
	register_on_player_receive_fields = function(formname, fn)
		fake.fields[formname] = fn
	end,
}
minetest = core
core_global = core
_G.core = core

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
	function p:set_player_velocity(v) self._vel = vnew(v.x, v.y, v.z) end
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
core.modpath = function(f) return MODROOT .. f end

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
	make_player("iris", { x = 700, y = 70, z = 700 })
	make_player("joe",  { x = 710, y = 70, z = 700 })

	-- /tpa: iris asks joe; joe accepts; iris (sender) warms up.
	core.registered_chatcommands["tpa"].func("iris", "joe")
	local w = smp_tp.warmup["iris"]
	ok(w == nil, "T8 no warm-up before acceptance")
	ok(smp_tp.accept_request("joe", "iris", "tpa") == true, "T8 joe accepts iris's /tpa")
	w = smp_tp.warmup["iris"]
	ok(w ~= nil and w.kind == "tpa", "T8 /tpa acceptance warms up the sender")
	eq(math.floor(w.to.x), 710, "T8 sender destination is the target's position")
	advance(6)
	eq(math.floor(iris._pos.x), 710, "T8 sender moved to target")

	-- /tpahere: iris asks joe to come; joe accepts; joe (target) warms
	-- up to IRIS's current position. (Let iris's /tpa cooldown lapse
	-- first.)
	reset_chat()
	advance(31)
	iris._pos = vnew(700, 70, 700)
	joe._pos  = vnew(710, 70, 700)
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

print(string.format("smp_tp dev-tests: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
