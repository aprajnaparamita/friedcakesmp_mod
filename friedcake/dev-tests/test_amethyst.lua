-- Smoke test: smp_amethyst pure logic (f06 T3, T6 and the drill plane).
--
-- Covers the engine-free parts of spec/features/f06-shards.md §4.3:
--   * the 3x3 plane geometry of the Shard Pickaxe / Shovel (T4 shape)
--   * the felling BFS and its hard cap at amethyst.felling_limit (T6)
--   * the self-destruct timer: expiry set/compare/sweep (T3)
--
-- Runs under plain LuaJIT with no core stub: logic.lua and expiry.lua
-- are pure.

local ROOT = "/Volumes/Dara/dev/coconut/friedcake/mods/smp_amethyst"
local logic = dofile(ROOT .. "/logic.lua")
local expiry = dofile(ROOT .. "/expiry.lua")

----------------------------------------------------------------------
-- Plane geometry (T4 shape: nine blocks in the plane perpendicular to
-- the dug face)
----------------------------------------------------------------------

do
	local under = { x = 10, y = 0, z = 0 }
	-- Facing +X: above is one cell further in +X.
	local above = { x = 11, y = 0, z = 0 }
	local plane = logic.plane_positions(under, above)
	assert(#plane == 9, "plane has 9 positions, got " .. #plane)
	-- Every position lies in the YZ plane at x = under.x.
	for _, p in ipairs(plane) do
		assert(p.x == under.x, "plane position off-axis: x=" .. p.x)
	end
	-- All 9 distinct y/z cells present.
	local seen, cells = {}, 0
	for _, p in ipairs(plane) do
		local k = p.y .. "," .. p.z
		if not seen[k] then seen[k] = true; cells = cells + 1 end
	end
	assert(cells == 9, "plane covers 9 distinct cells, got " .. cells)
	assert(seen["0,0"] == true, "plane includes the centre")

	-- Facing +Y: plane is the XZ plane.
	plane = logic.plane_positions(under, { x = 10, y = 1, z = 0 })
	for _, p in ipairs(plane) do
		assert(p.y == under.y, "plane position off-axis: y=" .. p.y)
	end
	-- Facing -Z: above has a smaller z.
	plane = logic.plane_positions(under, { x = 10, y = 0, z = -1 })
	for _, p in ipairs(plane) do
		assert(p.z == under.z, "plane position off-axis: z=" .. p.z)
	end
	print("plane geometry ok")
end

----------------------------------------------------------------------
-- Felling BFS (T6: stops at the limit)
----------------------------------------------------------------------

local function make_world(logs, leaves)
	local world = {}
	local function put(x, y, z, group)
		world[x .. "," .. y .. "," .. z] = { [group] = 1 }
	end
	for _, l in ipairs(logs) do put(l[1], l[2], l[3], "tree") end
	for _, l in ipairs(leaves) do put(l[1], l[2], l[3], "leaves") end
	return function(pos)
		return world[pos.x .. "," .. pos.y .. "," .. pos.z]
	end
end

do
	-- A 4-high log with a 3x3 leaf layer on top: 4 logs + 9 leaves = 13.
	local logs = { {0,0,0}, {0,1,0}, {0,2,0}, {0,3,0} }
	local leaves = {}
	for dx = -1, 1 do
		for dz = -1, 1 do
			leaves[#leaves + 1] = { dx, 4, dz }
		end
	end
	local get = make_world(logs, leaves)
	local visited = logic.bfs_connected({x=0,y=0,z=0}, get,
		{ "tree", "leaves" }, 512)
	assert(#visited == 13, "full tree is 13 nodes, got " .. #visited)

	-- T6: the limit is a hard stop.
	local capped = logic.bfs_connected({x=0,y=0,z=0}, get,
		{ "tree", "leaves" }, 5)
	assert(#capped == 5, "limit 5 stops at 5, got " .. #capped)
	local capped1 = logic.bfs_connected({x=0,y=0,z=0}, get,
		{ "tree", "leaves" }, 1)
	assert(#capped1 == 1, "limit 1 stops at 1, got " .. #capped1)

	-- Disconnected trees are not reached.
	local get2 = make_world(logs, {})
	local visited2 = logic.bfs_connected({x=0,y=0,z=0}, get2,
		{ "tree", "leaves" }, 512)
	assert(#visited2 == 4, "only the connected trunk, got " .. #visited2)
	print("felling BFS ok (13-node tree, capped at limit)")
end

----------------------------------------------------------------------
-- Expiry (T3)
----------------------------------------------------------------------

local function fake_stack()
	local fields = { name = "unknown:item" }
	return {
		fields = fields,
		get_name = function() return fields.name end,
		is_empty = function() return false end,
		get_meta = function(self)
			return {
				get_string = function(_, k) return fields[k] or "" end,
				set_string = function(_, k, v) fields[k] = v end,
			}
		end,
	}
end

local function fake_inv(slots)   -- 0-indexed, like engine inventories
	local n = 0
	for _ in pairs(slots) do n = n + 1 end
	return {
		get_size = function(self, _) return n end,
		get_stack = function(self, _, i) return slots[i] end,
		set_stack = function(self, _, i, v)
			slots[i] = type(v) == "string"
				and { is_empty = function() return true end }
				or v
		end,
	}
end

do
	local now = 1000000
	local st = fake_stack()
	assert(expiry.is_expired(st, now) == false, "no expiry -> never expires")

	expiry.set_expiry(st, now + 86400)
	assert(expiry.expires_at(st) == now + 86400, "expiry stored")
	assert(expiry.is_expired(st, now + 86399) == false, "not yet expired")
	assert(expiry.is_expired(st, now + 86400) == true, "expired at deadline")
	assert(expiry.remaining(st, now) == 86400, "remaining at purchase")
	assert(expiry.remaining(st, now + 3600) == 82800, "remaining after 1 h")

	-- duration formatting
	assert(expiry.duration_str(86400) == "1d", "1d")
	assert(expiry.duration_str(90000) == "1d 1h", "1d 1h")
	assert(expiry.duration_str(3600) == "1h", "1h")
	assert(expiry.duration_str(90) == "1m", "1m")

	-- sweep removes only expired amethyst stacks and notifies.
	local good = fake_stack()
	local dead = fake_stack()
	good:get_meta():set_string("name", "smp_amethyst:pickaxe")
	dead:get_meta():set_string("name", "smp_amethyst:axe")
	expiry.set_expiry(good, now + 1000)
	expiry.set_expiry(dead, now - 5)
	local notified = {}
	local inv = fake_inv({ [0] = good, [1] = dead })
	local removed = expiry.sweep_list(inv, "main", function(stack)
		notified[#notified + 1] = stack
	end, now)
	assert(removed == 1, "one stack removed, got " .. removed)
	assert(notified[1] == dead, "the expired stack was notified")
	assert(good.fields[expiry.META_KEY] ~= "", "good stack untouched")
	print("expiry ok")
end

----------------------------------------------------------------------
-- Full module load under a core stub: registrations and tool callbacks
----------------------------------------------------------------------

do
	-- Fake ItemStack (the engine global).
	local IS = {}
	IS.__index = IS
	function IS.new(name)
		local self = setmetatable({}, IS)
		self.name = name or ""
		self.count = 1
		self.fields = {}
		return self
	end
	function IS:get_name() return self.name end
	function IS:is_empty() return self.name == "" end
	function IS:get_count() return self.count end
	function IS:set_count(n) self.count = n end
	function IS:get_meta()
		local f = self.fields
		return {
			get_string = function(_, k) return f[k] or "" end,
			set_string = function(_, k, v) f[k] = v end,
		}
	end
	function IS:add_wear() end
	setmetatable(IS, { __call = function(_, name) return IS.new(name) end })
	ItemStack = IS

	local world = {}
	local chats = {}
	local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
	-- A pickaxe-diggable test node.
	local PICK_NAME = "stone"

	core = {
		get_translator = function()
			return function(s, ...)
				local a = {...}
				return (s:gsub("@(%d+)", function(n)
					return tostring(a[tonumber(n)] or "")
				end))
			end
		end,
		get_current_modname = function() return "smp_amethyst" end,
		get_modpath = function(m)
			return "/Volumes/Dara/dev/coconut/friedcake/mods/" .. m
		end,
		log = function(l, ...)
			if l == "error" then print("[ERR]", ...) end
		end,
		settings = {
			get = function() return "" end,
			get_bool = function() return false end,
		},
		registered_items = {},
		registered_nodes = {},
		register_tool = function(name, def) core.registered_items[name] = def end,
		register_item = function(name, def) core.registered_items[name] = def end,
		register_on_joinplayer = function() end,
		register_globalstep = function() end,
		register_on_pickup = function() end,
		get_connected_players = function() return {} end,
		chat_send_player = function(name, msg)
			chats[#chats + 1] = { name = name, msg = msg }
		end,
		is_protected = function() return false end,
		get_node_or_nil = function(pos) return world[key(pos)] end,
		get_node = function(pos)
			return world[key(pos)] or { name = "air" }
		end,
		get_meta = function()
			return { get_inventory = function() return nil end }
		end,
		get_node_drops = function() return {} end,
		handle_node_drops = function() end,
		remove_node = function(pos) world[key(pos)] = nil end,
		set_node = function(pos, n) world[key(pos)] = n end,
		node_dig = function(pos, node, player) world[key(pos)] = nil end,
	}
	core.registered_nodes[PICK_NAME] =
		{ diggable = true, groups = { pickaxey = 3 } }

	_G.smp_amethyst = nil
	dofile("/Volumes/Dara/dev/coconut/friedcake/mods/smp_amethyst/init.lua")

	-- All six items registered.
	for _, name in ipairs({
		"smp_amethyst:pickaxe", "smp_amethyst:axe", "smp_amethyst:shovel",
		"smp_amethyst:haste_potion", "smp_amethyst:bucket",
		"smp_amethyst:sell_axe",
	}) do
		assert(core.registered_items[name], "registered " .. name)
	end
	-- The blacklist is exposed for f04.
	assert(#smp_amethyst.blacklist == 6, "blacklist has 6 entries")

	local function fake_player(name, tool)
		return {
			get_player_name = function() return name end,
			get_wielded_item = function() return tool end,
			set_wielded_item = function(_, st) tool = st end,
		}
	end

	----------------------------------------------------------------------
	-- T4 shape: the drill digs the 3x3 plane (9 blocks), skipping
	-- protected and blacklisted nodes.
	----------------------------------------------------------------------
	do
		world = {}
		core.get_node_or_nil = function(pos) return world[key(pos)] end
		core.get_node = function(pos) return world[key(pos)] or { name = "air" } end
		core.remove_node = function(pos) world[key(pos)] = nil end
		core.node_dig = function(pos, node, player) world[key(pos)] = nil end

		local under = { x = 10, y = 0, z = 0 }
		world[key(under)] = { name = PICK_NAME }
		for dy = -1, 1 do
			for dz = -1, 1 do
				if not (dy == 0 and dz == 0) then
					world[key({ x = 10, y = dy, z = dz })] = { name = PICK_NAME }
				end
			end
		end
		-- One protected neighbour and one blacklisted neighbour: both
		-- survive the drill.
		local protected_pos = { x = 10, y = 1, z = -1 }
		world[key(protected_pos)] = { name = PICK_NAME }
		core.is_protected = function(pos)
			return pos.x == protected_pos.x and pos.y == protected_pos.y
				and pos.z == protected_pos.z
		end

		local before = 0
		for _ in pairs(world) do before = before + 1 end
		local tool = ItemStack("smp_amethyst:pickaxe")
		local player = fake_player("alice", tool)
		local returned = core.registered_items["smp_amethyst:pickaxe"]
			.on_use_primary(tool, player, {
				type = "node",
				under = under,
				above = { x = 11, y = 0, z = 0 },
			})
		local after = 0
		for _ in pairs(world) do after = after + 1 end
		assert(before - after == 8,
			"drill removed 8 of 9 (one protected): removed "
			.. (before - after))
		assert(world[key(protected_pos)], "protected node survives")
		assert(smp_amethyst.in_dig("alice") == false,
			"dig guard cleared after use")
		print("T4 shape ok: drill plane with protected skip")
	end

	----------------------------------------------------------------------
	-- T5: refused while combat-tagged.
	----------------------------------------------------------------------
	do
		world = {}
		local under = { x = 5, y = 5, z = 5 }
		world[key(under)] = { name = PICK_NAME }
		core.is_protected = function() return false end
		smp_combat = { is_tagged = function() return true end }
		local tool = ItemStack("smp_amethyst:pickaxe")
		local player = fake_player("bob", tool)
		core.registered_items["smp_amethyst:pickaxe"]
			.on_use_primary(tool, player, {
				type = "node",
				under = under,
				above = { x = 5, y = 5, z = 6 },
			})
		assert(world[key(under)], "tagged: nothing dug")
		local saw_refusal = false
		for _, c in ipairs(chats) do
			if c.msg:find("combat") then saw_refusal = true end
		end
		assert(saw_refusal, "tagged: refusal message sent")
		smp_combat = nil
		print("T5 ok: refused while tagged")
	end

	----------------------------------------------------------------------
	-- T3: using an expired item removes it with a message.
	----------------------------------------------------------------------
	do
		local tool = ItemStack("smp_amethyst:shovel")
		smp_amethyst.expiry.set_expiry(tool, os.time() - 10)
		local player = fake_player("carol", tool)
		local returned = core.registered_items["smp_amethyst:shovel"]
			.on_use_primary(tool, player, nil)
		assert(returned:is_empty(), "expired use returns empty stack")
		local saw_msg = false
		for _, c in ipairs(chats) do
			if c.msg:find("expired") then saw_msg = true end
		end
		assert(saw_msg, "expired: removal message sent")
		print("T3 (use) ok: expired item removed on use")
	end
end

print("ALL OK")
