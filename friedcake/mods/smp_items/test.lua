-- FriedcakeSMP — smp_items acceptance tests
-- Loaded by `/smp test smp_items` in-game and by
-- `friedcake/dev-tests/test_items.lua` headless.
--
-- Covers fixes/f01-economy-core.md row E-20 (the reversible shulker
-- contents codec) plus the M0/M1 invariants that must NOT move:
--
--   E-20  M2 <contents> is a reversible token over both Mineclonia
--         storage forms, so `stack_from_key` rebuilds M2 stacks;
--         the token never contains a pipe; M0/M1 stay byte-identical.
--
-- The suite only needs `core`, `ItemStack` and the item registry, so it
-- runs in a live world and under the headless harness alike.
--
-- Copyright (c) 2026 FriedcakeSMP contributors.
-- SPDX-License-Identifier: LGPL-2.1-or-later

local results = { passed = 0, failed = 0, lines = {} }

local function ok(cond, msg)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.lines[#results.lines + 1] = "FAIL " .. (msg or "ok")
	end
end

local function eq(a, b, msg)
	ok(a == b, string.format("%s: expected %s got %s",
		msg or "eq", tostring(b), tostring(a)))
end

local ITEM = "mcl_core:chest"

local function plain_box()
	return ItemStack(ITEM)
end

-- Mineclonia's two documented shulker storage forms
-- (spec/shared/03-mineclonia-api.md:21): `compressed` holds base64 of
-- zstd, the EMPTY item-meta key holds a serialized list. Both payloads
-- below deliberately contain bytes outside [A-Za-z0-9.-] — including a
-- pipe — so the no-pipe constraint of the M2 key is exercised, not
-- assumed (the six-field split is dev-tests/test_ah_keys.lua:167).
local COMPRESSED_PAYLOAD = "H4sIAAAAAAAAA/+/vuL2zT0="
local EMPTY_KEY_PAYLOAD  = 'return {"a|b", "c=d"}'

local function box_with(form)
	local s = plain_box()
	local meta = s:get_meta()
	if form == "compressed" then meta:set_string("compressed", COMPRESSED_PAYLOAD)
	elseif form == "empty" then meta:set_string("", EMPTY_KEY_PAYLOAD) end
	return s
end

local function payload_of(form)
	return form == "compressed" and COMPRESSED_PAYLOAD or EMPTY_KEY_PAYLOAD
end

local function meta_key_of(form)
	return form == "compressed" and "compressed" or ""
end

----------------------------------------------------------------------
-- M0 / M1 invariants (these are SHARED with f02/f03/f04/f05 — the
-- codec work must not have moved a single byte of them)
----------------------------------------------------------------------

eq(smp_items.key(plain_box(), "M0"), "m0|" .. ITEM, "M0 canonical form")
eq(smp_items.key(plain_box(), "M1"), "m1|" .. ITEM .. "||0", "M1 canonical form")
ok(smp_items.key(box_with("compressed"), "M1") == nil,
	"contents still disqualify M1")
ok(smp_items.key(box_with("empty"), "M1") == nil,
	"the empty-key storage form disqualifies M1 too")
ok(smp_items.key(box_with("compressed"), "M0") == nil,
	"contents still disqualify M0")
eq(smp_items.contents_of(plain_box()), "", "an empty box has no token")

----------------------------------------------------------------------
-- E-20: the codec itself
----------------------------------------------------------------------

for _, form in ipairs({ "compressed", "empty" }) do
	local src = box_with(form)
	local token = smp_items.contents_of(src)
	ok(token ~= "", form .. ": a box with contents has a token")
	ok(token:find("|", 1, true) == nil,
		form .. ": the token contains no pipe character")
	local key, value = smp_items.contents_decode(token)
	eq(key, meta_key_of(form), form .. ": the token names its own meta key")
	eq(value, payload_of(form), form .. ": the token carries the exact payload")

	-- The M2 key still parses into six pipe-separated fields.
	local m2 = smp_items.key(src, "M2")
	local n, e, w, named, c, mh =
		m2:match("^m2|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
	ok(n ~= nil, form .. ": the M2 key still splits into six fields")
	eq(n, ITEM, form .. ": field 1 is the name")
	eq(c, token, form .. ": field 5 is the contents token")
	eq(named, "0", form .. ": field 4 is the named flag")

	-- Round trip: rebuild and re-key.
	local rebuilt = smp_items.stack_from_key(m2)
	ok(rebuilt ~= nil, form .. ": stack_from_key rebuilds an M2 stack")
	if rebuilt then
		eq(rebuilt:get_name(), ITEM, form .. ": rebuilt stack keeps the item")
		eq(rebuilt:get_meta():get_string(meta_key_of(form)), payload_of(form),
			form .. ": rebuilt stack carries the identical raw payload")
		eq(smp_items.key(rebuilt, "M2"), m2,
			form .. ": the rebuilt stack keys back to the SAME M2 key")
	end
end

-- Wear and enchantments are part of the M2 key and travel with it.
local worn = box_with("compressed")
worn:set_wear(1234)
local worn_back = smp_items.stack_from_key(smp_items.key(worn, "M2"))
ok(worn_back ~= nil, "a worn box rebuilds")
eq(worn_back and worn_back:get_wear(), 1234, "wear survives the round-trip")

----------------------------------------------------------------------
-- The refusals: never rebuild something the key cannot carry
----------------------------------------------------------------------

ok(smp_items.contents_decode("deadbeef") == nil,
	"a legacy one-way hash token is refused")
ok(smp_items.stack_from_key("m2|" .. ITEM .. "||0|0|deadbeef|0") == nil,
	"a legacy M2 key cannot be rebuilt (no payload to restore)")
ok(smp_items.stack_from_key("m2|" .. ITEM .. "||0|1|" ..
	smp_items.contents_of(box_with("compressed")) .. "|0") == nil,
	"named == 1 cannot be rebuilt: the name text is outside §2.5's key")
ok(smp_items.stack_from_key("m1|" .. ITEM .. "||0") ~= nil,
	"a plain M1 key still rebuilds")
ok(smp_items.stack_from_key("m0|" .. ITEM) ~= nil,
	"a plain M0 key still rebuilds")
ok(smp_items.stack_from_key("not-a-key") == nil, "a malformed key is refused")

-- Comparison stays opaque and correct.
local full_key = smp_items.key(box_with("compressed"), "M2")
ok(smp_items.matches(box_with("compressed"), full_key, "M2"),
	"matches() accepts an identical stack")
ok(not smp_items.matches(plain_box(), full_key, "M2"),
	"matches() rejects a plain stack")

if results.failed == 0 then
	results.lines[#results.lines + 1] = "All smp_items tests passed."
else
	results.lines[#results.lines + 1] =
		string.format("%d failures.", results.failed)
end
return results
