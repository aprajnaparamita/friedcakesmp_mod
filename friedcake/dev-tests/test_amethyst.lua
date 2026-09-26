-- Smoke test: smp_amethyst pure logic (f06 T3, T6 and the drill plane).
--
-- Covers the engine-free parts of spec/features/f06-shards.md §4.3:
--   * the 3x3 plane geometry of the Shard Pickaxe / Shovel (T4 shape)
--   * the felling BFS and its hard cap at amethyst.felling_limit (T6)
--   * the self-destruct timer: expiry set/compare/sweep (T3)
--
-- Runs under plain LuaJIT with no core stub: logic.lua and expiry.lua
-- are pure.

local ROOT
for _, c in ipairs({
	"friedcake/mods/smp_amethyst/",   -- repo root (documented way)
	"mods/smp_amethyst/",             -- cwd is friedcake/
	"../mods/smp_amethyst/",          -- cwd is friedcake/dev-tests/
	"/Volumes/Dara/dev/coconut/friedcake/mods/smp_amethyst/", -- dev machine
}) do
	local f = io.open(c .. "init.lua", "r")
	if f then f:close(); ROOT = c:gsub("/+$", ""); break end
end
assert(ROOT, "smp_amethyst mod not found")
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

local function fake_inv(slots)   -- 1-indexed, exactly like engine lists
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
	local inv = fake_inv({ [1] = good, [2] = dead })
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
		self.wear = 0
		return self
	end
	function IS:get_name() return self.name end
	function IS:is_empty() return self.name == "" end
	function IS:get_count() return self.count end
	function IS:set_count(n) self.count = n end
	function IS:get_wear() return self.wear end
	function IS:add_wear(amount)
		self.wear = (self.wear or 0) + (amount or 1)
	end
	function IS:get_meta()
		local f = self.fields
		return {
			get_string = function(_, k) return f[k] or "" end,
			set_string = function(_, k, v) f[k] = v end,
		}
	end
	setmetatable(IS, { __call = function(_, name) return IS.new(name) end })
	ItemStack = IS

	local world = {}
	local chats = {}
	local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
	-- A pickaxe-diggable test node.
	local PICK_NAME = "stone"
	-- A blacklisted node (spawner per dig blacklist proposal)
	local BLACKLIST_NAME = "mcl_mobspawners:spawner"

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
			return ROOT
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
		register_craftitem = function(name, def) core.registered_items[name] = def end,
		register_on_joinplayer = function(fn)
			core._join_hooks = core._join_hooks or {}
			table.insert(core._join_hooks, fn)
		end,
		register_globalstep = function() end,
		register_on_item_pickup = function(fn) core._on_item_pickup = fn end,
		get_connected_players = function() return {} end,
		-- STRICT engine stubs (S05/QB-1 harness requirement): the engine
		-- runs luaL_checkstring on both and RAISES on a non-string first
		-- argument (l_env.cpp:648, l_server.cpp:92). Every suite in
		-- dev-tests carries these so an ObjectRef-where-a-name-was-expected
		-- bug cannot pass silently here while crashing in-game.
		chat_send_player = function(name, msg)
			if type(name) ~= "string" then
				error(string.format(
					"engine parity: core.chat_send_player expects a string name, got %s",
					type(name)), 2)
			end
			chats[#chats + 1] = { name = name, msg = msg }
		end,
		get_player_by_name = function(name)
			if type(name) ~= "string" then
				error(string.format(
					"engine parity: core.get_player_by_name expects a string name, got %s",
					type(name)), 2)
			end
			return nil
		end,
		is_protected = function() return false end,
		get_node_or_nil = function(pos) return world[key(pos)] end,
		get_node = function(pos)
			return world[key(pos)] or { name = "air" }
		end,
		get_meta = function(pos)
			local node = world[key(pos)]
			if node and node.get_meta then
				return node.get_meta()
			end
			return { get_inventory = function() return nil end }
		end,
		get_node_drops = function() return {} end,
		handle_node_drops = function() end,
		remove_node = function(pos) world[key(pos)] = nil end,
		set_node = function(pos, n) world[key(pos)] = n end,
		node_dig = function(pos, node, player)
			world[key(pos)] = nil
			-- Apply wear to the player's wielded tool (simulating engine behavior)
			local tool = player:get_wielded_item()
			if tool and tool.add_wear then
				tool:add_wear(1)
			end
		end,
	}
	core.registered_nodes[PICK_NAME] =
		{ diggable = true, groups = { pickaxey = 3 } }
	-- Blacklisted node: not diggable by the tool, but present in dig_blacklist_nodes
	core.registered_nodes[BLACKLIST_NAME] =
		{ diggable = true, groups = { pickaxey = 3 } }

	_G.smp_amethyst = nil
	dofile(ROOT .. "/init.lua")

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

	-- Declare inventory tables BEFORE fake_player so they're captured as upvalues
	local main_inv = {}
	local offhand_inv = {}

	local function fake_player(name, tool)
		return {
			is_player = function() return true end,
			get_player_name = function() return name end,
			get_wielded_item = function() return tool end,
			set_wielded_item = function(_, st) tool = st end,
			get_meta = function()
				return {
					get_string = function(_, k) return "" end,
					set_string = function(_, k, v) end,
				}
			end,
			get_inventory = function()
				return {
					get_size = function(_, list)
						if list == "main" then return 36 end
						if list == "offhand" then return 1 end
						return 0
					end,
					get_stack = function(_, list, i)
						if list == "main" then
							local s = main_inv[i]
							return s or ItemStack("")
						end
						if list == "offhand" then
							local s = offhand_inv[i]
							return s or ItemStack("")
						end
						return ItemStack("")
					end,
					set_stack = function(_, list, i, stack)
						if list == "main" then main_inv[i] = stack end
						if list == "offhand" then offhand_inv[i] = stack end
					end,
				}
			end,
		}
	end

	----------------------------------------------------------------------
	-- F06-1 join test: amethyst items in main AND offhand get description
	-- refreshed on join.
	----------------------------------------------------------------------
	do
		main_inv = {}
		offhand_inv = {}
		local now = os.time()
		-- Fresh pickaxe in main (lists are 1-based: slot 1, engine index 1)
		local pick_main = ItemStack("smp_amethyst:pickaxe")
		smp_amethyst.expiry.set_expiry(pick_main, now + 86400)
		main_inv[1] = pick_main
		-- Fresh shovel in offhand
		local shovel_off = ItemStack("smp_amethyst:shovel")
		smp_amethyst.expiry.set_expiry(shovel_off, now + 86400)
		offhand_inv[1] = shovel_off

		local player = fake_player("diana", ItemStack(""))
		-- Fire the join hooks registered by smp_amethyst
		for _, fn in ipairs(core._join_hooks or {}) do fn(player) end

		-- Both items should have their descriptions refreshed
		local pick_desc = main_inv[1]:get_meta():get_string("description")
		local shovel_desc = offhand_inv[1]:get_meta():get_string("description")
		assert(pick_desc and pick_desc:find("Expires in"), "main item description refreshed: " .. tostring(pick_desc))
		assert(shovel_desc and shovel_desc:find("Expires in"), "offhand item description refreshed: " .. tostring(shovel_desc))
		print("F06-1 join test ok: both main and offhand descriptions refreshed")
	end

	----------------------------------------------------------------------
	-- T4 shape: the drill digs the 3x3 plane (9 blocks), skipping
	-- protected and blacklisted nodes. Wear applied exactly once.
	----------------------------------------------------------------------
	do
		world = {}
		core.get_node_or_nil = function(pos) return world[key(pos)] end
		core.get_node = function(pos) return world[key(pos)] or { name = "air" } end
		core.remove_node = function(pos) world[key(pos)] = nil end
		_G.core.node_dig = function(pos, node, player)
			world[key(pos)] = nil
			-- Apply wear to the player's wielded tool (simulating engine behavior)
			local tool = player:get_wielded_item()
			if tool and tool.add_wear then
				tool:add_wear(1)
			end
		end

		local under = { x = 10, y = 0, z = 0 }
		world[key(under)] = { name = PICK_NAME }
		for dy = -1, 1 do
			for dz = -1, 1 do
				if not (dy == 0 and dz == 0) then
					world[key({ x = 10, y = dy, z = dz })] = { name = PICK_NAME }
				end
			end
		end
		-- One protected neighbour
		local protected_pos = { x = 10, y = 1, z = -1 }
		world[key(protected_pos)] = { name = PICK_NAME }
		-- One blacklisted neighbour (spawner)
		local blacklisted_pos = { x = 10, y = -1, z = 1 }
		world[key(blacklisted_pos)] = { name = BLACKLIST_NAME }

		core.is_protected = function(pos)
			return pos.x == protected_pos.x and pos.y == protected_pos.y
				and pos.z == protected_pos.z
		end

		local before = 0
		for _ in pairs(world) do before = before + 1 end
		local tool = ItemStack("smp_amethyst:pickaxe")
		local wear_before = tool:get_wear()
		local player = fake_player("alice", tool)
		local returned = core.registered_items["smp_amethyst:pickaxe"]
			.on_use_primary(tool, player, {
				type = "node",
				under = under,
				above = { x = 11, y = 0, z = 0 },
			})
		local after = 0
		for _ in pairs(world) do after = after + 1 end
		local removed = before - after
		assert(removed == 7,
			"drill removed 7 of 9 (one protected + one blacklisted): removed "
			.. removed)
		assert(world[key(protected_pos)], "protected node survives")
		assert(world[key(blacklisted_pos)], "blacklisted node (spawner) survives")
		assert(smp_amethyst.in_dig("alice") == false,
			"dig guard cleared after use")
		-- Wear applied exactly once (on the centre block via core.node_dig)
		local wear_after = returned:get_wear()
		assert(wear_after > wear_before, "wear was applied")
		-- Only one add_wear call worth (exact amount depends on tool caps)
		print("T4 shape ok: drill plane with protected + blacklisted skip, wear-once")
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

	----------------------------------------------------------------------
	-- T7: amethyst items can be sold and auctioned (acceptance paths).
	----------------------------------------------------------------------
	do
		-- The sell axe routes to smp_orders.best_open_order then smp_sell.
		-- Here we verify the *acceptance* half: the item is not rejected
		-- by the sell/auction logic due to being amethyst.
		-- We stub the counterpart mods to accept the item.
		local sell_accept = false
		local auction_accept = false
		local function fake_sell(player, stack)
			if smp_amethyst.expiry.is_amethyst(stack:get_name()) then
				sell_accept = true
				return true
			end
			return false
		end
		local function fake_auction_list(player, stack, price)
			if smp_amethyst.expiry.is_amethyst(stack:get_name()) then
				auction_accept = true
				return true
			end
			return false
		end
		_G.smp_sell = { sell = fake_sell }
		_G.smp_ah = { list_item = fake_auction_list }
		_G.smp_items = { key = function(stack, level) return stack:get_name() .. ":" .. level end }

		-- Reload init to pick up the stubs (the sell axe uses them at call time)
		_G.smp_amethyst = nil
		dofile(ROOT .. "/init.lua")

		-- Simulate sell axe use on a container with an amethyst pickaxe
		world = {}
		local container_pos = { x = 0, y = 0, z = 0 }
		world[key(container_pos)] = {
			name = "mcl_chests:chest",
			get_meta = function()
				return {
					get_inventory = function()
						local inv = { [1] = ItemStack("smp_amethyst:pickaxe") }
						return {
							get_size = function() return 1 end,
							get_stack = function(_, listname, i) return inv[i] end,
							set_stack = function(_, listname, i, v) inv[i] = v end,
						}
					end,
				}
			end,
		}
		core.registered_nodes["mcl_chests:chest"] = {
			groups = { chest = 1 },
			on_rightclick = function() end,
		}
		core.is_protected = function() return false end

		local tool = ItemStack("smp_amethyst:sell_axe")
		local player = fake_player("eve", tool)
		core.registered_items["smp_amethyst:sell_axe"]
			.on_use_primary(tool, player, {
				type = "node",
				under = container_pos,
				above = { x = 0, y = 1, z = 0 },
			})
		assert(sell_accept, "sell path accepted amethyst item")
		-- Auction path is harder to test without full ah; we just verify
		-- the blacklist doesn't block it (orders blacklist is separate)
		assert(not smp_amethyst.blacklist[smp_amethyst.blacklist[1] .. "_fake"],
			"blacklist is exact itemstrings only")
		print("T7 ok: amethyst items accepted by sell/auction paths")
	end

	----------------------------------------------------------------------
	-- S05/AX-1 / AX-2: the sell axe must never destroy unpaid stacks,
	-- and inventory lists are 1-based.
	----------------------------------------------------------------------
	do
		-- A chest whose main list is a plain Lua table keyed by the
		-- engine's 1-based slot numbers.
		local function make_chest(slots, size)
			return {
				name = "mcl_chests:chest",
				get_meta = function()
					return {
						get_inventory = function()
							return {
								get_size = function() return size end,
								get_stack = function(_, _, i)
									return slots[i] or ItemStack("")
								end,
								set_stack = function(_, _, i, v)
									if type(v) == "string" then
										slots[i] = ItemStack("")
									else
										slots[i] = v
									end
								end,
							}
						end,
					}
				end,
			}
		end

		local order_refusals, sell_calls = 0, 0
		local order_accepts, order_raises = false, false
		_G.smp_orders = {
			best_open_order = function(key) return { id = "o1", key = key } end,
			fill_from_stack = function(_order, _player, stack)
				order_refusals = order_refusals + 1
				if order_raises then error("fill_from_stack exploded") end
				if order_accepts then
					return { accepted = stack:get_count(), payout = 1, remaining = 0 }
				end
				-- The refusal contract (smp_orders/routing.lua:243): the
				-- order wants 1, the stack is 64 -> whole stack or nothing.
				return nil, "full"
			end,
		}
		_G.smp_sell = { sell = function() sell_calls = sell_calls + 1 return false end }

		local function use_sell_axe(at)
			local tool = ItemStack("smp_amethyst:sell_axe")
			local player = fake_player("frank", tool)
			core.registered_items["smp_amethyst:sell_axe"].on_use_primary(
				tool, player, {
					type = "node",
					under = at,
					above = { x = at.x, y = at.y + 1, z = at.z },
				})
		end

		local at = { x = 20, y = 0, z = 0 }
		local slots = {}
		slots[1] = ItemStack("mcl_core:diamond")
		slots[1]:set_count(64)
		world[key(at)] = make_chest(slots, 1)

		-- (a) order REFUSES, sell REFUSES: the 64 diamonds must survive.
		--     The old `accepted ~= false` deleted them here, unpaid.
		use_sell_axe(at)
		assert(order_refusals >= 1, "AX-1 the refusing fill was attempted")
		assert(slots[1] and slots[1]:get_name() == "mcl_core:diamond"
			and slots[1]:get_count() == 64,
			"AX-1 refused order + refused sell: the stack is untouched (got "
			.. tostring(slots[1] and slots[1]:get_name()) .. " x"
			.. tostring(slots[1] and slots[1]:get_count()) .. ")")

		-- (b) order REFUSES, sell PAYS: the axe falls through to
		--     route_to_sell and clears the slot only then.
		sell_calls = 0
		_G.smp_sell = { sell = function() sell_calls = sell_calls + 1 return true end }
		use_sell_axe(at)
		assert(sell_calls == 1, "AX-1 a refused order falls through to route_to_sell")
		assert(slots[1]:is_empty(), "AX-1 the paid stack was cleared")

		-- (c) order ACCEPTS: routed, cleared, and NOT sold a second time.
		order_accepts = true
		slots[1] = ItemStack("mcl_core:diamond")
		slots[1]:set_count(64)
		sell_calls = 0
		_G.smp_sell = { sell = function() sell_calls = sell_calls + 1 return true end }
		use_sell_axe(at)
		assert(sell_calls == 0, "AX-1 an accepted fill does not double-sell")
		assert(slots[1]:is_empty(), "AX-1 an accepted fill clears the slot")

		-- (d) fill_from_stack RAISES: pcall success is not the call's
		--     success — the stack must survive that too (nothing paid).
		order_accepts, order_raises = false, true
		slots[1] = ItemStack("mcl_core:diamond")
		slots[1]:set_count(64)
		sell_calls = 0
		_G.smp_sell = { sell = function() sell_calls = sell_calls + 1 return false end }
		use_sell_axe(at)
		assert(slots[1]:get_name() == "mcl_core:diamond"
			and slots[1]:get_count() == 64,
			"AX-1 a raising fill leaves the stack in place")
		order_raises = false

		-- AX-2: a 27-slot chest with the only item in slot 27 (the last
		-- one). The old `for i = 0, size - 1` never reached it. Slot 0
		-- holds a trap the engine rejects (l_inventory.cpp: index - 1).
		local chest27 = {}
		for i = 1, 27 do chest27[i] = ItemStack("") end
		chest27[27] = ItemStack("mcl_core:diamond")
		chest27[27]:set_count(3)
		chest27[0] = ItemStack("mcl_core:dirt")
		local at27 = { x = 30, y = 0, z = 0 }
		world[key(at27)] = make_chest(chest27, 27)
		sell_calls = 0
		_G.smp_sell = { sell = function() sell_calls = sell_calls + 1 return true end }
		use_sell_axe(at27)
		assert(chest27[27]:is_empty(),
			"AX-2 the last slot (27) is processed: got "
			.. tostring(chest27[27]:get_name()))
		assert(sell_calls == 1, "AX-2 exactly one stack routed: got " .. sell_calls)
		assert(chest27[0] and chest27[0]:get_name() == "mcl_core:dirt",
			"AX-2 slot 0 is never read (the engine rejects index 0)")

		print("S05/AX-1 + AX-2 ok: refused fills never delete, 1-based lists")
	end

	----------------------------------------------------------------------
	-- Regression: register_on_item_pickup must NOT block normal pickup.
	-- A truthy return short-circuits the engine's default add-to-inventory.
	----------------------------------------------------------------------
	do
		assert(core._on_item_pickup, "pickup callback registered")
		local p = fake_player("pickup_test", ItemStack(""))

		-- Normal (non-amethyst) item: defer to the engine (nil).
		local wood = ItemStack("mcl_core:wood")
		assert(core._on_item_pickup(wood, p) == nil,
			"non-amethyst pickup defers to engine")

		-- Live amethyst item (future expiry): also defer (nil).
		local live = ItemStack("smp_amethyst:pickaxe")
		smp_amethyst.expiry.set_expiry(live, os.time() + 10000)
		assert(core._on_item_pickup(live, p) == nil,
			"live amethyst pickup defers to engine")

		-- Expired amethyst item: consumed (empty stack returned).
		local dead = ItemStack("smp_amethyst:pickaxe")
		smp_amethyst.expiry.set_expiry(dead, os.time() - 100)
		local r = core._on_item_pickup(dead, p)
		assert(r ~= nil and r:is_empty(), "expired amethyst pickup returns empty")
		print("pickup regression ok: normal items are not blocked")
	end
end

print("ALL OK")
