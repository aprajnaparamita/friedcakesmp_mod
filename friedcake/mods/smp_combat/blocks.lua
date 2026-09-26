-- FriedcakeSMP — smp_combat / blocks.lua
-- The blocked-while-tagged command list and its enforcement.
-- spec/features/f10-combat.md §4.2.4.
--
-- Enforced with core.register_on_chatcommand returning true, which
-- cancels the command before it runs (builtin/game/chat.lua runs the
-- callbacks first and skips the command when one returns truthy).
--
-- Allowed while tagged, deliberately absent from the list:
--   /sell   — explicitly enabled for combat in June 2026 [S3]
--   /msg    — §4.2.4
--   /ah     — browsing is allowed (§4.2.4)
--   /bounty — no escape and no teleport; also used to fund fights
--
-- /kill is BLOCKED while tagged (S07/CB-2): a tagged player must not
-- be able to self-kill to hand kill credit — and a bounty — to a
-- friend. f10 §4.2.8 said /kill should credit the last attacker
-- instead; the credit survives for statistics, the payout does not
-- (see f10 §10, S07 record).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_combat.blocks = {}

function smp_combat.blocks.is_blocked(command)
	if type(command) ~= "string" then return false end
	return smp_combat.cfg.combat.blocked[command:lower()] == true
end

-- core.register_on_chatcommand(function(name, command, param))
function smp_combat.on_chatcommand(name, command, param)
	if not smp_combat.is_tagged(name) then return nil end
	if not smp_combat.blocks.is_blocked(command) then return nil end
	core.chat_send_player(name,
		smp_combat.S("You cannot use /@1 during combat.", command))
	return true -- cancels the command
end
