-- FriedcakeSMP — smp_items
-- Canonical item keys and matching levels.
-- Implements spec/shared/02-architecture.md §2.5 (normative).
--
-- This file was a reserved stub; f04 (orders) is the first feature that
-- needs M1 matching (T8: an unenchanted helmet must not fill an
-- enchanted-helmet order), so f04 fills it in. The contract below is
-- SHARED: f02 (/sell routing), f03 (auction), f05 (Quick Buy) must use
-- these functions and must not roll their own keys.
--
-- Key formats (PROPOSED, stable within the mod set):
--   M0: "m0|<name>"
--   M1: "m1|<name>|<ench>|<meta_hash>"
--   M2: "m2|<name>|<ench>|<wear>|<named>|<contents>|<meta_hash>"
-- where <ench> is a sorted "id:level,id:level" list ("" when unenchanted),
-- <contents> is a hash of shulker contents ("" when none) and <meta_hash>
-- is a hash of the remaining non-volatile metadata ("0" when empty).
--
-- Matching levels (shared §2.5):
--   M0  name, plain stacks only          (/sell base prices, /worth)
--   M1  name, ench and meta_hash; requires zero wear, no custom name and
--       no contents                      (orders, sell routing, Quick Buy)
--   M2  the full key                     (auction display, grouping, search)
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_items = {}

----------------------------------------------------------------------
-- Meta keys that do NOT count as "other non-volatile metadata" because
-- they are covered by dedicated parts of the key (or are volatile):
----------------------------------------------------------------------
local VOLATILE_META = {
	["mcl_enchanting:enchantments"] = true, -- covered by <ench>
	["name"] = true,                        -- custom name: covered by <named>
	["description"] = true,                 -- custom description: same
	["wear"] = true,                        -- covered by <wear>
}

-- Shulker content keys (shared/03-mineclonia-api.md): zstd base64 under
-- "compressed", or a serialized list under "".
local CONTENTS_KEYS = { "compressed", "" }

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

-- Deterministic 32-bit string hash (djb2), rendered as 8 hex digits.
-- Exact under Lua doubles: h*33 stays below 2^37.
local function hash_str(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

-- Resolve aliases so "mcl_core:glass_gray" and "mcl_core:glass_grey"
-- produce the same key.
local function resolve_name(name)
	if core.registered_aliases and core.registered_aliases[name] then
		return core.registered_aliases[name]
	end
	return name
end

-- Enchantment map {id = level} for a stack. Uses mcl_enchanting when
-- present; falls back to reading the meta directly (dev-test harnesses
-- run without the engine mod).
function smp_items.ench_of(stack)
	if not stack or stack:is_empty() then return {} end
	if mcl_enchanting and mcl_enchanting.get_enchantments then
		local ok, ench = pcall(mcl_enchanting.get_enchantments, stack)
		if ok and type(ench) == "table" then return ench end
	end
	local raw = stack:get_meta():get_string("mcl_enchanting:enchantments")
	if raw == "" then return {} end
	local t = core.deserialize and core.deserialize(raw)
	return type(t) == "table" and t or {}
end

-- Sorted "id:level,..." string; "" when unenchanted. Sorted by id so key
-- identity never depends on table iteration order.
function smp_items.ench_string(ench)
	if not ench then return "" end
	local ids = {}
	for id, level in pairs(ench) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local parts = {}
	for _, id in ipairs(ids) do
		parts[#parts + 1] = id .. ":" .. tostring(ench[id])
	end
	return table.concat(parts, ",")
end

-- Shulker contents hash; "" when the stack carries no contents.
function smp_items.contents_of(stack)
	local meta = stack:get_meta()
	for _, k in ipairs(CONTENTS_KEYS) do
		local v = meta:get_string(k)
		if v ~= "" then return hash_str(k .. "=" .. v) end
	end
	return ""
end

-- Whether the stack carries a custom name. Mineclonia stores it under
-- meta "name"; newer engines also honour "description".
function smp_items.named(stack)
	local meta = stack:get_meta()
	return meta:get_string("name") ~= "" or meta:get_string("description") ~= ""
end

-- Hash of the remaining non-volatile metadata. Volatile keys (see above)
-- and shulker contents keys are excluded; everything else participates,
-- sorted by key so the hash is deterministic.
function smp_items.meta_hash(stack)
	local meta = stack:get_meta()
	local fields = meta.to_table and meta:to_table().fields or {}
	local keys = {}
	local skip_contents = {}
	for _, k in ipairs(CONTENTS_KEYS) do skip_contents[k] = true end
	for k in pairs(fields) do
		if not VOLATILE_META[k] and not skip_contents[k] then
			keys[#keys + 1] = k
		end
	end
	if #keys == 0 then return "0" end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = k .. "=" .. tostring(fields[k])
	end
	return hash_str(table.concat(parts, ";"))
end

-- A plain stack: no enchantments, zero wear, no custom name, no contents
-- and no other non-volatile metadata (shared §2.5).
function smp_items.plain(stack)
	if not stack or stack:is_empty() then return false end
	if next(smp_items.ench_of(stack)) ~= nil then return false end
	if (stack.get_wear and stack:get_wear() or 0) ~= 0 then return false end
	if smp_items.named(stack) then return false end
	if smp_items.contents_of(stack) ~= "" then return false end
	if smp_items.meta_hash(stack) ~= "0" then return false end
	return true
end

----------------------------------------------------------------------
-- Keys
----------------------------------------------------------------------

-- Canonical key of a stack at the given level, or nil when the stack
-- cannot be keyed at that level (e.g. a worn stack has no M0/M1 key).
function smp_items.key(stack, level)
	level = level or "M1"
	if not stack or stack:is_empty() then return nil end
	local name = resolve_name(stack:get_name())
	if name == "" then return nil end

	if level == "M0" then
		if not smp_items.plain(stack) then return nil end
		return "m0|" .. name
	elseif level == "M1" then
		if (stack.get_wear and stack:get_wear() or 0) ~= 0 then return nil end
		if smp_items.named(stack) then return nil end
		if smp_items.contents_of(stack) ~= "" then return nil end
		local ench = smp_items.ench_string(smp_items.ench_of(stack))
		return "m1|" .. name .. "|" .. ench .. "|" .. smp_items.meta_hash(stack)
	elseif level == "M2" then
		local ench = smp_items.ench_string(smp_items.ench_of(stack))
		local wear = (stack.get_wear and stack:get_wear() or 0)
		local named = smp_items.named(stack) and 1 or 0
		local contents = smp_items.contents_of(stack)
		return "m2|" .. name .. "|" .. ench .. "|" .. wear .. "|" .. named ..
			"|" .. contents .. "|" .. smp_items.meta_hash(stack)
	end
	return nil
end

-- Parse a key back into its parts. Returns nil for malformed keys.
function smp_items.parse_key(key)
	if type(key) ~= "string" then return nil end
	local level, rest = key:match("^(m[012])|(.*)$")
	if not level then return nil end
	local out = { level = level:upper() }
	if level == "m0" then
		out.name = rest
	elseif level == "m1" then
		local name, ench, mh = rest:match("^([^|]*)|([^|]*)|([^|]*)$")
		if not name then return nil end
		out.name, out.ench_string, out.meta_hash = name, ench, mh
	elseif level == "m2" then
		local name, ench, wear, named, contents, mh =
			rest:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
		if not name then return nil end
		out.name, out.ench_string, out.wear = name, ench, tonumber(wear) or 0
		out.named = named == "1"
		out.contents, out.meta_hash = contents, mh
	end
	-- Rebuild the enchantment map for convenience.
	out.ench = {}
	if out.ench_string and out.ench_string ~= "" then
		for id, lvl in out.ench_string:gmatch("([^,]+):(%d+)") do
			out.ench[id] = tonumber(lvl)
		end
	end
	return out
end

-- True when the stack's key at `level` equals `key`.
function smp_items.matches(stack, key, level)
	if not key then return false end
	local parsed = smp_items.parse_key(key)
	if not parsed then return false end
	level = level or parsed.level
	local k = smp_items.key(stack, level)
	return k ~= nil and k == key
end

----------------------------------------------------------------------
-- Display and reconstruction
----------------------------------------------------------------------

-- Singular display name of an itemstring (first line of the engine
-- description). Falls back to the itemstring itself.
function smp_items.display_name(itemstring)
	if not itemstring or itemstring == "" then return "?" end
	local stack = ItemStack(itemstring)
	local desc = stack.get_description and stack:get_description() or nil
	if not desc or desc == "" then
		local def = core.registered_items and core.registered_items[resolve_name(itemstring)]
		desc = def and def.description or itemstring
	end
	-- Descriptions can be multi-line; the observed UI uses the first line.
	return (desc:match("^[^\n]*"))
end

-- Reconstruct a stack from an M0/M1 key: the plain item plus its
-- enchantments. Returns nil for M2 keys (wear/name/contents are not
-- reconstructible) or unknown items.
-- Orders use this to convert virtual counts into stacks at collection
-- time (f04 §4.9, T12).
function smp_items.stack_from_key(key)
	local parsed = smp_items.parse_key(key)
	if not parsed or parsed.level == "M2" then return nil end
	local name = parsed.name
	if core.registered_items and not core.registered_items[name] then
		return nil
	end
	local stack = ItemStack(name)
	if next(parsed.ench) ~= nil then
		if mcl_enchanting and mcl_enchanting.set_enchantments then
			mcl_enchanting.set_enchantments(stack, parsed.ench)
		else
			stack:get_meta():set_string("mcl_enchanting:enchantments",
				core.serialize and core.serialize(parsed.ench) or "")
		end
	end
	return stack
end

core.log("action", "[smp_items] loaded: M0/M1/M2 keys per shared §2.5 (owner: f04 for now)")
