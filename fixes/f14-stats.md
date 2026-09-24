# Fix brief — f14 Stats, leaderboards, scoreboard, API

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f14-stats.md` |
| Target mod(s) | `smp_stats` (+ `fixes/README.md` row update at the end) |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f14 |
| Verdict at audit | **MOSTLY COMPLETE (4 gaps)** · ~40 OK · T1–T11 green (incl. the 50 ms perf test) — plus the blocking B1-6 site in this mod |
| Branch | `agent/f14-stats-fixes` |
| Depends on | `00-P0-blockers` (B1-6/B4-1 — **fix site is yours: fix it here, don't wait**), D4 (`api.mode` default), D11 (integration-harness seam note) — **ruled 2026-09-24: D4 = §7 default corrected to `snapshot` (F14-D5 pre-applied by P1, verify, don't redo), D11 = A (`test_integration.lua` built by P5)** — **P5 finding: `smp_stats ↔ smp_combat` `optional_depends` cycle aborts a real engine boot — your half; f10 (combat) has no brief file, GAP-1** |

---

## Mission

`smp_stats` cannot finish loading even after `smp_store` is fixed: it calls
`core.register_on_globalstep`, an engine function that does not exist, and its
dev-test harness stubs that same wrong name, so the suite encodes the bug. On
top of that, `api.mode` defaults against the spec's own §7 table, monotonic
counters accept negative increments, and T4/T5 claim integration they only
simulate. "Fixed" means the mod boots, an operator's `api.mode` misconfiguration
fails loudly, counters provably never decrease, tests claim only what they
prove — and the scoreboard/leaderboard/perf OBSERVED surface stays byte- and
millisecond-identical. Consequence: without this, the whole feature class
(leaderboards, scoreboard, `/stats`) is dead in production and the audit's
strongest-performing suite keeps giving false assurance.

## Read this first (in order)

1. `AGENTS.md` — hard rules (esp. 1, 4, 6–8).
2. `spec/features/f14-stats.md` — §4.1 rule 2 monotonic (lines 82-83), §4.4
   (lines 112-128), §6 pseudocode (line 157 has `core.register_globalstep`
   **right**), §7 (line 187 `api.mode = off`), §9 (lines 207-221), §10
   (F14-D5 at line 237), F14-D1…D9.
3. `spec/shared/02-architecture.md`, `04-ui-kit.md`, `05-command-reference.md`,
   `06-config-reference.md` (`api.mode` row / §7 mirror), `08-ui-strings.md`,
   plus `spec/shared/00-conventions.md §0.5` (line 88: sentence case, **no
   terminal full stop**) — READ ONLY.
4. `spec/plan/acceptance-tests.md` — your row is line 28: **f14-stats |
   T1–T11** (+ perf budget X7, line 46) — the merge gate.
5. `SPEC-CONFORMANCE-REPORT.md` §4 f14 (lines 680-718), §2 B1 #6 (line 78),
   §3.3 weak-single-tests note (line 173).
6. Target mod source (`friedcake/mods/smp_stats/*.lua`, `test.lua`) +
   `friedcake/dev-tests/test_stats.lua`.

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| S1 | f14 §6 line 157 / report line 686 (B1 #6) | `core.register_on_globalstep` does not exist; `init.lua` re-raises on any submodule error, so `smp_stats` cannot finish loading **even after `smp_store` is fixed**. The logic around it (60 s flush, carried remainder) is correct — only the name is wrong | `smp_stats/playtime.lua:59`; re-raise `init.lua:88-96`; wrong-name harness stub `dev-tests/test_stats.lua:259` | **Fix it here — this is your mod's line (P0 lists it too; coordinate by fixing rather than waiting).** Rename to `core.register_globalstep`. Same change forces the harness: rename the stub key at `test_stats.lua:259` to `register_globalstep` (keep the capture-into-`globalstep_handlers` behaviour — tests that step the handler depend on it). Note the B4-1 overlap in §10 if you get there first (P0 brief says: note it). Do not change callback semantics, intervals or the remainder carry | **ALREADY FIXED on `main`** — verified 2026-09-24 (`playtime.lua:59` reads `core.register_globalstep`, harness stub renamed too; `STATUS.md` §3). **Verify, do not redo** |
| S2 | f14 §7 line 187 vs §4.4 line 128 / F14-D5 (`f14:237`) | `api.mode` default is `off` in §7's table but `snapshot` in code (§4.4 says "pick option 1 by default"; the spec self-documents the conflict) | `smp_stats/init.lua:43-50` (unset ⇒ `snapshot`) | **Integrator picks which side of the spec to correct** — record in `f14-stats.md §10` pointing at D4 (options: correct §7 to `snapshot`, or code to `off`). Do not change the default yourself; after D4 lands, align default *and* the invalid-value fallback together | ESCALATE (D4) |
| S3 | f14 §7 / report line 687 | Unknown `api.mode` values fall back to `snapshot`; the warning path exists but the empty/`""` case falls back silently alongside the legitimate "unset" case | `init.lua:44-45` (non-string **or** `""` ⇒ silent default), `:46-49` (garbage string ⇒ warns — keep) | Make invalid values fail loudly: distinguish **unset** (`core.settings:get` ⇒ `nil` ⇒ silent default, correct) from **set-but-invalid** (including `""` and unknown strings ⇒ `core.log("warning", …)` naming the bad value and the fallback, then fall back as today). Never hard-crash the mod over a config string | IN-SCOPE |
| S4 | f14 §4.1.2 (lines 82-83) / report line 688 | Counters must be monotonic; `add()` accepts negative increments, so monotonicity is convention, not enforced | `smp_stats/counters.lua:47-56` (`value = tonumber(value)` … `new = floor(current + value)`, no sign check) | Reject (or clamp to 0 delta) negative increments — a monotonic counter never decreases — keep the two negative-free live-field semantics of F14-D1 (`money`/`shards`/`playtime` still refused by `add`). Return the documented `nil, err` shape on rejection; all shipped callers pass positives so behaviour is unchanged | IN-SCOPE |
| S5 | f14 §9 T4/T5 / report lines 173, 689 | Both tests **simulate** f02's and f05's writes in shape rather than driving a real `/sell` or Quick Buy flow — field agreement, not integration; header currently reads as if integration were covered | `dev-tests/test_stats.lua:9-10` (headers), `:522-543` (the simulated sections) | Honest-labelling fix only (a full headless integration is out of scope): rename/annotate the section labels and file header so T4/T5 are explicitly **contract-shape tests** (they verify `rec.stats` field agreement, not the live flow), **and** add the seam note that real f02/f05 flows land with D11's integration harness — in the dev-test header and mirrored as a note in `f14-stats.md §10` (your file). **Do not claim end-to-end coverage you do not have; do not delete or renumber T4/T5** — the ids are the plan's merge gate | IN-SCOPE |
| S6 | f14 §4.4 option 2 / report line 690 | `api.mode = push` is a deliberately warned stub; spec marks option 2 PROPOSED/optional | warn `smp_stats/api.lua:108-112`; refusal `api.lua:127-130` (`/api` in push mode returns `false, …`), `off` refusal `:124-126` | Keep the stub — but ensure it **refuses cleanly and says so**: verify the load-time warning fires and `/api` refuses with the explanatory message in both `off` and `push` modes (T10 already asserts the refusals — keep those assertions green). No partial push implementation | IN-SCOPE (verify/keep) |
| S7 | shared §0.5 (line 88: no terminal full stop) / report line 714 | Terminal full stops on command descriptions and one refusal string (§0.5 drift; none are OBSERVED catalogue strings — verified absent from `shared/08`) | `init.lua:106` (`Show statistics for a player.`), `:119` (`Show the leaderboards.`), `:134`, `:142` (`Alias for /leaderboard.`), `api.lua:120` (`Issue or revoke your personal API key.`), `formspec.lua:197` and same string at `:201,:211,:225` (`Player @1 does not exist.`) | Strip the terminal full stops at all listed sites (all four `formspec.lua` occurrences of the string together), keeping every string inside `core.get_translator` | IN-SCOPE (minor) |

### S1 detail

Proof chain: `playtime.lua:59` (call) → `init.lua:88-96` (`loadfile`+`pcall`
re-raise at `:91/:95`) ⇒ `smp_stats` aborts at load. After your rename, the
harness **must** expose `core.register_globalstep` or the suite dies the same
way — that is why the `test_stats.lua:259` key rename is part of S1, not
optional. P0's B4-1/B4-3 (`test_engine_apis.lua` greps
`register_on_globalstep` to zero across `friedcake/mods`) must stay green
after your branch.

## Acceptance criteria

1. `rg 'register_on_globalstep' friedcake/mods/smp_stats` returns zero;
   `dev-tests/test_stats.lua` stubs and captures under `register_globalstep`.
2. Invalid-but-set `api.mode` produces a warning naming value + fallback;
   unset stays silent; default unchanged pending D4 (recorded in §10).
3. `smp_stats.add(name, key, -5)` cannot decrease a counter (rejected or
   clamped — asserted both that the counter is unchanged and the error shape).
4. T4/T5 honestly labelled contract-shape + D11 seam note present; no
   end-to-end claim anywhere in headers or §10.
5. O7-style hygiene: the seven strings above have no terminal full stops.
6. **Preserve exactly** — nothing below changes by one byte or one millisecond:
   - Scoreboard lowercase money convention (`754k` vs chat `$ 754K`) asserted
     against f01 §3.2 (F14-D3); event-driven updates by wrapping
     `add_money`/`take_money`/`set_money` (**never polling**); title chain
     `scoreboard.title` → `server.name`; two-line bottom-right HUD with **NO
     coordinate readout**.
   - All ten counters on the right hooks with the F14-D2 attribution resolver
     (incl. the f10 death-credit interplay); `rec.stats` seven fields exactly;
     ten leaderboard categories in official key **and** label order.
   - Rebuild outside globalstep on a `core.after` chain (`refresh` 300 s /
     `size` 100); **the 50 ms @ 10,000 performance test
     (`test.lua:124-158`, asserts `< 0.05`) must stay**; offline players
     included; `api_key` schema (`fcsmp_` + sha1); T1–T11 ids intact.
   - Beyond spec to keep: JSON snapshot files under `<worldpath>/friedcake_api/`;
     leaderboard picker `<`/`>` paging (F14-D6); `scoreboard.show`
     registration into f12's Scoreboard category (F14-D4).
   - Playtime accumulator behaviour (60 s flush, fractional remainder carry,
     T11 budget F14-D9) — only the registration *name* changes in S1.

## Tests

- `luajit friedcake/dev-tests/test_stats.lua` — must exit 0; new/updated
  cases:
  - S1: playtime accumulator registered via `core.register_globalstep`
    (handler captured by the renamed stub and still steps);
  - S4: negative increment cannot decrease a counter (assert unchanged +
    `nil, err`); positive path unchanged; live-field refusal unchanged;
  - S3: set-but-invalid `api.mode` logs a warning and falls back; unset
    defaults silently (capture via the harness `core.log` stub);
  - S6: `off` and `push` both refuse `/api` (keep T10 assertions);
  - S5: T4/T5 sections run under their new contract-shape labels (ids kept).
- In-mod `friedcake/mods/smp_stats/test.lua` — add the monotonic-counter and
  refusal cases safe for live re-run; **`test.lua:124-158` perf test stays
  untouched and green** (71-assertion suite must not regress).
- Exact gate (must exit 0):
  ```
  luajit friedcake/dev-tests/test_stats.lua
  ```

## Constraints

- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — D4/D11 and
  mirror changes are proposals through `f14-stats.md §10` /
  `## Proposed shared changes` only.
- No edits to `smp_core`, `smp_store`, `smp_admin` (AGENTS rule 4 — escalate;
  note `smp_store`'s own B1-1 is P0's, not yours).
- One agent per feature file: touch only `smp_stats` (+ your own feature file,
  your own dev-tests, `fixes/README.md` row). f02/f05/f10/f12 code is
  consume-only; their defects go in your §10.
- Money is integer cents; display only via `smp_core.fmt_money` (the
  scoreboard's local lowercase formatter is F14-D3-sanctioned — untouched).
- Every player-facing string through `core.get_translator`.
- No yields between validate and mutate in any economic operation
  (`add()` is ensure → mutate → upsert, keep it that way).
- Verbatim UI strings character-exact (and no terminal full stops — shared
  §0.5).
- Config keys must match `spec/shared/06-config-reference.md` — propose
  mirror changes, never hand-edit.
- Never downgrade an OBSERVED requirement (e.g. `scoreboard.enabled`, T8's
  50 ms budget); invented behaviour stays marked `PROPOSED`.
- Keep-on-failure retry is f10's — not yours, don't touch it.

## Out of scope

- D4's actual ruling (which side of the spec `api.mode` defaults to) —
  integrator; you only make invalid values loud and record the conflict.
- D11 (modpack-level integration harness covering the real f02/f05 flows) —
  structural, integrator-owned; you only annotate T4/T5 against it.
- Implementing `push` mode (§4.4 option 2 stays PROPOSED).
- Replacing simulation with a real two-mod integration test in this pass —
  explicitly out; the honest-labelling fix (S5) is the deliverable.
- Any edit to `smp_store` (B1-1) or other features' harness lines beyond
  `test_stats.lua` — P0/their owners.

## Definition of done

1. Every issue ID S1–S7 is either fixed or escalated, with the reason written
   into `spec/features/f14-stats.md §10` (S2 → D4, S5 seam note → D11).
2. `luajit friedcake/dev-tests/test_stats.lua` exits 0 — paste output into
   the PR/branch description, plus the zero-match
   `rg 'register_on_globalstep' friedcake/mods/smp_stats` output.
3. In-mod `smp_stats/test.lua` updated and passing; perf test
   (`test.lua:124-158`) still asserts `< 0.05`.
4. `git checkout -b agent/f14-stats-fixes` from `main`; commit references
   `SPEC-CONFORMANCE-REPORT.md §4 f14` (+ §2 B1 #6); push the **branch**,
   never `main`.
5. PR description carries the issue ID → evidence mapping (S1…S7 →
   `file:line` + commit), and notes to P0 that `test_stats.lua:259` was
   renamed under B4-1 (if you got there first).
6. `fixes/README.md` row `f14` annotated with what closed vs escalated.
