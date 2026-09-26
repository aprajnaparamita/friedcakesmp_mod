-- Standalone smoke test for smp_enderchest — runs under plain luajit,
-- no engine. Stubs core, ItemStack, mcl_formspec and a faithful fake
-- inventory (set_size truncates on shrink exactly like the engine's
-- InventoryList::setSize), registers mcl_chests' own join callback
-- first, then loads the mod and exercises the capacity contract, the
-- formspec geometry, the formname substitution, the show_formspec
-- wrapper, join migration, the reach rule and the modpack wiring.
--
-- Run: luajit friedcake/dev-tests/test_enderchest.lua
-- Exits non-zero on any failure (tools/agent-flow.sh test).

-- Locate the repository root from the script path.
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
		print(string.format("FAIL: %s — expected %s got %s",
			tostring(msg), tostring(b), tostring(a)))
	end
end

----------------------------------------------------------------------
-- ItemStack stub
----------------------------------------------------------------------

local function new_itemstack(name, count)
	name = name or ""
	if name == "" then
		count = 0
	else
		count = count or 1
	end
	local s = { _name = name, _count = count }
	function s:get_name() return self._name end
	function s:get_count() return self._count end
	function s:is_empty() return self._name == "" or self._count <= 0 end
	function s:get_definition() return {} end
	function s:to_string() return self._name .. " " .. self._count end
	return s
end
ItemStack = function(name, count) return new_itemstack(name, count) end

local function copy_stack(s)
	return new_itemstack(s:get_name(), s:get_count())
end

----------------------------------------------------------------------
-- Fake inventory — engine-faithful where it matters:
--   * set_size GROWS preserving items and SHRINKS by destroying every
--     slot beyond the new size (InventoryList::setSize →
--     m_items.resize truncates). This is the exact hazard that makes
--     the engine's 27-slot "enderchest" list unusable for 54 slots.
--   * set_stack / add_item copy stacks by value, like the C++ side.
----------------------------------------------------------------------

local function inv_new()
	local lists = {}
	local inv = {}

	local function ensure(name)
		if not lists[name] then lists[name] = {} end
		return lists[name]
	end

	function inv:set_size(name, size)
		local items = ensure(name)
		if #items == size then return end
		local grown = {}
		for i = 1, size do
			grown[i] = items[i] or new_itemstack("")
		end
		lists[name] = grown
	end

	function inv:get_size(name)
		local items = lists[name]
		return items and #items or 0
	end

	function inv:get_list(name)
		local items = lists[name]
		if not items then return nil end
		local out = {}
		for i, s in ipairs(items) do out[i] = copy_stack(s) end
		return out
	end

	function inv:set_stack(name, i, stack)
		local items = ensure(name)
		if type(stack) == "string" then
			items[i] = new_itemstack(stack)
		else
			items[i] = copy_stack(stack)
		end
	end

	function inv:room_for_item(name, stack)
		local items = ensure(name)
		for _, s in ipairs(items) do
			if s:is_empty() then return true end
			if s:get_name() == stack:get_name()
					and s:get_count() + stack:get_count() <= 99 then
				return true
			end
		end
		return false
	end

	function inv:add_item(name, stack)
		local items = ensure(name)
		local src = copy_stack(stack)
		for _, s in ipairs(items) do
			if not s:is_empty() and s:get_name() == src:get_name()
					and s:get_count() + src:get_count() <= 99 then
				s._count = s._count + src:get_count()
				return nil
			end
		end
		for i, s in ipairs(items) do
			if s:is_empty() then
				items[i] = src
				return nil
			end
		end
		return src
	end

	function inv:get_location() return { type = "player" } end

	return inv
end

local function collect_nonempty(inv, listname)
	local out = {}
	for _, s in ipairs(inv:get_list(listname) or {}) do
		if not s:is_empty() then out[#out + 1] = s:to_string() end
	end
	return out
end

local function make_player(name)
	local p = {}
	p._name = name
	p._pos = { x = 0, y = 64, z = 0 }
	p._inv = inv_new()
	p.get_player_name = function() return name end
	p.get_pos = function() return p._pos end
	p.get_inventory = function() return p._inv end
	p.get_wielded_item = function() return new_itemstack("") end
	return p
end

----------------------------------------------------------------------
-- core stub
----------------------------------------------------------------------

local join_cbs, allow_cbs = {}, {}
local shown = {}
local chest_in_reach = false

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
	get_current_modname = function() return "smp_enderchest" end,
	get_modpath = function(m) return ROOT .. "/friedcake/mods/" .. m end,
	settings = {
		get = function() return "" end,
		get_bool = function(_, _, default) return default end,
	},
	log = function() end,
	formspec_escape = function(s) return s end,
	colorize = function(_, text) return text end,
	registered_nodes = {
		-- Upstream Mineclonia help text: both defs claim 27 slots until
		-- smp_enderchest rewrites them (T4 proves the rewrite).
		["mcl_chests:ender_chest"] = {
			_tt_help = "27 interdimensional inventory slots\n" ..
				"Put items inside, retrieve them from any ender chest",
			_doc_items_longdesc = "Ender chests grant you access to a " ..
				"single personal interdimensional inventory with 27 slots.",
		},
		["mcl_chests:ender_chest_small"] = {
			_tt_help = "27 interdimensional inventory slots\n" ..
				"Put items inside, retrieve them from any ender chest",
			_doc_items_longdesc = "Ender chests grant you access to a " ..
				"single personal interdimensional inventory with 27 slots.",
		},
	},
	show_formspec = function(player, formname, formspec)
		shown[#shown + 1] =
			{ player = player, formname = formname, formspec = formspec }
	end,
	register_on_joinplayer = function(fn)
		join_cbs[#join_cbs + 1] = fn
	end,
	register_allow_player_inventory_action = function(fn)
		allow_cbs[#allow_cbs + 1] = fn
	end,
	find_node_near = function()
		if chest_in_reach then
			return { name = "mcl_chests:ender_chest_small" }
		end
		return nil
	end,
}

-- mcl_formspec stub: emit a recognisable marker per background block
-- so the test can assert the requested geometry.
mcl_formspec = {
	label_color = "#313131",
	get_itemslot_bg_v4 = function(x, y, w, h)
		return string.format("BG[%s,%s;%s,%s]",
			tostring(x), tostring(y), tostring(w), tostring(h))
	end,
}

----------------------------------------------------------------------
-- Load the mod — mcl_chests' join callback first, exactly as the
-- depends = mcl_chests ordering guarantees in the engine
----------------------------------------------------------------------

table.insert(join_cbs, function(player)
	player:get_inventory():set_size("enderchest", 9 * 3)
end)

local chunk, lerr = loadfile(ROOT .. "/friedcake/mods/smp_enderchest/init.lua")
ok(chunk ~= nil, "init.lua loads: " .. tostring(lerr))
if chunk then
	local good, err = pcall(chunk)
	ok(good, "init.lua runs: " .. tostring(err))
	if not good then
		print(string.format("smp_enderchest dev-tests: %d passed, %d failed",
			passed, failed))
		os.exit(1)
	end
end

local E = smp_enderchest
local LIST = E.LIST

----------------------------------------------------------------------
-- T1 — capacity: 9 columns x 6 rows = 54 slots
----------------------------------------------------------------------

eq(type(E), "table", "T1 mod table exported")
eq(E.COLS, 9, "T1 nine columns")
eq(E.ROWS, 6, "T1 six rows")
eq(E.SLOTS, 54, "T1 capacity is 54 slots")
eq(E.COLS * E.ROWS, E.SLOTS, "T1 SLOTS = COLS * ROWS")
eq(E.SLOTS, 9 * 3 * 2, "T1 exactly twice a normal chest")
eq(LIST, "smp_enderchest", "T1 storage list name")

----------------------------------------------------------------------
-- T2 — formspec geometry: double-chest rhythm, 9x6 ender list
----------------------------------------------------------------------

local fs = E.formspec()
ok(fs:find("formspec_version[4]", 1, true), "T2 formspec version 4")
ok(fs:find("size[11.75,14.15]", 1, true),
	"T2 size matches mcl_chests' double chest")
ok(fs:find("BG[0.375,0.75;9,6]", 1, true),
	"T2 container background requested as 9x6")
ok(fs:find("BG[0.375,8.825;9,3]", 1, true),
	"T2 main background 9x3 at 8.825")
ok(fs:find("BG[0.375,12.775;9,1]", 1, true),
	"T2 hotbar background 9x1 at 12.775")
ok(fs:find("list[current_player;" .. LIST .. ";0.375,0.75;9,6;]", 1, true),
	"T2 9x6 ender list at 0.375,0.75")
ok(fs:find("list[current_player;main;0.375,8.825;9,3;9]", 1, true),
	"T2 main rows under the container")
ok(fs:find("list[current_player;main;0.375,12.775;9,1;]", 1, true),
	"T2 hotbar row last")
ok(not fs:find("current_player;enderchest;", 1, true),
	"T2 engine 27-slot list is not referenced")
local _, nlists = fs:gsub("list%[current_player;", "")
eq(nlists, 3, "T2 exactly three list elements")
local ri = fs:find("listring[current_player;" .. LIST .. "]", 1, true)
local rm = fs:find("listring[current_player;main]", 1, true)
ok(ri and rm and ri < rm, "T2 listring cycles ender list into main")
ok(fs:find("Ender Chest", 1, true), "T2 title is Ender Chest")
ok(fs:find("Inventory", 1, true), "T2 Inventory label present")

----------------------------------------------------------------------
-- T3 — formname substitution: only the ender-chest formname swaps
----------------------------------------------------------------------

eq(E.intercept("mcl_chests:ender_chest_Alice", "stock 9x3"), fs,
	"T3 ender formname replaced with the 9x6 formspec")
eq(E.intercept("mcl_chests:ender_chest_", "stock"), fs,
	"T3 bare ender prefix replaced")
eq(E.intercept("mcl_chests:chest_1_2_3", "keep"), "keep",
	"T3 double chest untouched")
eq(E.intercept("mcl_chests:trapped_chest_1_2_3", "keep"), "keep",
	"T3 trapped chest untouched")
eq(E.intercept("smp_quickbuy:main", "keep"), "keep",
	"T3 other mods' formspecs untouched")
eq(E.intercept(123, 123), 123, "T3 non-string formname passes through")

----------------------------------------------------------------------
-- T4 — help text: both ender-chest defs say 54, never 27
----------------------------------------------------------------------

for _, name in ipairs({ "mcl_chests:ender_chest", "mcl_chests:ender_chest_small" }) do
	local def = core.registered_nodes[name]
	ok(def ~= nil, "T4 " .. name .. " is registered")
	if def then
		local tt = def._tt_help or ""
		ok(tt:find("54 interdimensional inventory slots", 1, true),
			"T4 " .. name .. " tooltip says 54 slots")
		ok(not tt:find("27", 1, true),
			"T4 " .. name .. " tooltip no longer says 27")
		ok((def._doc_items_longdesc or ""):find("54 slots", 1, true),
			"T4 " .. name .. " doc longdesc says 54 slots")
	end
end

----------------------------------------------------------------------
-- T5 — the core.show_formspec wrapper
----------------------------------------------------------------------

eq(type(core.show_formspec), "function", "T5 show_formspec is a function")
eq(#shown, 0, "T5 nothing was shown during load")
core.show_formspec("Alice", "mcl_chests:ender_chest_Alice", "stock 9x3")
eq(#shown, 1, "T5 wrapper forwards exactly one call")
eq(shown[1] and shown[1].player, "Alice", "T5 player forwarded")
eq(shown[1] and shown[1].formname, "mcl_chests:ender_chest_Alice",
	"T5 formname preserved (mcl_chests' close handler keys on it)")
eq(shown[1] and shown[1].formspec, fs,
	"T5 stock 9x3 formspec replaced by our 9x6")
core.show_formspec("Alice", "mcl_chests:chest_1_2_3", "double chest")
eq(shown[2] and shown[2].formspec, "double chest",
	"T5 double-chest formspec untouched")
core.show_formspec("Bob", "smp_quickbuy:main", "quickbuy")
eq(shown[3] and shown[3].formspec, "quickbuy",
	"T5 unrelated formspec untouched")

----------------------------------------------------------------------
-- T6 — join: grow to 54, migrate the engine list, never lose items
----------------------------------------------------------------------

local function run_join(p)
	for _, cb in ipairs(join_cbs) do cb(p) end
end

-- A stock-Mineclonia player: 27-slot engine list with three stacks.
local alice = make_player("Alice")
local ainv = alice:get_inventory()
ainv:set_size("enderchest", 27)
ainv:set_stack("enderchest", 1, new_itemstack("mcl_core:diamond", 5))
ainv:set_stack("enderchest", 9, new_itemstack("mcl_core:apple", 12))
ainv:set_stack("enderchest", 27, new_itemstack("mcl_tools:pick_diamond", 1))

run_join(alice)
eq(ainv:get_size("smp_enderchest"), 54, "T6 our list is 54 slots after join")
eq(ainv:get_size("enderchest"), 27, "T6 engine list stays mcl_chests' 27")
local migrated = collect_nonempty(ainv, "smp_enderchest")
eq(#migrated, 3, "T6 three legacy stacks migrated")
eq(migrated[1], "mcl_core:diamond 5", "T6 first legacy stack preserved")
eq(migrated[2], "mcl_core:apple 12", "T6 second legacy stack preserved")
eq(migrated[3], "mcl_tools:pick_diamond 1", "T6 third legacy stack preserved")
eq(#collect_nonempty(ainv, "enderchest"), 0,
	"T6 engine list cleared (no double storage)")

-- Second login. mcl_chests again runs set_size("enderchest", 27) —
-- our list must be untouched. This is the regression the engine's
-- truncating set_size would otherwise cause on every login.
run_join(alice)
eq(ainv:get_size("smp_enderchest"), 54, "T6 still 54 slots after rejoin")
local again = collect_nonempty(ainv, "smp_enderchest")
eq(#again, 3, "T6 items survive a second join (no 54→27 wipe)")
eq(again[1], "mcl_core:diamond 5", "T6 contents intact after rejoin")
eq(#collect_nonempty(ainv, "enderchest"), 0,
	"T6 engine list still empty after rejoin")

-- Fresh player: gets an empty 54-slot list of their own.
local bob = make_player("Bob")
run_join(bob)
local binv = bob:get_inventory()
eq(binv:get_size("smp_enderchest"), 54, "T6 fresh player gets 54 slots")
eq(#collect_nonempty(binv, "smp_enderchest"), 0,
	"T6 fresh player starts empty")
eq(binv:get_size("enderchest"), 27, "T6 mcl_chests created the engine list")

-- Players never share storage: each carries their own list.
local carol = make_player("Carol")
run_join(carol)
carol:get_inventory():set_stack("smp_enderchest", 1,
	new_itemstack("mcl_core:emerald", 3))
eq(#collect_nonempty(alice:get_inventory(), "smp_enderchest"), 3,
	"T6 Alice unaffected by Carol's storage")
eq(#collect_nonempty(carol:get_inventory(), "smp_enderchest"), 1,
	"T6 Carol has her own storage")

----------------------------------------------------------------------
-- T7 — reach rule: our list needs an ender chest in reach
----------------------------------------------------------------------

eq(#allow_cbs, 1, "T7 exactly one allow-callback registered")
local allow = allow_cbs[1]
local carl = make_player("Carl")
local cinv = carl:get_inventory()
cinv:set_size("smp_enderchest", 54)
cinv:set_size("main", 36)

chest_in_reach = true
eq(allow(carl, "put", cinv, { listname = "smp_enderchest" }), nil,
	"T7 put allowed with a chest in reach")
eq(allow(carl, "take", cinv, { listname = "smp_enderchest" }), nil,
	"T7 take allowed with a chest in reach")
eq(allow(carl, "move", cinv,
	{ from_list = "main", to_list = "smp_enderchest" }), nil,
	"T7 move in allowed with a chest in reach")

chest_in_reach = false
eq(allow(carl, "put", cinv, { listname = "smp_enderchest" }), 0,
	"T7 put denied without a chest in reach")
eq(allow(carl, "take", cinv, { listname = "smp_enderchest" }), 0,
	"T7 take denied without a chest in reach")
eq(allow(carl, "move", cinv,
	{ from_list = "smp_enderchest", to_list = "main" }), 0,
	"T7 move out denied without a chest in reach")
eq(allow(carl, "put", cinv, { listname = "main" }), nil,
	"T7 other lists untouched")
eq(allow(carl, "move", cinv, { from_list = "main", to_list = "main" }), nil,
	"T7 unrelated move untouched")
eq(allow(carl, "put", cinv, { listname = "enderchest" }), nil,
	"T7 engine list stays mcl_chests' business")
local detached = {
	get_location = function() return { type = "detached" } end,
}
eq(allow(carl, "put", detached, { listname = "smp_enderchest" }), nil,
	"T7 non-player inventories untouched")

----------------------------------------------------------------------
-- T8 — modpack wiring
----------------------------------------------------------------------

local f = io.open(ROOT .. "/friedcake/mods/modpack.conf", "r")
ok(f ~= nil, "T8 modpack.conf readable")
if f then
	local content = f:read("*a")
	f:close()
	ok(content:find("load_mod = smp_enderchest", 1, true),
		"T8 load_mod = smp_enderchest present in modpack.conf")
end

----------------------------------------------------------------------
-- in-game test suite (mods/smp_enderchest/test.lua)
----------------------------------------------------------------------

print("== in-game test suite (mods/smp_enderchest/test.lua) ==")
do
	local tchunk, lerr = loadfile(ROOT .. "/friedcake/mods/smp_enderchest/test.lua")
	ok(tchunk ~= nil, "test.lua loads: " .. tostring(lerr))
	if tchunk then
		local good, res = pcall(tchunk)
		ok(good, "test.lua runs: " .. tostring(res))
		if good and type(res) == "table" then
			eq(res.failed, 0, "in-game suite has no failures (" ..
				tostring(res.passed) .. " passed)")
			for _, l in ipairs(res.lines or {}) do print("  " .. l) end
		end
	end
end

----------------------------------------------------------------------

print(string.format("smp_enderchest dev-tests: %d passed, %d failed",
	passed, failed))
os.exit(failed == 0 and 0 or 1)
