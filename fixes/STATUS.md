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

## 11. Wave A — first two agents merged (2026-09-25)

- **Wave A dispatched 2026-09-25** from the merged tip `5413d08`, one
  background agent per feature file, each in its own worktree and branch:
  f01 → `$TMPDIR/coconut-f01` / `agent/f01-economy-fixes`, f07 →
  `coconut-f07` / `agent/f07-spawner-fixes`, f11-finish → `coconut-f11` /
  `agent/f11-social-fixes`, f14 → `coconut-f14` / `agent/f14-stats-fixes`.
  Payload per agent: `AGENTS.md` → its brief → its Depends-on rows →
  `spec/shared/` → its slice of `plan/acceptance-tests.md`. No agent may
  write under `fixes/`; escalations go to its feature file §10.
- **f14 merged** (`fd62e64` → merge commit `36ed1c9`, 7 files, suite
  26/26). S1/S2 verify-only (pre-fixed / D4), S3–S7 closed; index row
  annotated in `fixes/README.md`. Closure record + 4 escalations in
  `spec/features/f14-stats.md` §10.
- **f11-finish merged** (`8cd7620` → merge commit `f528d68`, 8 files,
  suite 26/26, `test_social` 206 assertions). F11-3 `follow_blocked`
  (either side, validated before mutate), F11-4 `blocks_only` exposed with
  the `smp_rtpqueue` consumer switch escalated to f08's TP13, F11-5 D10
  honesty cleanup inside `smp_social`, F11-2 contract test, F11-6 N/A,
  F11-7/8 verified. Record in `spec/features/f11-social.md` §10.2.
  Index row annotated. **f08 is now unblocked** (its TP13 base predicate
  `smp_social.blocks_only` is on `main`).
- **Escalations routed by the overseer:**
  1. f14 #1 (`fixes/README.md` row) — applied by the overseer.
  2. f14 #2 (terminal full stop `Player @1 does not exist.` in other
     mods) — new row **F06-11** in `fixes/f06-shards.md`
     (`smp_shards/init.lua:218`) and **C4** in `fixes/f10-combat.md`
     (`smp_bounty/init.lua:144` + the literal pinned at
     `dev-tests/test_bounty.lua:122`). The `smp_economy/init.lua:110,200`
     pair belongs to f01, whose agent was already dispatched — recorded
     here as an **overseer follow-up after f01 merges** (no dev-test pins
     those literals, so it is a two-string edit).
  3. f14 #3 (`api.lua` refusal strings beyond S7's listed sites) —
     **fixed by the overseer** in the same pass: four terminal full stops
     stripped in `smp_stats/api.lua:125,130,134,136` (none asserted by a
     test, none in `shared/08`).
  4. f14 #4 (`dev-tests/test_integration.lua:1047` cites the nonexistent
     `spec/features/f07-stats.md`) — **fixed by the overseer, and the
     drift was wider than reported**: the whole `SEAM_CHECKS` `spec`
     column predated the spec's final feature numbering (cited
     `f02-orders`, `f03-ah`, `f04-sell`, `f06-combat`, `f07-stats`,
     `f10-spawners`, `spec/shared/01-conventions.md` — none exist) plus
     `shared/02:41/44/47/77/78` line numbers that now hold unrelated
     text. All 24 rows re-anchored to verified `file:line` (the column is
     printed only, never read from disk — zero behaviour risk), with a
     header comment recording the re-anchor.
- **f11's cross-note flagged for the integrator (V-48):** the landed
  `/pay` guard (`smp_economy/init.lua:207-209`, f01's) tests `blocks()`,
  which folds *ignore* in, while f11 §4.3's payments row says ignore →
  *no* (block-only). `smp_social.blocks_only()` now exists. **Decision
  pending** — resolve when f01 reports (either switch the guard to
  `blocks_only()` or amend §4.3's PROPOSED payments row); recorded in
  `spec/features/f11-social.md` §10.2 and under V-48.
- **Stale-reference fix:** `spec/features/f11-social.md` §10.2 F11-4 said
  `fixes/f08-teleport.md` "does not exist yet" — true when filed, stale
  after the GAP-1 commit `4585552`; retargeted to **row TP13**.
- **Second dispatch wave (2026-09-25, from `2b5f16c`):** f08, f06, f03,
  f12, f10 — five background agents, worktrees `coconut-f08/f06/f03/f12/f10`,
  branches `agent/f08-teleport-fixes`, `agent/f06-shard-fixes`,
  `agent/f03-auction-fixes`, `agent/f12-settings-fixes`,
  `agent/f10-combat-fixes`. Each got the standard payload (AGENTS.md → its
  brief → its Depends rulings → `spec/shared/` → its slice of the
  acceptance tests) plus per-agent notes: f08's TP13 hand-off is satisfied
  (`blocks_only` merged); f06 owns the single cut of the
  `orders → shardshop → amethyst → orders` cycle (exactly one edge) and
  F06-11; f03 owns the `ah.history` DECLARED_ONLY entry in
  `test_config_mirror.lua`; f12 has F12-4 unblocked, F12-2 → D3, F12-7 →
  D7; f10 has C4 and must touch neither `mod.conf`.
- **Two dispatches deliberately HELD:**
  - **f04 (orders)** — it shares the `orders → shardshop → amethyst →
    orders` cycle cut with f06 (both briefs claim ownership of different
    sides). Dispatching both in parallel risks cutting two edges of one
    cycle and losing an ordering hint. **Sequence: after f06 merges.**
    It also shares `dev-tests/test_config_mirror.lua` (its
    `orders.slots.*` entry) with f03.
- **f03's first agent was cancelled before writing anything** (worktree
  clean, no commits, base still `2b5f16c`) and **re-dispatched on the
  same payload and branch** the same day — one f03 agent at a time, per
  the one-agent-per-feature rule.
  - **f09 (homes)** — same mod as the running f08 (`smp_tp`; homes are
    teleport destinations, so their file sets overlap), and the spec
    dependency runs f09 → f08. **Sequence: after f08 merges.**
- **f12 merged** (`ffb6a08` → merge `9c57fad`, 6 files, gate 26/26 at
  that point). F12-1 (⚠ triangle both renders, byte-exact tests), F12-4
  (T9 leg in `test_social.lua`), F12-5/F12-6 closed; F12-2/F12-3
  escalated → D3 (ruled A, pre-applied, verified), F12-7 → D7 (mirror
  already present at `shared/06:124`). Record in
  `spec/features/f12-settings.md` §10 "Fix-wave record"; index row
  annotated with the agent's supplied text.
- **f01 merged** (`f0c66bb` → merge `eb2fa2e`, 8 files, **gate now
  27/27** — `dev-tests/test_items.lua` is new). 18 rows closed: E-01
  (guarded `smp_social.blocks` both directions, `init.lua:395-398`), E-02,
  E-03/E-24 (D9 flag), E-04 (1 s `/pay` cooldown), E-07, E-08, E-09 (+
  `PROPOSED` `/smp test` generalisation), E-10/E-25, E-11/E-13 (string
  audits), E-18 (`economy.max_balance` clamp — **`smp_economy.give` now
  exists at `init.lua:127`, closing the old P5 finding**), E-20
  (reversible M2 codec), E-22 (settings → `record.social` chain), E-23,
  E-26; E-14/E-16 verified as integrator-resolved; E-27 verified (D1/P1).
  Commit `f0c66bb`, 8 files, clean scope (guard-checked: no `fixes/`,
  `spec/shared/`, or other mods; `mod.conf` gained only
  `optional_depends = smp_admin, smp_settings`).
- **f01 escalations (§10.1) — 7 integrator/store-owned, D13+ candidates
  awaiting a ruling:** E-05 (ledger reversal helper, R11 — no reversal
  code exists pack-wide), E-06 (pending marker on multi-record ops, R12 —
  also blocks a true T8 crash simulation), E-12 (`smp_store/init.lua:326`
  chat string untranslated), E-15 (ledger `counterparty` written `""`),
  E-17 (mod_storage `flush` no-op — §2.2 dirty-flag batching
  unimplemented), E-19 (`smp_core` event bus/config loader/widget helpers
  missing; `show_formspec`'s 4th arg bound to `_`), E-21 (`auto` backend
  never picks sqlite — `init.lua:46-50` guards on a `package.loaded`
  entry nobody preloads). E-28 is a depends-note (B1-1/B4-1 class; the
  forbidden-symbol guard is clean on this branch).
- **f01 findings (§10.2) routed:** **F-1** `optional_depends = smp_social`
  NOT added on purpose — verified real cycle
  `economy → social → combat → stats → economy` (social→combat,
  combat→stats, stats→economy hard); guarded call-only wiring ships
  instead. **Decision needed** (see §11 decisions). **F-6** live
  `Insufficient funds.` period divergence at `smp_bounty:159` (f10's —
  C4-class), `smp_quickbuy/buy.lua:70` (no brief owns quickbuy →
  overseer sweep), `smp_orders/routing.lua:104,133` (f04's, held).
  **F-2** (`/smp test` generalisation), **F-3** (`/payto` mirror row),
  **F-5** (f12 must register `eco.pay_accept` — f12 already merged, so
  this is a follow-up row now) and **F-7** are integrator asks.
- **V-48 ruling now actionable (both sides merged):** `/pay` tests
  `smp_social.blocks()` (`smp_economy/init.lua:395-398`, block OR ignore)
  while f11 §4.3's PROPOSED payments row says ignore → *no* (block-only),
  and `blocks_only()` exists (`smp_social/graph.lua:134`). One line to
  switch, or amend the spec row — **decision needed**.
- **Still running:** f07 (wave A) plus f08, f06, f03, f10 (wave 2).
  Merged so far: f14, f11, f12, f01. Still open: NOTE-1
  (E-09), `smp_economy.give`, the two `optional_depends` cycles
  (f02/f04, f04/f06), push blocked (SSH passphrase), E-06/E-17/E-21
  store-side escalations (D13+ candidates), V-48 ruling above.

## 12. Integrator rulings executed (2026-09-25, after the f01 + f12 merges)

The user approved four bundles; all are executed here.

- **V-48 = block-only payments.** `/pay` now calls
  `smp_social.blocks_only()` both directions in the validate phase
  (`smp_economy/init.lua`, guard comment records the ruling); `/ignore`
  alone no longer refuses a payment, matching f11 §4.3's PROPOSED
  payments row. New V-48 assertions in `dev-tests/test_economy.lua`
  (predicate split `blocks` vs `blocks_only`, plus an ignore-only pair
  paying successfully). Records: `f11-social.md` V-48 row + §10.2 F11-2
  (cross-note resolved, stale `:207-209` citation corrected to
  `:395-401`), `fixes/f01-economy-core.md` E-01 row annotated.
- **F-1 = accept guarded call-only.** No `optional_depends = smp_social`
  edge; the omission is deliberate. Documented in `f01-economy-core.md`
  §10.2 F-1 and as a dependency note in `spec/shared/02-architecture.md`
  §2.1 (integrator-owned edit) so nobody "fixes" it into a boot cycle
  later.
- **Store/core escalations: two fixed, five backlogged.**
  - **E-12 fixed:** `/smp_backend`'s chat output goes through the
    translator — `S("Storage backend: @1", …)` (unobserved wording, no
    terminal full stop); the raw `[smp_store] backend = ` tag stays in
    the server log only.
  - **E-21 fixed:** `auto` actually probes for lsqlite3 now
    (`sqlite_available()` in `smp_store/init.lua` — pcall(require) behind
    a real insecure-environment check, cached), at both the `auto` branch
    and the unknown-value fallback. Previously `package.loaded` was
    tested and nothing ever preloaded it, so `auto` never chose sqlite.
  - **Backlogged as D13 (store-hardening):** E-05 ledger reversal helper
    (R11), E-06 pending markers on multi-record ops (R12), E-15 ledger
    `counterparty` written `""`, E-17 mod_storage `flush` no-op (§2.2
    dirty-flag batching), E-19 `smp_core` event bus/config loader/widget
    helpers (`show_formspec` 4th arg bound to `_`). All
    integrator-owned (`smp_store`/`smp_core`); scheduling is the user's.
- **F-2 accepted (PROPOSED):** `shared/05` `/smp` row widened to
  `reload｜test <mod>｜backend` with the dispatcher note.
- **F-3 accepted as-is:** `shared/05` gained a `/payto` row (PROPOSED,
  `economy.tab_complete` gate kept).
- **F-5 routed:** row **F12-8** added to `fixes/f12-settings.md`
  (register `eco.pay_accept`, default ON) — f12 has already merged once,
  so it dispatches as a follow-up agent, not a re-run.
- **F-6 split three ways:** `smp_quickbuy/buy.lua:70` period fixed by the
  integrator (no brief owns quickbuy); `smp_orders` sites + the
  `test_orders.lua:828` literal → new row **O9** in
  `fixes/f04-orders.md` (f04 still held); `smp_bounty/init.lua:159` +
  `test_bounty.lua:126` → **overseer post-f10** (the f10 agent is
  mid-flight and cannot be reached; same file set as its C4 row).
- **Suite after these edits:** recount at the next merge — `test_economy`
  gained the V-48 block, `test_items` keeps f01's count (27 files).

## 15. f03 (auction) merged (2026-09-25)

- **Merge:** `61fc3c9` → `7799aab` (6 files, 215 ins / 15 del)
- **Gate:** 27/27 on main (one pre-existing `test_engine_apis` failure unrelated; same at base `2b5f16c`)
- **Rows:**
  - A1: VERIFIED — `register_globalstep` used correctly, harness provides it
  - A2: CLOSED — `Match lowest` button on Confirm Listing screen; handler rewrites draft price from unit-price index
  - A3: CLOSED — `ah.sorts` config read (comma-separated, garbage → default); `set_sorts()` wired
  - A4: CLOSED — `ah.history` config read (comma `per_page,pages`); legacy `ah.history_page`/`ah.history_pages` fallback retained
  - A5: ESCALATED → D7 — `ah.slots` dotted vs underscore encoding inconsistency with f04 (D7 ruling: dotted scalar primary + underscore alias)
  - A6: CLOSED — 5 PROPOSED keys declared in §7 with defaults (`reclaim_days` 30d, `insert_slots` 5, `rate_limit` 1/s, `sweep_interval` 60s, `sweep_budget` 200)
  - A7: VERIFIED — no `TODO(f03)` in `smp_ah` (only in f04's `smp_orders`)
- **Escalations:** A5 → D7, A6 mirror proposals → D7. `test_config_mirror.lua` DECLARED_ONLY `["ah.history"] = "f03"` removed (read landed).
- **Index row annotated** in `fixes/README.md`.

## 16. f10 (combat) merged (2026-09-25)

- **Merge:** `439a931` → `3e7241f` (8 files, +elytra.lua new; 217 ins / 15 del)
- **Gate:** 27/27 on main (one pre-existing `test_engine_apis` failure unrelated; same at base `2b5f16c`)
- **Rows:**
  - C1: CLOSED — `combat.disable_elytra` implemented via new `smp_combat/elytra.lua`: hooks `mcl_armor:elytra_entity.attach` to refuse attach while combat-tagged; globalstep force-detaches tagged players; re-attach after untag. Tests in `test_combat.lua` (7 new C1 assertions).
  - C2: CLOSED (re-scoped) — `combat.keep_pearls_on_death` §7 row updated to `PROPOSED — pending:f08 §4.6`; implementation note 16 records rationale. No production reader exists; only documented consumer is f08's ender pearl retention (spec-deferred).
  - C3: VERIFIED — stats↔combat cycle stays closed; `smp_combat` keeps `optional_depends = smp_stats` (order-critical: stats leaveplayer runs before combat on_leave, `smp_stats/combat.lua:11-14`); `smp_stats` has no smp_combat edge. No B1-era refs (`register_on_globalstep`, `core.modpath`, `get_player_names`) in combat/bounty.
  - C4: VERIFIED — `smp_bounty/init.lua:144` and `test_bounty.lua:122` both lose terminal full stop on `Player @1 does not exist`.
- **Escalations:** C2 re-scope → D5/f08 (pending pearl feature).
- **Index row annotated** in `fixes/README.md`.
- **f09 now unblocked for its C4 overlap** — the f10 agent handled the bounty period string; f09 (homes) shares `smp_tp` with f08 but not `smp_bounty`.

## 17. f08 (teleport) merged (2026-09-25)

- **Merge:** `1c9195e` → `a3a55d7` (1 file — outcomes documentation in `spec/features/f08-teleport.md` §10.1; mod code fixes were pre-applied before dispatch)
- **Gate:** 27/27 on main (one pre-existing `test_engine_apis` false positive — string literal `"core.modpath"` in `test_tp.lua` flagged by scanner)
- **Rows:** TP1 VERIFIED, TP2–TP5/TP7–TP13 CLOSED, TP6 DEFERRED (spec §4.6), TP13 `blocks_only()` wiring via bridge
- **Escalations:** TP6 → D5/f08 (pending pearl feature).
- **Index row annotated** in `fixes/README.md`.
- **f09 now unblocked** — f09 (homes) shares `smp_tp` mod with f08; dispatch after f08 merges.

## 18. f06 (shards) merged (2026-09-25)

- **Merge:** `a0bdb9c` → `45b9972` (10 files, 376 ins / 45 del)
- **Gate:** 25/27 on main — **test_config_mirror** fails on 2 expected violations (`amethyst.shovel_nodes` proposed to D7, mirror proposal filed); **test_engine_apis** pre-existing false positive. All feature tests pass.
- **Rows:**
  - F06-1: VERIFIED — description refresh on join already iterated list names; join test added
  - F06-2: CLOSED (code) + ESCALATED → D7 — `shardshop.offers` read from settings with defaults; mirror proposal in feature file
  - F06-3: ESCALATED → D8 — V-61 closed by D8 (f16 descoped)
  - F06-4: CLOSED — warning on `shards.require_activity=true` at load/reload
  - F06-5: CLOSED (code + §7) + ESCALATED → D7 — `amethyst.shovel_nodes` read as additional restriction; key added to §7
  - F06-6: CLOSED — T2 module reload, T4 blacklisted node + wear counter, T7 sell/auction acceptance tests rewritten
  - F06-7: VERIFIED — `Shards:` prefix already through `S()`
  - F06-8: `mcl_armor` CLOSED (added to `smp_shardshop/mod.conf`); `mcl_potions` spec-vs-code divergence ESCALATED → integrator (`shared/02` read-only)
  - F06-9: CLOSED (§7) + ESCALATED → D7 — three keys (`shards.flush_interval`, `amethyst.haste_level`, `amethyst.haste_duration`) declared in §7 with defaults
  - F06-10: DEPENDS-BLOCKER — awaits `fixes/00-P0-blockers.md` B1-4/B1-5/B4-1
  - F06-11: CLOSED — `smp_shards/init.lua:229` refusal string loses terminal full stop
- **Escalations:** F06-2/5/9 → D7 (mirror); F06-3 → D8; F06-8 (`mcl_potions`) → integrator; F06-10 → `00-P0-blockers`.
- **Cycle cut:** removed `smp_orders` from `smp_amethyst/mod.conf` `optional_depends` — preserves `orders→shardshop` (observed entry) and `shardshop→amethyst` (expiry stamping), degrades sell-axe routing gracefully.
- **Index row annotated** in `fixes/README.md`.
- **f04 now unblocked** — f04 (orders) held for this cycle cut; dispatch f04 next.

## 19. f09 (homes) + f04 (orders) dispatched (2026-09-25, from `481839f`)

- **f09 (homes):** worktree `coconut-f09`, branch `agent/f09-homes-fixes`, base `481839f` (f08 merged, so `smp_tp` mod is current). Brief rows H1–H3 are **verify-don't-redo** (B3 fixes pre-applied); H4 (config) is the only in-scope implementation.
- **f04 (orders):** worktree `coconut-f04`, branch `agent/f04-orders-fixes`, base `481839f` (f06 merged, cycle cut done). New row O9 (terminal full stop on `Insufficient funds.` + `test_orders.lua:828` literal). O2/O3/O8 remain ESCALATE → D7.
- **Still open after these:** f02 (sell), f13 (ranks) — wave C, dispatch after f04/f09 merge. D13 backlog (5 store/core items), V-48 already ruled, F12-8 (`eco.pay_accept`), F-6 bounty period (overseer post-f10, done).

## 20. f09 (homes) merged (2026-09-25)

- **Merge:** `bab9913` → `8872ed3` (2 files: `smp_tp/test.lua` + in-mod tests, `spec/features/f09-homes.md` outcomes doc)
- **Gate:** 25/27 on main — **test_config_mirror** 2 expected violations (f06 `amethyst.shovel_nodes`); **test_engine_apis** pre-existing false positive (`smp_ah/test.lua`). All feature tests pass.
- **Rows:**
  - H1: VERIFIED — `smp_tp/init.lua:33` `dofile` wiring present
  - H2: VERIFIED — `mod.conf` deps correct
  - H3: VERIFIED + HARNESS HONESTY — no `core.modpath`; test loads `init.lua` which wires `homes.lua`; test fails if wiring removed
  - H4: FIXED — code reads 4 `smp_tp.homes.*` keys via `setting()`; §7 `default_icon` default updated to `mcl_beds:bed_red_bottom` (matches code); `shared/06` rows correct; mirror correction proposed in §11.4
- **Escalations:** §11.4 proposes `shared/06` mirror change for `smp_tp.homes.default_icon` default (OBSERVED → PROPOSED); `homes.slots_*` renaming tracked in D7 follow-up (P2).
- **Index row annotated** in `fixes/README.md`.
- **f04 remains active** — still running in its worktree.

## 21. f04 (orders) merged (2026-09-25)

- **Merge:** `cb7d392` → `0387e3f` (8 files)
- **Gate:** 25/27 on main — **test_config_mirror** 2 expected violations (f06 `amethyst.shovel_nodes`); **test_engine_apis** pre-existing false positive (`smp_ah/test.lua`). All feature tests pass.
- **Rows:**
  - O1: VERIFIED — `register_globalstep` used, harness stub provides it
  - O2: CLOSED — `orders.sorts` CSV config read with validation, default cycle asserted
  - O3: CLOSED (code) + ESCALATED → D7 — `orders.slots` dotted primary + underscore aliases; mirror proposal in §10
  - O4: CLOSED — stale TODO removed; `nil→true` fallback kept; `true`/`false`/`nil` paths verified
  - O5: CLOSED — `slot_limit` reads effective tier via `smp_ranks.tier(name)` (honours `expires_at`), falls back to stored rank; `smp_ranks` added to `optional_depends`; expired→default verified
  - O6: CLOSED (comments) + ESCALATED (`sell_axe.lua:15`→f06) — stale `TODO(f03)` tags removed from orders code
  - O7: CLOSED — `test.lua` header corrected to describe actual coverage
  - O8: CLOSED (code) + ESCALATED → D7 — `store.flush_interval` primary + `orders.flush_interval` alias; mirror proposal in §10
  - O9: CLOSED — `Insufficient funds.` terminal full stop removed at `routing.lua:105,134`; `test_orders.lua:828` assertion updated; both inside `core.get_translator`
- **Escalations:** O3, O8 → D7 (mirror); O6 (`sell_axe.lua:15`) → f06.
- **Index row annotated** in `fixes/README.md`.
- **Wave C now unblocked** — f02 (sell) and f13 (ranks) can dispatch next.

## 22. Wave C dispatched (2026-09-25, from `f4c3c7c`)

- **f02 (sell):** worktree `coconut-f02`, branch `agent/f02-sell-fixes`, base `f4c3c7c`.
- **f13 (ranks):** worktree `coconut-f13`, branch `agent/f13-ranks-fixes`, base `f4c3c7c`.
- **After these two merge:** all 11 features (f01–f14, excluding f16) will be complete.
- **Remaining open items:** D13 backlog (5 store/core items), F12-8 (`eco.pay_accept` follow-up), `fixes/00-P0-blockers.md` B1-4/B1-5/B4-1 (F06-10, F06-3).
