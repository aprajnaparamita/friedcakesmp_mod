# S04 — Orders: crash consistency, payout rounding, contract clarity

**Target mod:** `friedcake/mods/smp_orders/` · **Branch:** `agent/sec-s04-orders`
**Audited at:** `85e4a5d`

## Mission

Orders hold escrowed money, so they are the largest store of value outside
balances. Make order state **durable at the moment money moves**, fix a
seller underpayment, and make the `fill_from_stack` refusal contract hard to
misread. Two other mods misread it, destroying items (S03 AH-1, S05 AX-1).

## Constraints (AGENTS.md)

Edit only `smp_orders`. Tests: `dev-tests/test_orders.lua` + `smp_orders/test.lua`.

## Findings

| ID | Sev | Status | Where | One line |
|---|---|---|---|---|
| OR-1 | Medium | CONFIRMED (hard crash only) | `orders.lua:94-103`, `init.lua:742-750` | Order records are flushed on a timer while money is written immediately: a hard crash splits them |
| OR-2 | Medium | CONFIRMED | `routing.lua:227-257` | `fill_from_stack` returns `nil, reason` on refusal, which two callers read as success |
| OR-3 | Low | CONFIRMED | `routing.lua:162-163` | The auction sweep pays `floor(price/count)×count`, so the seller loses up to count−1 cents |
| OR-4 | Low | CONFIRMED | `delivery.lua:287` | `delivery.show` re-syncs `session.version` on every render, so the X2 version guard is a no-op |

---

### OR-1 — Split-brain persistence

Money moves are written through `smp_store` **immediately**. Order records
are marked dirty and written **every `store.flush_interval` (10 s)**
(`init.lua:742-750`). The same applies to AH listings (`smp_ah/init.lua:1367`).
A clean shutdown, or a Lua error that shuts the server down, runs
`on_shutdown` and flushes. A **hard crash** does not: segfault, OOM kill,
`kill -9`, power loss.

What a crash inside the window rolls back:

| Operation in the window | After restart |
|---|---|
| Delivery: supplier paid, `escrow` and `delivered` updated in memory only | The order still has the full escrow, so the buyer **cancels and is refunded money that was already paid out**. Supplier inventory may or may not be rolled back, depending on the player-save timing. |
| Cancel: refund credited, `state=cancelled` in memory only | The order is open again, so the buyer **cancels a second time** |
| Create: escrow taken, order not yet written | The money disappears |

Anyone with a way to hard-crash the server turns this into a money dupe. An
engine or mod segfault, or memory exhaustion, would do it.

**Fix.** Write through for economic transitions. In `apply_delivery`,
`escrow.refund`, `escrow.payout`, `insert_order` and `cancel`, call a
`save_one(o)` that writes `order:<id>` **in the same callback, before
the money call returns to the player**. Mod-storage `set_string` is cheap,
so keep the batched flush only for cosmetic fields. Coordinate the same
change for `smp_ah` listings (`listings.set_state` should write through,
not `mark`).

**Test.** Harness: create, deliver, then **drop the in-memory db without a
flush** and `load_all()`. The reloaded order has `delivered`, `escrow`
and `state` equal to the pre-crash values.

---

### OR-2 — Make refusals unmistakable

`fill_from_stack` returns `{accepted, payout, remaining}` on success and
`nil, reason` on refusal. Both external callers got this wrong:

- `smp_ah/init.lua:825-830` treats pcall success as routed (S03 AH-1).
- `smp_amethyst/sell_axe.lua:42` uses `accepted ~= false`, which is true
  for `nil` (S05 AX-1).

**Fix.** Keep the return shape, since the callers are being fixed, but
**document** it in the header block at `routing.lua:7-11` with an explicit
"refusal is `nil, reason_string`; test `type(r) == 'table'`" note. Add an
exported predicate so callers stop guessing:

```lua
function smp_orders.can_take_stack(order, name, stack) -> bool, reason
```

Have `smp_ah.create_listing` call it before routing.

**Test.** A contract test in `test_orders.lua` enumerates every refusal
reason, asserts that each returns exactly `nil, string`, and asserts
that the stack's count is unchanged.

---

### OR-3 — Sweep underpays auction sellers

`absorb_listing` computes `unit = floor(l.unit_price)`, which
`smp_ah/listings.lua:414` already floors, and pays `unit × count`. A
listing of 3 items for $10.00 pays $9.99. The escrow keeps the cent.

**Fix.** Pay `cost = l.price` when `l.price <= o.escrow` and
`floor(l.price / count) <= o.unit_price`. The at-or-below check stays on
the unit price.

**Test.** A listing of 3 items at 1000 cents absorbed by an order at 400
cents per item: the seller receives 1000.

### OR-4 — Version guard re-synced on render

`delivery.show` sets `session.version = o.version` before every render
(`delivery.lua:287`), and `on_put`, `on_take` and `on_move` re-render. The
check at confirm time therefore passes unless the order changes between the
last render and the click. It is harmless today, because `deliver()`
re-validates `state` and `remaining` itself. Either drop the version
check or set the version only in `delivery.open`, so the guard means what
the comment says.

## Verified OK (no action)

- Escrow conservation: payout and refund clamp to the escrow. Cap-limited
  credits leave the remainder in escrow (`escrow.lua:36-78`).
- The delivery grid is owner-only (`delivery.lua:108-122`). Every item is
  returned on quit, leave and refusal. Grid copies are cleared after
  `deliver` (X1).
- Wizard steps cannot be skipped by forged fields. Step 4 is reachable
  only with the item, amount and price set.
- `manage_fields` checks `o.buyer == pname` for collect and cancel.
  Forged `order_<id>` on the board opens only a delivery screen.
- Order keys come from `smp_items.key(ItemStack(name), "M1")`, so the
  meta hash is always `"0"`. Rebuilding at collection time (`stack_from_key`)
  therefore loses nothing.

## Status (2026-09-27)

Branch `agent/sec-s04-orders` (worktree `coconut-sec-s04`). Code only
under `friedcake/mods/smp_orders/**` + `dev-tests/test_orders.lua` +
`smp_orders/test.lua`; §10 records in `spec/features/f04-orders.md`.

| ID | Outcome | Where |
|----|---------|-------|
| OR-1 | FIXED | `orders.lua` `save_one`/`reserve_id` write-through; `escrow.lua` record-before-money; `routing.lua` create reordered, collect/cancel save; crash test `== OR-1 … ==` in `dev-tests/test_orders.lua` |
| OR-2 | FIXED | `routing.lua` header contract verbatim + `can_take_stack` export; `fill_from_stack` delegates validation; shape unchanged for S03/S05 callers; tests in `dev-tests` (`== OR-2 … ==`) and `smp_orders/test.lua` |
| OR-3 | FIXED | `routing.lua` `absorb_listing` pays `l.price` (fallback `unit × count`); test `== OR-3 … ==` |
| OR-4 | FIXED (PROPOSED edge) | `delivery.lua` version pinned only in `delivery.open`; stale `delivery.show` closes the session and returns parked items (PROPOSED, justified in f04 §10); test `== OR-4 … ==` |
| SE-4 / CB-1 | FIXED | `delivery.lua` `allow_put` soft `smp_combat.is_tagged` check (covers drag + shift-click via `IMoveAction::apply` on the destination); `mod.conf` `optional_depends += smp_combat` (no cycle); test `== SE-4 / CB-1 … ==` |
| Harness | FIXED (incidental) | `dev-tests/test_orders.lua` `find_root()` probed `friedcake/modpack.conf` (does not exist; real path `friedcake/mods/modpack.conf`), so worktree runs silently loaded the main checkout's `smp_orders`. Probe corrected. |

**Tests.** `luajit friedcake/dev-tests/test_orders.lua` → `passed=780
failed=0 ALL OK` (baseline 598). `test_engine_apis.lua` → `passed=16`.
Full `dev-tests/` from the worktree root: 24/27 green; the 3 failures are
pre-existing and untouched (`test_config_mirror.lua` mirror rows,
`test_enderchest.lua` `T8 modpack.conf readable`, `test_integration.lua`
`cannot open modpack.conf`).

**Hand-offs.** S03 (AH-1) / S05 (AX-1): `fill_from_stack` keeps its
`{accepted,payout,remaining} | nil, reason` shape — only the caller-side
`type(r) == 'table'` test belongs to those briefs; no `smp_ah` edit was
needed from here. Engine note: `ModStorage::setString` commits per
statement on the sqlite3 backend (new worlds) but buffers until
`endSave` on the legacy `files` backend — surfaced as an integrator note
in f04 §10, not edited in `spec/shared/`.
