-- FriedcakeSMP — smp_enderchest
--
-- Donut SMP ender chests hold TWICE the vanilla capacity: 54 slots in
-- 9 columns x 6 rows — the same geometry as a double chest. Stock
-- Mineclonia gives every player a 27-slot "enderchest" list and shows
-- a 9x3 formspec (mcl_chests). This mod upgrades both to 9x6.
--
-- PROPOSED: the specification is silent on ender-chest capacity — the
-- only mention of an ender chest anywhere under spec/ is the chat
-- string "You bought 1 Ender Chest for $ 5.1K" (shared/08). The 9x6
-- capacity was reported from the live Donut SMP server. Surface this
-- in the owning feature file's §10 before merge; no fNN file covers
-- ender chests yet.
--
-- How it works, and why:
--
--   * Storage lives in a mod-owned player-inventory list
--     ("smp_enderchest", 54 slots). It CANNOT be the engine's
--     "enderchest" list: mcl_chests resets that list to 27 on every
--     join (its register_on_joinplayer), and InvRef:set_size destroys
--     items beyond the new size (InventoryList::setSize truncates
--     m_items), so a 54-slot engine list would lose slots 28-54 on
--     every login. Our list is never touched by mcl_chests, so it
--     persists safely in the player file. The engine's list stays at
--     27 and empty; anything already in it is migrated on join.
--
--   * Formspec: mcl_chests shows its 9x3 ender-chest formspec through
--     core.show_formspec with the formname "mcl_chests:ender_chest_
--     <player>". We wrap core.show_formspec and substitute a 9x6
--     formspec for exactly that formname prefix. The node's
--     on_rightclick then runs untouched, so the lid animation,
--     sounds, piglin rage and the formname-driven close handler in
--     mcl_chests all keep working. (Chaining on_rightclick instead
--     would flash the 9x3 formspec before ours.)
--
--   * The reach rule is mirrored: mcl_chests only lets players touch
--     its "enderchest" list while an ender chest is within reach;
--     client inventory actions are untrusted, so we register the same
--     allow-check for our list.
--
--   * Help text: Mineclonia's tooltip and doc entry say "27 slots";
--     both ender-chest node defs are updated to the capacity we
--     actually serve (hard rule 7 — all player-facing strings go
--     through the translator).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())
local F = core.formspec_escape
local C = core.colorize

smp_enderchest = {}

smp_enderchest.COLS = 9
smp_enderchest.ROWS = 6
smp_enderchest.SLOTS = smp_enderchest.COLS * smp_enderchest.ROWS  -- 54
smp_enderchest.LIST = "smp_enderchest"

local ENGINE_LIST = "enderchest"
local FORMNAME_PREFIX = "mcl_chests:ender_chest_"
local CHEST_NODE = "mcl_chests:ender_chest_small"

local SLOT_COUNT_HELP = S("54 interdimensional inventory slots")
local USAGE_HELP = S("Put items inside, retrieve them from any ender chest")
local LONGDESC = S("Ender chests grant you access to a single personal " ..
	"interdimensional inventory with 54 slots. This inventory is the same " ..
	"no matter from which ender chest you access it from. If you put one " ..
	"item into one ender chest, you will find it in all other ender " ..
	"chests. Each player will only see their own items, but not the items " ..
	"of other players.")

----------------------------------------------------------------------
-- Formspec
--
-- Geometry mirrors mcl_chests' own double-chest formspec (the large
-- chest is already 9x6): one 6-row container block from 0.75 to 8.25,
-- the Inventory label at 8.45, the 3 main rows at 8.825 and the
-- hotbar row at 12.775, in size[11.75,14.15].
----------------------------------------------------------------------

function smp_enderchest.formspec()
	return table.concat({
		"formspec_version[4]",
		"size[11.75,14.15]",

		"label[0.375,0.375;" .. F(C(mcl_formspec.label_color, S("Ender Chest"))) .. "]",
		mcl_formspec.get_itemslot_bg_v4(0.375, 0.75, 9, 6),
		"list[current_player;" .. smp_enderchest.LIST .. ";0.375,0.75;9,6;]",

		"label[0.375,8.45;" .. F(C(mcl_formspec.label_color, S("Inventory"))) .. "]",
		mcl_formspec.get_itemslot_bg_v4(0.375, 8.825, 9, 3),
		"list[current_player;main;0.375,8.825;9,3;9]",

		mcl_formspec.get_itemslot_bg_v4(0.375, 12.775, 9, 1),
		"list[current_player;main;0.375,12.775;9,1;]",

		"listring[current_player;" .. smp_enderchest.LIST .. "]",
		"listring[current_player;main]",
	})
end

-- Substitute our 9x6 formspec for the ender-chest formname; every
-- other formspec passes through untouched.
function smp_enderchest.intercept(formname, formspec)
	if type(formname) == "string"
			and formname:sub(1, #FORMNAME_PREFIX) == FORMNAME_PREFIX then
		return smp_enderchest.formspec()
	end
	return formspec
end

local engine_show_formspec = core.show_formspec
if type(engine_show_formspec) == "function" then
	core.show_formspec = function(player, formname, formspec)
		engine_show_formspec(player, formname,
			smp_enderchest.intercept(formname, formspec))
	end
end

----------------------------------------------------------------------
-- Join: grow our list, migrate anything left in the engine list
----------------------------------------------------------------------

core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	if not inv then return end

	-- Grow only in practice: set_size preserves existing stacks when
	-- growing, and nothing else ever shrinks this list.
	inv:set_size(smp_enderchest.LIST, smp_enderchest.SLOTS)

	-- Before this mod existed the engine's 27-slot list WAS the
	-- player's ender inventory. Move any contents into ours and clear
	-- it. Idempotent: after the first join the engine list is empty.
	local legacy = inv:get_list(ENGINE_LIST)
	if type(legacy) ~= "table" then return end
	for i, stack in ipairs(legacy) do
		if stack and not stack:is_empty()
				and inv:room_for_item(smp_enderchest.LIST, stack) then
			inv:add_item(smp_enderchest.LIST, stack)
			inv:set_stack(ENGINE_LIST, i, "")
		end
	end
end)

----------------------------------------------------------------------
-- Reach rule — client inventory actions are untrusted; mirror the
-- mcl_chests guard (an ender chest must be within reach) for our list
----------------------------------------------------------------------

core.register_allow_player_inventory_action(function(player, action, inv, info)
	if not info or not inv or inv:get_location().type ~= "player" then
		return
	end

	local touches = (action == "move" and
			(info.from_list == smp_enderchest.LIST or
				info.to_list == smp_enderchest.LIST)) or
		((action == "put" or action == "take") and
			info.listname == smp_enderchest.LIST)
	if not touches then return end

	local def = player:get_wielded_item():get_definition()
	local range = def and def.range or ItemStack():get_definition().range
		or tonumber(core.settings:get("mcl_hand_range")) or 4.5
	if not core.find_node_near(player:get_pos(), range, CHEST_NODE, true) then
		return 0
	end
end)

----------------------------------------------------------------------
-- Help text: both ender-chest node defs say "27 slots" upstream —
-- update them to the capacity we actually serve
----------------------------------------------------------------------

for _, name in ipairs({ "mcl_chests:ender_chest", "mcl_chests:ender_chest_small" }) do
	local def = core.registered_nodes and core.registered_nodes[name]
	if def then
		def._tt_help = SLOT_COUNT_HELP .. "\n" .. USAGE_HELP
		def._doc_items_longdesc = LONGDESC
	end
end

core.log("action", "[smp_enderchest] loaded: 54-slot (9x6) ender chest")
