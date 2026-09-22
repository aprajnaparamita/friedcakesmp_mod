-- FriedcakeSMP — smp_amethyst acceptance tests
-- Loaded in-game via `/smp test smp_amethyst`.
--
-- Covers the engine-testable parts of spec/features/f06-shards.md §9:
--   T3: expired amethyst items are removed (on use / sweep)
--   T7: the orders blacklist contains every amethyst itemstring
-- plus registration and timer checks for all six items.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local S = core.get_translator and core.get_translator("smp_amethyst")
	or function(s, ...) return s end

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "ok")
	end
end

local ITEMS = {
	"smp_amethyst:pickaxe",
	"smp_amethyst:axe",
	"smp_amethyst:shovel",
	"smp_amethyst:haste_potion",
	"smp_amethyst:bucket",
	"smp_amethyst:sell_axe",
}

-- All six items are registered.
for _, name in ipairs(ITEMS) do
	ok(core.registered_items[name] ~= nil, name .. " registered")
end

-- T7 (blacklist half): every amethyst itemstring is in the orders
-- blacklist that f04 imports.
ok(type(smp_amethyst.blacklist) == "table", "blacklist is a list")
local in_blacklist = {}
for _, name in ipairs(smp_amethyst.blacklist or {}) do
	in_blacklist[name] = true
end
for _, name in ipairs(ITEMS) do
	ok(in_blacklist[name] == true, name .. " in orders blacklist")
end

-- T3: the timer. A fresh item is not expired; one past its deadline is.
local now = os.time()
local fresh = ItemStack("smp_amethyst:pickaxe")
smp_amethyst.set_expiry(fresh, now)
ok(smp_amethyst.is_expired(fresh, now) == false, "fresh item not expired")
ok(smp_amethyst.is_expired(fresh, now + smp_amethyst.cfg.lifetime)
	== true, "item expired after lifetime")

local dead = ItemStack("smp_amethyst:axe")
smp_amethyst.set_expiry(dead, now - smp_amethyst.cfg.lifetime - 10)
ok(smp_amethyst.is_expired(dead, now) == true, "old item expired")

-- The description carries the remaining time.
local desc = smp_amethyst.refresh_description(fresh, now)
ok(desc ~= nil and desc:find("Expires") ~= nil,
	"description shows remaining time: " .. tostring(desc))

-- T3: sweep removes the expired stack and keeps the live one.
local removed_notified = 0
local function stub_inv()
	local slots = {
		[0] = ItemStack("smp_amethyst:pickaxe"),
		[1] = ItemStack("smp_amethyst:axe"),
	}
	smp_amethyst.expiry.set_expiry(slots[0], now + 3600)
	smp_amethyst.expiry.set_expiry(slots[1], now - 10)
	return {
		get_size = function(_, _) return 2 end,
		get_stack = function(_, _, i) return slots[i] end,
		set_stack = function(_, _, i, v)
			slots[i] = ItemStack(v)
		end,
	}
end
local inv = stub_inv()
smp_amethyst.expiry.sweep_list(inv, "main", function(_)
	removed_notified = removed_notified + 1
end, now)
ok(removed_notified == 1, "sweep removed exactly one expired stack")
ok(inv:get_stack("main", 0):is_empty() == false, "live stack kept")
ok(inv:get_stack("main", 1):is_empty() == true, "expired stack removed")

-- The re-entrancy guard table exists and is empty at rest.
ok(type(smp_amethyst._digging) == "table", "dig guard table exists")
ok(smp_amethyst.in_dig("__t_amethyst_nobody") == false,
	"no dig in progress at rest")

-- Felling limit is a sane positive integer.
ok(type(smp_amethyst.cfg.felling_limit) == "number"
		and smp_amethyst.cfg.felling_limit >= 1,
	"felling_limit configured")

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_amethyst tests passed."
else
	results.lines[#results.lines + 1] =
		string.format("%d failures.", results.failed)
end
return results
