-- FriedcakeSMP — smp_tp homes acceptance tests (f09)
--
-- Loaded by `/smp test smp_tp_homes` once the integrator wires the
-- generic test loader (f09 §11), and executed directly by the
-- standalone harness friedcake/dev-tests/test_homes.lua. Returns
-- {passed, failed, lines} like every other test.lua in the modpack.
--
-- Covers spec/features/f09-homes.md §9:
--   T1  /sethome at the slot limit: exactly `You reached home limits`,
--       nothing created                       (data level here; command
--       level in dev-tests/test_homes.lua)
--   T2  /sethome below the limit: exactly `Home set`, tab `Home <n>`
--   T3  rename updates submenu title and tab labels; id unchanged
--   T4  delete: exactly `Home deleted`, tab removed
--   T5  /homes <unknown>: exactly `Home does not exist` (command level)
--   T6  more homes than homes.tabs_before_more -> `Show More`
--   T7  icon choice persists in the store record (survives a restart;
--       the dev harness re-boots smp_store on top of this)
--   T8  home id deleted while its submenu is open fails safely
--   T9  nothing about a home is ever addressed to or rendered for
--       anyone but the owner (/findplayer itself is f11; f09's half of
--       the contract is owner-scoped data + no coordinates on screen)
--
-- Runs against a SYNTHETIC player record `__f09_test`: no online player
-- is required and no real player's homes are touched. Chat and
-- formspec output is captured (and still forwarded) so the verbatim
-- strings can be asserted in-game too.
--
-- Requires smp_tp/homes.lua to be loaded — see §11 "Proposed shared
-- changes" in spec/features/f09-homes.md.
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

local H = smp_tp and smp_tp.homes
if not H then
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] =
		"FAIL smp_tp/homes.lua is not loaded (integrator: dofile it from init.lua, f09 §11)"
	return results
end

local S = smp_tp.S
local cfg = smp_tp.cfg
local TNAME = "__f09_test"
local FORM = H.FORMNAME

----------------------------------------------------------------------
-- Capture chat + formspec output (still forwarded, so in-game behaviour
-- is unchanged and the captured lines can be asserted verbatim)
----------------------------------------------------------------------

local captured_chat = {}   -- [target] = { msg, ... }
local captured_fs = {}     -- [target] = { fs, ... }
local orig_chat = core.chat_send_player
local orig_fs = core.show_formspec

local function capture_reset()
	captured_chat = {}
	captured_fs = {}
end

local function restore()
	core.chat_send_player = orig_chat
	core.show_formspec = orig_fs
end

local function say_count(name)
	return #(captured_chat[name] or {})
end

local function say_last(name)
	local t = captured_chat[name]
	return t and t[#t]
end

local function find_plain(hay, needle)
	return hay:find(needle, 1, true)
end

local function count_occ(hay, needle)
	local c, i = 0, 1
	while true do
		local p = hay:find(needle, i, true)
		if not p then return c end
		c = c + 1
		i = p + #needle
	end
end

----------------------------------------------------------------------
-- The tests (wrapped so capture is always restored)
----------------------------------------------------------------------

local function run()
	core.chat_send_player = function(name, msg)
		captured_chat[name] = captured_chat[name] or {}
		local t = captured_chat[name]
		t[#t + 1] = msg
		return orig_chat(name, msg)
	end
	core.show_formspec = function(name, formname, fs)
		captured_fs[name] = captured_fs[name] or {}
		local t = captured_fs[name]
		t[#t + 1] = fs
		return orig_fs(name, formname, fs)
	end
	capture_reset()

	-- Fresh synthetic record; wipe anything a previous run left behind.
	smp_store.api.update_player_field(TNAME, "homes", {})
	local saved_default = cfg.homes.slots.default
	cfg.homes.slots.default = 2
	smp_core.close_session(TNAME, FORM)

	-- Observed strings, verbatim (08-ui-strings.md §8.6).
	eq(S("Home set"), "Home set", "string Home set")
	eq(S("Home deleted"), "Home deleted", "string Home deleted")
	eq(S("Home does not exist"), "Home does not exist", "string Home does not exist")
	eq(S("You reached home limits"), "You reached home limits",
		"string You reached home limits (plural)")
	eq(S("You renamed your home to @1", "rock"), "You renamed your home to rock",
		"string You renamed your home to @1")
	eq(S("Homes"), "Homes", "string Homes title")
	eq(S("Show More"), "Show More", "string Show More")
	eq(S("New Home"), "New Home", "string New Home")
	eq(S("Click to manage"), "Click to manage", "string Click to manage")

	----------------------------------------------------------------------
	-- T2 — create below the limit: exactly `Home set`, tab `Home <n>`
	----------------------------------------------------------------------
	local n = say_count(TNAME)
	local okc = H.do_sethome(TNAME, { x = 10, y = 64, z = -20 }, nil)
	ok(okc == true, "T2 create succeeds")
	eq(say_count(TNAME) - n, 1, "T2 exactly one chat line")
	eq(say_last(TNAME), "Home set", "T2 verbatim Home set")
	local homes = H.list(TNAME)
	eq(#homes, 1, "T2 one home stored")
	eq(homes[1].name, "Home 1", "T2 auto-name Home 1")
	eq(homes[1].id, 1, "T2 id is 1")
	eq(homes[1].icon, cfg.homes.default_icon, "T2 default icon")

	local rowfs = H.build_row(TNAME, { screen = "row" })
	ok(find_plain(rowfs, "home_1"), "T2 tab button home_1 rendered")
	ok(find_plain(rowfs, "Home 1"), "T2 tab label Home 1")
	ok(find_plain(rowfs, "Click to manage"), "T2 tab tooltip hint")
	ok(find_plain(rowfs, "New Home"), "T2 New Home tab present")

	n = say_count(TNAME)
	H.do_sethome(TNAME, { x = 11, y = 64, z = -20 }, nil)
	eq(say_last(TNAME), "Home set", "T2 second set: Home set")
	eq(H.list(TNAME)[2].name, "Home 2", "T2 auto-name Home 2")

	----------------------------------------------------------------------
	-- T1 — at the limit: exactly `You reached home limits`, nothing made
	----------------------------------------------------------------------
	n = say_count(TNAME)
	local okl = H.do_sethome(TNAME, { x = 12, y = 64, z = -20 }, nil)
	ok(okl == false, "T1 create refused at the limit")
	eq(say_count(TNAME) - n, 1, "T1 exactly one chat line")
	eq(say_last(TNAME), "You reached home limits", "T1 verbatim message")
	eq(#H.list(TNAME), 2, "T1 nothing created")
	-- Named form is refused the same way.
	n = say_count(TNAME)
	H.do_sethome(TNAME, { x = 12, y = 64, z = -20 }, "third")
	eq(say_last(TNAME), "You reached home limits", "T1 named create refused too")
	eq(#H.list(TNAME), 2, "T1 still nothing created")

	----------------------------------------------------------------------
	-- T5 — /homes <unknown>: exactly `Home does not exist`
	----------------------------------------------------------------------
	local homes_cmd = core.registered_chatcommands and
		core.registered_chatcommands["homes"]
	ok(homes_cmd ~= nil, "T5 /homes registered")
	if homes_cmd then
		n = say_count(TNAME)
		homes_cmd.func(TNAME, "definitely_not_a_home")
		eq(say_count(TNAME) - n, 1, "T5 exactly one chat line")
		eq(say_last(TNAME), "Home does not exist", "T5 verbatim message")
	end

	----------------------------------------------------------------------
	-- T3 — rename: title + tab labels change, id unchanged
	----------------------------------------------------------------------
	local id_before = H.list(TNAME)[1].id
	n = say_count(TNAME)
	local okr = H.do_rename(TNAME, 1, "rock")
	ok(okr == true, "T3 rename succeeds")
	eq(say_count(TNAME) - n, 1, "T3 exactly one chat line")
	eq(say_last(TNAME), "You renamed your home to rock", "T3 verbatim rename message")
	local h1 = H.get(TNAME, 1)
	ok(h1 ~= nil, "T3 home still addressable by id")
	eq(h1.id, id_before, "T3 id unchanged across rename")
	eq(h1.name, "rock", "T3 name updated")
	rowfs = H.build_row(TNAME, { screen = "row" })
	ok(find_plain(rowfs, "rock"), "T3 tab label shows the new name")
	ok(not find_plain(rowfs, "Home 1"), "T3 old tab label gone")
	local subfs = H.build_sub(h1)
	ok(find_plain(subfs, "rock"), "T3 submenu title shows the new name")
	ok(find_plain(subfs, "Teleport"), "T3 submenu has Teleport")
	ok(find_plain(subfs, "Change Icon"), "T3 submenu has Change Icon")
	ok(find_plain(subfs, "style[delete;textcolor=red]"), "T3 Delete is red [F0068]")

	----------------------------------------------------------------------
	-- T4 — delete: exactly `Home deleted`, tab removed
	----------------------------------------------------------------------
	n = say_count(TNAME)
	local okd = H.do_delete(TNAME, 2)
	ok(okd == true, "T4 delete succeeds")
	eq(say_count(TNAME) - n, 1, "T4 exactly one chat line")
	eq(say_last(TNAME), "Home deleted", "T4 verbatim Home deleted")
	eq(#H.list(TNAME), 1, "T4 home removed")
	rowfs = H.build_row(TNAME, { screen = "row" })
	ok(not find_plain(rowfs, "home_2"), "T4 tab button home_2 gone")
	ok(find_plain(rowfs, "home_1"), "T4 other tab intact")
	-- Deleting an unknown id is the T5 string too.
	n = say_count(TNAME)
	H.do_delete(TNAME, 99)
	eq(say_last(TNAME), "Home does not exist", "T4 unknown id message")

	----------------------------------------------------------------------
	-- T6 — more homes than homes.tabs_before_more -> Show More
	----------------------------------------------------------------------
	cfg.homes.slots.default = 9
	while #H.list(TNAME) < 4 do
		H.do_sethome(TNAME, { x = 20 + #H.list(TNAME), y = 64, z = -20 }, nil)
	end
	eq(#H.list(TNAME), 4, "T6 four homes created")
	rowfs = H.build_row(TNAME, { screen = "row" })
	ok(find_plain(rowfs, "Show More"), "T6 Show More rendered")
	eq(count_occ(rowfs, "item_image_button"), cfg.homes.tabs_before_more,
		"T6 only tabs_before_more home tabs shown")
	ok(find_plain(rowfs, "New Home"), "T6 New Home still present below limit")
	-- Show More target (PROPOSED, §10 V-32): the full row.
	local allfs = H.build_row(TNAME, { screen = "row", show_all = true })
	eq(count_occ(allfs, "item_image_button"), 4, "T6 Show More reveals every home")
	ok(not find_plain(allfs, "Show More"), "T6 no Show More when everything fits")
	cfg.homes.slots.default = saved_default

	----------------------------------------------------------------------
	-- T7 — icon choice persists in the store record
	----------------------------------------------------------------------
	ok(H.set_icon(TNAME, 1, "mcl_core:obsidian"), "T7 set icon")
	local rec = smp_store.api.get_player(TNAME)
	ok(rec ~= nil and type(rec.homes) == "table" and rec.homes[1] ~= nil and
		rec.homes[1].icon == "mcl_core:obsidian",
		"T7 icon lives in the persisted record (restart-safe)")
	rowfs = H.build_row(TNAME, { screen = "row" })
	ok(find_plain(rowfs, "mcl_core:obsidian"), "T7 tab renders the chosen icon")
	-- Choose Icon screen lists registered items with icons.
	local iconfs = H.build_icon({ screen = "icon", page = 1, query = "" }, H.get(TNAME, 1))
	ok(find_plain(iconfs, "Choose Icon"), "T7 Choose Icon title")
	ok(find_plain(iconfs, "mcl_beds:bed_red_bottom"), "T7 bed item listed")
	ok(find_plain(iconfs, "icon_search"), "T7 search field present")

	----------------------------------------------------------------------
	-- T8 — home id deleted while its submenu is open fails safely
	----------------------------------------------------------------------
	H.set_screen(TNAME, { screen = "sub", id = 1 })
	local sess = smp_core.get_session(TNAME, FORM)
	ok(sess ~= nil and sess.screen == "sub", "T8 submenu session open")
	H.do_delete(TNAME, 1)   -- deleted behind the open submenu
	n = say_count(TNAME)
	local fake_player = { get_player_name = function() return TNAME end }
	H.handle_fields(fake_player, { teleport = "true" })
	eq(say_count(TNAME) - n, 1, "T8 exactly one chat line")
	eq(say_last(TNAME), "Home does not exist", "T8 verbatim refusal")
	ok(smp_tp.warmup == nil or smp_tp.warmup[TNAME] == nil,
		"T8 no warm-up started for the stale id")
	sess = smp_core.get_session(TNAME, FORM)
	ok(sess ~= nil and sess.screen == "row", "T8 fell back to the Homes row")

	----------------------------------------------------------------------
	-- T9 — a home is never shown to anyone but its owner
	----------------------------------------------------------------------
	smp_store.api.update_player_field(TNAME, "homes", {})
	H.do_sethome(TNAME, { x = 1234, y = 65, z = -4321 }, nil)
	local own = H.list(TNAME)[1]
	local screens = {
		H.build_row(TNAME, { screen = "row" }),
		H.build_sub(own),
		H.build_rename({ screen = "rename" }, own),
		H.build_confirm(own),
		H.build_icon({ screen = "icon", page = 1, query = "" }, own),
	}
	for i, fs in ipairs(screens) do
		ok(not find_plain(fs, "1234") and not find_plain(fs, "-4321"),
			"T9 no coordinates on screen " .. i)
	end
	for target in pairs(captured_chat) do
		eq(target, TNAME, "T9 chat only ever addressed to the owner")
	end
	for target in pairs(captured_fs) do
		eq(target, TNAME, "T9 formspec only ever shown to the owner")
	end
	-- Data access is owner-scoped by construction: H.list/H.get take a
	-- single name and return that name's record only. /findplayer (f11)
	-- must consult the store through the same owner-scoped field — see
	-- f09 §4.8 and acceptance-tests X9.

	----------------------------------------------------------------------
	-- Cleanup: leave no test data behind
	----------------------------------------------------------------------
	smp_store.api.update_player_field(TNAME, "homes", {})
	cfg.homes.slots.default = saved_default
	smp_core.close_session(TNAME, FORM)
end

local okrun, err = pcall(run)
restore()
if not okrun then
	results.failed = results.failed + 1
	results.lines[#results.lines + 1] = "FAIL crashed: " .. tostring(err)
end

return results
