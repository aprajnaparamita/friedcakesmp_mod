-- Standalone smoke test for smp_orders (f04) — runs under plain luajit,
-- no engine. Stubs core, ItemStack, inventories, mcl_enchanting,
-- mcl_formspec and mcl_title, then loads smp_core, smp_store, smp_items
-- and smp_orders and exercises the f04 acceptance tests T1–T14 plus the
-- routing-in API contracts for f02/f03.
--
-- Run: luajit friedcake/dev-tests/test_orders.lua
-- Exits non-zero on any failure (tools/agent-flow.sh test).

-- Locate the repository root from the script path so the harness also
-- works from a git worktree checkout.
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
local function eq_lines(a, b, msg)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		failed = failed + 1
		print("FAIL: " .. tostring(msg) .. " (length " ..
			tostring(a and #a) .. " vs " .. tostring(b and #b) .. ")")
		return
	end
	for i = 1, #a do
		eq(a[i], b[i], msg .. " line " .. i)
	end
end

----------------------------------------------------------------------
-- JSON (same minimal codec as test_economy.lua)
----------------------------------------------------------------------

local function json_encode(v)
	local t = type(v)
	if t == "nil"     then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number"  then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if v == math.floor(v) then return string.format("%.0f", v) end
		return tostring(v)
	end
	if t == "string"  then
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
		else
			local p = {}
			for i = 1, n do p[#p + 1] = json_encode(v[i]) end
			return "[" .. table.concat(p, ",") .. "]"
		end
	end
	return "null"
end

local function skip_ws(s, i)
	while i <= #s do
		local c = s:sub(i, i)
		if c == ' ' or c == '\t' or c == '\n' or c == '\r' then i = i + 1
		else break end
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
			if     nc == '"' then out = out .. '"'
			elseif nc == '\\' then out = out .. '\\'
			elseif nc == '/' then out = out .. '/'
			elseif nc == 'n' then out = out .. '\n'
			elseif nc == 't' then out = out .. '\t'
			elseif nc == 'r' then out = out .. '\r'
			elseif nc == 'b' then out = out .. '\b'
			elseif nc == 'f' then out = out .. '\f'
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
		if i > #s then break end
		if s:sub(i, i) == '}' then return t, i + 1 end
		local k
		k, i = parse_str(s, i)
		i = skip_ws(s, i)
		i = skip_ws(s, i + 1) -- ':'
		local v
		v, i = parse_val(s, i)
		t[k] = v
		i = skip_ws(s, i)
		if s:sub(i, i) == ',' then i = i + 1 end
	end
	error("unterminated object")
end

local function parse_arr(s, i)
	local t, idx = {}, 1
	i = i + 1
	while true do
		i = skip_ws(s, i)
		if i > #s then break end
		if s:sub(i, i) == ']' then return t, i + 1 end
		local v
		v, i = parse_val(s, i)
		t[idx] = v
		idx = idx + 1
		i = skip_ws(s, i)
		if s:sub(i, i) == ',' then i = i + 1 end
	end
	error("unterminated array")
end

function parse_val(s, i)
	i = skip_ws(s, i)
	local c = s:sub(i, i)
	if c == '"' then return parse_str(s, i) end
	if c == '{' then return parse_obj(s, i) end
	if c == '[' then return parse_arr(s, i) end
	local j = i
	while j <= #s and s:sub(j, j):match('[^%s,}%]%)]') do j = j + 1 end
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
-- core.serialize / deserialize (for enchantment meta)
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
-- core stub
----------------------------------------------------------------------

local store_data = {}
local shown_forms = {}      -- [player] = {formname, spec}
local chats = {}            -- [player] = {msg, ...}
local dropped = {}          -- core.item_drop log
local actionbars = {}       -- mcl_title log
local commands = {}
local field_handlers = {}
local leave_handlers = {}
local gametime = 1000.0

local function advance(t) gametime = gametime + (t or 1) end

core = {
	DIR_DELIM = "/",
	get_mod_storage = function()
		return {
			get_string = function(_, k) return store_data[k] or "" end,
			set_string = function(_, k, v) store_data[k] = v end,
			get_keys = function(_)
				local out = {}
				for k in pairs(store_data) do out[#out + 1] = k end
				return out
			end,
		}
	end,
	write_json = json_encode,
	parse_json = json_decode,
	serialize = ser_value,
	deserialize = function(s)
		if type(s) ~= "string" or s == "" then return nil end
		local f = loadstring("return " .. s)
		if not f then return nil end
		local good, val = pcall(f)
		return good and val or nil
	end,
	get_translator = function(_)
		return function(s, ...)
			local args = { ... }
			return (s:gsub("@(%d+)", function(n)
				return tostring(args[tonumber(n)] or "")
			end))
		end
	end,
	get_current_modname = function() return _G.__current_modname or "smp_orders" end,
	get_modpath = function(m) return ROOT .. "/friedcake/mods/" .. m end,
	log = function(level, msg)
		if level == "error" then print("[engine error] " .. tostring(msg)) end
	end,
	chat_send_player = function(name, msg)
		chats[name] = chats[name] or {}
		chats[name][#chats[name] + 1] = msg
	end,
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
	settings = {
		get = function(_, k)
			local defaults = {
				["store.backend"] = "mod_storage",
			}
			return defaults[k] or ""
		end,
		get_bool = function(_, k)
			return nil -- orders.allow_self_delivery unset -> false
		end,
	},
	request_insecure_environment = function() return nil end,
	get_worldpath = function() return "/tmp" end,
	register_chatcommand = function(name, def) commands[name] = def end,
	registered_chatcommands = commands,
	register_privilege = function() end,
	register_on_player_receive_fields = function(fn)
		field_handlers[#field_handlers + 1] = fn
	end,
	register_on_leaveplayer = function(fn)
		leave_handlers[#leave_handlers + 1] = fn
	end,
	register_on_joinplayer = function() end,
	register_on_shutdown = function() end,
	register_on_globalstep = function() end,
	get_gametime = function() return gametime end,
	registered_aliases = {},
	item_drop = function(stack, pos)
		dropped[#dropped + 1] = { name = stack:get_name(), count = stack:get_count() }
		return ItemStack("")
	end,
}

----------------------------------------------------------------------
-- Item registry (Mineclonia itemstrings verified in ~/dev/mineclonia-git)
----------------------------------------------------------------------

core.registered_items = {
	["mcl_totems:totem"]             = { description = "Totem of Undying" },
	["mcl_armor:helmet_netherite"]   = { description = "Netherite Helmet" },
	["mcl_beacons:beacon"]           = { description = "Beacon" },
	["mcl_core:gold_ingot"]          = { description = "Gold Ingot" },
	["mcl_core:diamond"]             = { description = "Diamond" },
	["mcl_core:stone"]               = { description = "Stone" },
	["mcl_mobitems:bone"]            = { description = "Bone" },
	["mcl_maps:map_empty"]           = { description = "Empty Map" },
	["mcl_boats:acacia_boat"]        = { description = "Acacia Boat" },
	["mcl_amethyst:amethyst_shard"]  = { description = "Amethyst Shard" },
	["mcl_books:book"]               = { description = "Book" },
	["mcl_hoppers:hopper"]           = { description = "Hopper" },
	["mcl_chests:chest"]             = { description = "Chest" },
	["mcl_panes:pane_lime"]          = { description = "Lime Glass Pane" },
	["mcl_panes:pane_grey"]          = { description = "Grey Glass Pane" },
	["mcl_x:hidden_thing"]           = { description = "Hidden Thing",
	                                     groups = { not_in_creative_inventory = 1 } },
}

----------------------------------------------------------------------
-- ItemStack stub (engine semantics: get_stack returns copies)
----------------------------------------------------------------------

local function make_meta(stack)
	local meta = {}
	function meta:get_string(k)
		local v = stack._meta[k]
		return type(v) == "string" and v or ""
	end
	function meta:set_string(k, v) stack._meta[k] = v end
	function meta:contains(k) return stack._meta[k] ~= nil end
	function meta:to_table()
		local fields = {}
		for k, v in pairs(stack._meta) do fields[k] = v end
		return { fields = fields }
	end
	return meta
end

local function def_of(name)
	return core.registered_items[name]
end

local function stack_new(x)
	local s = { _name = "", _count = 0, _wear = 0, _meta = {} }

	function s:is_empty() return self._name == "" or self._count <= 0 end
	function s:get_name() return self._name end
	function s:set_name(n) self._name = n if self._count == 0 and n ~= "" then self._count = 1 end return self end
	function s:get_count() return self._count end
	function s:set_count(n)
		n = math.floor(tonumber(n) or 0)
		self._count = math.max(n, 0)
		return self
	end
	function s:get_wear() return self._wear end
	function s:set_wear(w) self._wear = math.floor(tonumber(w) or 0) return self end
	function s:get_meta() return make_meta(self) end
	function s:get_stack_max()
		local d = def_of(self._name)
		return (d and d.stack_max) or 64
	end
	function s:get_description()
		if self._meta.description and self._meta.description ~= "" then
			return self._meta.description
		end
		if self._meta.name and self._meta.name ~= "" then
			return self._meta.name
		end
		local d = def_of(self._name)
		return d and d.description or self._name
	end
	function s:take_item(n)
		n = math.min(math.floor(n or self._count), self._count)
		local taken = ItemStack(self._name)
		taken._meta = {}
		for k, v in pairs(self._meta) do taken._meta[k] = v end
		taken._wear = self._wear
		taken:set_count(n)
		self._count = self._count - n
		return taken
	end
	function s:to_string()
		if self:is_empty() then return "" end
		return string.format("%s %d %d", self._name, self._count, self._wear)
	end

	if x == nil then
		return s
	elseif type(x) == "table" and x._name ~= nil then
		-- copy constructor
		s._name, s._count, s._wear = x._name, x._count, x._wear
		for k, v in pairs(x._meta) do s._meta[k] = v end
		return s
	elseif type(x) == "string" and x ~= "" then
		local name, count, wear = x:match("^([^%s]+)%s*(%d*)%s*(%d*)")
		s._name = name or x
		s._count = tonumber(count) or 1
		s._wear = tonumber(wear) or 0
		if not def_of(s._name) then
			-- unknown item: behave like the engine (keep name, count 1)
		end
		return s
	end
	return s
end

ItemStack = stack_new

----------------------------------------------------------------------
-- Inventories (player + detached)
----------------------------------------------------------------------

local function make_inv(size)
	local inv = { _list = {}, _size = size }
	function inv:get_size(_) return self._size end
	function inv:set_size(_, n) self._size = n return true end
	function inv:get_stack(_, i)
		local s = self._list[i]
		return s and ItemStack(s) or ItemStack("")
	end
	function inv:set_stack(_, i, s)
		if s and not s:is_empty() then self._list[i] = ItemStack(s)
		else self._list[i] = nil end
		return true
	end
	function inv:get_list(_)
		local out = {}
		for i = 1, self._size do out[i] = self:get_stack("main", i) end
		return out
	end
	function inv:set_list(_, list)
		self._list = {}
		for i, s in ipairs(list or {}) do
			if s and not s:is_empty() then self._list[i] = ItemStack(s) end
		end
		return true
	end
	function inv:is_empty(_)
		for i = 1, self._size do
			local s = self._list[i]
			if s and not s:is_empty() then return false end
		end
		return true
	end
	function inv:room_for_item(_, stack)
		local need = stack:get_count()
		local max = stack:get_stack_max()
		for i = 1, self._size do
			if need <= 0 then break end
			local s = self._list[i]
			if not s or s:is_empty() then
				need = need - max
			elseif s:get_name() == stack:get_name() and s:get_wear() == stack:get_wear() then
				need = need - math.max(0, max - s:get_count())
			end
		end
		return need <= 0
	end
	function inv:add_item(_, stack)
		local left = ItemStack(stack)
		local max = left:get_stack_max()
		for i = 1, self._size do
			if left:is_empty() then break end
			local s = self._list[i]
			if s and not s:is_empty() and s:get_name() == left:get_name()
			   and s:get_count() < max then
				local move = math.min(max - s:get_count(), left:get_count())
				s:set_count(s:get_count() + move)
				left:take_item(move)
			end
		end
		for i = 1, self._size do
			if left:is_empty() then break end
			if not self._list[i] or self._list[i]:is_empty() then
				self._list[i] = ItemStack(left)
				left:set_count(0)
			end
		end
		return left
	end
	function inv:count(name)
		local total = 0
		for i = 1, self._size do
			local s = self._list[i]
			if s and not s:is_empty() and (not name or s:get_name() == name) then
				total = total + s:get_count()
			end
		end
		return total
	end
	return inv
end

local players = {}
local function make_player(name)
	local p = {
		_name = name,
		_inv = make_inv(36),
	}
	function p:get_player_name() return self._name end
	function p:get_inventory() return self._inv end
	function p:get_pos() return { x = 0, y = 0, z = 0 } end
	players[name] = p
	return p
end

core.get_player_by_name = function(n) return players[n] end
core.get_player_names = function()
	local out = {}
	for n in pairs(players) do out[#out + 1] = n end
	return out
end

local detached = {}
core.create_detached_inventory = function(name, callbacks, pname)
	detached[name] = { inv = make_inv(0), callbacks = callbacks, owner = pname }
	return detached[name].inv
end
core.get_detached_inventory = function(name)
	return detached[name] and detached[name].inv or nil
end
core.remove_detached_inventory = function(name)
	detached[name] = nil
end

----------------------------------------------------------------------
-- mcl_* stubs
----------------------------------------------------------------------

-- aqua_affinity is deliberately NOT in the registry (it is commented out
-- in Mineclonia) so the display fallback path is exercised.
mcl_enchanting = {
	enchantments = {
		protection = { name = "Protection" },
		respiration = { name = "Respiration" },
		unbreaking = { name = "Unbreaking" },
		mending = { name = "Mending" },
	},
	get_enchantments = function(stack)
		if not stack then return {} end
		return core.deserialize(
			stack:get_meta():get_string("mcl_enchanting:enchantments")) or {}
	end,
	set_enchantments = function(stack, ench)
		stack:get_meta():set_string("mcl_enchanting:enchantments",
			core.serialize(ench))
	end,
}

mcl_formspec = {
	label_color = "#313131",
	get_itemslot_bg_v4 = function(x, y, w, h)
		return string.format("SLOTBG[%s,%s,%s,%s]", x, y, w, h)
	end,
}

mcl_title = {
	set = function(player, kind, data)
		actionbars[#actionbars + 1] = {
			name = player and player.get_player_name and player:get_player_name()
				or tostring(player),
			kind = kind,
			text = data and data.text,
		}
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
load_mod("smp_store")
load_mod("smp_items")
load_mod("smp_orders")

----------------------------------------------------------------------
-- Test helpers
----------------------------------------------------------------------

local function money(name)
	local r = smp_store.api.get_player(name)
	return r and r.money or 0
end

local function seed(name, cents)
	smp_store.api.set_money(name, cents, "test", "seed")
end

local function spec_of(name)
	local f = shown_forms[name]
	return f and f.spec or nil
end

local function form_of(name)
	local f = shown_forms[name]
	return f and f.formname or nil
end

local function spec_has(name, str, msg)
	local spec = spec_of(name)
	ok(spec ~= nil and spec:find(str, 1, true) ~= nil,
		(msg or "spec contains") .. ": " .. str)
end

local function spec_lacks(name, str, msg)
	local spec = spec_of(name)
	ok(spec == nil or spec:find(str, 1, true) == nil,
		(msg or "spec lacks") .. ": " .. str)
end

local function last_chat(name)
	local c = chats[name]
	return c and c[#c] or nil
end

local function chat_has(name, str, msg)
	for _, m in ipairs(chats[name] or {}) do
		if m == str then
			passed = passed + 1
			return
		end
	end
	failed = failed + 1
	print(string.format("FAIL: %s — chat %q never sent to %s (last: %q)",
		tostring(msg), str, name, tostring(last_chat(name))))
end

local function clear_chat(name) chats[name] = {} end

local function send_fields(name, fields)
	local f = shown_forms[name]
	assert(f, "no form open for " .. name)
	for _, h in ipairs(field_handlers) do
		h(players[name], f.formname, fields)
	end
end

local function leave(name)
	for _, h in ipairs(leave_handlers) do
		h(players[name], "test")
	end
end

local display = smp_orders.display

----------------------------------------------------------------------
-- Players and seeds
----------------------------------------------------------------------

local alice = make_player("alice")   -- buyer
local bob = make_player("bob")       -- supplier
local carol = make_player("carol")   -- second supplier / buyer
seed("alice", 200000000000)          -- $2B
seed("bob", 10000)
seed("carol", 200000000000)

local key_totem = smp_items.key(ItemStack("mcl_totems:totem"), "M1")
local key_diamond = smp_items.key(ItemStack("mcl_core:diamond"), "M1")

print("== smp_items keying (shared §2.5) ==")
eq(key_totem, "m1|mcl_totems:totem||0", "totem M1 key shape")
local helm_magic = ItemStack("mcl_armor:helmet_netherite")
mcl_enchanting.set_enchantments(helm_magic,
	{ protection = 4, respiration = 3, aqua_affinity = 1, unbreaking = 3, mending = 1 })
local key_helm_ench = smp_items.key(helm_magic, "M1")
eq(key_helm_ench,
	"m1|mcl_armor:helmet_netherite|aqua_affinity:1,mending:1,protection:4,respiration:3,unbreaking:3|0",
	"enchanted M1 key: sorted ench, no meta noise")
local helm_plain = ItemStack("mcl_armor:helmet_netherite")
ok(smp_items.key(helm_plain, "M1") ~= key_helm_ench, "plain vs enchanted keys differ")
ok(smp_items.matches(helm_plain, key_helm_ench, "M1") == false,
	"M1: plain helmet does not match enchanted order")
ok(smp_items.matches(helm_magic, key_helm_ench, "M1") == true,
	"M1: identical enchantments match")
-- M0: plain only
eq(smp_items.key(helm_plain, "M0"), "m0|mcl_armor:helmet_netherite", "M0 plain keys")
ok(smp_items.key(helm_magic, "M0") == nil, "M0 rejects enchanted")
-- M0 -> M1 normalisation for f02 routing
eq(smp_orders.to_m1("m0|mcl_core:diamond"), key_diamond, "to_m1 normalisation")
-- named / worn / contents rejection at M1
local named = ItemStack("mcl_core:diamond")
named:get_meta():set_string("name", "Bob's Rock")
ok(smp_items.key(named, "M1") == nil, "M1 rejects named stacks")
local worn = ItemStack("mcl_armor:helmet_netherite")
worn:set_wear(500)
ok(smp_items.key(worn, "M1") == nil, "M1 rejects worn stacks")
-- stack_from_key round-trip (collection path)
local rebuilt = smp_items.stack_from_key(key_helm_ench)
ok(rebuilt ~= nil and rebuilt:get_name() == "mcl_armor:helmet_netherite",
	"stack_from_key rebuilds the item")
eq(rebuilt and rebuilt:get_meta():get_string("mcl_enchanting:enchantments") ~= "", true,
	"stack_from_key restores enchantments")
ok(smp_items.matches(rebuilt, key_helm_ench, "M1"), "rebuilt stack re-matches its key")

print("== display: plural/singular, enchant line (T2/T3) ==")
eq(display.plural("Totem of Undying"), "Totems of Undying", "plural totem")
eq(display.plural("Netherite Helmet"), "Netherite Helmets", "plural helmet")
eq(display.plural("Gold Ingot"), "Gold Ingots", "plural ingot")
eq(display.plural("Beacon"), "Beacons", "plural beacon")
eq(display.plural("Empty Map"), "Empty Maps", "plural map")
eq(display.plural("Bone"), "Bones", "plural bone")
eq(display.plural("Box"), "Boxes", "plural -es")
eq(display.plural("Berry"), "Berries", "plural -ies")
eq(display.ench_line({ protection = 4, respiration = 3, aqua_affinity = 1,
	unbreaking = 3, mending = 1 }),
	"Protection IV, Respiration III, Aqua Affinity, Unbreaking III, Mending",
	"enchantment line [F0164] — order, romans, level-1 bare")
eq(display.ench_line({}), "", "no enchantments -> no line")
eq(display.roman(4), "IV", "roman 4")
eq(display.roman(1), "I", "roman 1")
-- T2: tooltip line order
local helm_order = {
	template = "mcl_armor:helmet_netherite",
	ench = { protection = 4, respiration = 3, aqua_affinity = 1,
	         unbreaking = 3, mending = 1 },
	unit_price = 400000000, qty = 350, delivered = 251,
}
eq_lines(display.order_tooltip_lines(helm_order), {
	"Netherite Helmets",
	"Protection IV, Respiration III, Aqua Affinity, Unbreaking III, Mending",
	"$ 4M each",
	"251/350 Delivered",
	"Click to deliver items",
	"mcl_armor:helmet_netherite",
}, "T2 order tooltip, exact lines in order (component line dropped)")
-- T3: singular chat, plural panel
local totem_order = { template = "mcl_totems:totem", ench = {},
	unit_price = 3000000, qty = 300000, delivered = 0 }
eq(display.delivered_message(1, totem_order, 3000000),
	"You delivered 1 Totem of Undying and received $30K",
	"T3 delivery chat SINGULAR [F0227]")
eq_lines(display.confirm_lines(totem_order, 1), {
	"Totems of Undying",
	"300k requested",
	"$30K each",
	"You're delivering 1 Totems of Undying",
	"mcl_totems:totem",
}, "T3 confirm panel PLURAL at qty 1 [F0219] (§0.6 lower-case qty)")
eq(display.confirm_tooltip(3000000), "Confirm\nClick to deliver items ($30K)",
	"confirm pane tooltip [F0222]")

print("== T12 strings: the observed scale ==")
local gold_order = { template = "mcl_core:gold_ingot", ench = {},
	unit_price = 100000, qty = 1300000, delivered = 753000 }
eq_lines(display.order_tooltip_lines(gold_order), {
	"Gold Ingots",
	"$ 1K each",
	"753k/1.3m Delivered",
	"Click to deliver items",
	"mcl_core:gold_ingot",
}, "T12 753k/1.3m Delivered [F0160], no stack materialisation")

print("== data layer + escrow (T6, R2/R3) ==")
seed("alice", 200000000000)
local bal0 = money("alice")
advance()
local id1, err1 = smp_orders.create("alice", key_totem, 1, 1000)
ok(id1 ~= nil, "create returns an id (" .. tostring(err1) .. ")")
local o1 = smp_orders.get_order(id1)
eq(o1.state, "open", "new order is open")
eq(o1.version, 1, "new order version 1")
eq(o1.delivered, 0, "delivered 0")
eq(o1.collected, 0, "collected 0")
eq(o1.suppliers and next(o1.suppliers) == nil, true, "no suppliers yet")
-- T6: escrow is exactly Total and the balance drops by exactly that
eq(money("alice"), bal0 - 1000, "T6 balance drops by exactly Total")
eq(o1.escrow, 1000, "T6 escrow == unit_price × qty")
eq(o1.expires - o1.created, smp_orders.cfg.duration, "expiry = created + duration")
-- R3: ledger entry with reason order_escrow
do
	local entries = smp_store.api.ledger_for("alice", 1, 50)
	local found
	for _, e in ipairs(entries) do
		if e.type == "order_escrow" and e.ref == "order:" .. id1 then found = e end
	end
	ok(found ~= nil, "R3 order_escrow ledger entry exists")
	ok(found and found.amount == -1000, "R3 order_escrow amount is -total")
end
-- rate limit (R9)
local _, err_rl = smp_orders.create("alice", key_totem, 1, 1000)
eq(err_rl, "Too fast, slow down", "R9 creation rate limit")
advance()
-- blacklist [S9]
local key_shard = smp_items.key(ItemStack("mcl_amethyst:amethyst_shard"), "M1")
local _, err_bl = smp_orders.create("alice", key_shard, 1, 1000)
eq(err_bl, "This item cannot be ordered", "S9 amethyst cannot be ordered")
-- f06 contract: smp_amethyst.blacklist exact itemstrings
do
	_G.smp_amethyst = { blacklist = { "smp_amethyst:pickaxe", "smp_amethyst:sell_axe" } }
	ok(smp_orders.blacklisted("smp_amethyst:pickaxe"),
		"f06 contract: shard pickaxe blacklisted")
	ok(smp_orders.blacklisted("m1|smp_amethyst:sell_axe||0"),
		"f06 contract: sell axe blacklisted by key")
	ok(not smp_orders.blacklisted("smp_amethyst:other"),
		"f06 contract: only the listed itemstrings")
	_G.smp_amethyst = nil
	ok(not smp_orders.blacklisted("smp_amethyst:pickaxe"),
		"f06 contract degrades gracefully without smp_amethyst (prefix only)")
	ok(smp_orders.blacklisted("mcl_amethyst:amethyst_shard"),
		"mcl_amethyst: prefix still blacklisted without smp_amethyst")
end
-- insufficient funds
seed("bob", 10)
advance()
local _, err_funds = smp_orders.create("bob", key_totem, 100000, 100000)
eq(err_funds, "Insufficient funds.", "insufficient funds refusal")
seed("bob", 10000)
-- minimum price
advance()
local _, err_min = smp_orders.create("alice", key_totem, 1, 1)
eq(err_min, "Price below minimum ($ 1)", "min price refusal (Minimum: $ 1 [F0202])")
advance()

print("== T7: creation sweeps cheaper auction listings, cheapest first ==")
do
	-- f03's contract: listings_at_or_below returns whole listing records
	-- (id, seller, stack, count, price, unit_price, ...); consume_listing
	-- closes the ENTIRE listing.
	local l1 = { id = "L1", seller = "carol", stack = "mcl_core:diamond 10",
	             count = 10, price = 8000, unit_price = 800 }
	local l2 = { id = "L2", seller = "bob", stack = "mcl_core:diamond 5",
	             count = 5, price = 4500, unit_price = 900 }
	local consumed = {}
	local old_lab = smp_orders.au.listings_at_or_below
	local old_con = smp_orders.au.consume_listing
	smp_orders.au.listings_at_or_below = function(key, unit_price)
		if key == key_diamond and unit_price == 1000 then return { l1, l2 } end
		return {}
	end
	smp_orders.au.consume_listing = function(lid, buyer, price)
		consumed[#consumed + 1] = { id = lid, buyer = buyer, price = price }
		return true
	end
	local carol0, bob0 = money("carol"), money("bob")
	advance()
	local id = smp_orders.create("alice", key_diamond, 15, 1000)
	local o = smp_orders.get_order(id)
	eq(o.delivered, 15, "T7 order filled by the sweep")
	eq(o.state, "filled", "T7 state filled")
	eq(o.escrow, 15000 - 10 * 800 - 5 * 900, "T7 escrow: sellers paid their own prices")
	eq(money("carol") - carol0, 10 * 800, "T7 cheapest seller paid 800×10")
	eq(money("bob") - bob0, 5 * 900, "T7 second seller paid 900×5")
	eq(#consumed, 2, "T7 two listings consumed")
	eq(consumed[1] and consumed[1].id, "L1", "T7 cheapest listing consumed first")
	eq(consumed[1] and consumed[1].price, 10 * 800, "T7 L1 consumed at its own price")
	eq(consumed[2] and consumed[2].id, "L2", "T7 then the next cheapest")
	eq(consumed[2] and consumed[2].price, 5 * 900, "T7 L2 consumed at its own price")
	eq(consumed[1] and consumed[1].buyer, "alice", "T7 buyer recorded for f03's tx")
	eq(o.suppliers.carol, 10, "T7 supplier carol credited")
	eq(o.suppliers.bob, 5, "T7 supplier bob credited")
	-- R3: payout ledger entries
	local entries = smp_store.api.ledger_for("carol", 1, 50)
	local found
	for _, e in ipairs(entries) do
		if e.type == "order_payout" and e.ref == "order:" .. id then found = e end
	end
	ok(found ~= nil and found.amount == 8000, "R3 order_payout ledger entry")
	-- a listing larger than the remaining quantity is skipped (PROPOSED)
	local gwen = make_player("gwen")
	seed("gwen", 1000000)
	advance()
	local lbig = { id = "LB", seller = "bob", stack = "mcl_core:gold_ingot 15",
	               count = 15, price = 1500, unit_price = 100 }
	local key_gold = smp_items.key(ItemStack("mcl_core:gold_ingot"), "M1")
	smp_orders.au.listings_at_or_below = function(key, unit_price)
		if key == key_gold then return { lbig } end
		return {}
	end
	smp_orders.au.consume_listing = function() return true end
	local id2 = smp_orders.create("gwen", key_gold, 10, 500)
	local o2 = smp_orders.get_order(id2)
	eq(o2.delivered, 0, "T7 too-large listing skipped, order stays empty")
	eq(o2.state, "open", "T7 order stays open")
	eq(o2.escrow, 10 * 500, "T7 escrow untouched by a skipped listing")
	smp_orders.au.listings_at_or_below = old_lab
	smp_orders.au.consume_listing = old_con
	-- the shipped bridge degrades to "no listings" (TODO(f03))
	eq(#smp_orders.au.listings_at_or_below(key_diamond, 1000), 0,
		"au bridge stub returns {} without smp_ah")
end

print("== T8: enchanted-helmet order refuses a plain helmet ==")
advance()
local id_e, err_e = smp_orders.create("carol", key_helm_ench, 350, 400000000)
ok(id_e ~= nil, "enchanted order created (" .. tostring(err_e) .. ")")
local o_e = smp_orders.get_order(id_e)
do
	bob._inv:set_list("main", {})
	local plain = ItemStack("mcl_armor:helmet_netherite")
	local acc, pay, msg, processed = smp_orders.deliver(bob, id_e, { plain }, o_e.version)
	eq(acc, nil, "T8 refused")
	eq(msg, "Nothing matched this order", "T8 refusal message")
	eq(processed, true, "T8 stacks were processed (returned)")
	eq(bob._inv:count("mcl_armor:helmet_netherite"), 1, "T8 plain helmet returned")
	eq(o_e.delivered, 0, "T8 nothing counted")
	eq(o_e.version, 1, "T8 version unchanged on refusal")
end

print("== delivery: T9 over-delivery, T10 payout/escrow, action bar, chat ==")
advance()
local id_t = smp_orders.create("alice", key_totem, 10, 3000000) -- $30K each [F0212]
local o_t = smp_orders.get_order(id_t)
do
	bob._inv:set_list("main", {})
	clear_chat("bob")
	local before = money("bob")
	local stacks = { ItemStack("mcl_totems:totem 8") }
	local acc, pay, msg, processed = smp_orders.deliver(bob, id_t, stacks, o_t.version)
	eq(acc, 8, "accepted 8")
	eq(pay, 8 * 3000000, "T10 payout == unit_price × accepted")
	eq(processed, true, "processed")
	eq(msg, nil, "no error")
	eq(o_t.delivered, 8, "delivered 8")
	eq(o_t.escrow, 10 * 3000000 - 8 * 3000000, "T10 escrow debited exactly")
	ok(o_t.escrow >= 0, "T10 escrow never negative")
	eq(o_t.version, 2, "version bumped")
	eq(o_t.suppliers.bob, 8, "supplier credited")
	eq(money("bob") - before, 24000000, "T10 supplier balance credited exactly")
	chat_has("bob", "You delivered 8 Totem of Undying and received $240K",
		"T3/T10 chat, singular name")
	-- action bar [F0226]
	local ab = actionbars[#actionbars]
	ok(ab and ab.kind == "actionbar" and ab.text == "Delivering...",
		"action bar Delivering... [F0226]")
	-- buyer notification
	chat_has("alice", "bob delivered 8 Totems of Undying to your order",
		"buyer notification, plural name")
end
do
	-- T9: over-delivery fills to remaining (2) and returns the surplus
	bob._inv:set_list("main", {})
	clear_chat("bob")
	local stacks = { ItemStack("mcl_totems:totem 8") }
	local acc, pay = smp_orders.deliver(bob, id_t, stacks, o_t.version)
	eq(acc, 2, "T9 accepted only the remaining 2")
	eq(pay, 2 * 3000000, "T9 paid only for 2")
	eq(bob._inv:count("mcl_totems:totem"), 6, "T9 surplus 6 returned")
	eq(o_t.delivered, 10, "T9 delivered == qty")
	eq(o_t.state, "filled", "T9 state filled")
	eq(o_t.escrow, 0, "T10 escrow exactly zero, never negative")
	chat_has("bob", "You delivered 2 Totem of Undying and received $60K",
		"T9 chat")
end
do
	-- mixed stacks: non-matching returned, matching accepted (T8 pattern
	-- on a totem order)
	advance()
	local id_m = smp_orders.create("alice", key_totem, 5, 100000)
	local o_m = smp_orders.get_order(id_m)
	bob._inv:set_list("main", {})
	local diamond = ItemStack("mcl_core:diamond 3")
	local totems = ItemStack("mcl_totems:totem 2")
	local acc = smp_orders.deliver(bob, id_m, { diamond, totems }, o_m.version)
	eq(acc, 2, "mixed: only totems accepted")
	eq(bob._inv:count("mcl_core:diamond"), 3, "mixed: diamonds returned")
	eq(bob._inv:count("mcl_totems:totem"), 0, "mixed: totems consumed")
end
do
	-- version race (X2): stale seen_version is refused, stacks untouched
	bob._inv:set_list("main", {})
	local stacks = { ItemStack("mcl_totems:totem 1") }
	local acc, pay, msg, processed = smp_orders.deliver(bob, id_m, stacks, 1)
	eq(acc, nil, "X2 stale version refused")
	eq(msg, "This order has changed", "X2 refusal message")
	eq(processed, false, "X2 stacks NOT processed")
	eq(stacks[1]:get_count(), 1, "X2 stack untouched")
end
do
	-- T11: self-delivery refused
	bob._inv:set_list("main", {})
	advance()
	local id_s = smp_orders.create("bob", key_diamond, 4, 50000)
	local o_s = smp_orders.get_order(id_s)
	local stacks = { ItemStack("mcl_core:diamond 4") }
	local acc, pay, msg, processed = smp_orders.deliver(bob, id_s, stacks, o_s.version)
	eq(acc, nil, "T11 self-delivery refused")
	eq(msg, "You cannot deliver to your own order", "T11 refusal message")
	eq(processed, false, "T11 stacks untouched")
	eq(stacks[1]:get_count(), 4, "T11 items not consumed")
	eq(bob._inv:count("mcl_core:diamond"), 0, "T11 nothing added to inventory")
	eq(o_s.delivered, 0, "T11 order unchanged")
	-- delivery.open refuses early too
	ok(smp_orders.delivery.open(bob, id_s) == false, "T11 open() refuses own order")
end

print("== T13: disconnect with Deliver Items open returns every item ==")
do
	advance()
	local id_d = smp_orders.create("alice", key_diamond, 10, 60000)
	ok(smp_orders.delivery.open(bob, id_d), "delivery.open on someone else's order")
	eq(form_of("bob"), "smp_orders:deliver", "deliver form open")
	spec_has("bob", "Orders -> Deliver Items", "title [F0214]")
	spec_has("bob", "Confirm", "confirm pane present")
	spec_has("bob", "Click to deliver items ($0)", "affordance with empty grid")
	local dinv = core.get_detached_inventory("smp_orders_deliver_bob")
	ok(dinv ~= nil, "detached inventory exists")
	eq(dinv:get_size("main"), 27, "27-slot grid")
	dinv:set_stack("main", 1, ItemStack("mcl_core:diamond 5"))
	dinv:set_stack("main", 2, ItemStack("mcl_totems:totem 3"))
	bob._inv:set_list("main", {})
	-- disconnect
	leave("bob")
	eq(bob._inv:count("mcl_core:diamond"), 5, "T13 diamonds returned")
	eq(bob._inv:count("mcl_totems:totem"), 3, "T13 totems returned")
	ok(core.get_detached_inventory("smp_orders_deliver_bob") == nil,
		"T13 detached inventory destroyed")
	ok(smp_core.get_session("bob", "smp_orders:deliver") == nil,
		"T13 session closed")
end

print("== delivery UI flow: Deliver Items -> Confirm Delivery ==")
do
	advance()
	local id_u = smp_orders.create("alice", key_diamond, 7, 1200) -- $12 each
	local o_u = smp_orders.get_order(id_u)
	smp_orders.show_board("bob", 1)
	spec_has("bob", "Orders (Page 1)", "board title for bob")
	send_fields("bob", { ["order_" .. id_u] = "true" })
	eq(form_of("bob"), "smp_orders:deliver", "clicking an order opens Deliver Items")
	local dinv = core.get_detached_inventory("smp_orders_deliver_bob")
	dinv:set_stack("main", 1, ItemStack("mcl_core:diamond 3"))
	dinv:set_stack("main", 2, ItemStack("mcl_core:stone 2")) -- non-matching
	send_fields("bob", { to_confirm = "true" })
	spec_has("bob", "Orders -> Confirm Delivery", "confirm title [F0218]")
	spec_has("bob", "Diamonds", "panel plural name")
	spec_has("bob", "7 requested", "panel requested line")
	spec_has("bob", "$12 each", "panel unit price inline")
	spec_has("bob", "You're delivering 3 Diamonds", "panel delivering line [F0219]")
	spec_has("bob", "mcl_core:diamond", "panel itemstring (component line dropped)")
	spec_lacks("bob", "component(s)", "no Java component line (§0.5.1)")
	spec_has("bob", "Click to deliver items ($36)", "affordance carries payout [F0222]")
	bob._inv:set_list("main", {})
	clear_chat("bob")
	local bob0 = money("bob")
	send_fields("bob", { confirm_delivery = "true" })
	chat_has("bob", "You delivered 3 Diamond and received $36", "T3 singular chat [F0227]")
	eq(money("bob") - bob0, 3600, "paid 3 × $12")
	eq(o_u.delivered, 3, "order advanced")
	eq(bob._inv:count("mcl_core:stone"), 2, "non-matching stones returned")
	eq(bob._inv:count("mcl_core:diamond"), 0, "matching diamonds consumed")
	ok(core.get_detached_inventory("smp_orders_deliver_bob") == nil,
		"detached inventory destroyed after confirm")
	ok(smp_core.get_session("bob", "smp_orders:deliver") == nil, "session closed")
	-- R4: forged confirm field without a session is ignored
	local forged_before = o_u.version
	for _, h in ipairs(field_handlers) do
		h(players.bob, "smp_orders:deliver", { confirm_delivery = "true" })
	end
	eq(o_u.version, forged_before, "R4 forged confirm without session ignored")
end

print("== quit on Deliver Items returns items (R6, X1) ==")
do
	advance()
	local id_q = smp_orders.create("alice", key_diamond, 10, 60000)
	smp_orders.delivery.open(bob, id_q)
	local dinv = core.get_detached_inventory("smp_orders_deliver_bob")
	dinv:set_stack("main", 3, ItemStack("mcl_core:diamond 4"))
	bob._inv:set_list("main", {})
	send_fields("bob", { quit = "true" })
	eq(bob._inv:count("mcl_core:diamond"), 4, "quit returns the grid")
	ok(core.get_detached_inventory("smp_orders_deliver_bob") == nil,
		"quit destroys the detached inventory")
end

print("== board: T1 title/filter, sorting, paging, controls ==")
do
	smp_orders.show_board("alice", 1)
	spec_has("alice", "Orders (Page 1)", "T1 exact board title [F0156]")
	spec_has("alice", "Most Per Item", "T1 orders sort 1 [F0180]")
	spec_has("alice", "Most Paid", "T1 orders sort 2")
	spec_has("alice", "Recently Listed", "T1 orders sort 3")
	spec_lacks("alice", "Lowest Price", "T1 NOT the auction's sorts")
	spec_lacks("alice", "Highest Price", "T1 NOT the auction's sorts")
	spec_has("alice", "Request and deliver items", "book tooltip line 2 [F0158]")
	spec_has("alice", "Your Orders", "chest tooltip [F0186]")
	spec_has("alice", "Shard Shop", "shard tooltip [F0179]")
	spec_has("alice", "Click to view", "shard affordance")
	spec_has("alice", "Filter", "hopper tooltip line 1")
	spec_has("alice", "Click to change", "hopper tooltip line 2")
	spec_has("alice", "Inventory", "Inventory label [F0158]")
	-- control items present with Mineclonia substitutions (§4.3)
	spec_has("alice", "mcl_books:book", "book control itemstring")
	spec_has("alice", "mcl_hoppers:hopper", "hopper control itemstring")
	spec_has("alice", "mcl_chests:chest", "chest control itemstring")
	spec_has("alice", "mcl_amethyst:amethyst_shard", "shard control itemstring")
	-- filter cycles the three sorts
	local session = smp_core.get_session("alice", "smp_orders:board")
	local first = session.sort
	send_fields("alice", { ctl_filter = "true" })
	session = smp_core.get_session("alice", "smp_orders:board")
	ok(session.sort ~= first, "filter cycles the sort")
	send_fields("alice", { ctl_filter = "true" })
	send_fields("alice", { ctl_filter = "true" })
	session = smp_core.get_session("alice", "smp_orders:board")
	eq(session.sort, first, "filter wraps after three")
	-- sorting semantics: most_per_item puts the $4M helmet order first
	smp_orders.show_board("alice", 1, "most_per_item")
	local page1 = smp_orders.open_orders("most_per_item")
	eq(page1[1].unit_price, 400000000, "most_per_item: highest unit price first")
	local page2 = smp_orders.open_orders("recently_listed")
	ok(page2[1].created >= page2[#page2].created, "recently_listed: newest first")
	-- board -> Your Orders
	send_fields("alice", { ctl_your = "true" })
	eq(form_of("alice"), "smp_orders:your", "chest opens Your Orders")
	spec_has("alice", "Orders -> Your Orders", "Your Orders title [F0190]")
	spec_has("alice", "New Order", "empty slot offers New Order (PROPOSED)")
	spec_has("alice", "Click to create", "empty slot affordance (PROPOSED)")
	-- board -> shard shop (f06 missing -> graceful)
	smp_orders.show_board("alice", 1)
	clear_chat("alice")
	send_fields("alice", { ctl_shard = "true" })
	chat_has("alice", "The Shard Shop is not available yet", "TODO(f06) message")
end

print("== wizard: T4 search, T5 change-jumps, T6 create (UI path) ==")
do
	-- open from Your Orders -> empty slot
	smp_orders.show_your("alice", 1)
	send_fields("alice", { new_order = "true" })
	eq(form_of("alice"), "smp_orders:wizard", "empty slot opens the wizard")
	spec_has("alice", "Choose Item", "step 1 title [F0191]")
	spec_has("alice", "Search", "Search label/button [F0192]")
	spec_has("alice", "Cancel", "Cancel button")
	spec_has("alice", "mcl_totems:totem", "catalog shows items")
	spec_lacks("alice", "mcl_amethyst:amethyst_shard", "blacklisted items absent [S9]")
	spec_lacks("alice", "mcl_x:hidden_thing", "hidden items absent")
	-- T4: search narrows the list, title becomes "(1 results)"
	send_fields("alice", { do_search = "true", search = "totem" })
	spec_has("alice", "Choose Item (1 results)", "T4 exact ungrammatical title [F0198]")
	spec_has("alice", "Totem of Undying", "T4 result listed")
	spec_lacks("alice", "Acacia Boat", "T4 list narrowed")
	-- pick the item -> How many?
	send_fields("alice", { item_1 = "true", search = "totem" })
	spec_has("alice", "How many?", "step 2 title [F0199]")
	spec_has("alice", "Amount", "Amount field label [F0199]")
	spec_has("alice", "field[0.5,1.3;7,0.8;amount;;1]", "amount pre-filled with 1 [F0199]")
	spec_has("alice", "Next", "Next button [F0199]")
	send_fields("alice", { wiz_next = "true", amount = "5" })
	spec_has("alice", "Price per item?", "step 3 title [F0202]")
	spec_has("alice", "Amount: 5", "step 3 amount label [F0202]")
	spec_has("alice", "Minimum: $ 1", "step 3 minimum label [F0202]")
	spec_has("alice", "Review Order", "forward button named for next screen [F0203]")
	send_fields("alice", { wiz_review = "true", price = "10" })
	spec_has("alice", "Review Order", "step 4 title [F0204]")
	spec_has("alice", "Item: Totem of Undying", "review item (singular) [F0204]")
	spec_has("alice", "Amount: 5", "review amount")
	spec_has("alice", "Price: $ 10 each", "review price [F0204]")
	spec_has("alice", "Total: $ 50", "review total [F0204]")
	spec_has("alice", "Cancel!", "Cancel! with exclamation mark [F0204]")
	spec_has("alice", "Change Item", "Change Item [F0204]")
	spec_has("alice", "Change Amount", "Change Amount [F0204]")
	spec_has("alice", "Change Price", "Change Price [F0204]")
	spec_has("alice", "Create Order", "Create Order [F0204]")

	-- T5: Change Amount jumps to that step ALONE, preserving the others
	local session = smp_core.get_session("alice", "smp_orders:wizard")
	send_fields("alice", { change_amount = "true" })
	spec_has("alice", "How many?", "T5 Change Amount -> How many? alone")
	spec_has("alice", "field[0.5,1.3;7,0.8;amount;;5]", "T5 amount field pre-filled")
	session = smp_core.get_session("alice", "smp_orders:wizard")
	eq(session.item.name, "mcl_totems:totem", "T5 item preserved")
	eq(session.price, 1000, "T5 price preserved")
	send_fields("alice", { wiz_next = "true", amount = "7" })
	spec_has("alice", "Review Order", "T5 completing the jump returns to Review")
	spec_has("alice", "Amount: 7", "T5 new amount applied")
	spec_has("alice", "Item: Totem of Undying", "T5 item still intact")
	spec_has("alice", "Price: $ 10 each", "T5 price still intact")
	spec_has("alice", "Total: $ 70", "T5 total recomputed")

	-- T5: Change Item
	send_fields("alice", { change_item = "true" })
	spec_has("alice", "Choose Item", "T5 Change Item -> Choose Item alone")
	session = smp_core.get_session("alice", "smp_orders:wizard")
	eq(session.amount, 7, "T5 amount preserved across Change Item")
	eq(session.price, 1000, "T5 price preserved across Change Item")
	send_fields("alice", { do_search = "true", search = "diamond" })
	spec_has("alice", "Choose Item (1 results)", "T5 search in change-jump")
	send_fields("alice", { item_1 = "true", search = "diamond" })
	spec_has("alice", "Review Order", "T5 Change Item returns to Review")
	spec_has("alice", "Item: Diamond", "T5 new item")
	spec_has("alice", "Amount: 7", "T5 amount still 7")
	spec_has("alice", "Price: $ 10 each", "T5 price still $10")

	-- T5: Change Price
	send_fields("alice", { change_price = "true" })
	spec_has("alice", "Price per item?", "T5 Change Price -> Price alone")
	spec_has("alice", "Amount: 7", "T5 amount label on price step")
	send_fields("alice", { wiz_review = "true", price = "12" })
	spec_has("alice", "Review Order", "T5 Change Price returns to Review")
	spec_has("alice", "Item: Diamond", "T5 item still Diamond")
	spec_has("alice", "Amount: 7", "T5 amount still 7")
	spec_has("alice", "Price: $ 12 each", "T5 new price")
	spec_has("alice", "Total: $ 84", "T5 new total")

	-- invalid amount / price handling
	send_fields("alice", { change_amount = "true" })
	clear_chat("alice")
	send_fields("alice", { wiz_next = "true", amount = "0" })
	chat_has("alice", "Invalid amount: too small", "invalid amount refused")
	spec_has("alice", "How many?", "still on How many? after refusal")
	send_fields("alice", { wiz_next = "true", amount = "7" })

	-- T6: Create Order escrows exactly Total, board reopens [F0209]
	local bal_before = money("alice")
	advance()
	send_fields("alice", { create_order = "true" })
	eq(money("alice"), bal_before - 8400, "T6 escrow == Total ($84)")
	eq(form_of("alice"), "smp_orders:board", "T6 back to the board [F0209]")
	spec_has("alice", "Orders (Page 1)", "T6 board page 1")
	chat_has("alice", "Order created", "creation feedback (PROPOSED)")
	-- the new order exists with correct fields
	local newest
	for _, o in ipairs(smp_orders.orders_for("alice")) do
		if not newest or o.id > newest.id then newest = o end
	end
	ok(newest ~= nil, "newest order found")
	eq(newest.template, "mcl_core:diamond", "newest order item")
	eq(newest.qty, 7, "newest order qty")
	eq(newest.unit_price, 1200, "newest order unit price")
	eq(newest.escrow, 8400, "newest order escrow")
	-- Cancel! abandons the wizard
	smp_orders.wizard_start("alice")
	send_fields("alice", { wiz_cancel = "true" })
	ok(smp_core.get_session("alice", "smp_orders:wizard") == nil, "Cancel closes wizard")
	smp_orders.wizard_start("alice")
	send_fields("alice", { do_search = "true", search = "stone" })
	send_fields("alice", { item_1 = "true" })
	send_fields("alice", { wiz_next = "true", amount = "2" })
	send_fields("alice", { wiz_review = "true", price = "5" })
	send_fields("alice", { wiz_cancel_bang = "true" })
	ok(smp_core.get_session("alice", "smp_orders:wizard") == nil,
		"Cancel! closes the wizard")
	eq(form_of("alice"), "smp_orders:your", "Cancel! returns to Your Orders")
end

print("== slot limits (LIVE [S17], default PROPOSED 9) ==")
do
	local dave = make_player("dave")
	seed("dave", 1000000)
	local key_stone = smp_items.key(ItemStack("mcl_core:stone"), "M1")
	for i = 1, 9 do
		advance()
		local id = smp_orders.create("dave", key_stone, 1, 100)
		ok(id ~= nil, "dave order " .. i .. " created")
	end
	advance()
	local id10, err10 = smp_orders.create("dave", key_stone, 1, 100)
	eq(id10, nil, "10th order refused at default limit")
	eq(err10, "You reached order limits", "slot limit message (house style after [F0055])")
	eq(smp_orders.slot_limit("dave"), 9, "default slot limit 9")
	-- tiered limits read the player record's rank
	local rec = smp_store.api.ensure_player("dave")
	rec.rank = { tier = "tier1" }
	smp_store.api.upsert_player(rec)
	eq(smp_orders.slot_limit("dave"), 45, "tier1 slot limit 45")
	advance()
	local id_ok = smp_orders.create("dave", key_stone, 1, 100)
	ok(id_ok ~= nil, "tier1 can create the 10th order")
end

print("== manage: collection and cancellation (T14, V-43 PROPOSED) ==")
do
	-- bob delivers 40 into alice's totem order #id_t? that one is filled.
	-- Use the diamond order id_u (7 qty, 3 delivered, 4 remaining).
	advance()
	local id_c = smp_orders.create("alice", key_totem, 100, 1000) -- $10 each
	local o_c = smp_orders.get_order(id_c)
	bob._inv:set_list("main", {})
	local acc = smp_orders.deliver(bob, id_c, { ItemStack("mcl_totems:totem 40") }, o_c.version)
	eq(acc, 40, "40 delivered")
	eq(o_c.escrow, 60 * 1000, "escrow == unit × (qty − delivered) invariant")
	-- alice collects the 40 delivered totems (virtual -> stacks, T12 rule)
	alice._inv:set_list("main", {})
	local taken, cerr = smp_orders.collect(o_c, alice)
	eq(taken, 40, "collected 40")
	eq(cerr, nil, "collect ok")
	eq(alice._inv:count("mcl_totems:totem"), 40, "40 totems materialised")
	eq(o_c.collected, 40, "collected counter")
	eq(o_c.delivered, 40, "delivered unchanged by collection")
	-- only the buyer collects
	local _, err_not = smp_orders.collect(o_c, bob)
	eq(err_not, "Only the buyer can collect this order", "collect is buyer-only")
	-- nothing left to collect
	local _, err_none = smp_orders.collect(o_c, alice)
	eq(err_none, "No items to collect", "no double collection")
	-- T14: cancel refunds unspent escrow exactly; delivered stays collectible
	advance()
	bob._inv:set_list("main", {})
	local acc2 = smp_orders.deliver(bob, id_c, { ItemStack("mcl_totems:totem 10") }, o_c.version)
	eq(acc2, 10, "10 more delivered before cancel")
	eq(o_c.escrow, 50 * 1000, "escrow now 50 × unit")
	local bal_before = money("alice")
	local refunded, rerr = smp_orders.cancel(o_c, "alice")
	eq(refunded, 50 * 1000, "T14 refund == unspent escrow exactly")
	eq(rerr, nil, "cancel ok")
	eq(money("alice") - bal_before, 50 * 1000, "T14 balance credited")
	eq(o_c.state, "cancelled", "T14 state cancelled")
	eq(o_c.escrow, 0, "T14 escrow drained")
	-- T14: delivered items stay collectible after cancellation
	alice._inv:set_list("main", {})
	local taken2 = smp_orders.collect(o_c, alice)
	eq(taken2, 10, "T14 post-cancel collection of the 10 delivered")
	eq(alice._inv:count("mcl_totems:totem"), 10, "T14 items received")
	-- R3 refund ledger
	local entries = smp_store.api.ledger_for("alice", 1, 100)
	local found
	for _, e in ipairs(entries) do
		if e.type == "order_refund" and e.ref == "order:" .. id_c then found = e end
	end
	ok(found ~= nil and found.amount == 50000, "R3 order_refund ledger entry")
	-- cancel is buyer-only
	advance()
	local id_x = smp_orders.create("alice", key_totem, 2, 1000)
	local _, err_x = smp_orders.cancel(smp_orders.get_order(id_x), "bob")
	eq(err_x, "Only the buyer can cancel this order", "cancel is buyer-only")
	-- admin remove refunds too (§5.5)
	local bal_b2 = money("alice")
	local ref_admin = smp_orders.cancel(smp_orders.get_order(id_x), "root", true)
	eq(ref_admin, 2000, "admin cancel refunds")
	eq(money("alice") - bal_b2, 2000, "admin refund credited")
end

print("== manage screen UI (PROPOSED, V-43) ==")
do
	smp_orders.show_your("alice", 1)
	spec_has("alice", "Orders -> Your Orders", "your orders title")
	spec_has("alice", "Click to manage", "own orders show Click to manage")
	local mine = smp_orders.orders_for("alice")
	ok(#mine > 0, "alice has orders")
	send_fields("alice", { ["order_" .. mine[1].id] = "true" })
	eq(form_of("alice"), "smp_orders:manage", "own order opens manage")
	spec_has("alice", "Collect Items", "collect control (PROPOSED)")
	spec_has("alice", "Cancel Order", "cancel control (PROPOSED)")
	spec_has("alice", "Back", "back control")
	send_fields("alice", { back = "true" })
	eq(form_of("alice"), "smp_orders:your", "Back returns to Your Orders")
end

print("== expiry (§4.10 PROPOSED 7 days) ==")
do
	advance()
	local id_e2 = smp_orders.create("alice", key_totem, 3, 1000)
	local o_e2 = smp_orders.get_order(id_e2)
	o_e2.expires = os.time() - 1
	local bal_before = money("alice")
	local n = smp_orders.expire_due(os.time())
	ok(n >= 1, "expiry sweep ran")
	eq(o_e2.state, "expired", "order expired")
	eq(o_e2.escrow, 0, "expired escrow drained")
	eq(money("alice") - bal_before, 3000, "expired escrow refunded exactly")
	chat_has("alice", "Your order for Totems of Undying expired, $ 30 refunded",
		"expiry notification (PROPOSED)")
end

print("== T12: 1.3m-unit order never materialises stacks ==")
do
	advance()
	local id_big = smp_orders.create("alice", key_totem, 1300000, 100) -- $1 each
	local o_big = smp_orders.get_order(id_big)
	eq(o_big.qty, 1300000, "qty 1.3m is a plain integer")
	o_big.delivered = 753000
	o_big.escrow = (1300000 - 753000) * 100
	smp_orders.mark_dirty(id_big)
	-- board renders it with lower-case suffixes
	smp_orders.show_board("alice", 1)
	spec_has("alice", "753k/1.3m Delivered", "T12 board renders 753k/1.3m [F0160]")
	-- collecting is bounded by inventory room, never by the virtual count
	alice._inv:set_list("main", {})
	local taken = smp_orders.collect(o_big, alice)
	eq(taken, 36 * 64, "T12 collection stops at inventory capacity (36×64)")
	eq(o_big.collected, 36 * 64, "T12 collected counter is exact")
	eq(o_big.delivered - o_big.collected, 753000 - 2304,
		"T12 the rest stays virtual")
	eq(type(o_big.delivered), "number", "T12 delivered stays an integer field")
	eq(math.floor(o_big.delivered), o_big.delivered, "T12 delivered is integral")
end

print("== routing-in API (contracts for f02/f03/f07) ==")
do
	-- Fresh item + fresh buyer so old test orders cannot interfere.
	local erin = make_player("erin")
	seed("erin", 1000000000)
	local key_gold = smp_items.key(ItemStack("mcl_core:gold_ingot"), "M1")
	-- best_open_order: highest payer with remaining capacity
	advance()
	local idA = smp_orders.create("erin", key_gold, 10, 5000)
	ok(idA ~= nil, "routing order A created")
	advance()
	local idB = smp_orders.create("carol", key_gold, 10, 7000)
	ok(idB ~= nil, "routing order B created")
	local best = smp_orders.best_open_order(key_gold)
	eq(best.id, idB, "best_open_order picks the highest unit price")
	local best_m0 = smp_orders.best_open_order("m0|mcl_core:gold_ingot")
	eq(best_m0.id, idB, "best_open_order accepts M0 keys (f03 passes M1; f02 M0)")
	-- open_orders_above: descending, own orders excluded for the seller
	local above = smp_orders.open_orders_above("m0|mcl_core:gold_ingot", 4000)
	eq(#above, 2, "open_orders_above finds both payers")
	eq(above[1].unit_price, 7000, "open_orders_above sorts descending")
	eq(above[2].unit_price, 5000, "open_orders_above second")
	local above_carol = smp_orders.open_orders_above("m0|mcl_core:gold_ingot", 4000, "carol")
	eq(#above_carol, 1, "open_orders_above skips the seller's own orders")
	eq(above_carol[1].id, idA, "open_orders_above left the other order")
	-- absorb_from_sell (f02): pays the order price from escrow
	local oA = smp_orders.get_order(idA)
	local bob_before = money("bob")
	local n, cents = smp_orders.absorb_from_sell(oA, "bob", "m0|mcl_core:gold_ingot", 4)
	eq(n, 4, "absorb_from_sell took 4")
	eq(cents, 4 * 5000, "absorb_from_sell paid the ORDER unit price")
	eq(money("bob") - bob_before, 20000, "absorb_from_sell credited bob")
	eq(oA.delivered, 4, "absorb_from_sell advanced delivered")
	-- self-absorb refused (V-45 / T11 consistency)
	local n_self = smp_orders.absorb_from_sell(oA, "erin", "m0|mcl_core:gold_ingot", 4)
	eq(n_self, 0, "absorb_from_sell refuses the buyer's own items")
	-- fill_from_stack (f03 listing path): whole-stack or nothing
	local oB = smp_orders.get_order(idB)
	local stack = ItemStack("mcl_core:gold_ingot 10")
	local bob_before2 = money("bob")
	local res = smp_orders.fill_from_stack(oB, bob, stack)
	ok(res ~= nil, "fill_from_stack succeeded")
	eq(res.accepted, 10, "fill_from_stack took the whole stack")
	eq(res.payout, 10 * 7000, "fill_from_stack paid order price × accepted")
	eq(res.remaining, 0, "fill_from_stack consumed everything")
	eq(stack:get_count(), 0, "fill_from_stack consumed in place")
	eq(money("bob") - bob_before2, 70000, "fill_from_stack credited bob")
	eq(oB.state, "filled", "fill_from_stack filled the order")
	-- a stack larger than the order's remaining is refused, not partially
	-- consumed (X1: f03 would discard the leftover)
	local oA3 = smp_orders.get_order(idA)  -- remaining 6
	local bigstack = ItemStack("mcl_core:gold_ingot 12")
	local res_big, err_big = smp_orders.fill_from_stack(oA3, bob, bigstack)
	eq(res_big, nil, "fill_from_stack refuses a too-large stack")
	eq(err_big, "full", "fill_from_stack too-large reason")
	eq(bigstack:get_count(), 12, "too-large stack untouched")
	-- non-matching stack refused
	local oA2 = smp_orders.get_order(idA)
	local res_bad, err_bad = smp_orders.fill_from_stack(oA2, bob,
		ItemStack("mcl_core:stone 5"))
	eq(res_bad, nil, "fill_from_stack refuses non-matching")
	eq(err_bad, "Nothing matched this order", "fill_from_stack refusal message")
end

print("== commands: /orders, /order [search], /orderadmin ==")
do
	ok(commands["orders"] ~= nil, "/orders registered")
	ok(commands["order"] ~= nil, "/order registered")
	ok(commands["orderadmin"] ~= nil, "/orderadmin registered")
	commands["orders"].func("alice", "")
	eq(form_of("alice"), "smp_orders:board", "/orders opens the board")
	local r, msg = commands["order"].func("alice", "totem")
	ok(r == true, "/order search returns true")
	ok(msg:find("Totems of Undying", 1, true) ~= nil, "/order search finds plural name")
	ok(msg:find("Delivered", 1, true) ~= nil, "/order search shows progress")
	local r2, msg2 = commands["order"].func("alice", "zzzznothing")
	eq(msg2, "No orders found", "/order search no-match message")
	commands["order"].func("alice", "")
	eq(form_of("alice"), "smp_orders:board", "/order without args opens the board")
	-- /orderadmin remove refunds (fresh player to dodge the slot limit)
	local frank = make_player("frank")
	seed("frank", 100000)
	advance()
	local id_adm = smp_orders.create("frank", key_totem, 2, 1000)
	ok(id_adm ~= nil, "orderadmin: target order created")
	local bal_before = money("frank")
	local r3, msg3 = commands["orderadmin"].func("root", "remove " .. id_adm)
	ok(r3 == true or r3, "/orderadmin remove succeeds")
	eq(money("frank") - bal_before, 2000, "/orderadmin refunds the escrow")
	eq(smp_orders.get_order(id_adm).state, "cancelled", "/orderadmin cancels")
	local r4, msg4 = commands["orderadmin"].func("root", "remove 999999")
	eq(msg4, "No such order", "/orderadmin unknown id")
end

print("== persistence round-trip (own mod storage, dirty-flag flush) ==")
do
	smp_orders.save_dirty()
	local snapshot = {}
	for id, o in pairs(smp_orders.db.orders) do
		snapshot[id] = { state = o.state, delivered = o.delivered,
			collected = o.collected, escrow = o.escrow, version = o.version,
			unit_price = o.unit_price, qty = o.qty }
	end
	local next_id_before = smp_orders.db.next_id
	-- wipe memory and reload from storage
	smp_orders.db.orders = {}
	smp_orders.db.by_buyer = {}
	smp_orders.db.by_key = {}
	smp_orders.db.dirty = {}
	smp_orders.db.next_id = 1
	smp_orders.load_all()
	eq(smp_orders.db.next_id, next_id_before, "next_id survives the round-trip")
	local checked = 0
	for id, want in pairs(snapshot) do
		local o = smp_orders.get_order(id)
		ok(o ~= nil, "order " .. id .. " reloaded")
		if o then
			eq(o.state, want.state, "order " .. id .. " state")
			eq(o.delivered, want.delivered, "order " .. id .. " delivered")
			eq(o.collected, want.collected, "order " .. id .. " collected")
			eq(o.escrow, want.escrow, "order " .. id .. " escrow")
			eq(o.version, want.version, "order " .. id .. " version")
			eq(o.unit_price, want.unit_price, "order " .. id .. " unit_price")
			eq(o.qty, want.qty, "order " .. id .. " qty")
			checked = checked + 1
		end
	end
	ok(checked > 0, "round-trip checked at least one order")
	-- indexes rebuilt
	local ench_reload = smp_orders.get_order(id_e)
	ok(ench_reload ~= nil and ench_reload.ench.protection == 4,
		"enchantment map survives JSON round-trip")
	ok(#smp_orders.orders_for("alice") > 0, "by_buyer index rebuilt")
	ok(#smp_orders.open_orders_for_key(key_helm_ench) >= 1, "by_key index rebuilt")
	-- the reloaded enchanted order still refuses plain helmets (T8 again)
	local plain2 = ItemStack("mcl_armor:helmet_netherite")
	local acc_r = smp_orders.deliver(bob, id_e, { plain2 }, ench_reload.version)
	eq(acc_r, nil, "T8 holds after reload")
end

print("== in-game test suite (mods/smp_orders/test.lua) ==")
do
	local chunk, lerr = loadfile(ROOT .. "/friedcake/mods/smp_orders/test.lua")
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
print(string.format("passed=%d failed=%d", passed, failed))
if failed > 0 then
	print("TEST_ORDERS FAILED")
	os.exit(1)
end
print("ALL OK")
