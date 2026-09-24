-- FriedcakeSMP — smp_combat / elytra.lua
-- Elytra flight disable while combat-tagged (f10 §4.2.5).
--
-- When combat.disable_elytra is true, players who are combat-tagged cannot
-- start elytra flight, and any active glide is ended immediately.
-- The hook works by mutating the elytra entity prototype's attach method
-- and checking the tag in the globalstep for already-flying players.
--
-- The Mineclonia elytra entity is registered as "mcl_armor:elytra_entity"
-- by playerphysics/elytra.lua. The attach method is called when a player
-- double-jumps while falling with an elytra equipped.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_combat.elytra = {}
local E = smp_combat.elytra

local elytra_entity_name = "mcl_armor:elytra_entity"
local original_attach = nil
local hook_installed = false

-- Called once all mods are loaded (or eagerly in dev harness) to wrap
-- the elytra entity's attach method.
function E.install()
	if hook_installed then return end
	local def = core.registered_entities and core.registered_entities[elytra_entity_name]
	if not def then
		-- Entity not registered yet (load order); will be picked up on next globalstep
		return
	end
	if def.attach and not def._smp_combat_elytra_wrapped then
		original_attach = def.attach
		def.attach = function(self, player)
			if smp_combat.cfg.combat.disable_elytra and smp_combat.is_tagged(player) then
				core.chat_send_player(player:get_player_name(),
					smp_combat.S("You cannot use elytra during combat."))
				return
			end
			return original_attach(self, player)
		end
		def._smp_combat_elytra_wrapped = true
		hook_installed = true
		core.log("action", "[smp_combat] elytra disable hook installed")
	end
end

-- Called every globalstep from init.lua to:
-- 1. Retry install if the entity wasn't ready yet
-- 2. Force-detach already-flying players who become tagged
function E.step()
	if not smp_combat.cfg.combat.disable_elytra then return end

	-- Retry install if entity appeared late
	if not hook_installed then
		E.install()
	end

	-- Scan all tagged players; if any are currently attached to an elytra
	-- entity, force-detach them.
	for name in pairs(smp_combat.tags or {}) do
		local player = core.get_player_by_name(name)
		if player then
			local attach = player:get_attach()
			if attach then
				local le = attach:get_luaentity()
				if le and le.name == elytra_entity_name then
					-- Detach the elytra entity (calls its detach method)
					le:detach(player)
					core.chat_send_player(name,
						smp_combat.S("Your elytra flight was ended by the combat tag."))
				end
			end
		end
	end
end