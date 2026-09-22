-- FriedcakeSMP — smp_ranks tier table as configuration data (f13 §4.1).
--
-- This file is the ONE place the tier model lives. Consumers must call
-- the perk API (perk.lua), never read rec.rank, so a change here
-- propagates to f03, f04, f08 and f09 automatically (§4.2.4).
--
-- Tier ids are default/tier1/tier2/tier3/media (shared §0.5). Donut
-- names (Donut+, ...) appear only in smp_ranks.display, i.e. only in
-- display text, never in config keys or stored records.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local function get_str(key, default)
	local raw = core.settings:get(key)
	if type(raw) == "string" and raw ~= "" then return raw end
	return default
end

local function get_num(key, default)
	local raw = core.settings:get(key)
	if type(raw) == "string" and raw ~= "" then
		local n = tonumber(raw)
		if n and n == n and n ~= math.huge and n > 0 then
			return math.floor(n)
		end
		core.log("warning", "[smp_ranks] ignoring invalid " .. key .. "=" .. raw)
	end
	return default
end

----------------------------------------------------------------------
-- Tier ids (§4.1)
----------------------------------------------------------------------

smp_ranks.tier_order = { "default", "tier1", "tier2", "tier3", "media" }

local tier_ids = {
	default = true, tier1 = true, tier2 = true, tier3 = true, media = true,
}

function smp_ranks.is_tier(id)
	return type(id) == "string" and tier_ids[id] == true
end

-- Display names. Donut names describe the reference server and appear
-- only in display text (shared §0.5); records and config use tier ids.
smp_ranks.display = {
	default = "Default",
	tier1   = "Donut+",
	tier2   = "Donut++",
	tier3   = "Donut+++",
	media   = "Media",
}

function smp_ranks.display_label(tier)
	return smp_ranks.S(smp_ranks.display[tier] or tostring(tier))
end

----------------------------------------------------------------------
-- Slot tables (§4.1)
--
-- Defaults per f09 §7 / f03 §7 / f04 §7:
--   homes  {2, 9, 27, 90}   — default LEGACY [S25], tier1..3 LIVE [S17]
--   ah     {9, 45, 90, 90}  — default and tier3 PROPOSED (V-72: tier3 is
--   orders {9, 45, 90, 90}     documented only as "at least" tier2)
--   media = tier3 (§4.1).
--
-- Overridable with the flattened keys the owning features already read
-- (homes.slots_default … orders.slots_tier3), so their configuration
-- flows through the perk API without either side hard-coding numbers.
----------------------------------------------------------------------

local function slots(prefix, dflt, t1, t2, t3)
	local t = {
		default = get_num(prefix .. ".slots_default", dflt),
		tier1   = get_num(prefix .. ".slots_tier1", t1),
		tier2   = get_num(prefix .. ".slots_tier2", t2),
		tier3   = get_num(prefix .. ".slots_tier3", t3),
	}
	t.media = t.tier3 -- media is tier3 (§4.1)
	return t
end

smp_ranks.slots = {
	homes  = slots("homes", 2, 9, 27, 90),
	ah     = slots("ah", 9, 45, 90, 90),
	orders = slots("orders", 9, 45, 90, 90),
}

function smp_ranks.slots_for(perk, tier)
	local t = smp_ranks.slots[perk]
	if not t then return nil end
	return t[tier] or t.default
end

----------------------------------------------------------------------
-- /rtp cooldown seconds (f08 §7)
--
-- Only tier1's shorter cooldown is documented [S27]; tier2/tier3/media
-- fall back to the default at lookup time (PROPOSED — see §10 V-76).
-- media aliases tier3 if it is configured.
----------------------------------------------------------------------

local cooldowns = {
	default = get_num("rtp.cooldown_default", 60),
	tier1   = get_num("rtp.cooldown_tier1", 30),
}
for _, id in ipairs({ "tier2", "tier3", "media" }) do
	local key = "rtp.cooldown_" .. id
	local raw = core.settings:get(key)
	if type(raw) == "string" and raw ~= "" then
		cooldowns[id] = get_num(key, cooldowns.default)
	end
end
cooldowns.media = cooldowns.media or cooldowns.tier3 -- media = tier3 (§4.1)
smp_ranks.cooldowns = cooldowns

function smp_ranks.cooldown_for(tier)
	return smp_ranks.cooldowns[tier] or smp_ranks.cooldowns.default
end

----------------------------------------------------------------------
-- Module configuration (f13 §7)
----------------------------------------------------------------------

smp_ranks.cfg = {
	-- A tier lasts 30 days per grant [S17].
	grant_days = get_num("ranks.grant_days", 30),
	-- No observed chat line carries a rank prefix [F0269]: default "".
	chat_prefix = get_str("ranks.chat_prefix", ""),
	-- Hourly dirty-candidate sweep (§8; PROPOSED).
	expiry_check_interval = get_num("ranks.expiry_check_interval", 3600),
	-- Store URL and blurb shown by /ranks (§4.2.9; PROPOSED).
	store_text = get_str("ranks.store_text", ""),
}
