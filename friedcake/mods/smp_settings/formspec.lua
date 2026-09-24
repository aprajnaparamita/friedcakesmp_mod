-- FriedcakeSMP — smp_settings / formspec.lua
-- Formspec builders for the observed /settings screens (f12 §3,
-- shared/08 §8.1–8.4).
--
--   menu()                    -> the category menu (seven buttons)
--   category(key, pname)      -> one category's screen of toggle rows
--
-- Grammar (shared/08 §4.9, f12 §4.1): the value lives inside the label
-- — `button[]` labelled `<Name>: <Value>`, never `checkbox[]`. Click
-- cycles the value and the screen redraws in place (f12 §4.5).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_settings.S
local F = core.formspec_escape

local fs = {}
smp_settings.fs = fs

fs.FORMNAME = {
	menu     = "smp_settings:menu",
	category = "smp_settings:category",
}

-- Purple hover, sampled from [F0236]: hue unverified, PROPOSED (§10).
local PURPLE_HOVER = "#7B2FBE"

-- Yellow warning triangle to the right of the title on both prompt
-- menus (f12 §3.1/§3.2; shared/04 §4.2, [F0236, F0242]). U+26A0 as
-- the correct three-byte UTF-8 sequence — the same bytes
-- smp_tp/homes.lua:72 uses, never a truncated single byte. Its
-- MEANING is unestablished (open question V-28); §0.5 rule 2 makes
-- the observed layout normative, so it is drawn regardless.
local TRIANGLE = "\226\154\160"

-- Centre a plain-text label horizontally (house heuristic: 0.16 units
-- per character, same as smp_orders' head prompts).
local function centre_x(w, text)
	return math.max(0.3, (w - #text * 0.16) / 2)
end

-- A button with the purple hover style. The `style[]` element MUST
-- precede the element it styles (doc/lua_api.md, Styling Formspecs).
local function button(x, y, w, h, name, text)
	return table.concat({
		string.format("style[%s:hovered;bgcolor=%s]", name, PURPLE_HOVER),
		string.format("button[%f,%f;%f,%f;%s;%s]",
			x, y, w, h, name, F(text)),
	}, "")
end

----------------------------------------------------------------------
-- Category menu (f12 §3.1, §4.2): title, subtitle, seven buttons in
-- the observed order — Chat, Notifications, PvP, Visuals, Privacy,
-- Scoreboard, General (General centred beneath).

function fs.menu()
	local title = S("Settings")
	local subtitle = S("Choose a category to change your @1 settings",
		smp_settings.server_name())
	local w = 9.5
	local bw, bh = 3.8, 0.9
	local cols = { 0.75, 4.95 }
	local y0, pitch = 1.7, 1.1

	local cats = smp_settings.ordered_categories()
	local nrows = math.max(1, math.ceil(#cats / 2))
	local h = y0 + (nrows - 1) * pitch + bh + 0.4

	local parts = {
		"formspec_version[6]",
		string.format("size[%f,%f]", w, h),
		"bgcolor[#000000C0]",
		string.format("label[%f,0.3;%s]", centre_x(w, title),
			F(title) .. " " .. TRIANGLE),
		string.format("label[%f,0.85;%s]", centre_x(w, subtitle), F(subtitle)),
	}
	for i, cat in ipairs(cats) do
		local name = "cat_" .. cat.key
		local x, y
		if i == #cats and #cats % 2 == 1 then
			-- an odd trailing button centres beneath the grid;
			-- nrows already counts that row
			x = (w - bw) / 2
			y = y0 + (nrows - 1) * pitch
		else
			local col = (i - 1) % 2 + 1
			local row = math.floor((i - 2) / 2) + 1
			x, y = cols[col], y0 + (row - 1) * pitch
		end
		parts[#parts + 1] = button(x, y, bw, bh, name, cat.title)
		parts[#parts + 1] = string.format("tooltip[%s;%s]", name,
			F(S("Open @1 settings", cat.title)))
	end
	return table.concat(parts)
end

----------------------------------------------------------------------
-- Category screen (f12 §4.3): title `Settings - <Category>`, one
-- `<Label>: <Value>` button per registered setting (rows in
-- registration order), `Back` last. Empty categories render the title
-- and Back only — no invented rows (f12 §5.1).

function fs.category(category_key, pname)
	local cat = smp_settings.categories[category_key]
	if not cat then return nil end

	local title = S("Settings - @1", cat.title)
	local w = 10
	local x, bw, bh = 0.5, 9, 0.8
	local y0, pitch = 1.3, 0.95

	local ids = smp_settings.settings_in(category_key)
	local back_y = y0 + #ids * pitch + 0.25
	local h = back_y + bh + 0.35

	local parts = {
		"formspec_version[6]",
		string.format("size[%f,%f]", w, h),
		"bgcolor[#000000C0]",
		string.format("label[%f,0.3;%s]", centre_x(w, title),
			F(title) .. " " .. TRIANGLE),
	}
	for i, id in ipairs(ids) do
		local def = smp_settings.registered[id]
		local value = smp_settings.get(pname, id)
		local name = "toggle_" .. id
		parts[#parts + 1] = button(x, y0 + (i - 1) * pitch, bw, bh, name,
			def.label .. ": " .. smp_settings.value_label(def, value))
		parts[#parts + 1] = string.format("tooltip[%s;%s]", name,
			F(S("Click to toggle")))
	end
	parts[#parts + 1] = button(x, back_y, bw, bh, "back", S("Back"))
	return table.concat(parts)
end
