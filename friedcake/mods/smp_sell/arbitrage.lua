-- FriedcakeSMP — smp_sell/arbitrage.lua
--
-- Recipe-arbitrage scan (S02, fixes/security/S02-sell.md SE-1/SE-3).
--
-- The server is a buyer that never runs out of money, so any recipe whose
-- output sells for more than its inputs is an unlimited faucet: craft, sell,
-- repeat. This module walks the LIVE registry (it needs the real engine and
-- game; the dev-test harness has no recipes) and reports every such recipe.
--
-- What "cost" means here. Each item's cost is the cheapest way to have it:
--   * its /sell unit value, when it has one (selling it is the alternative);
--   * or, lower, the cost of its cheapest recipe divided by the yield;
--   * an unpriced item with no costed recipe (logs, flowers, raw ores) has
--     NO cost, and recipes that need one are skipped. Gathering free
--     resources is income, not arbitrage; that risk is judged by hand
--     (fixes/security/S02-sell.md SE-1).
-- A violation is a recipe for a PRICED output where
--   unit_value(output) * yield  >  sum(cost(inputs)) + tolerance,
-- with tolerance = max(10 cents, 1% of the input cost): integer-cent prices
-- cannot make 9 nuggets equal 1 ingot exactly in both directions.
--
-- Cooking recipes (smelting) are reported separately as `cooking` and do
-- not count as violations or lower any cost: they burn fuel and take time,
-- so a small premium on cooked output is the intended design.
--
-- `allow` names outputs whose premium is OBSERVED on the reference server
-- (prices_default.lua header, e.g. the $7 cobblestone wall [S2]); they are
-- reported under `allowed` instead of failing.
--
-- Recipe sources: core.get_all_craft_recipes (shaped, shapeless and cooking)
-- and Mineclonia's stonecutter (`_mcl_stonecutter_recipes` on the result,
-- yield 2 for slabs and 4 for cut copper / grates, mirroring
-- mcl_stonecutter/init.lua).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local A = {}

-- Mirrors mcl_stonecutter's recipe_yield table (group -> multiplier).
local STONECUTTER_YIELD = { slab = 2, cut_copper = 4, copper_grate = 4 }

local function out_name_count(output)
	if type(output) ~= "string" or output == "" then return nil end
	local stack = ItemStack(output)
	if stack:is_empty() then return nil end
	return stack:get_name(), stack:get_count()
end

-- All recipes as { out = name, yield = n, inputs = { itemstring|group }, kind = }
local function collect_recipes()
	local list = {}
	for name in pairs(core.registered_items) do
		if name ~= "" then
			for _, r in ipairs(core.get_all_craft_recipes(name) or {}) do
				local method = r.method or r.type
				if method ~= "fuel" then
					local out, n = out_name_count(r.output)
					if out and n and n > 0 then
						local inputs = {}
						for _, it in pairs(r.items or {}) do
							if type(it) == "string" and it ~= "" then
								inputs[#inputs + 1] = it
							end
						end
						if #inputs > 0 then
							list[#list + 1] = { out = out, yield = n,
								inputs = inputs, kind = method or "normal" }
						end
					end
				end
			end
		end
	end
	for name, def in pairs(core.registered_nodes) do
		local srcs = def._mcl_stonecutter_recipes
		if type(srcs) == "table"
				and core.get_item_group(name, "not_in_creative_inventory") == 0 then
			local yield = 1
			for g, mult in pairs(STONECUTTER_YIELD) do
				if core.get_item_group(name, g) > 0 then yield = yield * mult end
			end
			for _, src in pairs(srcs) do
				if type(src) == "string"
						and core.get_item_group(src, "stonecuttable") > 0 then
					list[#list + 1] = { out = name, yield = yield,
						inputs = { src }, kind = "stonecutter" }
				end
			end
		end
	end
	return list
end

-- group name -> { item names }
local function group_members()
	local g = {}
	for name, def in pairs(core.registered_items) do
		for grp, level in pairs(def.groups or {}) do
			if level and level ~= 0 then
				g[grp] = g[grp] or {}
				g[grp][#g[grp] + 1] = name
			end
		end
	end
	return g
end

-- Scan. `value_of(name)` -> unit value in cents or nil (default:
-- smp_sell.unit_value). Returns a list of violations, worst ratio first:
--   { out, yield, kind, out_value, in_cost, gain, inputs }
function A.scan(value_of, allow)
	value_of = value_of or smp_sell.unit_value
	allow = allow or A.OBSERVED_PREMIUMS
	local recipes = collect_recipes()
	local groups = group_members()

	local cost = {}
	for name in pairs(core.registered_items) do
		local v = value_of(name)
		if v and v > 0 then cost[name] = v end
	end

	local function input_cost(it)
		local grp = it:match("^group:(.+)$")
		if not grp then
			return cost[core.registered_aliases[it] or it]
		end
		-- "group:a,b": an item must carry every listed group; the player
		-- uses the cheapest such item.
		local want = {}
		for g in grp:gmatch("[^,]+") do want[#want + 1] = g end
		local best
		for _, name in ipairs(groups[want[1]] or {}) do
			local all = true
			for i = 2, #want do
				if core.get_item_group(name, want[i]) == 0 then all = false break end
			end
			if all and cost[name] and (not best or cost[name] < best) then
				best = cost[name]
			end
		end
		return best
	end

	local function recipe_cost(r)
		local total = 0
		for _, it in ipairs(r.inputs) do
			local c = input_cost(it)
			if not c then return nil end
			total = total + c
		end
		return total
	end

	-- Fixed point: an item's cost can only fall. Bounded passes.
	for _ = 1, 25 do
		local changed = false
		for _, r in ipairs(recipes) do
			local c = r.kind ~= "cooking" and recipe_cost(r)
			if c then
				local per = c / r.yield
				if not cost[r.out] or per < cost[r.out] - 1e-9 then
					cost[r.out] = per
					changed = true
				end
			end
		end
		if not changed then break end
	end

	local out, cooking, allowed = {}, {}, {}
	for _, r in ipairs(recipes) do
		local v = value_of(r.out)
		if v and v > 0 then
			local c = recipe_cost(r)
			if c then
				local gain = v * r.yield - c
				if gain > math.max(10, c * 0.01) then
					local rec = { out = r.out, yield = r.yield, kind = r.kind,
						out_value = v * r.yield, in_cost = c, gain = gain,
						inputs = r.inputs }
					local base = core.registered_aliases[r.out] or r.out
					if r.kind == "cooking" then
						cooking[#cooking + 1] = rec
					elseif allow[r.out] or allow[base]
							or allow[(r.out:gsub("_short_pillar$", ""))] then
						allowed[#allowed + 1] = rec
					else
						out[#out + 1] = rec
					end
				end
			end
		end
	end
	local function worst_first(a, b)
		local ra, rb = a.gain / math.max(a.in_cost, 1), b.gain / math.max(b.in_cost, 1)
		if ra ~= rb then return ra > rb end
		return a.out < b.out
	end
	table.sort(out, worst_first)
	table.sort(cooking, worst_first)
	table.sort(allowed, worst_first)
	return out, #recipes, cooking, allowed
end

-- Premiums the reference server itself pays (OBSERVED, prices_default.lua
-- header): not ours to change without an integrator ruling (AGENTS.md).
A.OBSERVED_PREMIUMS = {
	["mcl_walls:cobble"] = true,   -- $7 wall vs $6 cobble [S2]
}

-- One line per violation, for logs and /smp test output.
function A.describe(v)
	return string.format("%s x%d (%s) sells %s from inputs worth %s: +%s [%s]",
		v.out, v.yield, v.kind,
		smp_core.fmt_money(v.out_value, "inline"),
		smp_core.fmt_money(math.floor(v.in_cost + 0.5), "inline"),
		smp_core.fmt_money(math.floor(v.gain + 0.5), "inline"),
		table.concat(v.inputs, " + "))
end

return A
