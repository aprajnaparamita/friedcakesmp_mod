# Fix brief — f11 Social

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f11-social.md` |
| Target mod(s) | `smp_social` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f11 |
| Verdict at audit | **MOSTLY COMPLETE (5 gaps)** · ~27 OK · **0/10 tests** |
| Branch | `agent/f11-social-fixes` |
| Depends on | `00-P0-blockers` (in-game verification only); **D10** (mute producer, `01-integrator-decisions.md`); cross-references `fixes/f01-economy-core.md` and `fixes/f08-teleport.md` — **ruled 2026-09-24: D10 = A (`smp_admin.mute`/`unmute`/`is_muted` + `/mute`,`/unmute` built by P4 — the probe at `bridges.lua:97-104` works as written; your F11-5 honesty/TODO cleanup is still your row), D7 = A (P2)** |

---

## Mission

The implementation of the OBSERVED surface is faithful — all three
frame-evidenced strings, all 13 §2 command rows and the §6 pseudocode verify
character-exact — but **the feature has zero executable tests**. There is no
`friedcake/dev-tests/test_social*.lua` and no `mods/smp_social/test.lua`
(AGENTS step 7 violation), so the P7 roadmap gate ("the observed chat format,
`/msg` refusal … reproduced", `roadmap.md`, P7 row) is true **by code inspection
only**: nothing executes it. Close that first, then fix three §4.3/§4.1.3
behaviour gaps and the raw-string (i18n) debt. "Fixed" means all ten §9
acceptance tests run green under `luajit`, the block/ignore predicate split is
real and honestly documented, and every gap you cannot close yourself is
escalated with an ID — a regression in the best-attested strings in the corpus
must never again be invisible to the test suite.

## Read this first (in order)

1. `AGENTS.md` — hard rules 1–8.
2. `spec/features/f11-social.md` — §4.3 (effect table), §6 (send_pm), §7
   (config), §9 (T1–T10), §10 (open questions — you own this table).
3. `spec/shared/02-architecture.md`, `04-ui-kit.md`, `05-command-reference.md`
   (your 13 command rows), `06-config-reference.md`, `08-ui-strings.md`
   (READ ONLY — propose, never hand-edit).
4. `spec/plan/acceptance-tests.md:25` — f11's T1–T10 row is the merge gate;
   `:48` X9 (privacy cascade) names your `/pay` leg.
5. `SPEC-CONFORMANCE-REPORT.md` §4 f11 (lines 582–621).
6. `friedcake/mods/smp_social/` (13 files, **no `test.lua`**) +
   the harness model `friedcake/dev-tests/test_settings.lua` (517 lines —
   real `register_on_player_receive_fields` over a `core` stub at `:204`).

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| F11-1 | §9 | **All ten acceptance tests MISSING (highest priority).** No dev-test, no in-mod `test.lua` — AGENTS step 7 violation. T1–T10 exist on paper only | glob `dev-tests/test_social*` → none; `ls mods/smp_social/` → 13 files, no `test.lua`; report §4 f11 row 5 | Create `friedcake/dev-tests/test_social.lua` covering **T1–T10** (spec `f11:262-271`): T1 chat renders `<Name> message` with no prefix; T2 `Public Chat: OFF` recipient gets nothing; T3 stranger `/msg` → exact refusal, nothing delivered; T4 `/msg` to friend delivered; T5 ignored sender gets the **same** refusal; T6 `/ignore` suppresses chat + PMs + tpa; T7 TPA hint line follows the public message; T8 unknown command exact `This command does not exist`; T9 `/findplayer` never returns exact coordinates; T10 mutual follows = friends, one-way ≠. Model the harness on `dev-tests/test_settings.lua` (real receive-fields path over a `core` stub; do **not** stub engine functions that don't exist — see `00-P0-blockers.md` B4). Also add the in-mod `mods/smp_social/test.lua`. **This file also hosts f12's T9 leg — coordinate so `fixes/f12-settings.md`'s T9 row points at your new file** (do not build a second harness) | **DONE — merged 2026-09-24** (`dev-tests/test_social.lua` T1–T10 + in-mod `test.lua`, from `agent/f11-social`; suite 26/26). **Verify/extend only, do not rebuild** |
| F11-2 | §4.3 (payments row) | Block refuses **payments** — MISSING (`PROPOSED` row). `/pay` never consults the list; leaves cross-cutting X9's `/pay` leg (`acceptance-tests.md:48`) unimplemented | grep `smp_social\|blocks(` in `friedcake/mods/smp_economy/` → **zero** matches; wire-up site is `smp_economy/init.lua:183-233` (`/pay` command) — **f01's mod, not yours** | Specify the contract on your side: `smp_social.blocks(a, b)` already exists at `smp_social/graph.lua:112` (semantics: block OR ignore, both directions at the call site). Record the hand-off in §10 of `spec/features/f11-social.md` and reference `fixes/f01-economy-core.md`. Test **your** side of the contract in `test_social.lua` (stub-consumer call proving `blocks()` answers true for a blocker and false otherwise). **Do not edit `smp_economy`** | **ESCALATE → f01 brief** (`fixes/f01-economy-core.md`) + IN-SCOPE (contract test, §10 entry) |
| F11-3 | §4.3 (follows row) | Block refuses **follows** — MISSING (`PROPOSED` row). `follow()` checks self/existing/limit only | `smp_social/friends.lua:40-74` (`function smp_social.follow` at `:40`) — no block check | Add the block check to `follow()` **both directions** (refuse if either side blocks the other), with a refusal message in the `generic_refusal` style, plus a test case in `test_social.lua` | **IN-SCOPE** |
| F11-4 | §4.3 (RTP-pairing row) | Ignore must **NOT** exclude from RTP-queue pairing, but does. `graph.lua` folds ignore into `blocks()`, which `smp_rtpqueue` uses for pairing. The code comment claims the contradiction is "recorded in §10" — **f11 §10 contains no such entry, so that claim is false** | `smp_social/graph.lua:106-111` (comment; the false §10 claim at `:111`), `graph.lua:112-114` (`blocks()` = `is_blocked or ignores`); consumer `smp_rtpqueue/init.lua:50` (`smp_tp.bridge.blocks(a,b) or smp_tp.bridge.blocks(b,a)`, which delegates to `smp_social.blocks` via `smp_tp/bridge.lua:33-37`) | Expose a **block-only** predicate from `graph.lua` (e.g. `smp_social.blocks_only(a, b)`) separate from `blocks()`. Keep `blocks()`'s current semantics (block OR ignore) for payments/follows and everything else that consults it today — the only consumer that must switch is RTP pairing. Record the real decision in `f11-social.md` §10 (replacing the comment's false claim; tie it to V-48). **ESCALATE the one-line switch in `smp_rtpqueue/init.lua:50` to the f08 brief** (`fixes/f08-teleport.md`) — `smp_rtpqueue` is not your mod | **IN-SCOPE** (`graph.lua`, §10) + **ESCALATE → f08 brief** (`smp_rtpqueue/init.lua:50`) |
| F11-5 | §4.1.3 | Mutes PARTIAL / inert. Enforcement hook exists but **no mute producer exists anywhere** — the bridge always returns false | `smp_social/chat.lua:94-97` (hook), `smp_social/bridges.lua:97-104` (`is_muted` probes `smp_admin.is_muted`, `TODO(admin)` at `:103`); grep `mute\|is_muted` across `friedcake/mods/` outside `smp_social` → **zero**; `smp_admin` → zero. `smp_admin` is integrator-owned (AGENTS rule 4) | **ESCALATE → D10** (`01-integrator-decisions.md`: add a mute API to `smp_admin`, or amend f11 §4.1.3 to enforcement-only-until-moderation-tooling). Meanwhile, make the inert state **honest**: warn at load when a mute is enforced but no producer can exist, or gate the hook behind a capability check — no silent dead code. Keep the contract tested with a **stub producer** (define `smp_admin.is_muted` in the harness and assert the `You are muted` path fires) | **ESCALATE → D10** + IN-SCOPE (honesty + stub test) |
| F11-6 | §2 (tab completion) | Tab completion of player names after `/msg`, `/pay`, `/ignore` — **N/A, record it and stop** | Luanti has no server-driven argument-completion API (verified against the engine docs); spec `f11:30-31` records the observation, proposes no substitute | **Do nothing.** Write an explicit N/A note (in §10 of your feature file or the PR) so a fixing agent does not invent a client-side completion hack | **N/A** |
| F11-7 | AGENTS rule 7 | Raw player-facing strings (must go through `core.get_translator`) | `findplayer.lua:21-26` (`DIMENSION_NAMES` values), `:43-47` (sector names `South/North/East/West/Center`), `:63` (raw `"Overworld"` fallback), `:75` (`return "Spawn"`), `:77` (raw `" – "` composition); `kill.lua:24-25` formspec labels `Kill` / `Are you sure you want to kill yourself?` (buttons at `:27-28` also raw); `info.lua:119` screen title `Help`, `:131-171` titles `Rules`, `Discord`, `Media`, `Link`, `Store`, `Website`, `Ranks`, `Medal` (rendered raw via `formspec_escape` at `info.lua:53`) | Wrap every one in `S()` at the producer (dimension/region/sector names and `Spawn` become translated strings before they reach the `S("Location: @1", …)` label at `info`-style call sites; titles passed through `show_formspec`) | **ALREADY FIXED on `main`** — verified 2026-09-24 (`87c0eae`; e.g. `findplayer.lua:22` wraps names in `S()`; `STATUS.md` §3). **Verify, do not redo** |
| F11-8 | §7 | Config keys beyond spec, currently undeclared — declare or strike | `smp_social/init.lua:70-71` (`findplayer.spawn_radius` default 512, `findplayer.region_band` default 2048); `info.lua:120` (`info.help`) and `:130,136,141,146,151,156,164,170` (`info.rules/discord/media/link/store/website/ranks/medal`) | Add these as `PROPOSED`/beyond-spec rows to **your own** `f11-social.md` §7 (you own that file), and add a `## Proposed shared changes` entry proposing the mirror rows for `shared/06` under **D7** (config mirror reconciliation). Do not hand-edit `shared/06` | ✅ **DONE — merged 2026-09-24** — §7 rows landed with `agent/f11-social`; mirror rows present in `shared/06:119-123` (D7/P2 + the f11-merge split). **Verify only** |

## Acceptance criteria

1. `luajit friedcake/dev-tests/test_social.lua` exits **0** and every §9 test
   T1–T10 maps to at least one named assertion (print the T-id per case, like
   `test_settings.lua` does).
2. `friedcake/mods/smp_social/test.lua` exists (AGENTS step 7) and covers the
   same contract in-mod.
3. f12's T9 leg (stranger `/msg` under `Private Messages: Friends/Followed`
   returns the exact observed refusal) is asserted inside `test_social.lua`,
   and `fixes/f12-settings.md`'s T9 row can point at it — one harness, not two.
4. `follow()` refuses a block in both directions (test: A blocks B → B cannot
   follow A, A cannot follow B) — F11-3.
5. `smp_social.blocks_only(a, b)` exists, is block-graph-only; `blocks()`
   unchanged; `graph.lua`'s false "recorded in §10" claim replaced by a real
   §10 entry; the `smp_rtpqueue/init.lua:50` switch recorded in §10 pointing at
   `fixes/f08-teleport.md` — F11-4.
6. D10 escalation recorded in §10; the mute path warns (or capability-gates) at
   load when no producer exists; a stub `smp_admin.is_muted` test proves the
   enforcement hook end-to-end — F11-5.
7. Tab completion documented as N/A with the reason; no completion hack
   anywhere — F11-6.
8. `grep` for raw strings returns clean: every title/label/sector name found in
   F11-7's table is now behind `S()` — F11-7.
9. §7 declares (or explicitly strikes) all beyond-spec keys; the mirror
   proposal exists under `## Proposed shared changes` — F11-8.
10. **No regression in the preserved surface** (see Constraints): the three
    OBSERVED strings still match character-for-character, and every previously
    green dev-test suite still exits 0.

## Tests

- **New:** `friedcake/dev-tests/test_social.lua` — T1–T10 (spec §9) plus the
  F11-3 block-follow case, the F11-5 stub-producer mute case, the F11-2
  `blocks()` contract case, and the f12 T9 leg. Harness model:
  `dev-tests/test_settings.lua` (real callback path over a `core` stub).
- **New:** `friedcake/mods/smp_social/test.lua` — in-mod mirror of the above.
- Exact commands (must exit 0):

```sh
luajit friedcake/dev-tests/test_social.lua      # exit 0 — the new gate
luajit friedcake/dev-tests/test_settings.lua    # still exit 0 (f12 seam, T1–T8)
luajit friedcake/dev-tests/test_settings.lua && luajit friedcake/dev-tests/test_social.lua  # both green
```

- Also re-run any suites that touch seams you changed (`test_tp`, `test_economy`
  if the f01 hand-off lands later) — they must stay green.

## Constraints

- **No edits** to `spec/shared/`, `spec/plan/`, `spec/README.md`. Propose
  mirror/string changes under `## Proposed shared changes` in `f11-social.md`.
- **No edits** to `smp_core`, `smp_store`, `smp_admin` (AGENTS rule 4) or to
  another feature's mod — `smp_economy` (F11-2) and `smp_rtpqueue` (F11-4) are
  escalations, not tasks. Cross-mod seams are propose-only.
- **One agent per feature file** — do not touch f08's/f01's/f12's mods; your
  only spec-file edits are your own `spec/features/f11-social.md` (§7
  declarations, §10 entries) as AGENTS.md permits.
- Money is integer cents via `smp_core.fmt_money` (no money code here, but the
  `/pay` contract test must not invent floats).
- All player-facing strings through `core.get_translator` (rule 7) — F11-7.
- No yields between validate and mutate in any economic operation
  (`shared/02 §2.3`) — the broadcast pass in `chat.lua:48-60` already documents
  this; keep it synchronous.
- **Verbatim UI strings character-exact — preserve exactly:**
  - chat format `<@1> @2` with **no** rank prefix by default;
  - the `/msg` refusal `This user only accepts messages from friends or followed players`;
  - the TPA hint `Click to send @1 a teleport request` as a plain second line;
  - `This command does not exist`;
  - `generic_refusal()` structural identity between the ignore and privacy
    paths (T5 depends on it);
  - every §2 command row and alias vs `shared/05` (13 command groups);
  - all seven §7 keys and their defaults.
- Config keys must match `shared/06` — propose mirror changes (D7), never
  hand-edit the mirror.
- Never downgrade an `OBSERVED` requirement.
- Harness rule (from B4): never stub an engine API that does not exist — the
  tests must fail if a `core.*` name the engine lacks reappears.

## Out of scope

- Editing `smp_economy`'s `/pay` body (F11-2) and `smp_rtpqueue`'s pairing
  predicate (F11-4) — specified here, implemented under `fixes/f01-economy-core.md`
  and `fixes/f08-teleport.md`.
- Providing the `smp_admin` mute API — D10, integrator-owned.
- `shared/06` mirror rows — D7, integrator-owned.
- The rank-prefix question (V-24), voice chat (§4.8 N/A), and anything in
  f12's category screens.
- Inventing tab-completion or any client-side chat decoration.

## Definition of done

1. Every issue ID F11-1 … F11-8 is either **fixed** (with the file:line
   evidence of the fix) or **escalated with a reason and a target**
   (F11-2 → `fixes/f01-economy-core.md` + §10; F11-4 consumer →
   `fixes/f08-teleport.md` + §10; F11-5 → D10 in §10; F11-8 mirror → D7) —
   no ID silently dropped, no status softened.
2. `luajit friedcake/dev-tests/test_social.lua` exits 0; `test_settings.lua`
   and the rest of the suite still exit 0; in-mod `test.lua` added.
3. `git checkout -b agent/f11-social-fixes` from `main`; commit message
   references `SPEC-CONFORMANCE-REPORT.md §4 f11`; push the **branch**, never
   `main`.
4. Issue ID → evidence mapping in the PR/branch description: each F11-* ID with
   the test case name or `fixes/`/§10 entry that closes it.
5. Announce the new harness to the f12 agent: their T9 now lives in
   `test_social.lua`.
