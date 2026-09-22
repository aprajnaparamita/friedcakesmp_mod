-- FriedcakeSMP dev-test: smp_sell (f02-sell)
--
-- Standalone smoke test for the whole f02 acceptance matrix (f02 §9 T1-T10)
-- plus the pieces the matrix assumes: M0/M1 keys, the shulker codec, the
-- ledger, the statistics counter, history trimming, crash recovery and the
-- balance-cap refusal.
--
-- Run:  luajit friedcake/dev-tests/test_sell.lua
--
-- It stubs just enough of the engine (core.*, ItemStack, InvRef, detached
-- inventories, formspecs, players) for smp_core, smp_store, smp_economy and
-- smp_sell to load and run for real. Two fidelity notes:
--
--   * ItemStack:to_string() / ItemStack(itemstring) use the engine's
--     "name [count [wear [meta]]]" shape (src/inventory.cpp
--     ItemStack::serialize) with the metadata rendered by this file's own
--     serializer instead of the C++ one. The shulker codec round-trips
--     through exactly those two functions, so the codec logic is exercised.
--   * core.compress / core.decompress are stand-ins (a length prefix rather
--     than zstd) so the "compressed" branch of the shulker meta is covered
--     on a host without zstd.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local REPO = "/Volumes/Dara/dev/coconut"
local MODS = REPO .. "/friedcake/mods/"

local failures = {}
local function check(cond, msg)
	if not cond then
		failures[#failures + 1] = msg
		print("  FAIL: " .. msg)
	else
		print("  ok:   " .. msg)
	end
end
local function eq(got, want, msg)
	check(got == want, string.format("%s (got %s, want %s)",
		msg, tostring(got), tostring(want)))
end

----------------------------------------------------------------------
-- serialize / deserialize (stands in for core.serialize)
----------------------------------------------------------------------

local function ser(v)
	local t = type(v)
	if v == nil then return "nil" end
	if t == "boolean" then return tostring(v) end
	if t == "number" then
		if v ~= v then return "(0/0)" end
		if v == math.huge then return "(1/0)" end
		if v == -math.huge then return "(-1/0)" end
		return string.format("%.17g", v)
	end
	if t == "string" then
		return string.format("%q", v)
	end
	if t == "table" then
		local parts = {}
		local n = 0
		for k in pairs(v) do
			if type(k) == "number" then n = math.max(n, k) end
		end
		for i = 1, n do
			if v[i] ~= nil then parts[#parts + 1] = ser(v[i]) end
		end
		for k, vv in pairs(v) do
			if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
				parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(vv)
			end
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "nil"
end

local function deser(s)
	if type(s) ~= "string" or s == "" then return nil end
	local f, err = loadstring("return " .. s)
	if not f then return nil, err end
	local ok, v = pcall(f)
	if not ok then return nil, v end
	return v
end

----------------------------------------------------------------------
-- JSON (same minimal pair the other dev-tests use)
----------------------------------------------------------------------

local function json_encode(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number" then
		if v == math.floor(v) then return string.format("%.0f", v) end
		return tostring(v)
	end
	if t == "string" then
		return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
	end
	if t == "table" then
		local n = 0
		for k in pairs(v) do
			if type(k) ~= "number" then n = -1 break end
			if k > n then n = k end
		end
		if n == -1 then
			local p = {}
			for k, vv in pairs(v) do
				p[#p + 1] = string.format('"%s":%s', tostring(k), json_encode(vv))
			end
			return "{" .. table.concat(p, ",") .. "}"
		end
		local p = {}
		for i = 1, n do p[#p + 1] = json_encode(v[i]) end
		return "[" .. table.concat(p, ",") .. "]"
	end
	return "null"
end

local function skip_ws(s, i)
	while i <= #s do
		local c = s:sub(i, i)
		if c == " " or c == "\t" or c == "\n" or c == "\r" then i = i + 1 else break end
	end
	return i
end

local function parse_str(s, i)
	local out, j = "", i + 1
	while j <= #s do
		local c = s:sub(j, j)
		if c == '"' then return out, j + 1 end
		if c == '\\' then
			local nc = s:sub(j + 1, j + 1)
			if nc == 'n' then out = out .. "\n"
			elseif nc == 't' then out = out .. "\t"
			else out = out .. nc end
			j = j + 2
		else
			out = out .. c
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
		if s:sub(i, i) == '}' then return t, i + 1 end
		local k
		k, i = parse_str(s, i)
		i = skip_ws(s, i)
		i = skip_ws(s, i + 1)   -- skip ':'
		local v
		v, i = parse_val(s, i)
		t[k] = v
		i = skip_ws(s, i)
		if s:sub(i, i) == ',' then i = i + 1 end
	end
end

local function parse_arr(s, i)
	local t, idx = {}, 1
	i = i + 1
	while true do
		i = skip_ws(s, i)
		if s:sub(i, i) == ']' then return t, i + 1 end
		local v
		v, i = parse_val(s, i)
		t[idx] = v
		idx = idx + 1
		i = skip_ws(s, i)
		if s:sub(i, i) == ',' then i = i + 1 end
	end
end

function parse_val(s, i)
	i = skip_ws(s, i)
	local c = s:sub(i, i)
	if c == '"' then return parse_str(s, i) end
	if c == '{' then return parse_obj(s, i) end
	if c == '[' then return parse_arr(s, i) end
	local j = i
	while j <= #s and s:sub(j, j):match('[%-%d%.eE%+a-zA-Z]') do j = j + 1 end
	local tok = s:sub(i, j - 1)
	if tok == "true" then return true, j end
	if tok == "false" then return false, j end
	if tok == "null" then return nil, j end
	return tonumber(tok), j
end

local function json_decode(s)
	if not s or s == "" then return nil end
	local v = parse_val(s, 1)
	return v
end

----------------------------------------------------------------------
-- base64 (for the shulker "compressed" branch) and fake zstd
----------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64encode(data)
	return (data:gsub("...", function(cc)
		local a, b, c = cc:byte(1, 3)
		b = b or 0
		c = c or 0
		local n = a * 65536 + b * 256 + c
		local o = ""
		for shift = 18, 0, -6 do
			local idx = math.floor(n / 2 ^ shift) % 64 + 1
			o = o .. B64:sub(idx, idx)
		end
		return o
	end) .. string.rep("=", (3 - #data % 3) % 3))
end
local function b64decode(data)
	data = data:gsub("=", "")
	local out = {}
	for i = 1, #data, 4 do
		local chunk = data:sub(i, i + 3)
		local n = 0
		for k = 1, #chunk do
			local idx = B64:find(chunk:sub(k, k), 1, true)
			if not idx then break end
			n = n * 64 + (idx - 1)
		end
		local bytes = {}
		for shift = 16, 0, -8 do
			bytes[#bytes + 1] = string.char(math.floor(n / 2 ^ shift) % 256)
		end
		-- Only emit the bytes the chunk actually carried.
		local keep = math.floor(#chunk * 6 / 8)
		for k = 1, keep do out[#out + 1] = bytes[k] end
	end
	return table.concat(out)
end

----------------------------------------------------------------------
-- ItemStack stub
----------------------------------------------------------------------

local registered_items = {}
local registered_aliases = {}

local MetaRef = {}
MetaRef.__index = MetaRef
local function new_meta(fields)
	return setmetatable({ _fields = fields or {} }, MetaRef)
end
function MetaRef:get_string(k)
	local v = self._fields[k]
	return v == nil and "" or tostring(v)
end
function MetaRef:set_string(k, v)
	if v == nil or v == "" then self._fields[k] = nil else self._fields[k] = tostring(v) end
end
function MetaRef:to_table()
	local copy = {}
	for k, v in pairs(self._fields) do copy[k] = v end
	return { fields = copy }
end
function MetaRef:from_table(t)
	self._fields = {}
	for k, v in pairs((t or {}).fields or {}) do self._fields[k] = v end
end
function MetaRef:equals(other)
	return self:to_string() == other:to_string()
end

local Stack = {}
Stack.__index = Stack

local function stack_max(name)
	local def = registered_items[name]
	return (def and def.stack_max) or 64
end

local function parse_itemstring(s)
	local name, count, wear, meta = "", 0, 0, {}
	if type(s) ~= "string" or s == "" then return name, count, wear, meta end
	local rest = s
	name, rest = rest:match("^(%S+)%s*(.*)$")
	if not name then return "", 0, 0, {} end
	count = 1
	local c, r2 = rest:match("^(%-?%d+)%s*(.*)$")
	if c then
		count = tonumber(c)
		rest = r2
		local w, r3 = rest:match("^(%-?%d+)%s*(.*)$")
		if w then
			wear = tonumber(w)
			rest = r3
		end
	end
	rest = rest:match("^%s*(.*)$") or ""
	if rest ~= "" then
		local t = deser(rest)
		if type(t) == "table" then meta = t end
	end
	return name, count, wear, meta
end

local function make_stack(x)
	local self = setmetatable({
		_name = "", _count = 0, _wear = 0, _meta = new_meta(),
	}, Stack)
	self:replace(x)
	return self
end

function Stack:replace(x)
	self._name, self._count, self._wear = "", 0, 0
	self._meta = new_meta()
	if x == nil then return self end
	if type(x) == "string" then
		local name, count, wear, meta = parse_itemstring(x)
		name = registered_aliases[name] or name
		self._name, self._count, self._wear = name, count, wear
		self._meta = new_meta(meta)
	elseif type(x) == "table" and getmetatable(x) == Stack then
		self._name, self._count, self._wear = x._name, x._count, x._wear
		self._meta = new_meta(x._meta._fields)
	elseif type(x) == "table" then
		self._name = x.name or ""
		self._count = x.count or 1
		self._wear = x.wear or 0
		self._meta = new_meta(x.metadata and x.metadata.fields or {})
	end
	if self._name == "" then self._count = 0 end
	if self._count < 0 then self._count = 0 end
	return self
end

function Stack:is_empty() return self._count == 0 end
function Stack:get_count() return self._count end
function Stack:set_count(n) self._count = math.floor(tonumber(n) or 0); if self._count <= 0 then self._name = "" end; return self end
function Stack:take_item(n)
	n = math.floor(tonumber(n) or 1)
	self._count = math.max(0, self._count - n)
	if self._count == 0 then self._name, self._wear, self._meta = "", 0, new_meta() end
	return self
end
function Stack:get_name() return self._name end
function Stack:set_name(n) self._name = n; return self end
function Stack:get_wear() return self._wear end
function Stack:set_wear(w) self._wear = math.floor(tonumber(w) or 0); return self end
function Stack:get_meta() return self._meta end
function Stack:get_stack_max() return stack_max(self._name) end
function Stack:get_free_space() return math.max(0, self:get_stack_max() - self._count) end
function Stack:is_known() return registered_items[self._name] ~= nil end
function Stack:get_definition() return registered_items[self._name] or {} end
function Stack:get_description()
	local d = self._meta:get_string("description")
	if d ~= "" then return d end
	local def = registered_items[self._name]
	return (def and def.description) or self._name
end
function Stack:get_short_description()
	local d = self._meta:get_string("short_description")
	if d ~= "" then return d end
	local def = registered_items[self._name]
	if def and def.short_description then return def.short_description end
	return self:get_description()
end
function Stack:to_string()
	if self:is_empty() then return "" end
	local fields = self._meta._fields
	local has_meta = next(fields) ~= nil
	local parts = { self._name }
	if has_meta or self._count ~= 1 or self._wear ~= 0 then parts[#parts + 1] = self._count end
	if has_meta or self._wear ~= 0 then parts[#parts + 1] = self._wear end
	if has_meta then parts[#parts + 1] = ser(fields) end
	return table.concat(parts, " ")
end
function Stack:to_table()
	return {
		name = self._name, count = self._count, wear = self._wear,
		metadata = self._meta:to_table(),
	}
end
function Stack:equals(other) return self:to_string() == other:to_string() end
function Stack:clear() self._name, self._count, self._wear = "", 0, 0; self._meta = new_meta(); return self end
function Stack:add_item(n) self._count = self._count + math.floor(n or 1); return self end

function ItemStack(x)
	if getmetatable(x) == Stack then return make_stack(x) end
	return make_stack(x)
end

----------------------------------------------------------------------
-- InvRef stub
----------------------------------------------------------------------

local Inv = {}
Inv.__index = Inv
local function new_inv()
	return setmetatable({ _lists = {} }, Inv)
end
function Inv:set_size(list, n)
	self._lists[list] = self._lists[list] or {}
	local l = self._lists[list]
	for i = #l + 1, n do l[i] = ItemStack("") end
	for i = n + 1, #l do l[i] = nil end
	return true
end
function Inv:get_size(list) return #(self._lists[list] or {}) end
function Inv:get_stack(list, i)
	local l = self._lists[list]
	if not l or not l[i] then return ItemStack("") end
	return ItemStack(l[i])
end
function Inv:set_stack(list, i, stack)
	local l = self._lists[list]
	if not l then return false end
	l[i] = ItemStack(stack)
	return true
end
function Inv:get_list(list)
	local l = self._lists[list] or {}
	local out = {}
	for i = 1, #l do out[i] = ItemStack(l[i]) end
	return out
end
function Inv:set_list(list, stacks)
	local l = {}
	local size = self:get_size(list)
	for i = 1, size do
		l[i] = ItemStack(stacks and stacks[i] or "")
	end
	self._lists[list] = l
end
function Inv:is_empty(list)
	for _, s in ipairs(self._lists[list] or {}) do
		if not s:is_empty() then return false end
	end
	return true
end
-- Engine semantics: identical stacks merge up to stack_max, then empty slots.
function Inv:add_item(list, stack)
	local left = ItemStack(stack)
	if left:is_empty() then return left end
	local l = self._lists[list]
	if not l then return left end
	for i = 1, #l do
		if left:is_empty() then break end
		local cur = l[i]
		if not cur:is_empty() and cur:to_string() == left:to_string() then
			local room = cur:get_stack_max() - cur:get_count()
			if room > 0 then
				local move = math.min(room, left:get_count())
				cur:set_count(cur:get_count() + move)
				left:take_item(move)
			end
		end
	end
	for i = 1, #l do
		if left:is_empty() then break end
		if l[i]:is_empty() then
			local move = math.min(left:get_count(), left:get_stack_max())
			l[i] = ItemStack(left)
			l[i]:set_count(move)
			left:take_item(move)
		end
	end
	return left
end
function Inv:room_for_item(list, stack)
	local probe = new_inv()
	probe._lists[list] = {}
	for i = 1, self:get_size(list) do probe._lists[list][i] = ItemStack(self._lists[list][i]) end
	return probe:add_item(list, stack):is_empty()
end
function Inv:contains_item(list, stack)
	local need = stack:get_count()
	for _, s in ipairs(self._lists[list] or {}) do
		if not s:is_empty() and s:to_string() == stack:to_string() then
			need = need - s:get_count()
		end
	end
	return need <= 0
end

----------------------------------------------------------------------
-- Players, drops, formspecs
----------------------------------------------------------------------

local players = {}
local dropped = {}          -- items that hit the ground
local shown_formspecs = {}  -- [player] = { formname, formspec }
local closed_formspecs = {}

local function make_player(name)
	local inv = new_inv()
	inv:set_size("main", 36)
	local p = {
		_name = name,
		_inv = inv,
		_pos = { x = 1, y = 2, z = 3 },
		_wield = 1,
	}
	function p:get_player_name() return self._name end
	function p:get_inventory() return self._inv end
	function p:get_pos() return self._pos end
	function p:get_wield_index() return self._wield end
	function p:get_wielded_item() return self._inv:get_stack("main", self._wield) end
	function p:set_wield_index(i) self._wield = i end
	players[name] = p
	return p
end

----------------------------------------------------------------------
-- Handler registries
----------------------------------------------------------------------

local handlers = {
	fields = {}, leave = {}, die = {}, join = {}, shutdown = {},
	mods_loaded = {}, globalstep = {}, chatcommand = {},
}
local commands = {}
local privileges = {}
local detached = {}

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------

local SETTINGS = {
	["store.backend"] = "mod_storage",
	["store.flush_interval"] = "10",
	["store.max_balance"] = "1000000000000000",
	["economy.max_balance"] = "1000000000000000",
	["sell.mode"] = "button",
	["sell.multiplier"] = "1.0",
	["sell.history_size"] = "100",
	["mcl_chests_serialize_uncompressed"] = "true",
}

----------------------------------------------------------------------
-- core stub
----------------------------------------------------------------------

local storages = {}
local function mod_storage_for(name)
	storages[name] = storages[name] or {}
	local data = storages[name]
	return {
		get_string = function(_, k) return data[k] or "" end,
		set_string = function(_, k, v)
			if v == "" or v == nil then data[k] = nil else data[k] = v end
		end,
		get_keys = function(_)
			local out = {}
			for k in pairs(data) do out[#out + 1] = k end
			table.sort(out)
			return out
		end,
	}
end

_G.__current_modname = nil

core = {
	DIR_DELIM = "/",
	registered_items = registered_items,
	registered_nodes = registered_items,
	registered_craftitems = registered_items,
	registered_aliases = registered_aliases,
	registered_chatcommands = commands,
	registered_privileges = privileges,

	get_current_modname = function() return _G.__current_modname or "test" end,
	get_modpath = function(m) return MODS .. m end,
	get_worldpath = function() return "/tmp/smp_sell_devtest_world" end,
	get_mod_storage = function() return mod_storage_for(_G.__current_modname or "test") end,

	get_translator = function(_)
		return function(s, ...)
			local args = { ... }
			return (s:gsub("@(%d+)", function(n)
				return tostring(args[tonumber(n)] or "")
			end))
		end
	end,
	get_translated = function(_, _, s) return s end,
	-- Identity on purpose: the T1 assertion checks the exact label element.
	colorize = function(_, text) return text end,
	formspec_escape = function(s) return (tostring(s):gsub("[%[%];,\\]", "\\%1")) end,
	strip_colors = function(s) return s end,

	log = function(level, msg)
		if level == "error" or level == "warning" then
			print(string.format("  [%s] %s", level, tostring(msg)))
		end
	end,
	chat_send_player = function(name, msg)
		_G.__chat = _G.__chat or {}
		_G.__chat[#_G.__chat + 1] = { name = name, msg = msg }
	end,

	serialize = ser,
	deserialize = deser,
	write_json = json_encode,
	parse_json = json_decode,
	safe_file_write = function(_, content) return true end,

	compress = function(data, method) return "ZSTD1" .. data end,
	decompress = function(data, method)
		if type(data) ~= "string" or data:sub(1, 5) ~= "ZSTD1" then return nil end
		return data:sub(6)
	end,
	encode_base64 = b64encode,
	decode_base64 = b64decode,

	settings = {
		get = function(_, k) return SETTINGS[k] or "" end,
		get_bool = function(_, k, default)
			local v = SETTINGS[k]
			if v == nil or v == "" then return default end
			return v == "true" or v == "1"
		end,
		get_np_group = function() return nil end,
		write = function() return true end,
	},

	request_insecure_environment = function() return nil end,

	register_chatcommand = function(name, def) commands[name] = def end,
	register_craftitem = function(name, def)
		def = def or {}
		def.name = name
		registered_items[name] = def
	end,
	register_node = function(name, def)
		def = def or {}
		def.name = name
		registered_items[name] = def
	end,
	register_tool = function(name, def)
		def = def or {}
		def.name = name
		registered_items[name] = def
	end,
	register_craft = function() end,
	register_alias = function(a, b) registered_aliases[a] = b end,
	check_player_privs = function() return true end,
	pos_to_string = function(p) return string.format("(%g,%g,%g)", p.x, p.y, p.z) end,
	override_chatcommand = function(name, redef)
		local cur = commands[name]
		if not cur then return end
		for k, v in pairs(redef) do cur[k] = v end
	end,
	unregister_chatcommand = function(name) commands[name] = nil end,
	register_privilege = function(name, def) privileges[name] = def end,

	register_on_player_receive_fields = function(f) handlers.fields[#handlers.fields + 1] = f end,
	register_on_leaveplayer = function(f) handlers.leave[#handlers.leave + 1] = f end,
	register_on_dieplayer = function(f) handlers.die[#handlers.die + 1] = f end,
	register_on_joinplayer = function(f) handlers.join[#handlers.join + 1] = f end,
	register_on_shutdown = function(f) handlers.shutdown[#handlers.shutdown + 1] = f end,
	register_on_mods_loaded = function(f) handlers.mods_loaded[#handlers.mods_loaded + 1] = f end,
	register_on_globalstep = function(f) handlers.globalstep[#handlers.globalstep + 1] = f end,
	register_on_chatcommand = function(f) handlers.chatcommand[#handlers.chatcommand + 1] = f end,
	register_on_punchplayer = function() end,
	register_on_respawnplayer = function() end,
	register_on_dignode = function() end,
	register_on_placenode = function() end,

	get_player_by_name = function(name) return players[name] end,
	get_connected_players = function()
		local out = {}
		for _, p in pairs(players) do out[#out + 1] = p end
		return out
	end,
	get_player_names = function()
		local out = {}
		for n in pairs(players) do out[#out + 1] = n end
		return out
	end,
	get_gametime = function() return 0 end,
	get_item_group = function(name, group)
		local def = registered_items[name]
		return (def and def.groups and def.groups[group]) or 0
	end,
	get_node = function() return { name = "air" } end,

	show_formspec = function(name, formname, formspec)
		shown_formspecs[name] = { formname = formname, formspec = formspec }
		return true
	end,
	close_formspec = function(name, formname)
		closed_formspecs[name] = formname
		return true
	end,

	create_detached_inventory = function(name, callbacks, player_name)
		local inv = new_inv()
		detached[name] = { inv = inv, callbacks = callbacks or {}, owner = player_name }
		return inv
	end,
	remove_detached_inventory = function(name)
		local had = detached[name] ~= nil
		detached[name] = nil
		return had
	end,
	get_inventory = function(loc)
		if type(loc) ~= "table" then return nil end
		if loc.type == "detached" then
			local d = detached[loc.name]
			return d and d.inv or nil
		end
		if loc.type == "player" then
			local p = players[loc.name]
			return p and p._inv or nil
		end
		return nil
	end,

	item_drop = function(stack, dropper, pos)
		if not stack or stack:is_empty() then return ItemStack(""), nil end
		dropped[#dropped + 1] = {
			stack = ItemStack(stack),
			pos = pos,
			who = dropper and dropper.get_player_name and dropper:get_player_name() or nil,
		}
		stack:clear()
		return ItemStack(""), nil
	end,
	add_item = function(pos, stack)
		dropped[#dropped + 1] = { stack = ItemStack(stack), pos = pos, who = nil }
		return nil
	end,
}

-- mcl_formspec: present in Mineclonia, and menu.lua uses it when available.
mcl_formspec = {
	label_color = "#313131",
	itemslot_border_size = 0.05,
	get_itemslot_bg_v4 = function(x, y, w, h, size, texture)
		size = size or 0.05
		local out = {}
		for i = 0, w - 1 do
			for j = 0, h - 1 do
				out[#out + 1] = string.format("image[%g,%g;1.1,1.1;%s]",
					x + i + i * 0.25 - size, y + j + j * 0.25 - size,
					texture or "mcl_formspec_itemslot.png")
			end
		end
		return table.concat(out)
	end,
}

----------------------------------------------------------------------
-- A tiny fake Mineclonia: registered items, groups, aliases
----------------------------------------------------------------------

local function reg(name, def)
	registered_items[name] = def or {}
	registered_items[name].name = name
	registered_items[name].description = (def or {}).description or name
end

reg("mcl_mobitems:bone", { description = "Bone", stack_max = 64 })
reg("mcl_core:cobble", { description = "Cobblestone", stack_max = 99 })
reg("mcl_core:diamond", { description = "Diamond", stack_max = 64 })
reg("mcl_tools:pick_diamond", { description = "Diamond Pickaxe", stack_max = 1 })
reg("mcl_core:stone", { description = "Stone", stack_max = 99 })
reg("mcl_throwing:ender_pearl", { description = "Ender Pearl", stack_max = 16 })
reg("mcl_totems:totem", { description = "Totem of Undying", stack_max = 64 })
reg("mcl_amethyst:amethyst_shard", { description = "Amethyst Shard", stack_max = 64 })
reg("mcl_panes:pane_lime_flat", { description = "Lime Glass Pane", stack_max = 64 })
reg("mcl_dyes:green", { description = "Lime Dye", stack_max = 64 })
reg("mcl_core:glass", { description = "Glass", stack_max = 64 })
reg("smp_test:junk", { description = "Junk", stack_max = 64 })   -- never priced
reg("mcl_chests:chest", { description = "Chest", stack_max = 16 })
for _, colour in ipairs({ "violet", "white", "black" }) do
	reg("mcl_chests:" .. colour .. "_shulker_box",
		{ description = "Shulker Box", stack_max = 1, groups = { shulker_box = 1 } })
	reg("mcl_chests:" .. colour .. "_shulker_box_small",
		{ description = "Shulker Box", stack_max = 1, groups = { shulker_box = 1 } })
end
registered_aliases["mcl_walls:cobble"] = "mcl_walls:cobble_short_pillar"
reg("mcl_walls:cobble_short_pillar", { description = "Cobblestone Wall", stack_max = 99 })
registered_aliases["mcl_core:wood"] = "mcl_trees:wood_oak"
reg("mcl_trees:wood_oak", { description = "Oak Wood", stack_max = 64 })

----------------------------------------------------------------------
-- Load the mods in dependency order
----------------------------------------------------------------------

local function load(mod)
	_G.__current_modname = mod
	local f, err = loadfile(MODS .. mod .. "/init.lua")
	assert(f, "loadfile " .. mod .. ": " .. tostring(err))
	local ok, e = pcall(f)
	_G.__current_modname = nil
	if not ok then error("loading " .. mod .. ": " .. tostring(e)) end
end

load("smp_admin")
load("smp_core")
load("smp_store")
load("smp_economy")
load("smp_sell")

print("mods loaded; prices = " .. smp_sell.prices.count()
	.. ", mode = " .. smp_sell.cfg.mode
	.. ", multiplier = " .. tostring(smp_sell.cfg.multiplier))

----------------------------------------------------------------------
-- Test helpers
----------------------------------------------------------------------

local function money(name)
	local r = smp_store.api.get_player(name)
	return r and r.money or 0
end

local function set_money(name, cents)
	smp_store.api.set_money(name, cents, "test", "seed")
end

local function set_stat(name, key, value)
	local rec = smp_store.api.ensure_player(name)
	rec.stats = type(rec.stats) == "table" and rec.stats or {}
	rec.stats[key] = value
	smp_store.api.upsert_player(rec)
end

local function stat(name, key)
	local rec = smp_store.api.get_player(name)
	return rec and rec.stats and rec.stats[key] or 0
end

local function count_inventory(p)
	local n, kinds = 0, {}
	for i = 1, p._inv:get_size("main") do
		local s = p._inv:get_stack("main", i)
		if not s:is_empty() then
			n = n + s:get_count()
			kinds[s:get_name()] = (kinds[s:get_name()] or 0) + s:get_count()
		end
	end
	return n, kinds
end

local function put_in_container(player_name, stack, index)
	-- Mimic the engine's put path so the detached-inventory callbacks
	-- (owner check, slot bound, persistence) are exercised for real.
	local d = detached[smp_sell.menu.inv_name(player_name)]
	assert(d, "no detached inventory for " .. player_name)
	local inv, cb = d.inv, d.callbacks
	if cb.allow_put then
		local p = players[player_name]
		local allowed = cb.allow_put(inv, "main", index, stack, p)
		if allowed <= 0 then return false end
		stack = ItemStack(stack)
		stack:set_count(math.min(allowed, stack:get_count()))
	end
	inv:set_stack("main", index, stack)
	if cb.on_put then cb.on_put(inv, "main", index, stack, players[player_name]) end
	return true
end

local function take_from_container(player_name, index)
	local d = detached[smp_sell.menu.inv_name(player_name)]
	if not d then return ItemStack("") end
	local inv, cb = d.inv, d.callbacks
	local stack = inv:get_stack("main", index)
	if cb.allow_take then
		local allowed = cb.allow_take(inv, "main", index, stack, players[player_name])
		if allowed <= 0 then return ItemStack("") end
	end
	inv:set_stack("main", index, ItemStack(""))
	if cb.on_take then cb.on_take(inv, "main", index, stack, players[player_name]) end
	return stack
end

local function container_contents(player_name)
	local inv = smp_sell.menu.get_inv(player_name)
	local out = {}
	if not inv then return out end
	for i = 1, inv:get_size("main") do
		local s = inv:get_stack("main", i)
		if not s:is_empty() then out[#out + 1] = s end
	end
	return out
end

local function fire_fields(player_name, formname, fields)
	for _, f in ipairs(handlers.fields) do
		f(players[player_name], formname, fields)
	end
end

local function fire_leave(player_name)
	for _, f in ipairs(handlers.leave) do f(players[player_name], false) end
end

local function drain_chat()
	local out = _G.__chat or {}
	_G.__chat = {}
	local lines = {}
	for _, c in ipairs(out) do lines[#lines + 1] = c.msg end
	return lines
end

local function open_sell(player_name)
	local ok = commands.sell.func(player_name, "")
	drain_chat()
	return ok
end

local function confirm(player_name)
	fire_fields(player_name, smp_sell.menu.FORMNAME, { confirm = "" })
	return drain_chat()
end

local function quit_menu(player_name)
	fire_fields(player_name, smp_sell.menu.FORMNAME, { quit = "true" })
	return drain_chat()
end

-- A shulker box carrying the given contents (list of ItemStacks).
local function shulker(colour, contents)
	local box = ItemStack("mcl_chests:" .. (colour or "violet") .. "_shulker_box")
	local list = {}
	for i = 1, smp_sell.items.SHULKER_SLOTS do list[i] = ItemStack("") end
	for i, s in ipairs(contents or {}) do list[i] = ItemStack(s) end
	smp_sell.items.encode_contents(box, list)
	return box
end

local function shulker_contents(box)
	local out = {}
	for _, s in ipairs(smp_sell.items.decode_contents(box)) do
		if not s:is_empty() then out[#out + 1] = s end
	end
	return out
end

----------------------------------------------------------------------
-- Item keys, plainness and the shulker codec
----------------------------------------------------------------------

print("\n== M0/M1 keys, plainness, shulker codec ==")

do
	local items = smp_sell.items
	local plain = ItemStack("mcl_mobitems:bone 64")
	local enchanted = ItemStack("mcl_tools:pick_diamond")
	enchanted:get_meta():set_string("mcl_enchanting:enchantments",
		ser({ unbreaking = 3, mending = 1 }))
	local worn = ItemStack("mcl_tools:pick_diamond 1 1234")
	local named = ItemStack("mcl_core:diamond")
	named:get_meta():set_string("name", "Lucky Stone")
	local metaled = ItemStack("mcl_core:diamond")
	metaled:get_meta():set_string("some_mod:tracked", "7")

	eq(items.key_m0(plain), "mcl_mobitems:bone", "M0 key of a plain stack is the resolved name")
	eq(select(2, items.is_plain(enchanted)), "enchanted", "enchanted stack is not plain")
	eq(select(2, items.is_plain(worn)), "worn", "worn stack is not plain")
	eq(select(2, items.is_plain(named)), "named", "renamed stack is not plain")
	eq(select(2, items.is_plain(metaled)), "metadata", "extra metadata is not plain")
	eq(items.key_m0(enchanted), nil, "enchanted stack has no M0 key")
	eq(items.key_m1(enchanted),
		"mcl_tools:pick_diamond|mending:1,unbreaking:3|" .. items.digest(""),
		"M1 key carries sorted enchantments")
	eq(items.key_m1(worn), nil, "worn stack has no M1 key")
	eq(items.key_m1(named), nil, "renamed stack has no M1 key")
	check(items.key_m1(plain) == items.plain_m1("mcl_mobitems:bone"),
		"M1 key of a plain stack equals plain_m1(name)")

	-- Aliases resolve to the registered name.
	eq(items.resolve_name("mcl_walls:cobble"), "mcl_walls:cobble_short_pillar",
		"alias resolution (mcl_walls:cobble)")
	eq(ItemStack("mcl_core:wood"):get_name(), "mcl_trees:wood_oak",
		"alias resolution (mcl_core:wood)")
	eq(smp_sell.base_price("mcl_walls:cobble"), 700,
		"base price is reachable through an alias (cobblestone wall = 7 [S2])")
	eq(smp_sell.base_price("mcl_core:cobble"), 600,
		"cobblestone base price = 6 [S2]")
	eq(smp_sell.base_price("mcl_mobitems:bone"), 1000,
		"bone base price = $10.00 (f02 §5 example)")

	-- Amethyst timer metadata is exempt (sell.meta_exempt, f02 §4.1 [S9]).
	local amethyst = ItemStack("mcl_amethyst:amethyst_shard 4")
	amethyst:get_meta():set_string("smp:expires_at", tostring(os.time() + 3600))
	eq(select(1, items.is_plain(amethyst, {
		meta_exempt = smp_sell.cfg.meta_exempt_keys,
		item_exempt = smp_sell.cfg.meta_exempt_items,
	})), true, "amethyst item with an expiry timer is still sellable")

	-- Shulker codec round-trip.
	local box = shulker("violet", {
		ItemStack("mcl_mobitems:bone 64"),
		ItemStack("mcl_core:diamond 7"),
	})
	local decoded = shulker_contents(box)
	eq(#decoded, 2, "shulker round-trip keeps the stack count")
	eq(decoded[1]:get_name(), "mcl_mobitems:bone", "shulker round-trip keeps the item")
	eq(decoded[1]:get_count(), 64, "shulker round-trip keeps the count")
	check(box:get_meta():get_string("compressed") ~= "",
		"shulker meta carries the compressed contents")
	-- Emptying a box restores its pristine (metadata-free) form.
	smp_sell.items.encode_contents(box, {})
	eq(#shulker_contents(box), 0, "re-encoding an empty box decodes to nothing")
	eq(box:get_meta():get_string("compressed"), "",
		"an empty box loses its contents metadata")
	eq(box:to_string(), "mcl_chests:violet_shulker_box",
		"an emptied box is byte-identical to a fresh one")
	-- The uncompressed fallback key is honoured too.
	local box2 = ItemStack("mcl_chests:white_shulker_box")
	box2:get_meta():set_string("", ser({ "mcl_core:diamond 3" }))
	eq(#shulker_contents(box2), 1, "contents decode from the uncompressed key")
	eq(shulker_contents(box2)[1]:get_count(), 3, "uncompressed contents keep counts")
end

----------------------------------------------------------------------
-- T1: /sell opens a container titled exactly `Sell`
----------------------------------------------------------------------

print("\n== T1: the observed Sell container ==")

local alice = make_player("alice")
set_money("alice", 0)

do
	check(commands.sell ~= nil, "/sell is registered")
	check(commands.sellhistory ~= nil, "/sellhistory is registered")
	check(commands.worth ~= nil, "/worth is registered")

	open_sell("alice")
	local shown = shown_formspecs["alice"]
	check(shown ~= nil, "T1 /sell shows a formspec")
	eq(shown.formname, "smp_sell:sell", "T1 formname is smp_sell:sell")
	local fs = shown.formspec
	check(fs:find("formspec_version[6]", 1, true) ~= nil, "T1 formspec version 6")
	check(fs:find("label[0.375,0.375;Sell]", 1, true) ~= nil,
		"T1 the container is titled exactly `Sell` [F0093]")
	check(fs:find("size[11.75,12.925]", 1, true) ~= nil,
		"T1 container-menu geometry matches Mineclonia chests")
	check(fs:find("list[detached:smp_sell_alice;main;0.375,0.75;9,5;]", 1, true) ~= nil,
		"T1 a 9x5 detached sell grid over the player inventory")
	check(fs:find("label[0.375,7.2;Inventory]", 1, true) ~= nil,
		"T1 the `Inventory` section label [F0093]")
	check(fs:find("list[current_player;main;0.375,7.6;9,3;9]", 1, true) ~= nil
		and fs:find("list[current_player;main;0.375,11.55;9,1;]", 1, true) ~= nil,
		"T1 the player inventory is shown as 4x9")
	check(fs:find("item_image_button[10.375,5.75;1,1;mcl_panes:pane_lime_flat;confirm;]",
		1, true) ~= nil,
		"T1 the lime confirm pane sits in the bottom-right cell of the grid [F0094]")
	check(fs:find("tooltip[confirm;Confirm\\nClick to sell items]", 1, true) ~= nil,
		"T1 the confirm tooltip follows the shared §4.3 two-line idiom")
	check(fs:find("listring[detached:smp_sell_alice;main]", 1, true) ~= nil,
		"T1 shift-click rings between the grid and the inventory")
	eq(smp_sell.menu.slot_count(), 44,
		"T1 44 drop slots: the 45th cell belongs to the confirm pane")

	-- R5: the detached inventory only accepts the owner's moves.
	local d = detached["smp_sell_alice"]
	check(d ~= nil and d.owner == "alice", "the detached inventory is owner-scoped")
	local bob = make_player("bob")
	local allowed = d.callbacks.allow_put(d.inv, "main", 1,
		ItemStack("mcl_mobitems:bone 1"), bob)
	eq(allowed, 0, "R5 another player cannot put items into alice's sell grid")
	allowed = d.callbacks.allow_take(d.inv, "main", 1, ItemStack("mcl_mobitems:bone 1"), bob)
	eq(allowed, 0, "R5 another player cannot take from alice's sell grid")
	allowed = d.callbacks.allow_move(d.inv, "main", 1, "main", 2, 1, bob)
	eq(allowed, 0, "R5 another player cannot move items inside alice's sell grid")
	allowed = d.callbacks.allow_put(d.inv, "main", 45, ItemStack("mcl_mobitems:bone 1"), alice)
	eq(allowed, 0, "the confirm cell is not a drop slot")
	allowed = d.callbacks.allow_put(d.inv, "main", 44, ItemStack("mcl_mobitems:bone 1"), alice)
	eq(allowed, 1, "the owner may put one item into a drop slot")
	players["bob"] = nil
end

----------------------------------------------------------------------
-- T2: nothing is sold until the confirm control is clicked
----------------------------------------------------------------------

print("\n== T2: confirm-gated selling ==")

do
	set_money("alice", 0)
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 64"), 1)
	eq(money("alice"), 0, "T2 dropping items does not sell them")
	eq(#container_contents("alice"), 1, "T2 the items are still in the container")

	fire_fields("alice", smp_sell.menu.FORMNAME, {})   -- an unrelated field
	eq(money("alice"), 0, "T2 an unrelated field does not sell anything")

	local msgs = confirm("alice")
	eq(money("alice"), 64 * 1000, "T2 confirming sells at the base price (64 bones = $64)")
	eq(#container_contents("alice"), 0, "T2 the container is empty after the sale")
	check(#msgs > 0 and msgs[1]:find("You sold 64 Bone", 1, true) ~= nil,
		"T2 the result message names quantity, item and amount")
	check(msgs[1]:find("$ 64", 1, true) ~= nil,
		"T2 the amount is rendered by smp_core.fmt_money in body style")
	eq(closed_formspecs["alice"], "smp_sell:sell", "T2 the menu closes after confirming")
	check(smp_core.get_session("alice", "smp_sell:sell") == nil,
		"T2 the session is gone after confirming")

	-- History and statistics were written.
	local entries = smp_sell.history.list("alice")
	eq(#entries, 1, "the sale was appended to the sell history")
	eq(entries[1].server_total, 64000, "history records the server total in cents")
	eq(entries[1].lines[1].item, "mcl_mobitems:bone", "history records the item key")
	eq(entries[1].lines[1].qty, 64, "history records the quantity")
	eq(stat("alice", "money_made_from_sell"), 64000,
		"f14 stats: money_made_from_sell counts the proceeds")

	-- Ledger: exactly one `sell` entry for the payout (X4).
	local ledger, pages = smp_store.api.ledger_for("alice", 1, 50)
	local sells = 0
	for _, e in ipairs(ledger) do
		if e.type == "sell" then sells = sells + 1 end
	end
	check(sells >= 1, "the ledger carries a `sell` entry (shared §2.6 R3)")
end

----------------------------------------------------------------------
-- T3: ineligible items are returned, not consumed
----------------------------------------------------------------------

print("\n== T3: eligibility ==")

do
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")

	local enchanted = ItemStack("mcl_tools:pick_diamond")
	enchanted:get_meta():set_string("mcl_enchanting:enchantments", ser({ mending = 1 }))
	put_in_container("alice", enchanted, 1)                     -- enchanted: not M0
	put_in_container("alice", ItemStack("smp_test:junk 5"), 2)  -- unpriced
	put_in_container("alice", ItemStack("mcl_mobitems:bone 10"), 3)  -- sellable

	local msgs = confirm("alice")
	eq(money("alice"), 10 * 1000, "T3 only the eligible items were sold")
	eq(#container_contents("alice"), 0, "T3 the container is empty")

	local total, kinds = count_inventory(alice)
	eq(total, 6, "T3 both ineligible items came back (1 pickaxe + 5 junk)")
	eq(kinds["mcl_tools:pick_diamond"], 1, "T3 the enchanted pickaxe was returned")
	eq(kinds["smp_test:junk"], 5, "T3 the unpriced item was returned")

	local joined = table.concat(msgs, "\n")
	check(joined:find("Diamond Pickaxe could not be sold (enchanted)", 1, true) ~= nil,
		"T3 the refusal states the reason (shared §4.8 rule 3)")
	check(joined:find("Junk could not be sold and was returned", 1, true) ~= nil,
		"T3 an unpriced item is reported as returned")
end

----------------------------------------------------------------------
-- T4: routing to the better-paying order first, highest price first
----------------------------------------------------------------------

print("\n== T4: order routing ==")

do
	set_money("alice", 0)
	set_stat("alice", "money_made_from_sell", 0)

	-- Two open orders for bones at $20 and $15 per unit; the server pays $10.
	local absorbed = {}
	local order_backend = {
		open_orders_above = function(key_m1, unit, player_name)
			if key_m1 ~= smp_sell.items.plain_m1("mcl_mobitems:bone") then return {} end
			-- Deliberately returned out of order: the adapter must sort them.
			return {
				{ id = 3301, version = 1, state = "open", buyer = "carol",
				  unit_price = 1500, qty = 100, delivered = 90 },   -- 10 left
				{ id = 3302, version = 4, state = "open", buyer = "dave",
				  unit_price = 2000, qty = 500, delivered = 480 },  -- 20 left
				{ id = 3303, version = 1, state = "filled", buyer = "erin",
				  unit_price = 9000, qty = 10, delivered = 0 },     -- not open
				{ id = 3304, version = 1, state = "open", buyer = "alice",
				  unit_price = 9000, qty = 10, delivered = 0 },     -- own order
				{ id = 3305, version = 1, state = "open", buyer = "frank",
				  unit_price = 500, qty = 10, delivered = 0 },      -- pays less
			}
		end,
		absorb_from_sell = function(order, who, key_m1, qty)
			absorbed[#absorbed + 1] = { id = order.id, qty = qty, key = key_m1 }
			-- f04 pays the seller out of the order's escrow and writes its
			-- own `order_payout` ledger row (shared §2.6 R2, R3).
			smp_store.api.add_money(who, qty * order.unit_price, "order_payout",
				"order:" .. order.id)
			return qty, qty * order.unit_price
		end,
	}
	smp_sell.orders.source = order_backend
	check(smp_sell.orders.available(), "the routing adapter reports orders available")

	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 64"), 1)
	confirm("alice")

	eq(#absorbed, 2, "T4 two orders absorbed the bones")
	eq(absorbed[1].id, 3302, "T4 the highest unit price is served first")
	eq(absorbed[1].qty, 20, "T4 only the remaining order quantity is taken")
	eq(absorbed[2].id, 3301, "T4 the next-best order is served second")
	eq(absorbed[2].qty, 10, "T4 the second order takes what it has room for")

	-- 20 @ $20 + 10 @ $15 + 34 @ $10 (server)
	local expected_order = 20 * 2000 + 10 * 1500
	local expected_server = 34 * 1000
	eq(money("alice"), expected_order + expected_server,
		"T4 the seller receives the order price for routed units and the server price for the rest")

	local entries = smp_sell.history.list("alice")
	local e = entries[1]
	eq(e.order_total, expected_order, "T4 history records the order proceeds")
	eq(e.server_total, expected_server, "T4 history records the server proceeds")
	eq(e.lines[1].order, 30, "T4 history records the routed quantity")
	eq(e.lines[1].server, 34, "T4 history records the server quantity")
	eq(#e.lines[1].order_ids, 2, "T4 history records both order ids")

	eq(stat("alice", "money_made_from_sell"), expected_order + expected_server,
		"f02 §4.8: order and server proceeds both count towards money_made_from_sell")

	-- A routing failure must fall back to the server price, never lose items.
	set_money("alice", 0)
	absorbed = {}
	order_backend.absorb_from_sell = function() return nil, "order changed" end
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 10"), 1)
	confirm("alice")
	eq(money("alice"), 10 * 1000, "a refused order falls back to the server price")

	-- A PARTIAL acceptance routes the accepted units and sells the rest to
	-- the server (f04 may have less remaining than was planned).
	set_money("alice", 0)
	absorbed = {}
	order_backend.absorb_from_sell = function(order, who, key_m1, qty)
		local accepted = math.min(qty, 3)          -- the order only has 3 left
		local paid = accepted * order.unit_price
		smp_store.api.add_money(who, paid, "order_payout", "order:" .. order.id)
		absorbed[#absorbed + 1] = { id = order.id, qty = accepted }
		return accepted, paid
	end
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 10"), 1)
	confirm("alice")
	eq(absorbed[1] and absorbed[1].qty, 3, "the order accepted only what it had left")
	eq(money("alice"), 3 * 2000 + 7 * 1000,
		"a partial acceptance sells the remainder to the server")

	smp_sell.orders.source = nil
	eq(smp_sell.orders.available(), false, "routing degrades to 'no orders' when f04 is absent")
end

----------------------------------------------------------------------
-- T5: shulker contents are sold and the box comes back
----------------------------------------------------------------------

print("\n== T5: shulker boxes ==")

do
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")

	local enchanted_sword = ItemStack("mcl_tools:pick_diamond")
	enchanted_sword:get_meta():set_string("mcl_enchanting:enchantments", ser({ mending = 1 }))
	local box = shulker("violet", {
		ItemStack("mcl_mobitems:bone 64"),      -- sellable
		ItemStack("mcl_core:diamond 3"),        -- sellable
		enchanted_sword,                        -- ineligible (enchanted)
		ItemStack("smp_test:junk 2"),           -- ineligible (no price)
	})
	box:get_meta():set_string("name", "Mining Kit")   -- a named box must survive
	put_in_container("alice", box, 1)

	local msgs = confirm("alice")
	local expected = 64 * 1000 + 3 * 900000
	eq(money("alice"), expected, "T5 the eligible contents were sold")

	local total, kinds = count_inventory(alice)
	eq(kinds["mcl_chests:violet_shulker_box"], 1, "T5 the box was returned")
	eq(kinds["mcl_mobitems:bone"], nil, "T5 the sold contents are gone")

	local returned
	for i = 1, alice._inv:get_size("main") do
		local s = alice._inv:get_stack("main", i)
		if s:get_name() == "mcl_chests:violet_shulker_box" then returned = s end
	end
	check(returned ~= nil, "T5 the returned box is in the inventory")
	eq(returned:get_meta():get_string("name"), "Mining Kit",
		"T5 the box keeps its custom name")
	local left = shulker_contents(returned)
	eq(#left, 2, "T5 exactly the two ineligible items are still inside")
	local names = {}
	for _, s in ipairs(left) do names[s:get_name()] = s:get_count() end
	eq(names["mcl_tools:pick_diamond"], 1, "T5 the enchanted tool is intact inside the box")
	eq(names["smp_test:junk"], 2, "T5 the unpriced item is intact inside the box")
	check(table.concat(msgs, "\n"):find("Diamond Pickaxe could not be sold", 1, true) ~= nil,
		"T5 an ineligible item inside a box is reported")

	-- A box whose contents are entirely sellable comes back pristine.
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")
	put_in_container("alice", shulker("white", { ItemStack("mcl_mobitems:bone 64") }), 1)
	confirm("alice")
	eq(money("alice"), 64000, "an emptied box still pays for its contents")
	local back
	for i = 1, alice._inv:get_size("main") do
		local s = alice._inv:get_stack("main", i)
		if s:get_name() == "mcl_chests:white_shulker_box" then back = s end
	end
	check(back ~= nil, "the emptied box was returned")
	eq(back:to_string(), "mcl_chests:white_shulker_box",
		"an emptied box is restored to its pristine form")
	eq(#shulker_contents(back), 0, "the emptied box holds nothing")

	-- An empty box that has a price is itself sellable.
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_chests:violet_shulker_box"), 1)
	confirm("alice")
	eq(money("alice"), 1500000, "an empty shulker box sells as an ordinary item")
	eq(count_inventory(alice), 0, "nothing came back for an empty box")
end

----------------------------------------------------------------------
-- T6: closing without confirming returns every item
----------------------------------------------------------------------

print("\n== T6: closing without confirming ==")

do
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 64"), 1)
	put_in_container("alice", ItemStack("mcl_core:diamond 2"), 2)

	quit_menu("alice")
	eq(money("alice"), 0, "T6 nothing was sold")
	eq(#container_contents("alice"), 0, "T6 the container is empty after closing")
	local total, kinds = count_inventory(alice)
	eq(kinds["mcl_mobitems:bone"], 64, "T6 the bones came back")
	eq(kinds["mcl_core:diamond"], 2, "T6 the diamonds came back")
	check(smp_core.get_session("alice", "smp_sell:sell") == nil, "T6 the session closed")
	eq(detached["smp_sell_alice"], nil, "T6 the detached inventory was removed")

	-- R4: a forged field with no session must be ignored entirely.
	local before = money("alice")
	fire_fields("alice", "smp_sell:sell", { confirm = "" })
	eq(money("alice"), before, "R4 a confirm field with no session does nothing")
end

----------------------------------------------------------------------
-- T7: disconnecting with the menu open returns every item
----------------------------------------------------------------------

print("\n== T7: disconnect with the menu open ==")

do
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 32"), 1)
	put_in_container("alice", ItemStack("smp_test:junk 4"), 2)

	-- A handler registered AFTER smp_sell's stands in for "the player is
	-- saved": it must already see the items back in the inventory (R6).
	local seen_at_save = nil
	handlers.leave[#handlers.leave + 1] = function(player)
		seen_at_save = count_inventory(player)
	end

	fire_leave("alice")
	eq(money("alice"), 0, "T7 leaving does not sell anything")
	eq(seen_at_save, 36, "T7 every item is back in the inventory before the player is saved")
	eq(#container_contents("alice"), 0, "T7 the container is empty")

	-- The crash mirror was cleared, so a rejoin does not duplicate anything.
	players["alice"] = alice
	for _, f in ipairs(handlers.join) do f(alice) end
	eq(count_inventory(alice), 36, "rejoining after a clean leave does not duplicate items")

	table.remove(handlers.leave)   -- drop the test-only save probe
end

----------------------------------------------------------------------
-- T7b: crash recovery through the mirrored container
----------------------------------------------------------------------

print("\n== T7b: crash recovery ==")

do
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_core:diamond 5"), 1)

	-- The mirror is written on every container change (net 3 in menu.lua).
	local d = detached["smp_sell_alice"]
	check(d ~= nil, "the container exists")
	local raw = storages["smp_sell"]["sellbox:alice"]
	check(raw ~= nil and raw ~= "", "the container is mirrored into mod storage")

	-- Simulate a server crash: the detached inventory and the session vanish
	-- without any handler running, then the player rejoins.
	detached["smp_sell_alice"] = nil
	smp_core.close_all_sessions("alice")
	for _, f in ipairs(handlers.join) do f(alice) end

	local total, kinds = count_inventory(alice)
	eq(kinds["mcl_core:diamond"], 5, "T7b the mirrored container is restored on rejoin")
	eq(money("alice"), 0, "T7b recovery returns items, it does not sell them")
	eq(storages["smp_sell"]["sellbox:alice"], nil, "T7b the mirror is cleared after recovery")
end

----------------------------------------------------------------------
-- T8: a full inventory drops the returns at the player's feet
----------------------------------------------------------------------

print("\n== T8: full inventory on return ==")

do
	set_money("alice", 0)
	dropped = {}
	-- Fill every slot with unpriced junk.
	for i = 1, 36 do
		alice._inv:set_stack("main", i, ItemStack("smp_test:junk 64"))
	end
	open_sell("alice")
	put_in_container("alice", ItemStack("smp_test:junk 5"), 1)   -- will not fit back
	put_in_container("alice", ItemStack("mcl_mobitems:bone 8"), 2)

	local sold = 8
	local before_total = count_inventory(alice) + 5 + sold
	confirm("alice")

	eq(money("alice"), sold * 1000, "T8 the sellable item was paid for")
	local after_total = count_inventory(alice)
	local ground = 0
	for _, d in ipairs(dropped) do ground = ground + d.stack:get_count() end
	eq(after_total + ground + sold, before_total,
		"T8 nothing vanished: inventory + ground + sold is conserved")
	check(ground >= 5, "T8 the item that did not fit was dropped at the player's feet")
	for _, d in ipairs(dropped) do
		check(d.pos and d.pos.x == 1 and d.pos.y == 2 and d.pos.z == 3,
			"T8 the drop landed at the player's position")
		break
	end
	dropped = {}
	alice._inv:set_list("main", {})
end

----------------------------------------------------------------------
-- T9: sell.multiplier = 3.0 triples server payouts only
----------------------------------------------------------------------

print("\n== T9: the sell multiplier ==")

do
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 10"), 1)
	confirm("alice")
	eq(money("alice"), 10000, "baseline payout at multiplier 1.0")

	SETTINGS["sell.multiplier"] = "3.0"
	smp_sell.reload()
	eq(smp_sell.cfg.multiplier, 3.0, "the multiplier is live-tunable")
	eq(smp_sell.unit_value("mcl_mobitems:bone"), 3000, "unit value triples")

	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 10"), 1)
	confirm("alice")
	eq(money("alice"), 30000, "T9 the server payout triples")

	-- Order payouts are the buyer's price and must NOT move.
	local absorbed = {}
	smp_sell.orders.source = {
		open_orders_above = function()
			return { { id = 1, version = 1, state = "open", buyer = "carol",
			           unit_price = 1200, qty = 4, delivered = 0 } }
		end,
		absorb_from_sell = function(order, who, _, qty)
			absorbed[#absorbed + 1] = qty
			smp_store.api.add_money(who, qty * order.unit_price, "order_payout",
				"order:" .. order.id)
			return qty, qty * order.unit_price
		end,
	}
	set_money("alice", 0)
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 10"), 1)
	confirm("alice")
	-- The order pays $12/unit, which is BELOW the tripled server price of
	-- $30/unit, so nothing routes: the multiplier raised the bar [S4].
	eq(#absorbed, 0, "T9 an order below the multiplied server price is not used")
	eq(money("alice"), 30000, "T9 the whole stack went to the server at 3x")

	smp_sell.orders.source = {
		open_orders_above = function()
			return { { id = 2, version = 1, state = "open", buyer = "carol",
			           unit_price = 5000, qty = 6, delivered = 0 } }
		end,
		absorb_from_sell = function(order, who, _, qty)
			absorbed[#absorbed + 1] = qty
			smp_store.api.add_money(who, qty * order.unit_price, "order_payout",
				"order:" .. order.id)
			return qty, qty * order.unit_price
		end,
	}
	set_money("alice", 0)
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 10"), 1)
	confirm("alice")
	eq(money("alice"), 6 * 5000 + 4 * 3000,
		"T9 order payouts stay at the order's own unit price")

	smp_sell.orders.source = nil
	SETTINGS["sell.multiplier"] = "1.0"
	smp_sell.reload()
	eq(smp_sell.unit_value("mcl_mobitems:bone"), 1000, "the multiplier resets")
end

----------------------------------------------------------------------
-- T10: selling while combat-tagged succeeds
----------------------------------------------------------------------

print("\n== T10: combat ==")

do
	-- A stubbed smp_combat that tags everyone. smp_sell must never consult
	-- it: f02 §4.6 [S3] and f10 T3 both say /sell works while tagged.
	smp_combat = {
		is_tagged = function() return true end,
		blocked_commands = { sell = true, worth = true },   -- f10 MUST NOT do this
	}
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 4"), 1)
	local msgs = confirm("alice")
	eq(money("alice"), 4000, "T10 selling while combat-tagged succeeds")
	check(smp_sell.ALLOWED_IN_COMBAT.sell == true,
		"T10 smp_sell publishes its combat whitelist for f10")

	local ok, out = commands.worth.func("alice", "mcl_mobitems:bone")
	check(ok and out:find("Bone", 1, true) ~= nil, "T10 /worth works while tagged")
	smp_combat = nil
end

----------------------------------------------------------------------
-- /sell hand and /sell all
----------------------------------------------------------------------

print("\n== /sell hand and /sell all ==")

do
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	alice._inv:set_stack("main", 1, ItemStack("mcl_mobitems:bone 64"))
	alice._inv:set_stack("main", 2, ItemStack("smp_test:junk 3"))
	alice:set_wield_index(1)

	local ok = commands.sell.func("alice", "hand")
	check(ok, "/sell hand succeeds")
	eq(money("alice"), 64000, "/sell hand sells the held stack")
	eq(alice._inv:get_stack("main", 1):get_count(), 0, "/sell hand empties the hand slot")
	eq(alice._inv:get_stack("main", 2):get_count(), 3, "/sell hand leaves the rest alone")

	-- An ineligible held item must stay in the hand, not move.
	set_money("alice", 0)
	alice._inv:set_stack("main", 1, ItemStack("smp_test:junk 7"))
	alice:set_wield_index(1)
	ok = commands.sell.func("alice", "hand")
	eq(money("alice"), 0, "/sell hand on an ineligible item pays nothing")
	eq(alice._inv:get_stack("main", 1):get_count(), 7,
		"/sell hand returns an ineligible item to the hand slot")

	-- /sell all keeps the layout of what it cannot sell.
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	alice._inv:set_stack("main", 1, ItemStack("mcl_mobitems:bone 64"))
	alice._inv:set_stack("main", 5, ItemStack("smp_test:junk 2"))
	alice._inv:set_stack("main", 9, ItemStack("mcl_core:diamond 3"))
	ok = commands.sell.func("alice", "all")
	check(ok, "/sell all succeeds")
	eq(money("alice"), 64000 + 3 * 900000, "/sell all sells every sellable stack")
	eq(alice._inv:get_stack("main", 5):get_count(), 2, "/sell all left slot 5 alone")
	eq(alice._inv:get_stack("main", 5):get_name(), "smp_test:junk",
		"/sell all kept the unsellable item in its own slot")
	eq(alice._inv:get_stack("main", 1):get_count(), 0, "/sell all emptied the bone slot")

	-- /sell all with nothing to sell.
	alice._inv:set_list("main", {})
	local ok2, msg = commands.sell.func("alice", "all")
	eq(ok2, false, "/sell all with an empty inventory refuses")
	check(msg and msg:find("No items to sell", 1, true) ~= nil,
		"/sell all says there is nothing to sell")

	-- Unknown subcommand.
	local ok3, msg3 = commands.sell.func("alice", "everything")
	eq(ok3, false, "an unknown /sell argument is refused")
	check(msg3 and msg3:find("Usage: /sell", 1, true) ~= nil, "usage is shown")

	-- Cross-mod API contract (f06 amethyst sell axe, f07 "Sell all"):
	--   smp_sell.sell(player, stack) -> true only when the stack was paid.
	set_money("alice", 0)
	local sold = smp_sell.sell(alice, ItemStack("mcl_mobitems:bone 8"))
	eq(sold, true, "the single-stack API returns true when the stack was paid for")
	eq(money("alice"), 8000, "the single-stack API pays the server price")

	set_money("alice", 0)
	local renamed = ItemStack("mcl_mobitems:bone 8")
	renamed:get_meta():set_string("name", "My Bones")
	local sold2 = smp_sell.sell(alice, renamed)
	eq(sold2, false, "the single-stack API refuses an ineligible stack")
	eq(money("alice"), 0, "a refused single-stack sale pays nothing")

	set_money("alice", 0)
	local mixed_box = shulker("violet", {
		ItemStack("mcl_mobitems:bone 64"),
		ItemStack("smp_test:junk 2"),       -- ineligible contents
	})
	local sold3 = smp_sell.sell(alice, mixed_box)
	eq(sold3, false, "the single-stack API refuses a partly-sellable shulker")
	eq(money("alice"), 0, "a refused shulker sale pays nothing (no partial loss)")

	-- An array form is also accepted.
	set_money("alice", 0)
	local sold4 = smp_sell.sell(alice, {
		ItemStack("mcl_mobitems:bone 2"), ItemStack("mcl_core:diamond 1"),
	})
	eq(sold4, true, "the API accepts an array and pays for all of it")
	eq(money("alice"), 2 * 1000 + 1 * 900000, "the array API pays every stack")
end

----------------------------------------------------------------------
-- /worth
----------------------------------------------------------------------

print("\n== /worth ==")

do
	alice._inv:set_list("main", {})
	alice._inv:set_stack("main", 1, ItemStack("mcl_mobitems:bone 5"))
	alice:set_wield_index(1)

	local ok, out = commands.worth.func("alice", "")
	check(ok, "/worth with no argument reads the held item")
	check(out:find("Bone: $ 10 each", 1, true) ~= nil,
		"/worth renders `<Item>: <price> each` with smp_core.fmt_money")

	ok, out = commands.worth.func("alice", "mcl_core:diamond")
	check(ok and out:find("$ 9K each", 1, true) ~= nil,
		"/worth accepts a full itemstring")

	ok, out = commands.worth.func("alice", "diamond")
	check(ok and out:find("Diamond", 1, true) ~= nil,
		"/worth accepts a bare item name")

	ok, out = commands.worth.func("alice", "smp_test:junk")
	check(ok and out:find("has no server price", 1, true) ~= nil,
		"/worth reports an unpriced item")

	ok, out = commands.worth.func("alice", "no_such_item_at_all")
	eq(ok, false, "/worth refuses an unknown item")

	-- A held stack that cannot be sold says so.
	local pick = ItemStack("mcl_tools:pick_diamond")
	pick:set_wear(999)
	alice._inv:set_stack("main", 1, pick)
	ok, out = commands.worth.func("alice", "")
	check(ok and out:find("cannot be sold as it is (worn)", 1, true) ~= nil,
		"/worth warns when the held stack is not sellable at M0")

	-- With a multiplier the base price is shown too.
	alice._inv:set_stack("main", 1, ItemStack("mcl_mobitems:bone 1"))
	SETTINGS["sell.multiplier"] = "3.0"
	smp_sell.reload()
	ok, out = commands.worth.func("alice", "")
	check(out:find("$ 30 each", 1, true) ~= nil, "/worth applies the multiplier")
	check(out:find("Base price: $ 10 each", 1, true) ~= nil,
		"/worth shows the base price when a multiplier is active")
	SETTINGS["sell.multiplier"] = "1.0"
	smp_sell.reload()
end

----------------------------------------------------------------------
-- /sellhistory, trimming and the balance cap
----------------------------------------------------------------------

print("\n== /sellhistory, history trimming, balance cap ==")

do
	smp_sell.history.clear("alice")
	set_money("alice", 0)
	alice._inv:set_list("main", {})

	local ok, out = commands.sellhistory.func("alice", "")
	check(ok and out:find("No sales yet", 1, true) ~= nil,
		"/sellhistory says so when there is nothing")

	for i = 1, 7 do
		open_sell("alice")
		put_in_container("alice", ItemStack("mcl_mobitems:bone " .. i), 1)
		confirm("alice")
	end
	eq(smp_sell.history.count("alice"), 7, "seven sales are recorded")

	ok, out = commands.sellhistory.func("alice", "1")
	check(ok and out:find("Sell history (page 1/2)", 1, true) ~= nil,
		"/sellhistory paginates")
	check(out:find("#7", 1, true) ~= nil, "/sellhistory shows the newest sale first")
	check(out:find("received", 1, true) ~= nil, "/sellhistory shows the amount received")

	-- Trimming to sell.history_size.
	SETTINGS["sell.history_size"] = "3"
	smp_sell.reload()
	for i = 1, 3 do
		open_sell("alice")
		put_in_container("alice", ItemStack("mcl_mobitems:bone 1"), 1)
		confirm("alice")
	end
	eq(smp_sell.history.count("alice"), 3, "history is trimmed to sell.history_size")
	SETTINGS["sell.history_size"] = "100"
	smp_sell.reload()

	-- Balance cap: refused BEFORE anything is consumed (shared §0.7).
	smp_sell.history.clear("alice")
	set_money("alice", 1000000000000000 - 1000)   -- $10 below the cap
	alice._inv:set_list("main", {})
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 64"), 1)
	local msgs = confirm("alice")
	eq(money("alice"), 1000000000000000 - 1000,
		"a sale that would exceed the balance cap is refused")
	local total, kinds = count_inventory(alice)
	eq(kinds["mcl_mobitems:bone"], 64,
		"a refused sale leaves the items in the player's inventory")
	eq(#container_contents("alice"), 0, "the container was emptied by the close path")
	check(table.concat(msgs, "\n"):find("balance limit", 1, true) ~= nil,
		"the refusal says why")
	set_money("alice", 0)
end

----------------------------------------------------------------------
-- sell.mode = "close" [C1]
----------------------------------------------------------------------

print("\n== sell.mode = close ==")

do
	SETTINGS["sell.mode"] = "close"
	smp_sell.reload()
	eq(smp_sell.menu.slot_count(), 45, "close mode has no confirm cell, so 45 slots")

	set_money("alice", 0)
	alice._inv:set_list("main", {})
	open_sell("alice")
	local fs = shown_formspecs["alice"].formspec
	check(fs:find("item_image_button", 1, true) == nil,
		"close mode renders no confirm pane")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 3"), 1)
	quit_menu("alice")
	eq(money("alice"), 3000, "close mode sells when the menu closes [C1]")

	SETTINGS["sell.mode"] = "button"
	smp_sell.reload()
	eq(smp_sell.menu.slot_count(), 44, "button mode is back to 44 drop slots")
end

----------------------------------------------------------------------
-- Price reloading
----------------------------------------------------------------------

print("\n== price reloading ==")

do
	eq(smp_sell.base_price("mcl_core:cobble"), 600, "cobblestone starts at 6")
	smp_sell.prices._read = nil

	-- An override file changes a price without touching the modpack.
	local path = "/tmp/smp_sell_devtest_prices.lua"
	local f = assert(io.open(path, "w"))
	f:write('return { ["mcl_core:cobble"] = 1234, ["mcl_mobitems:bone"] = 0 }\n')
	f:close()
	SETTINGS["sell.base_prices"] = path
	smp_sell.reload()
	eq(smp_sell.base_price("mcl_core:cobble"), 1234, "an override file replaces a price")
	eq(smp_sell.base_price("mcl_mobitems:bone"), nil,
		"an override of 0 removes an item from the sellable set")
	SETTINGS["sell.base_prices"] = ""
	os.remove(path)
	smp_sell.reload()
	eq(smp_sell.base_price("mcl_core:cobble"), 600, "reloading without the override restores it")
	eq(smp_sell.base_price("mcl_mobitems:bone"), 1000, "bone is sellable again")

	-- /smp reload reaches the prices (the wrapped smp_economy command).
	local smp_cmd = commands.smp
	check(smp_cmd ~= nil, "/smp exists")
	drain_chat()
	local ok = smp_cmd.func("alice", "reload")
	check(ok ~= nil, "/smp reload still returns a result")
	local lines = drain_chat()
	check(table.concat(lines, "\n"):find("Sell prices reloaded", 1, true) ~= nil,
		"/smp reload reports the reloaded price count")
	ok = smp_cmd.func("alice", "test smp_sell")
	check(ok ~= nil, "/smp test smp_sell is dispatched by the wrapper")
	local test_lines = drain_chat()
	local test_report = table.concat(test_lines, "\n")
	print(test_report)
	check(ok == true, "/smp test smp_sell passes in-game (the mod's own test.lua)")
	check(test_report:find("Failed: 0", 1, true) ~= nil,
		"/smp test smp_sell reports zero failures")
end

----------------------------------------------------------------------
-- Key-authority delegation (smp_items, owned by f04)
----------------------------------------------------------------------

print("\n== key-authority delegation ==")

do
	-- Simulate the shared smp_items key authority with its documented format
	-- (see friedcake/mods/smp_items/init.lua, owner f04):
	--   M0 "m0|<name>"   M1 "m1|<name>|<ench>|<meta_hash>"
	-- smp_sell must adopt this format the moment it is present (f02 §8) and
	-- keep every stored/displayed itemstring in the bare form f02 §5 pins.
	local djb2 = function(str)
		local h = 5381
		for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967296 end
		return string.format("%08x", h)
	end
	local fake_items = {
		ench_of = function(stack)
			local raw = stack:get_meta():get_string("mcl_enchanting:enchantments")
			if raw == "" then return {} end
			local t = core.deserialize(raw)
			return type(t) == "table" and t or {}
		end,
		ench_string = function(ench)
			local ids = {}
			for id in pairs(ench or {}) do ids[#ids + 1] = id end
			table.sort(ids)
			local out = {}
			for _, id in ipairs(ids) do out[#out + 1] = id .. ":" .. tostring(ench[id]) end
			return table.concat(out, ",")
		end,
		named = function(stack)
			local m = stack:get_meta()
			return m:get_string("name") ~= "" or m:get_string("description") ~= ""
		end,
		meta_hash = function(stack)
			local fields = stack:get_meta():to_table().fields or {}
			local keys = {}
			for k in pairs(fields) do
				if k ~= "mcl_enchanting:enchantments" and k ~= "name"
				   and k ~= "description" and k ~= "compressed" and k ~= "" then
					keys[#keys + 1] = k
				end
			end
			if #keys == 0 then return "0" end
			table.sort(keys)
			local parts = {}
			for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(fields[k]) end
			return djb2(table.concat(parts, ";"))
		end,
	}
	fake_items.key = function(stack, level)
		if not stack or stack:is_empty() then return nil end
		local name = registered_aliases[stack:get_name()] or stack:get_name()
		local ench = fake_items.ench_string(fake_items.ench_of(stack))
		local mh = fake_items.meta_hash(stack)
		local wear = stack:get_wear()
		local named = fake_items.named(stack)
		if level == "M0" then
			if next(fake_items.ench_of(stack)) ~= nil or wear ~= 0
			   or named or mh ~= "0" then return nil end
			return "m0|" .. name
		elseif level == "M1" then
			if wear ~= 0 or named then return nil end
			return "m1|" .. name .. "|" .. ench .. "|" .. mh
		end
		return nil
	end

	local prev_smp_items = _G.smp_items
	_G.smp_items = fake_items

	local bone = ItemStack("mcl_mobitems:bone 4")
	eq(smp_sell.items.key_m0(bone, {}), "m0|mcl_mobitems:bone",
		"delegation: M0 keys adopt the smp_items format")
	eq(smp_sell.items.key_m1(bone, {}), "m1|mcl_mobitems:bone||0",
		"delegation: M1 keys adopt the smp_items format")
	eq(smp_sell.items.plain_m1("mcl_mobitems:bone"), "m1|mcl_mobitems:bone||0",
		"delegation: plain_m1 builds an smp_items-format key")
	eq(smp_sell.items.name_of(bone), "mcl_mobitems:bone",
		"delegation: name_of stays the bare itemstring (f02 §5 storage)")

	-- f04's worth_of() calls base_price("m0|<itemstring>"); it must resolve.
	eq(smp_sell.base_price("m0|mcl_mobitems:bone"), 1000,
		"delegation: base_price accepts an m0|-prefixed key (f04 worth_of)")

	-- Routing end-to-end with the delegated M1 key.
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	local seen_key = nil
	smp_sell.orders.source = {
		open_orders_above = function(key_m1, unit, seller)
			seen_key = key_m1
			return { { id = 1, version = 1, state = "open", buyer = "carol",
			           unit_price = 1500, qty = 4, delivered = 0 } }
		end,
		absorb_from_sell = function(order, who, key_m1, qty)
			smp_store.api.add_money(who, qty * order.unit_price, "order_payout",
				"order:" .. order.id)
			return qty, qty * order.unit_price
		end,
	}
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 4"), 1)
	confirm("alice")
	eq(seen_key, "m1|mcl_mobitems:bone||0",
		"delegation: routing offers the smp_items-format M1 key to f04")
	eq(money("alice"), 4 * 1500, "delegation: the sale routes and pays at the order price")

	smp_sell.orders.source = nil
	_G.smp_items = prev_smp_items
	set_money("alice", 0)
end

----------------------------------------------------------------------
-- Money is integer cents, never float (AGENTS.md rule 6)
----------------------------------------------------------------------

print("\n== integer cents ==")

do
	set_money("alice", 0)
	alice._inv:set_list("main", {})
	-- A price that cannot be represented exactly by a float multiplier.
	SETTINGS["sell.multiplier"] = "1.15"
	smp_sell.reload()
	open_sell("alice")
	put_in_container("alice", ItemStack("mcl_mobitems:bone 3"), 1)
	confirm("alice")
	local paid = money("alice")
	eq(paid, math.floor(paid), "the payout is an integer number of cents")
	eq(paid, 3 * math.floor(1000 * 1.15 + 0.5), "the multiplier rounds to whole cents")
	SETTINGS["sell.multiplier"] = "1.0"
	smp_sell.reload()

	-- fmt_money is the only renderer (spot-check the observed spacings).
	eq(smp_core.fmt_money(70000, "body"), "$ 700", "shared §0.6 body spacing")
	eq(smp_core.fmt_money(70000, "inline"), "$700", "shared §0.6 inline spacing")
	eq(smp_core.fmt_money(3000000, "body"), "$ 30K", "shared §0.6 suffix spacing")
end

----------------------------------------------------------------------
-- Result
----------------------------------------------------------------------

print("")
if #failures == 0 then
	print("ALL OK")
	os.exit(0)
else
	print(string.format("%d FAILURE(S):", #failures))
	for _, f in ipairs(failures) do print("  - " .. f) end
	os.exit(1)
end
