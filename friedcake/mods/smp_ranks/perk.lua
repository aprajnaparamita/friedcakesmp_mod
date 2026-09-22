-- FriedcakeSMP — smp_ranks perk API (f13 §4.2.4).
--
-- The deliverable of this feature: every consumer (f03, f04, f07, f08,
-- f09, f11) calls these five functions instead of reading the rank
-- record, so the tier table lives in exactly one place (tiers.lua).
--
-- Public surface — every function accepts EITHER a player name string
-- (f08 §6.2 assumed tier(name)) OR a Player ObjectRef (f09 §6 assumed
-- home_limit(player)):
--
--   smp_ranks.tier(who)          -> "default"|"tier1"|"tier2"|"tier3"|"media"
--   smp_ranks.home_limit(who)    -> int
--   smp_ranks.ah_limit(who)      -> int
--   smp_ranks.order_limit(who)   -> int
--   smp_ranks.rtp_cooldown(who)  -> int (seconds)
--   smp_ranks.chat_prefix(who)   -> string ("" with the default config)
--
-- Expiry is lazy (§6, §8): tier() computes from expires_at and never
-- mutates the record. An expired tier simply reads "default" (T2).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

----------------------------------------------------------------------
-- Name-or-player normalisation
----------------------------------------------------------------------

function smp_ranks.name_of(who)
	if type(who) == "string" then
		if who ~= "" then return who end
		return nil
	end
	if type(who) == "table" and type(who.get_player_name) == "function" then
		local ok, n = pcall(who.get_player_name, who)
		if ok and type(n) == "string" and n ~= "" then return n end
	end
	return nil
end

----------------------------------------------------------------------
-- tier()
----------------------------------------------------------------------

function smp_ranks.tier(who)
	local name = smp_ranks.name_of(who)
	if not name then return "default" end
	local rec = smp_store.api.get_player(name)
	local r = rec and rec.rank
	if type(r) == "table"
			and smp_ranks.is_tier(r.tier)
			and r.tier ~= "default"
			and type(r.expires_at) == "number"
			and r.expires_at > os.time() then
		return r.tier -- live tier, computed — no record mutation (T2)
	end
	return "default"
end

----------------------------------------------------------------------
-- Slot limits (perk in {"homes","ah","orders"} — §6)
----------------------------------------------------------------------

function smp_ranks.limit(who, perk)
	local tier = smp_ranks.tier(who)
	return smp_ranks.slots_for(perk, tier)
end

function smp_ranks.home_limit(who)
	return smp_ranks.limit(who, "homes")
end

function smp_ranks.ah_limit(who)
	return smp_ranks.limit(who, "ah")
end

function smp_ranks.order_limit(who)
	return smp_ranks.limit(who, "orders")
end

----------------------------------------------------------------------
-- /rtp cooldown (f08 §7)
----------------------------------------------------------------------

function smp_ranks.rtp_cooldown(who)
	return smp_ranks.cooldown_for(smp_ranks.tier(who))
end

----------------------------------------------------------------------
-- Optional chat prefix (§4.2.7)
--
-- ranks.chat_prefix defaults to "" — OBSERVED by absence: no chat line
-- carries a rank prefix [F0269, F0282, F0283], V-24. smp_social calls
-- this as chat_prefix(name) and falls back to "" on anything empty.
--
-- When a server does configure it, the template is a literal prefix
-- with @1 substituted by the player's display tier name (PROPOSED —
-- the spec does not describe the configured form).
----------------------------------------------------------------------

function smp_ranks.chat_prefix(who)
	local tpl = smp_ranks.cfg.chat_prefix
	if type(tpl) ~= "string" or tpl == "" then return "" end
	local label = smp_ranks.display_label(smp_ranks.tier(who))
	return (tpl:gsub("@1", function() return label end))
end
