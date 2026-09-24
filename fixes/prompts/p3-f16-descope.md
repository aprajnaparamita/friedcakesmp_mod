# Agent prompt — P3: D8 descope — f16 will never be built (spec-side)

| Field | Value |
|---|---|
| Feature spec | `spec/features/f16-legacy.md`, `spec/features/f06-shards.md` §10, `spec/plan/*`, `spec/README.md`, `spec/shared/02`, `spec/shared/05` |
| Target | documentation only — zero code |
| Audit source | `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D8 |
| Verdict at audit | medium — an unbuilt feature is advertised as scheduled across the plan layer |
| Branch | `agent/rulings-f16-descope` (base: `agent/integrator-decisions`) |
| Wave | 1 — runs in parallel with P1 and P4 |

## Mission

D8 was ruled **harder than "deferred"**: the five legacy mods (`smp_crates`,
`smp_afk`, `smp_teams`, `smp_duels`, `smp_servershop`) will **never be
built** — "never going to be written… no need for legacy mods". Your job is
to make every layer of the spec say *descoped permanently* instead of
*scheduled at P8*, without deleting history: this is a status change, not
book-burning. OBSERVED/LEGACY evidence tags and `[S…]` citations stay exactly
as they are.

The `fixes/` side (brief CANCELLED, README index) was already done by the
integrator — you only touch `spec/`.

## Read this first (in order)

1. `AGENTS.md` — rules 1–8; you are delegated the integrator's write access
   for the files below **only**.
2. `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D8 row (your
   authority and the exact sites).
3. `spec/features/f16-legacy.md` §1–2 (why it exists: features removed from
   Donut before the video — this is why nothing is observed).
4. `SPEC-CONFORMANCE-REPORT.md` §4 f16 (37 MISSING, 0/11 tests — the gaps that
   prompted the scope call).

## Requirements

**R1 — `spec/features/f16-legacy.md` status.**
- Add a banner directly under the `# f16 — …` heading:
  `> **DESCOPED — 2026-09-24 (D8).** These five mods will never be built.` /
  `> Retained as historical documentation of what the reference server had`
  `> before removal. Do not implement.` (blockquote, one short paragraph).
- §1 status table: add/change rows — `Phase` → `n/a (descoped)`; add
  `Status | **DESCOPED** (D8, 2026-09-24) — permanent, not deferred`.
- Do not delete sections; the LEGACY confidence text stays (it explains why
  nothing here is verifiable).

**R2 — close V-61 in `spec/features/f06-shards.md`.**
- `:175` V-61 row: close it —
  `**Closed (D8, 2026-09-24): f16 descoped permanently; no AFK zone will ever`
  `exist. `shards.require_activity` stays read, default false, documented
  inert.**` (keep the original question text in the row).
- Do **not** edit f06 §7 — P2 annotates the `shards.require_activity` row
  (`:134`) in wave 2 with the same citation.

**R3 — `spec/plan/roadmap.md`.**
- `:24` — drop the five f16 mods, keep f08's queue:
  `P8: smp_rtpqueue (f08)` and annotate `# (f16 descoped — D8, 2026-09-24)`.
- `:42` P8 Optional row — deliverables become `RTP queue, API export`; spec
  files `f08 (smp_rtpqueue), f14 (/api)`; acceptance cell: drop the
  `smp_servershop`+`smp_quickbuy` conflict sentence (no servershop will
  exist), keep "Tests per module". Add `f16 descoped (D8)` somewhere in the
  row so the removal is traceable.
- Also fix the phase-graph line ~24 area if the ASCII graph (lines ~1-25)
  names the legacy mods elsewhere in a "will be built" context — annotate,
  don't erase history marks.

**R4 — `spec/plan/acceptance-tests.md`.**
- `:30` f16-legacy row: strike it — keep the row visible with the test column
  emptied/struck and the "what they prove" cell replaced by
  `**Descoped (D8, 2026-09-24)** — f16 will never be built`.
- `:40` X1 "Duplication drill": remove `crate choice` from the menu-path list
  (or annotate it as descoped) — crates will not exist.
- Grep the rest of the file for `crate|duel|team|/shop|f16|legacy` and
  annotate any other in-scope presentation.

**R5 — sweep and annotate (status-type mentions only).**
- `grep -rn 'f16\|legacy' spec/plan/open-questions.md spec/README.md
  spec/shared/02-architecture.md spec/shared/05-command-reference.md` — every
  place that presents f16/mods as planned, scheduled or testable gets a
  `*(f16 descoped — D8, 2026-09-24)*` annotation (or the row struck, where it
  is a deliverable row).
- `spec/shared/06-config-reference.md` — **not yours**: P2 strikes the
  `legacy.*` rows in wave 2. Do not open that file.
- Other feature files (`grep -rln f16 spec/features/` → e.g. f01, f08, f13,
  f14, f15): edit only text that states f16 behaviour as *future work the
  pack will implement*; pure historical citations (`[S11]`, "removed from
  Donut", spawned-area notes like `f16 [S25]`) stay untouched.
- `spec/shared/05-command-reference.md`: annotate legacy command rows
  (`/shop`, crates, teams, duels — grep to find them) as descoped **only
  outside §5.5**; P4 is concurrently adding `/mute`,`/unmute` rows inside
  §5.5. If a legacy row lives inside §5.5, append a short annotation to that
  row only (single-line insert) and mention it in your reply so a merge
  conflict, if any, is trivial.

## Out of scope

- `shared/06` legacy rows → P2. `fixes/**` → done by the integrator.
- Code: `shards.require_activity` keeps being read (`smp_shards` config) —
  documented-inert, not removed; removing the read is nobody's job unless a
  future brief says so.
- Deleting `f16-legacy.md`, roadmap history, or evidence tags — forbidden.

## Tests

- Documentation-only: the full `dev-tests` suite must be green unchanged
  (run it to prove you touched no code).
- Post-condition greps:
  - `grep -n 'DESCOPED' spec/features/f16-legacy.md` → banner + status row
  - `grep -n 'Closed (D8' spec/features/f06-shards.md` → V-61
  - `grep -n 'f16' spec/plan/roadmap.md` → only descoped annotations
  - `grep -n 'f16-legacy' spec/plan/acceptance-tests.md` → struck row only
  - `grep -rn 'P8.*crates\|P8.*teams\|P8.*duels' spec/plan/` → 0 hits

## Constraints

- Files you may write: `spec/features/f16-legacy.md`,
  `spec/features/f06-shards.md` (§10 only), `spec/plan/roadmap.md`,
  `spec/plan/acceptance-tests.md`, `spec/plan/open-questions.md`,
  `spec/README.md`, `spec/shared/02-architecture.md`,
  `spec/shared/05-command-reference.md` (see R5), other feature files **only**
  for the future-tense f16 annotations in R5.
- Never delete OBSERVED/LEGACY evidence tags or `[S…]` citations.
- Everything else → ESCALATE entry + stop.

## Definition of done

1. R1–R5 applied; all post-condition greps pass; suite green.
2. Commit with `D8` in the message; push `agent/rulings-f16-descope`, never
   `main`.
3. Reply with: files touched, every annotated site, and any ESCALATE — plus
   explicitly confirm that `shared/06` was left to P2 and `fixes/` untouched.
