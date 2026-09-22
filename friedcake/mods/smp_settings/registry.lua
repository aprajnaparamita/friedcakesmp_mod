-- FriedcakeSMP — smp_settings / registry.lua
-- Categories and settings are registered, not hard-coded, so the six
-- unopened categories can be filled in as evidence arrives (f12 §5.1).
--
--   smp_settings.register_category("chat", { title = S("Chat"), order = 1 })
--   smp_settings.register("chat.public", {
--       category = "chat",
--       label    = S("Public Chat"),
--       values   = { "ON", "OFF" },
--       default  = "ON",
--   })
--
-- A setting is three-valued where the evidence says so (f12 §3.3):
-- ON, OFF and FRIENDS_FOLLOWED (stored) / Friends/Followed (displayed).
-- The registry owns the value domain; the store never validates.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_settings.S

smp_settings.registered = {}           -- [id]        = setting def
smp_settings.categories = {}           -- [key]       = category def
smp_settings.category_keys = {}        -- ordered array of category keys
smp_settings.settings_by_category = {} -- [key]       = array of ids (registration order)

-- Display strings for the three observed values (f12 §3.3, shared/08
-- §8.4). Every value a toggle can show passes through the translator.
local VALUE_DISPLAY = {
	ON = S("ON"),
	OFF = S("OFF"),
	FRIENDS_FOLLOWED = S("Friends/Followed"),
}
smp_settings.VALUE_DISPLAY = VALUE_DISPLAY

-- Display text for one value of a setting: the def's own display map
-- wins, then the shared three, then the raw stored token.
function smp_settings.value_label(def, value)
	if type(def) == "table" and type(def.display) == "table"
	   and def.display[value] then
		return def.display[value]
	end
	if VALUE_DISPLAY[value] then return VALUE_DISPLAY[value] end
	return tostring(value)
end

function smp_settings.register_category(key, def)
	assert(type(key) == "string" and key ~= "",
		"register_category: key must be a non-empty string")
	def = def or {}
	local existing = smp_settings.categories[key]
	local cat = {
		key   = key,
		title = def.title or (existing and existing.title) or key,
		order = tonumber(def.order) or (existing and existing.order) or 99,
		seq   = existing and existing.seq or (#smp_settings.category_keys + 1),
	}
	smp_settings.categories[key] = cat
	if not existing then
		smp_settings.category_keys[#smp_settings.category_keys + 1] = key
	end
	smp_settings.settings_by_category[key] =
		smp_settings.settings_by_category[key] or {}

	-- Keep the menu order deterministic: `order` first (the observed
	-- order is 1..7), registration sequence as the tiebreaker.
	local cats = smp_settings.categories
	table.sort(smp_settings.category_keys, function(a, b)
		if cats[a].order ~= cats[b].order then
			return cats[a].order < cats[b].order
		end
		return cats[a].seq < cats[b].seq
	end)
	return cat
end

-- Categories in menu order (f12 §3.1: Chat, Notifications, PvP,
-- Visuals, Privacy, Scoreboard, General).
function smp_settings.ordered_categories()
	local out = {}
	for _, key in ipairs(smp_settings.category_keys) do
		out[#out + 1] = smp_settings.categories[key]
	end
	return out
end

-- Setting ids registered under a category, in registration order
-- (chat.lua registers them in the observed row order).
function smp_settings.settings_in(category_key)
	return smp_settings.settings_by_category[category_key] or {}
end

function smp_settings.register(id, def)
	assert(type(id) == "string" and id ~= "",
		"register: id must be a non-empty string")
	assert(type(def) == "table", "register: def must be a table")
	local cat_key = def.category
	assert(type(cat_key) == "string" and smp_settings.categories[cat_key],
		"register " .. id .. ": unknown category " .. tostring(cat_key))
	assert(type(def.label) == "string" and def.label ~= "",
		"register " .. id .. ": label must be a non-empty string")
	assert(type(def.values) == "table" and #def.values >= 1,
		"register " .. id .. ": values must be a non-empty array")

	local entry = {
		id       = id,
		category = cat_key,
		label    = def.label,
		values   = {},   -- copied: the caller's array is never aliased
		display  = {},
	}
	for i, v in ipairs(def.values) do
		assert(type(v) == "string", "register " .. id .. ": values are strings")
		entry.values[i] = v
	end

	-- A default outside the value domain is a config typo (a narrowed
	-- settings.cycle_order can drop FRIENDS_FOLLOWED): warn and fall
	-- back to the first value rather than fail the load. The dev-tests
	-- pin the shipped defaults exactly, so a code typo still fails CI.
	entry.default = def.default or entry.values[1]
	if not smp_settings.index_of(entry.values, entry.default) then
		core.log("warning", "[smp_settings] default " .. tostring(entry.default)
			.. " for " .. id .. " is not in its value list; using "
			.. entry.values[1])
		entry.default = entry.values[1]
	end

	local display = def.display or {}
	for _, v in ipairs(entry.values) do
		entry.display[v] = display[v] or VALUE_DISPLAY[v] or v
	end

	smp_settings.registered[id] = entry
	local list = smp_settings.settings_by_category[cat_key]
	for i, existing in ipairs(list) do
		if existing == id then return entry end -- re-register: replace only
	end
	list[#list + 1] = id
	return entry
end
