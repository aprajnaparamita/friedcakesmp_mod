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

-- Hopper extraction (f07 §4.6.8): optional, off by default. There is
-- no hopper hook for virtual node metadata yet; the config key exists
-- so an implementation can be added without a schema change. See f07
-- §10.
function smp_spawners.performance.hopper_enabled()
	return cfg.hopper_extraction and true or false
end
