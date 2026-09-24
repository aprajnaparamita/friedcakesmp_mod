# Fix brief — f10 Combat & bounties

| Field | Value |
|---|---|
| Feature spec (read-only except §7/§10 rows noted) | `spec/features/f10-combat.md` |
| Target mod(s) | `smp_combat`, `smp_bounty` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f10 (evidence quoted into the rows below; you do not need to read that report — it describes pre-ruling states) |
| Verdict at audit | **MOSTLY COMPLETE (2 gaps)** · 18 OK · 1 N/A — all four roadmap-critical gates verified OK (tag, countdown, combat-log four-list drop + kill credit, blocked commands) |
| Branch | `agent/f10-combat-fixes` (created for you from the merged tip) |
| Depends on | `00-P0-blockers` (B1 site #1 blocked `smp_combat`/`smp_bounty` via `smp_store` — **already fixed on `main`, verify only**), **D7** — **ruled 2026-09-24: D7 = A (your `combat.*` rows incl. `combat.log_broadcast` added to the mirror by P2 — pre-applied, verify, don't redo)** — **P5 finding: the `smp_stats ↔ smp_combat` `optional_depends` boot cycle is RESOLVED at pack level 2026-09-24 — stats' redundant edge was removed and `smp_combat`'s `optional_depends = smp_stats` KEPT because it is order-critical (`smp_stats/combat.lua:11-14`: stats' leaveplayer callback must run before `smp_combat.on_leave` untags the logger) — verify the cycle stays closed, touch NEITHER `mod.conf`** — cross-references `fixes/f08-teleport.md` (`combat.keep_pearls_on_death`'s only consumer is f08 §4.6 pearls, spec-deferred) |

---

## Mission

Combat and bounties are the audit's cleanest feature class: tag refresh,
countdown, the four-list combat-log drop with kill credit, the character-exact
blocked-command refusal and the whole escrow flow all verified OK, hygiene
PASS. Two gaps remain, and both are "a documented knob nobody wired":
`combat.disable_elytra` reads, warns, and does nothing; `combat.keep_pearls_on_death`
is documented in the operator mirror with **zero production readers** (grep
finds it only in two test files). A config key that cannot take effect is the
§3.1 failure mode verbatim. "Fixed" means each key either does what the spec
says or is honestly re-scoped in your own §7/§10 — never a key that lies —
while every verified-OK behaviour above stays byte-identical.

## Read this first (in order)

1. `AGENTS.md` — hard rules (esp. 1, 4, 6–8).
2. `fixes/f10-combat.md` — this file: the rows below are your task.
3. `fixes/01-integrator-decisions.md` § **Rulings — 2026-09-24** — **D7** only.
   Settled; "but the spec says" loses to it.
4. `spec/features/f10-combat.md` — your own feature file: §4.2.5 (elytra),
   §4.3 (combat log, death credit), §5 (schema), §7 (`combat.*` keys),
   §9 (T1–T12), §10.1 (note 14 elytra disclosure, note 15 keep-on-failure,
   note 13 bounty namespace).
5. `spec/shared/` — end to end, READ ONLY (esp. `00-conventions.md §0.5`,
   `06-config-reference.md` `combat.*`/`bounty.*` rows,
   `05-command-reference.md` the block list).
6. `spec/plan/acceptance-tests.md` — your row is **line 24: f10-combat |
   T1–T12** (+ X5 combat logout line 44, X10 safe-zone bounty leg line 49)
   — the merge gate.
7. Target mod source (`friedcake/mods/smp_combat/*.lua`, `smp_bounty/*.lua`)
   + `friedcake/dev-tests/test_combat.lua`, `test_bounty.lua`.

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| C1 | §4.2.5 | `combat.disable_elytra` hook into Mineclonia's elytra physics **missing**: the key is read and `init.lua` only logs a warning when true — a knob that cannot take effect | key `smp_combat/config.lua:26`; warn-only `init.lua:140-143`; spec-disclosed `f10` §10.1 note 14 | Implement it engine-feasibly: investigate the real extension point in `~/dev/mineclonia-git` (the playerphysics/elytra path the spec names — how third-party mods are expected to override physics; `core.register_player_physics_modifier`-style APIs per `~/dev/luanti` docs) and disable elytra flight while a player is combat-tagged (or wholesale, per §4.2.5's exact wording — follow the spec text) when the key is `true`. Default stays `false` → zero behaviour change out of the box. **If no non-invasive hook exists** (patching Mineclonia's own mod files is forbidden): keep the loud warning, and record a §10 proposal in your own feature file to re-scope §4.2.5 to what is possible — never a silent no-op knob either way | IN-SCOPE (§10 fallback if the engine offers no seam) |
| C2 | §7 / `06:71` | `combat.keep_pearls_on_death` has **no production reader** — documented to operators, honoured by nothing; grep finds it only in `smp_settings/test.lua:182` and `dev-tests/test_settings.lua:492` | no reader anywhere under `friedcake/mods/` except the two test files | Decide and land one honest option: **(a)** implement a reader where death drops resolve — if `smp_combat` has a viable seam (dieplayer hook order vs `mcl_death_drop` — verify against `~/dev/mineclonia-git`, do **not** edit Mineclonia mods) — keeping the default exactly today's drop behaviour; **(b)** if no seam exists without touching another mod: record a §10 proposal to re-scope the §7 row as `pending:f08 §4.6` (its only consumer, ender pearls, is spec-deferred — see `fixes/f08-teleport.md` TP6) and align your own §7 accordingly. Either way the mirror row's promise must become true or be visibly narrowed — never left lying. Keep `test_config_mirror.lua` green | IN-SCOPE (choose (a) or (b) with evidence) |
| C3 | context / verify | Three pack-level items touch your mods — verify, don't touch | `smp_combat/mod.conf:4` (`optional_depends = …, smp_stats`), `smp_stats/combat.lua:11-14` ordering comment, `shared/06` `combat.log_broadcast` row | (i) Confirm the stats↔combat cycle stays closed (P5: it aborted real boots) and that **your** `smp_stats` edge is still there — it is the order-critical half; edit neither `mod.conf`. (ii) Confirm `combat.log_broadcast` reads match the mirrored row (D7/P2). (iii) Confirm no B1-era `core.register_on_globalstep`/`core.modpath`/`get_player_names` reference survives in your two mods (B1-fixed — verify only) | **VERIFY ONLY** |

### Preserve exactly (Confirmed OK — byte- and behaviour-identical)

20 s tag refreshed by every hit (`tag.lua:85`); action-bar countdown
`In combat: @1s`, `stay=40`, 1 Hz, clears on untag; combat log dropping all
four registered lists (iterated, **never hard-coded**) at the logout
coordinates with the kill credited, broadcast
`@1 has logged out during combat.`, `smp:combat_logged = 1`, respawn at
world spawn, flag cleared; blocked-command enforcement via
`register_on_chatcommand` with the character-exact refusal
`You cannot use /@1 during combat.` and `/sell`, `/msg`, `/ah` allowed;
melee/arrow/explosion tagging of both parties with the specified attribution
(blast ring 10 s/12 nodes/64-cap; V-73 ignition gap stays spec-acknowledged);
untag on death of player or opponent with credit before untag; `/kill` while
tagged credits the last attacker; kill credited into stats and bounty; the
complete bounty flow — list by total largest-first, escrow debit with stacked
contributions, `bounty.min_amount` $1 000 with the exact
`The minimum bounty is $ 1K.`, self-refusal, whole-bounty payout + broadcast,
no IP-shared payout, 3 600 s pair cooldown, no payout in the safe zone, no
refund except `/bountyadmin clear` pro rata; tag state transient in memory
(T11 restart-wipe); T1–T12 ids; X5/X10 legs. Keep-beyond-spec: blocked list
= 12 not 10 (`tp`, `home` — spec-aware, V-72); `/bounty` allowed while
tagged (spec silent); bounty records in `smp_bounty`'s own namespace (note
13); keep-on-failure retry (note 15); the Shard-Pickaxe while-tagged block
in `smp_amethyst` (wired `pickaxe.lua:44-47` — not your mod, don't touch).

## Acceptance criteria

1. C1: `combat.disable_elytra = true` produces the specified effect through
   a real engine/Mineclonia seam (asserted by a test), or a §10 proposal
   re-scopes §4.2.5 with the investigation evidence — default `false`
   behaviour unchanged either way.
2. C2: every `combat.*`/`bounty.*` key in `shared/06` either has a
   production reader that does what the row promises or is visibly re-scoped
   in your §7 + §10 — `keep_pearls_on_death` specifically lands in one of
   the two states; `test_config_mirror.lua` green.
3. C3: all three verifications recorded with grep output in your report.
4. T1–T12 ids intact and green; integer cents, translator, no yields on the
   escrow path (hygiene PASS stays PASS).

## Tests

- `luajit friedcake/dev-tests/test_combat.lua` and
  `luajit friedcake/dev-tests/test_bounty.lua` — must exit 0; add cases for
  C1 (key on → elytra disabled while tagged / seam effect) and C2 (reader
  behaviour, or the re-scope assertion).
- In-mod `smp_combat/test.lua` / `smp_bounty/test.lua` — add per AGENTS
  step 7 (create if absent).
- Exact gate (whole suite):
  ```
  for t in friedcake/dev-tests/test_*.lua; do luajit "$t"; done
  ```
  (26 files at dispatch; grows if you add one — `test_config_mirror.lua`
  and `test_engine_apis.lua` must stay green.)

## Constraints

- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — mirror/§7
  proposals flow through `f10-combat.md` §10 / `## Proposed shared changes`.
- No edits to `smp_core`, `smp_store`, `smp_admin`, `smp_stats`, Mineclonia
  mod files, or any other feature's mod — escalate instead.
- One agent per feature file: `smp_combat` + `smp_bounty` are yours; the
  queue's block-only pairing (f11/f08 hand-off) is **not** yours even though
  it consumes your tag/block state — record cross-notices in §10.
- Money is integer cents (bounty escrow is the most money-dense path in the
  pack); display only via `smp_core.fmt_money`.
- Every player-facing string through `core.get_translator`.
- No yields between validate and mutate in any economic operation — the
  escrow debit/payout must stay validate→mutate→ledger in one step.
- Verbatim UI strings character-exact; never downgrade an `OBSERVED`
  requirement (f10 has no frame coverage — its rows are LIVE/CLONE/PROPOSED;
  amendments go through §10, marked).
- Config keys must match `spec/shared/06-config-reference.md` — propose
  mirror changes, never hand-edit.

## Out of scope

- Implementing f08's ender pearls (spec-deferred) — C2 option (b) exists
  precisely because of this.
- Editing `smp_stats` or either `mod.conf` (C3 is verify-only).
- The `smp_rtpqueue` pairing predicate (f11 → f08 hand-off).
- V-73's ignition gap (stays spec-acknowledged) and tag-duration V-12
  (undocumented — tests run the PROPOSED 20 s default).

## Definition of done

1. Every issue ID C1–C3 is closed or has the reason written into
   `spec/features/f10-combat.md §10` (C1 no-seam proposal, C2 option (b)
   `pending:f08` if chosen).
2. Whole dev suite exits 0 (paste the count), including
   `test_config_mirror.lua` and `test_engine_apis.lua`.
3. Your branch `agent/f10-combat-fixes` (created from the merged tip) is
   clean and committed; attempt one `git push -u origin
   agent/f10-combat-fixes` — SSH is expected to fail, leave it local.
   **Never push `main`.**
4. Your report maps C1…C3 → evidence `file:line` + commit and lists §10
   escalations for the overseer. The overseer annotates `fixes/README.md` —
   you do not edit `fixes/`.
