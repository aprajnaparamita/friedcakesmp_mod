-- FriedcakeSMP — smp_settings / chat.lua
-- The seven observed Chat settings (f12 §3.2, §5.1), registered in the
-- observed row order. This is the only category with settings for now:
-- the other six categories are registered but empty — f12 §5.1 forbids
-- inventing rows, and f12 §10 keeps the V-39 candidate keys
-- (privacy.show_money, tp.tpa_enabled, general.hotbar, combat.*)
-- UNREGISTERED until their category opens with evidence.
--
-- Defaults: the first-open Chat screen [F0242] plus the §5 stored
-- schema. Four rows default to Friends/Followed, the rest to ON.
-- (§4.7's "most permissive" reading and §5.1's illustrative
-- `default = "ON"` disagree with that; flagged in §10 F12-B — flipping
-- is one line per setting.)
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_settings.register_category("chat", {
	title = smp_settings.S("Chat"),
	order = 1,
})

-- Tri-state cycle (f12 §7 settings.cycle_order): ON -> FRIENDS_FOLLOWED
-- -> OFF, read from config with the observed order as default.
local tri = smp_settings.cfg.cycle_order
-- Binary (f12 §5.1 sample, §4.4): ON -> OFF. FRIENDS_FOLLOWED is not
-- in these settings' value domain (V-37 decision, §10).
local bin = { "ON", "OFF" }

smp_settings.register("chat.public", {
	category = "chat",
	label    = smp_settings.S("Public Chat"),
	values   = bin,                       -- both states observed [F0242, F0245]
	default  = "ON",
})

smp_settings.register("chat.private_messages", {
	category = "chat",
	label    = smp_settings.S("Private Messages"),
	values   = tri,
	default  = "FRIENDS_FOLLOWED",
})

smp_settings.register("chat.server_messages", {
	category = "chat",
	label    = smp_settings.S("Server Chat Messages"),
	values   = bin,
	default  = "ON",
})

smp_settings.register("chat.hotbar_messages", {
	category = "chat",
	label    = smp_settings.S("Server Hotbar Messages"),
	values   = bin,
	default  = "ON",
})

smp_settings.register("chat.death_messages", {
	category = "chat",
	label    = smp_settings.S("Death Messages"),
	values   = tri,
	default  = "FRIENDS_FOLLOWED",
})

smp_settings.register("chat.advancements", {
	category = "chat",
	label    = smp_settings.S("Advancement Messages"),
	values   = tri,
	default  = "FRIENDS_FOLLOWED",
})

smp_settings.register("chat.join_leave", {
	category = "chat",
	label    = smp_settings.S("Join/Leave Messages"),
	values   = tri,
	default  = "FRIENDS_FOLLOWED",
})
