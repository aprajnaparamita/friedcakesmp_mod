-- FriedcakeSMP — smp_combat / combatlog.lua
-- The anti-disconnect mechanism. spec/features/f10-combat.md §4.3.
--
-- When a tagged player disconnects:
--   1. every list in mcl_death_drop.registered_dropped_lists is dropped
--      at the logout position (iterate the registered list — never
--      hard-code the names, so Mineclonia changes propagate [M1]);
--   2. the kill is credited to last_attacker (statistics f14, bounty
--      §4.4 through the kill listeners);
--   3. the event is broadcast (combat.log_broadcast, PROPOSED);
--   4. player meta smp:combat_logged = 1 is set; on next join the player
--      respawns at mcl_spawn.get_world_spawn_pos and the flag clears.
--
-- mcl_keepInventory does NOT apply here: the logout path drops
-- explicitly, independent of the death path (§8).
--
-- Drop + credit + flag happen in one callback with no yields between
-- them (shared §2.3): a crash between the drop and the credit loses the
-- kill, so they must be one synchronous sequence.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_combat.combatlog = {}

----------------------------------------------------------------------
-- Kill listeners: smp_bounty registers its claim path here so the
-- bounty mod can depend on smp_combat without a circular dependency.
----------------------------------------------------------------------

smp_combat.kill_listeners = smp_combat.kill_listeners or {}

function smp_combat.register_on_kill(fn)
	if type(fn) == "function" then
		smp_combat.kill_listeners[#smp_combat.kill_listeners + 1] = fn
	end
end

----------------------------------------------------------------------
-- drop_death_lists: mirrors the mcl_death_drop death path exactly,
-- but runs at logout and at the logout position.
----------------------------------------------------------------------

function smp_combat.combatlog.drop_death_lists(player)
	if not (mcl_death_drop and mcl_death_drop.registered_dropped_lists) then
		return 0
	end
	local playerinv = player.get_inventory and player:get_inventory()
	local pos = player:get_pos()
	if not pos then return 0 end

	local void_deadly = false
	if mcl_worlds and mcl_worlds.is_in_void then
		local ok, _, deadly = pcall(mcl_worlds.is_in_void, pos)
		if ok and deadly then void_deadly = true end
	end

	-- One drop spot near the logout position, mirroring the death path's
	-- air search (§8). Falls back to the logout position itself.
	local spot = pos
	local spots = core.find_nodes_in_area(
		vector.offset(pos, -3, 0, -3), vector.offset(pos, 3, 0, 3), { "air" })
	if type(spots) == "table" and #spots > 0 then
		local visible = {}
		for i = 1, #spots do
			local s = spots[i]
			if not core.line_of_sight or core.line_of_sight(pos, s) then
				visible[#visible + 1] = s
			end
		end
		if #visible > 0 then spot = visible[math.random(#visible)] end
	end

	local dropped = 0
	for l = 1, #mcl_death_drop.registered_dropped_lists do
		local entry = mcl_death_drop.registered_dropped_lists[l]
		local inv = entry.inv
		if inv == "PLAYER" then
			inv = playerinv
		elseif type(inv) == "function" then
			inv = inv(player)
		end
		local listname = entry.listname
		if inv then
			local list = inv:get_list(listname) or {}
			for i = 1, #list do
				local stack = list[i]
				local p = { x = spot.x, y = spot.y, z = spot.z }
				local vanishing = false
				if mcl_enchanting and mcl_enchanting.has_enchantment then
					local ok, res = pcall(mcl_enchanting.has_enchantment,
						stack, "curse_of_vanishing")
					vanishing = ok and res or false
				end
				if not void_deadly and entry.drop and not vanishing then
					local def = core.registered_items
						and core.registered_items[stack:get_name()]
					if def and def.on_drop then
						-- Same call the death path makes; pcall because a
						-- failing on_drop must not abort the combat log.
						local ok, res = pcall(def.on_drop, stack, player, p)
						if ok and res then
							stack = res
						else
							core.log("warning",
								"[smp_combat] on_drop failed for "
								.. tostring(stack:get_name()))
						end
					end
					core.add_item(p, stack)
					dropped = dropped + 1
				end
			end
			inv:set_list(listname, {})
		end
	end
	if mcl_armor and mcl_armor.update then
		pcall(mcl_armor.update, player)
	end
	return dropped
end

-- Top-level alias: the §6 algorithm calls smp_combat.drop_death_lists.
smp_combat.drop_death_lists = smp_combat.combatlog.drop_death_lists

----------------------------------------------------------------------
-- credit_kill: statistics (f14) + kill listeners (bounty §4.4).
----------------------------------------------------------------------

function smp_combat.credit_kill(killer, victim, pos)
	local kname = smp_combat.name_of(killer)
	local vname = smp_combat.name_of(victim)
	if not kname or not vname or kname == vname then return false end
	-- Statistics (f14 not landed yet).
	-- TODO(f14): agree on the final stats key with the stats agent.
	if smp_stats and type(smp_stats.add) == "function" then
		local ok, err = pcall(smp_stats.add, kname, "kills", 1)
		if not ok then
			core.log("error", "[smp_combat] stats credit failed: " .. tostring(err))
		end
	end
	for _, fn in ipairs(smp_combat.kill_listeners) do
		local ok, err = pcall(fn, kname, vname, pos)
		if not ok then
			core.log("error",
				"[smp_combat] kill listener failed: " .. tostring(err))
		end
	end
	return true
end

----------------------------------------------------------------------
-- core.register_on_leaveplayer — the combat log itself.
----------------------------------------------------------------------

function smp_combat.on_leave(player)
	local name = player:get_player_name()
	if not smp_combat.is_tagged(name) then return false end
	local pos = player:get_pos()
	local attacker = smp_combat.last_attacker(name)

	-- One synchronous sequence: drop -> flag -> broadcast -> credit.
	-- No yields anywhere in this function (shared §2.3).
	smp_combat.combatlog.drop_death_lists(player)
	local meta = player:get_meta()
	if meta and meta.set_int then meta:set_int("smp:combat_logged", 1) end
	if smp_combat.cfg.combat.log_broadcast then
		core.chat_send_all(
			smp_combat.S("@1 has logged out during combat.", name))
	end
	if attacker and attacker ~= name then
		smp_combat.credit_kill(attacker, name, pos)
	end
	smp_combat.untag(name)
	return true
end

----------------------------------------------------------------------
-- core.register_on_joinplayer — respawn at world spawn after a
-- combat log, then clear the flag (T6).
----------------------------------------------------------------------

function smp_combat.on_join(player)
	local name = player:get_player_name()
	local meta = player:get_meta()
	if meta and meta.get_int and meta:get_int("smp:combat_logged") == 1 then
		local ok, pos = false, nil
		if mcl_spawn and mcl_spawn.get_world_spawn_pos then
			ok, pos = pcall(mcl_spawn.get_world_spawn_pos, player)
		end
		if ok and pos then
			player:set_pos(pos)
			meta:set_int("smp:combat_logged", 0)
			core.log("action",
				"[smp_combat] " .. name .. " respawned at world spawn after combat log")
		else
			-- Keep the flag: the next join retries the respawn rather
			-- than silently letting the combat-logger stay at the
			-- logout position.
			core.log("warning",
				"[smp_combat] world spawn unavailable for " .. name
				.. "; combat-log respawn deferred")
		end
	end
	-- T11: tags are in-memory; a player whose tag would have been live
	-- joins clean by construction. Nothing to persist, nothing to clear.
	return true
end
