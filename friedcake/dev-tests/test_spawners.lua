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
	-- Relative invocation: trust the working directory. The modpack
	-- manifest lives at friedcake/mods/modpack.conf — probing
	-- friedcake/modpack.conf (which does not exist) used to send every
	-- relative run to the hardcoded fallback checkout, i.e. it tested
	-- someone else's working tree instead of this one (S06).
	local probe = io.open("friedcake/mods/modpack.conf", "r")
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
local logs = {}
local now = 1000000
local function tick(t) now = now + (t or 1) end

-- Hooks the f07 fix-batch tests drive: protection, inventory room and
-- the vanilla-spawner conversion path.
local protected_calls = {}
local protected_forced = false
local inv_room_ok = true
local node_dig_calls = 0
local vanilla_destruct_calls = 0

local objects_inside_radius = {}  -- [n] = {pos, objs}; T4 probes this
local function get_objects_inside_radius(pos, r)
	return objects_inside_radius[pk(pos) .. ":" .. r] or {}
end

-- The mod calls os.time() for smp:last_update; drive it from the
-- simulated clock so accrual math is deterministic.
local real_os_time = os.time
os.time = function() return now end

----------------------------------------------------------------------
-- ItemStack stub — engine-faithful where it matters (S06):
--
--   * `set_count(n)` CLEARS the stack unless 1 <= n <= 65535
--     (luanti src/script/lua_api/l_item.cpp:91-96). SP-3 depends on
--     this being faithful: the mod must never hand itself n > 65535.
--   * there is NO `ItemStack:remove_item` — the engine method table is
--     l_item.cpp:535-566; the mutation is `take_item(n)`, which
--     returns the TAKEN items. The stub deliberately does not fake
--     `remove_item`, so a regression to it fails here (the lesson of
--     test_engine_apis.lua: a stub must not encode the bug).
--   * `get_stack_max()` is the per-item limit; tests override it with
--     STACK_MAX[item_name] = n.
----------------------------------------------------------------------

local STACK_MAX = {}   -- test overrides; default 64 (Mineclonia)

local function new_itemstack(name, count)
	local meta = {}
	local s = {
		_name = name or "",
		_count = count or 1,
		_meta = meta,
		get_name = function(self) return self._name end,
		get_count = function(self) return self._count end,
		set_count = function(self, n)
			if type(n) ~= "number" then
				error("ItemStack:set_count: number expected, got "
					.. type(n), 2)
			end
			n = math.floor(n)
			if n > 0 and n <= 65535 then
				self._count = n
			else
				-- l_item.cpp:91-96: anything outside 1..65535 clears
				self._count = 0
				self._name = ""
			end
		end,
		is_empty = function(self)
			return self._count == 0 or self._name == ""
		end,
		clear = function(self)
			self._count = 0
			self._name = ""
		end,
		get_stack_max = function(self)
			return STACK_MAX[self._name] or 64
		end,
		get_free_space = function(self)
			return self:get_stack_max() - self:get_count()
		end,
		-- take_item(n): removes up to n from THIS stack and returns the
		-- TAKEN items (lua_api.md, ItemStack section).
		take_item = function(self, n)
			if type(n) ~= "number" then
				error("ItemStack:take_item: number expected, got "
					.. type(n), 2)
			end
			n = math.floor(n)
			if n < 1 then n = 1 end
			if n > self._count then n = self._count end
			local taken = new_itemstack(self._name, n)
			for k, v in pairs(self._meta) do taken._meta[k] = v end
			self._count = self._count - n
			if self._count <= 0 then
				self._count = 0
				self._name = ""
			end
			return taken
		end,
		get_meta = function()
			return {
				get_string = function(_, k) return meta[k] or "" end,
				set_string = function(_, k, v) meta[k] = tostring(v) end,
			}
		end,
		__tostring = function(self)
			return self._name .. "x" .. self._count
		end,
	}
	return s
end
ItemStack = function(name, count) return new_itemstack(name, count) end

-- Two stacks merge only when name AND metadata match (engine
-- ItemStack::canBeMergedWith); used by the inventory stub below.
local function stack_meta_key(s)
	local keys = {}
	for k in pairs(s._meta) do keys[#keys + 1] = k end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		out[#out + 1] = k .. "=" .. tostring(s._meta[k])
	end
	return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- vector — an engine global (src/script/lua_api/l_util.cpp); plain
-- luajit has no such thing. S06/SP-2 drops inventory leftovers at
-- `vector.offset(pos, 0, 0.5, 0)` (the node / the player's feet).
----------------------------------------------------------------------

vector = {
	new = function(x, y, z)
		if type(x) == "table" then return { x = x.x, y = x.y, z = x.z } end
		return { x = x or 0, y = y or 0, z = z or 0 }
	end,
	offset = function(v, dx, dy, dz)
		return { x = v.x + dx, y = v.y + dy, z = v.z + dz }
	end,
}

----------------------------------------------------------------------
-- Fake players and inventories
--
-- The inventory mirrors the engine's InvRef (src/script/lua_api/
-- l_inventory.cpp): a fixed-size slot list; `add_item` merges into
-- matching stacks first, then fills the first empty slots (splitting
-- stacks above stack_max), and ALWAYS returns the leftover ItemStack —
-- a truthy object, empty only when everything fit (l_inventory.cpp:
-- 275-291). S06/SP-2 depends on that being faithful: `if not
-- inv:add_item(...)` is never true.
--
-- opts = { slots = <capacity> }   (default 36 = the player "main" list)
----------------------------------------------------------------------

local function make_player(name, x, y, z, opts)
	local capacity = (opts and opts.slots) or 36
	local slots = {}   -- [1..capacity] = ItemStack or nil; dense from 1
	local p = {}
	p._name = name
	p._pos = { x = x or 0, y = y or 0, z = z or 0 }
	p._sneak = false
	p._slots = slots
	p._inv = slots          -- occupied slots in engine order (tests read it)
	p._capacity = capacity
	p._wielded = ItemStack("")
	p.get_player_name = function() return name end
	p.get_pos = function() return p._pos end
	p.get_player_control = function()
		return { sneak = p._sneak }
	end
	-- The engine calls on_dig(pos, node, digger) with three arguments
	-- only, so the dig path reads the tool off the player (f07 §10).
	p.get_wielded_item = function() return p._wielded end
	p.get_inventory = function()
		return {
			get_size = function(_, list)
				if list ~= "main" then return 0 end
				return capacity
			end,
			get_stack = function(_, list, i)
				if list ~= "main" then return ItemStack("") end
				return slots[i] or ItemStack("")
			end,
			-- True iff add_item would absorb the whole stack.
			room_for_item = function(_, list, stack)
				if list ~= "main" or not stack then return false end
				if stack:is_empty() then return true end
				local left = stack:get_count()
				local key = stack_meta_key(stack)
				for i = 1, capacity do
					local s = slots[i]
					if s and not s:is_empty()
						and s:get_name() == stack:get_name()
						and stack_meta_key(s) == key then
						left = left - math.min(
							s:get_stack_max() - s:get_count(), left)
						if left <= 0 then return true end
					end
				end
				for i = 1, capacity do
					if not slots[i] then
						left = left - stack:get_stack_max()
						if left <= 0 then return true end
					end
				end
				return false
			end,
			add_item = function(_, list, stack)
				if list ~= "main" then return stack end
				if not stack or stack:is_empty() then
					return ItemStack("")
				end
				-- Leftover: a fresh stack carrying the same meta.
				local left = new_itemstack(stack:get_name(),
					stack:get_count())
				for k, v in pairs(stack._meta) do left._meta[k] = v end
				-- 1. merge into partial stacks with identical meta
				for i = 1, capacity do
					if left:get_count() <= 0 then break end
					local s = slots[i]
					if s and not s:is_empty()
						and s:get_name() == left:get_name()
						and stack_meta_key(s) == stack_meta_key(left) then
						local room = s:get_stack_max() - s:get_count()
						if room > 0 then
							local move = math.min(room, left:get_count())
							s:set_count(s:get_count() + move)
							left:set_count(left:get_count() - move)
						end
					end
				end
				-- 2. first empty slots, splitting at stack_max
				for i = 1, capacity do
					if left:get_count() <= 0 then break end
					if not slots[i] then
						local n = math.min(left:get_count(),
							left:get_stack_max())
						local put = new_itemstack(left:get_name(), n)
						for k, v in pairs(left._meta) do
							put._meta[k] = v
						end
						slots[i] = put
						left:set_count(left:get_count() - n)
					end
				end
				-- 3. whatever is left did NOT fit: returned, never lost
				return left
			end,
		}
	end
	return p
end

----------------------------------------------------------------------
-- core stub
----------------------------------------------------------------------

-- Engine-side registries (S06/SP-1): `core.get_player_by_name`
-- resolves connections here, `core.get_player_privs` reads the
-- privilege table a test grants explicitly (the engine only ever
-- grants through register_privilege + grants, so nothing is default).
_G.__players = {}
_G.__player_privs = {}

-- MS-3 (strict stub, S05): the engine RAISES on a non-string player
-- name (luaL_checkstring), so the stubs below do too — a lenient stub
-- is what let the QB-1/SH-1/EC-2 class of bugs pass the harness.
local function require_name(name, api)
	if type(name) ~= "string" then
		error(api .. ": player name must be a string, got "
			.. type(name), 2)
	end
	return name
end

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
		-- Mimic the engine: `Settings:get_bool(key, default)` is called with
		-- `self` as the first argument, so the default is the THIRD.
		get_bool = function(_, _, default) return default end,
	},
	log = function(level, msg)
		logs[#logs + 1] = tostring(level) .. ": " .. tostring(msg)
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
		node_dig_calls = node_dig_calls + 1
		nodes[pk(pos)] = { name = "air" }
		timers[pk(pos)] = nil
		metas[pk(pos)] = nil
	end,
	-- Engine semantics (serverenvironment.cpp): set_node/remove_node run
	-- the old node's on_destruct and clear its metadata.
	set_node = function(pos, node)
		local old = nodes[pk(pos)]
		local olddef = old and core.registered_nodes[old.name]
		if olddef and olddef.on_destruct then olddef.on_destruct(pos) end
		nodes[pk(pos)] = node
		metas[pk(pos)] = nil
		timers[pk(pos)] = nil
	end,
	remove_node = function(pos)
		local old = nodes[pk(pos)]
		local olddef = old and core.registered_nodes[old.name]
		if olddef and olddef.on_destruct then olddef.on_destruct(pos) end
		nodes[pk(pos)] = { name = "air" }
		metas[pk(pos)] = nil
		timers[pk(pos)] = nil
	end,
	-- core.is_protected(pos, player_name): the second argument is a
	-- PLAYER NAME (builtin/game/misc.lua). Every call is recorded so
	-- the f07 §4.6.6 conformance test can assert that.
	is_protected = function(pos, name, player)
		protected_calls[#protected_calls + 1] =
			{ pos = pos, name = name, player = player }
		return protected_forced
	end,
	-- core.add_item(pos, itemstack): spawn an item entity at pos
	-- (lua_api.md "core.add_item(pos, item)"): the SP-2 leftover path.
	add_item = function(pos, stack)
		dropped[#dropped + 1] = { pos = pos, stack = stack,
			via = "add_item" }
		return true
	end,
	-- core.item_drop(itemstack, dropper, pos) — engine signature
	-- (builtin/game/item.lua:360). Nothing in this mod calls it any
	-- more; kept engine-shaped so a wrong call is visible here.
	item_drop = function(itemstack, dropper, pos)
		dropped[#dropped + 1] = { pos = pos, stack = itemstack,
			dropper = dropper, via = "item_drop" }
		return itemstack
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
			-- NodeMetaRef:get_inventory() always returns a valid InvRef
			-- (l_nodemeta.cpp:63-73), even for nodes that never declared
			-- one. `inv_room_ok` lets a test fill the hopper.
			get_inventory = function()
				t.inv = t.inv or { main = {} }
				local inv = t.inv
				return {
					is_empty = function(_, list)
						return #(inv[list] or {}) == 0
					end,
					get_size = function(_, list)
						return #(inv[list] or {})
					end,
					get_stack = function(_, list, i)
						local s = (inv[list] or {})[i]
						return s or ItemStack("")
					end,
					room_for_item = function() return inv_room_ok end,
					add_item = function(_, list, stack)
						inv[list] = inv[list] or {}
						inv[list][#inv[list] + 1] = stack
						return ItemStack("")
					end,
				}
			end,
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
	register_craftitem = function(name, def) core.registered_items[name] = def end,
	register_tool = function(name, def) core.registered_items[name] = def end,
	-- builtin/game/register.lua:456 — merges into the registered item
	-- and errors when it does not exist (hence the existence guard in
	-- node.lua).
	override_item = function(name, redefinition, del_fields)
		local item = core.registered_items[name] or
			core.registered_nodes[name]
		if not item then
			error("Attempt to override non-existent item " .. name, 2)
		end
		for k, v in pairs(redefinition) do item[k] = v end
		for _, f in ipairs(del_fields or {}) do item[f] = nil end
		core.registered_nodes[name] = item
		core.registered_items[name] = item
	end,
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
	--
	-- MS-3 (strict stub, S05): see require_name above — the engine
	-- RAISES on a non-string player name (luaL_checkstring), so these
	-- do too; a lenient stub is what let the QB-1/SH-1/EC-2 class of
	-- bugs pass the harness.
	get_player_by_name = function(name)
		require_name(name, "core.get_player_by_name")
		return _G.__players and _G.__players[name] or nil
	end,
	chat_send_player = function(name, msg)
		require_name(name, "core.chat_send_player")
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
	register_globalstep = function() end,
	register_privilege = function() end,
	-- Chat commands — builtin/common/chatcommands.lua:44-52. The engine
	-- defaults `def.privs = def.privs or {}` and stores the def
	-- verbatim, so ANY other key is never read: that is exactly how the
	-- pre-S06 `privilege = "smp_admin"` asked for nothing and let every
	-- player mint spawners. Reproducing the default here is what makes
	-- the SP-1 test fail on the bug instead of hiding it.
	registered_chatcommands = {},
	register_chatcommand = function(name, def)
		def = def or {}
		def.params = def.params or ""
		def.description = def.description or ""
		def.privs = def.privs or {}
		def.mod_origin = core.get_current_modname() or "??"
		core.registered_chatcommands[name] = def
	end,
	-- builtin/game/misc.lua:87 — an ObjectRef that quacks like a player.
	is_player = function(player)
		local t = type(player)
		return (t == "userdata" or t == "table") and
			type(player.is_player) == "function" and
			player:is_player() and true or false
	end,
	get_player_privs = function(name)
		return _G.__player_privs[name] or {}
	end,
	-- builtin/game/misc.lua:17-50 — table or list form, missing list
	-- as the second return value.
	check_player_privs = function(name, ...)
		if core.is_player(name) then
			name = name:get_player_name()
		elseif type(name) ~= "string" then
			error("core.check_player_privs expects a player or " ..
				"playername as argument.", 2)
		end
		local requested = { ... }
		local have = core.get_player_privs(name)
		local missing = {}
		if type(requested[1]) == "table" then
			for priv, value in pairs(requested[1]) do
				if value and not have[priv] then
					missing[#missing + 1] = priv
				end
			end
		else
			for _, priv in pairs(requested) do
				if not have[priv] then missing[#missing + 1] = priv end
			end
		end
		if #missing > 0 then return false, missing end
		return true, ""
	end,
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

-- mcl_formspec.get_itemslot_bg_v4 (mods/HUD/mcl_formspec/init.lua:26).
mcl_formspec = {
	get_itemslot_bg_v4 = function(x, y, w, h)
		return string.format("image[%s,%s;%s,%s;mcl_formspec_itemslot.png]",
			tostring(x), tostring(y), tostring(w), tostring(h))
	end,
}

-- The vanilla dungeon spawner (mcl_mobspawners init.lua:221): no on_dig
-- of its own (the engine default is core.node_dig), drop = "", and an
-- on_destruct that cleans up the doll and XP. Registered BEFORE
-- smp_spawners so node.lua's conversion override can find it.
core.register_node("mcl_mobspawners:spawner", {
	description = "Mob Spawner",
	groups = { pickaxey = 1, material_stone = 1, unmovable_by_piston = 1 },
	drop = "",
	on_destruct = function()
		vanilla_destruct_calls = vanilla_destruct_calls + 1
	end,
})

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

-- Recorded core.log lines (the F07-10 unknown-stack_mode warning).
local function has_log(needle)
	for _, l in ipairs(logs) do
		if l:find(needle, 1, true) then return true end
	end
	return false
end

-- Protection calls: reset and read the last one (f07 §4.6.6).
local function reset_protected()
	for i = #protected_calls, 1, -1 do protected_calls[i] = nil end
end
local function last_protected()
	return protected_calls[#protected_calls]
end

-- Chat lines a player received (the harness's core.chat_send_player).
local function chat_of(name)
	return chats[name] or {}
end
local function chat_has(name, needle)
	for _, l in ipairs(chat_of(name)) do
		if tostring(l):find(needle, 1, true) then return true end
	end
	return false
end
local function chat_reset(name)
	chats[name] = {}
end

-- Recorded core.log lines matching a needle.
local function log_count(needle)
	local n = 0
	for _, l in ipairs(logs) do
		if l:find(needle, 1, true) then n = n + 1 end
	end
	return n
end

-- Connect a fake player the way the engine would: get_player_by_name
-- resolves it and it starts with NO privileges (grant explicitly, as
-- a server operator would). Returns the player for chaining.
local function connect(player, privs)
	local name = player:get_player_name()
	_G.__players[name] = player
	_G.__player_privs[name] = privs or {}
	chat_reset(name)
	return player
end

-- Mirrors builtin/game/chat.lua:55-96 (the on_chatmessage handler):
-- parse "/cmd params", look the def up, check the DEFINITION's privs
-- BEFORE running it, and only then call def.func. Like the engine,
-- `sender` is the sender's NAME (a string), not an ObjectRef. Returns
-- what the engine would: `false, missing_privs` when refused,
-- otherwise whatever def.func returns.
local function run_chatcommand(sender, message)
	local cmd, param = string.match(message, "^/([^ ]+) *(.*)")
	if not cmd then return false, "no command" end
	param = param or ""
	local def = core.registered_chatcommands[cmd]
	if not def then return false, "invalid command" end
	local has_privs, missing = core.check_player_privs(sender, def.privs)
	if not has_privs then
		core.chat_send_player(sender, "You don't have permission to run "
			.. "this command (missing privileges: "
			.. table.concat(missing, ", ") .. ").")
		return false, missing
	end
	return def.func(sender, param)
end

-- An injected settings store with the engine's semantics
-- (l_settings.cpp:119-139 + settings.cpp:485 `is_yes`): an absent key
-- returns the default, a present one wins and is read as y/yes/true or
-- a non-zero number.
local function fake_settings(vals)
	return {
		get = function(_, k) return vals[k] end,
		get_bool = function(_, k, default)
			local v = vals[k]
			if v == nil then return default end
			if type(v) == "boolean" then return v end
			local s = tostring(v):lower():gsub("^%s+", ""):gsub("%s+$", "")
			if s == "y" or s == "yes" or s == "true" then return true end
			local n = tonumber(s)
			if n then return n ~= 0 end
			return false
		end,
	}
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
--
-- Rewritten for F07-13: the stub now matches the real f02 contract
-- (smp_sell/init.lua:180-186) — `true, lines` on success, `false,
-- lines` on refusal — and both paths assert conservation: on refusal
-- storage, version and the stacks handed over are untouched.
----------------------------------------------------------------------

do
	local function seed()
		local pos = place_spawner("skeleton", 1)
		smp_spawners.cfg.accrual_mode = "always"
		tick(640) -- exactly 64 kills -> 64 whole bones
		smp_spawners.accrue(pos, now)
		smp_spawners.cfg.accrual_mode = "active_only"
		return pos
	end

	local SUMMARY = "Spawner output sent to sell routing"
	local FALLBACK = smp_spawners.S("Spawner output could not be sold")

	-- Refusal A: f02's balance-cap refusal carries its own lines
	-- (smp_sell/sell.lua:150 via init.lua:195-203).
	do
		local pos = seed()
		local player = make_player("p9sell", 10, 65, 10)
		local store_before = core.get_meta(pos):get_string("smp:store")
		local v0 = state(pos).version
		local handed = nil
		smp_sell = {
			sell = function(p, stacks)
				handed = { player = p, n = #stacks,
					name = stacks[1]:get_name(),
					count = stacks[1]:get_count() }
				return false, { "You reached the balance limit" }
			end,
		}
		local ok_sell, msg = smp_spawners.routing.sell_all(pos, player,
			"skeleton")
		eq(ok_sell, false, "T9 refusal A: sell_all returns false")
		eq(core.get_meta(pos):get_string("smp:store"), store_before,
			"T9 refusal A: storage byte-identical")
		eq(state(pos).version, v0, "T9 refusal A: version untouched")
		eq(type(msg), "table", "T9 refusal A: f02 lines relayed as a list")
		eq(msg[1], "You reached the balance limit",
			"T9 refusal A: the refusal line reaches the player")
		ok(handed ~= nil and handed.player == player,
			"T9 refusal A: f02 got the player")
		eq(handed and handed.n or 0, 1, "T9 refusal A: one lot")
		eq(handed and handed.name or "", BONE,
			"T9 refusal A: the stored item")
		eq(handed and handed.count or 0, 64,
			"T9 refusal A: stacks handed over intact")
		near(store_sum(pos), 64, 1e-9,
			"T9 refusal A: nothing left storage")
		smp_sell = nil
	end

	-- Refusal B: empty plan / partial — f02 returns `false, {}`, so the
	-- player must still get our fallback line (never a silent nothing).
	do
		local pos = seed()
		local player = make_player("p9sellb", 10, 65, 10)
		local store_before = core.get_meta(pos):get_string("smp:store")
		local v0 = state(pos).version
		smp_sell = { sell = function() return false, {} end }
		local ok_sell, msg = smp_spawners.routing.sell_all(pos, player,
			"skeleton")
		eq(ok_sell, false, "T9 refusal B: sell_all returns false")
		eq(type(msg), "string", "T9 refusal B: empty lines -> our string")
		eq(msg, FALLBACK, "T9 refusal B: the fallback refusal line")
		eq(core.get_meta(pos):get_string("smp:store"), store_before,
			"T9 refusal B: storage unchanged")
		eq(state(pos).version, v0, "T9 refusal B: version unchanged")

		-- A bare `false` (no second value at all) behaves the same.
		smp_sell = { sell = function() return false end }
		local ok2, msg2 = smp_spawners.routing.sell_all(pos, player,
			"skeleton")
		eq(ok2, false, "T9 refusal C: bare false")
		eq(msg2, FALLBACK, "T9 refusal C: fallback refusal line")
		eq(state(pos).version, v0, "T9 refusal C: version unchanged")
		smp_sell = nil
	end

	-- Success: storage decreases exactly by the sold lots, and f02's
	-- receipt lines are relayed after our summary (f02 never shows
	-- them itself).
	do
		local pos = seed()
		local player = make_player("p9sellc", 10, 65, 10)
		local v0 = state(pos).version
		local routed = nil
		smp_sell = {
			sell = function(p, stacks)
				routed = { player = p, stacks = stacks }
				return true, { "Sold 64 x Bone for 12.00",
					"Balance: 12.00" }
			end,
		}
		local ok_sell, msg = smp_spawners.routing.sell_all(pos, player,
			"skeleton")
		eq(ok_sell, true, "T9 success: sell_all returns true")
		eq(type(msg), "table", "T9 success: lines are relayed")
		ok(type(msg[1]) == "string" and
			msg[1]:find(SUMMARY, 1, true) == 1,
			"T9 success: our summary comes first — " .. tostring(msg[1]))
		eq(msg[2], "Sold 64 x Bone for 12.00",
			"T9 success: f02 receipt line relayed")
		eq(msg[3], "Balance: 12.00",
			"T9 success: second f02 receipt line relayed")
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
-- Fix batch f07 — F07-2/F07-8/F07-9: §7 keys really do what they say
----------------------------------------------------------------------

do
	-- F07-2: three cases × five keys (acceptance 2).
	local default_true = {
		{ "spawners.require_silk_touch", "require_silk_touch" },
		{ "spawners.blast_immune", "blast_immune" },
		{ "spawners.enable_creeper", "enable_creeper" },
	}
	for _, entry in ipairs(default_true) do
		local key, field = entry[1], entry[2]
		local unset = smp_spawners.build_cfg(fake_settings({}))
		eq(unset[field], true, "F07-2 " .. key .. " unset -> default true")
		local on = smp_spawners.build_cfg(
			fake_settings({ [key] = "true" }))
		eq(on[field], true, "F07-2 " .. key .. " = true -> true")
		local off = smp_spawners.build_cfg(
			fake_settings({ [key] = "false" }))
		eq(off[field], false,
			"F07-2 " .. key .. " = false -> false (the old bool() bug)")
	end

	-- spawners.acquisition.admin lives in the acquisition table.
	local acq_unset = smp_spawners.build_cfg(fake_settings({}))
	eq(acq_unset.acquisition.admin, true,
		"F07-2 acquisition.admin unset -> default true")
	eq(smp_spawners.build_cfg(
		fake_settings({ ["spawners.acquisition.admin"] = "true" }))
		.acquisition.admin, true,
		"F07-2 acquisition.admin = true -> true")
	eq(smp_spawners.build_cfg(
		fake_settings({ ["spawners.acquisition.admin"] = "false" }))
		.acquisition.admin, false,
		"F07-2 acquisition.admin = false -> false")

	local open_unset = smp_spawners.build_cfg(fake_settings({}))
	eq(open_unset.open_requires_access, false,
		"F07-2 open_requires_access unset -> default false")
	eq(smp_spawners.build_cfg(
		fake_settings({ ["spawners.open_requires_access"] = "true" }))
		.open_requires_access, true,
		"F07-2 open_requires_access = true -> true")
	eq(smp_spawners.build_cfg(
		fake_settings({ ["spawners.open_requires_access"] = "false" }))
		.open_requires_access, false,
		"F07-2 open_requires_access = false -> false")

	-- The V-04 escape hatch drives the live type gate.
	local hatch = smp_spawners.build_cfg(
		fake_settings({ ["spawners.enable_creeper"] = "false" }))
	eq(hatch.enable_creeper, false, "F07-2 enable_creeper = false parses")
	local saved_creeper = smp_spawners.cfg.enable_creeper
	smp_spawners.cfg.enable_creeper = hatch.enable_creeper
	eq(smp_spawners.types.get("creeper"), nil,
		"F07-2 enable_creeper = false removes the creeper type (V-04)")
	smp_spawners.cfg.enable_creeper = saved_creeper

	-- The live config is itself built through build_cfg, so the engine
	-- stub's "key unset" path is what the pack boots with.
	local live = smp_spawners.build_cfg(core.settings)
	eq(live.require_silk_touch, true, "F07-2 live boot: silk required")
	eq(live.open_requires_access, false, "F07-2 live boot: menu open")
	eq(live.acquisition.admin, true, "F07-2 live boot: admin issue on")

	-- F07-8: documented dotted names, compound back-compat, dotted wins.
	local function cfg_for(vals)
		local c = smp_spawners.build_cfg(fake_settings({}))
		smp_spawners.apply_C_overrides(fake_settings(vals), c)
		return c
	end
	local dotted = cfg_for({ ["spawners.C.skeleton"] = "999" })
	near(dotted.C.skeleton, 999, 1e-9,
		"F07-8 spawners.C.skeleton overrides the default")
	near(dotted.C.zombie, 250, 1e-9,
		"F07-8 an untouched type keeps its PROPOSED default")

	local compound = cfg_for({ ["spawners.C"] = "skeleton=1000, zombie=200" })
	near(compound.C.skeleton, 1000, 1e-9,
		"F07-8 compound spawners.C still parses (the old parser was dead)")
	near(compound.C.zombie, 200, 1e-9,
		"F07-8 compound pairs beyond the first are read too")

	local both = cfg_for({ ["spawners.C"] = "skeleton=1000",
		["spawners.C.skeleton"] = "999" })
	near(both.C.skeleton, 999, 1e-9,
		"F07-8 the documented dotted name wins over the compound")

	local garbage = cfg_for({ ["spawners.C"] = "skeleton=abc, zombie=-5",
		["spawners.C.pig"] = "not a number" })
	near(garbage.C.skeleton, 1505.35, 1e-9,
		"F07-8 non-numeric compound value ignored")
	near(garbage.C.zombie, 250, 1e-9, "F07-8 negative value ignored")
	near(garbage.C.pig, 250, 1e-9, "F07-8 dotted garbage ignored")

	-- F07-9: table key is primary, flat keys are the fallback.
	local tbl = smp_spawners.build_cfg(fake_settings({
		["spawners.acquisition"] = "{ shard_shop = true, admin = false }",
	}))
	eq(tbl.acquisition.shard_shop, true,
		"F07-9 table key sets shard_shop = true")
	eq(tbl.acquisition.admin, false, "F07-9 table key sets admin = false")
	eq(tbl.acquisition.crates, false,
		"F07-9 table key leaves crates at its default")
	eq(tbl.acquisition.natural, false,
		"F07-9 table key leaves natural at its default")

	local flat = smp_spawners.build_cfg(fake_settings({
		["spawners.acquisition.crates"] = "true",
	}))
	eq(flat.acquisition.crates, true,
		"F07-9 flat back-compat key still works")
	eq(flat.acquisition.admin, true, "F07-9 flat defaults unchanged")

	local mixed = smp_spawners.build_cfg(fake_settings({
		["spawners.acquisition"] = "{ admin = false }",
		["spawners.acquisition.admin"] = "true",
		["spawners.acquisition.crates"] = "true",
	}))
	eq(mixed.acquisition.admin, false,
		"F07-9 the table key wins over the flat one for the same source")
	eq(mixed.acquisition.crates, true,
		"F07-9 flat key still fills a source the table does not name")

	local dflt = smp_spawners.build_cfg(fake_settings({}))
	eq(dflt.acquisition.shard_shop, false, "F07-9 default shard_shop false")
	eq(dflt.acquisition.crates, false, "F07-9 default crates false")
	eq(dflt.acquisition.natural, false, "F07-9 default natural false")
	eq(dflt.acquisition.admin, true, "F07-9 default admin true")
end

----------------------------------------------------------------------
-- Fix batch f07 — F07-3: the menu shows the player inventory
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 1)
	smp_spawners.cfg.accrual_mode = "always"
	tick(640)
	smp_spawners.accrue(pos, now)
	smp_spawners.cfg.accrual_mode = "active_only"

	local player = make_player("p3menu", 10, 65, 10)
	local session = smp_core.open_session("p3menu", "smp_spawners:menu", {
		pos = { x = pos.x, y = pos.y, z = pos.z },
		opened_type = "skeleton",
		page = 1,
	})
	local spec = smp_spawners.formspecs.render(session.pos, session)
	ok(type(spec) == "string", "F07-3 menu renders")
	ok(spec:find("Inventory", 1, true) ~= nil,
		"F07-3 Inventory label present (shared/04:22)")
	ok(spec:find("list[current_player;main;0.375,9.875;9,3;9]", 1, true) ~= nil,
		"F07-3 player inventory rows present")
	ok(spec:find("list[current_player;main;0.375,13.825;9,1;]", 1, true) ~= nil,
		"F07-3 player hotbar row present")
	ok(spec:find("mcl_formspec_itemslot.png", 1, true) ~= nil,
		"F07-3 slot backgrounds drawn (mcl_formspec v4)")
	ok(spec:find("size[11.75,15.2]", 1, true) ~= nil,
		"F07-3 form grown for the inventory section")
	-- Every element uses ';' between arguments (a ',' there makes the
	-- engine reject the element and the control silently vanishes).
	ok(spec:find("label%[[%d.]+,[%d.]+,") == nil,
		"F07-3 labels use ';' separators")
	ok(spec:find("button%[[%d.]+,[%d.]+,") == nil,
		"F07-3 buttons use ';' separators")
	-- The storage grid is NOT a real inventory: clicks stay take
	-- requests against the count table (f07 §8).
	ok(spec:find("list[nodemeta", 1, true) == nil,
		"F07-3 virtual storage is not a list[]")
	ok(spec:find("listring[", 1, true) == nil,
		"F07-3 no listring into the virtual storage")
	ok(spec:find("item_image_button[", 1, true) ~= nil,
		"F07-3 storage slots remain take-request buttons")

	-- A take still routes through the revalidating take-request path.
	local inv_before = #player._inv
	for _, h in ipairs(field_handlers) do
		local good, err = pcall(h, player, "smp_spawners:menu",
			{ slot1 = "true" })
		ok(good, "F07-3 take-request handler runs: " .. tostring(err))
	end
	eq(#player._inv, inv_before + 1,
		"F07-3 the slot click took the stored stack")
	near(state(pos).store[BONE], 0, 1e-9,
		"F07-3 storage emptied by the revalidated take")
	smp_core.close_session("p3menu", "smp_spawners:menu")
end

----------------------------------------------------------------------
-- Fix batch f07 — F07-4 / F07-5: piston immunity and hopper extraction
----------------------------------------------------------------------

do
	local def = core.registered_nodes["smp_spawners:spawner"]
	eq(def.groups.unmovable_by_piston, 1,
		"F07-4 group unmovable_by_piston = 1 (mcl_pistons api.lua:56)")
	eq(def.groups.container, 7,
		"F07-5 group container = 7 (blocked from generic container moves)")
	ok(type(def._on_hopper_out) == "function",
		"F07-5 _on_hopper_out hook registered on the node def")

	local pos = place_spawner("skeleton", 1)
	local hpos = { x = 10, y = 63, z = 10 }
	smp_spawners.cfg.accrual_mode = "always"
	tick(640)
	smp_spawners.accrue(pos, now)
	smp_spawners.cfg.accrual_mode = "active_only"
	local v0 = state(pos).version

	-- Default off: nothing moves, nothing changes.
	eq(def._on_hopper_out(pos, hpos), false,
		"F07-5 default-off extracts nothing")
	eq(state(pos).version, v0,
		"F07-5 default-off leaves storage and version alone")

	-- On: one item per pull.
	smp_spawners.cfg.hopper_extraction = true
	eq(def._on_hopper_out(pos, hpos), true,
		"F07-5 extraction moves an item when enabled")
	near(state(pos).store[BONE], 63, 1e-9,
		"F07-5 exactly one item per pull")
	local hinv = core.get_meta(hpos):get_inventory()
	eq(hinv:get_size("main"), 1, "F07-5 the hopper received the item")
	ok(state(pos).version > v0, "F07-5 the pull bumps the version counter")

	-- A full hopper extracts nothing and touches nothing.
	local v1 = state(pos).version
	inv_room_ok = false
	eq(def._on_hopper_out(pos, hpos), false,
		"F07-5 a full hopper takes nothing")
	near(state(pos).store[BONE], 63, 1e-9,
		"F07-5 storage untouched when the hopper is full")
	eq(state(pos).version, v1, "F07-5 no version bump on a refused pull")
	inv_room_ok = true

	-- Nothing stored: nothing to pull.
	smp_spawners.cfg.accrual_mode = "always"
	tick(1200)
	smp_spawners.accrue(pos, now)
	smp_spawners.cfg.accrual_mode = "active_only"
	local player = make_player("p5h", 10, 65, 10)
	smp_spawners.take(pos, player, "skeleton", BONE, math.huge)
	eq(def._on_hopper_out(pos, hpos), false,
		"F07-5 an empty spawner extracts nothing")

	smp_spawners.cfg.hopper_extraction = false
end

----------------------------------------------------------------------
-- Fix batch f07 — F07-6: convert_natural turns a dug vanilla spawner
-- into a virtual one
----------------------------------------------------------------------

do
	local V = "mcl_mobspawners:spawner"
	local vdef = core.registered_nodes[V]
	ok(vdef ~= nil and type(vdef.on_dig) == "function",
		"F07-6 the vanilla spawner's dig is overridden")

	local digger = make_player("p6conv", 20, 65, 20)
	local silk = { _name = "mcl_tools:pickaxe", _ench = { silk_touch = 1 } }
	local plain = { _name = "mcl_tools:pickaxe", _ench = {} }

	local function seed_vanilla(mob)
		local pos = { x = 20, y = 64, z = 20 }
		nodes[pk(pos)] = { name = V }
		metas[pk(pos)] = {}
		local m = core.get_meta(pos)
		m:set_string("Mob", mob)
		return pos
	end

	-- Default off: the vanilla dig falls through untouched.
	local pos = seed_vanilla("mobs_mc:skeleton")
	local digs0 = node_dig_calls
	vdef.on_dig(pos, { name = V }, digger, silk)
	eq(node_dig_calls, digs0 + 1,
		"F07-6 default-off: the vanilla dig still runs")
	eq(core.get_node_or_nil(pos).name, "air",
		"F07-6 default-off: the vanilla node is left alone")

	-- On: converted, with the type read from the vanilla `Mob` key.
	smp_spawners.cfg.convert_natural = true
	pos = seed_vanilla("mobs_mc:skeleton")
	local destruct0 = vanilla_destruct_calls
	vdef.on_dig(pos, { name = V }, digger, silk)
	eq(core.get_node_or_nil(pos).name, "smp_spawners:spawner",
		"F07-6 converts a vanilla spawner on a Silk Touch dig")
	eq(core.get_meta(pos):get_string("smp:type"), "skeleton",
		"F07-6 the type comes from the Mob key")
	eq(core.get_meta(pos):get_int("smp:stack"), 1,
		"F07-6 the converted node starts at stack 1")
	eq(vanilla_destruct_calls, destruct0 + 1,
		"F07-6 set_node ran the vanilla on_destruct (doll + XP cleanup)")
	ok(timers[pk(pos)] ~= nil and timers[pk(pos)].running,
		"F07-6 conversion starts the node timer")
	local converted = smp_spawners.read_state(pos)
	ok(converted ~= nil and converted.type_id == "skeleton",
		"F07-6 the converted node is a working virtual spawner")

	-- The same dig with only three arguments (what the engine actually
	-- sends) still sees the wielded tool.
	pos = seed_vanilla("mobs_mc:zombie")
	digger._wielded = silk
	vdef.on_dig(pos, { name = V }, digger)
	eq(core.get_node_or_nil(pos).name, "smp_spawners:spawner",
		"F07-6 a three-argument on_dig reads the wielded silk")
	digger._wielded = ItemStack("")
	eq(core.get_meta(pos):get_string("smp:type"), "zombie",
		"F07-6 zombie spawner converts to the zombie type")

	-- Without Silk Touch (silk required) the vanilla dig stands.
	pos = seed_vanilla("mobs_mc:zombie")
	vdef.on_dig(pos, { name = V }, digger, plain)
	eq(core.get_node_or_nil(pos).name, "air",
		"F07-6 no Silk Touch, no conversion")

	-- An unmapped mob has no type: vanilla dig stands.
	pos = seed_vanilla("mobs_mc:silverfish")
	vdef.on_dig(pos, { name = V }, digger, silk)
	eq(core.get_node_or_nil(pos).name, "air",
		"F07-6 an unknown mob is not converted")

	-- The creeper gate (V-04) applies to conversion too.
	pos = seed_vanilla("mobs_mc:creeper")
	smp_spawners.cfg.enable_creeper = false
	vdef.on_dig(pos, { name = V }, digger, silk)
	eq(core.get_node_or_nil(pos).name, "air",
		"F07-6 a disabled type is not converted (V-04)")
	smp_spawners.cfg.enable_creeper = true

	-- Protection blocks conversion.
	pos = seed_vanilla("mobs_mc:cow")
	protected_forced = true
	vdef.on_dig(pos, { name = V }, digger, silk)
	eq(core.get_node_or_nil(pos).name, "air",
		"F07-6 a protected vanilla spawner is not converted")
	protected_forced = false

	smp_spawners.cfg.convert_natural = false
end

----------------------------------------------------------------------
-- Fix batch f07 — F07-7: every interaction converts elapsed time
----------------------------------------------------------------------

do
	local player = make_player("p7acc", 10, 65, 10)

	-- Menu open.
	local pos = place_spawner("skeleton", 1)
	tick(120)
	smp_spawners.interaction.open_menu(pos, player)
	near(store_sum(pos), smp_spawners.cfg.r * 2, 1e-9,
		"F07-7 menu open accrues the full 120 s")
	smp_core.close_session("p7acc", "smp_spawners:menu")

	-- Take.
	pos = place_spawner("skeleton", 1)
	tick(120)
	local taken = smp_spawners.take(pos, player, "skeleton", BONE, 64)
	eq(taken, 12, "F07-7 take converts the elapsed 120 s first")

	-- Collect XP.
	pos = place_spawner("skeleton", 1)
	tick(120)
	local xp = smp_spawners.collect_xp(pos, player, "skeleton")
	near(xp, 12 * 5, 1e-9,
		"F07-7 Collect XP converts the elapsed 120 s first")

	-- Sell all.
	pos = place_spawner("skeleton", 1)
	tick(120)
	local routed = nil
	smp_sell = {
		sell = function(p, stacks)
			routed = { player = p, stacks = stacks }
			return true
		end,
	}
	local ok_sell = smp_spawners.routing.sell_all(pos, player, "skeleton")
	eq(ok_sell, true, "F07-7 sell all succeeds")
	ok(routed ~= nil and routed.stacks[1]:get_count() == 12,
		"F07-7 sell all converts the elapsed 120 s first")
	smp_sell = nil
end

----------------------------------------------------------------------
-- Fix batch f07 — F07-10: spawners.stack_mode actually works
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 1)
	local player = make_player("p10sm", 10, 65, 10)
	local function held(n)
		local item = ItemStack("smp_spawners:spawner_item")
		item:set_count(n)
		item:get_meta():set_string("type", "skeleton")
		return item
	end

	-- Default "all": the whole held stack merges (unchanged behaviour).
	smp_spawners.cfg.stack_mode = "all"
	local out = smp_spawners.interaction.add_stack(pos, player, held(32))
	eq(state(pos).stack, 33, "F07-10 stack_mode = all merges everything")
	eq(out:get_count(), 0, "F07-10 all held items consumed")

	-- "one": one spawner per click.
	smp_spawners.cfg.stack_mode = "one"
	local out1 = smp_spawners.interaction.add_stack(pos, player, held(32))
	eq(state(pos).stack, 34, "F07-10 stack_mode = one adds a single one")
	eq(out1:get_count(), 31, "F07-10 the rest comes back to the player")

	-- Unknown value: kept raw, warned about, behaves like "all".
	local unknown = smp_spawners.build_cfg(
		fake_settings({ ["spawners.stack_mode"] = "bogus" }))
	eq(unknown.stack_mode, "bogus",
		"F07-10 an unknown value is kept raw")
	smp_spawners.cfg.stack_mode = "bogus"
	local out2 = smp_spawners.interaction.add_stack(pos, player, held(4))
	eq(state(pos).stack, 38,
		"F07-10 an unknown value degrades to the default behaviour")
	eq(out2:get_count(), 0, "F07-10 unknown value consumed the stack")
	ok(has_log("unknown spawners.stack_mode"),
		"F07-10 an unknown value warns at build time")

	smp_spawners.cfg.stack_mode = "all"
end

----------------------------------------------------------------------
-- Fix batch f07 — F07-11: blast_immune is a real toggle
----------------------------------------------------------------------

do
	local def = core.registered_nodes["smp_spawners:spawner"]
	eq(def.drop, "", "F07-11 the node never drops a bare node item")

	local pos = place_spawner("skeleton", 1)
	local v0 = state(pos).version
	def.on_blast(pos, 1.0, false)
	eq(core.get_node_or_nil(pos).name, "smp_spawners:spawner",
		"F07-11 blast_immune (default) survives the blast")
	eq(state(pos).version, v0, "F07-11 an immune blast touches no metadata")

	-- Off: the node is removed and its timer stopped with it.
	smp_spawners.performance.start_timer(pos)
	smp_spawners.cfg.blast_immune = false
	def.on_blast(pos, 1.0, false)
	eq(core.get_node_or_nil(pos).name, "air",
		"F07-11 blast_immune = false removes the node")
	eq(timers[pk(pos)] and timers[pk(pos)].running or false, false,
		"F07-11 the timer is stopped with the node")
	smp_spawners.cfg.blast_immune = true
end

----------------------------------------------------------------------
-- Fix batch f07 — engine truth: the protection argument and the dig
-- tool (f07 §4.6.6, §10)
----------------------------------------------------------------------

do
	local def = core.registered_nodes["smp_spawners:spawner"]
	local silk = { _name = "mcl_tools:pickaxe", _ench = { silk_touch = 1 } }

	-- core.is_protected(pos, player_name) — never an action tag, never
	-- an ObjectRef (builtin/game/misc.lua; smp_world keys off the name).
	local pos = place_spawner("skeleton", 5)
	local digger = make_player("pGuard", 10, 65, 10)
	reset_protected()
	def.on_dig(pos, { name = "smp_spawners:spawner" }, digger, silk)
	local call = last_protected()
	ok(call ~= nil, "eng core.is_protected is consulted on a dig")
	eq(call and call.name, "pGuard",
		"eng core.is_protected receives the player name")
	eq(call and call.player, nil,
		"eng no stray third argument is passed to core.is_protected")

	-- A refused dig mutates nothing.
	local stack0 = state(pos).stack
	protected_forced = true
	local v0 = state(pos).version
	def.on_dig(pos, { name = "smp_spawners:spawner" }, digger, silk)
	eq(state(pos).version, v0, "eng a protected dig mutates nothing")
	eq(state(pos).stack, stack0, "eng a protected dig leaves the stack alone")
	protected_forced = false

	-- Placement consults protection the same way.
	local item = ItemStack("smp_spawners:spawner_item")
	item:set_count(1)
	item:get_meta():set_string("type", "skeleton")
	local pointed = { above = { x = 30, y = 64, z = 30 },
	                  node = { x = 30, y = 63, z = 30 } }
	reset_protected()
	protected_forced = true
	local out = smp_spawners.interaction.place(digger, pointed, item)
	eq(out:get_count(), 1, "eng a protected place consumes nothing")
	eq(core.get_node_or_nil(pointed.above).name, "air",
		"eng a protected place places nothing")
	local pcall_ = last_protected()
	ok(pcall_ ~= nil and pcall_.name == "pGuard",
		"eng place passes the player name to core.is_protected")
	protected_forced = false

	-- The engine calls on_dig(pos, node, digger) with three arguments:
	-- without reading the wielded tool the silk check could never pass.
	local pos2 = place_spawner("skeleton", 1)
	local dw = make_player("pTool", 10, 65, 10)
	dw._wielded = silk
	def.on_dig(pos2, { name = "smp_spawners:spawner" }, dw)
	eq(core.get_node_or_nil(pos2).name, "air",
		"eng a three-argument on_dig sees the wielded Silk Touch")

	-- And without it the dig is still refused.
	local pos3 = place_spawner("skeleton", 1)
	local nb = make_player("pTool2", 10, 65, 10)
	nb._wielded = { _name = "mcl_tools:pickaxe", _ench = {} }
	def.on_dig(pos3, { name = "smp_spawners:spawner" }, nb)
	eq(core.get_node_or_nil(pos3).name, "smp_spawners:spawner",
		"eng a three-argument on_dig without silk refuses the dig")
end

----------------------------------------------------------------------
-- Security batch S06 — SP-1: /spawner is admin-gated and audited
----------------------------------------------------------------------

do
	local def = core.registered_chatcommands["spawner"]
	ok(def ~= nil, "SP-1 /spawner is registered")
	eq(def and def.privilege, nil,
		"SP-1 the ignored `privilege` key is gone")
	eq(def and def.privs and def.privs.smp_admin, true,
		"SP-1 the engine-read `privs` table demands smp_admin")
	ok(type(def and def.func) == "function", "SP-1 the command has a func")

	-- Sender WITHOUT smp_admin: chat.lua checks def.privs before it
	-- ever calls def.func, so nothing is minted and nothing is logged.
	local sender = connect(make_player("sp_noadmin", 10, 65, 10))
	local target = connect(make_player("sp_target", 12, 65, 12))
	local audit_before = log_count("[smp_spawners] /spawner give")
	local ran, missing = run_chatcommand(sender:get_player_name(),
		"/spawner give sp_target skeleton 5")
	eq(ran, false, "SP-1 a sender without smp_admin is refused")
	ok(type(missing) == "table" and missing[1] == "smp_admin",
		"SP-1 smp_admin is named as the missing privilege")
	ok(chat_has("sp_noadmin", "missing privileges: smp_admin"),
		"SP-1 the refusal reaches the sender as a chat line")
	eq(target:get_inventory():get_stack("main", 1):is_empty(), true,
		"SP-1 no spawner was minted for the target")
	eq(log_count("[smp_spawners] /spawner give"), audit_before,
		"SP-1 a refused issue leaves no audit line")

	-- With the privilege the same command works, and it is audited.
	_G.__player_privs["sp_noadmin"] = { smp_admin = true }
	ran = run_chatcommand(sender:get_player_name(),
		"/spawner give sp_target skeleton 5")
	eq(ran, true, "SP-1 a sender with smp_admin runs the command")
	local got = target:get_inventory():get_stack("main", 1)
	eq(got:get_name(), "smp_spawners:spawner_item",
		"SP-1 the target received a spawner item")
	eq(got:get_count(), 5, "SP-1 the target received the requested count")
	ok(has_log("[smp_spawners] /spawner give 5xskeleton to sp_target "
		.. "by sp_noadmin"),
		"SP-1 the issue is written to the action log")
end

----------------------------------------------------------------------
-- Security batch S06 — SP-2: leftovers are dropped, never destroyed
----------------------------------------------------------------------

do
	-- (a) /spawner give into a full inventory: the leftover falls at
	-- the target's feet. InvRef:add_item ALWAYS returns a leftover
	-- stack (l_inventory.cpp:275-291), so the test is is_empty().
	local sender = connect(make_player("sp_adm2", 10, 65, 10),
		{ smp_admin = true })
	local target = connect(make_player("sp_bulge", 12, 65, 12,
		{ slots = 1 }))
	local filler = ItemStack(BONE)
	filler:set_count(64)
	target:get_inventory():add_item("main", filler)

	local before = #dropped
	run_chatcommand(sender:get_player_name(),
		"/spawner give sp_bulge skeleton 64")
	eq(#dropped, before + 1,
		"SP-2 the give leftover is dropped, not destroyed")
	local d = dropped[#dropped]
	eq(d.via, "add_item", "SP-2 the leftover uses core.add_item")
	ok(d.via ~= "item_drop",
		"SP-2 never the mis-called core.item_drop(pos, stack)")
	eq(d.stack:get_name(), "smp_spawners:spawner_item",
		"SP-2 the leftover is the spawner stack")
	eq(d.stack:get_count(), 64, "SP-2 every refused item survives")
	near(d.pos.y, 65.5, 1e-9, "SP-2 dropped at the target's feet")

	-- (b) A Silk Touch dig into a full inventory: same rule, dropped
	-- half a node above the spawner.
	local pos = place_spawner("skeleton", 1)
	local vdef = core.registered_nodes["smp_spawners:spawner"]
	local digger = connect(make_player("sp_fulldig", 10, 65, 10,
		{ slots = 1 }))
	local filler2 = ItemStack(BONE)
	filler2:set_count(64)
	digger:get_inventory():add_item("main", filler2)
	digger._wielded = { _name = "mcl_tools:pickaxe",
		_ench = { silk_touch = 1 } }

	before = #dropped
	vdef.on_dig(pos, { name = "smp_spawners:spawner" }, digger)
	eq(core.get_node_or_nil(pos).name, "air", "SP-2 the dig removed the node")
	eq(#dropped, before + 1, "SP-2 the dig leftover is dropped")
	local d2 = dropped[#dropped]
	eq(d2.via, "add_item", "SP-2 the dig leftover uses core.add_item")
	eq(d2.stack:get_name(), "smp_spawners:spawner_item",
		"SP-2 the dig leftover is the spawner stack")
	eq(d2.stack:get_count(), 1, "SP-2 the dig leftover count")
	near(d2.pos.y, 64.5, 1e-9, "SP-2 dropped above the node")
end

----------------------------------------------------------------------
-- Security batch S06 — SP-3: no oversized stacks, no lost output
----------------------------------------------------------------------

do
	-- (a) A take is capped by free inventory space: one free slot
	-- holds 64, so 436 of the 500 stay stored.
	local pos = place_spawner("skeleton", 1)
	local st = state(pos)
	st.store[BONE] = 500
	st.last_update = now
	smp_spawners.write_state(st)

	local player = connect(make_player("sp_cap", 10, 65, 10, { slots = 1 }))
	local before = #dropped
	local taken = smp_spawners.take(pos, player, "skeleton", BONE, 500)
	eq(taken, 64, "SP-3 a take is capped at stack_max x free space")
	near(state(pos).store[BONE], 436, 1e-9,
		"SP-3 only the delivered items leave the store")
	eq(player:get_inventory():get_stack("main", 1):get_count(), 64,
		"SP-3 the free slot holds a full stack")
	eq(#dropped, before, "SP-3 a capped take drops nothing on the floor")

	-- (b) A full inventory takes nothing at all and writes nothing.
	local full = connect(make_player("sp_full", 10, 65, 10, { slots = 1 }))
	local filler = ItemStack(BONE)
	filler:set_count(64)
	full:get_inventory():add_item("main", filler)
	local store_before = core.get_meta(pos):get_string("smp:store")
	local v0 = state(pos).version
	local taken2 = smp_spawners.take(pos, full, "skeleton", BONE, 500)
	eq(taken2, 0, "SP-3 a full inventory takes nothing")
	eq(core.get_meta(pos):get_string("smp:store"), store_before,
		"SP-3 a refused take leaves the store byte-identical")
	eq(state(pos).version, v0, "SP-3 a refused take writes nothing")

	-- (c) Way past the u16 range: ItemStack:set_count(n) CLEARS the
	-- stack for n > 65535 (l_item.cpp:91-96), so the take must arrive
	-- in stack_max-sized chunks instead of one 100000-item stack.
	local pos2 = place_spawner("skeleton", 1)
	local st2 = state(pos2)
	st2.store[BONE] = 100000
	st2.last_update = now
	smp_spawners.write_state(st2)

	STACK_MAX[BONE] = 65535   -- per-item override; restore below
	local big = connect(make_player("sp_big", 10, 65, 10, { slots = 2 }))
	local taken3 = smp_spawners.take(pos2, big, "skeleton", BONE, 100000)
	eq(taken3, 100000, "SP-3 a >65535 take is delivered in chunks")
	near(state(pos2).store[BONE], 0, 1e-9, "SP-3 the store is emptied")
	local inv = big:get_inventory()
	eq(inv:get_stack("main", 1):get_count(), 65535,
		"SP-3 the first chunk stops at stack_max")
	eq(inv:get_stack("main", 2):get_count(), 34465,
		"SP-3 the second chunk carries the remainder")
	eq(inv:get_stack("main", 1):is_empty(), false,
		"SP-3 no chunk was cleared by set_count")
	STACK_MAX[BONE] = nil

	-- (d) Sell all with a >u16 store: lots are split at stack_max and
	-- exactly the handed counts are subtracted.
	local pos3 = place_spawner("skeleton", 1)
	local st3 = state(pos3)
	st3.store[BONE] = 100000
	st3.last_update = now
	smp_spawners.write_state(st3)
	local v3 = state(pos3).version
	local routed = nil
	smp_sell = {
		sell = function(p, stacks)
			routed = { player = p, stacks = stacks }
			return true
		end,
	}
	local seller = connect(make_player("sp_sell", 10, 65, 10))
	local ok_sell, _ = smp_spawners.routing.sell_all(pos3, seller,
		"skeleton")
	eq(ok_sell, true, "SP-3 the big sale succeeds")
	ok(routed ~= nil, "SP-3 f02 was reached")
	eq(routed and #routed.stacks or 0, 1563,
		"SP-3 the 100000 lot is split into stack_max lots")
	local sum, max_count, sane = 0, 0, true
	for _, lot in ipairs(routed and routed.stacks or {}) do
		local c = lot:get_count()
		sum = sum + c
		if c > max_count then max_count = c end
		if c < 1 or c > 64 then sane = false end
	end
	eq(sum, 100000, "SP-3 every item reaches f02 (conservation)")
	eq(max_count, 64, "SP-3 no lot exceeds stack_max")
	ok(sane, "SP-3 no lot is empty or oversized")
	eq(routed and routed.stacks[#routed.stacks]:get_count() or -1, 32,
		"SP-3 the tail lot carries the remainder")
	near(state(pos3).store[BONE], 0, 1e-9,
		"SP-3 exactly the handed counts are subtracted")
	ok(state(pos3).version > v3, "SP-3 the version moves on success")

	-- (e) A refused sale subtracts nothing, however large the store.
	local pos4 = place_spawner("skeleton", 1)
	local st4 = state(pos4)
	st4.store[BONE] = 100000
	st4.last_update = now
	smp_spawners.write_state(st4)
	local store4 = core.get_meta(pos4):get_string("smp:store")
	smp_sell = { sell = function() return false, {} end }
	local refused = smp_spawners.routing.sell_all(pos4, seller, "skeleton")
	eq(refused, false, "SP-3 a refused sale returns false")
	eq(core.get_meta(pos4):get_string("smp:store"), store4,
		"SP-3 a refused sale leaves the store byte-identical")
	smp_sell = nil
end

----------------------------------------------------------------------
-- Security batch S06 — SP-4: mutations need area access, view does not
----------------------------------------------------------------------

do
	local pos = place_spawner("skeleton", 1)
	local st = state(pos)
	st.store[BONE] = 64
	st.xp = 30
	st.last_update = now
	smp_spawners.write_state(st)

	local player = connect(make_player("sp_guarded", 10, 65, 10))
	protected_forced = true

	-- VIEWING stays open: open_requires_access still defaults false and
	-- the 3-argument revalidate (the view gate) consults no protection.
	shown_forms["sp_guarded"] = nil
	smp_spawners.interaction.open_menu(pos, player)
	ok(shown_forms["sp_guarded"] ~= nil,
		"SP-4 a protected spawner can still be looked at")
	ok(smp_spawners.revalidate(pos, "skeleton", player) ~= nil,
		"SP-4 the view gate does not consult protection")

	-- MUTATIONS all refuse, before anything is written.
	local store_before = core.get_meta(pos):get_string("smp:store")
	local v0 = state(pos).version
	chat_reset("sp_guarded")

	local taken = smp_spawners.take(pos, player, "skeleton", BONE, 64)
	eq(taken, 0, "SP-4 take refuses on a protected area")
	eq(state(pos).store[BONE], 64, "SP-4 refused take leaves the store")
	eq(state(pos).version, v0, "SP-4 refused take writes nothing")
	ok(chat_has("sp_guarded", "This area is protected"),
		"SP-4 the player is told why take refused")

	local xp = smp_spawners.collect_xp(pos, player, "skeleton")
	eq(xp, 0, "SP-4 Collect XP refuses on a protected area")
	eq(state(pos).xp, 30, "SP-4 refused Collect XP leaves the XP")

	local called = false
	smp_sell = {
		sell = function()
			called = true
			return true
		end,
	}
	local sold, msg = smp_spawners.routing.sell_all(pos, player,
		"skeleton")
	eq(sold, false, "SP-4 Sell all refuses on a protected area")
	eq(msg, nil,
		"SP-4 a protected refusal carries no bogus \"removed\" line")
	eq(called, false, "SP-4 f02 is never reached for a protected area")
	ok(not chat_has("sp_guarded", "This spawner has been removed"),
		"SP-4 the player is not told the spawner was removed")
	eq(core.get_meta(pos):get_string("smp:store"), store_before,
		"SP-4 a refused sale leaves the store byte-identical")
	smp_sell = nil

	protected_forced = false
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
			print(string.format("  in-game suite (test.lua): %d assertions",
				res.passed))
			for _, l in ipairs(res.lines or {}) do print("  " .. l) end
		end
	end
end

----------------------------------------------------------------------

print(string.format("smp_spawners dev-tests: %d passed, %d failed",
	passed, failed))
os.exit(failed == 0 and 0 or 1)
