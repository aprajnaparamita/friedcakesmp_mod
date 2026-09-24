# Fix brief — f03 Auction house

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f03-auction.md` |
| Target mod(s) | `smp_ah` (+ `fixes/README.md` row update at the end) |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f03 |
| Verdict at audit | **MOSTLY COMPLETE (4 gaps)** · 44 OK · T1–T10 green |
| Branch | `agent/f03-auction-fixes` |
| Depends on | `00-P0-blockers` (B1-2 site + `ah_harness` shim — must land first), D7 (slots-encoding ruling); D1 awareness only (f05's side is the one that must yield) — **ruled 2026-09-24: D7 = A (slots: dotted scalar primary + underscore alias; mirror/§7 by P2 — your A4–A6 code rows remain yours, incl. the `ah.history` `pending:f03` marker), D1 = A (period-free form, applied by P1)** |

---

## Mission

`smp_ah` is the healthiest large mod in the pack — 44 rows OK, all 11 observed
strings character-exact, T1–T10 + the key-identity suite green — but four §7/§4
requirements diverge: the configurable sort list and the history keys are
declared OBSERVED/LIVE and never read, the slot-table encoding disagrees with
f04's, and the §4.12 "Match lowest" button was never built. "Fixed" means an
operator's `ah.sorts`, `ah.history` and `ah.slots.*` settings actually work, the
proposed Quick Auction Sell affordance exists per spec wording, and every
OBSERVED byte and economic invariant above survives untouched — the consequence
of getting the preserve list wrong is a broken observed UI on a feature that is
otherwise ship-ready.

## Read this first (in order)

1. `AGENTS.md` — hard rules (esp. 1, 4, 6–8).
2. `spec/features/f03-auction.md` — §4.12 (line 206-208), §7 (lines 293-303),
   §9 (lines 322-335), §10, §11.1, `## Proposed shared changes`.
3. `spec/shared/02-architecture.md`, `04-ui-kit.md`, `05-command-reference.md`,
   `06-config-reference.md` (rows `06:17` `ah.slots`, `06:22` `ah.sorts`,
   `06:23` `ah.history`, `06:79` `store.flush_interval`), `08-ui-strings.md`
   (READ ONLY).
4. `spec/plan/acceptance-tests.md` — your row is line 17: **f03-auction |
   T1–T10** (+ race drill X2, perf budget X7) — the merge gate.
5. `SPEC-CONFORMANCE-REPORT.md` §4 f03 (lines 280-311) and §2 B1 #2 (line 74).
6. Target mod source (`friedcake/mods/smp_ah/{init,listings,formspec,keys}.lua`,
   `test.lua`) + `friedcake/dev-tests/test_ah.lua` and `test_ah_keys.lua` +
   `friedcake/dev-tests/ah_harness.lua`.

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| A1 | report §2 B1 #2 / `00-P0-blockers.md` B1-2, B4 | `core.register_on_globalstep` (nonexistent engine API) — mod cannot load | `smp_ah/init.lua:1276`; harness fake `dev-tests/ah_harness.lua:782` | **Owned by the P0 brief — do not re-do, do not regress.** Before you start, confirm the line reads `core.register_globalstep` and that `ah_harness` provides the *real* name (P0 deletes the fake). Never re-introduce the fake after P0 lands | DEPENDS-BLOCKER (B1-2) |
| A2 | f03 §4.12 (lines 206-208) | Quick Auction Sell "Match lowest" button on `Confirm Listing` — no string, no handler anywhere (`grep -r "Match lowest" friedcake/` = 0 hits; PROPOSED-only, no frame evidence) | spec `f03-auction.md:206-208`; `smp_ah/formspec.lua` (Confirm Listing screen), `smp_ah/init.lua` (listing draft/confirm handler) | **Implement** the button on `Confirm Listing` per §4.12's wording: label exactly `Match lowest` (through `core.get_translator`), action = replace the draft price with the current lowest active listing's price for the same item (use the §4.15 unit-price index — no full scan), then normal validation applies unchanged (price bounds, fees, re-validation, no yields). Handle "no listings yet" by leaving the draft untouched. Record every invented detail (tooltip, no-listing behaviour, total-vs-unit interpretation) as PROPOSED in f03 §11.1 and note it in §10. *Fallback if you judge it must wait for frame evidence: ESCALATE in `f03-auction.md §10` with that reasoning — but §4.12 is written normatively, so implementing is the recommended path* | IN-SCOPE (low priority) |
| A3 | f03 §7 line 302 / `06:22` | `ah.sorts` declared **OBSERVED** but never read; sort table hardcoded | `smp_ah/init.lua:65` (`sorts = { "lowest_price", "highest_price", "recently_listed" }`); consumers `init.lua:338,417,445,457`; `reload_cfg` at `init.lua:69-93` also skips it | Read `ah.sorts` as a comma-separated list (parse pattern: `smp_orders/init.lua:58-65` blacklist `gmatch`), defaulting to exactly `{lowest_price, highest_price, recently_listed}`; validate entries against the known sort ids (skip/fall back to default on garbage so a typo cannot break the Filter cycle); wire it into `reload_cfg` alongside the other keys | IN-SCOPE |
| A4 | f03 §7 line 303 / `06:23` | `ah.history` (100 per page, 10 pages, LIVE [S23]) never read; code only reads its own split keys | `smp_ah/init.lua:53-54` (`ah.history_page` / `ah.history_pages`); consumers `listings.lua:43-44,220,769-782` | Read the documented key `ah.history` (as a comma-list `per_page,pages` — record that encoding PROPOSED in §10), keeping `ah.history_page`/`ah.history_pages` as back-compat aliases; defaults stay exactly 100 per page / 10 pages; caps logic (`listings.lua:220,769`) unchanged | IN-SCOPE |
| A5 | f03 §7 line 297 / `06:17` vs f04 | `ah.slots` table read as dotted scalars; encoding inconsistent with f04's underscore scalars of the same table | `smp_ah/init.lua:59-62` (`ah.slots.default|tier1|tier2|tier3`), reload `init.lua:84-87`; f04 reads `orders.slots_default…` (`smp_orders/init.lua:41-46`) | **The one-convention ruling is D7's** — record the cross-mod inconsistency in `f03-auction.md §10` pointing at D7 and stop. Meanwhile keep the documented (dotted) spelling as-is so an operator's `ah.slots.default = 45` works; verify both load and reload paths read it | ESCALATE (D7) |
| A6 | AGENTS (spec silence → mark PROPOSED) | Keys code reads but f03 §7 never declares: `ah.reclaim_days` (`:50`), `ah.insert_slots` (`:51`), `ah.rate_limit` (`:52`), `ah.sweep_interval` (`:56`), `ah.sweep_budget` (`:57`) | `smp_ah/init.lua:50-52,56-57` | Declare all five in `f03-auction.md §7` as `PROPOSED` rows with their defaults (30 d / 5 / 1 per s / 60 s / 200) — `ah.reclaim_days` is already sanctioned by §11.1, so this is bookkeeping; rate limiting itself is sanctioned by `spec/shared/02-architecture.md §2.6 R9` (line 128), only the key name was undeclared. **Mirror additions to `shared/06` are D7's** — propose them in §10, never hand-edit | IN-SCOPE |
| A7 | report f03 "Beyond spec" seam note | Confirm the stale-seam direction: does any neighbouring mod still claim `smp_ah` is a stub? | Re-verified: `grep -rn "TODO(f03)" friedcake/mods` matches **only** `smp_orders` (`init.lua:14`, `au_bridge.lua:42,56`, `routing.lua:143,170`) — that is f04's mod, cleaned by the f04 brief. `smp_ah`'s own `smp_orders` stub for standalone load | Re-run the grep, paste the result in the PR, keep the stub at `init.lua:656-661` (correct, ships `best_open_order` only when f04 is absent). No edits outside `smp_ah` | IN-SCOPE (verify-only) |

### A2 detail (if implementing)

F0142's `Confirm Listing` grid already carries a red `Cancel` pane (§11.1).
Add `Match lowest` as one more control (house style: label + `Click to …`
two-line tooltip, `shared/00-conventions.md §0.5.4`). It mutates only the
server-side listing *draft* — no money, no listing write happens in the button
handler, so §2.3 (no yields between validate and mutate) is trivially kept.
Do not alter the observed tooltip lines (`You're going to sell this item for
$@1` …) or any other element of the screen.

## Acceptance criteria

1. `core.settings:get("ah.sorts")` / `ah.history` / `ah.slots.*` are read;
   defaults produce byte-identical behaviour to today (T3 cycle order
   unchanged).
2. `Match lowest` button exists on `Confirm Listing`, works per §4.12 wording,
   and every invented detail is recorded PROPOSED in §11.1/§10 — **or** the
   row is escalated in §10 with reasoning.
3. A5/A6 escalations recorded in `f03-auction.md §10` (A6's §7 rows added).
4. **Preserve exactly** — nothing below changes by one byte or one tick:
   - All 11 observed strings character-exact: `Auction (Page N)`,
     `Search`/`Click to search`, `Filter`/`Click to change` + option list,
     `Your Items`/`Click to view`, `Search Auction`, `Auction > Your Items`,
     `Insert Item`, `Edit Sign Message`, `Type price`, `Done`,
     `Confirm Listing`, `Auction > Confirm Purchase`, the total-price line
     (`You're going to sell this item for $@1`), the **period-free**
     `This item was already bought` (OBSERVED; D1 concerns f05's side — do
     not touch yours), and the three sort labels in observed cycle order
     `Lowest Price → Highest Price → Recently Listed`.
   - Total-price (not unit) semantics; re-validate + funds + room with **no
     yields** (`init.lua:850-872`); capacity 45/90/default 9; 48 h expiry +
     30-day reclaim; fees; both routing directions; 100-per-page history caps;
     `$1…$10¹²` bounds; unit-price + token indexes (no full scans);
     T1–T10 + `test_ah_keys`.
   - Beyond spec: legacy `k0/k1/k2` key migration, the `smp_items`
     deferral shim, cancel/reclaim affordances (§11.1 PROPOSED).
5. P0 not regressed: `rg 'register_on_globalstep|core\.modpath' friedcake/mods`
   still returns zero after your branch.

## Tests

- `luajit friedcake/dev-tests/test_ah.lua` — must exit 0; new cases:
  - default `ah.sorts` ⇒ T3 cycle unchanged (existing assertions at
    `test_ah.lua:199-234` still pass untouched);
  - `ah.sorts = recently_listed,lowest_price` set ⇒ cycle order follows the
    setting; garbage entry ⇒ falls back to the default set;
  - `ah.history = 100,10` and the legacy `ah.history_page`/`ah.history_pages`
    aliases both configure `listings` (cap = per_page × pages);
  - A2: Confirm Listing renders `Match lowest`; activating it rewrites the
    draft price; out-of-bounds result still refused by the normal path.
- `luajit friedcake/dev-tests/test_ah_keys.lua` — must exit 0 (unchanged).
- In-mod `friedcake/mods/smp_ah/test.lua` — add the sorts/history/slots
  setting cases safe for live re-run; `A1`-adjacent: assert the harness
  registers the playtime/globalstep callback under `core.register_globalstep`.
- Exact gate (both must exit 0):
  ```
  luajit friedcake/dev-tests/test_ah.lua && luajit friedcake/dev-tests/test_ah_keys.lua
  ```

## Constraints

- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — proposals flow
  through `f03-auction.md` §10 / `## Proposed shared changes` only.
- No edits to `smp_core`, `smp_store`, `smp_admin` (AGENTS rule 4 — escalate).
- One agent per feature file: touch only `smp_ah` (+ your own feature file +
  your own dev-tests and `fixes/README.md` row). `smp_orders`,
  `smp_amethyst`, etc. are others' mods — cross-mod seams are propose-only.
- Money is integer cents; display only via `smp_core.fmt_money`.
- Every player-facing string through `core.get_translator`.
- No yields between validate and mutate in any economic operation
  (`shared/02-architecture.md §2.3`).
- Verbatim UI strings character-exact.
- Config keys must match `spec/shared/06-config-reference.md` — if code and
  mirror disagree, propose the mirror change (D7), never hand-edit it.
- Never downgrade an OBSERVED requirement; new/invented behaviour is marked
  `PROPOSED` in the spec file you own.
- Do not regress A1/P0: no `register_on_globalstep`, no re-added harness fakes.

## Out of scope

- D7 itself (integrator decides the slots/sorts mirror encoding).
- D1 (f05's period in the race string) — your side is already OBSERVED-correct.
- The `smp_items` collision / keying unification (`f03 §11.2`) — integrator.
- Deleting `smp_ah/keys.lua` (proposed shared change 1) — integrator.
- `ah_harness.lua:782` shim cleanup beyond verifying P0 did it — P0 owns B4.
- Any edit to `smp_orders`' stale `TODO(f03)` comments — f04 brief owns them.

## Definition of done

1. Every issue ID A1–A7 is either fixed or escalated, with the reason written
   into `spec/features/f03-auction.md §10` (A2-fallback, A5, A6-mirror).
2. Both dev-test suites exit 0 — paste command output into the PR/branch
   description.
3. In-mod `smp_ah/test.lua` updated and passing.
4. `git checkout -b agent/f03-auction-fixes` from `main`; commit message
   references `SPEC-CONFORMANCE-REPORT.md §4 f03`; push the **branch**, never
   `main`.
5. PR description carries the issue ID → evidence mapping (A1…A7 →
   `file:line` + commit), plus the A7 grep output.
6. `fixes/README.md` row `f03` annotated with what closed vs escalated.
