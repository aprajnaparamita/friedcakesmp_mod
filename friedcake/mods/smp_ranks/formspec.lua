-- FriedcakeSMP — smp_ranks /ranks menu (f13 §4.2.9, §8).
--
-- A prompt menu (shared/04-ui-kit.md §4.1): formspec_version[6],
-- bgcolor[#000000C0], no inventory list, a Back button. Every perk
-- number is rendered from the live tier table (tiers.lua) — never
-- hard-coded — so the screen and the enforcement cannot drift (T7).
--
-- The store link sits in a field for copying: Luanti cannot open URLs
-- (§4.2.9). The field is server-read-only — no handler ever consumes
-- what the client types into it.
--
-- The whole screen is PROPOSED: no frame shows a rank menu (V-73).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local FORMNAME = "smp_ranks:ranks"
smp_ranks.FORMNAME = FORMNAME

local S = smp_ranks.S

----------------------------------------------------------------------
-- Rows — one per configured tier, built from live config (T7)
----------------------------------------------------------------------

function smp_ranks.tier_rows()
	local rows = {}
	for _, tier in ipairs(smp_ranks.tier_order) do
		rows[#rows + 1] = {
			tier = tier,
			label = S("@1: @2 homes, @3 auction slots, @4 order slots, @5s rtp",
				smp_ranks.display_label(tier),
				smp_ranks.slots_for("homes", tier),
				smp_ranks.slots_for("ah", tier),
				smp_ranks.slots_for("orders", tier),
				smp_ranks.cooldown_for(tier)),
		}
	end
	return rows
end

----------------------------------------------------------------------
-- Formspec
----------------------------------------------------------------------

function smp_ranks.formspec()
	local fs = {
		"formspec_version[6]",
		"", -- size[], filled in once the tier rows are counted
		"bgcolor[#000000C0]",
		"label[0.4,0.55;" .. core.formspec_escape(S("Ranks")) .. "]",
	}
	local rows = smp_ranks.tier_rows()
	for i, row in ipairs(rows) do
		fs[#fs + 1] = string.format("label[0.4,%.2f;%s]",
			1.3 + (i - 1) * 0.9, core.formspec_escape(row.label))
	end
	local store_y = 1.3 + #rows * 0.9 + 0.3
	local store = smp_ranks.cfg.store_text
	if store == "" then store = S("(no store link configured)") end
	fs[#fs + 1] = string.format("field[0.4,%.2f;10.2,0.8;store;%s;%s]",
		store_y, core.formspec_escape(S("Store")), core.formspec_escape(store))
	fs[#fs + 1] = "field_close_on_enter[store;false]"
	fs[#fs + 1] = string.format("button[4.5,%.2f;2,0.8;back;%s]",
		store_y + 1.2, core.formspec_escape(S("Back")))
	-- Grow with the tier list so Back always stays inside the dialog.
	fs[2] = string.format("size[11,%.2f]", math.max(9.9, store_y + 2.5))
	return table.concat(fs, "")
end

function smp_ranks.show(name)
	smp_core.open_session(name, FORMNAME, {})
	core.show_formspec(name, FORMNAME, smp_ranks.formspec())
end

----------------------------------------------------------------------
-- Fields: only Back/quit; the store field is never read back.
----------------------------------------------------------------------

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORMNAME then return end
	local name = player:get_player_name()
	smp_core.handle_fields(name, formname, fields, function(_, f)
		if f.back or f.quit then return "close" end
	end)
end)
