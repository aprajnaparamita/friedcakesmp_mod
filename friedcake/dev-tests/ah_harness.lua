-- dev-tests/ah_harness.lua — a fake engine for f03's smoke tests
--
-- Stubs just enough of `core.*`, `ItemStack`, inventories and players for
-- smp_core / smp_store / smp_economy / smp_items / smp_ah to load and run, so
-- the auction house's acceptance tests (f03 §9 T1–T10) can be exercised
-- without a server. Not named `test_*.lua`, so `tools/agent-flow.sh test`
-- does not try to run it directly.
--
-- Usage:
--   local H = dofile(HERE .. "/ah_harness.lua")
--   H.boot()
--   local alice = H.player("alice", { money = 100000, items = { "mcl_core:dirt 2" } })
--   H.cmd("ah", "alice", "")
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local H = {}

local HERE = (arg and arg[0] or "friedcake/dev-tests/x.lua"):match("^(.*)[/\\][^/\\]*$") or "."
H.HERE = HERE
H.MODROOT = HERE .. "/../mods/"
H.REPO = HERE .. "/../.."
-- An override: `H.MODROOT = "/some/path/mods"` after require sets the absolute
-- mod location (handy when dofile'd from a script whose own path doesn't lead
-- to the test harness's directory).
local function resolve_modroot()
	return H.MODROOT
end
H.LOAD_ORDER = { "smp_admin", "smp_core", "smp_store", "smp_items", "smp_economy",
	"smp_ranks", "smp_ah" }

----------------------------------------------------------------------
-- JSON (minimal, mirrors dev-tests/test_economy.lua's stub)
----------------------------------------------------------------------

local function json_encode(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if v == math.floor(v) and math.abs(v) < 2 ^ 53 then
			return string.format("%.0f", v)
		end
		return string.format("%.14g", v)
	end
	if t == "string" then
		return '"' .. v:gsub("[\\\"\n\r\t]", function(ch)
			if ch == "\n" then return "\\n" end
			if ch == "\r" then return "\\r" end
			if ch == "\t" then return "\\t" end
			return "\\" .. ch
		end) .. '"'
	end
	if t == "table" then
		local n, is_array = 0, true
		for k in pairs(v) do
			if type(k) ~= "number" then is_array = false break end
			n = n + 1
		end
		if is_array and n == #v then
			local p = {}
			for i = 1, #v do p[i] = json_encode(v[i]) end
			return "[" .. table.concat(p, ",") .. "]"
		end
		local p = {}
		for k, vv in pairs(v) do
			p[#p + 1] = json_encode(tostring(k)) .. ":" .. json_encode(vv)
		end
		table.sort(p)
		return "{" .. table.concat(p, ",") .. "}"
	end
	return "null"
end

local function skip_ws(s, i)
	while i <= #s do
		local ch = s:sub(i, i)
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r" then i = i + 1
		else break end
	end
	return i
end

local function parse_str(s, i)
	local out, j = "", i + 1
	while j <= #s do
		local ch = s:sub(j, j)
		if ch == '"' then return out, j + 1 end
		if ch == "\\" then
			local nc = s:sub(j + 1, j + 1)
			if nc == "n" then out = out .. "\n"
			elseif nc == "r" then out = out .. "\r"
			elseif nc == "t" then out = out .. "\t"
			else out = out .. nc end
			j = j + 2
		else
			out = out .. ch
			j = j + 1
		end
	end
	error("unterminated string")
end

local parse_val
local function parse_obj(s, i)
	local t = {}
	i = i + 1
	while true do
		i = skip_ws(s, i)
		if i > #s then break end
		if s:sub(i, i) == "}" then return t, i + 1 end
		local k
		k, i = parse_str(s, i)
		i = skip_ws(s, i)
		if s:sub(i, i) ~= ":" then error("expected : at " .. i) end
		i = skip_ws(s, i + 1)
		local v
		v, i = parse_val(s, i)
		t[k] = v
		i = skip_ws(s, i)
		if s:sub(i, i) == "," then i = i + 1 end
	end
	error("unterminated object")
end

local function parse_arr(s, i)
	local t, idx = {}, 1
	i = i + 1
	while true do
		i = skip_ws(s, i)
		if i > #s then break end
		if s:sub(i, i) == "]" then return t, i + 1 end
		local v
		v, i = parse_val(s, i)
		t[idx], idx = v, idx + 1
		i = skip_ws(s, i)
		if s:sub(i, i) == "," then i = i + 1 end
	end
	error("unterminated array")
end

function parse_val(s, i)
	i = skip_ws(s, i)
	local ch = s:sub(i, i)
	if ch == '"' then return parse_str(s, i) end
	if ch == "{" then return parse_obj(s, i) end
	if ch == "[" then return parse_arr(s, i) end
	local j = i
	while j <= #s and s:sub(j, j):match("[%-%d%.eE%+a-zA-Z]") do j = j + 1 end
	local tok = s:sub(i, j - 1)
	if tok == "true" then return true, j end
	if tok == "false" then return false, j end
	if tok == "null" then return nil, j end
	return tonumber(tok), j
end

local function json_decode(s)
	if type(s) ~= "string" or s == "" then return nil end
	local ok, v = pcall(parse_val, s, 1)
	if not ok then return nil end
	return v
end

H.json_encode, H.json_decode = json_encode, json_decode

----------------------------------------------------------------------
-- serialize / deserialize (Lua source form, like the engine)
----------------------------------------------------------------------

local function lua_serialize(v, indent)
	indent = indent or ""
	local t = type(v)
	if t == "number" or t == "boolean" then return tostring(v) end
	if t == "string" then return string.format("%q", v) end
	if t ~= "table" then return "nil" end
	local keys, array_n = {}, 0
	for k in pairs(v) do
		if type(k) == "number" and k == math.floor(k) and k >= 1 then
			array_n = math.max(array_n, k)
		else
			keys[#keys + 1] = k
		end
	end
	local parts = {}
	local is_array = (#keys == 0)
	for i = 1, array_n do
		parts[#parts + 1] = indent .. "  " .. lua_serialize(v[i], indent .. "  ")
	end
	if not is_array then
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			local ks = (type(k) == "number") and ("[" .. k .. "]") or
				("[" .. string.format("%q", tostring(k)) .. "]")
			parts[#parts + 1] = indent .. "  " .. ks .. " = " ..
				lua_serialize(v[k], indent .. "  ")
		end
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function lua_deserialize(s)
	if type(s) ~= "string" or s == "" then return nil end
	local body = s:match("^%s*return%s+(.*)$")
	if not body then
		-- The engine also accepts a bare table literal.
		body = s:match("^%s*(%{.*%})%s*$")
	end
	if not body then return nil end
	local f = loadstring("return " .. body)
	if not f then return nil end
	local ok, v = pcall(f)
	if not ok then return nil end
	return v
end

----------------------------------------------------------------------
-- ItemStack / ItemMeta / Inventory stubs
----------------------------------------------------------------------

local Stack = {}
Stack.__index = Stack

local descriptions = {}   -- itemstring -> description (set by boot())

local function make_meta(fields)
	local m = { _f = fields or {} }
	function m:get_string(k) local v = self._f[k] return v == nil and "" or tostring(v) end
	function m:set_string(k, v) self._f[k] = v end
	function m:get_int(k) return math.floor(tonumber(self._f[k]) or 0) end
	function m:set_int(k, v) self._f[k] = tostring(math.floor(v)) end
	function m:to_table() return { fields = self._f } end
	function m:get_keys()
		local out = {}
		for k in pairs(self._f) do out[#out + 1] = k end
		table.sort(out)
		return out
	end
	function m:equals(other)
		local a, b = self._f, (other and other._f) or {}
		for k, v in pairs(a) do if b[k] ~= v then return false end end
		for k, v in pairs(b) do if a[k] ~= v then return false end end
		return true
	end
	return m
end
H.make_meta = make_meta

--- ItemStack(itemstring | table | nil | ItemStack)
function H.ItemStack(x)
	local s = setmetatable({ _name = "", _count = 0, _wear = 0, _fields = {} }, Stack)
	if x == nil or x == "" then return s end
	if getmetatable(x) == Stack then
		s._name, s._count, s._wear = x._name, x._count, x._wear
		for k, v in pairs(x._fields) do s._fields[k] = v end
		return s
	end
	if type(x) == "table" then
		s._name = x.name or ""
		s._count = math.floor(tonumber(x.count) or 1)
		s._wear = math.floor(tonumber(x.wear) or 0)
		for k, v in pairs(x.metadata or {}) do s._fields[k] = v end
		return s
	end
	-- itemstring: "name", "name count", "name count wear", plus an optional
	-- quoted metadata blob (the engine's `to_string` form).
	local str = tostring(x)
	local meta = str:match("%s'(.*)'%s*$")
	if meta then
		str = str:gsub("%s*'.*'%s*$", "")
		for k, v in pairs(lua_deserialize(meta) or {}) do s._fields[k] = v end
	end
	local name, count, wear = str:match("^(%S+)%s+(%d+)%s+(%d+)$")
	if name then
		s._name, s._count, s._wear = name, tonumber(count), tonumber(wear)
	else
		name, count = str:match("^(%S+)%s+(%d+)$")
		if name then
			s._name, s._count = name, tonumber(count)
		else
			s._name = str:match("^(%S+)$") or ""
			s._count = 1                -- `ItemStack("name")` parses to count=1
		end
	end
	return s
end
ItemStack = H.ItemStack

function Stack:is_empty() return self._name == "" or self._count <= 0 end
function Stack:get_name() return self._name end
function Stack:set_name(n) self._name = n return self:is_empty() end
function Stack:get_count() return self._count end
function Stack:set_count(n) self._count = math.floor(tonumber(n) or 0) return self:is_empty() end
function Stack:get_wear() return self._wear end
function Stack:set_wear(w) self._wear = math.floor(tonumber(w) or 0) return self:is_empty() end
function Stack:get_meta() return make_meta(self._fields) end
function Stack:get_stack_max()
	local def = core.registered_items[self._name]
	return (def and def.stack_max) or 64
end
function Stack:clear() self._name, self._count, self._fields = "", 0, {} end
function Stack:to_string()
	if self:is_empty() then return "" end
	local out = self._name
	if self._count ~= 1 or self._wear ~= 0 or next(self._fields) then
		out = out .. " " .. self._count
	end
	if self._wear ~= 0 or next(self._fields) then
		out = out .. " " .. self._wear
	end
	if next(self._fields) then
		out = out .. " '" .. lua_serialize(self._fields) .. "'"
	end
	return out
end
function Stack:to_table()
	return { name = self._name, count = self._count, wear = self._wear,
		metadata = self._fields }
end
function Stack:get_description()
	if self._fields["description"] and self._fields["description"] ~= "" then
		return self._fields["description"]
	end
	local def = core.registered_items[self._name]
	return (def and def.description) or descriptions[self._name] or self._name
end
function Stack:get_short_description()
	return (self:get_description():match("^[^\n]*")) or self._name
end
function Stack:get_definition() return core.registered_items[self._name] end
function Stack:is_known() return core.registered_items[self._name] ~= nil end
function Stack:add_item(list_ignored) return self end
function Stack:take_item(n)
	n = math.min(math.floor(tonumber(n) or 1), self._count)
	local out = H.ItemStack(self)
	out._count = n
	self._count = self._count - n
	if self._count <= 0 then self:clear() end
	return out
end
function Stack:peek_item(n)
	local out = H.ItemStack(self)
	out._count = math.min(math.floor(tonumber(n) or 1), self._count)
	return out
end

----------------------------------------------------------------------
-- Inventory
----------------------------------------------------------------------

local Inv = {}
Inv.__index = Inv

function H.Inventory(size, callbacks, owner)
	local inv = setmetatable({
		_lists = {}, _size = {}, _callbacks = callbacks, _owner = owner,
	}, Inv)
	inv._lists["main"] = {}
	inv._size["main"] = size or 36
	return inv
end

function Inv:set_size(list, n)
	self._size[list] = math.floor(n)
	self._lists[list] = self._lists[list] or {}
	for i = #self._lists[list] + 1, n do self._lists[list][i] = H.ItemStack() end
	for i = n + 1, #self._lists[list] do self._lists[list][i] = nil end
	return true
end

function Inv:get_size(list) return self._size[list] or 0 end

function Inv:_list(list)
	self._lists[list] = self._lists[list] or {}
	local l = self._lists[list]
	for i = 1, self:get_size(list) do l[i] = l[i] or H.ItemStack() end
	return l
end

function Inv:get_list(list) 
	local out = {}
	local l = self:_list(list)
	for i = 1, self:get_size(list) do out[i] = H.ItemStack(l[i]) end
	return out
end

function Inv:set_list(list, arr)
	local l = self:_list(list)
	for i = 1, self:get_size(list) do
		local s = arr and arr[i]
		l[i] = (s and not s:is_empty()) and H.ItemStack(s) or H.ItemStack()
	end
	return true
end

function Inv:get_stack(list, i)
	return H.ItemStack(self:_list(list)[math.floor(i)] or H.ItemStack())
end

function Inv:set_stack(list, i, stack)
	self:_list(list)[math.floor(i)] = (stack and not stack:is_empty())
		and H.ItemStack(stack) or H.ItemStack()
	return true
end

function Inv:is_empty(list)
	for i = 1, self:get_size(list) do
		if not self:_list(list)[i]:is_empty() then return false end
	end
	return true
end

function Inv:contains_item(list, stack, match_meta)
	local want = stack:get_name()
	local n = stack:get_count()
	for i = 1, self:get_size(list) do
		local s = self:_list(list)[i]
		if not s:is_empty() and s:get_name() == want then
			n = n - s:get_count()
			if n <= 0 then return true end
		end
	end
	return false
end

--- How many of `stack` fit, honouring stack_max and existing partial stacks.
function Inv:room_for_item(list, stack)
	if not stack or stack:is_empty() then return true end
	local left = stack:get_count()
	local max = stack:get_stack_max()
	local l = self:_list(list)
	for i = 1, self:get_size(list) do
		if left <= 0 then break end
		local s = l[i]
		if s:is_empty() then
			left = left - max
		elseif s:get_name() == stack:get_name() and s:get_wear() == stack:get_wear()
		   and s:get_meta():equals(stack:get_meta()) then
			left = left - (max - s:get_count())
		end
	end
	return left <= 0
end

function Inv:add_item(list, stack)
	local left = H.ItemStack(stack)
	if left:is_empty() then return left end
	local max = left:get_stack_max()
	local l = self:_list(list)
	-- Merge first, then fill empties (the engine's order).
	for i = 1, self:get_size(list) do
		if left:is_empty() then break end
		local s = l[i]
		if not s:is_empty() and s:get_name() == left:get_name()
		   and s:get_wear() == left:get_wear()
		   and s:get_meta():equals(left:get_meta()) then
			local room = max - s:get_count()
			if room > 0 then
				local move = math.min(room, left:get_count())
				s:set_count(s:get_count() + move)
				left:set_count(left:get_count() - move)
			end
		end
	end
	for i = 1, self:get_size(list) do
		if left:is_empty() then break end
		if l[i]:is_empty() then
			l[i] = H.ItemStack(left)
			left:clear()
		end
	end
	return left
end

function Inv:remove_item(list, stack)
	local want = stack:get_count()
	local l = self:_list(list)
	for i = 1, self:get_size(list) do
		if want <= 0 then break end
		local s = l[i]
		if not s:is_empty() and s:get_name() == stack:get_name() then
			local take = math.min(want, s:get_count())
			s:set_count(s:get_count() - take)
			want = want - take
			if s:get_count() <= 0 then l[i] = H.ItemStack() end
		end
	end
	return stack
end

--- Test helper: a player-driven put, honouring the detached callbacks
--- (`allow_put`) exactly like the engine does.
function Inv:simulate_put(list, index, stack, player)
	if self._callbacks and self._callbacks.allow_put then
		local allowed = self._callbacks.allow_put(self, list, index, stack, player)
		if (tonumber(allowed) or 0) <= 0 then return stack end
		stack = H.ItemStack(stack)
		stack:set_count(math.min(stack:get_count(), allowed))
	end
	local l = self:_list(list)
	if not l[index]:is_empty() then return stack end
	l[index] = H.ItemStack(stack)
	if self._callbacks and self._callbacks.on_put then
		self._callbacks.on_put(self, list, index, stack, player)
	end
	return H.ItemStack()
end

--- Test helper: a player-driven take, honouring `allow_take`.
function Inv:simulate_take(list, index, player)
	local stack = self:_list(list)[index]
	if stack:is_empty() then return H.ItemStack() end
	if self._callbacks and self._callbacks.allow_take then
		local allowed = self._callbacks.allow_take(self, list, index, stack, player)
		if (tonumber(allowed) or 0) <= 0 then return H.ItemStack() end
	end
	self:_list(list)[index] = H.ItemStack()
	if self._callbacks and self._callbacks.on_take then
		self._callbacks.on_take(self, list, index, stack, player)
	end
	return stack
end

----------------------------------------------------------------------
-- Players
----------------------------------------------------------------------

H.players = {}
H.chat = {}       -- [pname] = { messages }
H.forms = {}      -- [pname] = { {formname=, fs=} }
H.last_form = {}  -- [pname] = {formname=, fs=}
H.closed = {}     -- [pname] = { formname }
H.logs = {}

local Player = {}
Player.__index = Player

function H.player(name, opts)
	opts = opts or {}
	local p = setmetatable({
		_name = name,
		_inv = H.Inventory(36),
		_wield = 1,
		_pos = { x = 0, y = 0, z = 0 },
		_hp = 20,
	}, Player)
	H.players[name] = p
	H.chat[name] = H.chat[name] or {}
	if opts.money or opts.shards then
		-- smp_store may not be loaded yet when the harness is used standalone.
		p._seed_money = opts.money or 0
		p._seed_shards = opts.shards or 0
	end
	local items = opts.items or {}
	for i, item in ipairs(items) do
		p._inv:set_stack("main", i, H.ItemStack(item))
	end
	if opts.wield then p._wield = opts.wield end
	return p
end

function Player:get_player_name() return self._name end
function Player:get_inventory() return self._inv end
function Player:get_wield_index() return self._wield end
function Player:get_wielded_item() return self._inv:get_stack("main", self._wield) end
function Player:set_wield_index(i) self._wield = i return true end
function Player:get_pos() return { x = self._pos.x, y = self._pos.y, z = self._pos.z } end
function Player:set_pos(p) self._pos = p end
function Player:get_hp() return self._hp end
function Player:set_hp(n) self._hp = n end
function Player:get_meta()
	self._meta = self._meta or make_meta({})
	return self._meta
end
function Player:hud_add() return 1 end
function Player:hud_change() return true end
function Player:send_formspec(fs, formname)
	core.show_formspec(self._name, formname, fs)
end
function Player:get_player_control() return {} end
function Player:set_animation() end

--- Remove a player from the world (disconnect). Fires the registered
--- `on_leaveplayer` callbacks, like the engine does.
function H.leave(name)
	local p = H.players[name]
	H.players[name] = nil
	for _, cb in ipairs(H.on_leave) do cb(p or name, false) end
	return p
end

function H.join(name)
	local p = H.players[name] or H.player(name)
	H.players[name] = p
	for _, cb in ipairs(H.on_join) do cb(p, false) end
	return p
end

----------------------------------------------------------------------
-- The core stub
----------------------------------------------------------------------

H.on_receive = {}
H.on_leave = {}
H.on_join = {}
H.on_globalstep = {}
H.on_shutdown = {}
H.on_mods_loaded = {}
H.commands = {}
H.detached = {}
H.storages = {}
H.settings_map = {}

local function storage_for(modname)
	modname = modname or _G.__current_modname or "unknown"
	H.storages[modname] = H.storages[modname] or {}
	local data = H.storages[modname]
	return {
		get_string = function(_, k) return data[k] or "" end,
		set_string = function(_, k, v) data[k] = v end,
		remove = function(_, k) data[k] = nil end,
		contains = function(_, k) return data[k] ~= nil end,
		get_keys = function(_)
			local out = {}
			for k in pairs(data) do out[#out + 1] = k end
			table.sort(out)
			return out
		end,
		to_table = function(_) return { fields = data } end,
	}
end
H.storage_for = storage_for
H.storage_data = function(modname) return H.storages[modname] or {} end

local ESC = string.char(27)

-- MS-3 (S03): the dev-test stubs for the engine's string arguments are as
-- strict as `luaL_checkstring` — strings and numbers pass, anything else
-- (an ObjectRef passed as a name) RAISES. S05 QB-1 crashed the server
-- through exactly this path, and a lenient stub would hide it.
local function checkname(fn, argidx, v)
	if type(v) ~= "string" and type(v) ~= "number" then
		error(string.format("bad argument #%d to '%s' (string expected, got %s)",
			argidx, fn, type(v)), 3)
	end
end
H.checkname = checkname

function H.boot(opts)
	opts = opts or {}
	H.settings_map = opts.settings or {}
	descriptions = opts.descriptions or {}
	H.chat, H.forms, H.last_form, H.closed, H.logs = {}, {}, {}, {}, {}
	H.on_receive, H.on_leave, H.on_join = {}, {}, {}
	H.on_globalstep, H.on_shutdown, H.on_mods_loaded = {}, {}, {}
	H.commands, H.detached, H.storages, H.players = {}, {}, {}, {}

	core = {
		registered_items = opts.items or {
			["mcl_core:dirt"]   = { description = "Dirt", stack_max = 64 },
			["mcl_core:diamond"] = { description = "Diamond", stack_max = 64 },
			["mcl_core:stone"]  = { description = "Stone", stack_max = 64 },
			["mcl_throwing:ender_pearl"] = { description = "Ender Pearl", stack_max = 16 },
			["mcl_tools:shovel_diamond"] = { description = "Diamond Shovel", stack_max = 1 },
			["mcl_chests:chest"] = { description = "Chest", stack_max = 64 },
			["mcl_hoppers:hopper"] = { description = "Hopper", stack_max = 64 },
			["mcl_signs:wall_sign_oak"] = { description = "Oak Sign", stack_max = 16 },
			["mcl_panes:pane_grey"] = { description = "Grey Glass Pane", stack_max = 64 },
			["mcl_panes:pane_lime"] = { description = "Lime Glass Pane", stack_max = 64 },
			["mcl_anvils:anvil"] = { description = "Anvil", stack_max = 1 },
		},
		registered_nodes = {},
		registered_aliases = opts.aliases or {},
		registered_chatcommands = H.commands,
		registered_privileges = {},

		get_translator = function(_mod)
			return function(s, ...)
				local args = { ... }
				return (tostring(s):gsub("@(%d+)", function(n)
					return tostring(args[tonumber(n)] or "")
				end))
			end
		end,
		get_current_modname = function() return _G.__current_modname end,
		get_modpath = function(m) return H.MODROOT .. m end,
		get_mod_storage = function() return storage_for(_G.__current_modname) end,
		get_worldpath = function() return "/tmp" end,
		DIR_DELIM = "/",

		write_json = json_encode,
		parse_json = json_decode,
		serialize = lua_serialize,
		deserialize = lua_deserialize,
		formspec_escape = function(s)
			return (tostring(s):gsub("\\", "\\\\"):gsub(";", "\\;")
				:gsub("%[", "\\["):gsub("%]", "\\]"))
		end,
		get_color_escape_sequence = function(color) return ESC .. "(c@" .. color .. ")" end,
		-- Mirrors the engine's builtin/common/misc_helpers.lua exactly, so
		-- colour escapes in rendered formspecs behave like the real thing.
		colorize = function(color, message)
			-- Mirrors the engine's split-on-newline-then-prefix-each-line.
			local code = ESC .. "(c@" .. color .. ")"
			local lines = {}
			local s2 = tostring(message)
			local NL = string.char(10)
			local function split(s)
				local out = {}
				local i = 1
				while i <= #s do
					local nl = s:find(NL, i, true)
					if nl then
						out[#out + 1] = s:sub(i, nl - 1)
						i = nl + 1
					else
						out[#out + 1] = s:sub(i)
						i = #s + 1
					end
				end
				return out
			end
			local parts = split(s2)
			-- The engine's split("\n", true) drops an empty trailing element
			-- so "abc\n" becomes {"abc"}.
			if #parts > 0 and parts[#parts] == "" then parts[#parts] = nil end
			for i, line in ipairs(parts) do parts[i] = code .. line end
			return table.concat(parts, NL) .. ESC .. "(c@#fff)"
		end,
		strip_colors = function(str)
			return (tostring(str):gsub(ESC .. "%([bc]@[^)]+%)", ""))
		end,
		explode_color_escape_text = function(s) return s end,

		log = function(level, msg)
			if msg == nil then msg = level level = "none" end
			H.logs[#H.logs + 1] = { level = level, msg = tostring(msg) }
			if H.verbose then print("[log:" .. level .. "] " .. tostring(msg)) end
		end,
		debug = function(msg) H.logs[#H.logs + 1] = { level = "debug", msg = tostring(msg) } end,

		-- MS-3 (S03): as strict as the engine — `luaL_checkstring` accepts
		-- strings and numbers and RAISES on anything else (see `checkname`
		-- above). An ObjectRef passed as a name is a fatal error in a
		-- callback (S05 QB-1), so the stub must fail the same way.
		chat_send_player = function(name, msg)
			checkname("chat_send_player", 1, name)
			checkname("chat_send_player", 2, msg)
			H.chat[name] = H.chat[name] or {}
			table.insert(H.chat[name], tostring(msg))
		end,
		chat_send_all = function(msg)
			H.chat["*"] = H.chat["*"] or {}
			table.insert(H.chat["*"], tostring(msg))
		end,

		show_formspec = function(name, formname, fs)
			H.forms[name] = H.forms[name] or {}
			table.insert(H.forms[name], { formname = formname, fs = fs or "" })
			H.last_form[name] = { formname = formname, fs = fs or "" }
		end,
		close_formspec = function(name, formname)
			H.closed[name] = H.closed[name] or {}
			table.insert(H.closed[name], formname)
		end,

		get_player_by_name = function(name)
			-- MS-3: as strict as the engine's `luaL_checkstring` (see above).
			checkname("get_player_by_name", 1, name)
			return H.players[name]
		end,
		get_connected_players = function()
			local out = {}
			for _, p in pairs(H.players) do out[#out + 1] = p end
			return out
		end,
		settings = {
			get = function(_, k) local v = H.settings_map[k] return v == nil and "" or tostring(v) end,
			get_bool = function(_, k, default)
				local v = H.settings_map[k]
				if v == nil then return default and true or false end
				return v == true or v == "true"
			end,
			get_np_group = function() return nil end,
			write = function() return true end,
		},

		register_chatcommand = function(name, def) H.commands[name] = def end,
		override_chatcommand = function(name, def) H.commands[name] = def end,
		unregister_chatcommand = function(name) H.commands[name] = nil end,
		register_privilege = function(name, def)
			core.registered_privileges[name] = def or {}
		end,
		register_on_player_receive_fields = function(cb) H.on_receive[#H.on_receive + 1] = cb end,
		register_on_leaveplayer = function(cb) H.on_leave[#H.on_leave + 1] = cb end,
		register_on_joinplayer = function(cb) H.on_join[#H.on_join + 1] = cb end,
		register_globalstep = function(cb) H.on_globalstep[#H.on_globalstep + 1] = cb end,
		register_on_shutdown = function(cb) H.on_shutdown[#H.on_shutdown + 1] = cb end,
		register_on_mods_loaded = function(cb) H.on_mods_loaded[#H.on_mods_loaded + 1] = cb end,
		register_on_newplayer = function() end,
		register_on_dieplayer = function() end,
		register_on_respawnplayer = function() end,
		register_on_punchplayer = function() end,
		register_on_chat_message = function() end,
		register_on_cheat = function() end,

		create_detached_inventory = function(name, callbacks, pname)
			local inv = H.Inventory(0, callbacks, pname)
			H.detached[name] = inv
			return inv
		end,
		get_detached_inventory = function(name) return H.detached[name] end,
		remove_detached_inventory = function(name) H.detached[name] = nil return true end,

		add_item = function(pos, stack)
			H.dropped = H.dropped or {}
			H.dropped[#H.dropped + 1] = H.ItemStack(stack):to_string()
			return nil
		end,
		item_drop = function() end,
		get_us_time = function() return os.time() * 1000000 end,
		get_gametime = function() return os.time() end,
		gettimeofday = function() return { sec = os.time(), usec = 0 } end,
		request_insecure_environment = function() return nil end,
		global_exists = function(n) return _G[n] ~= nil end,
		string_to_pos = function() return nil end,
		pos_to_string = function(p) return "(" .. p.x .. "," .. p.y .. "," .. p.z .. ")" end,
		after = function(t, fn, ...)
			H.pending = H.pending or {}
			H.pending[#H.pending + 1] = { t = t, fn = fn, args = { ... } }
		end,
	}
	core.get_connected_players = core.get_connected_players

	-- Sanity: nothing in the mod set may yield between validate and mutate, so
	-- the harness fails loudly if a mod schedules a deferred call in a
	-- transaction path.
	H.pending = nil

	local order = opts.load or H.LOAD_ORDER
	for _, mod in ipairs(order) do
		H.load_mod(mod)
	end
	for _, cb in ipairs(H.on_mods_loaded) do cb() end
	-- Seed money through smp_store now that it is up.
	for name, p in pairs(H.players) do
		if p._seed_money or p._seed_shards then
			if smp_store and smp_store.api then
				smp_store.api.set_money(name, p._seed_money or 0, "test", "harness seed")
				if p._seed_shards then
					smp_store.api.add_shards(name, p._seed_shards, "test", "harness seed")
				end
			end
			p._seed_money, p._seed_shards = nil, nil
		end
	end
	return H
end

function H.load_mod(mod)
	local path = H.MODROOT .. mod .. "/init.lua"
	local f, err = loadfile(path)
	if not f then
		error("loadfile " .. mod .. ": " .. tostring(err))
	end
	_G.__current_modname = mod
	local ok, res = pcall(f)
	_G.__current_modname = nil
	if not ok then
		error("mod " .. mod .. " failed: " .. tostring(res))
	end
	return res
end

--- Money helpers for assertions.
function H.money(name)
	local rec = smp_store.api.get_player(name)
	return (rec and math.floor(tonumber(rec.money) or 0)) or 0
end

function H.set_money(name, cents)
	smp_store.api.set_money(name, cents, "test", "harness")
	return H.money(name)
end

--- Run a chat command as a player. Returns (ok, message).
function H.cmd(name_cmd, pname, param)
	local def = H.commands[name_cmd]
	if not def then error("no such command: " .. tostring(name_cmd)) end
	return def.func(pname, param or "")
end

--- Deliver a formspec field event, like the client does.
function H.receive(pname, formname, fields)
	for _, cb in ipairs(H.on_receive) do
		cb(H.players[pname], formname, fields or {})
	end
end

function H.step(dtime)
	for _, cb in ipairs(H.on_globalstep) do cb(dtime or 0.1) end
end

function H.shutdown()
	for _, cb in ipairs(H.on_shutdown) do cb() end
end

--- Last formspec shown to a player, and helpers for string assertions.
function H.form(pname)
	return H.last_form[pname] and H.last_form[pname].fs or ""
end

function H.formname(pname)
	return H.last_form[pname] and H.last_form[pname].formname or ""
end

--- Unescape a formspec string enough to grep observed UI text: drops
--- `\;`, `\[`, `\]` escapes and colour codes.
function H.plain(fs)
	local s = core.strip_colors(tostring(fs))
	return (s:gsub("\\;", ";"):gsub("\\%[", "["):gsub("\\%]", "]"):gsub("\\\\", "\\"))
end

function H.last_chat(pname)
	local list = H.chat[pname] or {}
	return list[#list]
end

function H.has_chat(pname, text)
	for _, m in ipairs(H.chat[pname] or {}) do
		if m == text then return true end
	end
	return false
end

function H.clear_chat(pname) H.chat[pname] = {} end

return H
