-- FriedcakeSMP — smp_quickbuy bridges
--
-- The contracts that f03 (auction house), f10 (combat) and f14 (stats)
-- implement against. Until those mods land, each bridge delegates to the
-- real mod when it exists and otherwise returns a safe default, so
-- smp_quickbuy loads and degrades gracefully. The integrator does not need
-- to rewire anything: the delegation is automatic once the mods exist.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_quickbuy.au     = {}
smp_quickbuy.combat = {}
smp_quickbuy.stats  = {}

----------------------------------------------------------------------
-- f03 auction-house bridge
--
-- smp_quickbuy.au.cheapest_for(key, ench, qty)
--   key : string itemstring (M1 key base — exact item, zero wear, §2.5)
--   ench: table { enchant_id = level, ... } — exact match required (M1)
--   qty : integer number of items wanted
--
--   returns nil when there are not enough active matching listings to fill
--   `qty`, otherwise:
--     { listings = { { id = N, version = N, count = N, price = <cents>,
--                      unit_price = <cents>, ... }, ... },
--       cost_cents = <integer, sum of `price` over listings> }
--
--   `price` on each listing record is the integer number of cents the buyer
--   pays for that listing in full; `count` is how many items it delivers.
--   PROPOSED (V-58): whole listings are bought, so the last listing may
--   overshoot `qty` by less than one stack. cost_cents is always the exact
--   total the purchase will cost, so the guard and the funds check use it
--   directly.
----------------------------------------------------------------------
function smp_quickbuy.au.cheapest_for(key, ench, qty)
	-- Delegates to smp_ah.cheapest_for (f03 §6.2; shipped). Returns nil only
	-- when the auction house is absent or cannot fill the entry.
	if smp_ah and smp_ah.cheapest_for then
		return smp_ah.cheapest_for(key, ench, qty)
	end
	return nil
end

----------------------------------------------------------------------
-- smp_quickbuy.au.buy(player, id, version)
--   Re-validates the listing (state + version counter, f03 §6.2) and, when
--   valid, debits the buyer, credits the seller, delivers the stack and
--   bumps the version.
--
--   returns nil on failure (already bought / version mismatch / insufficient
--   funds / no inventory space). The buyer is NEVER charged on failure.
--   returns { stack = ItemStack } on success.
--
--   Quick Buy calls this once per listing so that a listing bought out from
--   under the purchase (T7) fails cleanly without a partial charge, and the
--   rest of the purchase still completes.
----------------------------------------------------------------------
function smp_quickbuy.au.buy(player, id, version)
	-- Delegates to smp_ah.buy(player, id, version) (f03 §6.2; shipped).
	if smp_ah and smp_ah.buy then
		return smp_ah.buy(player, id, version)
	end
	return nil
end

----------------------------------------------------------------------
-- f10 combat bridge
----------------------------------------------------------------------
function smp_quickbuy.combat.is_tagged(player)
	-- Delegates to smp_combat.is_tagged(player) (f10; shipped).
	if smp_combat and smp_combat.is_tagged then
		return smp_combat.is_tagged(player)
	end
	return false
end

----------------------------------------------------------------------
-- f14 stats bridge
----------------------------------------------------------------------
function smp_quickbuy.stats.add(player, key, value)
	-- Delegates to smp_stats.add(player, key, value) (f14; shipped).
	if smp_stats and smp_stats.add then
		return smp_stats.add(player, key, value)
	end
	return nil
end

core.log("action", "[smp_quickbuy] bridges ready — f03/f10/f14 all delegate to the shipped mods")
