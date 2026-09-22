-- FriedcakeSMP — smp_bounty
-- Escrowed bounties (f10 §4.4).
--
-- Commands:
--   /bounty                      bounty list, largest first
--   /bounty <player>             one player's bounty
--   /bounty add <player> amount  place or raise a bounty (escrowed)
--   /bounties                    alias of /bounty [S24]
--   /bountyadmin clear <player>  remove a bounty, pro-rata refund (admin)
--
-- The claim path runs through smp_combat's kill listeners, so it fires
-- for normal deaths, /kill credit (f11) and combat-log kills alike
-- (§4.4.3, T5, T7).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

smp_bounty = {}
smp_bounty.S = S
smp_bounty.cfg = {}

local function setting(key, default)
	if core.settings and core.settings.get then
		local v = core.settings:get(key)
		if v ~= nil and v ~= "" then return v end
	end
	return default
end

-- bounty.min_amount $1,000 (§7; dollars in settings, cents internally).
do
	local cents = smp_core.parse_amount(tostring(setting("bounty.min_amount", "1000")))
	smp_bounty.cfg.min_amount = cents or 100000
end
-- bounty.pair_cooldown 3,600 s per killer–target pair (§4.4.4).
smp_bounty.cfg.pair_cooldown =
	tonumber(setting("bounty.pair_cooldown", "3600")) or 3600

local MP = core.get_modpath(core.get_current_modname())
dofile(MP .. "/escrow.lua")
dofile(MP .. "/abuse.lua")

----------------------------------------------------------------------
-- Public surface used by smp_combat's §6 pseudo-code
----------------------------------------------------------------------

-- Returns true when a payout would be refused (any abuse rule).
-- `pos` is optional so the two-argument pseudo-code still works.
function smp_bounty.is_abuse(killer, victim, pos)
	return smp_bounty.abuse.check(killer, victim, pos) ~= nil
end

----------------------------------------------------------------------
-- Claim path (§4.4.3): the killer receives the whole bounty from
-- escrow; a broadcast announces it. Validate everything before the
-- first mutation; the payout and the cooldown record are synchronous.
----------------------------------------------------------------------

function smp_bounty.try_claim(killer, victim, pos)
	local kname = smp_combat.name_of(killer)
	local vname = smp_combat.name_of(victim)
	if not kname or not vname or kname == vname then return false end

	local b = smp_bounty.get(vname)
	if not b or (b.total or 0) <= 0 then return false end

	local refusal = smp_bounty.abuse.check(kname, vname, pos)
	if refusal then
		core.log("action", "[smp_bounty] payout to " .. kname .. " on "
			.. vname .. " refused: " .. refusal)
		return false
	end

	local paid = smp_bounty.escrow_payout(b, kname)
	if paid <= 0 then return false end

	smp_bounty.abuse.record_claim(kname, vname)
	core.chat_send_all(S("@1 claimed the @2 bounty on @3.",
		kname, smp_core.fmt_money(paid, "body"), vname))
	return true
end

smp_combat.register_on_kill(smp_bounty.try_claim)

-- Remember IPs while they are knowable (see abuse.lua header).
core.register_on_joinplayer(function(player)
	smp_bounty.abuse.remember_ip(player:get_player_name())
end)
core.register_on_leaveplayer(function(player)
	smp_bounty.abuse.remember_ip(player:get_player_name())
end)

----------------------------------------------------------------------
-- /bounty
----------------------------------------------------------------------

local function resolve_target(raw)
	if not raw or raw == "" then return nil end
	local rec = smp_store.api.get_player(raw)
	if rec and type(rec.name) == "string" and rec.name ~= "" then
		return rec.name
	end
	if core.player_exists and core.player_exists(raw) then return raw end
	local lc = raw:lower()
	local names = smp_store.api.all_player_names()
	for i = 1, #names do
		if names[i]:lower() == lc then return names[i] end
	end
	return nil
end

local function bounty_list_lines()
	local rows = {}
	for _, b in pairs(smp_bounty.db.bounties) do
		if (b.total or 0) > 0 then
			rows[#rows + 1] = { target = b.target, total = b.total }
		end
	end
	if #rows == 0 then return { S("There are no bounties.") } end
	table.sort(rows, function(a, b)
		if a.total == b.total then return a.target < b.target end
		return a.total > b.total
	end)
	local out = { S("--- Bounties ---") }
	for i = 1, #rows do
		out[#out + 1] = S("@1. @2 — @3", i, rows[i].target,
			smp_core.fmt_money(rows[i].total, "body"))
	end
	return out
end

local function bounty_add(player_name, rest)
	local target_raw, amount_raw
	if rest then
		target_raw, amount_raw = rest:match("^(%S+)%s+(.+)$")
	end
	if not target_raw then
		return false, S("Usage: /bounty add <player> <amount>")
	end
	local target = resolve_target(target_raw)
	if not target then
		return false, S("Player @1 does not exist.", target_raw)
	end
	if player_name:lower() == target:lower() then
		return false, S("You cannot place a bounty on yourself.")
	end
	local cents, perr = smp_core.parse_amount(amount_raw)
	if not cents then
		return false, S("Invalid amount: @1", perr or "?")
	end
	local b, err = smp_bounty.escrow_deposit(player_name, target, cents)
	if not b then
		if err == "min" then
			return false, S("The minimum bounty is @1.",
				smp_core.fmt_money(smp_bounty.cfg.min_amount, "body"))
		elseif err == "funds" then
			return false, S("Insufficient funds.")
		elseif err == "self" then
			return false, S("You cannot place a bounty on yourself.")
		end
		return false, S("The bounty could not be placed.")
	end
	return true, S("You added @1 to @2's bounty. New total: @3.",
		smp_core.fmt_money(cents, "body"), target,
		smp_core.fmt_money(b.total, "body"))
end

local function bounty_func(player_name, param)
	param = param and param:match("^%s*(.-)%s*$") or ""
	if param == "" then
		core.chat_send_player(player_name, table.concat(bounty_list_lines(), "\n"))
		return true
	end
	local sub, rest = param:match("^(%S+)%s+(.+)$")
	if sub and sub:lower() == "add" then
		return bounty_add(player_name, rest)
	end
	if param:lower() == "add" then
		return false, S("Usage: /bounty add <player> <amount>")
	end
	local b = smp_bounty.get(param)
	if not b or (b.total or 0) <= 0 then
		return true, S("@1 has no bounty.", param)
	end
	return true, S("@1's bounty: @2", b.target,
		smp_core.fmt_money(b.total, "body"))
end

core.register_chatcommand("bounty", {
	params = S("[player] | add <player> <amount>"),
	description = S("Bounty list, or place a bounty."),
	func = bounty_func,
})

core.register_chatcommand("bounties", {
	params = S("[player]"),
	description = S("Alias of /bounty."),
	func = function(player_name, param)
		return bounty_func(player_name, param)
	end,
})

----------------------------------------------------------------------
-- /bountyadmin clear <player> (§4.4.5): pro-rata refund from escrow
----------------------------------------------------------------------

core.register_chatcommand("bountyadmin", {
	params = S("clear <player>"),
	description = S("Remove a bounty, with refund (admin)."),
	privs = { smp_admin = true },
	func = function(player_name, param)
		local sub, rest = (param or ""):match("^%s*(%S+)%s*(.-)%s*$")
		if sub ~= "clear" or rest == "" then
			return false, S("Usage: /bountyadmin clear <player>")
		end
		local b = smp_bounty.get(rest)
		if not b or (b.total or 0) <= 0 then
			return false, S("@1 has no bounty.", rest)
		end
		local refunded = smp_bounty.escrow_refund(b)
		return true, S("Cleared @1's bounty. Refunded @2.",
			b.target, smp_core.fmt_money(refunded, "body"))
	end,
})

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------

smp_bounty.load()

core.log("action", "smp_bounty loaded: min "
	.. smp_core.fmt_money(smp_bounty.cfg.min_amount, "inline")
	.. ", pair cooldown " .. tostring(smp_bounty.cfg.pair_cooldown) .. "s")
