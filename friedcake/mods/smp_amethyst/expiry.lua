-- FriedcakeSMP — smp_amethyst/expiry.lua
--
-- The self-destruct timer for shard items (f06 §4.3).
--
-- Every amethyst item bought with shards carries a self-destruct timer
-- starting at one day [S9]. The expiry is an absolute Unix time in item
-- meta key `smp:expires_at`, set at purchase. An expired item is removed
-- on use and on join (T3); the description shows the remaining time and
-- is refreshed on use and on join.
--
-- This module is pure item-meta logic: it knows nothing about nodes,
-- effects or the store, so it can be unit-tested without an engine.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local M = {}

M.META_KEY = "smp:expires_at"   -- absolute Unix time, seconds

-- Names of items this expiry logic applies to. An item without an
-- expiry set never expires (admin-given items are not timed).
M.PREFIX = "smp_amethyst:"

function M.is_amethyst(itemstring)
	return type(itemstring) == "string"
		and itemstring:sub(1, #M.PREFIX) == M.PREFIX
end

-- Set the absolute expiry (Unix seconds) on a stack.
function M.set_expiry(stack, expires_at)
	stack:get_meta():set_string(M.META_KEY, tostring(math.floor(expires_at)))
	return stack
end

-- Absolute expiry (Unix seconds) or nil if the item has none.
function M.expires_at(stack)
	local raw = stack:get_meta():get_string(M.META_KEY)
	if raw == "" then return nil end
	local n = tonumber(raw)
	if not n or n ~= n or n <= 0 then return nil end
	return math.floor(n)
end

-- An item is expired when it carries an expiry at or before `now`.
function M.is_expired(stack, now)
	local e = M.expires_at(stack)
	if e == nil then return false end
	now = now or os.time()
	return e <= now
end

-- Seconds remaining, or nil if the item has no expiry (never expires).
function M.remaining(stack, now)
	local e = M.expires_at(stack)
	if e == nil then return nil end
	now = now or os.time()
	local r = e - now
	if r < 0 then r = 0 end
	return r
end

-- Human remaining-time line, e.g. "1d 3h", "5h 12m", "90s".
-- PROPOSED display format; no frame evidence (f06 §10 V-21).
function M.remaining_str(stack, now)
	local r = M.remaining(stack, now)
	if r == nil then return nil end
	local d = math.floor(r / 86400)
	local h = math.floor((r % 86400) / 3600)
	local m = math.floor((r % 3600) / 60)
	local s = r % 60
	local parts = {}
	if d > 0 then parts[#parts + 1] = d .. "d" end
	if d > 0 or h > 0 then parts[#parts + 1] = h .. "h" end
	if d == 0 and (h > 0 or m > 0) then parts[#parts + 1] = m .. "m" end
	if d == 0 and h == 0 and m == 0 then parts[#parts + 1] = s .. "s" end
	return table.concat(parts, " ")
end

-- Refresh the item's description with the remaining time (f06 §4.3:
-- "the description refreshes with remaining time on use and on join").
-- Returns the description that was set (or nil for items without an
-- expiry).
function M.refresh_description(stack, display_name, S, now)
	local rs = M.remaining_str(stack, now)
	if rs == nil then return nil end
	local desc
	if M.is_expired(stack, now) then
		desc = S("Expired")
	else
		desc = S("Expires in @1", rs)
	end
	stack:get_meta():set_string("description", desc)
	return desc
end

-- Sweep one inventory list, removing expired amethyst items.
-- `notify` is called once per removed stack as
-- notify(stack, remaining_seconds) so the caller can message the player.
-- Returns the number of stacks removed.
function M.sweep_list(inv, listname, notify)
	local size = inv:get_size(listname)
	if not size then return 0 end
	local removed = 0
	for i = 0, size - 1 do
		local stack = inv:get_stack(listname, i)
		if not stack:is_empty() and M.is_amethyst(stack:get_name())
				and M.is_expired(stack) then
			inv:set_stack(listname, i, "")
			if notify then notify(stack, i) end
			removed = removed + 1
		end
	end
	return removed
end

return M
