-- FriedcakeSMP — smp_settings / test.lua
-- In-game test suite (run by /smp test once the generic loader lands;
-- also executed headlessly by dev-tests/test_settings.lua).
-- Covers f12 §9 T1–T8 (T9 is f11's stranger-/msg test; its f12 leg
-- runs in dev-tests/test_social.lua), plus fix rows F12-1 (the title
-- warning triangle on both renders) and F12-5 (description style).
-- Pure checks: does not mutate the calling player's settings.

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
		results.lines[#results.lines + 1] = "ok   " .. msg
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. msg
	end
	return cond
end

local function eq(got, want, msg)
	return ok(got == want, msg .. " (got " .. tostring(got)
		.. ", want " .. tostring(want) .. ")")
end

local function has(spec, needle)
	return spec ~= nil and spec:find(needle, 1, true) ~= nil
end

local fs = smp_settings.fs
local CAT_KEYS = {
	"chat", "notifications", "pvp", "visuals",
	"privacy", "scoreboard", "general",
}
local CAT_TITLES = {
	"Chat", "Notifications", "PvP", "Visuals",
	"Privacy", "Scoreboard", "General",
}

----------------------------------------------------------------------
-- T1: seven categories, observed order, in the menu as buttons
do
	local cats = smp_settings.ordered_categories()
	eq(#cats, 7, "T1 seven categories registered")
	for i, key in ipairs(CAT_KEYS) do
		eq(cats[i] and cats[i].key, key, "T1 category " .. i .. " key")
		eq(cats[i] and cats[i].title, CAT_TITLES[i],
			"T1 category " .. i .. " title")
	end

	local menu = fs.menu()
	local n = 0
	for _ in menu:gmatch(";cat_") do n = n + 1 end
	eq(n, 7, "T1 menu has exactly seven category buttons")
	local prev = 0
	for _, key in ipairs(CAT_KEYS) do
		local p = menu:find(";cat_" .. key .. ";", 1, true)
		ok(p ~= nil and p > prev, "T1 button cat_" .. key
			.. " present and in observed order")
		prev = p or 0
	end
end

----------------------------------------------------------------------
-- T2: each category button tooltip is `Open <Category> settings`
do
	local menu = fs.menu()
	for i, key in ipairs(CAT_KEYS) do
		ok(has(menu, "tooltip[cat_" .. key .. ";Open "
			.. CAT_TITLES[i] .. " settings]"),
			"T2 tooltip cat_" .. key)
	end
end

----------------------------------------------------------------------
-- T3: subtitle `Choose a category to change your <server.name> settings`
do
	local want = "Choose a category to change your "
		.. smp_settings.server_name() .. " settings"
	eq(smp_settings.S("Choose a category to change your @1 settings",
		smp_settings.server_name()), want, "T3 subtitle verbatim")
	ok(has(fs.menu(), want), "T3 subtitle rendered in menu")
end

----------------------------------------------------------------------
-- T4: Settings - Chat shows the seven observed toggles in observed
-- order, then Back
do
	local screen = fs.category("chat", nil)
	ok(has(screen, "Settings - Chat"), "T4 title `Settings - Chat`")
	local ROWS = {
		"Public Chat: ON",
		"Private Messages: Friends/Followed",
		"Server Chat Messages: ON",
		"Server Hotbar Messages: ON",
		"Death Messages: Friends/Followed",
		"Advancement Messages: Friends/Followed",
		"Join/Leave Messages: Friends/Followed",
	}
	local n, prev = 0, 0
	for _ in screen:gmatch(";toggle_") do n = n + 1 end
	eq(n, 7, "T4 seven toggle rows")
	prev = 0
	for _, row in ipairs(ROWS) do
		local p = screen:find(row, 1, true)
		ok(p ~= nil and p > prev, "T4 row `" .. row .. "` in order")
		prev = p or 0
	end
	local back = screen:find(";back;Back", 1, true)
	ok(back ~= nil and back > prev, "T4 Back after the last toggle")
end

----------------------------------------------------------------------
-- T4 (continued): unopened categories stay empty — title + Back only
do
	local screen = fs.category("notifications", nil)
	ok(has(screen, "Settings - Notifications"),
		"T4 unopened category renders its title")
	ok(not has(screen, ";toggle_"),
		"T4 unopened category has no invented rows")
	ok(has(screen, ";back;Back"), "T4 unopened category has Back")
end

----------------------------------------------------------------------
-- T6: value domains, defaults, cycle order and wrap-around
do
	eq(smp_settings.get("nobody", "chat.public"), "ON",
		"chat.public default ON")
	eq(smp_settings.get("nobody", "chat.private_messages"),
		"FRIENDS_FOLLOWED", "chat.private_messages default FRIENDS_FOLLOWED")
	eq(smp_settings.get("nobody", "chat.death_messages"),
		"FRIENDS_FOLLOWED", "chat.death_messages default FRIENDS_FOLLOWED")
	eq(smp_settings.get("nobody", "chat.advancements"),
		"FRIENDS_FOLLOWED", "chat.advancements default FRIENDS_FOLLOWED")
	eq(smp_settings.get("nobody", "chat.join_leave"),
		"FRIENDS_FOLLOWED", "chat.join_leave default FRIENDS_FOLLOWED")
	eq(smp_settings.get("nobody", "chat.server_messages"), "ON",
		"chat.server_messages default ON")
	eq(smp_settings.get("nobody", "chat.hotbar_messages"), "ON",
		"chat.hotbar_messages default ON")

	local bin = smp_settings.registered["chat.public"].values
	eq(#bin, 2, "binary setting has two states")
	eq(smp_settings.next_value("chat.public", "ON"), "OFF", "T6 ON -> OFF")
	eq(smp_settings.next_value("chat.public", "OFF"), "ON",
		"T6 OFF wraps to ON")

	local tri = smp_settings.registered["chat.private_messages"].values
	eq(#tri, 3, "tri-state setting has three states")
	eq(smp_settings.next_value("chat.private_messages", "ON"),
		"FRIENDS_FOLLOWED", "T6 ON -> FRIENDS_FOLLOWED")
	eq(smp_settings.next_value("chat.private_messages", "FRIENDS_FOLLOWED"),
		"OFF", "T6 FRIENDS_FOLLOWED -> OFF")
	eq(smp_settings.next_value("chat.private_messages", "OFF"), "ON",
		"T6 OFF wraps to ON")

	local def = smp_settings.registered["chat.private_messages"]
	eq(smp_settings.value_label(def, "FRIENDS_FOLLOWED"),
		"Friends/Followed", "T6 displayed value is Friends/Followed")
end

----------------------------------------------------------------------
-- T8: forged setting ids are ignored by the write path
do
	eq(smp_settings.set(nil, "forged.id", "ON"), false,
		"T8 forged id rejected by set")
	eq(smp_settings.set(nil, "chat.public", "MAYBE"), false,
		"T8 out-of-domain value rejected by set")
	eq(smp_settings.next_value("forged.id", "ON"), nil,
		"T8 forged id rejected by next_value")
	eq(smp_settings.on_toggle(nil, "forged.id"), false,
		"T8 forged id rejected by on_toggle")
end

----------------------------------------------------------------------
-- Consumer contract: unregistered ids read as nil (smp_orders falls
-- back to its own default; f08's eco.pay_accept etc. are NOT ours).
do
	local good, v = pcall(smp_settings.get, "nobody", "eco.order_alerts")
	ok(good and v == nil, "unregistered id returns nil")
	eq(smp_settings.get("nobody", "eco.pay_accept"), nil,
		"eco.pay_accept not registered")
	eq(smp_settings.get("nobody", "combat.keep_pearls_on_death"), nil,
		"combat.* not registered")
	eq(smp_settings.get("nobody", "privacy.show_money"), nil,
		"privacy.* not registered")
end

----------------------------------------------------------------------
-- Purple hover (PROPOSED) precedes the buttons it styles
do
	local menu = fs.menu()
	ok(has(menu, "style[cat_chat:hovered;bgcolor=#7B2FBE]"),
		"purple hover style on cat_chat")
end

----------------------------------------------------------------------
-- F12-1: the yellow warning triangle sits right of the title on both
-- prompt menus (f12 §3.1/§3.2; shared/04 §4.2). U+26A0 as the exact
-- three UTF-8 bytes, never a truncated single byte.
do
	local TRIANGLE = "\226\154\160"
	eq(#TRIANGLE, 3, "F12-1 triangle is the full 3-byte UTF-8 sequence")
	eq(TRIANGLE:byte(1), 0xE2, "F12-1 U+26A0 byte 1")
	eq(TRIANGLE:byte(2), 0x9A, "F12-1 U+26A0 byte 2")
	eq(TRIANGLE:byte(3), 0xA0, "F12-1 U+26A0 byte 3")

	local menu = fs.menu()
	ok(has(menu, "Settings " .. TRIANGLE),
		"F12-1 triangle in the category-menu title")
	local screen = fs.category("chat", nil)
	ok(has(screen, "Settings - Chat " .. TRIANGLE),
		"F12-1 triangle in the `Settings - Chat` title")
	ok(not has(menu, "\241") and not has(screen, "\241"),
		"F12-1 no truncated lone 0xF1 byte in either render")
end

----------------------------------------------------------------------
-- F12-5: /settings description is sentence case, no terminal full
-- stop (shared §0.5 rule 4).
do
	local def = core.registered_chatcommands
		and core.registered_chatcommands.settings
	eq(def and def.description, "Open the settings menu",
		"F12-5 /settings description has no terminal full stop")
end

return results
