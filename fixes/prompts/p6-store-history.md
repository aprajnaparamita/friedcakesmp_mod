# Agent prompt — P6: D12 — generic `smp_store` history API

| Field | Value |
|---|---|
| Feature spec | `spec/features/f02-sell.md` §6:139 + §11, `spec/features/f03-auction.md` §6 (seam amendments only) |
| Target | `friedcake/mods/smp_store/**`, `friedcake/dev-tests/test_store.lua` |
| Audit source | `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D12 row (was OPEN-1) |
| Verdict at audit | two blocked ESCALATEs: f02 proposes `append_sell_history`, f03 proposes `append_history` — one generic API serves both |
| Branch | `agent/rulings-store-history` (base: tip of `agent/integrator-decisions` **after P1 merged**) |
| Wave | 3 — runs in parallel with P5 (file-disjoint); after P1 because it edits `f02 §6` adjacent to P1's D2 line |

## Mission

D12 (ruled 2026-09-24, was OPEN-1): build **one** history seam instead of two.
Add `smp_store.api.append_history(kind, name, entry) -> id` mirroring the
existing ledger helpers, extend all three drivers with parity, and amend the
two feature specs' PROPOSED seams to the final signature. Consumer wiring —
f02's `smp_sell/history.lua` local `_read`/`_write` (V-94) and f03's history
storage — stays the f02/f03 briefs' rows: you build and specify, they wire.

## Read this first (in order)

1. `AGENTS.md` — rules 1–8 (integer cents; no yields between validate and
   mutate; `smp_store` is integrator-owned and **this prompt is the explicit
   grant** to edit it).
2. `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D12 row, and
   the OPEN-1 paragraph (now ruled).
3. `fixes/REQUIREMENTS.md` §2 *D12* — the exact change list.
4. `friedcake/mods/smp_store/ledger.lua` and its driver implementations in
   `backends/{mod_storage,sqlite,postgres}.lua` — **copy these conventions
   exactly**: API shape, driver surface, how the ledger is tested for each
   backend.
5. `friedcake/dev-tests/test_store.lua` — the harness you extend; note which
   backends it already drives and how.
6. `spec/features/f02-sell.md` §6 (line 139) and §11 (the `append_sell_history`
   proposal, V-94); `spec/features/f03-auction.md` §6 (the `append_history`
   proposal).

## Requirements

**R1 — the API.**
- `smp_store.api.append_history(kind, name, entry) -> id`.
- `kind`: string namespace (`"sell"`, `"auction"`, extensible); `name`: player
  name (works for offline names, same rule as the rest of the store); `entry`:
  plain table, round-trips exactly, carries `t = os.time()`.
- Append-only per `(kind, name)` with FIFO prune to `cap` (optional argument,
  **default 100** — matches `sell.history_size`'s default). Prune keeps the
  newest.
- `id`: monotonic integer per `(kind, name)` or per store — pick one, document
  it in the docstring comment, never return a float.
- Money anywhere inside an entry is integer cents (you don't do arithmetic —
  callers pass cents; just don't corrupt them).

**R2 — drivers with parity.**
- Extend `backends/mod_storage.lua`, `backends/sqlite.lua`,
  `backends/postgres.lua` the same way the ledger is implemented in each —
  same naming, same error behaviour, same transaction discipline.
- If the dev harness cannot reach postgres, follow however `test_store.lua`
  currently covers the ledger for it (fake, skip-with-note — mirror the
  existing pattern, invent nothing) and say in your reply which pattern you
  copied.
- No yields between validate and mutate anywhere in the new path (§2.3).

**R3 — spec amendments (the two blocked seams).**
- `f02-sell.md` §11: rewrite the proposal to the ruled outcome — generic
  `smp_store.api.append_history("sell", player, entry)`, marked decided
  (D12, 2026-09-24); V-94's local-seam description becomes "local until the
  f02 brief wires `history.lua` onto the API" — keep the OBSERVED facts.
- `f02-sell.md` §6 line 139: `smp_store.append_sell_history(player, receipt)`
  → the generic call with a receipt-shaped entry (P1 deliberately left this
  line to you).
- `f03-auction.md` §6: `append_history(kind, payload)` PROPOSED → the final
  signature with an explicit `name` parameter, marked decided (D12).
- Doc-grammar rules: apply to §7-table rows only — these are prose lines, so
  normal Markdown, no prose retrofits.

**R4 — tests.**
- Extend `friedcake/dev-tests/test_store.lua` (same harness style, no engine):
  append returns an integer id; round-trip equality; FIFO prune at cap;
  kind-isolation (`"sell"` vs `"auction"` same name never mix);
  name-isolation; offline name works; every backend the file already drives
  gets the same cases.

## Out of scope (hard)

- Wiring `smp_sell/history.lua`, `smp_sell/items.lua`, or any `smp_ah`/
  `smp_orders` consumer onto the API (f02/f03 briefs' rows).
- Any other `smp_store` behaviour — ledger, money, player blobs untouched.
- `smp_admin` (P4), `spec/shared/06` + §7 tables (P2), `f02 §6` beyond line
  139 (P1), `spec/plan/**` (P3/P5), `fixes/**`, other dev-tests.

## Tests

- `luajit friedcake/dev-tests/test_store.lua` → exit 0 with R4 cases added.
- Full suite green: every `friedcake/dev-tests/test_*.lua` exits 0 (baseline
  is 22 files; none may regress).

## Constraints

- Money integer cents; no player-facing strings (if any, `core.get_translator`);
  no yields in the economic path; no floats as ids.
- Files you may write: `friedcake/mods/smp_store/**`,
  `friedcake/dev-tests/test_store.lua`, `spec/features/f02-sell.md` (lines
  139 + §11 only), `spec/features/f03-auction.md` (§6 only). Everything else
  → ESCALATE + stop.

## Definition of done

1. R1–R4 complete; `test_store.lua` green with new cases; full suite green.
2. Reply with: chosen `id` semantics, per-backend coverage pattern you
   mirrored (and the postgres decision), the exact three spec-line edits, and
   test output.
3. Commit with `D12` in the message; push `agent/rulings-store-history`,
   never `main`.
