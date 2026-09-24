-- FriedcakeSMP — smp_spawners / performance.lua
-- Node-timer lifecycle and the no-op callbacks. f07 §4.8, goal G1.
--
-- Budget (shared §2.7): no ABMs, at most one node timer per spawner,
-- O(1) accrual, menus render only the visible page. This module owns
-- the one timer each spawner may have.
--
-- accrual_mode active_only (default): the node timer only runs while
-- the map block is active, and accrue() clamps each tick, so a long
-- log-off produces at most 2 x timer_interval of output (f07 §4.5).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local cfg = smp_spawners.cfg

smp_spawners.performance = {}

function smp_spawners.performance.timer()
	return core.get_node_timer
end

function smp_spawners.performance.start_timer(pos)
	local ok, err = pcall(function()
		core.get_node_timer(pos):start(cfg.timer_interval)
	end)
	if not ok then
		core.log("error",
			"[smp_spawners] start_timer failed: " .. tostring(err))
	end
end

function smp_spawners.performance.stop_timer(pos)
	local ok, err = pcall(function()
		core.get_node_timer(pos):stop()
	end)
	if not ok then
		core.log("error",
			"[smp_spawners] stop_timer failed: " .. tostring(err))
	end
end

-- Hopper extraction (f07 §4.6.8): optional, off by default.
function smp_spawners.performance.hopper_enabled()
	return cfg.hopper_extraction and true or false
end

-- Pull adapter for mcl_hoppers: the node has no real inventory, so the
-- generic container machinery is blocked (container = 7) and hoppers
-- are routed here instead (mcl_hoppers init.lua:62-70 calls
-- `_on_hopper_out(uppos, pos)` before any generic pull).
--
--   pos   the spawner (hopper's node above)
--   hpos  the hopper that is pulling
--
-- One whole item per pull, the alphabetically first stored item first,
-- and only when the hopper's inventory reports room for it. Returns
-- true only when an item actually moved.
--
-- f07 §4.6.8 says extraction is off by default, so the gate is the
-- first thing checked — with spawners.hopper_extraction = false this
-- never touches storage.
function smp_spawners.performance.hopper_extract(pos, hpos)
	if not cfg.hopper_extraction then return false end

	-- f07 §4.5: accrue before the state object that gets written, so a
	-- hopper pull never takes output the spawner had not yet produced.
	smp_spawners.accrue(pos)

	local state = smp_spawners.read_state(pos)
	if not state then return false end

	local names = {}
	for name, count in pairs(state.store) do
		if math.floor((count or 0) + 0.5 - 1e-9) >= 1 then
			names[#names + 1] = name
		end
	end
	if #names == 0 then return false end
	table.sort(names)
	local name = names[1]

	local hinv = core.get_meta(hpos):get_inventory()
	if not hinv then return false end
	local one = ItemStack(name)
	one:set_count(1)
	if hinv.room_for_item and not hinv:room_for_item("main", one) then
		return false
	end

	-- Validate done; no yields from here on (shared §2.3).
	state.store[name] = state.store[name] - 1
	smp_spawners.write_state(state)
	hinv:add_item("main", one)
	return true
end
