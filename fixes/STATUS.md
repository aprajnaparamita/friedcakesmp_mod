# fixes/ status — verified 2026-09-24

Verification pass over this directory and the repository. Every claim below was
checked against the working tree, the git graph, or an executed test — not
copied from the briefs. Written before `01-integrator-decisions.md` work started,
so the decision record has a baseline to refer to.

Branch at time of writing: `agent/integrator-decisions` (branched from
`agent/p0-engine-apis`, see "Branch reality" for why not from `main`).

---

## 1. Branch reality

- **`fixes/` is not on `main`.** `git ls-tree main fixes/` → empty. The whole
  brief pack exists only on `agent/p0-engine-apis` and `agent/ender-chest`.
- **`main` still does not boot.** Brief 00's own follow-up (README §"Row 00")
  found three sites its first pass missed; all three are still live on `main`:

  | Site | On `main` | On `agent/p0-engine-apis` |
  |---|---|---|
  | `friedcake/mods/smp_amethyst/init.lua:205` | `core.register_on_pickup` — load-time crash, pack aborts | `core.register_on_item_pickup` |
  | `friedcake/mods/smp_economy/init.lua:161` | `core.get_player_names()` — client-only, nil on a server | replaced (commented) |
  | `friedcake/mods/smp_shards/init.lua:196` | `core.get_player_names()` | replaced (commented) |
  | `friedcake/mods/smp_sell/items.lua:478` | `core.get_translated` | fixed on `p0` |
  | `friedcake/dev-tests/test_engine_apis.lua` (B4-3 guard) | **absent** | present |

- Unmerged branches: `agent/p0-engine-apis` (3 ahead: `3cb4e95` ender chest,
  `d462222` this `fixes/` pack, `bb8238f` P0 guard + the 3 missed sites) and
  `agent/f11-social` (2 ahead, dated 2026-09-22).
- Every `agent/f02…f15` branch is merged, but they are the **pre-audit
  implementation branches of 2026-09-22** — not fix work. **No feature fix
  branch exists yet**: none of the README's prescribed names
  (`agent/f01-economy-fixes`, `agent/integrator-decisions`,
  `agent/f16-legacy-decide`, …) existed before this pass.
- Working tree clean. **22/22 dev-test suites pass**
  (`luajit friedcake/dev-tests/test_*.lua`, all exit 0).

## 2. Per-brief status

| Brief | Status | Notes |
|---|---|---|
| `00-P0-blockers.md` | **✅ done on branch, NOT merged** | B1–B3 already on `main`; guard + 3 missed sites only on `agent/p0-engine-apis`. Criteria 1–5 verified locally (see §1). Criterion 6 (real-server boot smoke) **unverified** — no server run in this environment. |
| `01-integrator-decisions.md` | **❌ not started** (no rulings, no branch until now) | Critical path: blocks 11 briefs (see §4). |
| `f01-economy-core.md` (28 rows) | ❌ not started | No `agent/f01-economy-fixes` branch. Several rows already fixed on `main` — see §3. |
| `f02-sell.md` (4 rows) | ❌ not started | Rows are escalations (D2, D7, store-history seam) + re-verify-after-00. |
| `f03-auction.md` (7 rows) | ❌ not started | Verified open: A2 (`Match lowest` absent), A3 (`ah.sorts` hardcoded, `smp_ah/init.lua:65`). |
| `f04-orders.md` (8 rows) | ❌ not started | Verified open: O2 (`orders.sorts` hardcoded, `smp_orders/init.lua:48`). |
| `f06-shards.md` (10 rows) | ❌ not started | F06-1 **already fixed on `main`** (`for _, list in ipairs({"main","offhand"})` at `smp_amethyst/init.lua:179`). |
| `f07-spawners.md` (14 rows) | ❌ not started | **Both P1 defects already fixed on `main`**: F07-1 (`routing.lua:70-78` now sells first, decrements only on `true`) and F07-2 (`bool()` now `core.settings:get_bool(key, default)`, `init.lua:39-44`). Verified open: F07-3 (no `Inventory` label / `list[]` in `smp_spawners/formspecs.lua`). |
| `f08-teleport.md` | **⚠ file missing** | Indexed in README (8 gaps) but does not exist — broken link, 8 gaps unassigned. |
| `f09-homes.md` | **⚠ file missing** | Indexed in README (4 gaps, "feature never loads") but does not exist. Its headline blocker **is** already fixed by P0 B3 (`homes.lua` dofile'd at `smp_tp/init.lua:33`; `mod.conf` carries `smp_store` + optional `smp_ranks`). |
| `f10-combat.md` | **⚠ file missing** | Indexed in README (2 gaps) but does not exist. |
| `f11-social.md` (8 rows) | 🟡 **partially done on unmerged `agent/f11-social`** | 2 commits: `test_social.lua` T1–T10 + in-mod `test.lua` (closes F11-1 — the audit's "0 of 10 tests" counted `main` only), plus §7/§10/§11 spec rows (F11-8). F11-7 landed on `main` (`87c0eae`). **Still open even on that branch:** F11-3 (`follow()` has no block check), F11-4 (no `blocks_only` predicate in `graph.lua`), F11-5 (→ D10). |
| `f12-settings.md` (7 rows) | ❌ not started | Verified open: F12-1 (no `⚠` in `smp_settings/formspec.lua` renders). F12-4 waits on the f11 harness (exists on the f11 branch). |
| `f13-ranks.md` (3 rows) | ❌ not started | Contract tests + hand-offs to f04/f08 + D6 all pending. |
| `f14-stats.md` (7 rows) | ❌ not started | S1 blocker site **already fixed on `main`** (`smp_stats/playtime.lua:59` reads `register_globalstep`). Verified open: S4 (counters accept negative increments, `smp_stats/counters.lua:47-56`). |
| `f16-legacy.md` (4 rows) | ❌ blocked on D8 | Correctly refuses to start before the scope call. No branch. |

## 3. The briefs are partly stale (report §0 supersedes them)

`SPEC-CONFORMANCE-REPORT.md §0` (same-day second pass, commits `68b5bf5`,
`86c5918`, `87c0eae` on `main`) closed findings that several briefs still list
as open and top-priority. Verified in code on 2026-09-24:

| Brief row | Report §0 says | Verified state |
|---|---|---|
| B1–B3 (brief 00), B4-1/B4-2 harness fakes | FIXED | **fixed on both `main` and `p0`** — zero `register_on_globalstep`/`core.modpath` in `friedcake/mods/`, zero in `dev-tests/` except the guard |
| F07-1 spawner Sell-all item loss | P1-4 FIXED | **fixed** — `routing.lua:70-78` honours the sell return before decrementing |
| F07-2 `bool()` default-true keys | P1-5 FIXED | **fixed** — `get_bool(key, default)` |
| F06-1 amethyst join refresh | P1-7 FIXED | **fixed** — `for _, list in ipairs(...)` |
| E-14 `shards_for_playtime` dropped on sqlite | P1-6 FIXED | **fixed** — column + migration in `smp_store/backends/sqlite.lua:73,162-170,207-227` |
| E-16 ledger paging by global id | P1-6 FIXED | **fixed** — filter-then-page in `mod_storage.lua:147-160` |
| E-01 `/pay` ignores `smp_social.blocks` | P2-10 FIXED | **fixed** — `smp_economy/init.lua:207-209` |
| F11-7 raw strings | P2-12 FIXED | **fixed on `main`** (`87c0eae`) |
| S1 `smp_stats` wrong globalstep name | B1 #6 FIXED | **fixed** — `playtime.lua:59` |

Still genuinely open (spot-checked, not exhaustive): E-02 (no `register_on_joinplayer`
in `smp_economy`), E-04 (no `/pay` cooldown), **E-09 (`/smp test` — call at
`smp_economy/init.lua:473` vs `local function` at `:489`, no forward
declaration → nil call)**, E-20 (M2 shulker codec still a one-way hash,
`smp_items/init.lua:100-107`), F07-3, A2, A3, O2, S4, F12-1.

**Consequence:** an agent handed a brief verbatim will re-do finished work.
Each brief needs a reconciliation note against report §0 before dispatch.

## 4. Structural findings

1. **Zero escalations recorded.** No `spec/features/*.md` §10 entry references
   `fixes/` at all → per AGENTS.md process, not one feature brief has been
   picked up. Every ESCALATE row in every brief is still pending.
2. **14 gaps have no brief file.** README indexes `f08`, `f09`, `f10` (8 + 4 +
   2 gaps) but the files do not exist — either write them or strike the rows.
3. **Decision D1–D11 gate 11 of 13 remaining briefs:** f01 (D1, D7, D9),
   f02 (D2, D7), f03 (D7), f04 (D7), f06 (D7, D8), f07 (D5, D7), f11 (D10),
   f12 (D3, D7), f13 (D6), f14 (D4), f16 (D7, D8). Nothing else can be
   verified end-to-end until `01-integrator-decisions.md` is ruled.
4. **README row 00 says "✅ fixed — pack boots"**, but that is true only of the
   unmerged branch — `main` still crashes at load (see §1). The row should not
   be ✅ until `agent/p0-engine-apis` is merged.

## 5. Recommended order

1. Merge `agent/p0-engine-apis` → `main` (carries `fixes/`, the ender chest,
   the guard, and the three crash sites; without it `main` doesn't boot and no
   other agent can see the briefs).
2. Rule D1–D11 in `01-integrator-decisions.md` (branch
   `agent/integrator-decisions`) — gates 11 briefs.
3. Write or strike `f08`/`f09`/`f10` — 14 unassigned gaps with broken index
   links.
4. Merge `agent/f11-social` and finish F11-3/F11-4/F11-5 (also unblocks f12's
   T9).
5. Annotate briefs against report §0 (§3 above) before dispatching feature
   agents.
6. Remaining briefs in any order — independent after step 2.

## 6. Commands used

```sh
git branch -a --sort=-committerdate
git log --oneline main..agent/<branch>          # ahead/merged per branch
git ls-tree main fixes/                          # empty → fixes/ not on main
git grep -n 'register_on_pickup' main -- friedcake/mods/smp_amethyst/
git grep -n 'register_on_globalstep\|core\.modpath' main -- friedcake/
grep -rn 'fixes/' spec/features/                 # zero → no escalations filed
ls fixes/                                        # f08/f09/f10 absent
for t in friedcake/dev-tests/test_*.lua; do luajit "$t"; done   # 22/22 exit 0
```

## 7. Addendum — rulings written, execution delegated (2026-09-24, same session)

The audit above is the *baseline*; this records what happened next.

- **D1–D11 are ruled.** Dated rulings with chosen options and exact change
  sites live in `01-integrator-decisions.md` § *Rulings — 2026-09-24*.
  Outcomes: D1=A, D2=A, D3=A, D4=§7→`snapshot`, D5=normalise-to-renderer,
  D6=upsert_player, D7=A (mirror follows code), D8=**descoped permanently**
  (f16 never built — harder than the brief's Option B "deferred"), D9=A,
  D10=A, D11=A.
- **Requirements** written to `fixes/REQUIREMENTS.md` (per-decision change
  lists with file:line, cross-cutting rules, conflict matrix, open items).
- **Six standalone execution prompts** in `fixes/prompts/` (P1–P6), waves:
  1 ∥ 3 ∥ 4 → 2 → 5 ∥ 6; each branches from `agent/integrator-decisions`.
- **Brief annotations:** every feature brief's *Depends on* row now carries its
  ruling outcome (brief 01 criterion 5); README row 01 → ✅ with prompt links;
  README f16 row → cancelled; README f08/f09/f10 rows marked ⚠ *brief file
  missing* (the broken-link finding above is now visible in the index);
  `fixes/f16-legacy.md` carries a CANCELLED banner; `f06` F06-3 marked
  pre-applied.
- **Still open:** nothing in the rulings — OPEN-1 (the f02/f03 sell-history
  seam) was ruled as **D12** the same session (one generic
  `smp_store.api.append_history(kind, name, entry)`), executed by the sixth
  prompt `prompts/p6-store-history.md` (wave 3, parallel with P5). GAP-1
  (missing f08/f09/f10 briefs) and NOTE-1 (E-09) remain, unchanged from §5.
- **Unchanged from §5:** merge `agent/p0-engine-apis` first; author the
  f08/f09/f10 briefs; merge `agent/f11-social`.
