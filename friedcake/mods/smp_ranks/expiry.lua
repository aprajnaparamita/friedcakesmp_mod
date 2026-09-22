-- FriedcakeSMP — smp_ranks expiry (f13 §4.2.2, §8).
--
-- Expiry itself is lazy: tier() computes from expires_at, so no record
-- is mutated when a tier lapses (T2). This module exists only to emit
-- the expiry notification on join and on the hourly sweep.
--
-- The sweep runs over dirty candidates only — the in-memory watch set
-- populated by grants and joins — never a full table scan (§8).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local watch = {}      -- name -> expires_at (candidates for the sweep)
local notified = {}   -- name -> true once notified this server run

function smp_ranks.watch(name, expires_at)
	watch[name] = expires_at
end

function smp_ranks.unwatch(name)
	watch[name] = nil
end

-- Exposed for the acceptance tests; not part of the public surface.
smp_ranks._watch = watch
smp_ranks._notified = notified

local function notify(name)
	if notified[name] then return end
	notified[name] = true
	core.log("action", "[smp_ranks] rank expired: " .. name)
	if core.get_player_by_name(name) then
		core.chat_send_player(name, smp_ranks.S("Your rank has expired"))
	end
end

-- Join-time check (§4.2.2). Live ranks are re-added to the watch set;
-- already-expired ranks notify once and leave the record untouched.
function smp_ranks.check_join(name)
	local rec = smp_store.api.get_player(name)
	local r = rec and rec.rank
	if type(r) ~= "table" or type(r.tier) ~= "string" or r.tier == "" then
		return
	end
	if type(r.expires_at) ~= "number" then return end
	if r.expires_at > os.time() then
		watch[name] = r.expires_at
		notified[name] = nil
	else
		watch[name] = nil
		notify(name)
	end
end

-- One sweep pass. Emission only — no record mutation (§8).
function smp_ranks.sweep(now)
	now = now or os.time()
	for name, expires_at in pairs(watch) do
		if expires_at <= now then
			watch[name] = nil
			notify(name)
		end
	end
end

core.register_on_joinplayer(function(player)
	smp_ranks.check_join(player:get_player_name())
end)

-- Hourly loop over the dirty candidates (ranks.expiry_check_interval).
local function schedule()
	core.after(smp_ranks.cfg.expiry_check_interval, function()
		local ok, err = pcall(smp_ranks.sweep)
		if not ok then
			core.log("error", "[smp_ranks] expiry sweep failed: " .. tostring(err))
		end
		schedule()
	end)
end

if core.after then schedule() end
