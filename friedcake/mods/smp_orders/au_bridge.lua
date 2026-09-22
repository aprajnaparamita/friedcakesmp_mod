-- FriedcakeSMP — smp_orders / au_bridge.lua
-- Bridge to the auction house (f03 / smp_ah).
--
-- f04's creation algorithm (f04 §6.1) sweeps the auction house for
-- listings at or below the new order's unit price, cheapest first. The
-- engine-side contract lives in f03 and was pinned there (smp_ah/init.lua):
--
--   smp_ah.listings_at_or_below(m1_key, unit_price, now)
--       -> array of active listing records for that M1 key whose unit
--          price is <= unit_price, cheapest first. Each record carries
--          { id, seller, stack (serialized), count, price, unit_price,
--            name, state, version, ... }.
--
--   smp_ah.consume_listing(id, buyer, price, reason)
--       -> closes the listing (state "routed"), records an ah transaction
--          and an "ah_sale" ledger row. The MONEY is f04's business:
--          smp_orders pays the seller from escrow ("order_payout").
--          NOTE (f04 §10): this also writes an "ah_sale" ledger row, so an
--          absorbed listing currently yields two ledger rows for one credit
--          — flagged to the integrator.
--
-- The bridge takes the shape f04 §6.1 specifies (listings_at_or_below
-- without the `now` argument; consume_listing without the reason) and
-- fills the f03-specific arguments in. Until smp_ah ships, every call
-- degrades to "no listings" so orders work standalone.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_orders.au = {}

-- Listings for `key` at or below `unit_price`, cheapest first.
function smp_orders.au.listings_at_or_below(key, unit_price)
	if smp_ah and type(smp_ah.listings_at_or_below) == "function" then
		local ok, res = pcall(smp_ah.listings_at_or_below, key, unit_price, os.time())
		if ok and type(res) == "table" then return res end
		if not ok then
			core.log("error", "[smp_orders] smp_ah.listings_at_or_below failed: "
				.. tostring(res))
		end
	end
	return {} -- TODO(f03)
end

-- Close listing `listing_id` as consumed by `buyer` at `price` cents.
-- The seller is paid by smp_orders (order escrow); f03 records the
-- transaction and closes the listing. Returns true on acknowledgement.
function smp_orders.au.consume_listing(listing_id, buyer, price)
	if smp_ah and type(smp_ah.consume_listing) == "function" then
		local ok, res = pcall(smp_ah.consume_listing, listing_id, buyer,
			price, "routed")
		if ok then return res and true or false end
		core.log("error", "[smp_orders] smp_ah.consume_listing failed: "
			.. tostring(res))
	end
	return false -- TODO(f03)
end
