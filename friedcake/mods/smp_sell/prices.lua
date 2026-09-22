-- FriedcakeSMP — smp_sell/prices.lua
--
-- Reloadable base-price table (f02 §4.9, §7 `sell.base_prices`).
--
-- Prices are INTEGER CENTS everywhere (AGENTS.md hard rule 6). The shipped
-- defaults live in prices_default.lua; operators override them with a file
-- in the world directory (see below) and reload with `/smp reload`.
--
-- Alias handling matters: Mineclonia registers a lot of items under an alias
-- (`mcl_walls:cobble` -> `mcl_walls:cobble_short_pillar`,
-- `mcl_core:wood` -> `mcl_trees:wood_oak`). A stack's name is the RESOLVED
-- one, so every configured key is normalised through the alias table on
-- load. Operators may write either form.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local items = ...   -- dofile'd with the items module as the single argument

local P = {}

local DEFAULT_FILE = "smp_sell_prices.lua"   -- in the world directory

----------------------------------------------------------------------
-- Table assembly
----------------------------------------------------------------------

local defaults = {}
local overrides = {}
local lookup = {}          -- resolved itemstring -> cents (never negative)
local override_path = nil
local override_err = nil

local function load_defaults()
	local modpath = core.get_modpath("smp_sell")
	if not modpath then return {} end
	local chunk, err = loadfile(modpath .. "/prices_default.lua")
	if not chunk then
		core.log("error", "[smp_sell] cannot load prices_default.lua: " .. tostring(err))
		return {}
	end
	local ok, t = pcall(chunk)
	if not ok or type(t) ~= "table" then
		core.log("error", "[smp_sell] prices_default.lua did not return a table")
		return {}
	end
	return t
end

-- Accept `1234` (cents), `"$12.34"`, or `{ cents = 1234 }` / `{ dollars = 12.34 }`.
-- Returns integer cents, or nil when the entry means "not sellable".
local function to_cents(v)
	if v == nil or v == false then return nil end
	if type(v) == "table" then
		if v.cents ~= nil then return to_cents(v.cents) end
		if v.dollars ~= nil then
			local d = tonumber(v.dollars)
			if not d or d ~= d or d < 0 then return nil end
			return math.floor(d * 100 + 0.5)
		end
		return nil
	end
	if type(v) == "string" then
		-- Operators writing "$12.34" get the shared parser, so every suffix
		-- form in spec/shared/00-conventions.md §0.6 is accepted.
		local cents = smp_core.parse_amount(v)
		if not cents or cents <= 0 then return nil end
		return cents
	end
	local n = tonumber(v)
	if not n or n ~= n or n == math.huge or n < 0 then return nil end
	return math.floor(n + 0.5)
end
P.to_cents = to_cents

local function rebuild()
	lookup = {}
	local function absorb(src)
		for k, v in pairs(src) do
			if type(k) == "string" and k ~= "" then
				local cents = to_cents(v)
				local resolved = items.resolve_name(k)
				if cents and cents > 0 then
					lookup[resolved] = cents
					if k ~= resolved then lookup[k] = cents end
				else
					-- 0 / false / unparsable removes the item from the set.
					lookup[resolved] = false
					lookup[k] = false
				end
			end
		end
	end
	absorb(defaults)
	absorb(overrides)
end

local function load_overrides()
	local path = override_path
	if not path then
		local worldpath = core.get_worldpath and core.get_worldpath()
		if worldpath then path = worldpath .. "/" .. DEFAULT_FILE end
	end
	if not path then
		overrides = {}
		return 0
	end
	local f = io.open(path, "r")
	if not f then
		overrides = {}          -- no override file is normal
		override_err = nil
		return 0
	end
	f:close()
	local chunk, err = loadfile(path)
	if not chunk then
		overrides = {}
		override_err = tostring(err)
		core.log("error", "[smp_sell] cannot load price override " .. path .. ": " .. override_err)
		return 0
	end
	local ok, t = pcall(chunk)
	if not ok or type(t) ~= "table" then
		overrides = {}
		override_err = "did not return a table"
		core.log("error", "[smp_sell] price override " .. path .. " " .. override_err)
		return 0
	end
	overrides = t
	override_err = nil
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	core.log("action", "[smp_sell] loaded " .. n .. " price override(s) from " .. path)
	return n
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Strip a canonical-key prefix. `smp_items` renders an M0 key as
-- "m0|<name>" (owner: f04), and f04's `smp_orders.worth_of` calls
-- `smp_sell.base_price("m0|" .. itemstring)`. Bare itemstrings — the form
-- f02 §5 stores in the history and the ledger — are accepted unchanged.
local function strip_prefix(key)
	if type(key) ~= "string" then return nil end
	key = key:match("^m0|(.+)$") or key
	if key == "" then return nil end
	return key
end

-- Base price in cents for an item key, or nil when the item is not sellable.
function P.base_price(key)
	key = strip_prefix(key)
	if not key then return nil end
	local cents = lookup[key]
	if cents == nil then
		-- Try the resolved name (a stack's name is always resolved; a
		-- configured key may not be, and vice versa).
		cents = lookup[items.resolve_name(key)]
	end
	if type(cents) ~= "number" or cents <= 0 then return nil end
	return cents
end

-- Unit value actually paid by the server: base_price * sell.multiplier.
-- Integer cents. Rounding is to the nearest cent (PROPOSED — f02 §10 V-89;
-- §0.7 only pins rounding for fees).
function P.unit_value(key, multiplier)
	local base = P.base_price(key)
	if not base then return nil end
	multiplier = tonumber(multiplier) or 1
	if multiplier ~= multiplier or multiplier < 0 then multiplier = 1 end
	return math.floor(base * multiplier + 0.5)
end

function P.count()
	local n = 0
	for _, v in pairs(lookup) do
		if type(v) == "number" then n = n + 1 end
	end
	return n
end

function P.status()
	return {
		prices = P.count(),
		override_path = override_path,
		override_error = override_err,
	}
end

-- Re-read the override file and rebuild. Called at start-up, from
-- `core.register_on_mods_loaded` (aliases are only complete by then) and by
-- the wrapped `/smp reload`.
function P.reload(new_path)
	if new_path ~= nil then override_path = (new_path ~= "") and new_path or nil end
	defaults = load_defaults()
	load_overrides()
	rebuild()
	return P.count()
end

-- Used by the dev tests and by /worth's argument resolver.
function P.all()
	local out = {}
	for k, v in pairs(lookup) do
		if type(v) == "number" then out[k] = v end
	end
	return out
end

return P
