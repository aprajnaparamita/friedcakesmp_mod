# Fix brief — f04 Orders

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f04-orders.md` |
| Target mod(s) | `smp_orders` (+ `fixes/README.md` row update at the end) |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f04 |
| Verdict at audit | **MOSTLY COMPLETE (3 gaps)** · 48 OK · T1–T14 green (+ 1 consumer item handed over from f13) |
| Branch | `agent/f04-orders-fixes` |
| Depends on | `00-P0-blockers` (B1-3 + harness shim), D7 (slots + flush-interval ruling); consumer row also references the f13 brief `fixes/f13-ranks.md` — **ruled 2026-09-24: D7 = A (slots settled: dotted scalar primary, `orders_slots_default`-style underscore alias — O2/O3 implement the code side; mirror by P2)** — **P5 finding: `smp_orders` sits in two boot-aborting `optional_depends` cycles (`↔ smp_sell`, and `→ smp_shardshop → smp_amethyst → smp_orders`) — mod.conf is yours** |

---

## Mission

`smp_orders` passes 48 rows and T1–T14, but two declared OBSERVED/LIVE config
keys are never read (sorts hardcoded, slot table in an encoding that matches
neither its own spec row nor f03's), the §4.13 notification toggle still
carries a stale `TODO(f12)` although f12 has shipped, and — handed over from
the f13 brief — `slot_limit` reads `rec.rank` raw so an **expired** rank keeps
granting order perks. "Fixed" means the operator's `orders.sorts` /
`orders.slots.*` settings work, `eco.order_alerts` is genuinely honoured both
ways, expired ranks stop granting capacity, and every observed string, escrow
invariant and routing contract survives byte-for-byte — otherwise a popular
high-value feature silently mis-pays or mis-restricts players.

## Read this first (in order)

1. `AGENTS.md` — hard rules (esp. 1, 4, 6–8).
2. `spec/features/f04-orders.md` — §4.13 (line 236), §7 (lines 327-336), §9
   (lines 356-373), §10, §11, `## Proposed shared changes`.
3. `spec/shared/02-architecture.md` (§2.3 no-yields, §2.6 R9),
   `04-ui-kit.md`, `05-command-reference.md`, `06-config-reference.md`
   (rows `06:24` `orders.slots`, `06:27` `orders.sorts`, `06:79`
   `store.flush_interval`), `08-ui-strings.md` (line 29:
   `Orders (Page @1)`) — READ ONLY.
4. `spec/plan/acceptance-tests.md` — your row is line 18: **f04-orders |
   T1–T14** (+ race drill X2) — the merge gate.
5. `SPEC-CONFORMANCE-REPORT.md` §4 f04 (lines 313-349), §4 f13 consumer row
   (line 664), §2 B1 #3 (line 75).
6. Target mod source (`friedcake/mods/smp_orders/*.lua`, `test.lua`) +
   `friedcake/dev-tests/test_orders.lua` + `test.lua` header.
7. For the consumer row: `friedcake/mods/smp_ranks/{perk,grant,expiry}.lua`
   and the f13 brief `fixes/f13-ranks.md` (written in parallel by the f13
   agent — if it does not exist yet, the contract is `smp_ranks.tier(who)`
   (`perk.lua:44`, lazy expiry at `:52-53`) and `smp_ranks.order_limit(who)`
   (`perk.lua:76`)).

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| O1 | report §2 B1 #3 / `00-P0-blockers.md` B1-3 | `core.register_on_globalstep` (nonexistent engine API) — mod cannot load | `smp_orders/init.lua:709`; harness fake `dev-tests/test_orders.lua:303` | **Owned by the P0 brief — do not re-do, do not regress.** Before you start confirm the line reads `core.register_globalstep` and that `test_orders.lua`'s `core` stub provides the *real* name (P0 B4-1 deletes the fake). If your suite cannot load until the stub is renamed, that rename is part of P0 — coordinate, don't re-add a fake | DEPENDS-BLOCKER (B1-3) |
| O2 | f04 §7 line 334 / `06:27` | `orders.sorts` declared **OBSERVED** but never read; table hardcoded | `smp_orders/init.lua:48`; consumers `init.lua:187,407-412,639` | Read `orders.sorts` as a comma-separated list (parse pattern: the blacklist right below at `init.lua:58-65`), default exactly `{most_per_item, most_paid, recently_listed}`; validate entries (skip garbage → default) so the Filter cycle can never break; T1 asserts the cycle order and that the auction's sorts are absent | IN-SCOPE |
| O3 | f04 §7 line 331 / `06:24` vs f03 | `orders.slots` read as underscore scalars — matches neither the declared table key nor f03's dotted style | `smp_orders/init.lua:41-46` (`orders.slots_default`, `orders.slots_tier1`, …); f03 reads `ah.slots.default…` (`smp_ah/init.lua:59-62`) | **Shared-convention ruling is D7's** — record in `f04-orders.md §10` pointing at D7 and stop. Meanwhile make the documented (dotted) spelling work: read `orders.slots.default|tier1|tier2|tier3` as primary, keep `orders.slots_default…` as back-compat aliases so no existing `minetest.conf` breaks | ESCALATE (D7) + IN-SCOPE (make documented spelling work) |
| O4 | f04 §4.13 (line 236) / `06` | Notifications respect `eco.order_alerts`, but `routing.lua` carries a stale `TODO(f12): default on until smp_settings ships` — f12 has shipped | `smp_orders/routing.lua:45-58`, stale comment at `:53`; `smp_settings.get` exists (`smp_settings/accessor.lua:32`) | 1) Remove/reword the stale TODO (comment only — the `nil → true` fallback stays: f12 deliberately leaves `eco.order_alerts` unregistered until its category opens with evidence, `f12-settings.md:290-295`, so `nil → default on` is correct and must be kept). 2) **Verify the value is honoured on/off**: add tests driving `smp_settings.get` to return `true` (notify sends), `false` (notify suppressed), `nil` (default on). 3) If verification shows the toggle cannot be *set* by a player (unregistered id ⇒ `smp_settings.set` refuses, `accessor.lua:53-54`), do **not** edit `smp_settings` — record it in `f04-orders.md §10` as a note to f12/V-39 | IN-SCOPE |
| O5 | f13 §4.2.4 / §11.3.2 (report line 664) | Consumers must read the **effective** rank honouring `expires_at`; `slot_limit` reads `rec.rank` raw, so an expired rank still grants order slot capacity | `smp_orders/orders.lua:204-206` (`local tier = rec and rec.rank and rec.rank.tier or "default"`) | Read the effective tier through `smp_ranks`: prefer `smp_ranks.order_limit(name)` (`smp_ranks/perk.lua:76`) or `smp_ranks.tier(name)` (`perk.lua:44` — checks `expires_at > os.time()` lazily), guarded `if smp_ranks and …`; fall back to `rec.rank.tier` only when `smp_ranks` is absent. Add `smp_ranks` to `smp_orders/mod.conf` `optional_depends` (line 4 — your own file). Test: rank record with `expires_at` in the past ⇒ default tier, no perk | IN-SCOPE (consumer item from f13) |
| O6 | report f04 "Hygiene note" (line 347) | Stale `TODO(f03)` comments claim smp_ah stubs that already delegate to shipped f03 functions — comments only, behaviour is correct | `smp_orders/init.lua:14`; `au_bridge.lua:42,56` (guards at `:34,:49` already call `smp_ah.listings_at_or_below` / `consume_listing`); additionally re-verified same class: `routing.lua:143` section header "until smp_ah ships", `routing.lua:170` "(TODO(f03))" | Reword/remove the stale tags (behaviour untouched): the bridge falls back only when `smp_ah` is absent, which is graceful degradation, not a missing feature. **`smp_amethyst/sell_axe.lua:15` says the same but belongs to f06 — ESCALATE that one line in `f04-orders.md §10`, do not edit it** | IN-SCOPE (comments) / ESCALATE (`sell_axe.lua:15` → f06) |
| O7 | report §3.3 line 174 | In-game `test.lua` header overclaims "§9 T1–T14" while heavy tests live only in dev-tests | `smp_orders/test.lua:6` (`-- Covers spec/features/f04-orders.md §9 T1–T14.`) | Fix the header to state accurately what this file covers, **or** lift the missing T-cases in (AGENTS step 7 quality bar) — either is acceptable, lying headers are not | IN-SCOPE |
| O8 | `06:79` `store.flush_interval` vs beyond-spec key | `orders.flush_interval` shadows the shared `store.flush_interval` that f03 reads (`smp_ah/init.lua:55`) — two keys, one concept | `smp_orders/init.lua:53` | Align in your mod: read shared `store.flush_interval` first with `orders.flush_interval` as back-compat alias (defaults agree: 10 s). Whether the `orders.*` key is declared in `shared/06` or struck is **D7** — propose it in §10, never hand-edit the mirror | IN-SCOPE (code) + ESCALATE (mirror → D7) |
| O9 | shared §0.5 (`spec/shared/00-conventions.md:88`, no terminal full stop on unobserved strings) — routed from f01 §10.2 **F-6** by the overseer 2026-09-25 (same class as D1/E-27) | `Insufficient funds.` carries a terminal full stop; the auction house's OBSERVED-form string is period-free (`smp_ah/init.lua:179-180`), and f01's own copy is period-free | `smp_orders/routing.lua:104`, `:133`; the dev-test **pins the old literal** at `dev-tests/test_orders.lua:828` (`eq(err_funds, "Insufficient funds.", …)`) | Strip the terminal full stop at both code sites (keep the strings inside `core.get_translator`) and update the `test_orders.lua:828` assertion to `"Insufficient funds"`. Check `mods/smp_orders/test.lua` does not pin the period too | **IN-SCOPE (minor)** |

### O4 detail

`alerts_on` (`routing.lua:48-54`) is called by `notify_buyer` (`:56-61`) and
any other notification path — grep `alerts_on` before testing so both ways are
covered at the choke point. The dev-test harness has no live settings store:
stub `smp_settings` (or its `get`) per case; also assert the
`smp_settings`-absent path returns `true`.

### O5 detail

`fixes/f13-ranks.md` documents the consumer contract from the f13 side; the
ranks mod itself is read-only for you. `smp_orders` currently has **no**
`smp_ranks` entry in `mod.conf` — without the optional-depend declaration the
call can race load order; guard for absence so a ranks-less pack still works.

## Acceptance criteria

1. `orders.sorts` and `orders.slots.*` (documented spelling) are read from
   settings; defaults produce byte-identical behaviour to today; the
   underscore-alias and old defaults still work.
2. `eco.order_alerts` verified both ways with tests; stale TODO removed;
   un-settable-toggle finding (if any) recorded in §10, not patched into
   `smp_settings`.
3. Expired-rank test green: `rec.rank = {tier="tier2", expires_at = past}` ⇒
   order slots = default tier until `smp_ranks` says otherwise.
4. O3/O6/O8 escalations recorded in `f04-orders.md §10`.
5. **Preserve exactly** — nothing below changes by one byte or one tick:
   - All 14 observed strings character-exact: `Orders (Page N)` — verified
     against spec: `f04:204` and `shared/08:29` both say `Orders (Page @1)`
     **with** both parens and `formspec.lua:160` renders it that way; there is
     no missing-paren quirk to reproduce — keep the spec form exactly;
     `Choose Item (1 results)` (ungrammatical on purpose), `How many?`,
     `Price per item?`, `Minimum: $ 1`, `Review Order`, `Cancel!`,
     `Create Order`, `Orders -> …` breadcrumbs, `Click to deliver items ($N)`,
     `Delivering...`, the singular-name line `You delivered 1 Totem of Undying
     and received $30K`, the six-line tooltip order with `251/350 Delivered`.
   - Escrow = `unit × qty` with `Total:` as committed; AH creation sweep
     cheapest-first with per-seller payout; delivery over detached inventory
     with M1 matching / partial fills / returns; self-delivery refused; all
     four routing-in sources (`/sell`, spawner Sell all, amethyst sell axe,
     auction listings); cancel/expiry refunds; capacity tiers; amethyst
     blacklist; §5 schema; §6 algorithms; T1–T14 + routing-in API contracts
     (`best_open_order`, `fill_from_stack`, `open_orders_above`,
     `absorb_from_sell`, `au.*`), quit-return, version race, persistence.
   - Beyond spec: `orders.expire_check_interval`, manage screen,
     `Order created` line, expiry notification, exact-itemstring blacklist
     with graceful degradation, `Too fast, slow down` (R9).
   - No yields between validate and mutate anywhere on escrow/payout paths.

## Tests

- `luajit friedcake/dev-tests/test_orders.lua` — must exit 0; new cases:
  - default sorts ⇒ T1 assertions (`test_orders.lua:1096-1119`) untouched;
    `orders.sorts = most_paid,recently_listed` set ⇒ cycle follows it;
    garbage ⇒ default;
  - slots: `orders.slots.default = 3` honoured **and** legacy
    `orders.slots_default = 3` still honoured (alias), unset ⇒ 9;
  - O4: `eco.order_alerts` = `true` / `false` / `nil` / settings-mod absent ⇒
    notify sends / suppresses / sends / sends;
  - O5: expired rank (`expires_at` past) does not grant tier capacity; live
    rank does; `smp_ranks` absent ⇒ fallback path works;
  - O8: `store.flush_interval` read, `orders.flush_interval` alias still read.
- In-mod `friedcake/mods/smp_orders/test.lua` — update header (O7) and add the
  string/sort/alias cases safe for live re-run.
- Exact gate (must exit 0):
  ```
  luajit friedcake/dev-tests/test_orders.lua
  ```

## Constraints

- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — proposals flow
  through `f04-orders.md` §10 / `## Proposed shared changes` only.
- No edits to `smp_core`, `smp_store`, `smp_admin` (AGENTS rule 4 — escalate).
- One agent per feature file: touch only `smp_orders` (+ your own feature
  file, your own dev-tests, `fixes/README.md` row). `smp_amethyst`,
  `smp_ranks`, `smp_settings`, `smp_ah` are read/consume only — their defects
  get escalated in §10, never patched.
- Money is integer cents; display only via `smp_core.fmt_money`.
- Every player-facing string through `core.get_translator`.
- No yields between validate and mutate in any economic operation.
- Verbatim UI strings character-exact.
- Config keys must match `spec/shared/06-config-reference.md` — propose
  mirror changes (D7), never hand-edit.
- Never downgrade an OBSERVED requirement; invented behaviour marked
  `PROPOSED` in your own feature file.
- Do not regress O1/P0.

## Out of scope

- **Quick-buy → orders routing is N/A by spec** (`f04 §4.8` and `f05` define
  none; `smp_quickbuy` has zero references to `smp_orders`) — do not invent it.
- D7's ruling itself (slots encoding, flush-interval mirror) — integrator.
- Registering `eco.order_alerts` in f12's registry — f12's file (§10 note).
- `smp_amethyst/sell_axe.lua:15` comment — f06's file (escalate only).
- The two f03 integration seams listed in `f04 "Proposed shared changes" 5`
  (double ledger row, `(nil, reason)` mis-read) — coordinate with the f03
  brief/integrator; propose only.
- D11 integration harness — structural, integrator-owned.

## Definition of done

1. Every issue ID O1–O8 is either fixed or escalated, with the reason written
   into `spec/features/f04-orders.md §10` (O3, O4-finding, O6/sell_axe, O8
   mirror).
2. `luajit friedcake/dev-tests/test_orders.lua` exits 0 — paste output into
   the PR/branch description.
3. In-mod `smp_orders/test.lua` updated (header no longer overclaims).
4. `git checkout -b agent/f04-orders-fixes` from `main`; commit references
   `SPEC-CONFORMANCE-REPORT.md §4 f04` (+ f13 consumer row line 664); push the
   **branch**, never `main`.
5. PR description carries the issue ID → evidence mapping (O1…O8 →
   `file:line` + commit).
6. `fixes/README.md` row `f04` annotated with what closed vs escalated.
