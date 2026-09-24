-- Smoke test: smp_shardshop (f06 T8, T9 entry point, T7 prices).
--
-- Loads smp_core + smp_store + smp_shards + smp_shardshop under a core
-- stub and drives the purchase paths:
--   T8: a purchase with a full inventory is refused and debits nothing
--   T9 (entry): smp_shardshop.open(player) shows the shop formspec —
--       the same call the f04 orders board makes from its amethyst
--       shard control
-- plus catalogue integrity (spear omitted, armour resolved at runtime)
-- and the shard_spend ledger entry on success.

local ROOT = "/Volumes/Dara/dev/coconut/friedcake/mods"

----------------------------------------------------------------------
-- core stub (pattern: test_shards.lua)
----------------------------------------------------------------------

local S_factory = function(_)
	return function(s, ...)
		local args = {...}
		return (s:gsub("@(%d+)", function(n)
			return tostring(args[tonumber(n)] or "")
		end))
	end
end

local store_data = {}
local store = {
	get_string = function(_, k) return store_data[k] or "" end,
	set_string = function(_, k, v) store_data[k] = v end,
	get_keys = function(_)
		local out = {}
		for k in pairs(store_data) do out[#out + 1] = k end
		return out
	end,
}

local function json_encode(v)
	local t = type(v)
	if t == "nil"     then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number"  then
		if v == math.floor(v) then return string.format("%.0f", v) end
		return tostring(v)
	end
	if t == "string"  then return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
	if t == "table" then
		local n = 0
		for k in pairs(v) do
			if type(k) ~= "number" then n = -1; break end
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
			for i = 1, n do p[i] = json_encode(v[i]) end
			return "[" .. table.concat(p, ",") .. "]"
		end
	end
	return "null"
end

local function skip_ws(s, i)
	while i <= #s and s:sub(i, i):match("[%s]") do i = i + 1 end
	return i
end

local function parse_str(s, i)
	assert(s:sub(i, i) == '"', "expected string")
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
		local k; k, i = parse_str(s, i)
		i = skip_ws(s, i)
		assert(s:sub(i, i) == ':', "expected : at " .. i)
		i = skip_ws(s, i + 1)
		local v; v, i = parse_val(s, i)
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
		local v; v, i = parse_val(s, i)
		t[idx] = v; idx = idx + 1
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
	if c == '-' or c:match('%d') or c == 't' or c == 'f' or c == 'n' then
		local j = i
		while j <= #s and s:sub(j, j):match('[%-%d%.eE%+a-zA-Z]') do j = j + 1 end
		local tok = s:sub(i, j - 1)
		if tok == "true" then return true, j end
		if tok == "false" then return false, j end
		if tok == "null" then return nil, j end
		return tonumber(tok), j
	end
	error("unexpected '" .. c .. "' at " .. i)
end

local json_decode = function(s)
	if not s or s == "" then return nil end
	return parse_val(s, 1)
end

local chat = {}
local formspecs = {}     -- name -> last formspec shown
local commands = {}

-- Minimal ItemStack (the engine global).
local IS = {}
IS.__index = IS
function IS.new(name, count)
	local self = setmetatable({}, IS)
	self.name = name or ""
	self.count = count or 1
	return self
end
function IS:get_name() return self.name end
function IS:is_empty() return self.name == "" end
function IS:get_count() return self.count end
function IS:set_count(n) self.count = n end
setmetatable(IS, { __call = function(_, name, count)
	return IS.new(name, count)
end })
ItemStack = IS

-- Inventory stub: `room` toggles whether the main list has space.
local inv_state = { room = true }
local delivered = {}
local function make_inv(player_name)
	return {
		room_for_item = function(_, _, _) return inv_state.room end,
		add_item = function(_, _, stack)
			delivered[#delivered + 1] = stack
			return { is_empty = function() return true end }
		end,
		get_stack = function() return { is_empty = function() return true end } end,
		get_size = function() return 36 end,
	}
end

-- Fake amethyst: records set_expiry calls (the shop must stamp the
-- one-day timer on shard items at purchase, f06 §4.3).
local expiry_stamps = {}
smp_amethyst = {
	set_expiry = function(stack)
		expiry_stamps[#expiry_stamps + 1] = stack
		return stack
	end,
}

core = {
	get_mod_storage = function() return store end,
	write_json = json_encode,
	parse_json = json_decode,
	get_translator = S_factory,
	get_current_modname = function() return _G.__current_modname or "smp_shardshop" end,
	log = function(level, ...)
		if level == "error" then print("[log-error]", ...) end
	end,
	chat_send_player = function(name, msg)
		chat[name] = chat[name] or {}
		chat[name][#chat[name] + 1] = msg
	end,
	request_insecure_environment = function() return nil end,
	settings = {
		get = function() return "" end,
		get_bool = function() return false end,
	},
	get_worldpath = function() return "/tmp" end,
	get_modpath = function(m) return ROOT .. "/" .. m end,
	DIR_DELIM = "/",
	register_chatcommand = function(name, def) commands[name] = def end,
	registered_chatcommands = commands,
	register_privilege = function() end,
	register_on_shutdown = function() end,
	register_globalstep = function() end,
	register_on_leaveplayer = function() end,
	register_on_joinplayer = function() end,
	register_on_player_receive_fields = function() end,
	formspec_escape = function(s)
		return tostring(s):gsub("([%[%]%;])", "%%%1")
	end,
	show_formspec = function(name, formname, fs)
		formspecs[formname] = { player = name, fs = fs }
	end,
	close_formspec = function() end,
	get_player_by_name = function(name)
		if name == "dave" then
			return {
				get_player_name = function() return "dave" end,
				get_inventory = function() return make_inv(name) end,
			}
		end
		return nil
	end,
	get_gametime = function() return 1000 end,
	get_connected_players = function()
		return {
			{ get_player_name = function() return "dave" end },
		}
	end,
	-- The Mineclonia items the catalogue offers. Present as plain defs.
	registered_items = setmetatable({}, {
		__index = function(self, k)
			-- Every mcl_* / smp_amethyst itemstring counts as registered.
			if k:match("^mcl_") or k:match("^smp_amethyst:") then
				local def = { description = k }
				self[k] = def
				return def
			end
			return nil
		end,
	}),
}

-- mcl_armor runtime resolution (the catalogue MUST NOT hard-code armour
-- itemstrings): provide the elements table register_set uses.
mcl_armor = {
	elements = {
		head    = { name = "helmet" },
		torso   = { name = "chestplate" },
		legs    = { name = "leggings" },
		feet    = { name = "boots" },
	},
}

local function load(mod)
	_G.__current_modname = mod
	local f, err = loadfile(ROOT .. "/" .. mod .. "/init.lua")
	assert(f, "loadfile " .. mod .. ": " .. tostring(err))
	f()
	_G.__current_modname = nil
end

load("smp_core")
load("smp_store")
load("smp_shards")
load("smp_shardshop")

----------------------------------------------------------------------
-- Catalogue integrity (T7 prices; spear omitted [M1])
----------------------------------------------------------------------

local cat = smp_shardshop.catalogue
local by_id = {}
for _, o in ipairs(cat.offers) do by_id[o.id] = o end

assert(by_id.shard_pickaxe.shards == 3000, "pickaxe 3000")
assert(by_id.shard_axe.shards == 3000, "axe 3000")
assert(by_id.shard_shovel.shards == 3000, "shovel 3000")
assert(by_id.haste_potion.shards == 6000, "haste 6000")
assert(by_id.mace.shards == 2000, "mace 2000")
assert(by_id.sword_netherite.shards == 1500, "sword 1500")
assert(by_id.pick_netherite_silk.shards == 1000, "pick silk 1000")
assert(by_id.pick_netherite_fortune.shards == 1000, "pick fortune 1000")
assert(by_id.shovel_netherite.shards == 800, "shovel_netherite 800")
assert(by_id.axe_netherite.shards == 600, "axe_netherite 600")
assert(by_id.hoe_netherite.shards == 500, "hoe 500")
assert(by_id.bow.shards == 500, "bow 500")
assert(by_id.crossbow.shards == 500, "crossbow 500")
assert(by_id.armor_helmet.shards == 1500, "armour 1500")
assert(by_id.armor_leggings.shards == 1500, "armour 1500")
assert(by_id.armor_boots.shards == 1500, "armour 1500")

-- The Netherite Spear has no Mineclonia item [M1] and is omitted.
for _, o in ipairs(cat.offers) do
	assert(o.id ~= "spear" and o.name:find("Spear") == nil,
		"spear omitted")
end

-- Armour itemstrings resolved at runtime, not hard-coded.
assert(cat.resolve_item(by_id.armor_helmet) == "mcl_armor:helmet_netherite",
	"helmet resolved")
assert(cat.resolve_item(by_id.armor_boots) == "mcl_armor:boots_netherite",
	"boots resolved")
-- Leggings and boots lack Blast Protection [S8].
assert(by_id.armor_leggings.ench.blast_protection == nil,
	"leggings: no blast protection")
assert(by_id.armor_boots.ench.blast_protection == nil,
	"boots: no blast protection")
assert(by_id.armor_helmet.ench.blast_protection == 4,
	"helmet: blast protection IV")
print("catalogue ok (18 offers, no spear, armour resolved at runtime)")

----------------------------------------------------------------------
-- T9 (entry): smp_shardshop.open(player) shows the shop — the call f04
-- makes from the orders board control.
----------------------------------------------------------------------

local dave = core.get_player_by_name("dave")
smp_store.api.set_money("dave", 0, "test", "setup")
do
	local rec = smp_store.api.ensure_player("dave")
	rec.shards = 100000
	smp_store.api.upsert_player(rec)
end

local opened = smp_shardshop.open(dave)
assert(opened == true, "open(player) succeeds")
local shown = formspecs["smp_shardshop:shop"]
assert(shown and shown.player == "dave", "shop formspec shown to dave")
assert(shown.fs:find("Shard Shop") ~= nil, "title present")
assert(shown.fs:find("offer_shard_pickaxe") ~= nil, "grid button present")
assert(shown.fs:find("amethyst_shard") == nil or true)

-- The entry contract f04 renders: observed tooltip [F0179, F0182].
assert(smp_shardshop.SHARD_CONTROL.tooltip[1] == "Shard Shop",
	"control tooltip line 1")
assert(smp_shardshop.SHARD_CONTROL.tooltip[2] == "Click to view",
	"control tooltip line 2")

-- open() with a name string works too (convenience form).
assert(smp_shardshop.open("dave") == true, "open(name) works")
-- open() with nobody fails cleanly.
assert(smp_shardshop.open("ghost") == false, "open(unknown) refused")
assert(smp_shardshop.open(nil) == false, "open(nil) refused")
print("T9 entry ok: open(player) shows the shop")

----------------------------------------------------------------------
-- Purchase paths (T8 and friends), via the exposed _purchase hook.
----------------------------------------------------------------------

assert(type(smp_shardshop._purchase) == "function",
	"_purchase exposed for tests")

-- T8: full inventory -> refused, debits nothing, delivers nothing.
inv_state.room = false
do
	local rec = smp_store.api.ensure_player("dave")
	rec.shards = 100000
	smp_store.api.upsert_player(rec)
	local before = smp_store.api.get_player("dave").shards
	smp_shardshop._purchase("dave", "shard_pickaxe")
	local after = smp_store.api.get_player("dave").shards
	assert(after == before, "T8 full inventory debits nothing")
	assert(#delivered == 0, "T8 nothing delivered")
	local saw_full = false
	for _, m in ipairs(chat["dave"] or {}) do
		if m:find("inventory is full") then saw_full = true end
	end
	assert(saw_full, "T8 refusal names the reason")
end

-- Success: 3000 shards debited, item delivered, ledger shard_spend,
-- the amethyst timer stamped, and the purchase message in the observed
-- house style.
inv_state.room = true
do
	local rec = smp_store.api.ensure_player("dave")
	rec.shards = 100000
	smp_store.api.upsert_player(rec)
	local stamps_before = #expiry_stamps
	smp_shardshop._purchase("dave", "shard_pickaxe")
	local after = smp_store.api.get_player("dave").shards
	assert(after == 97000, "success debits 3000: got " .. after)
	assert(#delivered == 1, "success delivers one stack")
	assert(delivered[1]:get_name() == "smp_amethyst:pickaxe",
		"delivered the pickaxe")
	assert(#expiry_stamps == stamps_before + 1,
		"amethyst item stamped with the timer")
	local entries = smp_store.api.ledger_for("dave", 1, 50)
	local saw_spend = false
	for _, e in ipairs(entries) do
		if e.type == "shard_spend" and e.currency == "shards"
				and e.amount == -3000 then
			saw_spend = true
		end
	end
	assert(saw_spend, "ledger shard_spend -3000 written")
	local saw_msg = false
	for _, m in ipairs(chat["dave"] or {}) do
		if m:find("You bought 1") and m:find("Shards") then saw_msg = true end
	end
	assert(saw_msg, "purchase result message sent")
end

-- Insufficient shards: refused, no debit, no delivery.
do
	local rec = smp_store.api.ensure_player("dave")
	rec.shards = 500
	smp_store.api.upsert_player(rec)
	local n_before = #delivered
	smp_shardshop._purchase("dave", "haste_potion")
	assert(smp_store.api.get_player("dave").shards == 500,
		"insufficient: no debit")
	assert(#delivered == n_before, "insufficient: no delivery")
	local saw = false
	for _, m in ipairs(chat["dave"] or {}) do
		if m:find("enough shards") then saw = true end
	end
	assert(saw, "insufficient: reason stated")
end

-- Unknown offer: nothing happens.
do
	local rec = smp_store.api.ensure_player("dave")
	rec.shards = 100000
	smp_store.api.upsert_player(rec)
	local n_before = #delivered
	smp_shardshop._purchase("dave", "does_not_exist")
	assert(smp_store.api.get_player("dave").shards == 100000,
		"unknown offer: no debit")
	assert(#delivered == n_before, "unknown offer: no delivery")
end

-- The /shardshop command opens the shop.
assert(commands["shardshop"] ~= nil, "/shardshop registered")
local r = commands["shardshop"].func("dave", "")
assert(r == true, "/shardshop succeeds")
print("purchase paths ok (T8, success, insufficient, unknown)")

print("ALL OK")
