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

io.stderr:write("EXPIRY.LUA LOADED\n")

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

-- Format a duration (whole seconds) as "1d 3h", "5h 12m" or "90s".
-- PROPOSED display format; no frame evidence (f06 §10 V-21).
function M.duration_str(secs)
	secs = math.floor(secs or 0)
	if secs < 0 then secs = 0 end
	local d = math.floor(secs / 86400)
	local h = math.floor((secs % 86400) / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	local parts = {}
	if d > 0 then parts[#parts + 1] = d .. "d" end
	if h > 0 then parts[#parts + 1] = h .. "h" end
	if d == 0 and m > 0 then parts[#parts + 1] = m .. "m" end
	if d == 0 and h == 0 and m == 0 then parts[#parts + 1] = s .. "s" end
	return table.concat(parts, " ")
end

-- Human remaining-time line, or nil if the item has no expiry.
function M.remaining_str(stack, now)
	local r = M.remaining(stack, now)
	if r == nil then return nil end
	return M.duration_str(r)
end

-- Refresh the item's description with the remaining time (f06 §4.3:
-- "the description refreshes with remaining time on use and on join").
-- Returns the description that was set (or nil for items without an
-- expiry).
-- Call signature: (stack, now?) or (stack, display_name?, S?, now?)
-- If S not provided, tries to get translator from core or smp_amethyst.
function M.refresh_description(stack, display_name, S, now)
	-- Handle flexible arguments: (stack, now) or (stack, display_name, S, now)
	if type(display_name) == "number" then
		-- Called as (stack, now)
		now = display_name
		display_name = nil
		S = nil
	elseif type(display_name) == "function" then
		-- Called as (stack, S, now) - unlikely but handle it
		S = display_name
		display_name = nil
	end

	-- Resolve translator
	if S == nil then
		print("DEBUG expiry: resolving S, _G.core = " .. tostring(_G.core) .. ", _G.core.get_translator = " .. tostring(_G.core and _G.core.get_translator))
		-- Try global core (test environment or actual engine)
		if _G.core and type(_G.core.get_translator) == "function" then
			S = _G.core.get_translator("smp_amethyst")
			print("DEBUG expiry: got S from core.get_translator")
		-- Try smp_amethyst module (actual game)
		elseif _G.smp_amethyst and type(_G.smp_amethyst) == "table" then
			-- smp_amethyst doesn't expose S directly, create a fallback
			S = function(s, ...) 
				local a = {...}
				return (s:gsub("@(%d+)", function(n)
					return tostring(a[tonumber(n)] or "")
				end))
			end
		else
			-- Final fallback: simple @n substitution
			S = function(s, ...)
				local a = {...}
				return (s:gsub("@(%d+)", function(n)
					return tostring(a[tonumber(n)] or "")
				end))
			end
		end
	end

	-- Resolve display_name
	if display_name == nil then
		-- Try to get from registered items (needs core)
		if _G.core and _G.core.registered_items then
			local def = _G.core.registered_items[stack:get_name()]
			display_name = def and def.description or stack:get_name()
		else
			display_name = stack:get_name()
		end
	end

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
-- `notify` is called once per removed stack as notify(stack, index) so
-- the caller can message the player. `now` is the Unix time used for the
-- expiry comparison (defaults to os.time()); inject a fake clock in
-- tests. Returns the number of stacks removed.
function M.sweep_list(inv, listname, notify, now)
	now = now or os.time()
	local size = inv:get_size(listname)
	if not size then return 0 end
	-- Collect first, then remove: no mutation while iterating.
	local victims = {}
	for i = 0, size - 1 do
		local stack = inv:get_stack(listname, i)
		if not stack:is_empty() and M.is_amethyst(stack:get_name())
				and M.is_expired(stack, now) then
			victims[#victims + 1] = { i = i, stack = stack }
		end
	end
	for _, v in ipairs(victims) do
		inv:set_stack(listname, v.i, "")
		if notify then notify(v.stack, v.i) end
	end
	return #victims
end

return M
