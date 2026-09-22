-- FriedcakeSMP — smp_ah/keys.lua
--
-- Canonical item keys and matching levels (M0/M1/M2) for the auction house.
-- Implements spec/shared/02-architecture.md §2.5. `smp_items` now ships the
-- shared implementation (filled by f04), and this file DELEGATES `key` and
-- `matches` to it at load time (`foreign()`), so there is one canonical
-- keying across the mod set. The fallback below only runs when `smp_items`
-- is absent.
--
-- §2.5, verbatim:
--
--   The canonical key of a stack consists of:
--     * `name`: registered name after alias resolution;
--     * `ench`: sorted `id:level` list from `mcl_enchanting.get_enchantments`;
--     * `wear`: raw wear value (0 means pristine);
--     * `named`: whether the stack carries a custom name;
--     * `contents`: hash of shulker contents, if any;
--     * `meta_hash`: hash of the remaining non-volatile metadata.
--
--   | Level | Compares                                                      |
--   | M0    | `name`, plain stacks only                                     |
--   | M1    | `name`, `ench` and `meta_hash`; requires zero wear, no custom  |
--   |       | name and no contents                                          |
--   | M2    | The full key including wear, name flag and contents            |
--
-- Key strings are canonical, self-describing and versioned (`m0|`, `m1|`,
-- `m2|`) so they can be stored, indexed and compared across restarts without
-- a decode table. Field separators (`|`, `,`, `:`) never occur inside a
-- registered item name, an enchantment id, or a hex digest.
--
-- Format (shared with the other economy mods, so keys compare across f02/f03/
-- f04/f05):
--
--   M0: "m0|<name>"
--   M1: "m1|<name>|<ench>|<meta_hash>"
--   M2: "m2|<name>|<ench>|<wear>|<named>|<contents>|<meta_hash>"
--
-- with `<ench>` a sorted "id:level,..." list ("" when unenchanted),
-- `<named>` 0/1 and `<contents>` a hash ("" when the stack holds none).
--
-- **One keying per mod set.** `smp_items` is the shared owner of §2.5 (filled
-- by f04). This file ships a fallback implementation for headless use, and
-- `keys.key` / `keys.matches` DELEGATE to `smp_items` when it is loaded, so
-- every mod in the set derives identical keys. The helpers `smp_items` does
-- not provide (`equals`, `parts`, `display`, `parse`) stay local to f03.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_ah = smp_ah or {}

local keys = {}
smp_ah.keys = keys

keys.VERSION = 1

----------------------------------------------------------------------
-- Hashing
--
-- `core.sha1` is used when the engine provides it (Luanti >= 5.4). The
-- arithmetic fallback exists so this file can be exercised headlessly by
-- `friedcake/dev-tests/test_ah_keys.lua`, where no engine is loaded. It is a
-- 64-bit composite (djb2 + sdbm + length prefix); collision resistance is
-- not a security property here, only a stability property.
----------------------------------------------------------------------

local MOD32 = 4294967296 -- 2^32

local function djb2(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % MOD32
	end
	return string.format("%08x", h)
end

local function sdbm(s)
	local h = 0
	for i = 1, #s do
		h = (string.byte(s, i) + h * 65599) % MOD32
	end
	return string.format("%08x", h)
end

local function fallback_hash(s)
	return djb2(s) .. sdbm(s) .. string.format("%04x", #s % 65536)
end

function keys.hash(s)
	if type(s) ~= "string" then s = tostring(s) end
	if core and type(core.sha1) == "function" then
		local ok, digest = pcall(core.sha1, s)
		if ok and type(digest) == "string" and digest ~= "" then
			return digest
		end
	end
	return fallback_hash(s)
end

-- The hash of "nothing". Stored explicitly so an empty meta hash compares
-- equal across processes and backends.
keys.EMPTY_HASH = keys.hash("")

----------------------------------------------------------------------
-- Stack fields
----------------------------------------------------------------------

-- Meta keys that are derived, volatile, or already carried by another field
-- of the canonical key. Excluding them keeps two otherwise identical stacks
-- equal when only a cached/derived value differs (tt description rewrites,
-- mcl_enchanting's groupcaps cache, ...).
local VOLATILE_META = {
	[""]                             = true, -- shulker contents, uncompressed copy
	["compressed"]                   = true, -- shulker contents, zstd+base64
	["description"]                  = true, -- derived by `tt`
	["groupcaps_hash"]               = true, -- derived by mcl_enchanting
	["mcl_enchanting:enchantments"]  = true, -- carried in `ench`
	["name"]                         = true, -- carried in `named`
	["wear"]                         = true, -- carried in `wear`
}

-- Enchantment table, preferring the Mineclonia API (§2.5) and falling back
-- to the raw meta key it reads, so the file also works without the mod.
local function get_enchantments(stack)
	if mcl_enchanting and type(mcl_enchanting.get_enchantments) == "function" then
		local ok, e = pcall(mcl_enchanting.get_enchantments, stack)
		if ok and type(e) == "table" then return e end
	end
	local meta = stack:get_meta()
	local raw = meta and meta:get_string("mcl_enchanting:enchantments") or ""
	if raw == "" then return {} end
	local ok, e = pcall(core.deserialize, raw)
	if ok and type(e) == "table" then return e end
	return {}
end

-- Sorted `id:level` list plus the same information as an ordered table for
-- display (`display.ench` in f03 §5).
local function ench_parts(stack)
	local e = get_enchantments(stack)
	local ids = {}
	for id, level in pairs(e) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local joined, list = {}, {}
	for _, id in ipairs(ids) do
		local level = tonumber(e[id]) or 0
		if level > 0 then
			joined[#joined + 1] = id .. ":" .. level
			list[#list + 1] = { id = id, level = level }
		end
	end
	return table.concat(joined, ","), list
end

--- Sorted `id:level` string from an enchantment *spec* table `{id = level}`.
--
-- f05 (Quick Buy) stores entries as `{ key = <itemstring>, ench = {id=level},
-- qty }` (f05 §5) and passes `ench` to `smp_ah.cheapest_for`. The canonical
-- M1 key spells enchantments as a sorted "id:level,..." list, so this helper
-- produces the same string the key builder does (alphabetical id order,
-- positive levels only). Exposed so `cheapest_for` can build an M1-key prefix
-- from a spec without an actual ItemStack.
function keys.ench_string_from_spec(ench)
	if type(ench) ~= "table" then return "" end
	local ids = {}
	for id in pairs(ench) do ids[#ids + 1] = id end
	table.sort(ids)
	local parts = {}
	for _, id in ipairs(ids) do
		local level = tonumber(ench[id]) or 0
		if level > 0 then parts[#parts + 1] = id .. ":" .. level end
	end
	return table.concat(parts, ",")
end

-- Shulker (and other container item) contents. Mineclonia stores the
-- authoritative copy in `compressed` (base64 of zstd) and a serialized copy
-- in the legacy `""` key; the latter may be truncated to the first few
-- stacks when `mcl_chests_serialize_uncompressed` is false, so `compressed`
-- wins. spec/shared/03-mineclonia-api.md §3.1.
local CONTENTS_KEYS = { "compressed", "" }

local function contents_raw(stack)
	local meta = stack:get_meta()
	if not meta then return nil end
	for _, k in ipairs(CONTENTS_KEYS) do
		local v = meta:get_string(k)
		if v ~= "" then return k .. "=" .. v end
	end
	return nil
end

-- Hash of every non-volatile meta field, in sorted key order.
local function meta_hash_of(stack)
	local meta = stack:get_meta()
	if not meta then return keys.EMPTY_HASH end
	local fields
	if type(meta.to_table) == "function" then
		local t = meta:to_table()
		fields = t and t.fields
	end
	if type(fields) ~= "table" then
		-- Older/stubbed meta objects: fall back to key enumeration.
		fields = {}
		if type(meta.get_keys) == "function" then
			for _, k in ipairs(meta:get_keys() or {}) do
				fields[k] = meta:get_string(k)
			end
		end
	end
	local names = {}
	for k in pairs(fields) do
		if not VOLATILE_META[k] then names[#names + 1] = k end
	end
	if #names == 0 then return keys.EMPTY_HASH end
	table.sort(names)
	local parts = {}
	for i, k in ipairs(names) do
		parts[i] = k .. "=" .. tostring(fields[k])
	end
	return keys.hash(table.concat(parts, "\1"))
end

-- Registered name after alias resolution (§2.5).
local function resolved_name(stack)
	local name = stack:get_name()
	if type(name) ~= "string" or name == "" then return "" end
	if core and type(core.registered_aliases) == "table" then
		name = core.registered_aliases[name] or name
	end
	return name
end

--- Split a stack into the six canonical fields of §2.5.
--
-- @param stack ItemStack
-- @return table `{name, ench, ench_list, wear, named, contents, meta_hash, plain}`
function keys.parts(stack)
	if not stack or (type(stack.is_empty) == "function" and stack:is_empty()) then
		return nil
	end
	local ench, ench_list = ench_parts(stack)
	local wear = 0
	if type(stack.get_wear) == "function" then
		wear = tonumber(stack:get_wear()) or 0
	end
	local meta = stack:get_meta()
	local named = false
	if meta then
		named = (meta:get_string("name") or "") ~= ""
	end
	local raw_contents = contents_raw(stack)
	local contents = raw_contents and keys.hash(raw_contents) or nil
	local meta_hash = meta_hash_of(stack)
	return {
		name      = resolved_name(stack),
		ench      = ench,
		ench_list = ench_list,
		wear      = wear,
		named     = named,
		contents  = contents,
		meta_hash = meta_hash,
		-- A **plain** stack has no enchantments, zero wear, no custom name,
		-- no contents and no other non-volatile metadata (§2.5).
		plain     = (ench == "" and wear == 0 and not named
			and contents == nil and meta_hash == keys.EMPTY_HASH),
	}
end

----------------------------------------------------------------------
-- Key construction
----------------------------------------------------------------------

local function n_flag(b) return b and "1" or "0" end

--- The shared `smp_items` implementation, when one is loaded. Functions
--- installed by this file are recorded in `shim_fns`, so "foreign" means
--- "somebody else owns §2.5 and f03 must agree with them".
local shim_fns = {}

local function foreign(fn_name)
	if type(smp_items) ~= "table" then return nil end
	local fn = smp_items[fn_name]
	if type(fn) ~= "function" or shim_fns[fn] then return nil end
	return fn
end

--- Canonical key of a stack at a matching level.
--
-- Returns `nil` when the stack cannot be represented at that level: an empty
-- stack, or (for M0/M1) a stack that is not eligible — M0 requires a plain
-- stack, M1 requires zero wear, no custom name and no contents (§2.5).
-- Returning nil rather than a degraded key is deliberate: a worn or renamed
-- stack must never silently match an order or a base price.
--
-- Delegates to `smp_items.key` when a real shared implementation is loaded.
--
-- @param stack ItemStack
-- @param level "M0"|"M1"|"M2" (case-insensitive; default "M2")
-- @return string|nil
function keys.key(stack, level)
	level = keys.normalise_level(level)
	local owner = foreign("key")
	if owner then
		local ok, k = pcall(owner, stack, level)
		if ok and (k == nil or type(k) == "string") then return k end
	end
	local p = keys.parts(stack)
	if not p then return nil end
	if level == "M0" then
		if not p.plain then return nil end
		return "m0|" .. p.name
	elseif level == "M1" then
		if p.wear ~= 0 or p.named or p.contents then return nil end
		return "m1|" .. p.name .. "|" .. p.ench .. "|" .. p.meta_hash
	end
	return "m2|" .. p.name
		.. "|" .. p.ench
		.. "|" .. p.wear
		.. "|" .. n_flag(p.named)
		.. "|" .. (p.contents or "")
		.. "|" .. p.meta_hash
end

function keys.normalise_level(level)
	if type(level) ~= "string" then return "M2" end
	level = level:upper()
	if level == "M0" or level == "M1" or level == "M2" then return level end
	return "M2"
end

--- Decode a canonical key back into §2.5 fields.
--
-- An M0/M1 key is widened to the full field set (zero wear, unnamed, no
-- contents) so `keys.equals` can compare keys built at different levels.
-- The legacy `k0|`/`k1|`/`k2|` spelling (an earlier f03 build, with `e=`/`m=`
-- field prefixes) is still accepted so persisted keys survive an upgrade.
--
-- @return table|nil `{level, name, ench, wear, named, contents, meta_hash}`
function keys.parse(k)
	if type(k) ~= "string" or k == "" then return nil end
	local tag, rest = k:match("^([mk]%d)|(.*)$")
	if not tag then return nil end
	local legacy = (tag:sub(1, 1) == "k")
	local digit = tag:sub(2)
	local out = { level = nil, name = "", ench = "", wear = 0, named = false,
		contents = nil, meta_hash = keys.EMPTY_HASH }
	if digit == "0" then
		out.level, out.name = "M0", rest
	elseif digit == "1" then
		out.level = "M1"
		local pattern = legacy and "^([^|]*)|e=([^|]*)|m=(.*)$"
			or "^([^|]*)|([^|]*)|([^|]*)$"
		out.name, out.ench, out.meta_hash = rest:match(pattern)
		if not out.name then return nil end
	elseif digit == "2" then
		out.level = "M2"
		local pattern = legacy and
			"^([^|]*)|e=([^|]*)|w=(%-?%d+)|n=([01])|c=([^|]*)|m=(.*)$"
			or "^([^|]*)|([^|]*)|(%-?%d+)|([01])|([^|]*)|([^|]*)$"
		local name, ench, wear, named, contents, mh = rest:match(pattern)
		if not name then return nil end
		out.name      = name
		out.ench      = ench
		out.wear      = tonumber(wear) or 0
		out.named     = (named == "1")
		out.contents  = (contents ~= "-" and contents ~= "") and contents or nil
		out.meta_hash = mh
		if out.meta_hash == "" then out.meta_hash = keys.EMPTY_HASH end
	else
		return nil
	end
	return out
end

-- Is a parsed key eligible to match at `level`? M0 needs a plain stack, M1
-- needs zero wear, no custom name and no contents (§2.5).
local function eligible(p, level)
	if level == "M0" then
		return p.ench == "" and p.wear == 0 and not p.named
			and p.contents == nil and p.meta_hash == keys.EMPTY_HASH
	elseif level == "M1" then
		return p.wear == 0 and not p.named and p.contents == nil
	end
	return true
end

--- Level-bounded equality of two canonical keys.
--
-- Both keys are compared on exactly the fields the level covers, and both
-- must be *eligible* at that level, so `equals(m2_worn_key, m1_key, "M1")`
-- is false rather than a partial match. At M2 both keys must be M2 keys: an
-- M1 key carries no wear/contents information, so it is never "equal" at the
-- strictest level.
function keys.equals(k1, k2, level)
	level = keys.normalise_level(level)
	if type(k1) ~= "string" or type(k2) ~= "string" then return false end
	if level == "M2" and k1 == k2 then return true end
	local a, b = keys.parse(k1), keys.parse(k2)
	if not a or not b then return false end
	if not eligible(a, level) or not eligible(b, level) then return false end
	if a.name ~= b.name then return false end
	if level == "M0" then return true end
	if level == "M2" then
		if a.level ~= "M2" or b.level ~= "M2" then return false end
		return a.ench == b.ench and a.wear == b.wear and a.named == b.named
			and (a.contents or "") == (b.contents or "")
			and a.meta_hash == b.meta_hash
	end
	-- M1: name, ench and meta_hash.
	return a.ench == b.ench and a.meta_hash == b.meta_hash
end

--- Does a stack match a canonical key at a level?
--
-- This is the call `f04-orders` §6.2 makes on delivery
-- (`smp_items.matches(s, o.key, "M1")`). Delegates to a real `smp_items`
-- when one is loaded.
function keys.matches(stack, key, level)
	level = keys.normalise_level(level)
	local owner = foreign("matches")
	if owner and type(key) == "string" then
		local ok, res = pcall(owner, stack, key, level)
		if ok then return res and true or false end
	end
	local k = keys.key(stack, level)
	if not k then return false end
	return keys.equals(k, key, level)
end

--- The highest level at which a stack is representable.
-- M2 always works; M1 for unworn, unnamed, content-free stacks; M0 for plain
-- ones. Used by `/sell` style callers that want the strictest key available.
function keys.best_level(stack)
	local p = keys.parts(stack)
	if not p then return nil end
	if p.plain then return "M0" end
	if p.wear == 0 and not p.named and not p.contents then return "M1" end
	return "M2"
end

--- Display block for a listing record (f03 §5 `display`).
--
-- `lore`, `trim` and `contents` are carried for schema compatibility with
-- api.Ah [S23]; Mineclonia has no data-component lore or armour trim, and
-- shulker contents are not previewed by f03 (§3.8 "not observed").
function keys.display(stack)
	local p = keys.parts(stack)
	if not p then return nil end
	local desc
	if type(stack.get_description) == "function" then
		desc = stack:get_description()
	end
	if type(desc) ~= "string" or desc == "" then
		desc = (core and core.registered_items and core.registered_items[p.name]
			and core.registered_items[p.name].description) or p.name
	end
	-- A description may be multi-line (tool stats); the tooltip's first line
	-- is the singular display name (§4.4 rule 1).
	local first = desc:match("^[^\n]*") or desc
	return {
		name     = first,
		full     = desc,
		lore     = {},
		ench     = p.ench_list,
		trim     = nil,
		contents = p.contents and true or nil,
	}
end

----------------------------------------------------------------------
-- smp_items compatibility shim
--
-- `smp_items` is a stub (friedcake/mods/smp_items/init.lua). f03 owns the
-- minimum M1/M2 keying it needs (tools/claim-f03.md, Heads-up 1). These
-- wrappers are installed ONLY where the shared table is still empty, so the
-- eventual `smp_items` owner can replace them by loading first — `smp_items`
-- is listed above `smp_ah` in modpack.conf, so a real implementation always
-- wins. PROPOSED; see spec/features/f03-auction.md §10 and the
-- "Proposed shared changes" block at the bottom of that file.
----------------------------------------------------------------------

smp_items = smp_items or {}

local function install(name, fn)
	if type(smp_items[name]) ~= "function" then
		-- Recorded so `foreign()` above can tell our own shim from a real
		-- shared implementation (Lua functions cannot carry fields).
		shim_fns[fn] = true
		smp_items[name] = fn
	end
end

install("key",      function(stack, level) return keys.key(stack, level) end)
install("matches",  function(stack, key, level) return keys.matches(stack, key, level) end)
install("equals",   function(k1, k2, level) return keys.equals(k1, k2, level) end)
install("parts",    function(stack) return keys.parts(stack) end)
install("display",  function(stack) return keys.display(stack) end)

-- Convenience aliases on the feature table itself, so f03 code reads
-- `smp_ah.key(stack, "M2")` as the spec's §6.1 pseudocode does.
smp_ah.key     = keys.key
smp_ah.matches = keys.matches

if core and type(core.log) == "function" then
	core.log("action", "[smp_ah] keys.lua: M0/M1/M2 canonical item keys ready")
end
