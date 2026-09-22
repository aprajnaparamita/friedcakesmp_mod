-- FriedcakeSMP — smp_stats / mobs.lua
-- mobs_killed (f14 §4.1 table [M1], T3): wrap `on_die` on every
-- mobs_mc:* entity definition in core.register_on_mods_loaded.
--
-- Mineclonia calls `self:on_die(pos, mcl_reason)` from
-- mcl_mobs/physics.lua only when the definition defines on_die, so
-- every mobs_mc:* def gets a wrapper — the original may be nil. The
-- wrapper calls the original first (its return value is preserved:
-- physics.lua treats `true` as "death handled, remove now") and then
-- credits the killer.
--
-- V-79 (engine-verified): mcl_damage.from_punch records
-- mcl_reason.direct = the punching object and mcl_reason.source =
-- the ultimate source (an arrow's shooter via
-- luaentity._source_object); finish_reason folds source = source or
-- direct. smp_stats.name_from_object walks source -> direct, then
-- owner for tamed killers. Only a player-backed killer credits
-- stats — a creeper killing a cow credits nobody (T3: "for the
-- killer only").
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

core.register_on_mods_loaded(function()
	local wrapped = 0
	for name, def in pairs(core.registered_entities) do
		if type(name) == "string" and name:match("^mobs_mc:")
		   and type(def) == "table" and not def._stats_wrapped then
			local orig = def.on_die
			def.on_die = function(self, pos, mcl_reason, ...)
				local ret
				if orig then
					ret = orig(self, pos, mcl_reason, ...)
				end
				local mr = type(mcl_reason) == "table" and mcl_reason or nil
				local kname = mr
					and smp_stats.name_from_object(mr.source or mr.direct)
				if kname then
					smp_stats.add(kname, "mobs_killed", 1)
				end
				return ret
			end
			def._stats_wrapped = true
			wrapped = wrapped + 1
		end
	end
	core.log("action", "[smp_stats] wrapped on_die on " .. wrapped
		.. " mobs_mc:* entity definitions")
end)
