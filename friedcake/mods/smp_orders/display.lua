-- FriedcakeSMP — smp_orders / display.lua
-- Display names, enchantment lines and tooltip composition.
--
-- The reference server is internally inconsistent and BOTH readings are
-- requirements (f04 §3, T3):
--   * order tooltips / panels use the PLURAL display name —
--     "Netherite Helmets" [F0164], "Totems of Undying" [F0212],
--     even at quantity 1 ("You're delivering 1 Totems of Undying" [F0219])
--   * the delivery chat line uses the SINGULAR display name —
--     "You delivered 1 Totem of Undying and received $30K" [F0227]
-- Do not unify them.
--
-- Money/quantity rendering goes through smp_core (shared §0.6):
--   order tooltip price   "$ 4M each"   body style (space)   [F0164]
--   confirm panel price   "$30K each"   inline style         [F0219]
--   confirm affordance    "Click to deliver items ($30K)"    [F0222]
--   delivery chat         "received $30K"                    [F0227]
--   quantities            lower-case suffixes "753k/1.3m"    [F0160]
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_orders.S

smp_orders.display = {}
local display = smp_orders.display

----------------------------------------------------------------------
-- Money / quantity rendering helpers (all delegate to smp_core)
----------------------------------------------------------------------

-- "$ 30K" — tooltip bodies and chat lines (shared §0.6).
function display.money(cents)
	return smp_core.fmt_money(cents, "body")
end

-- "$30K" — inline / parenthesised amounts.
function display.money_inline(cents)
	return smp_core.fmt_money(cents, "inline")
end

-- "30K" / "10" — the bare numeric part, for catalogue strings that carry
-- their own "$": `Price: $ @1 each`, `Total: $ @1`, `Minimum: $ @1`,
-- `Click to deliver items ($@1)`, `You delivered ... received $@3`.
function display.money_num(cents)
	local s = smp_core.fmt_money(cents, "inline")
	return (s:gsub("^%$", ""))
end

-- "300k" — quantity with lower-case suffixes.
function display.qty(n)
	return smp_core.fmt_qty(n)
end

----------------------------------------------------------------------
-- Pluralisation (T3)
----------------------------------------------------------------------

-- Pluralise an English display name (PROPOSED rule set; the reference
-- server renders Java's pluralised item names):
--   * "X of Y" names pluralise the FIRST word —
--     Totem of Undying -> Totems of Undying            [F0212]
--   * every other name pluralises the LAST word —
--     Netherite Helmet -> Netherite Helmets            [F0164]
--     Gold Ingot       -> Gold Ingots                  [F0160]
--     Beacon           -> Beacons                      [F0159]
--     Empty Map        -> Empty Maps                   [F0161]
--     Bone             -> Bones                        [F0171]
local function plural_word(w)
	local lc = w:lower()
	if lc:match("[sxz]$") or lc:match("ch$") or lc:match("sh$") then
		return w .. "es"
	elseif lc:match("[^aeiou]y$") then
		return w:sub(1, -2) .. "ies"
	end
	return w .. "s"
end

function display.plural(desc)
	if type(desc) ~= "string" or desc == "" then return desc end
	if desc:find("%s+of%s+") then
		local head, tail = desc:match("^(%S+)(%s.*)$")
		if head then return plural_word(head) .. tail end
		return desc
	end
	local head, last = desc:match("^(.*%s)(%S+)$")
	if head then return head .. plural_word(last) end
	return plural_word(desc)
end

-- Singular display name of an order's item.
function display.item_name(order)
	return smp_items.display_name(order.template)
end

-- Plural display name of an order's item.
function display.order_name(order)
	return display.plural(display.item_name(order))
end

----------------------------------------------------------------------
-- Enchantment line (part of M1 order identity — f04 §3.1, T8)
----------------------------------------------------------------------

-- Canonical rendering order. The observed line is
--   "Protection IV, Respiration III, Aqua Affinity, Unbreaking III,
--    Mending"  [F0164]
-- Mineclonia registers enchantments into a hash table (order is lost) so
-- we pin a Java-registry-style order that reproduces the observation
-- exactly; unknown ids sort alphabetically after the known ones.
-- PROPOSED (f04 §8 "as registered").
display.ENCH_ORDER = {
	protection = 1, fire_protection = 2, feather_falling = 3,
	blast_protection = 4, projectile_protection = 5, respiration = 6,
	aqua_affinity = 7, depth_strider = 8, frost_walker = 9, thorns = 10,
	sharpness = 11, smite = 12, bane_of_arthropods = 13, knockback = 14,
	fire_aspect = 15, looting = 16, silk_touch = 17, efficiency = 18,
	fortune = 19, unbreaking = 20, power = 21, punch = 22, flame = 23,
	infinity = 24, luck_of_the_sea = 25, lure = 26, mending = 27,
	curse_of_binding = 28, curse_of_vanishing = 29, riptide = 30,
	channeling = 31, impaling = 32, multishot = 33, piercing = 34,
	quick_charge = 35, soul_speed = 36, swift_sneak = 37,
	density = 38, breach = 39, wind_burst = 40,
}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

-- Roman numerals for levels 1..10; beyond that fall back to the number.
function display.roman(level)
	return ROMAN[level] or tostring(level)
end

-- Human name of an enchantment id. Prefers Mineclonia's own (translated)
-- registration; falls back to Title Case of the id. Note: aqua_affinity
-- is commented out in Mineclonia ("requires engine change") so the
-- fallback path is the one that renders "Aqua Affinity".
function display.ench_name(id)
	if mcl_enchanting and mcl_enchanting.enchantments and
	   mcl_enchanting.enchantments[id] then
		local def = mcl_enchanting.enchantments[id]
		if def.name and def.name ~= "" then
			-- names may be translated strings; take the first line
			return (tostring(def.name):match("^[^\n]*"))
		end
	end
	local words = {}
	for w in tostring(id):gmatch("[^_]+") do
		words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2)
	end
	return table.concat(words, " ")
end

-- "Protection IV, Respiration III, Aqua Affinity, Unbreaking III,
--  Mending" — level 1 omits the numeral ("Aqua Affinity", "Mending")
-- [F0164]. Returns "" when the order carries no enchantments.
function display.ench_line(ench)
	if type(ench) ~= "table" or not next(ench) then return "" end
	local ids = {}
	for id in pairs(ench) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b)
		local oa, ob = display.ENCH_ORDER[a], display.ENCH_ORDER[b]
		if oa and ob then
			if oa ~= ob then return oa < ob end
		elseif oa then
			return true
		elseif ob then
			return false
		end
		return a < b
	end)
	local parts = {}
	for _, id in ipairs(ids) do
		local level = tonumber(ench[id]) or 1
		local name = display.ench_name(id)
		if level == 1 then
			parts[#parts + 1] = name
		else
			parts[#parts + 1] = name .. " " .. display.roman(level)
		end
	end
	return table.concat(parts, ", ")
end

----------------------------------------------------------------------
-- Tooltips and panels
----------------------------------------------------------------------

-- Order tooltip lines, in the OBSERVED order (f04 §3.1 [F0164], T2):
--   1 plural display name
--   2 enchantment line (only when enchanted)
--   3 "$ 4M each"           unit price, body style
--   4 "251/350 Delivered"   lower-case quantity suffixes
--   5 "Click to deliver items"
--   6 itemstring (Mineclonia's, per shared §0.5.1 — the Java
--     "minecraft:..." line is translated, the component(s) line dropped)
function display.order_tooltip_lines(order)
	local lines = { display.order_name(order) }
	local ench = display.ench_line(order.ench)
	if ench ~= "" then lines[#lines + 1] = ench end
	lines[#lines + 1] = S("@1 each", display.money(order.unit_price))
	lines[#lines + 1] = S("@1/@2 Delivered",
		display.qty(order.delivered), display.qty(order.qty))
	lines[#lines + 1] = S("Click to deliver items")
	lines[#lines + 1] = order.template
	return lines
end

-- Confirm-delivery detail panel lines (f04 §3.4 [F0219]):
--   Totems of Undying
--   300k requested                     (quantity, lower-case per §0.6)
--   $30K each                          (inline style)
--   You're delivering 1 Totems of Undying   (PLURAL even at qty 1)
--   mcl_totems:totem                   (itemstring; component line DROP)
function display.confirm_lines(order, delivering_count)
	return {
		display.order_name(order),
		S("@1 requested", display.qty(order.qty)),
		S("@1 each", display.money_inline(order.unit_price)),
		S("You're delivering @1 @2",
			display.qty(delivering_count), display.order_name(order)),
		order.template,
	}
end

-- The delivery result chat line (f04 §3.4 [F0227], T3 — SINGULAR name):
--   "You delivered 1 Totem of Undying and received $30K"
function display.delivered_message(accepted, order, payout)
	return S("You delivered @1 @2 and received $@3",
		display.qty(accepted), display.item_name(order),
		display.money_num(payout))
end

-- Confirm-pane affordance tooltip: "Confirm" / "Click to deliver items
-- ($30K)" [F0222].
function display.confirm_tooltip(payout_preview)
	return S("Confirm") .. "\n" ..
		S("Click to deliver items ($@1)", display.money_num(payout_preview))
end
