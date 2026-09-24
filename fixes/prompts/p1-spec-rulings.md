# Agent prompt — P1: land ruling text D1–D6 (spec-side, one code line)

| Field | Value |
|---|---|
| Feature spec | `spec/features/f05-quickbuy.md`, `f02-sell.md`, `f12-settings.md`, `f14-stats.md`, `f07-spawners.md`, `f13-ranks.md` |
| Target | spec text only, plus `friedcake/mods/smp_quickbuy/buy.lua:87` |
| Audit source | `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D1–D6 |
| Verdict at audit | high — six self-contradictions block the f02/f05/f07/f12/f13/f14 briefs |
| Branch | `agent/rulings-spec-text` (base: `agent/integrator-decisions`) |
| Wave | 1 — runs in parallel with P3 and P4 |

## Mission

The integrator ruled D1–D6 on 2026-09-24. Your job is to make the spec say
what was ruled, at the exact sites listed, and make the one line of code D1
requires. Every edit below was already decided — you are a scribe with a
checklist, not a designer. If reality disagrees with an item here, stop and
record an ESCALATE; do not improvise.

## Read this first (in order)

1. `AGENTS.md` — rules 1–8 (ownership, OBSERVED preservation, translator).
2. `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24* (your authority).
3. `spec/README.md:104` and `spec/shared/00-conventions.md §0.5–§0.6` — never
   downgrade an OBSERVED requirement; verbatim UI strings.
4. `SPEC-CONFORMANCE-REPORT.md` §0.5 (first-open screen), §0.6 (money/UI
   strings), §3.4 (the spec-side notes that produced these rulings).

## Requirements

**R1 — D1 (A): race string loses its period.**
- `spec/features/f05-quickbuy.md:194` — inside that sentence, change
  `` `This item was already bought.` `` to `` `This item was already bought` ``
  (drop the terminal period; keep the sentence grammatical).
- `friedcake/mods/smp_quickbuy/buy.lua:87` — `S("This item was already bought.")`
  → `S("This item was already bought")`.
- Check no `.tr`/locale file references the old msgid (there should be none;
  `grep -rn 'already bought\.' --include='*.tr' .`).
- Do **not** touch anything already period-free: `spec/shared/08-ui-strings.md:148`,
  `f03:194`, `f01:65`, `smp_ah/init.lua:169`, `dev-tests/test_ah.lua`.

**R2 — D2 (A): the chat receipt is the design.**
- `spec/features/f02-sell.md` §6, line ~140: the pseudocode calls
  `receipt:show(player)` — a screen that does not exist and will never be
  built. Replace it with the real chat-emitting call: grep
  `friedcake/mods/smp_sell/receipt.lua:164-214` for the function that sends
  the receipt lines to chat, use its name in the pseudocode, and cite
  `receipt.lua:<line>` in an adjacent comment.
- `spec/features/f02-sell.md:186` (V-55): close it —
  `| V-55 | … | **Closed (D2, 2026-09-24): the chat receipt is the design; no formspec receipt. §6 amended.** |`
  (keep the original question text in the row).
- No code change: `smp_sell/receipt.lua` already emits chat lines.
- **Leave V-94 and line 139 (`append_sell_history`) alone** — that seam is
  OPEN-1, not D2.

**R3 — D3 (A): f12 defaults and the categories row.**
- `spec/features/f12-settings.md:140-141` §4.7 item 7: replace the blanket
  "Every setting defaults to its most permissive value except where stated"
  with the implemented truth: the four chat-adjacent settings
  (`chat.private_messages`, `chat.death_messages`, `chat.advancements`,
  `chat.join_leave`) default to `FRIENDS_FOLLOWED` so a fresh profile
  reproduces the observed first-open screen [F0242] (§0.5 fidelity); every
  other setting defaults to its most permissive value (`ON`). Keep a
  `PROPOSED` tag only on the "rest default ON" half if you must — the four
  `FRIENDS_FOLLOWED` rows are settled by this ruling.
- `spec/features/f12-settings.md:~178` — the
  `smp_settings.register("chat.private_messages", …)` sample in §5.1: set its
  `default` field to `FRIENDS_FOLLOWED` so sample, schema (`:152-157`) and
  code agree.
- `spec/features/f12-settings.md:205` §7 — **strike** the
  `| \`settings.categories\` | … |` row. Before striking, verify the seven
  categories in observed order are documented in §4 prose with their
  OBSERVED [F0237] tag; if the §7 row was the only place the fact appears,
  move that sentence into §4 first. Striking a *config-key claim* is not a
  downgrade — losing the *fact* would be.
- Annotate as decided 2026-09-24: F12-B (`:249`), F12-C (`:250`), and the
  `:302` open-question bullet (append "— decided: D3, §4.7 rewritten, row
  struck" or equivalent; keep the original text visible).

**R4 — D4: f14 `api.mode` default.**
- `spec/features/f14-stats.md:187` — default cell `off` → `snapshot`; keep the
  options cell `(`off`, `snapshot`, `push`)`.
- Annotate F14-D5 (`:237`) and the §10 bullet (`:257`) as resolved 2026-09-24
  (§7 now says `snapshot`; code was already `snapshot`, `smp_stats/init.lua:43-50`).
- Do not touch code.

**R5 — D5: f07 text follows the renderer.**
- `spec/features/f07-spawners.md:34` (§3 sketch): `Page 1/5` → `Page 1 of 5`.
- `spec/features/f07-spawners.md:129` (§4.6.3): ``Header `<Type> Spawner ×n` ``
  → ``Header `<Type> Spawner x<n>` `` — V-01's exact spelling (`:262`); the
  code renders `x128`.
- Leave `×` at `:33` (grid `5 × 9`) and `:76,99,102` (formulas) — those are
  not UI strings. V-01 (`:262`) and §5's string list (`:292`) already conform.
- Post-check: `grep -n 'Page 1/5\|×n' spec/features/f07-spawners.md` → 0 hits.

**R6 — D6: `mark_dirty` is a phantom.**
- `spec/features/f13-ranks.md:114`: `smp_store.mark_dirty("players", name)` →
  `smp_store.api.upsert_player(rec)` (single read-modify-write, no yields —
  the pattern already used at `smp_ranks/grant.lua:38`).
- Post-check: `grep -rn 'mark_dirty' spec/` → 0 hits; if another file
  surfaces, fix it the same way (it is in scope for this ruling).

## Out of scope

- **§7 table alignment and everything `spec/shared/06-config-reference.md`** →
  P2 (including the mirror half of D3). Do not edit any §7 table except the
  D3 strike and D4 default above.
- f16/V-61/plan files → P3. `smp_admin`/tests → P4. Harness → P5.
- `fixes/**` — already annotated by the integrator.
- Consumer wiring (f01's `/pay` flag call, f11's mute honesty) → their briefs.

## Tests

- Full suite green: every `friedcake/dev-tests/test_*.lua` exits 0. These are
  text edits plus one msgid, but run everything — `test_quickbuy` and
  `test_ah` are the canaries for R1.
- Post-condition greps (all must hold):
  - `grep -rn 'already bought\.' spec/features/ friedcake/mods/` → 0
  - `grep -rn 'mark_dirty' spec/` → 0
  - `grep -n 'Page 1/5\|×n' spec/features/f07-spawners.md` → 0
  - `grep -n '| `api.mode` | `off`' spec/features/f14-stats.md` → 0
  - `grep -n 'settings.categories' spec/features/f12-settings.md` → prose/§10 only, no §7 row

## Constraints

- Money integer cents; strings through `core.get_translator`; no yields in
  economic paths (you have no code paths that qualify beyond R1's msgid).
- Never downgrade an OBSERVED row — R3's strike moves structure out of a
  config table, the OBSERVED fact itself must survive in §4.
- Files you may write, and only these:
  `spec/features/f05-quickbuy.md`, `spec/features/f02-sell.md`,
  `spec/features/f12-settings.md`, `spec/features/f14-stats.md`,
  `spec/features/f07-spawners.md`, `spec/features/f13-ranks.md`,
  `friedcake/mods/smp_quickbuy/buy.lua`.

## Definition of done

1. R1–R6 applied at the cited lines; post-condition greps all pass.
2. Full dev suite green.
3. Commit with the D-IDs in the message; push `agent/rulings-spec-text`,
   never `main`.
4. Reply with a per-requirement table (R1–R6 → line changed → pass) and any
   ESCALATE you recorded.
