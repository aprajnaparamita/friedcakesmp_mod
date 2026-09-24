-- FriedcakeSMP — smp_combat
-- Combat tag, blocked-command list and combat log (f10 §4.2, §4.3).
--
-- The tag is in-memory ONLY (f10 §5.1): a server restart must look like
-- a normal join, because a crashed process cannot run the logout path —
-- a crash IS a combat log (T11).
--
-- Public contract (f05, f06 and f08 already stub it with TODO(f10)):
--   smp_combat.is_tagged(name_or_player) -> boolean
--   smp_combat.tag(victim, attacker) / smp_combat.untag(who)
--   smp_combat.last_attacker(name_or_player) -> string | nil
--   smp_combat.resolve_attacker(obj) -> string | nil
--   smp_combat.pvp_allowed(victim, attacker) -> boolean
--   smp_combat.killer_from(reason) -> string | nil
--   smp_combat.register_on_kill(fn(killer, victim, pos))  -- smp_bounty
--
-- Commands:
--   /combat untag <player>       clear a combat tag (smp_admin)
--
-- combat.disable_elytra (§4.2.5) is enforced by elytra.lua: while a
-- player is tagged an elytra launch is refused and any glide ends.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_combat = {}
smp_combat.S = S
smp_combat.cfg = {}

local MP = core.get_modpath(core.get_current_modname())
dofile(MP .. "/config.lua")
dofile(MP .. "/tag.lua")
dofile(MP .. "/attribution.lua")
dofile(MP .. "/blocks.lua")
dofile(MP .. "/countdown.lua")
dofile(MP .. "/combatlog.lua")
dofile(MP .. "/elytra.lua")

----------------------------------------------------------------------
-- Engine callbacks. Named functions so the dev harness and test.lua can
-- invoke them with the exact engine signatures.
----------------------------------------------------------------------

-- Melee (§4.2.1): core.register_on_punchplayer(player, hitter,
-- time_from_last_punch, tool_capabilities, dir, damage).
-- Follows the §6 algorithm: no damage threshold — any punch between two
-- players tags both (PROPOSED, recorded in §10).
function smp_combat.on_punch(victim, hitter)
	if not victim or not victim.is_player or not victim:is_player() then
		return
	end
	local attacker = smp_combat.resolve_attacker(hitter)
	if not attacker then return end -- environment: no tag
	smp_combat.try_tag_exchange(victim, attacker)
end

-- Arrows and explosions (§4.2.1, §8):
--   * arrows: Mineclonia deals arrow damage with source = the arrow's
--     `_shooter` [M1], so reason._mcl_reason.source is the shooter;
--   * punched end crystals: source is the puncher (mcl_end);
--   * TNT / respawn anchors: no player source — fall back to the 10 s
--     (pos, placer) ring buffer.
function smp_combat.on_hpchange(player, hp_change, reason)
	if not hp_change or hp_change >= 0 then return end
	if not player or not player.is_player or not player:is_player() then
		return
	end
	if type(reason) ~= "table" then return end
	local mcl = type(reason._mcl_reason) == "table"
		and reason._mcl_reason or reason
	local attacker
	local src = mcl.source
	if src ~= nil then
		attacker = smp_combat.resolve_attacker(src)
	end
	if not attacker and mcl.type == "explosion" then
		-- TNT explodes with direct = the primed entity; anchors with
		-- neither. Key the ring off the entity, else the victim.
		local center
		if src ~= nil and src.get_pos then center = src:get_pos() end
		if not center and mcl.direct and mcl.direct.get_pos then
			center = mcl.direct:get_pos()
		end
		if not center then center = player:get_pos() end
		attacker = smp_combat.attribution.nearest_placer(
			center, smp_combat.name_of(player))
	end
	if not attacker and reason.type == "punch" then
		attacker = smp_combat.resolve_attacker(reason.object)
	end
	if not attacker then return end
	smp_combat.try_tag_exchange(player, attacker)
end

-- Death (§4.2.7, §4.2.8): credit the killer from the reason, else the
-- last attacker — /kill (f11) or any suicide must not deny a kill or a
-- bounty. Untag both sides: the victim, their opponent, and anyone
-- whose opponent was the victim.
function smp_combat.on_die(victim, reason)
	if not victim or not victim.is_player or not victim:is_player() then
		return
	end
	local vname = victim:get_player_name()
	local pos = victim:get_pos()
	local was_tagged = smp_combat.is_tagged(vname)
	local opponent = smp_combat.killer_from(reason)
	if not opponent and was_tagged then
		opponent = smp_combat.last_attacker(vname)
	end

	-- Credit BEFORE untagging: the last attacker is read from the tag.
	if opponent and opponent ~= vname then
		smp_combat.credit_kill(opponent, vname, pos)
	end

	-- Untag on the death of the player or of the opponent (§4.2.7).
	smp_combat.untag(vname)
	if opponent then smp_combat.untag(opponent) end
	for name, t in pairs(smp_combat.tags) do
		if t.last_attacker == vname then
			smp_combat.untag(name)
		end
	end
end

----------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------

core.register_on_punchplayer(smp_combat.on_punch)
core.register_on_player_hpchange(smp_combat.on_hpchange)
core.register_on_chatcommand(smp_combat.on_chatcommand)
core.register_on_leaveplayer(smp_combat.on_leave)
core.register_on_joinplayer(smp_combat.on_join)
core.register_on_dieplayer(smp_combat.on_die)
core.register_on_placenode(smp_combat.attribution.on_placenode)
core.register_on_punchnode(smp_combat.attribution.on_punchnode)
core.register_globalstep(function(dtime)
	smp_combat.countdown.step(dtime)
	-- combat.disable_elytra (§4.2.5): a no-op unless the key is true.
	smp_combat.elytra.step()
end)

-- The elytra entity def is registered by Mineclonia's `playerphysics`
-- mod, whose load order relative to smp_combat is unspecified, so the
-- hook installs once every mod has loaded. The dev harness has no
-- core.register_on_mods_loaded — it installs eagerly there (and the
-- wrapper itself re-checks on every step, so a late def is picked up).
if core.register_on_mods_loaded then
	core.register_on_mods_loaded(smp_combat.elytra.install)
else
	smp_combat.elytra.install()
end

----------------------------------------------------------------------
-- /combat untag <player> (admin)
----------------------------------------------------------------------

core.register_chatcommand("combat", {
	params = S("untag <player>"),
	description = S("Clear a combat tag (admin)."),
	privs = { smp_admin = true },
	func = function(player_name, param)
		local target = param and param:match("^%s*(.-)%s*$") or ""
		if target == "" then
			return false, S("Usage: /combat untag <player>")
		end
		if not smp_combat.is_tagged(target) then
			return false, S("@1 is not tagged.", target)
		end
		smp_combat.untag(target)
		return true, S("Cleared combat tag for @1.", target)
	end,
})

core.log("action",
	"[smp_combat] loaded: tag " .. tostring(smp_combat.cfg.combat.tag_seconds)
	.. "s, " .. tostring(#smp_combat.cfg.combat.blocked_list)
	.. " blocked commands, combat log ready")
