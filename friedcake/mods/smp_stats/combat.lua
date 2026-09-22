-- FriedcakeSMP — smp_stats / combat.lua
-- Kill/death attribution (f14 §4.1.2, §4.1.3, T2).
--
-- With f10 (smp_combat) present its own hooks credit `kills` — its
-- dieplayer hook calls smp_combat.credit_kill, and its combat-log
-- leave hook credits the attacker the same way — so this file credits
-- `deaths` in every case and stands down on kills while smp_combat
-- exists, to avoid double-counting (§4.1.3: combat-log kills credit
-- kills AND deaths exactly once each).
--
-- Load order: smp_combat optionally depends on smp_stats, so
-- smp_stats loads first and its leaveplayer callback runs BEFORE
-- smp_combat.on_leave untags the logger — the tag this check reads is
-- still set (spec §4.3, claim contract).
--
-- Killer resolution when f10 is absent (V-79, engine-verified against
-- ~/dev/mineclonia-git @ mcl_damage, mcl_mobs/physics.lua):
--   reason.object             the puncher; for arrows, the arrow
--                             entity itself
--   mcl_reason.source         mcl_damage.finish_reason: source =
--                             source or direct; from_punch records
--                             source = luaentity._source_object for
--                             projectiles (the shooter) and
--                             direct   = the punching object
--   entity owner              a tamed wolf's kill credits its owner
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

-- Resolve an ObjectRef to the player name statistics should credit:
-- players directly, projectiles through their stored source, tamed
-- animals through their owner. Returns nil for everything else (mob
-- kills mob, environment kills).
function smp_stats.name_from_object(obj)
	if not obj then return nil end
	if obj.is_player and obj:is_player() and obj.get_player_name then
		return obj:get_player_name()
	end
	if obj.get_luaentity then
		local le = obj:get_luaentity()
		if le then
			-- Projectile carrying its shooter (arrow, fireball).
			if le._source_object then
				local n = smp_stats.name_from_object(le._source_object)
				if n then return n end
			end
			-- Tamed animal: credit the owner (mobs_mc wolf, ocelot...).
			if type(le.owner) == "string" and le.owner ~= "" then
				return le.owner
			end
		end
	end
	return nil
end

-- Resolve the killing player from a register_on_dieplayer reason.
function smp_stats.killer_from_reason(reason)
	if type(reason) ~= "table" then return nil end
	local n = smp_stats.name_from_object(reason.object)
	if n then return n end
	local mr = reason._mcl_reason
	if type(mr) == "table" then
		n = smp_stats.name_from_object(mr.source)
			or smp_stats.name_from_object(mr.direct)
		if n then return n end
	end
	return nil
end

----------------------------------------------------------------------
-- Player deaths (T2): the victim's death is always ours to credit.

core.register_on_dieplayer(function(victim, reason)
	if not victim or not victim.is_player or not victim:is_player() then
		return
	end
	local vname = victim:get_player_name()
	smp_stats.add(vname, "deaths", 1)
	-- f10 present: its own hook credits the opponent's `kills` through
	-- smp_combat.credit_kill (f10 §4.3). Stand down.
	if type(smp_combat) == "table" then return end
	local kname = smp_stats.killer_from_reason(reason)
	if kname and kname ~= vname then
		smp_stats.add(kname, "kills", 1)
	end
end)

----------------------------------------------------------------------
-- Combat-log deaths (f10 §4.3: the logger dies, the attacker gets the
-- kill). f10's leave hook — registered after ours, since f10 depends
-- on smp_stats — credits the attacker; ours credits the logger's
-- `deaths`, under exactly the condition f10 credits the kill: the
-- logger is tagged and has a real opponent.

core.register_on_leaveplayer(function(player, _)
	local name = player.get_player_name and player:get_player_name()
	if not name then return end
	if type(smp_combat) ~= "table" then return end
	if type(smp_combat.is_tagged) ~= "function" then return end
	if not smp_combat.is_tagged(name) then return end
	local attacker = type(smp_combat.last_attacker) == "function"
		and smp_combat.last_attacker(name) or nil
	if attacker and attacker ~= name then
		smp_stats.add(name, "deaths", 1)
	end
end)
