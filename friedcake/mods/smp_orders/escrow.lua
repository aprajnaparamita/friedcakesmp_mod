-- FriedcakeSMP — smp_orders / escrow.lua
-- Escrow deposit, payout and refund. All money moves go through
-- smp_store.api.{take_money,add_money}, which append the ledger entries
-- with the reason codes pinned by shared/02-architecture.md §2.6 R3:
--   order_escrow   buyer commits unit_price × qty at creation
--   order_payout   supplier is paid from escrow on delivery
--   order_refund   unspent escrow returns on cancel / expire / admin
--
-- R2: payouts come ONLY from escrow — payout() and refund() clamp to the
-- order's remaining escrow so the record can never go negative (T10).
--
-- The escrow balance itself lives on the order record:
--   escrow = unit_price × (qty − delivered)     (f04 §5, integer cents)
-- Callers mutate the record and mark it dirty; this module never yields.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

smp_orders.escrow = {}

-- Deposit at creation. Returns the cents actually taken, or nil when the
-- buyer cannot afford it (take_money refuses overdrafts).
-- Ledger: one "order_escrow" entry, actor = buyer.
function smp_orders.escrow.deposit(buyer_name, total, order_id)
	total = math.floor(total)
	if total <= 0 then return 0 end
	return smp_store.api.take_money(buyer_name, total, "order_escrow",
		"order:" .. tostring(order_id))
end

-- Pay a supplier from an order's escrow. Clamps to the available escrow
-- (R2) and to the player balance cap (add_money returns the applied
-- delta). Returns the cents actually paid out.
-- Ledger: one "order_payout" entry, actor = supplier, counterparty-ref =
-- "order:<id>".
function smp_orders.escrow.payout(order, supplier_name, cents)
	cents = math.floor(cents)
	if cents <= 0 then return 0 end
	if cents > order.escrow then
		core.log("warning", string.format(
			"[smp_orders] payout clamped on order %d: wanted %d, escrow %d",
			order.id, cents, order.escrow))
		cents = order.escrow
	end
	if cents <= 0 then return 0 end
	order.escrow = order.escrow - cents
	local applied = smp_store.api.add_money(supplier_name, cents, "order_payout",
		"order:" .. tostring(order.id)) or 0
	if applied < cents then
		-- Supplier balance cap hit (f01 §T10): the un-applied remainder
		-- stays in escrow rather than vanishing (X3 conservation).
		order.escrow = order.escrow + (cents - applied)
		core.log("warning", string.format(
			"[smp_orders] payout to %s capped at %d of %d (order %d)",
			supplier_name, applied, cents, order.id))
	end
	return applied
end

-- Refund unspent escrow to the buyer (cancel / expire / admin remove).
-- Clamps to the available escrow. Returns the cents actually refunded.
-- Ledger: one "order_refund" entry, actor = buyer.
function smp_orders.escrow.refund(order, cents)
	cents = math.floor(cents)
	if cents <= 0 then return 0 end
	if cents > order.escrow then cents = order.escrow end
	if cents <= 0 then return 0 end
	order.escrow = order.escrow - cents
	local applied = smp_store.api.add_money(order.buyer, cents, "order_refund",
		"order:" .. tostring(order.id)) or 0
	if applied < cents then
		order.escrow = order.escrow + (cents - applied)
		core.log("warning", string.format(
			"[smp_orders] refund to %s capped at %d of %d (order %d)",
			order.buyer, applied, cents, order.id))
	end
	return applied
end
