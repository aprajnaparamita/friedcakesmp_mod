-- FriedcakeSMP — smp_combat configuration
-- spec/features/f10-combat.md §7. Defaults are PROPOSED unless noted.
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local cfg = smp_combat and smp_combat.cfg or {}

local function setting(key, default)
	if core.settings and core.settings.get then
		local v = core.settings:get(key)
		if v ~= nil and v ~= "" then return v end
	end
	return default
end

cfg.combat = cfg.combat or {}

-- 20 s tag, refreshed by every hit. PROPOSED (V-12: duration
-- undocumented).
cfg.combat.tag_seconds = tonumber(setting("combat.tag_seconds", 20)) or 20

-- Elytra (f10 §4.2.5). Mineclonia ships no public toggle for gliding,
-- so elytra.lua hooks the entity prototype in core.registered_entities
-- plus the mcl_serverplayer capability gate (see its header for the
-- seam evidence). Default false: the hook checks this key at call time,
-- so leaving it off changes nothing. When true, elytra flight is
-- refused while a player is combat-tagged.
cfg.combat.disable_elytra = setting("combat.disable_elytra", "false") == "true"

-- Broadcast combat logs to chat (§4.3.3, PROPOSED; V-69).
cfg.combat.log_broadcast = setting("combat.log_broadcast", "true") == "true"

-- Blocked-while-tagged command list (§4.2.4). The ten commands are LIVE
-- [S7][S27]; `tp` and `home` are the aliases of `tpa` and `homes`
-- (f08 §2, f09 §2) closed so the block cannot be sidestepped (PROPOSED).
-- /sell is deliberately absent — it is allowed in combat (June 2026) [S3].
-- /msg, /ah and /bounty are also allowed (§4.2.4).
local DEFAULT_BLOCKED = {
	"rtp", "rtpqueue", "tpa", "tp", "tpahere", "tpaccept",
	"homes", "home", "spawn", "warp", "world", "shop",
}

local function parse_blocked()
	local raw = setting("combat.blocked_commands", "")
	local names = {}
	if raw ~= "" then
		for name in raw:gmatch("[^,]+") do
			name = name:match("^%s*(.-)%s*$"):lower()
			if name ~= "" then names[#names + 1] = name end
		end
	end
	if #names == 0 then names = DEFAULT_BLOCKED end
	local set = {}
	for _, n in ipairs(names) do set[n] = true end
	return names, set
end

cfg.combat.blocked_list, cfg.combat.blocked = parse_blocked()

-- Explosion attribution ring (§4.2.1, PROPOSED): a (pos, placer) pair is
-- honoured for `explosion_window` seconds within `explosion_radius` nodes
-- of the damage. Used for TNT and respawn anchors, which explode without
-- a player source in mcl_explosions.explode(pos, strength, info).
cfg.combat.explosion_window = tonumber(setting("combat.explosion_window", 10)) or 10
cfg.combat.explosion_radius = tonumber(setting("combat.explosion_radius", 12)) or 12

function cfg.combat.finalize()
	cfg.combat.blocked_list, cfg.combat.blocked = parse_blocked()
	cfg.combat.tag_seconds = tonumber(setting("combat.tag_seconds", cfg.combat.tag_seconds))
		or cfg.combat.tag_seconds
end
