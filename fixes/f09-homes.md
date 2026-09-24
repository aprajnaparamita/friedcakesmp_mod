# Fix brief — f09 Homes

| Field | Value |
|---|---|
| Feature spec (read-only except §7/§10 rows noted) | `spec/features/f09-homes.md` |
| Target mod(s) | `smp_tp` (homes subsystem: `homes.lua`) |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f09 (evidence quoted into the rows below; you do not need to read that report — it describes pre-ruling and pre-P0 states) |
| Verdict at audit | **PARTIAL (4 gaps)** · 14 OK — *"the feature is complete inside its edit surface but does not run"* — **three of the four gaps were closed by P0's B3; your job is verify-don't-redo plus the config row** |
| Branch | `agent/f09-homes-fixes` (created for you from the merged tip) |
| Depends on | `00-P0-blockers` **B3** (the three load gaps: `dofile` wiring, `mod.conf` deps, B2 `core.modpath`) — **all three ALREADY FIXED on `main` 2026-09-24 (`smp_tp/init.lua:33`, `mod.conf` carries `smp_store` + optional `smp_ranks`, `core.get_modpath` — verified in tree); verify, do not redo** — **D7** — **ruled 2026-09-24: D7 = A (mirror `06:50-68` incl. the `homes.*` rows and `f09 §7` renamed to the real `smp_tp.*` literals by P2 — pre-applied, verify, don't redo; `homes.delete_confirm` mirror row added)** — cross-references `fixes/f08-teleport.md` (spec dependency f09 → f08) and `fixes/f11-social.md` (T9's `/findplayer` leg is f11's command) |

---

## Mission

The audited verdict was blunt: homes are the pack's best-reproduced UI —
the full observed tab row, submenu, `Choose Icon` browser and all five
verbatim chat strings pass character-for-character — and **none of it runs**,
because three integrator edits never landed and the dev harness shims all
three gaps, so 134/134 tests gave false assurance. P0's B3 landed those edits
on `main`. What remains is the part nobody may skip: **prove the feature now
runs through its real load path** (not the harness's direct `dofile`), prove
the config keys match the renamed mirror, and close the test caveat honestly.
If your branch passes only because a shim still stands in for the wiring, you
have closed nothing.

## Read this first (in order)

1. `AGENTS.md` — hard rules (esp. 1, 4, 6–8).
2. `fixes/f09-homes.md` — this file: the rows below are your task.
3. `fixes/01-integrator-decisions.md` § **Rulings — 2026-09-24** — **D7** only.
   Settled; "but the spec says" loses to it.
4. `spec/features/f09-homes.md` — your own feature file: §4 (behaviour),
   §5 (schema), §7 (config — the renamed rows), §9 (T1–T9), §10, §11
   (notes 1–2: the wiring, now landed — verify against it).
5. `spec/shared/` — end to end, READ ONLY (esp. `00-conventions.md §0.5`
   verbatim UI, `06-config-reference.md` `smp_tp.homes.*` rows,
   `08-ui-strings.md` the five verbatim home strings).
6. `spec/plan/acceptance-tests.md` — your row is **line 23: f09-homes |
   T1–T9** (T9's `/findplayer` leg is f11's command — owner-scoping only,
   see row) — the merge gate.
7. Target mod source (`friedcake/mods/smp_tp/homes.lua`, `init.lua`,
   `mod.conf`) + `friedcake/dev-tests/test_homes.lua`.

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| H1 | §11 note 1 | `dofile(... "homes.lua")` never wired from `init.lua` — `/homes`, `/sethome`, `/delhome` did not exist in-game | report §4 f09 row 1 (`init.lua:19-27` at audit); `homes.lua:24` and `test_homes.lua:55` awaited the line | **Verify the B3 fix**: `init.lua:33` now `dofile(modpath .. "/homes.lua")`. Confirm the commands register through the real load path (grep the registration + a load-order assertion if your harness offers one). **Do not redo** | **ALREADY FIXED on `main`** (B3) — verify only |
| H2 | §11 note 2 | `mod.conf` lacked `smp_store` (+ optional `smp_ranks`) | report §4 f09 row 2 (`mod.conf:3` at audit) | **Verify**: `mod.conf:3-4` now reads `depends = smp_core, smp_store, mcl_worlds, mcl_spawn` / `optional_depends = mcl_title, mcl_vars, smp_ranks`. **Do not redo** | **ALREADY FIXED on `main`** (B3) — verify only |
| H3 | §11 note 1 + report "test caveat" | The `core.modpath` blocker (B2) **and** the harness workaround: 134/134 passed **only because the harness shims all three load gaps** — direct `dofile` of `homes.lua`, shimmed modpath | report §4 f09 rows 3 + caveat (`test_homes.lua:55,355,386-389` at audit) | **Verify, then de-shim what is now real**: (a) confirm no `core.modpath` reference survives anywhere in `smp_tp` (the harnesses now shim `core.get_modpath` — the engine-real name at `test_homes.lua:349`, `test_tp.lua:195` — that is legal, keep it); (b) make the suite exercise the **real wiring**: assert `init.lua` pulls in `homes.lua` (e.g. load `init.lua`'s file list, or a registration-count assertion that fails if `homes.lua` were removed from `init.lua`), rather than only direct-dofiling `homes.lua` at `test_homes.lua:55`; (c) if any shim still stands in for a **load gap** (not a path root), remove it and fix the code instead. Never stub an engine-absent name (B4-1) — `test_engine_apis.lua` must stay green | IN-SCOPE (verification + harness honesty) |
| H4 | §7 / `06:64-67` | Config keys read through the `smp_tp.`-prefixed helper where the mirror once documented `homes.*` — mirror-named `minetest.conf` entries were silently ignored (values all matched defaults) | reads `homes.lua:46,62-65`; mirror rename by P2 | **Verify the D7 rename closed the divergence**: every `homes` key your code reads (`grep 'setting(' homes.lua`) has a matching `smp_tp.homes.*` row in `shared/06` and in your own §7, values/defaults identical; `homes.delete_confirm` is present in both. `test_config_mirror.lua` must stay green. Any residual mismatch → fix **code or your own §7**, propose mirror changes through `## Proposed shared changes`, never hand-edit `shared/06` | IN-SCOPE (verify; fix residual) |

### Preserve exactly (Confirmed OK — byte-identical)

`/homes`, `/home`, `/sethome`, `/delhome`; slots `{2,9,27,90}` tier-gated
through the `smp_ranks` bridge with its documented fallback; `name_max` 32;
**the full observed UI** — the `Homes` tab row with correct triangle, one tab
per home, `New Home` after the last, `Show More` far right and separated at
`tabs_before_more=3`, tooltips `<name>`/`Click to manage`, the 2×2 submenu
(`Teleport`/`Change Icon`, `Rename`/`Delete`, centred `Back`, red Delete),
`Choose Icon` with the alphabetised registered-item list and
`Search`/`Default`/`Back`, `Rename` pre-filled with the current name with
stacked `Save`/`Cancel`, delete confirmation; **all five verbatim chat
strings** (`Home set`, `Home deleted`, `Home does not exist`,
`You reached home limits`, `You renamed your home to @1`); storage in the
`smp_store` player record; stale-id re-validation at click time; T1–T8 ids.
Keep-beyond-spec: `Choose Icon` paging (`(Page @1)`, `Prev`, `Next`).

## Acceptance criteria

1. H1/H2 verified with evidence (greps/output in your report), nothing
   re-implemented.
2. H3: the suite fails if `homes.lua` is unwired from `init.lua` — i.e. the
   harness now proves the real load path; no shim replaces a load gap;
   `test_engine_apis.lua` green (no engine-absent stub names).
3. H4: code reads ↔ `shared/06` rows ↔ your §7 rows agree key-for-key and
   default-for-default; `test_config_mirror.lua` green.
4. T1–T9 ids intact and green; the five verbatim strings unchanged byte for
   byte; no OBSERVED row downgraded.

## Tests

- `luajit friedcake/dev-tests/test_homes.lua` — must exit 0; add/adjust the
  H3 real-wiring assertion and the H4 key-agreement check.
- In-mod `smp_tp/test.lua` — homes cases per AGENTS step 7 (add if absent).
- Exact gate (whole suite):
  ```
  for t in friedcake/dev-tests/test_*.lua; do luajit "$t"; done
  ```
  (26 files at dispatch; grows if you add one.)

## Constraints

- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — proposals
  flow through `f09-homes.md` §10 / `## Proposed shared changes`.
- No edits to `smp_core`, `smp_store`, `smp_admin` — escalate instead
  (storage of homes is *through* `smp_store`'s existing API only).
- One agent per feature file: `smp_tp`'s homes subsystem is yours; the
  teleport/rtp/queue rows belong to `fixes/f08-teleport.md` — do not work
  them, record cross-notices in §10.
- Money is integer cents; display only via `smp_core.fmt_money`.
- Every player-facing string through `core.get_translator`.
- Verbatim UI strings character-exact (§0.5); never downgrade an `OBSERVED`
  requirement.
- Config keys must match `spec/shared/06-config-reference.md` — propose
  mirror changes, never hand-edit.

## Out of scope

- Re-doing B3's three edits (landed — verify only).
- T9's `/findplayer` behaviour — f11's command; you assert owner-scoping
  only (`/findplayer` never returns exact coordinates' *leak* leg lives
  with f11's brief).
- Teleport, `/rtp`, requests, queue rows — `fixes/f08-teleport.md`.
- Chat-privacy settings legs (f11/f12).

## Definition of done

1. Every issue ID H1–H4 is closed with evidence written into your report
   (H1/H2 greps, H3 wiring assertion, H4 key agreement); anything residual
   escalated in `spec/features/f09-homes.md §10`.
2. Whole dev suite exits 0 (paste the count), including
   `test_config_mirror.lua` and `test_engine_apis.lua`.
3. Your branch `agent/f09-homes-fixes` (created from the merged tip) is
   clean and committed; attempt one `git push -u origin
   agent/f09-homes-fixes` — SSH is expected to fail, leave it local.
   **Never push `main`.**
4. Your report states plainly whether the feature now runs through its real
   load path (not a shim). The overseer annotates `fixes/README.md` — you
   do not edit `fixes/`.
