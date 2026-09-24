-- FriedcakeSMP — smp_orders acceptance tests
-- Loaded by `/smp test smp_orders` in-game (once the integrator wires a
-- generic test loader — see f04 §10), and by the standalone harness in
-- friedcake/dev-tests/test_orders.lua. Returns {passed, failed, lines}.
--
-- Covers spec/features/f04-orders.md §9 display strings, keys, tooltip
-- order, sort cycling, parsing, and UI flows (wizard, board, delivery).
-- The heavy economy paths (T6–T14) run in the standalone harness
-- friedcake/dev-tests/test_orders.lua which stubs the store.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "assertion")
	end
end

local function eq(a, b, msg)
	ok(a == b, string.format("%s: expected %q got %q",
		msg or "eq", tostring(b), tostring(a)))
end

local S = smp_orders.S
local display = smp_orders.display
local cfg = smp_orders.cfg
local fs = smp_orders.fs

----------------------------------------------------------------------
-- T1 — board title and the three ORDERS sorts (not the auction's)
----------------------------------------------------------------------
eq(fs.sort_label("most_per_item"), "Most Per Item", "T1 sort label 1")
eq(fs.sort_label("most_paid"), "Most Paid", "T1 sort label 2")
eq(fs.sort_label("recently_listed"), "Recently Listed", "T1 sort label 3")
eq(smp_orders.cycle_sort("most_per_item"), "most_paid", "T1 cycle 1->2")
eq(smp_orders.cycle_sort("most_paid"), "recently_listed", "T1 cycle 2->3")
eq(smp_orders.cycle_sort("recently_listed"), "most_per_item", "T1 cycle 3->1")
eq(#cfg.sorts, 3, "T1 exactly three sorts")
eq(S("Orders (Page @1)", 1), "Orders (Page 1)", "T1 board title")

----------------------------------------------------------------------
-- T2 — order tooltip line order:
-- name, enchantments, "$ @1 each", "@1/@2 Delivered",
-- "Click to deliver items", itemstring
----------------------------------------------------------------------
do
	local fake = {
		template = "mcl_armor:helmet_netherite",
		ench = { protection = 4, respiration = 3, aqua_affinity = 1,
		         unbreaking = 3, mending = 1 },
		unit_price = 400000000,   -- $4M
		qty = 350, delivered = 251,
	}
	local lines = display.order_tooltip_lines(fake)
	eq(lines[1], "Netherite Helmets", "T2 plural name")
	eq(lines[2],
		"Protection IV, Respiration III, Aqua Affinity, Unbreaking III, Mending",
		"T2 enchantment line, registration order, roman numerals, level-1 bare")
	eq(lines[3], "$ 4M each", "T2 unit price, body spacing")
	eq(lines[4], "251/350 Delivered", "T2 progress")
	eq(lines[5], "Click to deliver items", "T2 affordance")
	eq(lines[6], "mcl_armor:helmet_netherite", "T2 itemstring last")
	eq(#lines, 6, "T2 six lines (component line dropped)")
end

----------------------------------------------------------------------
-- T3 — plural in tooltips/panels, singular in the delivery chat
----------------------------------------------------------------------
eq(display.plural("Totem of Undying"), "Totems of Undying", "T3 plural totem")
eq(display.plural("Netherite Helmet"), "Netherite Helmets", "T3 plural helmet")
eq(display.plural("Gold Ingot"), "Gold Ingots", "T3 plural ingot")
eq(display.plural("Beacon"), "Beacons", "T3 plural beacon")
eq(display.plural("Empty Map"), "Empty Maps", "T3 plural map")
eq(display.plural("Bone"), "Bones", "T3 plural bone")
do
	local fake = { template = "mcl_totems:totem", unit_price = 3000000, qty = 1 }
	eq(display.delivered_message(1, fake, 3000000),
		"You delivered 1 Totem of Undying and received $30K",
		"T3 delivery chat, SINGULAR name [F0227]")
	local panel = display.confirm_lines(fake, 1)
	eq(panel[4], "You're delivering 1 Totems of Undying",
		"T3 confirm panel, PLURAL at qty 1 [F0219]")
	eq(panel[3], "$30K each", "T3 panel price inline spacing")
	eq(display.confirm_tooltip(3000000),
		"Confirm\nClick to deliver items ($30K)",
		"T3 confirm pane affordance [F0222]")
end

----------------------------------------------------------------------
-- T4 — the ungrammatical "(1 results)" title survives verbatim
----------------------------------------------------------------------
eq(S("Choose Item (@1 results)", 1), "Choose Item (1 results)", "T4 title")

----------------------------------------------------------------------
-- Verbatim strings this mod owns (shared/08-ui-strings.md §8.1–§8.7)
----------------------------------------------------------------------
eq(S("Orders -> Your Orders"), "Orders -> Your Orders", "S your orders title")
eq(S("Orders -> Deliver Items"), "Orders -> Deliver Items", "S deliver title")
eq(S("Orders -> Confirm Delivery"), "Orders -> Confirm Delivery", "S confirm title")
eq(S("How many?"), "How many?", "S how many")
eq(S("Price per item?"), "Price per item?", "S price")
eq(S("Review Order"), "Review Order", "S review")
eq(S("Cancel!"), "Cancel!", "S cancel with exclamation mark")
eq(S("@1 requested", "300k"), "300k requested", "S requested")
eq(S("You're delivering @1 @2", 1, "Totems of Undying"),
	"You're delivering 1 Totems of Undying", "S delivering")
eq(S("Delivering..."), "Delivering...", "S action bar")
eq(S("@1 each", "$ 182K"), "$ 182K each", "S each (body spacing [F0159])")
eq(S("@1/@2 Delivered", "167k", "200k"), "167k/200k Delivered", "S delivered")

----------------------------------------------------------------------
-- Quantity rendering at the observed scale (T12 strings)
----------------------------------------------------------------------
eq(display.qty(753000), "753k", "T12 753k")
eq(display.qty(1300000), "1.3m", "T12 1.3m")
do
	local fake = { template = "mcl_core:gold_ingot", unit_price = 100000,
	               qty = 1300000, delivered = 753000 }
	local lines = display.order_tooltip_lines(fake)
	eq(lines[1], "Gold Ingots", "T12 plural name")
	eq(lines[2], "$ 1K each", "T12 $ 1K each [F0160]")
	eq(lines[3], "753k/1.3m Delivered", "T12 753k/1.3m Delivered [F0160]")
	eq(#lines, 5, "T12 no enchantment line for a plain item")
end

----------------------------------------------------------------------
-- Keying sanity (shared §2.5 — M1 includes enchantments, T8's basis)
----------------------------------------------------------------------
do
	local plain = ItemStack("mcl_armor:helmet_netherite")
	local magic = ItemStack("mcl_armor:helmet_netherite")
	if mcl_enchanting and mcl_enchanting.set_enchantments then
		mcl_enchanting.set_enchantments(magic, { protection = 4 })
	end
	local kp = smp_items.key(plain, "M1")
	local km = smp_items.key(magic, "M1")
	ok(kp ~= nil and km ~= nil, "T8 both helmets key at M1")
	ok(kp ~= km, "T8 enchanted key differs from plain key")
	ok(smp_items.matches(plain, km, "M1") == false,
		"T8 plain helmet does NOT match enchanted order")
	ok(smp_items.matches(magic, kp, "M1") == false,
		"T8 enchanted helmet does NOT match plain order")
	ok(smp_items.matches(magic, km, "M1") == true, "T8 exact enchant match")
	local worn = ItemStack("mcl_armor:helmet_netherite")
	worn:set_wear(1000)
	ok(smp_items.key(worn, "M1") == nil, "T8 worn stack has no M1 key")
end

----------------------------------------------------------------------
-- parse_qty — §0.6 suffixes, integer quantities
----------------------------------------------------------------------
eq(smp_orders.parse_qty("1"), 1, "Q 1")
eq(smp_orders.parse_qty("64"), 64, "Q 64")
eq(smp_orders.parse_qty("250k"), 250000, "Q 250k")
eq(smp_orders.parse_qty("1.5m"), 1500000, "Q 1.5m")
eq(smp_orders.parse_qty("1.3M"), 1300000, "Q 1.3M")
ok(smp_orders.parse_qty("0") == nil, "Q reject 0")
ok(smp_orders.parse_qty("-5") == nil, "Q reject negative")
ok(smp_orders.parse_qty("abc") == nil, "Q reject garbage")
ok(smp_orders.parse_qty("") == nil, "Q reject empty")

----------------------------------------------------------------------
-- Blacklist (LIVE [S9]) and slot limits (LIVE [S17])
----------------------------------------------------------------------
ok(smp_orders.blacklisted("mcl_amethyst:amethyst_shard"), "B amethyst shard")
ok(smp_orders.blacklisted("m1|mcl_amethyst:amethyst_shard||0"), "B amethyst key")
ok(not smp_orders.blacklisted("mcl_core:diamond"), "B diamond allowed")
eq(cfg.slots.default, 9, "B default slots 9")
eq(cfg.slots.tier1, 45, "B tier1 slots 45")
eq(cfg.slots.tier2, 90, "B tier2 slots 90")

return results
