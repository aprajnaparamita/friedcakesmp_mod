# Fix brief — f02 Sell

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f02-sell.md` |
| Target mod(s) | `smp_sell` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f02 |
| Verdict at audit | MOSTLY COMPLETE (2 gaps) · 37/39 OK · T1–T10 green |
| Branch | `agent/f02-sell-fixes` |
| Depends on | `00-P0-blockers.md` B4-1 (harness shims — note only, do not re-specify); `01-integrator-decisions.md` **D2** (receipt screen), **D7** (config mirror); an integrator ruling on the sell-history seam (no D-ID — proposed in `f02 §11`) |

---

## Mission

The mod is otherwise the strongest in the pack: every observed UI element, all
four commands, routing, shulker handling and all ten acceptance tests pass. The
two open gaps are both **§6 mechanism replacements** that cross an ownership
seam: sell history lives in `smp_sell`'s own mod storage instead of a
`smp_store` table (declared as V-94), and the §6 `receipt:show(player)` receipt
screen was never built — chat lines stand in (undeclared, V-55 open). Neither is
yours to decide: both need integrator rulings (D2 for the receipt; the
store-history seam must be either commissioned or ratified). "Fixed" means: the
rulings are implemented exactly as issued — or, if they have not landed, both
seams are recorded in the feature file and **zero regressions** occur while you
wait. Consequence of getting this wrong: silently losing the two declared
exceptions, or regressing the only fully-green suite in the audit.

## Read this first (in order)

1. `AGENTS.md` — hard rules 1–8.
2. `spec/features/f02-sell.md` — end to end, especially §6 (lines 112–141),
   §7 (146–152), §9 (165–178), §10 V-55/V-94 (186, 195) and §11 (197–228).
3. `spec/shared/02-architecture.md` (§2.2 persistence, §2.3 no yields),
   `04-ui-kit.md` (container grammar), `05-command-reference.md`,
   `06-config-reference.md`, `08-ui-strings.md` (READ ONLY — `Sell` at :22,
   `Confirm\nClick to sell items` at :40).
4. `spec/plan/acceptance-tests.md` — f02 row (T1–T10) is the merge gate.
5. `SPEC-CONFORMANCE-REPORT.md` §4 — f02 (lines 252–276), plus §2/§3.3 for
   the blocker context.
6. `friedcake/mods/smp_sell/` source + `friedcake/dev-tests/test_sell.lua`
   (2,001 lines) + `friedcake/mods/smp_sell/test.lua` (599 lines, 64
   assertions).

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| F02-1 | f02 §6 line 139 (`smp_store.append_sell_history`), shared §2.2, V-94 | Sell history lives in `smp_sell`'s own mod-storage namespace instead of a `smp_store` table. Declared (V-94) with the API proposed in `f02 §11.1`, but the §6 pseudocode and the code still disagree | `friedcake/mods/smp_sell/history.lua:43-59` (`H._read`/`H._write`), `:101-117` (`H.append` → `_write` at 117); proposal at `spec/features/f02-sell.md:202-207` | Present **both** options to the integrator and stop: **(A)** commission `smp_store.api.append_sell_history(name, entry) -> id` + `sell_history_for(name, page, size)` per f02 §11.1 — `smp_store` is integrator-owned (AGENTS rule 4) — then switch `history.lua` to it; **(B)** ratify V-94 as-is and have §6 amended to name the local seam. Either way **the seam must be recorded** in §10/§11 of `spec/features/f02-sell.md` (your feature file) with the ruling's ID. No behaviour change until ruled | **ESCALATE (integrator)** |
| F02-2 | f02 §6 line 140 (`receipt:show(player)`), V-55 (`f02:186`) | The receipt screen was never implemented; the mod emits bounded chat lines instead | `friedcake/mods/smp_sell/receipt.lua:164-214` (`self:messages`); V-55 open at `spec/features/f02-sell.md:186` | Wait for **D2** (`fixes/01-integrator-decisions.md`): Option A closes V-55 as "chat receipt is the design" and amends §6 (no code change); Option B requires a formspec receipt (~1 screen) — build it only if ruled. Record the outcome in §10 V-55 | **ESCALATE → D2** |
| F02-3 | f02 §7 line 152 (`sell.base_prices`), shared/06 mirror | `sell.base_prices` is read by the code but is absent from `spec/shared/06-config-reference.md` (grep = 0 matches) — one of the keys **D7** exists to reconcile | `friedcake/mods/smp_sell/init.lua:94` (`cfg.base_prices_path = get_str("sell.base_prices", "")`); mirror absence verified by grep | Propose the mirror row through your own feature file (§11/§10) and point it at **D7**; never hand-edit `shared/06` (AGENTS rule 1). Code stays as-is | **ESCALATE → D7** |
| F02-4 | — (test harness) | The dev-test suite stubs `core.register_on_globalstep`, masking the B1 load blocker — green tests give false assurance until `00` lands | `friedcake/dev-tests/test_sell.lua:685` (`register_on_globalstep = function(f) …`) | Do **not** re-specify — fixed by `fixes/00-P0-blockers.md` B4-1. Re-run your suite after that brief lands and confirm it is still green with the shim deleted | **DEPENDS-BLOCKER (B4-1)** |

**Status of everything else:** 37/39 audited rows are `OK` and must stay OK.
Nothing else in f02 is a gap.

## Preserve (do not regress)

All of the following were verified verbatim/OK at audit; each is an acceptance
criterion in its own right:

- Container titled exactly `Sell` (OBSERVED, `shared/08:22`).
- 9×5 grid — 44 drop slots + lime confirm pane in the bottom-right cell, with
  `Confirm\nClick to sell items` (`shared/08:40`) and the `Inventory` label
  under it.
- Routing order: better-paying orders first, highest order price first,
  remainder to the server (`sell.lua:92-114`).
- Shulker handling: eligible contents sold, box returned holding ineligible
  items, same codec (`compressed` / empty key).
- `/sell` allowed while combat-tagged.
- 100-entry history (`sell.history_size` default), `money_made_from_sell`
  counts **both** server and order proceeds.
- No-loss paths: disconnect return-before-save (R6), close-without-confirm,
  full-inventory drop-at-feet (T8), crash-safe container mirror + join
  recovery (T7b).
- Every key in f02 §7 (`sell.mode`, `sell.multiplier`, `sell.history_size`,
  `sell.meta_exempt`, `sell.base_prices`).
- All ten acceptance tests T1–T10 **plus the crash-mirror T7b**
  (`test_sell.lua:1414-1440`) stay green.

## Beyond spec — keep, but declare

Keep these behaviours; they are already surfaced in the feature file — do not
delete them and do not pretend they are spec'd:

- `sell.history_page_size` (`init.lua:92`), `sell.receipt_max_lines`
  (`init.lua:93`) — undeclared keys → declare in f02 §7, mirror row → D7.
- Extra `id`/`source` history fields (V-90) — additive to §5.
- Crash-safe container mirror + join recovery (stronger than R6 requires).
- `/sellreload` (`init.lua:559`).
- `store.max_balance` fallback key (`init.lua:96`, behind
  `economy.max_balance`).
- **ESCALATE → D7** for `sell.base_prices` missing from `shared/06` (F02-3).

## Acceptance criteria

1. **F02-4:** after `00-P0-blockers.md` lands, `luajit
   friedcake/dev-tests/test_sell.lua` exits 0 with the
   `register_on_globalstep` shim gone; `rg 'register_on_globalstep'
   friedcake/dev-tests/test_sell.lua friedcake/mods/smp_sell` returns 0.
2. **F02-1:** the seam is recorded either way — a dated ruling exists in
   `fixes/01-integrator-decisions.md` / the integrator's reply, echoed in §10
   or §11 of `spec/features/f02-sell.md`. If Option A: `history.lua` reads and
   writes through `smp_store` and a dev-test asserts history survives via the
   store API. If Option B: code unchanged, V-94 stays declared, §6 amended by
   the integrator.
3. **F02-2:** D2's ruling is recorded against V-55. Option A: no code change,
   §6 amended. Option B: a receipt screen opens on sale and a test asserts it,
   while the chat fallback is removed or kept only as ruled.
4. **F02-3:** `sell.base_prices` appears as a proposal in your feature file
   pointing at D7; `shared/06` itself is untouched by you.
5. **Preserve:** all items in "Preserve (do not regress)" still hold — every
   one of them has a passing assertion in `test_sell.lua` before and after your
   work (add any assertion that is currently missing rather than removing a
   behaviour).

## Tests

- Dev-test: `luajit friedcake/dev-tests/test_sell.lua` — **must exit 0**
  (verified green on 2026-09-23: `ALL OK`). T1–T10 and T7b must remain.
- Additions per ruling:
  - If F02-1 Option A lands: a case that appends history, "restarts" the
    mod (reload `history.lua` consumer state), and reads the entry back
    through `smp_store`.
  - If F02-2 Option B lands: a case that opens the receipt screen after a
    mixed sale (server + order + returned lines) and asserts its contents.
  - Keep the T7b crash-mirror test untouched.
- In-mod: update `friedcake/mods/smp_sell/test.lua` (64 assertions) so any
  behaviour you touch is covered there too; `/smp test smp_sell` must pass.

## Constraints

- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — propose through
  your own feature file (`## Proposed shared changes` / §10), never hand-edit.
- No edits to `smp_core`, `smp_store`, `smp_admin` (AGENTS rule 4) — the
  store-history API in F02-1 is an escalation, not a task.
- One agent per feature file: do not touch any mod outside `smp_sell`;
  cross-mod seams (f04 routing, f07 Sell-all caller) are propose-only.
- Money is integer cents, always rendered with `smp_core.fmt_money`; floats
  forbidden for money.
- All player-facing strings via `core.get_translator`.
- No yields between validate and mutate in any economic operation (shared §2.3).
- Verbatim UI strings character-exact — `Sell`, `Confirm\nClick to sell items`,
  `Inventory` are frozen.
- Config keys must match `shared/06` — propose mirror changes (D7), never
  hand-edit the mirror.
- Never downgrade an `OBSERVED` requirement.
- One agent owns `spec/features/f02-sell.md` — that is you; do not touch other
  features' spec files.

## Out of scope

- Behavioural refactors of eligibility, routing, shulkers or the detached
  inventory — all audited OK.
- Other open questions in §10 (V-54, V-56, V-88–V-93) — not part of the two
  declared gaps; record new discoveries in §10 instead of acting.
- Anything in `00-P0-blockers.md` (B1/B4) — owned by that brief.
- Receipt/history work beyond whatever D2 / the store-API ruling actually
  specifies.

## Definition of done

1. Every issue ID (F02-1…F02-4) is either **fixed** or **escalated with a
   written reason and a named decision/integrator target** — no silent drops.
2. `luajit friedcake/dev-tests/test_sell.lua` exits 0; in-mod
   `smp_sell/test.lua` updated and green.
3. `git checkout -b agent/f02-sell-fixes` from `main`; commit referencing
   `SPEC-CONFORMANCE-REPORT.md §4 f02`; push the **branch, never `main`**.
4. Issue ID → evidence mapping present in the commit/PR description
   (F02-1 → `history.lua:43-59,101-117`; F02-2 → `receipt.lua:164-214` +
   D2; F02-3 → `init.lua:94` + D7; F02-4 → `test_sell.lua:685` + 00/B4-1).
5. `fixes/README.md`'s f02 row may be updated to ✅ only when both escalations
   have landed rulings (note "pending D2/D7/integrator" otherwise).
