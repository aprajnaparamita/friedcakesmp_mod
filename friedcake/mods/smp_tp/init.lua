-- FriedcakeSMP — smp_tp
-- Teleportation framework (f08): warm-up path, /rtp, teleport requests,
-- /spawn, /warp, /world, /back.
--
-- The warm-up framework in warmup.lua is the real deliverable: every
-- other teleport feature (including f09's /home) rides on
-- smp_tp.teleport_with_warmup(player, pos, kind).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_tp = {}
smp_tp.S = S
smp_tp.cfg = {}

-- Load order matters only where a file extends smp_tp at require time.
dofile(core.modpath("config.lua"))
smp_tp.cfg.finalize()
dofile(core.modpath("bridge.lua"))
dofile(core.modpath("state.lua"))
dofile(core.modpath("warmup.lua"))
dofile(core.modpath("rtp.lua"))
dofile(core.modpath("requests.lua"))
dofile(core.modpath("formspec.lua"))
dofile(core.modpath("commands.lua"))

----------------------------------------------------------------------
-- Leave/death bookkeeping (f08 §4.4.6, §8: re-validate at fire time;
-- requests involving a dead/left player are cancelled).
----------------------------------------------------------------------

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	smp_tp.cancel_warmup(name, true)
	smp_tp.cancel_requests_of(name)
	smp_tp.clear_state(name)
end)

core.register_on_dieplayer(function(player)
	local name = player:get_player_name()
	smp_tp.cancel_warmup(name)
	smp_tp.cancel_requests_of(name)
	local st = smp_tp.get_state(name)
	-- Death location for /back (disabled by default).
	local pos = player:get_pos()
	st.last_death = { x = math.floor(pos.x), y = math.floor(pos.y), z = math.floor(pos.z) }
end)

----------------------------------------------------------------------
-- Globalstep: 1 Hz request-expiry sweep and RTP zone check.
-- O(online players) per second (shared §2.7).
----------------------------------------------------------------------

core.register_globalstep(function(dtime)
	smp_tp.state_globalstep(dtime)
	smp_tp.rtp_zone_step(dtime)
end)

----------------------------------------------------------------------
-- f08 §4.6 (ender pearls): LOW PRIORITY, not implemented here.
-- Removing thrown pearls on the thrower's death requires hooking
-- mcl_throwing:ender_pearl_entity's on_throw, which is owned by the
-- Mineclonia pearl entity; recorded in f08 §10 (V-68) for the
-- integrator to sequence against f10.
----------------------------------------------------------------------

core.log("action",
	"[smp_tp] loaded: warm-up framework, /rtp, requests, /spawn, /warp, /world, /back")

return smp_tp
