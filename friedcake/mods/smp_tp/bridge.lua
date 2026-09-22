-- FriedcakeSMP — smp_tp external bridges
--
-- Four cross-mod lookups owned by later-phase mods. Each bridge calls the
-- real implementation when that mod is loaded and otherwise falls back to
-- a PERMISSIVE default so f08 works standalone. When the owning mod lands,
-- its functions are picked up automatically; the TODO(fNN) markers are the
-- fallbacks only.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_tp.bridge = {}

-- f10 — combat tag. Permissive: nobody is tagged.
function smp_tp.bridge.is_tagged(name)
	if smp_combat and smp_combat.is_tagged then
		return smp_combat.is_tagged(name)
	end
	-- TODO(f10): permissive default until smp_combat lands.
	return false
end

-- f13 — rank tier. Permissive: everyone is the default tier.
function smp_tp.bridge.tier(name)
	if smp_ranks and smp_ranks.tier then
		return smp_ranks.tier(name)
	end
	-- TODO(f13): permissive default until smp_ranks.tier lands.
	return "default"
end

-- f11 — social block graph. Permissive: nobody blocks anybody.
function smp_tp.bridge.blocks(a, b)
	if smp_social and smp_social.blocks then
		return smp_social.blocks(a, b)
	end
	-- TODO(f11): permissive default until smp_social.blocks lands.
	return false
end

-- f12 — per-player settings. Permissive: no setting is stored.
function smp_tp.bridge.get_name(name, key)
	if smp_settings and smp_settings.get_name then
		return smp_settings.get_name(name, key)
	end
	-- TODO(f12): permissive default until smp_settings lands.
	return nil
end

return smp_tp.bridge
