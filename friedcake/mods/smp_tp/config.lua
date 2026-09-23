-- FriedcakeSMP — smp_tp configuration
-- spec/features/f08-teleport.md §7. Defaults are PROPOSED unless noted.
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local cfg = smp_tp and smp_tp.cfg or {}

local function setting(key, default)
	-- core.settings may be absent in test harnesses.
	if core.settings and core.settings.get then
		local v = core.settings:get("smp_tp." .. key)
		if v ~= "" and v ~= nil then return v end
	end
	return default
end

----------------------------------------------------------------------
-- Warm-up framework (§4.1)
----------------------------------------------------------------------

cfg.tp = cfg.tp or {}
-- 5 s warm-up. CLONE [C7]; PROPOSED outside RTP.
cfg.tp.warmup = tonumber(setting("tp.warmup", 5))
-- Movement > 1 node during warm-up cancels. LIVE for RTP [S27].
cfg.tp.cancel_move_distance = tonumber(setting("tp.cancel_move_distance", 1))
-- Accept/Deny formspec for requests. CLONE [C1]; the decided substitute
-- for clickable chat (shared/04-ui-kit.md §4.8).
cfg.tp.confirm_menu = setting("tp.confirm_menu", "true") == "true"
-- Per-kind cooldowns in seconds, tier-keyed. Only /rtp is evidenced
-- (LIVE [S27]); the others are PROPOSED mirrors of it.
cfg.tp.cooldown = {
	rtp   = { default = 60, tier1 = 30, tier2 = 30, tier3 = 30 },
	tpa   = { default = 30, tier1 = 30, tier2 = 30, tier3 = 30 },
	spawn = { default = 30, tier1 = 30, tier2 = 30, tier3 = 30 },
	warp  = { default = 30, tier1 = 30, tier2 = 30, tier3 = 30 },
	world = { default = 30, tier1 = 30, tier2 = 30, tier3 = 30 },
	back  = { default = 30, tier1 = 30, tier2 = 30, tier3 = 30 },
}
-- /back returns to the last death or teleport location; disabled by
-- default to preserve the stakes of death (PROPOSED, f08 §4.5.4).
cfg.tp.back_enabled = setting("tp.back_enabled", "false") == "true"

----------------------------------------------------------------------
-- /rtp (§4.2)
----------------------------------------------------------------------

cfg.rtp = cfg.rtp or {}
-- The menu was removed on the reference server 15 June 2026 [S14].
-- Bare /rtp acts directly (OBSERVED [F0037]).
cfg.rtp.menu_enabled = false
cfg.rtp.min_radius = tonumber(setting("rtp.min_radius", 500))
-- max_radius = world border minus 500, floored at min_radius + 1.
-- Resolved at load; nil until smp_tp.cfg.finalize() runs.
cfg.rtp.max_radius = nil
cfg.rtp.max_attempts = tonumber(setting("rtp.max_attempts", 10))
cfg.rtp.cooldown = {
	default = 60,
	tier1 = 30,   -- Donut+ had a shorter cooldown [S27]
	tier2 = 30,
	tier3 = 30,
}
-- Dimension scan bands. Overworld defaults per §7; nether and end are
-- resolved from mcl_vars in cfg.finalize().
cfg.rtp.scan = {
	overworld = { min = -32, max = 256 },
	nether    = nil,  -- mg_nether_min .. mg_bedrock_nether_top_max - 8
	["end"]   = nil,  -- mg_end_min .. mg_end_min + 128
}
-- RTP zone: a box at spawn. A player who STAYS inside for zone_delay is
-- teleported to the Overworld; pass-through does not count [S27].
-- Default: centred on the world spawn, 8x8, enabled. PROPOSED layout.
cfg.rtp.zone_delay = tonumber(setting("rtp.zone_delay", 3))
cfg.rtp.zone = {
	minx = -4, maxx = 4, minz = -4, maxz = 4,
}
-- Named regions: rectangular areas in the Overworld, mapped from the
-- reference server's proxy regions [S1]. {} = whole world. PROPOSED.
cfg.rtp.regions = {}
-- Spawn-protection exclusion radius (f15 owns protection; RTP must land
-- outside it, shared §X10). Reads the f15 key `world.spawn_protect_radius`
-- (default 128) directly — it is not namespaced under `smp_tp.`.
cfg.rtp.spawn_protect_radius = 128
if core.settings and core.settings.get then
	local v = core.settings:get("world.spawn_protect_radius")
	if v ~= "" and v ~= nil then
		cfg.rtp.spawn_protect_radius = tonumber(v) or 128
	end
end

----------------------------------------------------------------------
-- Teleport requests (§4.4)
----------------------------------------------------------------------

cfg.tpa = cfg.tpa or {}
cfg.tpa.expiry = tonumber(setting("tpa.expiry", 60))

----------------------------------------------------------------------
-- /spawn, /warp (§4.5)
----------------------------------------------------------------------

-- Named spawn lobbies. "main" is always available and uses
-- mcl_spawn.get_world_spawn_pos. Others are server configuration.
cfg.lobbies = {
	-- main = { x = 0, y = 72, z = 0 },  -- omit to use world spawn
}
-- Spawn utility locations (the former crates area, f16 [S25]).
cfg.warps = {
	-- crates = { x = 12, y = 70, z = -40 },
}

----------------------------------------------------------------------
-- /rtpqueue (f08 §4.3; lives in smp_rtpqueue but configured here)
----------------------------------------------------------------------

cfg.rtpqueue = cfg.rtpqueue or {}
cfg.rtpqueue.timeout = tonumber(setting("rtpqueue.timeout", 300))
cfg.rtpqueue.min_separation = 16
cfg.rtpqueue.max_separation = 32

----------------------------------------------------------------------
-- Dimension scan band resolution (runs once at load)
----------------------------------------------------------------------

function smp_tp.cfg.finalize()
	local band
	if mcl_vars then
		band = mcl_vars
		-- Nether: floor to just above the bedrock column, ceiling a few
		-- nodes below the bedrock top so the ceiling itself is never a
		-- landing (f08 §4.2.6).
		local nmin = band.mg_nether_min or -29072
		local nmax = (band.mg_bedrock_nether_top_max or nmin + 128) - 8
		cfg.rtp.scan.nether = { min = nmin, max = math.min(nmax, nmin + 127) }
		local emin = band.mg_end_min or -26880
		cfg.rtp.scan["end"] = { min = emin, max = emin + 128 }
		cfg.rtp.scan.overworld = {
			min = math.max(cfg.rtp.scan.overworld.min, band.mg_overworld_min or -128),
			max = math.min(cfg.rtp.scan.overworld.max, band.mg_overworld_max or 320),
		}
	end
	-- World border: max_radius = border minus 500, floored.
	-- This Luanti fork has no core.get_world_border binding; fall back
	-- to 30000 until one is added.
	local border = 30000
	if core.get_world_border then
		local ok, b = pcall(core.get_world_border)
		if ok and type(b) == "number" and b > 0 then border = b end
	end
	smp_tp._border = math.floor(border)
	local mr = math.floor(border) - 500
	cfg.rtp.max_radius = math.max(mr, cfg.rtp.min_radius + 1)
end

return cfg
