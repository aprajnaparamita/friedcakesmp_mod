# S03 — Auction house: routed listings destroyed, API hardening

**Target mod:** `friedcake/mods/smp_ah/` · **Branch:** `agent/sec-s03-ah`
**Audited at:** `85e4a5d`

## Mission

Stop listings that are routed into a buy order from **destroying the
seller's stack**, a bug any player can turn against others. Harden
`smp_ah.buy` against being called with the wrong argument types.

## Constraints (AGENTS.md)

Edit only `smp_ah`. The `smp_orders` contract changes live in **S04**.
Tests: `dev-tests/test_ah*.lua` + `smp_ah/test.lua`.

## Findings

| ID | Sev | Status | Where | One line |
|---|---|---|---|---|
| AH-1 | High | CONFIRMED | `init.lua:825-831` | `pcall` success is read as "routed": an order refusal **deletes the stack** |
| AH-2 | Medium | CONFIRMED | `init.lua:913`, `:203`, `:211` | `smp_ah.buy` crashes the server on a non-string name (see S05 QB-1) |
| AH-3 | Low | CONFIRMED | `smp_orders/routing.lua:162` (fix in S04) | Order sweep pays `floor(price/count) × count`, which is less than the listing price |
| AH-4 | Low | CONFIRMED | `init.lua:599-620`, `:885-887` | The insert inventory stays open after the price step: items put there are wiped at commit |
| AH-5 | Low | CONFIRMED | `listings.lua:710-750` | Quick Buy matching ignores `<meta_hash>`: the buyer can receive a different variant |

---

### AH-1 — Routing into an order deletes the stack (HIGH)

**Where.** `smp_ah.create_listing`, `init.lua:822-832`:

```lua
local routed, res = pcall(smp_orders.fill_from_stack, order, pname, stack)
if routed then
	...
	return res or true, "routed"
end
```

`routed` is **pcall's success flag**, not the routing result.
`fill_from_stack` returns `nil, reason` when it refuses:
`smp_orders/routing.lua:246` (`"full"`, when the stack is larger than the
order's remaining quantity), `:234` (the seller's own order), `:237`,
and `:231`. All of these come back here as `true, "routed"`:

- **Menu path:** `commit_listing` (`:885-887`) clears the flow and
  removes the detached inventory, so the stack is gone.
- **`/ah sell` path:** `ah_sell` already did
  `inv:set_stack("main", index, "")` (`:1294`), and `cerr == "routed"`
  returns, so the stack is gone.

No listing is created and nobody is paid.

**Griefing repro.**
1. The attacker opens an order for **1** diamond at a unit price above
   the market.
2. The victim runs `/ah sell 500k` holding 64 diamonds, which is $7,812
   per unit. The order pays more, so `best_open_order` picks it.
3. `fill_from_stack` returns `nil, "full"`. The 64 diamonds are deleted.
4. The attacker cancels the order and gets the escrow back.

It also triggers by accident: list anything while you have your own
better-paying order for the same item.

**Fix.**
```lua
local ok, res, why = pcall(smp_orders.fill_from_stack, order, pname, stack)
if ok and type(res) == "table" and (res.accepted or 0) > 0 then
	-- routed
	return res, "routed"
end
if not ok then log("error", ...) end
-- otherwise fall through and create the normal listing
```
`fill_from_stack` consumes the whole stack or nothing, so falling through
with the stack intact is safe. Better still, skip orders that cannot take
the stack **before** calling: `smp_orders.remaining(order) >= count` and
`order.buyer ~= pname`. That needs S04 to expose `remaining` in the
contract, which it already does as `smp_orders.remaining`.

**Tests.**
- Order remaining 1, list 64: the listing is created with count 64, and
  the stack is not lost.
- The seller's own better order: the listing is created normally.
- Order remaining ≥ 64: routed, the seller is paid `64 × unit`, and the
  stack is consumed.
- The same three cases through `/ah sell`.

---

### AH-2 — Type guard on public entry points

`smp_ah.buy`, `withdraw` and `create_listing` are cross-mod contracts.
Add this at the top of each:

```lua
if type(pname) ~= "string" or pname == "" then return nil, "offline" end
```

A caller passing an ObjectRef should then get a refusal instead of a fatal
`luaL_checkstring` error. The root caller is fixed in S05 QB-1.

### AH-3 — Sweep underpays sellers

This is fixed in S04 (`absorb_listing` should pay `l.price`, not
`floor(l.price / count) × count`). It is recorded here because the seller
is an AH user.

### AH-4 — Insert inventory left writable after the price step

`take_inserted` empties the detached `insert` list but leaves the
inventory in place with `allow_put` still active. A modified client can put
items into it during the price or confirm steps. `restore_inserted` then
does `inv:set_list("insert", {})` (`:638`), and `commit_listing` calls
`remove_detached_inventory` (`:887`). Both wipe those items. It is
self-inflicted, but it is item destruction.

**Fix:** have `allow_put` return 0 unless `flow(pname).stage == "insert"`,
and `return_stack` anything found in the list before removing the
inventory.

### AH-5 — Meta-hash-blind Quick Buy match

`listings.cheapest_for` matches on the `m1|name|ench|` prefix, deliberately
ignoring `<meta_hash>`. Quick Buy can therefore buy a stack whose other
metadata differs from what the entry describes. Record this in f05 §10
(V-58-adjacent). If any item's meta carries value, decide whether the
entry should pin `meta_hash = "0"`.

## Verified OK (no action)

- `smp_ah.buy` re-validates `state`, `version` (taken from the server-side
  session, not from a client field), expiry, funds and room, **before**
  mutating. The mutation order is money out, state change, money in, item
  in, with no yields.
- `withdraw` checks the seller and state, and cannot double-withdraw.
- Every formname is checked against `v.formname` (R4). Forged `ah_l<id>`
  fields only open a confirm screen.
- User strings in formspecs go through `F = core.formspec_escape`.

## Definition of done

- AH-1, AH-2 and AH-4 fixed, with the tests above.
- AH-5 recorded in f05 §10.

## Status (2026-09-27, verified)

| ID | Outcome | Change |
|---|---|---|
| AH-1 | **FIXED** | Routed only on an accepted fill; a refusal or raise lists normally. Routing also requires `smp_orders.can_take_stack` (S04): **merge S04 with or before S03**, or routing stays off. |
| AH-2 | **FIXED** | `buy`, `withdraw`, `validate_listing`/`create_listing` refuse non-string names with `nil, "offline"`. |
| AH-3 | **FIXED in S04** | `absorb_listing` pays `l.price`. |
| AH-4 | **FIXED** | Insert grid accepts puts only in the insert stage; strays are returned at back-out and at commit. Also refuses puts while combat-tagged (SE-4). |
| AH-5 | **RECORDED** | For f05 §10 (Quick Buy matching ignores meta hash). |
| OR-1 (AH side) | **FIXED** | Listing state writes through to storage. |

**Tests:** `dev-tests/test_ah.lua` 361/361, `test_ah_keys.lua` 110/110. Removing the AH-2 guard or the AH-4 stage lock makes the new sections fail.
