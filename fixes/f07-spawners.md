# Fix brief — f07 Virtual spawners

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f07-spawners.md` |
| Target mod(s) | `smp_spawners` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f07 |
| Verdict at audit | PARTIAL (14 gaps) · 48/63 OK · T1–T10 green (T9 stubbed) |
| Branch | `agent/f07-spawner-fixes` |
| Depends on | `00-P0-blockers.md` B4-1 (harness shim `test_spawners.lua:296` — note only); `01-integrator-decisions.md` **D5** (spec-internal wording splits — documentation only), **D7** (config mirror rows) |

Gap-count reconciliation: §4's exception table lists 13 rows; the report's
count of 14 also covers the §3.4 spec-internal wording splits, which are **D5**
(integrator) and not code work. Both are itemised below.

---

## Mission

The production model itself (curve, defaults, loot/XP tables) is implemented
exactly and well tested — the gaps are around it, and two are P1: **Sell all
loses items on refusal** (storage is decremented and written *before*
`smp_sell.sell` is called, whose return value is then ignored — a `false`
means the player's stored output vanishes, and the code comment cites the very
rule it breaks), and the **`bool()` helper bug** makes four default-true §7
keys impossible to turn off — including `spawners.enable_creeper`, which V-04
designates as the integrator's escape hatch. "Fixed" means: no item can ever
leave storage without a successful sale, every §7 key actually does what it
says, the four MISSING behaviours (menu inventory, piston immunity, hopper
extraction, natural conversion) exist or are formally struck, lazy accrual
behaves per §4.5 — and every currently-verbatim menu string, curve anchor and
revalidation rule survives untouched. Consequence of failure: silent item loss
in the pack's main economic asset, and operators who believe they disabled
creeper spawners did not.

## Read this first (in order)

1. `AGENTS.md` — hard rules 1–8 (esp. 8: no yields between validate and
   mutate — this brief's top defect violates exactly that).
2. `spec/features/f07-spawners.md` — end to end: §3 (25–40), §4.5 (106–118),
   §4.6 (120–150, esp. 4.6.4/4.6.7/4.6.8/4.6.9), §6 (181–211), §7 (213–230),
   §9 (243–256), §10 V-01/V-04/V-63 (258–268), `## Proposed shared changes`
   (270–296).
3. `spec/shared/02-architecture.md` (§2.3 — validate-then-mutate, no yields),
   `04-ui-kit.md` (**line 22**: container menus show the player inventory under
   an `Inventory` label), `05-command-reference.md`, `06-config-reference.md`
   (line 37 `spawners.C.skeleton`, line 49 `spawners.acquisition`), `08-ui-strings.md`
   (READ ONLY).
4. `spec/plan/acceptance-tests.md` — f07 row (T1–T10) is the merge gate.
5. `SPEC-CONFORMANCE-REPORT.md` §4 — f07 (lines 409–453), §3.4 (line 191,
   D5 wording splits), §3.3 (weak tests), §5 (in-mod assertions wouldn't catch
   the `bool()` bug).
6. Target source `friedcake/mods/smp_spawners/` (`init`, `node`, `routing`,
   `formspecs`, `interaction`, `performance`, `accrue`, `types`, `item`) +
   `friedcake/dev-tests/test_spawners.lua` + `friedcake/mods/smp_spawners/test.lua`.
7. Engine source-of-truth for the MISSING mechanics (per AGENTS): Mineclonia
   `~/dev/mineclonia-git` — piston gating is the `unmovable_by_piston` group,
   checked at `mods/ITEMS/REDSTONE/mcl_pistons/api.lua:56`
   (`core.get_item_group(nn.name, "unmovable_by_piston") == 1` → abort);
   hopper extraction mechanics live in `mods/ITEMS/mcl_hoppers`. Re-verify
   both clones before you rely on a line reference.
8. The f02 contract you must honour: `spec/features/f02-sell.md` §6 and
   `friedcake/mods/smp_sell/init.lua:180-186` (READ ONLY — you may not edit
   `smp_sell`).

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| F07-1 | f07 §4.6.4 + shared §2.3 | **P1 defect — Sell all loses items on refusal.** Storage is decremented and `write_state`d **before** `smp_sell.sell` is called, then the return value is ignored. f02's contract says the caller removes items only on `true` (`smp_sell/init.lua:180-186`); on `false` — balance cap (`sell.lua:150`), empty plan / partial (`smp_sell/init.lua:195-203`) — the removed items are neither restored nor returned. The comment at `routing.lua:59-60` cites shared §2.3 while the code does the opposite (decrement first = mutate before validate) | `friedcake/mods/smp_spawners/routing.lua:59-74` (comment 59–60, decrement 61–63, `write_state` 64, `smp_sell.sell(player, stacks)` at 74, `return true` at 76 regardless); contract `smp_sell/init.lua:180-186`; refusal paths `sell.lua:150`, `smp_sell/init.lua:195-203` | Restructure to **validate-then-mutate honouring the return**: build the stacks, call `smp_sell.sell`, and only on `true` decrement storage + `write_state` (keep the no-yield window tight per §2.3 — no yields between the successful sell and the state write; if the engine forces sequencing, restore-on-false must be exact). On `false`: storage untouched (or restored), player gets the refusal message, `return false`. Fix the misleading comment. Add the conservation test (see F07-13) | **IN-SCOPE (P1, top priority)** |
| F07-2 | f07 §7 (`require_silk_touch`, `blast_immune`, `enable_creeper`, `acquisition.admin`) | **P1 bug — `bool()` makes default-true keys impossible to set false:** `settings:get_bool(key) or default` returns `default` whenever the stored value is `false`, so `= false` is indistinguishable from unset. `spawners.enable_creeper` is V-04's designated escape hatch and can never fire | `friedcake/mods/smp_spawners/init.lua:39-41` (`local function bool(key, default) return core.settings:get_bool(key) or default end`); affected keys at `init.lua:63` (`require_silk_touch`), `:67` (`blast_immune`), `:72` (`enable_creeper`), `:78` (`acquisition.admin`); report §5 notes in-mod config assertions wouldn't catch it | Use `core.settings:get_bool(key, default)` (or an explicit nil-check equivalent) so a stored `false` wins. Re-verify all four default-true keys **and** `open_requires_access` (`init.lua:66`, default false) behave correctly for unset/true/false each | **IN-SCOPE (P1)** |
| F07-3 | f07 §3 (line 36 `Inventory`) + `shared/04:22` | `Inventory` label + player inventory **MISSING** under the menu — grep for `list[`/`Inventory` in `smp_spawners` → 0 matches; the mod's own comment claims the layout | `friedcake/mods/smp_spawners/formspecs.lua:4` (comment: "a virtual storage grid over the player inventory"); absence verified by grep; requirement `spec/shared/04-ui-kit.md:22` | Add the `Inventory` label and the `list[]` player-inventory elements to the spawner menu, per the shared container grammar (chest geometry like the other menus); keep the virtual 45-slot storage grid separate from the real player list[]s (read-only render; clicks stay take-requests) | **IN-SCOPE** |
| F07-4 | f07 §4.6.7 ("cannot be pushed") | Piston push-immunity **MISSING** — groups are only `cracky`/`oddly_breakable_by_hand` | `friedcake/mods/smp_spawners/node.lua:139` (`groups = { cracky = 3, oddly_breakable_by_hand = 1 }`) | Add `unmovable_by_piston = 1` to the node groups — verified mechanism: Mineclonia aborts the push when `core.get_item_group(name, "unmovable_by_piston") == 1` (`~/dev/mineclonia-git/mods/ITEMS/REDSTONE/mcl_pistons/api.lua:56`). Re-verify against the local clone first (AGENTS: do not trust stale references). If a piston path genuinely cannot be gated this way, record why in §10 instead of leaving it silently missing | **IN-SCOPE** |
| F07-5 | f07 §4.6.8 (hoppers, "optional extraction … off by default") | Hopper extraction **MISSING** — the config key is read and a getter exists, but nothing in the engine path ever calls it | key: `init.lua:70` (`hopper_extraction`); getter only: `performance.lua:44-48` (`hopper_enabled`, with the comment admitting "no hopper hook … yet") | Either implement the extraction hook (study `~/dev/mineclonia-git/mods/ITEMS/mcl_hoppers` for how hoppers pull from node inventories; virtual counts have no real inventory, so this likely needs a pull adapter honouring `hopper_enabled` and §4.4 capacity) **or** strike the key — but `spawners.hopper_extraction` is itself beyond-spec (already proposed at `f07:281`), so striking = remove from your feature file's proposal and note in §10. Pick one and say which in §10 | **IN-SCOPE** |
| F07-6 | f07 §4.6.9 / §7 (`spawners.convert_natural`, default false) | Dead key — read into config, referenced nowhere else; no conversion code exists | `friedcake/mods/smp_spawners/init.lua:68`; grep of the mod finds no other use (only `test.lua:147` asserting the default) | Either implement: when true, a Silk Touch dig of a vanilla dungeon spawner (`mcl_mobspawners:spawner`) converts it to `smp_spawners:spawner` with the right type per §4.6.9 `[C3]` — honouring `spawners.acquisition.natural`-style gating and `require_silk_touch` — **or** strike the key from §7 (your feature file) and record it in §10 as not adopted (like §4.6.10's isolation bonus). Pick one, state it in §10 | **IN-SCOPE** |
| F07-7 | f07 §4.5 ("State updates lazily: **every interaction converts elapsed time**") | Lazy accrual DIVERGENT — `accrue()` runs only from the node timer; menu open, take, Collect XP and Sell all read state only, so displayed/withdrawn output can lag one 60 s tick | `friedcake/mods/smp_spawners/node.lua:150-151` (sole call site: `on_timer` → `accrue` + reschedule); grep confirms no caller in `formspecs.lua`/`interaction.lua`/`routing.lua` (only the dofile at `init.lua:109`) | Call `smp_spawners.accrue(pos)` (or an elapsed-time conversion wrapper) at the start of **every interaction**: menu open, item take, `Take all`, Collect XP, Sell all, and the stacking/dig paths that read storage — then re-read state so the UI and payouts always include elapsed time, per §4.5. The 60 s node timer stays as the background driver | **IN-SCOPE** |
| F07-8 | f07 §7 (`spawners.C.skeleton`) + `shared/06:37` | Key-shape DIVERGENT: code reads one compound `spawners.C` string of `id=val` pairs; the documented/mirrored name is per-type `spawners.C.<type>` and has no effect | compound parse: `friedcake/mods/smp_spawners/init.lua:90-99` (`core.settings:get("spawners.C")` + gmatch); documented name: `spec/shared/06-config-reference.md:37`, `f07:218`, override path named in V-02 (`f07:263`) | Code-side only: read the **documented** names (`spawners.C.skeleton`, `spawners.C.zombie`, … — dotted keys or however the engine exposes nested settings, plus keep the old compound spelling as a back-compat fallback if you like). Defaults per `types.lua` unchanged (skeleton 1505.35 LIVE, others 250 PROPOSED). **Propose nothing to the mirror yourself** — D7 owns `shared/06` | **IN-SCOPE** |
| F07-9 | f07 §7 (`spawners.acquisition`) + `shared/06:49` | Key-shape DIVERGENT: code reads flat `spawners.acquisition.<src>` keys; the documented/mirrored key is a single table `{shard_shop, crates, natural, admin}` | flat reads: `init.lua:74-79`; documented shape: `spec/shared/06-config-reference.md:49`, `f07:230` | Code-side: read the documented single table key (parse `spawners.acquisition` as a table/spec-form value), keeping the flat keys as back-compat fallback so existing configs keep working. Defaults unchanged. Mirror untouched — D7 | **IN-SCOPE** |
| F07-10 | f07 §7 (`spawners.stack_mode`, default `all`, LIVE [S24]) | Key read but behaviour hard-coded to whole-stack; any other value is silently ignored | `friedcake/mods/smp_spawners/init.lua:53` (`stack_mode = str(...)`); stacking logic `interaction.lua:63-80` (comment "LIVE [S24] stack_mode = all"; whole held stack added, no branch on the config value) | Make the key work: at minimum honour `"all"` (current behaviour) vs a defined alternative (e.g. `"one"` = one spawner per click) and warn at load on unknown values; **or** narrow §7's row to `"all"`-only in your feature file if you can argue no other mode is specifiable. Default behaviour must remain exactly today's whole-stack merge | **IN-SCOPE** |
| F07-11 | f07 §7 (`spawners.blast_immune`, default true) + §4.6.7 | Key read but inert — `on_blast` is unconditionally a no-op, so the toggle does nothing (default behaviour matches spec; the off-state is unreachable) | read: `init.lua:67`; unconditional no-op: `node.lua:143-146` (`on_blast = function(pos, intensity) -- deliberately empty end`) | Make the toggle real: `blast_immune = true` → current no-op (spec default preserved); `false` → behave like a normal Mineclonia node under blast (return the standard drop/damage contract — check how comparable `cracky` nodes and `mcl_mobspawners:spawner` handle `on_blast` in `~/dev/mineclonia-git`). Pair with F07-2 so `false` is actually settable | **IN-SCOPE** |
| F07-12 | f07 §4.6.3 (shift-click substitute), V-01 | Shift-click "take as much as fits" — PARTIAL, **declared** by V-01: no shift state in Luanti formspecs; `Take all` substituted | `formspecs.lua:250` (comment + button), V-01 decision `f07:262` | **Not a gap to re-litigate.** Keep `Take all`. Ensure the feature file's V-01 entry and §4.6.3 read as *accepted substitution* (documentation wording only if needed) — do not attempt a shift-state mechanism | **ACCEPTED-DECLARED (V-01) — record, don't change** |
| F07-13 | f07 §9 T9 | T9 exercises Sell all with a **stubbed** `smp_sell.sell` that always succeeds; the contract's `false` path and the ordering claim are untested | `test_spawners.lua:724-754` (stub at `:735`; asserts only the `true` path) | Strengthen against the **real contract** shape (`smp_sell/init.lua:180-186`): stub returns `true`/`false` exactly as f02 specifies, drive a `false` (simulate the balance-cap refusal of `sell.lua:150` and the empty-plan refusal of `init.lua:195-203`) and assert **conservation**: storage counts and version unchanged-or-restored, nothing paid, refusal message surfaced, `sell_all` returns `false`. This doubles as the F07-1 ordering/regression test. The cross-mod ordering claim (better orders first) belongs to f02's T4 — assert only your side (stacks handed over intact, honouring the return) | **IN-SCOPE** |
| F07-14 | f07 §3 vs §4.6.3 / §5 (`Page 1/5` vs `Page n of m`; `×n` vs `x128`) | Spec-internal wording splits the code had to break; code renders `x` and `Page n of m` consistently (the observed/V-01 forms) | report §3.4 (`SPEC-CONFORMANCE-REPORT.md:191`); render sites: `formspecs.lua:90` (`S("@1 Spawner x@2", …)`), `formspecs.lua:139` (`S("Page @1 of @2", …)`); comment at `formspecs.lua:89` still says `×n` | **Do not "fix" this in code** — the current `x`/`Page n of m` choices are correct pending **D5**. Record in §10 that f07 awaits D5 (spec normalises to what the code renders, never the reverse). Optional: align the `formspecs.lua:89` *comment* with what line 90 actually renders | **ESCALATE → D5** (documentation only) |

**Status of everything else:** 48/63 rows OK and frozen — see Preserve.

## Preserve (do not regress)

- The curve `C × (1 − (1 − r/C)^n)` with exact anchors **58.9 / 495.7 /
  1477.6** (stacks 10/100/1000), `r = 6`, `C = 1505.35` skeleton; V-62's
  isolated `smp_spawners.curve` seam.
- Nine types' exact loot tables and XP values (incl. V-03 blaze **rods**),
  deterministic fractional accrual — no RNG anywhere.
- **Zero entities / zero ABMs** (goal G1) — asserted (0 entities, 0 LBMs).
- Capacity `min(hard_cap, per_spawner × n)` with `paused_full` ("Storage
  full" visible), overflow discarded, `last_update` still advances (V-05).
- XP cap `xp.per_spawner_cap × n` + `mcl_experience.add_xp`; stack size
  2,147,483,647; sneak dig −64 with overflow drop; Silk Touch gating
  (`require_silk_touch`).
- Version-counter double-collect protection; O(1) accrual; one timer per
  spawner; revalidation of node/type/stack/distance on **every** received
  field; menu actions fail safely on a dug node (T10).
- All verbatim/proposed menu strings: `<Type> Spawner x<n>`, the
  `Stored @1 / @2    XP @3 / @4` line, `Rate: @1 kills/min`,
  `< Prev`/`Next >`, `Sell all`, `Collect XP`, `Take all`, `Close`,
  `Page n of m` — plus the §10-proposed string list at `f07:289-296`.
- Placement/stacking/take rules with protection; anyone may open/take/sell;
  `open_requires_access` default false; Sell-all routing through f02 when
  present, V-63 `Selling is not available yet` fallback when absent.
- Capacity/accrual defaults in §7 (per_spawner 2 880, hard_cap
  2 147 483 647, xp cap 2 000, timer 60 s, accrual_mode `active_only`,
  sneak_break_max 64).

## Beyond spec — keep, but declare

- `/spawner give` 1–64 cap (`Count must be between 1 and 64`).
- Extra refusal/protection strings not yet in the §08 proposal list
  (`Close`, `Administrative spawner issue is disabled`, `Unknown spawner
  type`, `This area is protected`, …).
- Keys `spawners.offline_cap_hours`, `enable_creeper`, `hopper_extraction`
  — already proposed to the mirror in `f07:274-282`; keep those proposals
  current as F07-5/F07-6 evolve (if you strike `hopper_extraction` or
  `convert_natural`, update the proposal to match).

## Acceptance criteria

1. **F07-1:** with `smp_sell.sell` returning `false`, spawner storage,
   version and totals are byte-identical to their pre-call state (or exactly
   restored), the player is told, `sell_all` returns `false`; with `true`,
   storage decreases exactly by the sold lots. No yield sits between the
   successful sell and the state write (§2.3).
2. **F07-2:** each of `require_silk_touch`, `blast_immune`, `enable_creeper`,
   `acquisition.admin`, `open_requires_access` behaves correctly for
   unset/`true`/`false` — three cases × five keys asserted in dev-tests;
   specifically `spawners.enable_creeper = false` removes the creeper type
   (V-04 escape hatch works).
3. **F07-3:** the menu contains an `Inventory` label and functional `list[]`
   player-inventory elements; storage grid and player inventory are distinct;
   a take still routes through the revalidating take-request path.
4. **F07-4:** the spawner node registers group `unmovable_by_piston = 1`
   (assert via `core.registered_nodes` in a test) — mechanism re-verified
   against `~/dev/mineclonia-git`.
5. **F07-5:** either a working extraction path gated on
   `spawners.hopper_extraction` (with a test showing default-off extracts
   nothing), **or** the key struck from §7 + §10 note — one of the two, stated.
6. **F07-6:** either `convert_natural = true` converts a dug
   `mcl_mobspawners:spawner` (test: dig with Silk Touch → `smp_spawners:spawner`
   of the right type) with default-false leaving vanilla untouched,
   **or** the key struck from §7 + §10 note — one of the two, stated.
7. **F07-7:** simulate `last_update` 120 s in the past, open the menu (and
   separately: take / Collect XP / Sell all) → accrued output includes the
   full elapsed 120 s, not merely what the last timer tick produced.
8. **F07-8/F07-9:** settings under the documented names
   (`spawners.C.skeleton`, `spawners.acquisition = {…}`) change behaviour;
   old spellings still work if kept as fallback; defaults unchanged;
   `shared/06` untouched by you.
9. **F07-10/F07-11:** `stack_mode` and `blast_immune` each demonstrably do
   what their (unchanged) defaults say **and** respond to a non-default value;
   default-path behaviour identical to today.
10. **F07-13:** new conservation test green; T9 stub matches the real f02
    contract, both `true` and `false` paths covered.
11. **F07-14:** no code change; D5 recorded in §10; renders still `x` /
    `Page n of m`.
12. **Preserve:** every item above still asserted — T1–T8 and T10 unchanged
    and green.

## Tests

- Dev-test: `luajit friedcake/dev-tests/test_spawners.lua` — **must exit 0**
  (verified green on 2026-09-23: `86 passed, 0 failed`). T1–T8, T10 stay as
  they are; T9 is rewritten per F07-13 plus a new conservation case (force
  `smp_sell.sell → false`, assert storage/version/money unchanged).
- New cases: bool matrix (F07-2), menu inventory presence (F07-3),
  `unmovable_by_piston` group (F07-4), hopper/convert on-off paths or their
  strike documented (F07-5/6), elapsed-time conversion on each interaction
  (F07-7), documented config-name overrides (F07-8/9), `stack_mode` /
  `blast_immune` toggles (F07-10/11).
- In-mod: update `friedcake/mods/smp_spawners/test.lua` (report §5: its
  config assertions would **not** have caught the `bool()` bug — make them
  catch it now).
- After `00-P0-blockers.md` lands, re-run with the `register_on_globalstep`
  shim at `test_spawners.lua:296` deleted (`B4-1`) — suite must still exit 0.

## Constraints

- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — mirror rows go
  through your feature file → **D7**; you propose nothing directly.
- No edits to `smp_core`, `smp_store`, `smp_admin` — and **no edits to any
  other feature's mod** (`smp_sell` is read-only reference material for the
  F07-1/F07-13 contract; f02's owner fixes anything wrong on that side).
- One agent per feature file: touch only `smp_spawners` and
  `spec/features/f07-spawners.md`. Cross-mod seams (f02 Sell all, f04/f06
  routing-in, f16 legacy) are propose-only via `## Proposed shared changes`
  / §10.
- Money is integer cents; display only via `smp_core.fmt_money`. (Spawner
  storage is item counts/XP, not money — Sell-all proceeds are f02's side.)
- All player-facing strings via `core.get_translator`.
- **No yields between validate and mutate in any economic operation** —
  F07-1 is precisely this rule; shared §2.3.
- Verbatim UI strings character-exact — the Preserve list is frozen,
  including `x`/`Page n of m` (pending D5, never "corrected" to `×`/`1/5`).
- Config keys must match `shared/06` — code reads the documented names;
  mirror changes are D7's.
- Never downgrade an `OBSERVED` requirement. (f07 has **0 frames** — its
  OBSERVED surface is the shared grammar it borrows; the LIVE rows
  `stack_mode`, `C.skeleton`, `acquisition` stay LIVE.)
- Never change curve constants, loot tables or XP values — they are the
  audited-OK core.

## Out of scope

- Recalibrating `r`/`C` or loot (V-02/V-62) — uncalibrated PROPOSED defaults
  are accepted; only the *override mechanism* (F07-8) is in scope.
- Building f16 legacy acquisition sources (`shard_shop`, `crates`) — keys stay
  default false.
- D5's spec-text normalisation — integrator edits §3/§4.6.3, not you.
- Anything in `00-P0-blockers.md`, `01-integrator-decisions.md` beyond the
  D5/D7 escalations.
- Refactoring the formspec/harness architecture beyond the tests listed.

## Definition of done

1. Every issue ID (F07-1…F07-14) is fixed or escalated with a written reason
   and named target (D5 / D7 / integrator / `00`) — no silent drops;
   F07-5/F07-6 each end in an explicit implement-vs-strike decision recorded
   in §10.
2. `luajit friedcake/dev-tests/test_spawners.lua` exits 0; in-mod
   `smp_spawners/test.lua` updated (and no longer blind to the `bool()` bug).
3. `git checkout -b agent/f07-spawner-fixes` from `main`; commit referencing
   `SPEC-CONFORMANCE-REPORT.md §4 f07`; push the **branch, never `main`**.
4. Issue ID → evidence mapping in the commit/PR description: F07-1 →
   `routing.lua:59-74` vs `smp_sell/init.lua:180-186`, `sell.lua:150`,
   `smp_sell/init.lua:195-203` · F07-2 → `init.lua:39-41,63,67,72,78` ·
   F07-3 → `formspecs.lua:4` + `shared/04:22` · F07-4 → `node.lua:139` +
   `mcl_pistons/api.lua:56` · F07-5 → `init.lua:70`, `performance.lua:44-48` ·
   F07-6 → `init.lua:68` · F07-7 → `node.lua:150-151` · F07-8 →
   `init.lua:90-99` vs `shared/06:37` · F07-9 → `init.lua:74-79` vs
   `shared/06:49` · F07-10 → `init.lua:53`, `interaction.lua:63-80` ·
   F07-11 → `init.lua:67`, `node.lua:143` · F07-12 → `formspecs.lua:250`,
   V-01 · F07-13 → `test_spawners.lua:724-754` · F07-14 → report §3.4 +
   `formspecs.lua:90,139`.
5. `fixes/README.md`'s f07 row flips to ✅ when D5/D7 are the only open items
   (annotate "pending D5/D7" otherwise).
