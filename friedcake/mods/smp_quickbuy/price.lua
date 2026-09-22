-- FriedcakeSMP — smp_quickbuy price lookup and the 3× price guard
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local cfg = smp_quickbuy.cfg

smp_quickbuy.price = {}

-- Live lowest total cost to fill `qty` of (key, ench).
--
-- Returns (cost_cents, raw_result) where raw_result is the bridge's full
-- { listings=…, cost_cents=… } table, or nil when there are not enough
-- listings.
--
-- NEVER cache the result across a redraw: the 3× guard compares the live
-- cost against the price the player saw, and a stale figure defeats the
-- guard (f05 §8).
function smp_quickbuy.price.lookup(key, ench, qty)
	local result = smp_quickbuy.au.cheapest_for(key, ench, qty)
	if not result then return nil end
	return result.cost_cents, result
end

-- The 3× price guard (§4.3, §6).
--
-- Returns true when the purchase may proceed without extra confirmation:
-- current <= shown * cfg.price_guard. Both arguments are integer cents and
-- cfg.price_guard defaults to exactly 3.0, so T3 tests 3 — not 2 or 4.
function smp_quickbuy.price.within_guard(shown, current)
	if not shown or shown < 0 or not current or current < 0 then return false end
	return current <= shown * cfg.price_guard
end

core.log("action", "[smp_quickbuy] price lookup + 3x guard ready (price_guard="
	.. tostring(cfg.price_guard) .. ")")
