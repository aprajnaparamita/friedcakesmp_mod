-- Standalone test for smp_items (f01 row E-20) — runs under plain luajit,
-- no engine. Stubs `core`, `ItemStack` and the item registry, loads
-- smp_items and exercises:
--
--   * the M0/M1 invariants (byte-identical to the pre-E-20 keys);
--   * the reversible shulker-contents codec in the M2 <contents> field;
--   * `stack_from_key` rebuilding M2 stacks — both Mineclonia storage
--     forms (meta `compressed`, and the empty key `""`);
--   * the refusals: legacy one-way hash tokens, `named == 1`, unknown items;
--   * the six-field pipe split that dev-tests/test_ah_keys.lua:167 performs,
--     proving the token never carries a pipe character.
--
-- Run: luajit friedcake/dev-tests/test_items.lua
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
	return "."
end

local ROOT = find_root()
local MODS = ROOT .. "/friedcake/mods"

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
-- Serializer (the enchantment fallback path uses core.serialize/deserialize)
----------------------------------------------------------------------

local function ser(v)
	local t = type(v)
	if t == "number" then return string.format("%.17g", v) end
	if t == "string" then return string.format("%q", v) end
	if t == "boolean" then return tostring(v) end
	if t == "table" then
		local parts = {}
		for k, val in pairs(v) do
			if type(k) == "string" then
				parts[#parts + 1] = string.format("[%q]=%s", k, ser(val))
			else
				parts[#parts + 1] = string.format("[%d]=%s", k, ser(val))
			end
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "nil"
end

local function unser(s)
	if type(s) ~= "string" or s == "" then return nil end
	local f = loadstring("return " .. s)
	if not f then return nil end
	local good, v = pcall(f)
	return good and v or nil
end

----------------------------------------------------------------------
-- core stub (every name below is engine-real; see
-- dev-tests/engine_api_surface.txt)
----------------------------------------------------------------------

core = {
	get_translator = function()
		return function(s, ...)
			local args = { ... }
			return (s:gsub("@(%d+)", function(n)
				return tostring(args[tonumber(n)] or "")
			end))
		end
	end,
	get_current_modname = function() return "smp_items" end,
	get_modpath = function(m) return MODS .. "/" .. m end,
	log = function(level, msg)
		if level == "error" then print("[engine error] " .. tostring(msg)) end
	end,
	serialize = ser,
	deserialize = unser,
	registered_aliases = {},
	registered_items = {
		["mcl_core:chest"]    = { description = "Chest" },
		["mcl_core:diamond"]  = { description = "Diamond" },
		["mcl_core:stone"]    = { description = "Stone" },
	},
}

----------------------------------------------------------------------
-- ItemStack stub (engine semantics: meta is a flat string map)
----------------------------------------------------------------------

local function make_meta(stack)
	local meta = {}
	function meta:get_string(k)
		local v = stack._meta[k]
		return type(v) == "string" and v or ""
	end
	function meta:set_string(k, v) stack._meta[k] = tostring(v) end
	function meta:contains(k) return stack._meta[k] ~= nil end
	function meta:to_table()
		local fields = {}
		for k, v in pairs(stack._meta) do fields[k] = v end
		return { fields = fields }
	end
	return meta
end

local function stack_new(x)
	local s = { _name = "", _count = 0, _wear = 0, _meta = {} }
	function s:is_empty() return self._name == "" or self._count <= 0 end
	function s:get_name() return self._name end
	function s:set_name(n)
		self._name = n
		if self._count == 0 and n ~= "" then self._count = 1 end
		return self
	end
	function s:get_count() return self._count end
	function s:set_count(n)
		self._count = math.max(math.floor(tonumber(n) or 0), 0)
		return self
	end
	function s:get_wear() return self._wear end
	function s:set_wear(w) self._wear = math.floor(tonumber(w) or 0) return self end
	function s:get_meta() return make_meta(self) end
	function s:get_description()
		if self._meta.description and self._meta.description ~= "" then
			return self._meta.description
		end
		local d = core.registered_items[self._name]
		return d and d.description or self._name
	end
	function s:to_string()
		if self:is_empty() then return "" end
		return string.format("%s %d %d", self._name, self._count, self._wear)
	end
	if type(x) == "table" and x._name ~= nil then
		s._name, s._count, s._wear = x._name, x._count, x._wear
		for k, v in pairs(x._meta) do s._meta[k] = v end
		return s
	end
	if type(x) == "string" and x ~= "" then
		local name, count, wear = x:match("^([^%s]+)%s*(%d*)%s*(%d*)")
		s._name = name or x
		s._count = tonumber(count) or 1
		s._wear = tonumber(wear) or 0
	end
	return s
end

ItemStack = stack_new

----------------------------------------------------------------------
-- Load the mod
----------------------------------------------------------------------

dofile(MODS .. "/smp_items/init.lua")
ok(type(smp_items) == "table", "smp_items loaded")

local ITEM = "mcl_core:chest"

local function plain_box()
	return ItemStack(ITEM)
end

-- A box carrying Mineclonia's two documented storage forms
-- (spec/shared/03-mineclonia-api.md:21). Both payloads deliberately
-- contain bytes outside [A-Za-z0-9.-] — including a PIPE — so the
-- encoding constraint is exercised, not assumed.
local COMPRESSED_PAYLOAD = "H4sIAAAAAAAAA/+/vuL2zT0="
local EMPTY_KEY_PAYLOAD  = 'return {"a|b", "c=d"}'

local function box_with(form)
	local s = plain_box()
	local meta = s:get_meta()
	if form == "compressed" then
		meta:set_string("compressed", COMPRESSED_PAYLOAD)
	elseif form == "empty" then
		meta:set_string("", EMPTY_KEY_PAYLOAD)
	end
	return s
end

----------------------------------------------------------------------
-- M0 / M1 invariants: byte-identical to the pre-E-20 keys
----------------------------------------------------------------------

print("--- M0/M1 invariants ---")
eq(smp_items.key(plain_box(), "M0"), "m0|" .. ITEM, "M0 canonical literal")
eq(smp_items.key(plain_box(), "M1"), "m1|" .. ITEM .. "||0",
	"M1 canonical literal (no contents field at all)")

local enchanted = plain_box()
enchanted:get_meta():set_string("mcl_enchanting:enchantments",
	ser({ protection = 4 }))
eq(smp_items.key(enchanted, "M1"), "m1|" .. ITEM .. "|protection:4|0",
	"M1 with an enchantment is byte-identical too")

-- Contents disqualify M1 exactly as before (the predicate only ever
-- asked "is there any contents?", never what it was).
ok(smp_items.key(box_with("compressed"), "M1") == nil,
	"a box with contents still has no M1 key")
ok(smp_items.key(box_with("compressed"), "M0") == nil,
	"a box with contents still has no M0 key")
eq(smp_items.contents_of(plain_box()), "", "an empty box has no contents token")

----------------------------------------------------------------------
-- E-20: the reversible codec
----------------------------------------------------------------------

print("--- E-20: reversible contents codec ---")
local c_tok = smp_items.contents_of(box_with("compressed"))
local e_tok = smp_items.contents_of(box_with("empty"))
ok(c_tok:sub(1, 1) == "C", "compressed form tags the token with C")
ok(e_tok:sub(1, 1) == "S", "empty-key form tags the token with S")
ok(c_tok:find("|", 1, true) == nil, "the compressed token carries no pipe")
ok(e_tok:find("|", 1, true) == nil, "the empty-key token carries no pipe")

local c_key, c_val = smp_items.contents_decode(c_tok)
eq(c_key, "compressed", "C decodes back to the compressed meta key")
eq(c_val, COMPRESSED_PAYLOAD, "C decodes to the exact payload")
local e_key, e_val = smp_items.contents_decode(e_tok)
eq(e_key, "", "S decodes back to the empty meta key")
eq(e_val, EMPTY_KEY_PAYLOAD, "S decodes to the exact payload")

-- A legacy one-way hash (the pre-E-20 format) is refused, never guessed.
ok(smp_items.contents_decode("deadbeef") == nil, "a legacy hash is refused")
ok(smp_items.contents_decode("") == nil, "an empty token is refused")
ok(smp_items.contents_decode("C%zz") == nil, "a broken escape is refused")

----------------------------------------------------------------------
-- The six-field M2 split (dev-tests/test_ah_keys.lua:167)
----------------------------------------------------------------------

print("--- M2 six-field parse ---")
local m2 = smp_items.key(box_with("compressed"), "M2")
ok(m2 and m2:sub(1, 3) == "m2|", "M2 tag")
local n2, e2, w2, named2, c2, mh2 =
	m2:match("^m2|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
ok(n2 ~= nil, "the M2 key still parses into exactly six pipe-separated fields")
eq(n2, ITEM, "M2 field 1 is the name")
eq(e2, "", "M2 field 2 is the enchantment list")
eq(w2, "0", "M2 field 3 is the wear")
eq(named2, "0", "M2 field 4 is the named flag")
eq(c2, c_tok, "M2 field 5 is the reversible contents token")
eq(mh2, "0", "M2 field 6 is the meta hash")

local m2e = smp_items.key(box_with("empty"), "M2")
local _, _, _, _, c2e = m2e:match("^m2|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
eq(c2e, e_tok, "the empty-key token survives the six-field split too")

----------------------------------------------------------------------
-- E-20: stack_from_key rebuilds M2 stacks
----------------------------------------------------------------------

print("--- E-20: M2 rebuild ---")
for _, form in ipairs({ "compressed", "empty" }) do
	local src = box_with(form)
	local key = smp_items.key(src, "M2")
	local rebuilt = smp_items.stack_from_key(key)
	ok(rebuilt ~= nil, form .. ": stack_from_key rebuilds an M2 stack")
	if rebuilt then
		eq(rebuilt:get_name(), ITEM, form .. ": rebuild keeps the item")
		eq(smp_items.contents_of(rebuilt), smp_items.contents_of(src),
			form .. ": rebuild keeps identical contents")
		local src_key = form == "compressed" and "compressed" or ""
		eq(rebuilt:get_meta():get_string(src_key),
			form == "compressed" and COMPRESSED_PAYLOAD or EMPTY_KEY_PAYLOAD,
			form .. ": rebuild restores the raw payload on its own meta key")
		eq(smp_items.key(rebuilt, "M2"), key,
			form .. ": the rebuilt stack keys back to the SAME M2 key")
	end
end

-- Wear travels too (E-20 covers the whole M2 key, not just contents).
local worn = box_with("compressed")
worn:set_wear(1234)
local worn_key = smp_items.key(worn, "M2")
local worn_back = smp_items.stack_from_key(worn_key)
ok(worn_back ~= nil, "a worn box rebuilds")
eq(worn_back and worn_back:get_wear(), 1234, "wear survives the round-trip")

-- Enchantments travel too.
local ench_box = box_with("compressed")
ench_box:get_meta():set_string("mcl_enchanting:enchantments",
	ser({ protection = 4 }))
local ench_back = smp_items.stack_from_key(smp_items.key(ench_box, "M2"))
ok(ench_back ~= nil, "an enchanted box rebuilds")
eq(smp_items.ench_of(ench_back).protection, 4,
	"enchantments survive the M2 round-trip")

----------------------------------------------------------------------
-- The refusals
----------------------------------------------------------------------

print("--- rebuild refusals ---")
ok(smp_items.stack_from_key("m2|" .. ITEM .. "||0|0|deadbeef|0") == nil,
	"a legacy one-way contents hash cannot be rebuilt")
ok(smp_items.stack_from_key("m2|" .. ITEM .. "||0|1||0") == nil,
	"named == 1 cannot be rebuilt (the name text is not in the key)")
ok(smp_items.stack_from_key("m1|" .. ITEM .. "||0") ~= nil,
	"a plain M1 key still rebuilds")
ok(smp_items.stack_from_key("m0|" .. ITEM) ~= nil,
	"a plain M0 key still rebuilds")
ok(smp_items.stack_from_key("m1|mcl_core:absent||0") == nil,
	"an unknown item cannot be rebuilt")
ok(smp_items.stack_from_key("not-a-key") == nil, "a malformed key is refused")

-- matches() still compares opaquely and correctly.
local full = box_with("compressed")
local full_key = smp_items.key(full, "M2")
ok(smp_items.matches(full, full_key, "M2"), "matches() accepts the same stack")
ok(not smp_items.matches(plain_box(), full_key, "M2"), "matches() rejects a plain box")

----------------------------------------------------------------------
-- The in-mod suite (AGENTS step 7: mods/smp_items/test.lua)
----------------------------------------------------------------------

print("== in-game test suite (mods/smp_items/test.lua) ==")
do
	local chunk, lerr = loadfile(MODS .. "/smp_items/test.lua")
	ok(chunk ~= nil, "smp_items/test.lua loads: " .. tostring(lerr))
	if chunk then
		local good, res = pcall(chunk)
		ok(good, "smp_items/test.lua runs: " .. tostring(res))
		if good and type(res) == "table" then
			eq(res.failed, 0, "in-mod suite has no failures (" ..
				tostring(res.passed) .. " passed)")
			for _, l in ipairs(res.lines or {}) do print("  " .. l) end
		end
	end
end

----------------------------------------------------------------------
print(string.format("passed=%d failed=%d", passed, failed))
if failed > 0 then
	print("TEST_ITEMS FAILED")
	os.exit(1)
end
print("ALL OK")
