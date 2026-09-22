-- FriedcakeSMP — smp_admin
-- Registers privileges used by every other smp_* mod. The privileges
-- are declared once here, in one place, so feature agents don't have to
-- remember to register them. spec/shared/05-command-reference.md §5.5.
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

-- Privileges granted by /grant <name> smp_admin  /grant ... smp_moderator
-- The descriptions are written for staff, not for the player.

core.register_privilege("smp_admin", {
	description = S("Full FriedcakeSMP administration: edit money, reload config, run tests."),
	give_to_singleplayer = false,
})

core.register_privilege("smp_moderator", {
	description = S("FriedcakeSMP moderation: read the ledger, see hidden info."),
	give_to_singleplayer = false,
})

-- Privileges added by later features will register themselves in their own
-- mod; smp_admin does not own them.

core.log("action", "[smp_admin] privileges registered: smp_admin, smp_moderator")
