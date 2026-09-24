# Agent prompt — P2: D7 — config mirror reconciliation + guard test

| Field | Value |
|---|---|
| Feature spec | `spec/shared/06-config-reference.md` (integrator-owned; this prompt delegates that ownership for the pass) + every feature file's **§7** table |
| Target | `spec/shared/06-config-reference.md`, §7 tables, new `friedcake/dev-tests/test_config_mirror.lua` |
| Audit source | `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D7 = Option A (plus the mirror halves of D3 and D8) |
| Verdict at audit | high — the config contract lies in both directions; blocks f01/f02/f03/f04/f06/f09/f10/f12 briefs |
| Branch | `agent/rulings-config-mirror` (base: tip of `agent/integrator-decisions` **after P1 and P3 merged**) |
| Wave | 2 — run after P1 (f12/f14 §7) and P3 (f06 annotations) |

## Mission

D7 = **A: the mirror and the §7 tables follow the code.** `shared/06` must end
up with exactly the set of configuration keys the pack actually reads — no
advertised key nobody reads, no read key absent from the mirror — and every
feature's §7 table must agree with it. One bidirectional pass, one guard test
that keeps it true. You are delegated the integrator's write access to
`shared/06` and to §7 tables across feature files; nothing else.

Two related strikes ride along because they are mirror work: D3's
`settings.categories` row and D8's four `legacy.*` rows.

## Read this first (in order)

1. `AGENTS.md` — rules 1–8; rule 1 normally forbids `spec/shared/` edits —
   **this prompt is the integrator's explicit delegation for this file only**.
2. `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D7 row, and
   the D3/D8 rows for your two strikes.
3. `SPEC-CONFORMANCE-REPORT.md` §3.1 — the exact failure modes (prefix renames,
   `store.`/`ah.history` ambiguity, slots tables, the nine missing keys).
4. `spec/shared/06-config-reference.md` in full (header says: feature §7 is the
   declaration source, this file is the consolidated mirror).
5. `fixes/REQUIREMENTS.md` §2 "D7" — your at-minimum add list and resolutions.
6. Feature §7 tables: `grep -n '^## 7\.' spec/features/*.md`.

## Method (do it in this order)

**R1 — build the three sets.**
- **READ**: every settings access in `friedcake/mods/**` —
  `core.settings:get`, `get_bool`, `get_np`, `get_string`, `list_setting`,
  including **prefix-composed** reads: `"smp_tp." .. key`
  (`smp_tp/config.lua:11`, `smp_tp/homes.lua:46` — expand against the key
  tables in those files), `"store." .. k` (`smp_store/init.lua:29`), the
  `ah.`/`orders.`/`spawners.`/`amethyst.`/`quickbuy.` config tables (expand
  them — a literal-prefix grep alone will undercount), the `setting()`
  helper in `smp_combat/config.lua`, `list_setting("settings.cycle_order", …)`
  in `smp_settings/init.lua:43`. Record key → reader `file:line`.
- **DECLARED**: the union of all `## 7. Configuration` first-cells across
  `spec/features/*.md` (expand multi-key cells `` `a`, `b` `` and prefix rows
  `` `x.*` ``).
- **MIRROR**: every first-cell key of `shared/06`'s table.
- Foreign keys are not yours: `mcl_*`, `server.*`, `mg_*`, `beds_*`, … —
  skip unless a feature §7 declares them (then mirror them with Spec column).

**R2 — additions to `shared/06`** (defaults and Status copied verbatim from
the owning §7; Spec column names that feature). At minimum (from the audit —
but the sweep in R1 is authoritative and overrides this list):
`sell.base_prices` (f02:152), `orders.allow_self_delivery` (f04:336),
`quickbuy.page_size` (f05 §7), `shards.transferable` (f06:135),
`shardshop.offers` (f06:139), `settings.cycle_order` (f12 §7),
`homes.delete_confirm` (f09:208 — after rename, see R3),
`combat.log_broadcast` (f10:192), `world.soft_border`, `world.border_margin`,
`world.max_accounts_per_ip`, `world.staff_name_filter`,
`world.staff_name_action`, `world.entity_caps` (f15:153-158),
`scoreboard.title` (`smp_stats/init.lua:57`), `stats.persist_interval`,
`api.mode` (default **`snapshot`** — D4 landed in P1), `ledger.page_size`
(`smp_economy/init.lua:35,47`), `economy.tab_complete`
(`smp_economy/init.lua:253`), `store.*` keys read under the `store.` prefix,
`store.max_balance`, `quickbuy.max_entries`, `quickbuy.price_guard`.
Where R1 finds a read key that **no** §7 declares: add the mirror row *and*
add a §7 row in the owning feature file (you are granted that §7 edit),
Spec column = the feature, Status = `PROPOSED`, and say in your reply which
§7 rows you created.

**R3 — renames (D7=A: docs follow code).**
- `shared/06:50-68` (`tp.*`, `rtp.*`, `rtpqueue.*`, `tpa.*`, `homes.*`) and
  the matching `f08-teleport.md §7:301-315` / `f09-homes.md §7:204-208` rows:
  replace each documented spelling with the **exact full name the code
  reads** under the `smp_tp.` prefix — grep the key tables in
  `smp_tp/config.lua` and `smp_tp/homes.lua`; do not guess the suffix
  shape. `rtpqueue.separation` becomes whatever split keys exist
  (`config.lua:110-111`, e.g. min/max) — one mirror row per real key.
- Keep every Status/Spec cell on renamed rows (renaming a spelling is not a
  status change; the observations behind `tabs_before_more` [F0061] etc. are
  about behaviour/values, not settings-file spellings).
- Other feature §7 tables whose keys the sweep shows under a pack prefix:
  rename identically. **Except:** `f02`, `f05`, `f07`, `f12`, `f13`, `f14`
  §7 — P1 already made the ruling edits there (D1/D2/D3/D4/D5/D6); you may
  *add* rows to those files per R2 if a read key is undeclared, but you do
  not re-litigate P1's rows.

**R4 — slots encoding (`shared/06:17,24`).**
- The documented tables (`ah.slots`, `orders.slots`) are read as dotted
  scalars. Replace each with a prefix row: key cell `` `ah.slots.*` `` /
  `` `orders.slots.*` ``, default cell listing the four values
  (`default`, `tier1`, `tier2`, `tier3` with their numbers), a note in the
  row that the primary spelling is the dotted scalar and the underscore form
  (`orders_slots_default`-style) is an accepted alias (f04 O3), Spec column
  unchanged (f03/f04).
- Where code does not yet read the documented spelling — f04's alias work
  (O3), f07's compound `spawners.C` reads (F07-8/9) — **you do not change
  code**: keep the documented row and register the key in your guard's
  `DECLARED_ONLY` list keyed to that brief (see R6). Those briefs drain the
  list when they land.

**R5 — resolutions and strikes.**
- `store.max_balance`: add a row (Spec: `shared §2.2`) with a cross-note
  against `economy.max_balance` (f01 — E-18's dead-enforcement question stays
  f01's). `economy.max_balance` keeps its row untouched.
- `ah.history` (`06:23`): keep the row, annotate `pending:f03` (f03 brief A6
  owns the storage seam); register it in `DECLARED_ONLY`.
- Strike `settings.categories` (`06:76`) — D3; leave
  `<!-- struck: D3, 2026-09-24 — structure registered in code, not a config key -->`
  where the row was.
- Strike the four `legacy.*` rows (`06:81-84`) — D8; leave
  `<!-- struck: D8, 2026-09-24 — f16 descoped permanently -->`.
- Annotate `shards.require_activity` (`06` row, and f06 §7 `:134` which you
  also own): `inert (V-61 closed, D8 2026-09-24)` — the key is still read, so
  the row stays; it just documents that nothing will ever flip it on.
- **Never** remove or downgrade an OBSERVED row as part of a rename; if a
  rename would strand an OBSERVED note, keep the note text in the renamed row.

**R6 — the guard: new `friedcake/dev-tests/test_config_mirror.lua`.**
Standalone `luajit` script, exit non-zero on violation, print a summary
table. It re-derives MIRROR, READ and DECLARED (same parsing rules as R1 —
keep the parsing in one place in the file) and enforces:
1. every READ key with a pack prefix is in MIRROR → else fail: `<key> read at <site> but absent from shared/06`;
2. every MIRROR row is in READ **or** in `DECLARED_ONLY` (a table in the
   test: `key = "brief-id"` with a comment) **or** in DECLARED → else fail:
   `<key> advertised but unread`;
3. every DECLARED key is in MIRROR → else fail: `<key> in <feature> §7 but absent from shared/06`;
4. `DECLARED_ONLY` entries whose brief has already landed (i.e. whose key now
   appears in READ, or whose brief id is in the test's `drained` list you
   update only in this pass for P1/P3-era items) → fail as stale;
5. prefix-composed reads are matched through an explicit `PREFIX_PATTERNS`
   table in the test (pattern → how to expand), so a rename is visible in
   review, never silently matched;
6. foreign prefixes (`mcl_`, `server.`, `mg_`, `beds_`, `tt`, …) are skipped
   unless declared in some §7;
7. duplicate rows in MIRROR → fail.
The test must pass on the tree you leave behind, with `DECLARED_ONLY`
containing **only** entries keyed to briefs that have not run (expected:
f04 alias, f07 spawners-compound, f03 `ah.history` — print them as a drain
list).

## Out of scope (hard)

- **Any code change** — renames/aliases in `smp_tp`, `smp_ah`, `smp_orders`,
  `smp_spawners` are the owning briefs' rows (f03 A4–A6, f04 O2/O3, f07
  F07-8/9, f08/f09 when their briefs exist). Record a hand-off note per key
  in your reply instead.
- `f12`/`f14` §7 rows P1 already ruled (D3 strike, D4 default) — verify they
  are consistent with your mirror; do not edit.
- `spec/plan/**` (P3/P5), `smp_admin` (P4), `fixes/**` (integrator),
  non-§7 sections of any feature file (§10 rows belong to their briefs).

## Tests

- `luajit friedcake/dev-tests/test_config_mirror.lua` → exit 0; summary shows
  zero unexplained rows in both directions and the `DECLARED_ONLY` drain list.
- Full suite green: every `friedcake/dev-tests/test_*.lua` exits 0.
- Negative self-check (throwaway, not committed): temporarily add a bogus row
  to `shared/06` and confirm the guard fails with the right message; remove it.

## Constraints

- Money integer cents; defaults copied from §7 exactly (no re-rounding of
  `$10¹²`-style cells); no status downgrades; strings/citations preserved
  character for character.
- Files you may write: `spec/shared/06-config-reference.md`,
  `spec/features/*.md` **§7 tables only** (plus the f06 §7 annotation listed
  in R5), `friedcake/dev-tests/test_config_mirror.lua`. Everything else →
  ESCALATE + stop.

## Definition of done

1. R1–R6 complete; guard green; suite green; drain list = only not-yet-run
   briefs.
2. Reply with: the three-set diff summary (added N rows, renamed M rows,
   struck K rows), every §7 row you created or renamed (file + line), the
   final `DECLARED_ONLY` table, and your hand-off notes for code-side changes
   owed by other briefs.
3. Commit with `D7 D3-mirror D8-mirror` in the message; push
   `agent/rulings-config-mirror`, never `main`.
