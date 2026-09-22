-- FriedcakeSMP — smp_ranks
-- Rank tiers, lazy expiry, the perk API and the /ranks menu
-- (spec/features/f13-ranks.md).
--
-- Public surface (f13 §4.2.4) — every function accepts a player name
-- string OR a Player ObjectRef:
--   smp_ranks.tier(who)          -> "default"|"tier1"|"tier2"|"tier3"|"media"
--   smp_ranks.home_limit(who)    -> int
--   smp_ranks.ah_limit(who)      -> int
--   smp_ranks.order_limit(who)   -> int
--   smp_ranks.rtp_cooldown(who)  -> seconds
--   smp_ranks.chat_prefix(who)   -> "" with the default config (V-24)
--
-- Consumers MUST call these instead of reading rec.rank, so the tier
-- table lives in exactly one place (tiers.lua).
--
-- Commands:
--   /ranks                        perk table + store link  (LIVE [S2])
--   /rank set <player> <tier> [days]   grant a tier        (admin, PROPOSED)
--   /rank clear <player>               clear a tier        (admin, PROPOSED)
--
-- Submodules (loaded below in dependency order):
--   tiers.lua     the §4.1 tier table as configuration data
--   perk.lua      the five perk functions + name-or-player normalisation
--   grant.lua     grant/clear with 30-day stacking (§6)
--   expiry.lua    lazy expiry + hourly dirty-candidate sweep (§8)
--   formspec.lua  /ranks prompt menu rendered from live config
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_ranks = {}

local MODNAME = core.get_current_modname() or "smp_ranks"
smp_ranks.MODNAME = MODNAME
smp_ranks.S = core.get_translator(MODNAME)
local S = smp_ranks.S

local modpath = core.get_modpath(MODNAME)
for _, file in ipairs({
	"tiers.lua",
	"perk.lua",
	"grant.lua",
	"expiry.lua",
	"formspec.lua",
}) do
	local chunk, err = loadfile(modpath .. "/" .. file)
	if not chunk then
		error("[smp_ranks] cannot load " .. file .. ": " .. tostring(err))
	end
	local ok, lerr = pcall(chunk)
	if not ok then
		error("[smp_ranks] error in " .. file .. ": " .. tostring(lerr))
	end
end

----------------------------------------------------------------------
-- /ranks — the perk table and the configured store text (§4.2.9)
----------------------------------------------------------------------

core.register_chatcommand("ranks", {
	params = "",
	description = S("Show the rank perk table and the store link."),
	privs = {},
	func = function(player_name, _)
		if player_name == "" then
			return false, S("Run this command in-game.")
		end
		smp_ranks.show(player_name)
		return true
	end,
})

----------------------------------------------------------------------
-- /rank — grant or clear tiers (admin; shared §5.5)
----------------------------------------------------------------------

core.register_chatcommand("rank", {
	params = "set <player> <tier> [days] | clear <player>",
	description = S("Grant or clear a rank tier (admin)."),
	privs = { smp_admin = true },
	func = function(_, param)
		local usage = S("Usage: /rank set <player> <tier> [days] or /rank clear <player>")
		local sub, rest = (param or ""):match("^%s*(%S+)%s*(.*)$")
		if sub == "set" then
			local target, tier, days_txt =
				(rest or ""):match("^(%S+)%s+(%S+)%s*(%S*)$")
			if not target then return false, usage end
			if not smp_ranks.is_tier(tier) then
				return false, S("Unknown tier: @1. Tiers: default, tier1, tier2, tier3, media", tier)
			end
			local days = smp_ranks.cfg.grant_days
			if days_txt and days_txt ~= "" then
				days = tonumber(days_txt)
				if not days or days ~= days or days == math.huge
						or days < 1 or days ~= math.floor(days) then
					return false, S("Days must be a whole number of at least 1")
				end
			end
			local rec, err = smp_ranks.grant(target, tier, days)
			if not rec then
				core.log("warning", "[smp_ranks] grant failed: " .. tostring(err))
				return false, usage
			end
			local label = smp_ranks.display_label(tier)
			if days == 1 then
				return true, S("Granted @1 to @2 for @3 day", label, target, days)
			end
			return true, S("Granted @1 to @2 for @3 days", label, target, days)
		elseif sub == "clear" then
			local target = (rest or ""):match("^%s*(%S+)%s*$")
			if not target then return false, usage end
			smp_ranks.clear(target)
			return true, S("Cleared @1's rank", target)
		end
		return false, usage
	end,
})

core.log("action", "[smp_ranks] loaded: /ranks /rank — perk API ready "
	.. "(tier, home_limit, ah_limit, order_limit, rtp_cooldown)")
