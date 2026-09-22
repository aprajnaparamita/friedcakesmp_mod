-- Standalone smoke test for smp_spawners (f07) — runs under plain
-- luajit, no engine. Stubs core, ItemStack, the node timer,
-- mcl_enchanting and mcl_experience, then loads smp_core and
-- smp_spawners and exercises the f07 acceptance tests T1–T6 plus the
-- Silk Touch dig rules (T7, T8) and stale-menu safety (T10).
--
-- Run: luajit friedcake/dev-tests/test_spawners.lua
-- Exits non-zero on any failure (tools/agent-flow.sh test).

-- Locate the repository root from the script path.
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
		print(string.format("FAIL: %s — expected %s got %s",
			tostring(msg), tostring(b), tostring(a)))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("FAIL: %s — expected %s (+/-%s) got %s",
			tostring(msg), tostring(b), tostring(tol or 1e-9),
			tostring(a)))
	end
end

----------------------------------------------------------------------
-- core.serialize / deserialize (same codec as test_orders.lua)
----------------------------------------------------------------------

local function ser_value(v)
	local t = type(v)
	if t == "number" then
		if v == math.floor(v) then return string.format("%.0f", v) end
		return string.format("%.17g", v)
	elseif t == "boolean" then return tostring(v)
	elseif t == "string" then return string.format("%q", v)
	elseif t == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local parts = {}
		for _, k in ipairs(keys) do
			parts[#parts + 1] = "[" .. ser_value(k) .. "]=" .. ser_value(v[k])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "nil"
end

----------------------------------------------------------------------
-- World state
----------------------------------------------------------------------

local function pk(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end

local nodes, metas, timers = {}, {}, {}
local placed_cb = {}
local field_handlers = {}
local leave_handlers = {}
local lbm_count = 0
local registered_entities = {}
local dropped = {}
local shown_forms = {}
local chats = {}
local now = 1000000
local function tick(t) now = now + (t or 1) end

local objects_inside_radius = {}  -- [n] = {pos, objs}; T4 probes this
local function get_objects_inside_radius(pos, r)
	return objects_inside_radius[pk(pos) .. ":" .. r] or {}
end

-- The mod calls os.time() for smp:last_update; drive it from the
-- simulated clock so accrual math is deterministic.
local real_os_time = os.time
os.time = function() return now end

----------------------------------------------------------------------
-- ItemStack stub
----------------------------------------------------------------------

local function new_itemstack(name, count)
	local meta = {}
	return {
		_name = name or "",
		_count = count or 1,
		_meta = meta,
		get_name = function(self) return self._name end,
		get_count = function(self) return self._count end,
		set_count = function(self, n) self._count = n end,
		get_meta = function(self)
			return {
				get_string = function(_, k) return meta[k] or "" end,
				set_string = function(_, k, v) meta[k] = tostring(v) end,
			}
		end,
		remove_item = function(self, n)
			self._count = self._count - (n or 1)
			if self._count <= 0 then self._name = "" end
			return self
		end,
		__tostring = function(self)
			return self._name .. "x" .. self._count
		end,
	}
end
ItemStack = function(name, count) return new_itemstack(name, count) end

----------------------------------------------------------------------
-- Fake players and inventories
----------------------------------------------------------------------

local function make_player(name, x, y, z)
	local inv = {}
	local p = {}
	p._name = name
	p._pos = { x = x or 0, y = y or 0, z = z or 0 }
	p._sneak = false
	p._inv = inv
	p.get_player_name = function() return name end
	p.get_pos = function() return p._pos end
	p.get_player_control = function()
		return { sneak = p._sneak }
	end
	p.get_inventory = function()
		return {
			add_item = function(self, list, stack)
				inv[#inv + 1] = stack
				return true
			end,
		}
	end
	return p
end

----------------------------------------------------------------------
-- core stub
----------------------------------------------------------------------

core = {
	DIR_DELIM = "/",
	get_translator = function(_)
		return function(s, ...)
			local args = { ... }
			return (s:gsub("@(%d+)", function(n)
				return tostring(args[tonumber(n)] or "")
			end))
		end
	end,
	get_current_modname = function() return _G.__current_modname or "smp_spawners" end,
	get_modpath = function(m) return ROOT .. "/friedcake/mods/" .. m end,
	settings = {
		get = function(_) return "" end,
		get_bool = function(_) return nil end,
	},
	log = function(level, msg)
		if level == "error" then print("[engine error] " .. tostring(msg)) end
	end,
	serialize = ser_value,
	deserialize = function(s)
		if type(s) ~= "string" or s == "" then return nil end
		local f = loadstring("return " .. s)
		if not f then return nil end
		local good, val = pcall(f)
		return good and val or nil
	end,
	-- world
	nodes_ = nodes,
	get_node_or_nil = function(pos)
		return nodes[pk(pos)] or { name = "air" }
	end,
	get_node = function(pos)
		return nodes[pk(pos)] or { name = "air" }
	end,
	place_node = function(pos, stack, placer)
		nodes[pk(pos)] = { name = stack:get_name() }
		for _, cb in ipairs(placed_cb) do cb(pos, { name = stack:get_name() }) end
		return true
	end,
	node_dig = function(pos, node)
		nodes[pk(pos)] = { name = "air" }
		timers[pk(pos)] = nil
	end,
	set_node = function(pos, node) nodes[pk(pos)] = node end,
	is_protected = function() return false end,
	item_drop = function(pos, stack)
		dropped[#dropped + 1] = stack
	end,
	get_meta = function(pos)
		local k = pk(pos)
		metas[k] = metas[k] or {}
		local t = metas[k]
		return {
			get_string = function(_, k2) return t[k2] or "" end,
			set_string = function(_, k2, v) t[k2] = tostring(v) end,
			get_int = function(_, k2) return math.floor(tonumber(t[k2]) or 0) end,
			set_int = function(_, k2, v) t[k2] = tostring(v) end,
			get_float = function(_, k2) return tonumber(t[k2]) or 0 end,
			set_float = function(_, k2, v) t[k2] = tostring(v) end,
		}
	end,
	get_node_timer = function(pos)
		local k = pk(pos)
		timers[k] = timers[k] or {}
		local t = timers[k]
		return {
			start = function(_, d) t.running = true; t.delay = d end,
			stop = function() t.running = false end,
			is_started = function() return t.running or false end,
		}
	end,
	on_timer = function(pos)
		-- fire the node timer callback, as the engine would
		local n = nodes[pk(pos)]
		if n and n.name == "smp_spawners:spawner" then
			local def = core.registered_nodes[n.name]
			if def and def.on_timer then def.on_timer(pos) end
		end
	end,
	-- registry
	registered_nodes = {},
	register_node = function(name, def) core.registered_nodes[name] = def end,
	registered_items = {},
	register_item = function(name, def) core.registered_items[name] = def end,
	register_lbm = function() lbm_count = lbm_count + 1 end,
	registered_entities = registered_entities,
	register_entity = function(name, def)
		registered_entities[name] = def
	end,
	add_entity = function(pos, name)
		error("smp_spawners must not add entities (T4): " .. tostring(name))
	end,
	get_objects_inside_radius = get_objects_inside_radius,
	objects_inside_radius = get_objects_inside_radius,
	-- player / chat
	get_player_by_name = function(name)
		return _G.__players and _G.__players[name] or nil
	end,
	chat_send_player = function(name, msg)
		chats[name] = chats[name] or {}
		chats[name][#chats[name] + 1] = msg
	end,
	-- formspecs
	show_formspec = function(name, formname, spec)
		shown_forms[name] = { formname = formname, spec = spec }
	end,
	close_formspec = function(name, formname)
		local f = shown_forms[name]
		if f and f.formname == formname then shown_forms[name] = nil end
	end,
	formspec_escape = function(s)
		if type(s) ~= "string" then return s end
		return (s:gsub("\\", "\\\\"):gsub("%]", "\\]"):gsub("%[", "\\["):gsub(";", "\\;"))
	end,
	-- callbacks
	register_on_placenode = function(fn) placed_cb[#placed_cb + 1] = fn end,
	register_on_dignode = function() end,
	register_on_player_receive_fields = function(fn)
		field_handlers[#field_handlers + 1] = fn
	end,
	register_on_leaveplayer = function(fn)
		leave_handlers[#leave_handlers + 1] = fn
	end,
	register_on_joinplayer = function() end,
	register_on_shutdown = function() end,
	register_on_globalstep = function() end,
	register_chatcommand = function() end,
	register_privilege = function() end,
	get_gametime = function() return now end,
}

----------------------------------------------------------------------
-- Mineclonia stubs
----------------------------------------------------------------------

mcl_enchanting = {
	has_enchantment = function(stack, id)
		if type(stack) ~= "table" then return false end
		return (stack._ench or {})[id] and true or false
	end,
}

local xp_granted = {}
mcl_experience = {
	add_xp = function(player, xp)
		local name = player:get_player_name()
		xp_granted[name] = (xp_granted[name] or 0) + xp
	end,
}

----------------------------------------------------------------------
-- Load the mods
----------------------------------------------------------------------

local function load_mod(mod)
	_G.__current_modname = mod
	local f, err = loadfile(ROOT .. "/friedcake/mods/" .. mod .. "/init.lua")
	assert(f, "loadfile " .. mod .. ": " .. tostring(err))
	local good, lerr = pcall(f)
	_G.__current_modname = nil
	assert(good, mod .. " init failed: " .. tostring(lerr))
end

load_mod("smp_core")
load_mod("smp_spawners")

----------------------------------------------------------------------
-- Test helpers
----------------------------------------------------------------------

local BONE = "mcl_mobitems:bone"
local function place_spawner(type_id, stack)
	local pos = { x = 10, y = 64, z = 10 }
	nodes[pk(pos)] = { name = "smp_spawners:spawner" }
	metas[pk(pos)] = {}
	smp_spawners.init_meta(pos, type_id)
	local meta = core.get_meta(pos)
	if stack then
		meta:set_int("smp:stack", stack)
		meta:set_string("infotext", smp_spawners.S("@1 Spawner x@2",
			smp_spawners.types.def[type_id].display, stack))
	end
	return pos
end

local function state(pos)
	return smp_spawners.read_state(pos)
end

local function store_sum(pos)
	local st = state(pos)
	return smp_spawners.store_total(st.store)
end

----------------------------------------------------------------------
-- T4 (run first as an invariant): zero entities, zero ABMs
----------------------------------------------------------------------

ok(lbm_count == 0, "T4 no ABMs registered")
ok(next(registered_entities) == nil, "T4 no entities registered")
local objs = get_objects_inside_radius({ x = 10, y = 64, z = 10 }, 16)
ok(#objs == 0, "T4 zero objects within radius after load")

----------------------------------------------------------------------
-- T1 — a stack of 1 produces r kills/min within 1% over 10 minutes
----------------------------------------------------------------------

do
	local r = smp_spawners.cfg.r
	local C = smp_spawners.cfg.C["skeleton"]
	-- curve(1, r, C) == r
	near(smp_spawners.curve(1, r, C), r, 1e-9, "T1 curve(1) == r")
	-- the spec's illustrative table
	near(smp_spawners.curve(10, 6, 1505.35), 58.9, 0.05, "T1 f(10) = 58.9")
	near(smp_spawners.curve(100, 6, 1505.35), 495.7, 0.05, "T1 f(100) = 495.7")
	near(smp_spawners.curve(1000, 6, 1505.35), 1477.6, 0.05, "T1 f(1000) = 1477.6")

	local pos = place_spawner("skeleton", 1)
	-- 10 simulated minutes through the node timer (60 s ticks), as the
	-- engine would drive it under accrual_mode active_only.
	local summary
	for i = 1, 10 do
		tick(60)
		summary = smp_spawners.accrue(pos, now)
	end
	ok(summary ~= nil, "T1 accrue returned a summary")
	local got = state(pos).store[BONE] or 0
	ok(math.abs(got - r * 10) / (r * 10) < 0.01,
		string.format("T1 10-min output within 1%% (got %s)", tostring(got)))
	near(state(pos).xp, r * 10 * 5, 1e-9, "T1 xp accrual")
	-- T4 again: still no objects after 60 s of production
	local o2 = get_objects_inside_radius(pos, 16)
	ok(#o2 == 0, "T4 zero objects after 10 simulated minutes")
end

----------------------------------------------------------------------
-- T2 — monotonic in stack size, decreasing marginal output
----------------------------------------------------------------------

do
	local r, C = smp_spawners.cfg.r, smp_spawners.cfg.C["skeleton"]
	-- Strictly increasing up to n = 7,000 (beyond that base^n
	-- underflows into the ulp and the curve is exactly C in floating
	-- point, which is non-strict monotonicity as expected).
	local prev = smp_spawners.curve(1, r, C)
	local monotone = true
	for n = 2, 7000 do
		local v = smp_spawners.curve(n, r, C)
		if v <= prev then monotone = false break end
		prev = v
	end
	ok(monotone, "T2 output strictly monotonic in stack size")
	-- The exact marginal is C * (1 - r/C) * (1 - r/C)^(n-1), a
	-- geometric decrease in n; test it directly (finite differences
	-- of the curve are float noise near the asymptote).
	local base = 1 - r / C
	local pm = r -- m(1) = f(1) - f(0) = r
	local decreasing = true
	for n = 2, 7000 do
		local m = r * base ^ (n - 1) -- f(n) - f(n-1) = r * base^(n-1)
		if m >= pm then decreasing = false break end
		pm = m
	end
	ok(decreasing, "T2 marginal output strictly decreases")
	-- Non-strict beyond that, and never above C.
	local flat = smp_spawners.curve(7000, r, C)
	local ok_flat, over = true, false
	for _, n in ipairs({ 8000, 100000, 1000000, 2147483647 }) do
		local v = smp_spawners.curve(n, r, C)
		if v < flat then ok_flat = false break end
		if v > C then over = true break end
		flat = v
	end
	ok(ok_flat, "T2 non-decreasing at large stacks")
	ok(not over, "T2 never above C at large stacks")
	-- per-type monotonicity too
	local pos = place_spawner("spider", 1)
	local a = smp_spawners.kills_per_min("spider", 1)
	local b = smp_spawners.kills_per_min("spider", 10)
	ok(b > a, "T2 spider rate rises with stack size")
end

----------------------------------------------------------------------
-- T3 — a stack of 1,000 approaches but never exceeds C
----------------------------------------------------------------------

do
	local r, C = smp_spawners.cfg.r, smp_spawners.cfg.C["skeleton"]
	local v = smp_spawners.curve(1000, r, C)
	ok(v < C, "T3 f(1000) < C")
	ok(v > C * 0.97, "T3 f(1000) within 3% of C")
	-- never exceeds at any size, even absurd
	local max_ok = true
	for _, n in ipairs({ 1, 2, 5, 64, 100, 1000, 100000, 2147483647 }) do
		if smp_spawners.curve(n, r, C) > C then max_ok = false end
	end
	ok(max_ok, "T3 curve never exceeds C")
	-- and a real 1000-stack accrue stays under C * minutes
	local pos = place_spawner("skeleton", 1000)
	tick(60)
	smp_spawners.accrue(pos, now)
	local got = state(pos).store[BONE] or 0
	ok(got < C and got > C * 0.97,
		string.format("T3 1000-stack 1-min output below C (got %s)",
			string.format("%.2f", got)))
end

----------------------------------------------------------------------
-- T5 — capacity pause and resume; nothing lost silently
----------------------------------------------------------------------

do
	-- Small capacity so the test is quick.
	smp_spawners.cfg.storage.per_spawner = 10
	local pos = place_spawner("skeleton", 1)

	-- Run until full: 100 minutes at 6/min = 600 potential kills.
	tick(6000)
	local s1 = smp_spawners.accrue(pos, now)
	ok(s1 and s1.paused_full == true, "T5 accrue reports capacity pause")
	near(store_sum(pos), 10, 1e-9, "T5 storage clamped to capacity")
	-- No silent banking: last_update advanced, so the 600 virtual kills
	-- are gone (discarded at full), not stored off-menu.
	near(state(pos).last_update, now, 1e-9, "T5 last_update advances at full")
	local meta = core.get_meta(pos)
	local v1 = meta:get_int("smp:version")

	-- One more tick while full: still full, no growth.
	tick(60)
	local s2 = smp_spawners.accrue(pos, now)
	ok(s2 and s2.added == 0, "T5 no output while full")
	near(store_sum(pos), 10, 1e-9, "T5 storage unchanged while full")

	-- Collect: take the 10 whole bones.
	local player = make_player("p5", 10, 65, 10)
	local taken = smp_spawners.take(pos, player, "skeleton", BONE, 64)
	eq(taken, 10, "T5 take after pause")
	near(store_sum(pos), 0, 1e-9, "T5 storage empty after collect")

	-- Resume: the next accrue produces again.
	tick(60)
	local s3 = smp_spawners.accrue(pos, now)
	ok(s3 and s3.added > 0 and s3.paused_full == false,
		"T5 production resumes after collection")
	ok(meta:get_int("smp:version") > v1, "T5 version counter moves")
	smp_spawners.cfg.storage.per_spawner = 2880
end

----------------------------------------------------------------------
-- T6 — two players collecting cannot double-collect (version counter)
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 1)
	-- Seed a whole 64 bones via a direct accrual of 64 minutes. The
	-- active_only clamp would cap this at 2 minutes, so use "always"
	-- for the seed and restore the default after. 640 s at 6/min is
	-- exactly 64 virtual kills.
	smp_spawners.cfg.accrual_mode = "always"
	tick(640)
	smp_spawners.accrue(pos, now)
	smp_spawners.cfg.accrual_mode = "active_only"
	local st = state(pos)
	near(st.store[BONE], 64, 1e-9, "T6 seeded 64 bones")
	local v0 = st.version

	-- Two viewers, both with the menu open at the same version.
	local a = make_player("p6a", 10, 65, 10)
	local b = make_player("p6b", 11, 65, 11)
	eq(a:get_pos().x, 10, "T6 player A in range")
	ok(smp_spawners.within_menu_range(pos, a), "T6 A within 8 nodes")
	ok(smp_spawners.within_menu_range(pos, b), "T6 B within 8 nodes")

	-- A collects.
	local ta = smp_spawners.take(pos, a, "skeleton", BONE, 64)
	eq(ta, 64, "T6 A takes 64")
	-- B acts "at the same moment": the handler re-reads the live state,
	-- so B must get nothing, not a second 64.
	local tb = smp_spawners.take(pos, b, "skeleton", BONE, 64)
	eq(tb, 0, "T6 B cannot double-collect")
	near(state(pos).store[BONE], 0, 1e-9, "T6 store empty, not negative")
	ok(state(pos).version > v0, "T6 version bumped by the collect")

	-- XP double-collect too.
	tick(60)
	smp_spawners.accrue(pos, now)
	local xa = smp_spawners.collect_xp(pos, a, "skeleton")
	local xb = smp_spawners.collect_xp(pos, b, "skeleton")
	ok((xa or 0) > 0 and (xb or 0) == 0, "T6 XP single-collect")
end

----------------------------------------------------------------------
-- T7 — digging without Silk Touch is refused
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 5)
	local def = core.registered_nodes["smp_spawners:spawner"]
	ok(def and type(def.on_dig) == "function", "T7 on_dig registered")
	local digger = make_player("p7", 10, 65, 10)
	local v0 = state(pos).version
	def.on_dig(pos, { name = "smp_spawners:spawner" }, digger,
		{ _name = "mcl_tools:pickaxe", _ench = {} })
	ok(core.get_node_or_nil(pos).name == "smp_spawners:spawner",
		"T7 node survives a dig without Silk Touch")
	eq(state(pos).stack, 5, "T7 stack unchanged")
	eq(state(pos).version, v0, "T7 no metadata mutation")
	-- With Silk Touch the dig removes one spawner.
	local st_tool = {
		_name = "mcl_tools:pickaxe",
		_ench = { silk_touch = 1 },
	}
	local okd, errd = pcall(def.on_dig, pos,
		{ name = "smp_spawners:spawner" }, digger, st_tool)
	assert(okd, "on_dig raised: " .. tostring(errd))
	eq(state(pos).stack, 4, "T7 Silk Touch dig removes one")
	local got = digger._inv[#digger._inv]
	ok(got and got:get_name() == "smp_spawners:spawner_item",
		"T7 digger receives a spawner item")
	eq(got:get_meta():get_string("type"), "skeleton",
		"T7 item carries the type")
end

----------------------------------------------------------------------
-- T8 — sneaking dig removes up to 64 and keeps the storage; the last
-- spawner removes the node
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 128)
	local def = core.registered_nodes["smp_spawners:spawner"]
	-- Seed storage first.
	tick(120)
	smp_spawners.accrue(pos, now)
	local before = store_sum(pos)
	ok(before > 0, "T8 storage seeded")

	local digger = make_player("p8", 10, 65, 10)
	digger._sneak = true
	local st_tool = { _name = "mcl_tools:pickaxe", _ench = { silk_touch = 1 } }
	def.on_dig(pos, { name = "smp_spawners:spawner" }, digger, st_tool)
	eq(state(pos).stack, 128 - 64, "T8 sneak dig removes 64 of 128")
	near(store_sum(pos), before, 1e-9, "T8 partial removal keeps storage")
	local got = digger._inv[#digger._inv]
	eq(got:get_count(), 64, "T8 digger receives 64 items")

	-- Remove the rest and then the last one: node gone, storage lost.
	local guard = 0
	while core.get_node_or_nil(pos).name ~= "air" and guard < 10 do
		def.on_dig(pos, { name = "smp_spawners:spawner" }, digger, st_tool)
		guard = guard + 1
	end
	ok(core.get_node_or_nil(pos).name == "air",
		"T8 last spawner removes the node")
	eq(timers[pk(pos)] and 1 or 0, 0, "T8 timer cleared with the node")
	digger._sneak = false
end

----------------------------------------------------------------------
-- Accrual clamping (f07 §4.5): a 30-day log-off is clamped
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 1)
	local t0 = now
	tick(30 * 24 * 3600) -- 30 days
	smp_spawners.accrue(pos, now)
	local got = state(pos).store[BONE] or 0
	-- active_only: clamped to 2 x 60 s = 2 minutes -> 12 kills
	near(got, smp_spawners.cfg.r * 2, 1e-9,
		"clamp 30-day log-off to 2 x timer_interval")
	local clamped = smp_spawners.clamp_elapsed(30 * 24 * 3600, "active_only")
	eq(clamped, 2 * smp_spawners.cfg.timer_interval, "clamp_elapsed active_only")
	eq(smp_spawners.clamp_elapsed(100, "always"), 100, "clamp_elapsed always")
	eq(smp_spawners.clamp_elapsed(100000, "capped"),
		smp_spawners.cfg.offline_cap_hours * 3600, "clamp_elapsed capped")
end

----------------------------------------------------------------------
-- Stacking (f07 §4.6.2)
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 1)
	local player = make_player("p9", 10, 65, 10)
	local item = ItemStack("smp_spawners:spawner_item")
	item:set_count(32)
	item:get_meta():set_string("type", "skeleton")
	local before = state(pos).stack
	local out = smp_spawners.interaction.add_stack(pos, player, item)
	eq(state(pos).stack, before + 32, "stack adds the whole held stack")
	eq(out:get_count(), 0, "stack consumes the held items")
	-- Different types rejected.
	local other = ItemStack("smp_spawners:spawner_item")
	other:set_count(4)
	other:get_meta():set_string("type", "zombie")
	local v0 = state(pos).version
	local out2 = smp_spawners.interaction.add_stack(pos, player, other)
	eq(state(pos).stack, before + 32, "foreign type not stacked")
	eq(out2:get_count(), 4, "foreign item returned")
	eq(state(pos).version, v0, "no version bump on rejected stack")
	-- Over the 32-bit cap rejected.
	local big = ItemStack("smp_spawners:spawner_item")
	big:set_count(64)
	big:get_meta():set_string("type", "skeleton")
	local meta = core.get_meta(pos)
	meta:set_int("smp:stack", 2147483647 - 1)
	local out3 = smp_spawners.interaction.add_stack(pos, player, big)
	eq(out3:get_count(), 64, "overflow stack rejected")
	eq(state(pos).stack, 2147483647 - 1, "stack under the cap unchanged")
end

----------------------------------------------------------------------
-- T10 — an action on a node dug since the menu opened fails safely
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 1)
	tick(60)
	smp_spawners.accrue(pos, now)
	local player = make_player("p10", 10, 65, 10)
	local session = smp_core.open_session("p10", "smp_spawners:menu", {
		pos = { x = pos.x, y = pos.y, z = pos.z },
		opened_type = "skeleton",
		page = 1,
	})
	local spec = smp_spawners.formspecs.render(session.pos, session)
	ok(spec ~= nil and spec:find("Skeleton Spawner", 1, true) ~= nil,
		"T10 menu renders with the header")

	-- The node gets dug (by a Silk Touch player) while the menu is up.
	local digger = make_player("p10d", 10, 65, 10)
	local def = core.registered_nodes["smp_spawners:spawner"]
	local st_tool = { _name = "mcl_tools:pickaxe", _ench = { silk_touch = 1 } }
	def.on_dig(pos, { name = "smp_spawners:spawner" }, digger, st_tool)
	-- Stack was 1, so the node is now gone.
	ok(core.get_node_or_nil(pos).name == "air", "T10 node dug out")

	-- The stale menu action must fail: revalidate returns nil and no
	-- mutation happens.
	local st = smp_spawners.revalidate(session.pos, session.opened_type,
		player)
	eq(st, nil, "T10 revalidate fails on a dug node")
	local taken = smp_spawners.take(pos, player, "skeleton", BONE, 64)
	eq(taken, 0, "T10 take on dug node takes nothing")
	local xp = smp_spawners.collect_xp(pos, player, "skeleton")
	eq(xp, 0, "T10 xp collect on dug node grants nothing")
	local sold, _ = smp_spawners.routing.sell_all(pos, player, "skeleton")
	eq(sold, false, "T10 sell all on dug node fails")
	smp_core.close_session("p10", "smp_spawners:menu")
end

----------------------------------------------------------------------
-- T9 — sell all routes into f02 (stubbed smp_sell.sell)
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 1)
	smp_spawners.cfg.accrual_mode = "always"
	tick(640) -- exactly 64 kills -> 64 whole bones
	smp_spawners.accrue(pos, now)
	smp_spawners.cfg.accrual_mode = "active_only"

	local routed = nil
	smp_sell = {
		sell = function(player, stacks)
			routed = { player = player, stacks = stacks }
		end,
	}
	local player = make_player("p9sell", 10, 65, 10)
	local v0 = state(pos).version
	local ok_sell, msg = smp_spawners.routing.sell_all(pos, player,
		"skeleton")
	ok(ok_sell == true, "T9 sell all succeeds with f02 present: " ..
		tostring(msg))
	ok(routed ~= nil and routed.player == player,
		"T9 f02.sell received the player")
	eq(routed and #routed.stacks or 0, 1, "T9 one lot (one loot type)")
	local lot = routed.stacks[1]
	eq(lot:get_name(), BONE, "T9 lot is the stored item")
	eq(lot:get_count(), 64, "T9 lot is the whole count")
	near(state(pos).store[BONE], 0, 1e-9, "T9 storage emptied")
	ok(state(pos).version > v0, "T9 version bumped")
	smp_sell = nil
end

----------------------------------------------------------------------
-- Type table sanity (PROPOSED markers, blaze rods, creeper gate)
----------------------------------------------------------------------

do
	local blaze = smp_spawners.types.get("blaze")
	ok(blaze.loot["mcl_mobitems:blaze_rod"] == 0.5,
		"blaze outputs rods (S10 over S24, f07 §10)")
	ok(blaze.loot["mcl_mobitems:blaze_powder"] == nil, "no powder")
	local creeper = smp_spawners.types.get("creeper")
	ok(creeper ~= nil and creeper.conditional == true,
		"creeper type present and conditional (f07 §4.2)")
	smp_spawners.cfg.enable_creeper = false
	eq(smp_spawners.types.get("creeper"), nil, "creeper gated by config")
	smp_spawners.cfg.enable_creeper = true
	ok(smp_spawners.types.get("skeleton").C == 1505.35,
		"skeleton C is the published value [S24]")
	eq(smp_spawners.types.get("nope"), nil, "unknown type rejected")
end

----------------------------------------------------------------------
-- on_blast / on_punch do nothing (cardinal rule, f07 §4.6.7)
----------------------------------------------------------------------

do
	local def = core.registered_nodes["smp_spawners:spawner"]
	local pos = place_spawner("skeleton", 1)
	local v0 = state(pos).version
	local err = nil
	pcall(function() def.on_blast(pos, 1.0) end)
	pcall(function() def.on_punch(pos, { name = "smp_spawners:spawner" },
		make_player("pb", 10, 65, 10), nil) end)
	ok(core.get_node_or_nil(pos).name == "smp_spawners:spawner",
		"blast does not remove the node")
	eq(state(pos).version, v0, "blast/punch do not touch metadata")
end

----------------------------------------------------------------------
-- in-game test suite (mods/smp_spawners/test.lua)
----------------------------------------------------------------------

print("== in-game test suite (mods/smp_spawners/test.lua) ==")
do
	local chunk, lerr = loadfile(ROOT .. "/friedcake/mods/smp_spawners/test.lua")
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

print(string.format("smp_spawners dev-tests: %d passed, %d failed",
	passed, failed))
os.exit(failed == 0 and 0 or 1)
