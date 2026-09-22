-- FriedcakeSMP — smp_bounty / escrow.lua
-- Escrow deposit, payout, refund — and the bounty record store.
-- spec/features/f10-combat.md §4.4, §5.2; shared §2.6 R2, R3.
--
-- Escrow, NOT credit: /bounty add debits the contributor immediately
-- (ledger `bounty_escrow`); the bounty total IS the escrow. Payout comes
-- only from escrow (ledger `bounty_payout`); no money is ever minted on
-- payout (X3 conservation).
--
-- Persistence (PROPOSED, recorded in f10 §10): smp_store exposes no
-- generic table API yet (its STORAGE.md lists bounties as "later"), so
-- bounties live in this mod's own mod-storage namespace with the same
-- JSON-document pattern smp_orders uses. Money and ledger always go
-- through smp_store.api.
--
-- Record schema (§5.2):
--   { target = "Dave", total = 500000000,
--     contributors = { Alice = 300000000, Bob = 200000000 },
--     created = 1758500000, updated = 1758503600 }
--   keyed by target:lower(); `target` keeps the canonical display name.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local db = {
	bounties = {}, -- [lower(target)] = record
	claims = {},   -- [lower(killer).."|"..lower(victim)] = os.time()
	_storage = nil,
}
smp_bounty.db = db

local function storage()
	if not db._storage then
		db._storage = core.get_mod_storage()
	end
	return db._storage
end

----------------------------------------------------------------------
-- Load / save. Writes are synchronous: a bounty mutation is money
-- movement, so it is flushed immediately rather than on a dirty timer.
----------------------------------------------------------------------

function smp_bounty.load()
	local s = storage()
	local ok1, raw_b = pcall(core.parse_json, s:get_string("bounties"))
	local ok2, raw_c = pcall(core.parse_json, s:get_string("claims"))
	db.bounties = (ok1 and type(raw_b) == "table") and raw_b or {}
	db.claims = (ok2 and type(raw_c) == "table") and raw_c or {}

	local now = os.time()
	local window = smp_bounty.cfg.pair_cooldown
	for key, b in pairs(db.bounties) do
		b.key = key
		b.target = type(b.target) == "string" and b.target or key
		b.total = math.floor(tonumber(b.total) or 0)
		b.contributors = type(b.contributors) == "table" and b.contributors or {}
		for name, v in pairs(b.contributors) do
			b.contributors[name] = math.floor(tonumber(v) or 0)
			if b.contributors[name] <= 0 then b.contributors[name] = nil end
		end
		b.created = tonumber(b.created) or now
		b.updated = tonumber(b.updated) or b.created
		if b.total <= 0 then db.bounties[key] = nil end
	end
	-- Prune claim cooldowns that have elapsed (§4.4.4).
	for key, t in pairs(db.claims) do
		if now - (tonumber(t) or 0) >= window then db.claims[key] = nil end
	end
end

function smp_bounty.save()
	local s = storage()
	s:set_string("bounties", core.write_json(db.bounties))
	s:set_string("claims", core.write_json(db.claims))
end

function smp_bounty.key_of(target)
	return tostring(target or ""):lower()
end

function smp_bounty.get(target)
	return db.bounties[smp_bounty.key_of(target)]
end

-- Removal without refund — the §6 pseudo-code's post-payout clear.
function smp_bounty.clear(target)
	local key = smp_bounty.key_of(target)
	if not db.bounties[key] then return false end
	db.bounties[key] = nil
	smp_bounty.save()
	return true
end

----------------------------------------------------------------------
-- Deposit: validate first, then mutate, no yields in between (R1/§2.3).
-- Returns record on success, or nil + "min" | "self" | "funds".
----------------------------------------------------------------------

function smp_bounty.escrow_deposit(contributor, target, cents)
	cents = math.floor(tonumber(cents) or 0)
	if contributor == nil or target == nil then return nil, "self" end
	if contributor:lower() == target:lower() then return nil, "self" end
	if cents < smp_bounty.cfg.min_amount then return nil, "min" end

	-- Validate funds before mutating anything.
	local rec = smp_store.api.get_player(contributor)
	if not rec then rec = smp_store.api.ensure_player(contributor) end
	if (rec.money or 0) < cents then return nil, "funds" end

	-- Mutate: debit into escrow, then stack the contribution.
	local key = smp_bounty.key_of(target)
	local taken = smp_store.api.take_money(contributor, cents,
		"bounty_escrow", "bounty:" .. key)
	if not taken then return nil, "funds" end -- re-validated inside take_money

	local b = db.bounties[key]
	if not b then
		b = {
			key = key,
			target = target,
			total = 0,
			contributors = {},
			created = os.time(),
			updated = os.time(),
		}
		db.bounties[key] = b
	end
	b.contributors[contributor] = (b.contributors[contributor] or 0) + taken
	b.total = b.total + taken
	b.updated = os.time()
	smp_bounty.save()
	return b
end

----------------------------------------------------------------------
-- Payout: comes ONLY from escrow (R2). Never mints: add_money credits
-- the killer exactly what the escrow held. If the killer's balance cap
-- (f01) absorbs less than the full total, the remainder stays in
-- escrow — orphaned but conserved (X3) — and the bounty remains
-- claimable for that remainder.
----------------------------------------------------------------------

function smp_bounty.escrow_payout(b, killer)
	local cents = math.floor(b.total or 0)
	if cents <= 0 then return 0 end
	local applied = smp_store.api.add_money(killer, cents, "bounty_payout",
		"bounty:" .. b.key) or 0
	if applied > cents then applied = cents end
	b.total = cents - applied
	if b.total <= 0 then
		db.bounties[b.key] = nil
		smp_bounty.save()
	else
		b.contributors = {}
		b.updated = os.time()
		smp_bounty.save()
		core.log("warning", string.format(
			"[smp_bounty] payout capped: %d of %d on %s; remainder stays in escrow",
			applied, cents, b.key))
	end
	return applied
end

----------------------------------------------------------------------
-- Refund: /bountyadmin clear (§4.4.5). Pro-rata from escrow; in the
-- normal case escrow == sum(contributors), so every contributor is
-- refunded in full (T10). Ledger: bounty_payout (R3 has no dedicated
-- refund code — noted in f10 §10).
----------------------------------------------------------------------

function smp_bounty.escrow_refund(b)
	local total = math.floor(b.total or 0)
	if total <= 0 then
		db.bounties[b.key] = nil
		smp_bounty.save()
		return 0
	end

	local names = {}
	local sum = 0
	for name, a in pairs(b.contributors) do
		names[#names + 1] = name
		sum = sum + a
	end
	table.sort(names) -- deterministic rounding order

	local give = {}
	if sum == total then
		for _, n in ipairs(names) do give[n] = b.contributors[n] end
	elseif sum > 0 then
		local remaining = total
		for _, n in ipairs(names) do
			give[n] = math.floor(b.contributors[n] * total / sum)
			remaining = remaining - give[n]
		end
		-- Hand out the flooring remainder in name order (exact when
		-- total <= sum, which escrow conservation guarantees).
		for _, n in ipairs(names) do
			while remaining > 0 and give[n] < b.contributors[n] do
				give[n] = give[n] + 1
				remaining = remaining - 1
			end
		end
	end
	-- sum == 0: orphaned escrow from a capped payout — nobody to refund.

	local refunded = 0
	for _, n in ipairs(names) do
		local want = give[n] or 0
		if want > 0 then
			local applied = smp_store.api.add_money(n, want, "bounty_payout",
				"bounty:" .. b.key) or 0
			if applied > want then applied = want end
			refunded = refunded + applied
		end
	end

	local unrefunded = total - refunded
	if unrefunded > 0 then
		-- Balance-cap edge or orphaned escrow: the cents stay conserved
		-- in escrow rather than vanishing (X3). Logged for staff.
		b.total = unrefunded
		b.contributors = {}
		b.updated = os.time()
		smp_bounty.save()
		core.log("warning", string.format(
			"[smp_bounty] refund left %d in escrow on %s",
			unrefunded, b.key))
	else
		db.bounties[b.key] = nil
		smp_bounty.save()
	end
	return refunded
end
