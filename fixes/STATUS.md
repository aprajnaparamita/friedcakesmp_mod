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

## 8. Wave 1 executed and merged (2026-09-24, same session)

- **P1** → `agent/rulings-spec-text` `5de444f` — D1–D6, 7 files, suite 22/22.
- **P3** → `agent/rulings-f16-descope` `c0f8ae8` — D8 spec side, 9 files, 22/22.
- **P4** → `agent/rulings-admin-apis` `2b95c66` — D9+D10; `smp_admin`
  26→226 lines, new `dev-tests/test_admin.lua` (70 assertions) + in-mod
  `test.lua`; suite 23/23; `bridges.lua:97-104` probe verified resolving.
- All three merged into `agent/integrator-decisions` (zero conflicts); suite
  green at **23 files**.
- **Escalations resolved by the integrator in this commit:** P3's five
  wording/status sites — `shared/00:18` LEGACY definition, `shared/01:45-46`
  + `:66` G4, `plan/open-questions.md` V-61 row (mirrors f06's closure),
  `f06:50` §4.1 pointer, `shared/05` §5.4 heading — all annotated per D8;
  P4's f01 flag-signature heads-up (`flag(kind, detail)`, 2 args vs f01:166's
  4-arg pseudocode) recorded on f01's *Depends on* row.
- **Ratified (P4, spec-silent):** server console (`caller == ""`) may run
  `/mute`/`/unmute`, mirroring the engine's console privilege bypass.
- **Not acted on:** `SPEC-CONFORMANCE-REPORT.md` (:226, :53, :224, :705, :899)
  still describes pre-ruling states — it is a point-in-time audit record;
  left historical on purpose.
- Push still blocked (SSH key passphrase) — every branch is local; push
  `agent/integrator-decisions` and the three P-branches once keys are loaded.

## 9. Waves 2–3 executed — all six prompts merged (2026-09-24, same session)

- **P2** → `agent/rulings-config-mirror` `17e040d` — D7: mirror reconciled
  (59 rows added, 20 renamed incl. `tp/rtp/rtpqueue/tpa/homes` → real
  `smp_tp.*` literals, 5 struck: `settings.categories` + 4 `legacy.*`),
  §7 tables reconciled in 12 features, new `test_config_mirror.lua`
  (three-set READ/DECLARED/MIRROR guard; both negative checks fire).
  DECLARED_ONLY drain (hand-offs): `ah.history` (f03 A6),
  `orders.slots.*` (f04 O3), `spawners.C.skeleton` (f07 F07-8/9).
- **P5** → `agent/rulings-integration-test` `617677d` — D11:
  `test_integration.lua` (1305 lines) with engine-cited topo order
  (`mods.cpp:43-48`, `mod_configuration.cpp:219-321`), strict 542-name
  core (0 misses), 23/23 seams OK, degraded pass OK, both R6 negative
  demos exit 1 with the right messages; seam-policy paragraph landed in
  `plan/acceptance-tests.md`.
- **P6** → `agent/rulings-store-history` `a17a8f9` — D12:
  `smp_store.api.append_history(kind, name, entry, cap?) -> id` with
  driver parity across mod_storage/sqlite/postgres (id = monotonic per
  `(kind, name)`, default cap 100 FIFO), 7 new `test_store` cases; f02:139
  + §11 amended, f03 new §6.3, f02 §10 V-94 annotated by the integrator.
- **Ratified (agent judgement calls):** P5's engine-wins deviations (real
  `settings` API list, no `Profiler` stub, documented reverse-alphabetical
  tie-break stand-in, literal keep-set rule); P6's E1 (f03 §6 never
  contained the `append_history` line the audit claimed — §6.3 addition is
  D12's intent), E2 (ledger lives in `init.lua` + backends, no
  `ledger.lua`), E5 (`test_store` path → worktree-aware `find_root()`).
- **Handed to feature briefs (recorded on each *Depends on* row):**
  - f01 — `smp_economy.give` called at four spec sites, defined nowhere.
  - **Boot-aborting `optional_depends` cycles** (engine treats present
    optional deps as ordering deps → `ServerError`): `smp_sell ↔ smp_orders`
    (f02/f04), `smp_orders → smp_shardshop → smp_amethyst → smp_orders`
    (f04/f06), `smp_stats ↔ smp_combat` (f14 + f10 — f10's brief is
    missing, GAP-1). P5's harness gate is hard-deps-only, so these are
    non-gating there but must be fixed in the owning mods' `mod.conf`.
- Suite after all six merges: **25/25 dev-tests green.** Push still blocked
  (SSH passphrase): `agent/integrator-decisions` + the six P-branches are
  all local. Wave-1 worktrees remain under
  `$TMPDIR/coconut-p1..p6` and can be removed with `git worktree remove`.

## 10. Wave 0 by the overseer (2026-09-24, same session)

- **`main` fast-forwarded to `agent/integrator-decisions`** — zero
  divergence, so a `--ff-only` merge. This closes §1 ("`fixes/` is not on
  `main`"; "main still does not boot") and §4 finding 4: the pack, the
  briefs, the rulings and the P1–P6 execution are now on `main`, and
  README row 00's ✅ is no longer branch-conditional. §1–§6 above stay as
  the **baseline** record; this section supersedes them where they conflict.
  (Push still blocked — `origin/main` lags until the SSH key is loaded.)
- **`agent/f11-social` merged into `agent/integrator-decisions`** (§9's
  recommended step 4). One conflict — `spec/features/f11-social.md` §7,
  both sides having edited the same rows (P2's mirror sweep vs the f11
  branch) — resolved **by code, per D7**: `info.help` falls back to the
  generated command list (never "not configured"), `info.rules` **and**
  `info.ranks` answer `This text is not configured` (the f11 side grouped
  `info.ranks` with the links — wrong, `info.lua:162-167` has no
  `link = true`), the other six answer `This link is not configured`.
  `shared/06:121` was split to match the same three groups (Status/Spec
  cells kept).
- **The f11 branch predated B1:** its `test_social.lua:424` stubbed
  `register_on_globalstep` — exactly the B4-1 class the guard exists to
  catch, and it made `smp_store`'s init fail. Renamed to
  `register_globalstep` (capture list unchanged).
- **Suite now 26/26** — `test_social` joins the gate.
- **STATUS §3 reconciliation applied to the briefs** (the integrator had
  annotated the *rulings* on the Depends rows; the *pre-fixed rows* were
  still open, so a verbatim agent would have re-done finished work):
  F07-1, F07-2, F06-1, S1, E-01 marked **ALREADY FIXED on `main`** (each
  re-verified in tree first); E-14, E-16 marked **RESOLVED** (no §10
  escalation to file); F11-1, F11-8 marked **done/merged**; F11-7 marked
  fixed (`87c0eae`); F12-4 marked **UNBLOCKED** (harness exists).
- **f11 open rows after the merge:** F11-3 (follow block check), F11-4
  (`blocks_only` predicate), F11-5 (D10 honesty cleanup) — that is the
  f11-finish agent's scope.
- **The `smp_stats ↔ smp_combat` boot-aborting cycle closed (pack-level,
  overseer):** `smp_stats/mod.conf` lost its redundant `smp_combat`
  `optional_depends` edge; **`smp_combat`'s `smp_stats` edge stays** — it
  is the order-critical one (`smp_stats/combat.lua:11-14`: stats'
  leaveplayer callback must run before `smp_combat.on_leave` untags the
  logger). One edge removed = cycle gone, documented callback order
  preserved. f14's Depends row annotated (verify, don't touch either
  `mod.conf`). Note: the drafted plan said to edit `smp_combat`'s conf —
  that would have deleted the order-critical edge, so the other side was
  cut instead. The remaining cycles (`sell↔orders`,
  `orders→shardshop→amethyst→orders`) stay with their owning briefs
  (f02/f04, f04/f06 — each owns its own `mod.conf`).
- **GAP-1 CLOSED (2026-09-24):** `fixes/f08-teleport.md` (13 rows — 8 audit
  gaps + 4 deviations + the F11-4 queue hand-off), `fixes/f09-homes.md`
  (4 rows), `fixes/f10-combat.md` (2 gaps + verify context) authored by the
  overseer from the audit's §4 sections, with the P0-B3, D7 and pack-level
  resolutions baked in as **verify-don't-redo** rows and each *Depends on*
  row carrying its ruling outcomes (brief 01 criterion 5). The 14
  unassigned gaps are assigned; `fixes/README.md` index rows no longer
  carry the ⚠ marker. f08's TP13 (queue block-only pairing) depends on the
  f11 branch's `blocks_only` — dispatch f08 **after** f11-finish merges.
- **Still open, unchanged:** NOTE-1 (E-09, f01's),
  `smp_economy.give` (f01's P5 finding), the two remaining
  `optional_depends` cycles (f02/f04 = `sell ↔ orders`; f04/f06 =
  `orders → shardshop → amethyst → orders`), push blocked (SSH
  passphrase).
