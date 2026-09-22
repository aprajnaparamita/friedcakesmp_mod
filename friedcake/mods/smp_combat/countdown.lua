-- FriedcakeSMP — smp_combat / countdown.lua
-- Action-bar countdown while tagged. spec/features/f10-combat.md §4.2.3.
--
-- Display: `In combat: 20s` (PROPOSED string, §3) on the action-bar
-- channel of mcl_title — the same channel the observed `Delivering...`
-- indicator uses [F0226].
--
-- NOTE on `stay`: Mineclonia's mcl_title.set converts `stay` from
-- gameticks to seconds (gametick_to_secondes divides by 20), so
-- stay = 40 means 2 seconds. The bar is refreshed once per second; a
-- 2 s stay means it never flickers between refreshes and clears itself
-- shortly after the tag expires even if no explicit remove runs.
--
-- Budget: O(tagged players) once per second (shared §2.7).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_combat.countdown = {}

local accumulator = 0

function smp_combat.countdown.show(name)
	if not (mcl_title and mcl_title.set) then return end
	local left = smp_combat.seconds_left(name)
	if not left then return end
	local player = core.get_player_by_name(name)
	if not player then return end
	mcl_title.set(player, "actionbar", {
		text = smp_combat.S("In combat: @1s", math.ceil(left)),
		stay = 40, -- gameticks = 2 s (see header)
	})
end

function smp_combat.countdown.clear(name)
	if not (mcl_title and mcl_title.remove) then return end
	local player = core.get_player_by_name(name)
	if player then mcl_title.remove(player, "actionbar") end
end

-- Registered as a globalstep callback from init.lua.
function smp_combat.countdown.step(dtime)
	accumulator = accumulator + dtime
	if accumulator < 1 then return end
	accumulator = 0
	local now = os.time()
	-- Setting the current key to nil during pairs() is legal in Lua.
	for name, t in pairs(smp_combat.tags) do
		if t.expires <= now then
			smp_combat.untag(name) -- also clears the action bar
		else
			smp_combat.countdown.show(name)
		end
	end
end
