-- FriedcakeSMP — smp_social friends and follows (f11 §4.4)
--
-- Following is one-way; mutual follows are friends (derived, never
-- stored); friends and followed players get join and leave notices; at
-- most social.max_follows (200) follows.
--
-- A block on EITHER edge refuses the follow (§4.3 "Refuse their
-- follows": block = yes, ignore = no — F11-3, §10.2).
--
-- The friend/follow graph is load-bearing: four of the seven observed
-- chat settings (f12 §3.3) resolve against it.
--
-- Subcommands [S24]: list, friends, followers, following, search,
-- addsearch. `add` and `remove` (with `follow`/`unfollow`) are PROPOSED
-- aliases for `addsearch`/`remove` — recorded in f11 §10.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator(core.get_current_modname())

local function player_exists(name)
	if core.player_exists then return core.player_exists(name) end
	return true
end

local function canonical(name)
	local p = core.get_player_by_name(name)
	return p and p:get_player_name() or name
end

local function sorted_copy(list)
	local out = {}
	for _, v in ipairs(list) do out[#out + 1] = v end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end

----------------------------------------------------------------------
-- follow / unfollow (also used by tests)
----------------------------------------------------------------------

-- §4.3 effect table: a BLOCK refuses follows (both directions), an
-- IGNORE does not. PROPOSED row, tied to V-48; decision record in f11
-- §10.2 (F11-3). Exported so the in-mod suite can assert the split
-- without needing two existing player accounts.
function smp_social.follow_blocked(a, b)
	return smp_social.is_blocked(a, b) or smp_social.is_blocked(b, a)
end

function smp_social.follow(a, b)
	if a:lower() == b:lower() then
		return false, S("You cannot follow yourself")
	end
	if not player_exists(b) then
		return false, S("Player @1 does not exist", b)
	end
	-- Validate before mutate, no yields (shared §2.3). Generic refusal
	-- in the §6 style: it states a reason without naming the block, so
	-- it reveals nothing to the refused side (X9).
	if smp_social.follow_blocked(a, b) then
		return false, S("This user is not accepting follows")
	end
	local already = false
	local full = false
	smp_social.mutate_social(a, function(soc)
		if smp_social.list_has(soc.following, b) then
			already = true
			return
		end
		if #soc.following >= smp_social.cfg.social.max_follows then
			full = true
			return
		end
		soc.following[#soc.following + 1] = canonical(b)
	end)
	if already then
		return false, S("You are already following @1", b)
	end
	if full then
		return false, S("You reached the follow limit")
	end
	-- Mutual follows form a friendship: tell both sides (PROPOSED).
	if smp_social.follows(b, a) then
		local pb = core.get_player_by_name(b)
		if pb then core.chat_send_player(b, S("You are now friends with @1", a)) end
		local pa = core.get_player_by_name(a)
		if pa then core.chat_send_player(a, S("You are now friends with @1", b)) end
	end
	return true, S("You are now following @1", canonical(b))
end

function smp_social.unfollow(a, b)
	local found = false
	smp_social.mutate_social(a, function(soc)
		for i = #soc.following, 1, -1 do
			if tostring(soc.following[i]):lower() == b:lower() then
				table.remove(soc.following, i)
				found = true
			end
		end
	end)
	if not found then
		return false, S("You are not following @1", b)
	end
	return true, S("You no longer follow @1", b)
end

----------------------------------------------------------------------
-- Derived views
----------------------------------------------------------------------

local function friends_of(name)
	local out = {}
	for _, other in ipairs(sorted_copy(smp_social.get_social(name).following)) do
		if smp_social.is_friend(name, other) then
			out[#out + 1] = other
		end
	end
	return out
end

-- Followers require a reverse scan of the record table. Command-time
-- only, never in a callback hot path (PROPOSED; see §10).
local function followers_of(name)
	local out = {}
	for _, other in ipairs(smp_store.api.all_player_names()) do
		if other:lower() ~= name:lower()
				and smp_social.follows(other, name) then
			out[#out + 1] = other
		end
	end
	table.sort(out, function(x, y) return x:lower() < y:lower() end)
	return out
end

local function say_list(name, title, empty, list)
	if #list == 0 then
		return smp_social.say(name, empty)
	end
	return smp_social.say(name, S("@1 (@2): @3", title, #list,
		table.concat(list, ", ")))
end

local function search_players(name, query)
	local q = query:lower()
	local hits = {}
	local total = 0
	for _, n in ipairs(smp_store.api.all_player_names()) do
		if n:lower():find(q, 1, true) then
			total = total + 1
			if #hits < 10 then hits[#hits + 1] = n end
		end
	end
	table.sort(hits, function(x, y) return x:lower() < y:lower() end)
	if total == 0 then
		return smp_social.say(name, S("No players match @1", query))
	end
	smp_social.say(name, S("Players matching @1 (@2): @3", query, total,
		table.concat(hits, ", ")))
	return smp_social.say(name,
		S("Use /friend addsearch <name> to follow a player"))
end

----------------------------------------------------------------------
-- /friend
----------------------------------------------------------------------

local function friend_cmd(name, param)
	local sub, rest = (param or ""):match("^%s*(%S+)%s*(.-)$")
	sub = sub and sub:lower() or ""
	rest = (rest or ""):match("^%s*(.-)%s*$") or ""

	if sub == "" or sub == "list" then
		local soc = smp_social.get_social(name)
		local friends = friends_of(name)
		smp_social.say(name, S("Friends: @1", #friends))
		smp_social.say(name, S("Following: @1", #soc.following))
		smp_social.say(name, S("Followers: @1",
			#followers_of(name)))
		return smp_social.say(name,
			S("Use /friend friends, /friend following or /friend followers for details"))
	elseif sub == "friends" then
		return say_list(name, S("Friends"), S("You have no friends yet"),
			friends_of(name))
	elseif sub == "following" then
		return say_list(name, S("Following"), S("You are not following anyone"),
			sorted_copy(smp_social.get_social(name).following))
	elseif sub == "followers" then
		return say_list(name, S("Followers"), S("No one is following you"),
			followers_of(name))
	elseif sub == "search" then
		if rest == "" then return false end
		return search_players(name, rest)
	elseif sub == "addsearch" or sub == "add" or sub == "follow" then
		if rest == "" then return false end
		local ok, err = smp_social.follow(name, rest)
		if not ok then return smp_social.say(name, err) end
		return smp_social.say(name, err)
	elseif sub == "remove" or sub == "unfollow" then
		if rest == "" then return false end
		local ok, err = smp_social.unfollow(name, rest)
		return smp_social.say(name, err)
	end
	return false -- unknown subcommand: engine prints /friend's usage
end

smp_social.register_cmd("friend", {
	params = S("[list, friends, followers, following, search, addsearch]"),
	description = S("Follow and friends system"),
	func = friend_cmd,
}, { "friends" })

----------------------------------------------------------------------
-- Join and leave notices (§4.4: friends get join and leave notices)
--
-- Viewer-side filter, consistent with Public Chat (T2): the VIEWER's
-- `chat.join_leave` decides what they see — ON shows every notice,
-- FRIENDS_FOLLOWED shows only players the viewer follows (friends are
-- mutual follows, so they are covered), OFF shows none.
----------------------------------------------------------------------

local function notify_graph(name, joined)
	if not smp_social.cfg.social.friend_notify then return end
	local msg = joined
		and S("@1 joined the game", name)
		or  S("@1 left the game", name)
	for _, p in ipairs(core.get_connected_players()) do
		local viewer = p:get_player_name()
		if viewer ~= name then
			local pref = smp_social.get_setting(viewer, "chat.join_leave")
			local visible = pref == "ON"
				or (pref == "FRIENDS_FOLLOWED"
					and smp_social.follows(viewer, name))
			if visible then
				core.chat_send_player(viewer, msg)
			end
		end
	end
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	-- Make sure the record and the graph cache exist and are current.
	smp_store.api.ensure_player(name)
	smp_social._invalidate(name)
	notify_graph(name, true)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	notify_graph(name, false)
	-- Runtime state does not survive a disconnect (§5: last_pm is not
	-- persisted; rate-limit state is per-session).
	smp_social._invalidate(name)
	smp_social._chat_state[name] = nil
	smp_social._last_pm[name] = nil
	for other, target in pairs(smp_social._last_pm) do
		if target == name then smp_social._last_pm[other] = nil end
	end
end)

return true
