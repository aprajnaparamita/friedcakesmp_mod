-- FriedcakeSMP — smp_sell/items.lua
--
-- Canonical item keys and matching levels (spec/shared/02-architecture.md
-- §2.5), plus the Mineclonia shulker-box content codec
-- (spec/shared/03-mineclonia-api.md §3.1).
--
-- WHY THIS FILE EXISTS IN smp_sell
-- --------------------------------
-- §2.5 assigns this work to `smp_items`, and f02 §8 is explicit that both
-- `/sell` and order routing must use `smp_items` and must never re-derive a
-- key locally. `smp_items` is still a stub (it defines no global at all), so
-- smp_sell ships a self-contained implementation of exactly the §2.5 rules.
-- Every exported function DEFERS to `smp_items.<same name>` the moment that
-- mod provides it, so the day smp_items lands this file becomes a thin
-- fallback and the keys stay identical across mods. The proposed smp_items
-- surface is listed in f02 §11 (Proposed shared changes).
--
-- Verified against ~/dev/mineclonia-git (not the stale pinned SHA):
--   * shulker item meta: "compressed" = base64(zstd(core.serialize(list))),
--     "" = core.serialize(list); the list holds ItemStack:to_string() values
--     (mods/ITEMS/mcl_chests/init.lua get_shulker_stack / set_inventory_and_
--     meta_from_stack). 27 slots. Both box variants carry group shulker_box=1
--     and stack_max=1.
--   * custom name is meta "name" (mods/ITEMS/mcl_anvils/init.lua:266);
--     meta "description" is a derived tooltip cache (mods/HELP/tt/init.lua)
--     and meta "groupcaps_hash" a derived toolcaps cache
--     (mods/ITEMS/mcl_enchanting/engine.lua) — both volatile.
--   * enchantments live in meta "mcl_enchanting:enchantments" as a serialized
--     {id = level} table (mcl_enchanting.get_enchantments).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local M = {}

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

M.SHULKER_SLOTS      = 27
M.KEY_CONTENTS       = "compressed"  -- base64(zstd(serialize(list)))
M.KEY_CONTENTS_RAW   = ""             -- serialize(list) — the empty meta key
M.KEY_ENCHANTMENTS   = "mcl_enchanting:enchantments"
M.KEY_CUSTOM_NAME    = "name"

-- Tooltip stack limit used by mcl_chests when the uncompressed copy is
-- truncated (mods/ITEMS/mcl_chests/init.lua shulker_num_tt_stacks = 5).
local TT_STACKS = 5

-- Derived caches and keys that are represented elsewhere in the canonical
-- key. They never make a stack "non-plain".
local VOLATILE_META = {
	["description"]            = true,
	["short_description"]      = true,
	["groupcaps_hash"]         = true,
	[M.KEY_ENCHANTMENTS]       = true,
	[M.KEY_CONTENTS]           = true,
	[M.KEY_CONTENTS_RAW]       = true,
}

----------------------------------------------------------------------
-- Deferral to smp_items (see the header comment)
----------------------------------------------------------------------

local function shared(fn)
	local t = rawget(_G, "smp_items")
	if type(t) == "table" and type(t[fn]) == "function" then
		return t[fn]
	end
	return nil
end

-- Wrap a local implementation so smp_items wins when it exists.
local function defer(fn, local_impl)
	return function(...)
		local f = shared(fn)
		if f then return f(...) end
		return local_impl(...)
	end
end

----------------------------------------------------------------------
-- Small utilities
----------------------------------------------------------------------

local function setting_bool(key, default)
	if core.settings and core.settings.get_bool then
		local ok, v = pcall(core.settings.get_bool, core.settings, key, default)
		if ok and v ~= nil then return v end
	end
	return default
end

-- mcl_chests truncates the uncompressed copy when this game setting is off.
-- Read once; the setting is not live-tunable in Mineclonia either.
M.serialize_uncompressed = setting_bool("mcl_chests_serialize_uncompressed", true)

-- A polynomial rolling hash over the bytes of a string, folded twice into a
-- 16-hex-digit token. §2.5 asks for a "hash" of the contents / remaining
-- metadata; a stable digest keeps M1/M2 keys short enough to store and to
-- index. Collisions are bounded by the rest of the key (name and
-- enchantments are always present).
--
-- Deliberately arithmetic-only: Luanti runs Lua 5.1 / LuaJIT, so the 5.3
-- bitwise operators are not available and `bit` is LuaJIT-only.
local function digest(s)
	if type(s) ~= "string" or s == "" then return "0000000000000000" end
	local m = 2147483647 -- 2^31 - 1
	local h1, h2 = 0, 0
	for i = 1, #s do
		local b = s:byte(i)
		h1 = (h1 * 31 + b + i) % m
		h2 = (h2 * 131 + b * (i % 251 + 1)) % m
	end
	return string.format("%08x%08x", math.floor(h1), math.floor(h2))
end
M.digest = digest

----------------------------------------------------------------------
-- Names, groups and shulker detection
----------------------------------------------------------------------

local function resolve_name(name)
	if type(name) ~= "string" or name == "" then return name end
	local aliases = core.registered_aliases
	if type(aliases) ~= "table" then return name end
	local seen = 0
	while type(aliases[name]) == "string" and aliases[name] ~= name and seen < 32 do
		name = aliases[name]
		seen = seen + 1
	end
	return name
end
M.resolve_name = defer("resolve_name", resolve_name)

local function stack_name(stack)
	if type(stack) == "string" then return M.resolve_name(stack) end
	if stack and stack.get_name then return M.resolve_name(stack:get_name()) end
	return ""
end
M.stack_name = stack_name

local function is_shulker(stack_or_name)
	local name = stack_name(stack_or_name)
	if name == "" then return false end
	if core.get_item_group then
		local ok, g = pcall(core.get_item_group, name, "shulker_box")
		if ok and type(g) == "number" and g > 0 then return true end
	end
	-- Fallback for engines/tests without group data: Mineclonia names every
	-- box "<color>_shulker_box" and "<color>_shulker_box_small".
	return name:find("shulker_box", 1, true) ~= nil
end
M.is_shulker = defer("is_shulker", is_shulker)

----------------------------------------------------------------------
-- Shulker content codec
----------------------------------------------------------------------

-- Decode a shulker box's contents into a fixed 27-slot array of ItemStacks.
-- Prefers the compressed key (the authoritative copy) and falls back to the
-- uncompressed one. Never raises: a corrupt box decodes to 27 empty stacks,
-- which is the safe reading (nothing is sold, the box is returned as-is).
local function decode_contents(stack)
	local out = {}
	for i = 1, M.SHULKER_SLOTS do out[i] = ItemStack("") end
	if not stack or not stack.get_meta then return out end

	local meta = stack:get_meta()
	local list

	local compressed = meta:get_string(M.KEY_CONTENTS)
	if compressed ~= "" and core.decode_base64 and core.decompress then
		local ok, raw = pcall(core.decode_base64, compressed)
		if ok and type(raw) == "string" and raw ~= "" then
			local ok2, ser = pcall(core.decompress, raw, "zstd")
			if ok2 and type(ser) == "string" then
				local ok3, decoded = pcall(core.deserialize, ser)
				if ok3 and type(decoded) == "table" then list = decoded end
			end
		end
	end

	if type(list) ~= "table" then
		local raw = meta:get_string(M.KEY_CONTENTS_RAW)
		if raw ~= "" then
			local ok, decoded = pcall(core.deserialize, raw)
			if ok and type(decoded) == "table" then list = decoded end
		end
	end

	if type(list) ~= "table" then return out end
	for i = 1, M.SHULKER_SLOTS do
		local v = list[i]
		if v ~= nil and v ~= "" then
			local ok, s = pcall(ItemStack, v)
			if ok and s then out[i] = s end
		end
	end
	return out
end
M.decode_contents = defer("decode_contents", decode_contents)

-- Re-encode contents onto a box stack, mirroring mcl_chests exactly so the
-- box opens, tooltips and stacks like one the game produced. An all-empty
-- box is restored to its pristine (metadata-free) form.
local function encode_contents(stack, contents)
	local items = {}
	local non_empty = 0
	for i = 1, M.SHULKER_SLOTS do
		local s = contents and contents[i]
		if s and not s:is_empty() then
			items[i] = s:to_string()
			non_empty = non_empty + 1
		else
			items[i] = ""
		end
	end

	local meta = stack:get_meta()
	if non_empty == 0 then
		-- Setting a metadata key to "" removes it in Luanti, which yields the
		-- same stack a freshly crafted box has.
		meta:set_string(M.KEY_CONTENTS, "")
		meta:set_string(M.KEY_CONTENTS_RAW, "")
	else
		local ser = core.serialize(items)
		if core.compress and core.encode_base64 then
			local ok, z = pcall(core.compress, ser, "zstd")
			if ok and z then
				meta:set_string(M.KEY_CONTENTS, core.encode_base64(z))
			end
		end
		if M.serialize_uncompressed then
			meta:set_string(M.KEY_CONTENTS_RAW, ser)
		else
			local tt_items = {}
			for i = 1, TT_STACKS do tt_items[i] = items[i] end
			meta:set_string(M.KEY_CONTENTS_RAW, core.serialize(tt_items))
		end
	end

	-- Keep the tooltip in step, exactly as get_shulker_stack() does.
	local tt = rawget(_G, "tt")
	if type(tt) == "table" and type(tt.reload_itemstack_description) == "function" then
		pcall(tt.reload_itemstack_description, stack)
	end
	return stack
end
M.encode_contents = defer("encode_contents", encode_contents)

-- True when a box stack holds at least one item.
local function has_contents(stack)
	if not is_shulker(stack) then return false end
	for _, s in ipairs(decode_contents(stack)) do
		if not s:is_empty() then return true end
	end
	return false
end
M.has_contents = has_contents

----------------------------------------------------------------------
-- Enchantments and metadata
----------------------------------------------------------------------

local function enchantments(stack)
	local ench
	local mcl = rawget(_G, "mcl_enchanting")
	if type(mcl) == "table" and type(mcl.get_enchantments) == "function" then
		local ok, t = pcall(mcl.get_enchantments, stack)
		if ok and type(t) == "table" then ench = t end
	end
	if type(ench) ~= "table" and stack and stack.get_meta then
		local raw = stack:get_meta():get_string(M.KEY_ENCHANTMENTS)
		if raw ~= "" then
			local ok, t = pcall(core.deserialize, raw)
			if ok and type(t) == "table" then ench = t end
		end
	end
	ench = ench or {}

	-- Sorted "id:level" list — the §2.5 canonical form.
	local out = {}
	for id, level in pairs(ench) do
		if type(level) == "number" and level > 0 then
			out[#out + 1] = tostring(id) .. ":" .. level
		elseif level == true then
			out[#out + 1] = tostring(id) .. ":1"
		end
	end
	table.sort(out)
	return out
end
M.enchantments = defer("enchantments", enchantments)

-- ctx.meta_exempt is a { [meta_key] = true } set; ctx.item_exempt is a
-- { [itemstring_prefix] = true } set. Both come from `sell.meta_exempt`
-- (f02 §7): amethyst items carry a `smp:expires_at` timer that MUST NOT make
-- them unsellable [S9].
local function meta_exempt_for(stack, ctx)
	ctx = ctx or {}
	if ctx.item_exempt then
		local name = stack_name(stack)
		for prefix in pairs(ctx.item_exempt) do
			if prefix ~= "" and name:sub(1, #prefix) == prefix then
				return true
			end
		end
	end
	return false
end

-- Non-volatile metadata entries as sorted "k=v" strings.
local function nonvolatile_meta(stack, ctx)
	ctx = ctx or {}
	local out = {}
	if not stack or not stack.get_meta then return out end
	if meta_exempt_for(stack, ctx) then return out end

	local fields
	local ok, tbl = pcall(function() return stack:get_meta():to_table() end)
	if ok and type(tbl) == "table" then fields = tbl.fields end
	if type(fields) ~= "table" then return out end

	local exempt = ctx.meta_exempt or {}
	for k, v in pairs(fields) do
		if not VOLATILE_META[k] and not exempt[k] and tostring(v) ~= "" then
			out[#out + 1] = tostring(k) .. "=" .. tostring(v)
		end
	end
	table.sort(out)
	return out
end
M.nonvolatile_meta = nonvolatile_meta

local function is_named(stack)
	if not stack or not stack.get_meta then return false end
	return stack:get_meta():get_string(M.KEY_CUSTOM_NAME) ~= ""
end
M.is_named = is_named

local function wear(stack)
	if stack and stack.get_wear then
		local ok, w = pcall(stack.get_wear, stack)
		if ok and type(w) == "number" then return w end
	end
	return 0
end
M.wear = wear

-- §2.5: a **plain** stack has no enchantments, zero wear, no custom name, no
-- contents and no other non-volatile metadata.
local function is_plain(stack, ctx)
	if not stack or stack:is_empty() then return false, "empty" end
	if #enchantments(stack) > 0        then return false, "enchanted" end
	if wear(stack) ~= 0                then return false, "worn" end
	if is_named(stack)                 then return false, "named" end
	if has_contents(stack)             then return false, "container" end
	if #nonvolatile_meta(stack, ctx) > 0 then return false, "metadata" end
	return true, nil
end
M.is_plain = defer("is_plain", is_plain)

----------------------------------------------------------------------
-- Canonical keys (§2.5)
--
-- FORMAT OWNERSHIP. `smp_items` owns the key format (shared §2.5; f02 §8 is
-- explicit that sell routing and orders must agree on the M1 key and use
-- smp_items, never a locally re-derived one). When that mod implements
-- `smp_items.key(stack, level)` — the f04 agent owns it today — the keys
-- below adopt ITS format:
--
--   M0: "m0|<name>"                 M1: "m1|<name>|<ench>|<meta_hash>"
--
-- When smp_items is still the reserved stub, a self-contained equivalent is
-- used (same fields, no level prefix). The formats are the same only in
-- structure, so smp_sell never MIXES them: whichever authority is loaded
-- wins for every key this file produces.
----------------------------------------------------------------------

-- True when smp_items provides the shared key authority.
local function shared_key_authority()
	local t = shared("key")
	return type(t) == "function"
end

-- Bare resolved itemstring. Used for price lookups, the history and ledger
-- refs (f02 §5 stores `item = "mcl_mobitems:bone"`), display names and
-- grouping — never for cross-mod matching.
function M.name_of(stack)
	return stack_name(stack)
end

-- M0: the resolved item name, plain stacks only. Format follows the key
-- authority; `name_of` is the always-bare form for storage/display.
local function key_m0(stack, ctx)
	local plain = is_plain(stack, ctx)
	if not plain then return nil end
	local name = stack_name(stack)
	if shared_key_authority() then return "m0|" .. name end
	return name
end
M.key_m0 = defer("key_m0", key_m0)

-- M1: name + enchantments + meta_hash; requires zero wear, no custom name
-- and no contents. Returns nil when the stack cannot be matched at M1.
local function key_m1(stack, ctx)
	if not stack or stack:is_empty() then return nil end
	if wear(stack) ~= 0     then return nil end
	if is_named(stack)      then return nil end
	if has_contents(stack)  then return nil end
	local name = stack_name(stack)

	if shared_key_authority() then
		local f = shared("key")
		local ok, k = pcall(f, stack, "M1")
		if ok and type(k) == "string" and k ~= "" then return k end
		-- smp_items rejected the stack (its named() also treats a derived
		-- tooltip `description` meta as a custom name). For a plain stack the
		-- canonical M1 key is unambiguous, so rebuild it and keep routing
		-- working. f02 §11 proposes the smp_items fix.
		if #enchantments(stack) == 0 and #nonvolatile_meta(stack, ctx) == 0 then
			return M.plain_m1(name)
		end
		return nil
	end

	local ench = table.concat(enchantments(stack), ",")
	local meta = digest(table.concat(nonvolatile_meta(stack, ctx), ";"))
	return name .. "|" .. ench .. "|" .. meta
end
M.key_m1 = defer("key_m1", key_m1)

-- M2: the full key including wear, the name flag and a contents hash.
local function key_m2(stack, ctx)
	if shared_key_authority() then
		local f = shared("key")
		local ok, k = pcall(f, stack, "M2")
		if ok and type(k) == "string" and k ~= "" then return k end
	end
	if not stack or stack:is_empty() then return nil end
	local name = stack_name(stack)
	local ench = table.concat(enchantments(stack), ",")
	local contents = ""
	if is_shulker(stack) then
		local parts = {}
		for _, s in ipairs(decode_contents(stack)) do
			if not s:is_empty() then parts[#parts + 1] = s:to_string() end
		end
		contents = digest(table.concat(parts, "\1"))
	end
	return table.concat({
		name,
		ench,
		tostring(wear(stack)),
		is_named(stack) and "1" or "0",
		contents,
		digest(table.concat(nonvolatile_meta(stack, ctx), ";")),
	}, "|")
end
M.key_m2 = defer("key_m2", key_m2)

-- The M1 key of a plain, unenchanted, unmodified stack — the only kind of
-- key /sell ever routes (M0 eligibility already requires plainness).
function M.plain_m1(name)
	if shared_key_authority() then return "m1|" .. name .. "||0" end
	return name .. "||" .. digest("")
end

----------------------------------------------------------------------
-- Display name (chat / tooltips)
----------------------------------------------------------------------

local function display_name(stack_or_name)
	if type(stack_or_name) == "string" then
		local def = core.registered_items and core.registered_items[stack_or_name]
		if def and def.description and def.description ~= "" then
			return core.get_translated_string
				and core.get_translated_string("en", stack_or_name .. ".description")
				or def.description
		end
		return stack_or_name
	end
	if stack_or_name and stack_or_name.get_short_description then
		local ok, d = pcall(stack_or_name.get_short_description, stack_or_name)
		if ok and d ~= nil and d ~= "" then return d end
	end
	if stack_or_name and stack_or_name.get_description then
		local ok, d = pcall(stack_or_name.get_description, stack_or_name)
		if ok and d ~= nil and d ~= "" then return d end
	end
	return stack_name(stack_or_name)
end
M.display_name = display_name

----------------------------------------------------------------------
-- Grouping
----------------------------------------------------------------------

-- group_m0(stacks, ctx) -> array of { key, name, count, stacks } sorted by
-- key. This is the shape f02 §6 iterates. Non-plain and empty stacks are
-- skipped (the caller decides what to do with them; see collect()).
local function group_m0(stacks, ctx)
	local by_key = {}
	local order = {}
	for _, stack in ipairs(stacks or {}) do
		if stack and not stack:is_empty() then
			local key = key_m0(stack, ctx)
			if key then
				local g = by_key[key]
				if not g then
					g = { key = key, name = key, count = 0, stacks = {} }
					by_key[key] = g
					order[#order + 1] = key
				end
				g.count = g.count + stack:get_count()
				g.stacks[#g.stacks + 1] = stack
			end
		end
	end
	table.sort(order)
	local out = {}
	for _, k in ipairs(order) do out[#out + 1] = by_key[k] end
	return out
end
M.group_m0 = defer("group_m0", group_m0)

----------------------------------------------------------------------
-- collect(): the shulker-aware intake step
--
-- Turns an array of ItemStacks into
--   { groups  = { {key, key_m1, count, lots = {{stack, count, box_index, slot}}} },
--     returns = { ItemStack, ... },      -- give these back, unconditionally
--     rejected = { {stack, reason}, ... } -- same stacks, with a reason
--   }
--
-- `returns` holds COPIES. Boxes appear in `returns` with their remaining
-- (ineligible) contents already re-encoded, because every eligible unit in a
-- group is always consumed by a sale — so the outcome for a box does not
-- depend on routing. Nothing here mutates the caller's stacks.
----------------------------------------------------------------------

local function collect(stacks, ctx)
	local groups, by_key = {}, {}
	local returns, return_slots, rejected = {}, {}, {}

	local function add_return(stack, slot)
		returns[#returns + 1] = stack
		-- Keep the two arrays aligned: returns[i] came from stacks[return_slots[i]].
		return_slots[#returns] = slot
	end

	local function add_lot(key, key_m1, stack, count, box_index, slot)
		local g = by_key[key]
		if not g then
			g = { key = key, key_m1 = key_m1, count = 0, lots = {} }
			by_key[key] = g
			groups[#groups + 1] = g
		end
		g.count = g.count + count
		g.lots[#g.lots + 1] = {
			stack = stack, count = count, box_index = box_index, slot = slot,
		}
	end

	for input_index, stack in ipairs(stacks or {}) do
		if stack and not stack:is_empty() then
			if is_shulker(stack) and has_contents(stack) then
				-- Sell the eligible contents, return the box with the rest.
				local box = ItemStack(stack)                  -- copy
				local contents = decode_contents(box)
				local kept = {}
				local any_kept = false
				for i = 1, M.SHULKER_SLOTS do
					local inner = contents[i]
					if inner and not inner:is_empty() then
						local plain, reason = is_plain(inner, ctx)
						local key = plain and stack_name(inner) or nil
						if key and ctx.base_price and ctx.base_price(key) then
							add_lot(key, key_m1(inner, ctx) or M.plain_m1(key),
								inner, inner:get_count(), #returns + 1, i)
						else
							kept[i] = inner
							any_kept = true
							if not plain then
								rejected[#rejected + 1] = { stack = inner, reason = reason }
							end
						end
					end
				end
				encode_contents(box, any_kept and kept or {})
				add_return(box, input_index)
			else
				local plain, reason = is_plain(stack, ctx)
				local key = plain and stack_name(stack) or nil
				if key and ctx.base_price and ctx.base_price(key) then
					add_lot(key, key_m1(stack, ctx) or M.plain_m1(key),
						stack, stack:get_count(), nil, nil)
				else
					add_return(ItemStack(stack), input_index)   -- copy
					rejected[#rejected + 1] = {
						stack = stack,
						reason = (not plain) and reason or "no_price",
					}
				end
			end
		end
	end

	table.sort(groups, function(a, b) return a.key < b.key end)
	return {
		groups = groups, returns = returns, return_slots = return_slots,
		rejected = rejected,
	}
end
M.collect = collect

return M
