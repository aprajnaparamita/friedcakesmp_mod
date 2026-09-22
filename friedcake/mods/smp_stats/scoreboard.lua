-- FriedcakeSMP — smp_stats / scoreboard.lua
-- The observed bottom-right sidebar (f14 §3.1, §4.3, T6).
--
-- A two-line text HUD: the sidebar title, then `$ ` + the money
-- balance in the THIRD money convention (f01 §3.2): lower-case
-- suffix, no upper-case K/M/B — F0287 reads `Voire $ 754k`, F0055
-- `Voire 723k`. Local fmt_scoreboard() implements it; smp_core
-- .fmt_money's upper-case suffix must NOT be reused here (T6).
--
-- Updates: hooks smp_store.api.add_money/take_money/set_money (the
-- only money mutators — f01 routes every credit/debit through them)
-- and join. Never polls (§8). The coordinate readout in the frames is
-- Lunar Client HUD — deliberately NOT reimplemented (shared §1.2,
-- §3.3).
--
-- Visibility: `scoreboard.enabled` (OBSERVED, §7) AND — when f12 is
-- present — the per-player `scoreboard.show` toggle registered into
-- the observed Scoreboard category (§4.3.1, PROPOSED wiring, V-78;
-- §10 F14-D4).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local WHITE = 0xFFFFFF

-- The third money convention (claim rule 5; f01 §3.2): lower-case
-- suffix at the same thresholds fmt_money uses, no `$` (the HUD adds
-- it), dollars with cents below $1,000. Produces 723k, 754k, 1.2b,
-- 15k, 7, 5.50.
function smp_stats.fmt_scoreboard(cents)
	cents = tonumber(cents) or 0
	if cents ~= cents or cents == math.huge or cents == -math.huge then
		return "0"
	end
	cents = math.floor(cents + 0.5)
	if cents < 0 then cents = 0 end
	local function pretty(scaled, suffix)
		local r = string.format("%.1f%s", scaled, suffix)
		return (r:gsub("%.0([kmbt])", "%1")) -- parens: gsub returns 2
	end
	if cents >= 100000000000000 then return pretty(cents / 100000000000000, "t") end
	if cents >= 100000000000     then return pretty(cents / 100000000000,     "b") end
	if cents >= 100000000        then return pretty(cents / 100000000,        "m") end
	if cents >= 100000           then return pretty(cents / 100000,           "k") end
	if cents % 100 == 0 then return string.format("%d", cents / 100) end
	return string.format("%.2f", cents / 100)
end

-- HUD text: title line + `$ ` + readout (F0287 form).
local function hud_text(name)
	return smp_stats.scoreboard_title() .. "\n$ "
		.. smp_stats.fmt_scoreboard(smp_stats.get(name, "money"))
end
smp_stats.hud_text = hud_text

-- Per-player visibility (§4.3.1): the observed `scoreboard.enabled`
-- config plus f12's per-player toggle when registered.
function smp_stats.scoreboard_visible(name)
	if not smp_stats.cfg.scoreboard_enabled then return false end
	if smp_settings and type(smp_settings) == "table"
	   and smp_settings.registered
	   and smp_settings.registered["scoreboard.show"] then
		return smp_settings.get(name, "scoreboard.show") == "ON"
	end
	return true
end

----------------------------------------------------------------------
-- HUD lifecycle: one text HUD per player, id kept locally. Add on
-- join, hud_change on every balance mutation, hud_remove when the
-- setting turns the sidebar off.

local hud_ids = {} -- [name] = hud id

function smp_stats.refresh_scoreboard(name)
	local player = core.get_player_by_name(name)
	if not player then return false end
	local id = hud_ids[name]
	if not smp_stats.scoreboard_visible(name) then
		if id then
			player:hud_remove(id)
			hud_ids[name] = nil
		end
		return false
	end
	local text = hud_text(name)
	if id then
		player:hud_change(id, "text", text) -- one HUD tick, no poll
		return true
	end
	hud_ids[name] = player:hud_add({
		type = "text",
		position = { x = 1, y = 1 },   -- bottom-right anchor
		alignment = { x = -1, y = -1 }, -- block sits above/left of it
		offset = { x = -8, y = -40 },   -- clear of hotbar + minimap (§8)
		number = WHITE,
		text = text,
	})
	return true
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	smp_store.api.ensure_player(name)
	smp_stats.refresh_scoreboard(name)
end)

core.register_on_leaveplayer(function(player, _)
	local name = player.get_player_name and player:get_player_name()
	if name then hud_ids[name] = nil end -- the HUD went with the ref
end)

----------------------------------------------------------------------
-- Money mutators (§8): wrap the three smp_store money functions —
-- f01 routes every balance change through them — call the original
-- first, then hud_change. No polling anywhere.

do
	local api = smp_store.api
	local orig_add = api.add_money
	local orig_take = api.take_money
	local orig_set = api.set_money

	api.add_money = function(name, cents, reason, ref)
		local applied = orig_add(name, cents, reason, ref)
		if applied and applied > 0 then
			smp_stats.refresh_scoreboard(name)
		end
		return applied
	end

	api.take_money = function(name, cents, reason, ref)
		local removed = orig_take(name, cents, reason, ref)
		if removed then
			smp_stats.refresh_scoreboard(name)
		end
		return removed
	end

	api.set_money = function(name, cents, reason, ref)
		local r = orig_set(name, cents, reason, ref)
		smp_stats.refresh_scoreboard(name)
		return r
	end
end

----------------------------------------------------------------------
-- f12 wiring (§4.3.1, PROPOSED): register `Scoreboard` as the first
-- (and currently only) row of the observed Scoreboard category when
-- smp_settings is present. Registered in register_on_mods_loaded so
-- both registries exist regardless of load order. Applied on the next
-- balance update or rejoin (smp_settings exposes no change callback —
-- §10 F14-D4).

core.register_on_mods_loaded(function()
	if type(smp_settings) == "table" and smp_settings.register
	   and type(smp_settings.categories) == "table"
	   and smp_settings.categories.scoreboard then
		smp_settings.register("scoreboard.show", {
			category = "scoreboard",
			label = smp_stats.S("Scoreboard"),
			values = { "ON", "OFF" },
			default = "ON",
		})
	end
end)
