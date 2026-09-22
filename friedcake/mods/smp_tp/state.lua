-- FriedcakeSMP — smp_tp per-player transient state
--
-- Schema per spec/features/f08-teleport.md §5. Nothing here survives a
-- restart; it is held in memory only (player meta once f12 lands, if we
-- want it to).
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = smp_tp.S

smp_tp.state = {}

function smp_tp.get_state(name)
	local st = smp_tp.state[name]
	if not st then
		st = {
			warmup = nil,               -- mirror of smp_tp.warmup[name]
			last_teleport_from = nil,   -- pos, for /world
			cooldowns = {},             -- kind -> expiry (os.time)
			requests_out = {},          -- [target][type] = expiry
			requests_in = {},           -- [sender][type] = expiry
			rtpqueue = nil,             -- {joined_at} while queued
			accept_tpa = true,          -- /tpatoggle
			accept_tpahere = true,      -- /tpaheretoggle
			auto_accept = false,        -- /tpauto
			last_death = nil,           -- pos, for /back
			zone_entered_at = nil,      -- RTP zone timer
		}
		smp_tp.state[name] = st
	end
	return st
end

function smp_tp.clear_state(name)
	smp_tp.state[name] = nil
end

----------------------------------------------------------------------
-- Request expiry sweep. Runs from the globalstep; O(online players)
-- per second at most (shared §2.7).
----------------------------------------------------------------------

local function sweep_expiries(now)
	for name in pairs(smp_tp.state) do
		local st = smp_tp.state[name]
		for kind, exp in pairs(st.cooldowns) do
			if exp <= now then st.cooldowns[kind] = nil end
		end
		local dead_out = {}
		for target, types in pairs(st.requests_out) do
			for t, exp in pairs(types) do
				if exp <= now then
					types[t] = nil
					dead_out[#dead_out + 1] = { name = name, target = target, t = t }
				end
			end
			if not next(types) then st.requests_out[target] = nil end
		end
		local dead_in = {}
		for sender, types in pairs(st.requests_in) do
			for t, exp in pairs(types) do
				if exp <= now then
					types[t] = nil
					dead_in[#dead_in + 1] = { name = name, sender = sender, t = t }
				end
			end
			if not next(types) then st.requests_in[sender] = nil end
		end
		-- Notify the other side of expired requests.
		for _, d in ipairs(dead_out) do
			if core.player_exists(d.target) then
				core.chat_send_player(d.target, S("Teleport request from @1 expired", d.name))
			end
		end
		for _, d in ipairs(dead_in) do
			if core.player_exists(d.sender) then
				core.chat_send_player(d.sender, S("Teleport request to @1 expired", d.name))
			end
		end
		-- Drop state for offline players (requests from/to them are
		-- cancelled per f08 §4.4.6; the counterpart is told there).
		if not core.player_exists(name) and (next(st.requests_out) or next(st.requests_in)) then
			for target in pairs(st.requests_out) do
				if core.player_exists(target) then
					core.chat_send_player(target, S("Teleport request from @1 cancelled", name))
				end
			end
			for sender in pairs(st.requests_in) do
				if core.player_exists(sender) then
					core.chat_send_player(sender, S("Teleport request to @1 cancelled", name))
				end
			end
			smp_tp.clear_state(name)
		end
	end
end

local last_sweep = 0
function smp_tp.state_globalstep(dtime)
	local now = os.time()
	if now - last_sweep >= 1 then
		last_sweep = now
		sweep_expiries(now)
	end
end

return smp_tp
