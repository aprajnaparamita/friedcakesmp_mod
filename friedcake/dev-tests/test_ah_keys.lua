-- dev-tests/test_ah_keys.lua — standalone smoke test for smp_ah/keys.lua
--
-- Covers spec/shared/02-architecture.md §2.5 (canonical item keys, matching
-- levels M0/M1/M2) for the slice f03 implements. No engine required: the
-- ItemStack / ItemMeta / core surface used by keys.lua is stubbed here.
--
-- Run: luajit friedcake/dev-tests/test_ah_keys.lua
-- Prints ALL OK and exits 0 on success.

local MODROOT = "/Volumes/Dara/dev/coconut/friedcake/mods/"

----------------------------------------------------------------------
-- Stubs
----------------------------------------------------------------------

local registered_items = {
	["mcl_core:diamond"]       = { description = "Diamond" },
	["mcl_core:diamond_new"]   = { description = "Diamond" },
	["mcl_tools:sword_diamond"] = { description = "Diamond Sword\n5.5 Attack Damage" },
	["mcl_chests:grey_shulker_box"] = { description = "Grey Shulker Box" },
	["mcl_core:dirt"]          = { description = "Dirt" },
}

core = {
	registered_items = registered_items,
	registered_aliases = { ["mcl_core:diamond_old"] = "mcl_core:diamond" },
	deserialize = function(s)
		-- keys.lua only deserializes the enchantment blob; a tiny
		-- `return {...}` evaluator is enough and stays sandboxed.
		if type(s) ~= "string" or s == "" then return nil end
		local body = s:match("^return%s+(.*)$")
		if not body then return nil end
		local f = loadstring("local t = " .. body .. " return t")
		if not f then return nil end
		local ok, v = pcall(f)
		if ok then return v end
		return nil
	end,
	log = function() end,
}

local function make_meta(fields)
	local m = { _f = fields or {} }
	function m:get_string(k) return self._f[k] or "" end
	function m:set_string(k, v) self._f[k] = v end
	function m:to_table() return { fields = self._f } end
	function m:get_keys()
		local out = {}
		for k in pairs(self._f) do out[#out + 1] = k end
		table.sort(out)
		return out
	end
	return m
end

-- Minimal ItemStack: accepts "name", "name count", or a table.
local Stack = {}
Stack.__index = Stack

local function ItemStack(x)
	local s = setmetatable({ _name = "", _count = 1, _wear = 0, _fields = {} }, Stack)
	if type(x) == "table" and not getmetatable(x) then
		s._name   = x.name or ""
		s._count  = x.count or 1
		s._wear   = x.wear or 0
		s._fields = x.metadata or {}
	elseif type(x) == "string" and x ~= "" then
		local name, count = x:match("^(%S+)%s+(%d+)$")
		if name then
			s._name, s._count = name, tonumber(count)
		else
			s._name = x
		end
	elseif x == nil then
		s._name = ""
	end
	return s
end

function Stack:is_empty() return self._name == "" or self._count <= 0 end
function Stack:get_name() return self._name end
function Stack:get_count() return self._count end
function Stack:get_wear() return self._wear end
function Stack:get_meta() return make_meta(self._fields) end
function Stack:to_string()
	if self:is_empty() then return "" end
	if self._count == 1 then return self._name end
	return self._name .. " " .. self._count
end
function Stack:get_description()
	local def = registered_items[self._name]
	if self._fields["description"] and self._fields["description"] ~= "" then
		return self._fields["description"]
	end
	return (def and def.description) or self._name
end

----------------------------------------------------------------------
-- Load the module under test
----------------------------------------------------------------------

smp_ah = nil
smp_items = nil
local chunk, err = loadfile(MODROOT .. "smp_ah/keys.lua")
assert(chunk, "loadfile keys.lua: " .. tostring(err))
chunk()

local K = smp_ah.keys
assert(K, "smp_ah.keys missing")

----------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------

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
		print(string.format("FAIL %s: expected %s got %s", tostring(msg),
			tostring(b), tostring(a)))
	end
end

----------------------------------------------------------------------
-- 1. Plain stacks
----------------------------------------------------------------------

local diamond = ItemStack("mcl_core:diamond 64")
local p = K.parts(diamond)
eq(p.name, "mcl_core:diamond", "parts.name")
eq(p.wear, 0, "parts.wear")
eq(p.named, false, "parts.named")
eq(p.contents, nil, "parts.contents")
eq(p.ench, "", "parts.ench empty")
eq(p.meta_hash, K.EMPTY_HASH, "parts.meta_hash empty")
eq(p.plain, true, "parts.plain")

local k0 = K.key(diamond, "M0")
local k1 = K.key(diamond, "M1")
local k2 = K.key(diamond, "M2")
ok(k0 and k0:sub(1, 3) == "m0|", "M0 tag")
ok(k1 and k1:sub(1, 3) == "m1|", "M1 tag")
ok(k2 and k2:sub(1, 3) == "m2|", "M2 tag")
eq(k0, "m0|mcl_core:diamond", "M0 canonical form")
ok(K.parse(k1) ~= nil, "M1 parses")
ok(K.parse(k2) ~= nil, "M2 parses")

-- The canonical format is SHARED with the other economy mods (f02/f04/f05):
--   m1|<name>|<ench>|<meta_hash>
--   m2|<name>|<ench>|<wear>|<named>|<contents>|<meta_hash>
do
	local name, ench, mh = k1:match("^m1|([^|]*)|([^|]*)|([^|]*)$")
	eq(name, "mcl_core:diamond", "M1 field 1 is the name")
	eq(ench, "", "M1 field 2 is the enchantment list")
	eq(mh, K.EMPTY_HASH, "M1 field 3 is the meta hash")
	local n2, e2, w2, named2, c2, mh2 =
		k2:match("^m2|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
	eq(n2, "mcl_core:diamond", "M2 field 1 is the name")
	eq(w2, "0", "M2 field 3 is the wear")
	eq(named2, "0", "M2 field 4 is the named flag")
	eq(c2, "", "M2 field 5 is the contents hash")
	eq(mh2, K.EMPTY_HASH, "M2 field 6 is the meta hash")
	-- An M2 key of the same pristine stack carries the same name/ench/meta.
	eq(e2, ench, "M2 enchantment field agrees with M1")
end

-- Stack size is NOT part of the key (a listing prices the whole stack).
eq(K.key(ItemStack("mcl_core:diamond 1"), "M2"), k2, "count not in key")

-- Default level is M2.
eq(K.key(diamond), k2, "default level M2")
eq(K.key(diamond, "nonsense"), k2, "unknown level falls back to M2")

----------------------------------------------------------------------
-- 2. Enchantments are part of M1 (§2.5: "M1 includes enchantments")
----------------------------------------------------------------------

local ench_a = ItemStack({ name = "mcl_tools:sword_diamond", metadata = {
	["mcl_enchanting:enchantments"] = "return { sharpness = 5, unbreaking = 3 }",
}})
local ench_b = ItemStack({ name = "mcl_tools:sword_diamond", metadata = {
	["mcl_enchanting:enchantments"] = "return { unbreaking = 3, sharpness = 5 }",
}})
local ench_c = ItemStack({ name = "mcl_tools:sword_diamond", metadata = {
	["mcl_enchanting:enchantments"] = "return { sharpness = 4, unbreaking = 3 }",
}})
local plain_sword = ItemStack("mcl_tools:sword_diamond")

eq(K.key(ench_a, "M1"), K.key(ench_b, "M1"), "enchant order does not matter")
ok(K.key(ench_a, "M1") ~= K.key(ench_c, "M1"), "enchant level matters at M1")
ok(K.key(ench_a, "M1") ~= K.key(plain_sword, "M1"), "enchanted ~= plain at M1")
ok(K.matches(ench_b, K.key(ench_a, "M1"), "M1"), "matches() agrees with key()")
ok(not K.matches(ench_c, K.key(ench_a, "M1"), "M1"), "matches() rejects a different level")
eq(K.key(ench_a, "M1"):find("sharpness:5") ~= nil, true, "M1 carries sorted id:level")
eq(K.key(ench_a, "M1"):find("unbreaking:3") ~= nil, true, "M1 carries both enchantments")

-- An enchanted stack is not plain, so it has no M0 key.
eq(K.key(ench_a, "M0"), nil, "enchanted stack has no M0 key")
eq(K.key(diamond, "M0") ~= nil, true, "plain stack has an M0 key")
eq(K.best_level(diamond), "M0", "best_level plain")
eq(K.best_level(ench_a), "M1", "best_level enchanted")

----------------------------------------------------------------------
-- 3. Wear, custom name and contents disqualify M1 (§2.5)
----------------------------------------------------------------------

local worn = ItemStack({ name = "mcl_tools:sword_diamond", wear = 1234 })
eq(K.key(worn, "M1"), nil, "worn stack has no M1 key")
eq(K.key(worn, "M0"), nil, "worn stack has no M0 key")
ok(K.key(worn, "M2") ~= nil, "worn stack has an M2 key")
ok(K.key(worn, "M2") ~= K.key(plain_sword, "M2"), "wear is in the M2 key")
ok(not K.matches(worn, K.key(plain_sword, "M1"), "M1"), "worn does not match M1")
-- Level-bounded equality must refuse an ineligible key rather than compare
-- the fields it happens to share.
ok(not K.equals(K.key(worn, "M2"), K.key(plain_sword, "M1"), "M1"),
	"M2 worn vs M1 pristine at M1 is false")

local named = ItemStack({ name = "mcl_tools:sword_diamond", metadata = { name = "Excalibur" } })
eq(K.key(named, "M1"), nil, "renamed stack has no M1 key")
eq(named:get_meta():get_string("name") ~= "", true, "custom name is meta key 'name'")
ok(K.key(named, "M2") ~= K.key(plain_sword, "M2"), "named flag is in the M2 key")
eq(K.best_level(named), "M2", "best_level renamed")

local shulker_empty = ItemStack("mcl_chests:grey_shulker_box")
local shulker_full = ItemStack({ name = "mcl_chests:grey_shulker_box", metadata = {
	compressed = "BASE64ZSTD", [""] = "return { 'mcl_core:dirt 64' }",
}})
eq(K.key(shulker_full, "M1"), nil, "shulker with contents has no M1 key")
ok(K.key(shulker_full, "M2") ~= K.key(shulker_empty, "M2"), "contents hash is in the M2 key")
-- The authoritative `compressed` copy wins: a differing truncated `""` copy
-- must not change the key.
local shulker_same = ItemStack({ name = "mcl_chests:grey_shulker_box", metadata = {
	compressed = "BASE64ZSTD", [""] = "return { 'mcl_core:dirt 1' }",
}})
eq(K.key(shulker_same, "M2"), K.key(shulker_full, "M2"), "compressed copy is authoritative")
eq(K.best_level(shulker_full), "M2", "best_level contents")

----------------------------------------------------------------------
-- 4. meta_hash: non-volatile in, derived out
----------------------------------------------------------------------

local with_meta = ItemStack({ name = "mcl_core:diamond", metadata = { some_mod = "x" } })
ok(K.key(with_meta, "M1") ~= k1, "extra meta changes the M1 key")
ok(K.key(with_meta, "M2") ~= k2, "extra meta changes the M2 key")
eq(K.key(with_meta, "M1"), K.key(ItemStack({ name = "mcl_core:diamond",
	metadata = { some_mod = "x" } }), "M1"), "meta_hash is deterministic")

-- Volatile/derived keys must NOT change the key: `tt` rewrites `description`
-- on load and mcl_enchanting caches `groupcaps_hash`.
local volatile = ItemStack({ name = "mcl_core:diamond", metadata = {
	description = "Diamond\n(some cached text)", groupcaps_hash = "abc123",
}})
eq(K.key(volatile, "M1"), k1, "volatile meta excluded from meta_hash (M1)")
eq(K.key(volatile, "M2"), k2, "volatile meta excluded from meta_hash (M2)")

----------------------------------------------------------------------
-- 5. Alias resolution
----------------------------------------------------------------------

local aliased = ItemStack("mcl_core:diamond_old 64")
eq(K.key(aliased, "M2"), k2, "alias resolved into the canonical name")
eq(K.parts(aliased).name, "mcl_core:diamond", "parts.name is alias-resolved")

----------------------------------------------------------------------
-- 6. equals() / parse() level semantics
----------------------------------------------------------------------

ok(K.equals(k1, k1, "M1"), "M1 reflexivity")
ok(K.equals(k2, k2, "M2"), "M2 reflexivity")
ok(not K.equals(k1, k2, "M2"), "M2 distinguishes levels")
-- At M0 an enchanted item must not equal a plain one of the same name.
ok(not K.equals(K.key(ench_a, "M2"), K.key(plain_sword, "M0"), "M0"),
	"M0 requires plain stacks")
ok(K.equals(K.key(plain_sword, "M2"), K.key(plain_sword, "M0"), "M0"),
	"M0 plain equality")
eq(K.equals(nil, k1, "M1"), false, "nil key never equals")
eq(K.equals(k1, nil, "M1"), false, "nil key never equals (rhs)")
eq(K.parse("garbage"), nil, "parse rejects garbage")
eq(K.parse(""), nil, "parse rejects empty")
eq(K.parse(k1).level, "M1", "parse level M1")
eq(K.parse(k2).level, "M2", "parse level M2")
eq(K.parse(k2).wear, 0, "parse wear")
eq(K.parse(K.key(worn, "M2")).wear, 1234, "parse wear value")
eq(K.parse(K.key(named, "M2")).named, true, "parse named flag")
eq(K.parse(K.key(shulker_full, "M2")).contents ~= nil, true, "parse contents hash")

----------------------------------------------------------------------
-- 7. Empty stacks
----------------------------------------------------------------------

eq(K.key(ItemStack(""), "M2"), nil, "empty stack has no key")
eq(K.key(nil, "M2"), nil, "nil stack has no key")
eq(K.parts(ItemStack("")), nil, "empty stack has no parts")

----------------------------------------------------------------------
-- 8. display() for the listing record (f03 §5)
----------------------------------------------------------------------

local d = K.display(ItemStack("mcl_tools:sword_diamond 1"))
eq(d.name, "Diamond Sword", "display.name is the first line only")
eq(d.full:find("5.5 Attack Damage") ~= nil, true, "display.full keeps the stat lines")
local de = K.display(ench_a)
eq(#de.ench, 2, "display.ench list")
eq(de.ench[1].id, "sharpness", "display.ench sorted")
eq(de.ench[1].level, 5, "display.ench level")
eq(K.display(ItemStack("")), nil, "display of an empty stack")

----------------------------------------------------------------------
-- 9. smp_items shim: fill the stub, never clobber a real implementation
----------------------------------------------------------------------

eq(type(smp_items.key), "function", "smp_items.key installed")
eq(type(smp_items.matches), "function", "smp_items.matches installed")
eq(smp_items.key(diamond, "M1"), k1, "smp_items.key delegates to f03's keying")
ok(smp_items.matches(ench_b, smp_items.key(ench_a, "M1"), "M1"),
	"smp_items.matches delegates (the f04 §6.2 call shape)")

local function reload_keys()
	local c2 = assert(loadfile(MODROOT .. "smp_ah/keys.lua"))
	c2()
	return smp_ah.keys
end

-- smp_items loads before smp_ah in modpack.conf, so a real implementation
-- always wins: the shim must not replace it, and f03 must defer to it.
smp_items.key = function(_stack, level) return "m1|OWNER|" .. tostring(level) end
K = reload_keys()
eq(smp_items.key(diamond, "M1"), "m1|OWNER|M1", "existing smp_items.key is preserved")
eq(K.key(diamond, "M1"), "m1|OWNER|M1", "keys.key defers to the shared owner")
smp_items.matches = function(_stack, key) return key == "m1|OWNER|M1" end
K = reload_keys()
eq(K.matches(diamond, "m1|OWNER|M1", "M1"), true, "keys.matches defers to the owner")

-- Drop the owner again: f03's own keying is the fallback (§2.5).
smp_items.key, smp_items.matches = nil, nil
K = reload_keys()
eq(K.key(diamond, "M1"), k1, "fallback keying restored")
eq(smp_items.key(diamond, "M1"), k1, "shim reinstalled over the stub")

----------------------------------------------------------------------
-- 9b. Legacy `k*` spelling still parses (an earlier f03 build stored these)
----------------------------------------------------------------------

do
	local legacy1 = "k1|mcl_core:diamond|e=|m=" .. K.EMPTY_HASH
	local parsed = K.parse(legacy1)
	ok(parsed ~= nil, "legacy k1 parses")
	if parsed then
		eq(parsed.level, "M1", "legacy level")
		eq(parsed.name, "mcl_core:diamond", "legacy name")
		eq(parsed.ench, "", "legacy ench")
		eq(parsed.meta_hash, K.EMPTY_HASH, "legacy meta hash")
	end
	eq(K.parse("k0|mcl_core:diamond") ~= nil, true, "legacy k0 parses")
	eq(K.parse("k2|mcl_core:dirt|e=|w=0|n=0|c=-|m=" .. K.EMPTY_HASH) ~= nil, true,
		"legacy k2 parses")
	eq(K.parse("q1|a|b|c"), nil, "unknown tag rejected")
	-- A legacy M2 key and the current spelling of the same stack agree field
	-- by field, so stored listings keep matching after an upgrade.
	local legacy2 = "k2|mcl_core:diamond|e=|w=0|n=0|c=-|m=" .. K.EMPTY_HASH
	ok(K.equals(legacy2, k2, "M2"), "legacy M2 equals the current M2 key")
	ok(K.equals(legacy1, k1, "M1"), "legacy M1 equals the current M1 key")
end

----------------------------------------------------------------------
-- 10. Hash stability
----------------------------------------------------------------------

eq(K.hash("abc"), K.hash("abc"), "hash is deterministic")
ok(K.hash("abc") ~= K.hash("abd"), "hash distinguishes")
ok(#K.hash("abc") >= 16, "hash is wide enough")
eq(K.EMPTY_HASH, K.hash(""), "EMPTY_HASH")

print(string.format("keys: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("ALL OK (smp_ah/keys.lua)")
