# Fix brief — f08 Teleport, `/rtp`, requests, queue

| Field | Value |
|---|---|
| Feature spec (read-only except §5/§7/§10 rows noted) | `spec/features/f08-teleport.md` |
| Target mod(s) | `smp_tp`, `smp_rtpqueue` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f08 (evidence quoted into the rows below; you do not need to read that report — it describes pre-ruling states) |
| Verdict at audit | **MOSTLY COMPLETE (8 gaps)** · 30 OK · 2 N/A — plus four cosmetic/behaviour deviations and one hand-off row |
| Branch | `agent/f08-teleport-fixes` (created for you from the merged tip) |
| Depends on | `00-P0-blockers` (B2 `core.modpath` — **already fixed on `main`, verify only**), **D7** — **ruled 2026-09-24: D7 = A (mirror + your §7 rows renamed to the real `smp_tp.*` literals by P2 — pre-applied, verify, don't redo; `rtpqueue.separation` is documented as the split `min/max` keys)** — **hand-off from the f11 brief (F11-4): `smp_rtpqueue/init.lua:50` must pair on block-only, not ignore — `smp_social.blocks_only` is being added by the f11 agent; if it is not on your base, record the row in §10 and leave it open (the overseer sequences f08 after f11-finish merges)** |

---

## Mission

`/rtp`, teleport requests and the queue are the pack's most-tested surface
(30 OK at audit), but four of the audited gaps are safety gaps: warm-up and
request cancellation ignore the *other* party's combat tag, world-border
clipping always uses 30000, and RTP landings do not exclude the protected
spawn radius by default — which is exactly the X10 cascade. On top of that a
cancelled warm-up still overwrites `/world`'s origin, four UI strings bypass
the translator, and one formspec line renders a raw invalid UTF-8 byte.
"Fixed" means every cancellation/border rule holds for both parties, `/world`
only records real teleports, the OBSERVED UI stays byte-identical, and the
queue pairs on *blocks* (not ignore) once f11 lands the predicate.

## Read this first (in order)

1. `AGENTS.md` — hard rules (esp. 1, 4, 6–8).
2. `fixes/f08-teleport.md` — this file: the rows below are your task.
3. `fixes/01-integrator-decisions.md` § **Rulings — 2026-09-24** — **D7** only.
   Settled; "but the spec says" loses to it.
4. `spec/features/f08-teleport.md` — your own feature file: §4.1.3, §4.2.3,
   §4.4.6, §4.6 (pearls — spec-deferred), §5 (state schema), §7 (config),
   §8 line 322 (`stay`), §9 (T1–T13), §10 (Q-3 pearls).
5. `spec/shared/` — end to end, READ ONLY (esp. `00-conventions.md §0.5`
   verbatim UI, `06-config-reference.md` the renamed `smp_tp.*` rows,
   `08-ui-strings.md` for the triangle/label glyphs).
6. `spec/plan/acceptance-tests.md` — your row is **line 22: f08-teleport |
   T1–T13** (+ X9 `/tpa` leg line 48, X10 landing leg line 49) — the merge gate.
7. Target mod source (`friedcake/mods/smp_tp/*.lua`, `smp_rtpqueue/*.lua`)
   + `friedcake/dev-tests/test_tp.lua`.

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| TP1 | precondition (B2) | `core.modpath` does not exist — audit says `smp_tp` never loads | report §2 B2 (line 127); `init.lua:19-27` at audit time | Verify the P0 fix landed (engine function is `core.get_modpath(modname)`; call sites use it now) and that no `core.modpath` reference survives in `smp_tp`/`smp_rtpqueue`. **Do not redo** | **ALREADY FIXED on `main`** (B2, `68b5bf5`) — verify only |
| TP2 | §4.1.3 | Tagging **either party** must cancel the warm-up; only the mover is checked, and only at start/fire — the stationary counterparty is never checked, and there is no tag-event hook | mover-only checks at `warmup.lua:93-96` (start) and `:140-143` (fire) | Re-check **both** parties on every tick of the countdown (and at fire): if either is tagged (`smp_combat.is_tagged` when loaded — optional, guard with `type()`), cancel with the existing movement/damage cancellation path and message. Keep the no-yield window and the exact OBSERVED action-bar countdown unchanged | IN-SCOPE |
| TP3 | §4.4.6 | Request must cancel if **either** party is tagged — two bugs: (a) the acceptor-tagged branch refuses **without dropping the request**; (b) a mirror bug clears the partner's **inbox** instead of their **outbox**, so the sender's outbox entry never clears | (a) `requests.lua:173`, `:178-181`; (b) `requests.lua:44` calls `drop_request` where `drop_request_out` is meant | (a) drop the request on the acceptor-tagged refusal (state consistent with die/leave handling `init.lua:34-49`); (b) fix the mirror direction at `:44`. Keep the generic refusal `This player cannot be asked for a teleport` byte-exact | IN-SCOPE |
| TP4 | §4.2.3 | Candidate is clipped to the world border **before** the border is probed — `cfg._border` is assigned from a hardcoded 30000 first, so the clip always uses 30000 | ordering bug `config.lua:137-144` (`core.get_world_border()` probe comes after the assignment) | Probe first, then assign: the real world border governs the clip; unset/no-border keeps 30000 as the documented fallback. Add a test that a non-default world border changes the clip | IN-SCOPE |
| TP5 | §4.2.3 / X10 | RTP landing must exclude the protected spawn radius — the mechanism exists but the key defaults to **0** and `world.spawn_protect_radius` (128, pinned in `minetest.conf.example:53`) is never read, so there is **no exclusion by default** | mechanism `rtp.lua:152,166-169`; key default `config.lua:81`; unread world key | Make the default exclusion real: read `world.spawn_protect_radius` (a `shared/06` world-namespace key — consuming it is fine; you may not edit `f15`'s spec) and use it as the landing exclusion default so X10's `/rtp` leg holds out of the box. Keep any local override key behaviour documented in your own §7 | IN-SCOPE |
| TP6 | §4.6 | Ender pearls — no pearl code anywhere | explicit deferral: `f08` §10 Q-3, `init.lua:61-67` | **Do not build.** The spec defers pearls itself; record in §10 that the deferral stands and that f10's `combat.keep_pearls_on_death` has no consumer until pearls exist (cross-reference `fixes/f10-combat.md`). No pearl code, no keys | **DEFERRED by the spec** (Q-3) — record, stop |
| TP7 | §5 | `state.rtpqueue = {joined_at}` in `smp_tp.state` vs the queue state actually living in `smp_rtpqueue`'s own members table — behaviour unaffected | `smp_tp` state vs `smp_rtpqueue` members | Align the **spec text to the code** (D7/D5 precedent: docs follow code): amend §5 of your feature file to describe where queue state actually lives, note it in §10, keep the OBSERVED queue *behaviour* (5 s countdown, 16–32 apart, 300 s timeout) untouched. §5's state schema is design, not an observation — this is not an OBSERVED downgrade | IN-SCOPE (own file, spec-side) |
| TP8 | §7 / `06:50-63` | Config divergence, three code-side leftovers after P2's mirror rename: (a) `rtp.cooldown` is **never read** from settings — hardcoded table; (b) `rtp.menu_enabled` hardcoded; (c) `rtpqueue.separation` split — verify reads match the mirrored `min/max` keys | (a) hardcoded defaults `config.lua:56-61`; (b) `config.lua:50`; (c) split keys `config.lua:110-111`, cfg fields `:117-118` | Read the keys the mirror now documents (defaults = today's exact values — bare `/rtp` with **no menu** and the 60/30 s cooldowns are Confirmed-OK behaviour and must not shift); document the tier2/tier3 cooldowns as `PROPOSED` rows in your own §7 (they are beyond-spec but implemented) and propose the mirror rows through `## Proposed shared changes`; warn on unknown values. **Keep `dev-tests/test_config_mirror.lua` green** — fix code to match the mirror, never the reverse | IN-SCOPE |
| TP9 | §4.5 `/world` | Origin is recorded at warm-up **start**, so a *cancelled* warm-up still overwrites `last_teleport_from` — `/back`/`/world` then returns the player to where they already are | `warmup.lua` origin write at start (report "cosmetic/behaviour deviations") | Move the origin write to the successful-teleport path only (same place the OBSERVED successful-origin recording is confirmed working); add a test: cancelled warm-up leaves `last_teleport_from` unchanged | IN-SCOPE |
| TP10 | §3 / §0.5 | `formspec.lua:35` renders a lone invalid UTF-8 byte `\241` as the triangle | `formspec.lua:35` | Replace with the correct triangle glyph for the observed UI — take the exact character from `shared/08-ui-strings.md` / your feature file's §3 (never invent: the glyph is part of the OBSERVED surface); assert the byte sequence in a test so it cannot rot back | IN-SCOPE |
| TP11 | §3.2 / AGENTS rule 7 | `Teleport Request` / `Deny` / `Accept` / `Main` are not translated | report §4 f08 cosmetic list | Wrap every one in `S()` at the producer (and any sibling raw labels you find on the same screen — same class, same fix), all through `core.get_translator` | IN-SCOPE |
| TP12 | §8 line 322 | `stay = 20` (20 ticks = 1 s) where §8 specifies `stay = 1` — visibility is correct, literal spec value not implemented | report cosmetic list; `smp_tp` formspec `stay` sites | Determine which side is right **for the observed result**: if `stay = 1` renders the same, implement the literal spec value; if it breaks visibility, amend §8 in your own feature file (docs follow renderer — D5 precedent) with a §10 note. Do not silently keep the divergence | IN-SCOPE (decide + record) |
| TP13 | f11 hand-off (F11-4) | Queue pairing excludes ignore-blockers: `smp_rtpqueue` consults `smp_social.blocks()` (block OR ignore), but ignore must **not** exclude RTP pairing — spec requires mutual-*block* exclusion only | `smp_rtpqueue/init.lua:50` (`smp_tp.bridge.blocks(a,b) or …(b,a)` delegating to `smp_social.blocks` via `smp_tp/bridge.lua:33-37`) | Switch line 50 to the **block-only** predicate `smp_social.blocks_only` that the f11 brief (F11-4) adds. If `blocks_only` is not on your branch yet: record TP13 in `f08` §10 as pending-f11 and stop that row — the overseer sequences f08 after f11-finish merges. **Do not edit `smp_social`** | **DEPENDS (f11 brief)** |

### Preserve exactly (Confirmed OK — byte- and behaviour-identical)

Warm-up countdown on the action bar; movement/damage/tag cancellation for the
mover; per-command tier-reduced cooldowns; bare `/rtp` with no menu; named
regions, ring radius, dimension bands from `mcl_vars`, async `emerge_area`
with remaining-guard; the full safe-y hazard reject list (two free non-liquid
nodes, nether band, end stone only); ≤10 attempts with **no cooldown on
failure**; 60/30 s cooldowns; the 3 s RTP zone at 1 Hz; the whole queue —
toggle, FIFO pairing, 5 s countdown to one safe location 16–32 apart, 300 s
timeout, leave/move/tag exit; one pending request per (sender,target,type)
with 60 s expiry; the single generic refusal `This player cannot be asked
for a teleport`; `tp.confirm_menu` Accept/Deny layout; `/tpauto`; `/spawn`
lobby menu, `/warp`, `/back` off by default. Keep-beyond-spec:
`tier2`/`tier3` cooldowns (now documented PROPOSED — TP8), the `smp_tp.*`
prefix namespace, `spawn_protect_radius` key.

## Acceptance criteria

1. TP2/TP3: a tag on **either** party cancels warm-up and drops the pending
   request — asserted for mover, counterparty, sender and target.
2. TP4: a configured world border changes the landing clip; unset still 30000.
3. TP5: RTP never lands inside the protected spawn radius with default
   config (X10 leg), mechanism asserted both directions.
4. TP9: cancelled warm-up leaves `/world` origin untouched; successful
   teleport updates it.
5. TP10/TP11/TP12: the triangle byte is the spec glyph, the four labels go
   through `S()`, `stay` matches the decided side — all recorded.
6. TP13: queue pairing excludes mutual *blocks* only (pending-f11 recorded
   in §10 if the predicate is absent).
7. TP6/TP7/TP8: deferral, §5 alignment and the config reads are recorded
   with their reasons; `test_config_mirror.lua` stays green.
8. T1–T13 ids intact and green; no OBSERVED string changed by one byte.

## Tests

- `luajit friedcake/dev-tests/test_tp.lua` — must exit 0; add cases for
  TP2 (counterparty tag), TP3a/b (request dropped, outbox cleared), TP4
  (border clip), TP5 (spawn exclusion), TP9 (origin untouched), TP10
  (glyph bytes), TP13 (block-only pairing, skip if `blocks_only` absent).
- In-mod `smp_tp/test.lua` / `smp_rtpqueue/test.lua` — add what the brief's
  DoD needs and AGENTS step 7 requires (create if absent).
- Exact gate (must exit 0, whole suite):
  ```
  for t in friedcake/dev-tests/test_*.lua; do luajit "$t"; done
  ```
  (26 files at dispatch; grows if you add one — `test_config_mirror.lua`
  and `test_engine_apis.lua` must stay green: no engine-absent stub names).

## Constraints

- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — mirror/§7
  proposals flow through `f08-teleport.md` §10 / `## Proposed shared changes`.
- No edits to `smp_core`, `smp_store`, `smp_admin`, `smp_social`,
  `smp_combat`, or any other feature's mod — escalate instead (TP13 is the
  only cross-mod touch and it waits on f11's predicate).
- Money is integer cents; display only via `smp_core.fmt_money`.
- Every player-facing string through `core.get_translator`.
- No yields between validate and mutate in any economic operation.
- Verbatim UI strings character-exact (§0.5); never downgrade an `OBSERVED`
  requirement; invented behaviour stays `PROPOSED`.
- Config keys must match `spec/shared/06-config-reference.md` — propose
  mirror changes, never hand-edit.

## Out of scope

- Ender pearls (TP6 — spec-deferred, Q-3) and K/D-or-gear matchmaking
  (optional/N-A).
- Chat-privacy on requests (PROPOSED, needs f11/f12) — record only.
- Editing `smp_social` to build `blocks_only` — that is f11's row.
- Any change to the queue's OBSERVED pairing/countdown behaviour.

## Definition of done

1. Every issue ID TP1–TP13 is either fixed or has the reason written into
   `spec/features/f08-teleport.md §10` (TP6 deferral, TP13 pending-f11,
   TP7/TP12 spec amendments).
2. Whole dev suite exits 0 (paste the count), including
   `test_config_mirror.lua` and `test_engine_apis.lua`.
3. Your branch `agent/f08-teleport-fixes` (created from the merged tip) is
   clean and committed; attempt one `git push -u origin
   agent/f08-teleport-fixes` — SSH is expected to fail, leave it local.
   **Never push `main`.**
4. Your report maps TP1…TP13 → evidence `file:line` + commit, lists §10
   escalations for the overseer, and states what must be re-verified once
   f11-finish merges (TP13). The overseer annotates `fixes/README.md` — you
   do not edit `fixes/`.
