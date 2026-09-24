# Fix brief — f13 Ranks and membership

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f13-ranks.md` |
| Target mod(s) | `smp_ranks` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f13 (lines 658–676) |
| Verdict at audit | **MOSTLY COMPLETE (2 gaps)** — the mod itself is clean; both gaps are consumers bypassing the rank API · 1 spec-side N/A · T1–T8 green (76 checks, integration halves owned externally) |
| Branch | `agent/f13-ranks-fixes` |
| Depends on | `01-integrator-decisions.md` **D6**; hand-offs to `fixes/f04-orders.md` and `fixes/f08-teleport.md`; `00-P0-blockers.md` B4-1 owns the `test_ranks.lua:254` shim (do not touch) — **ruled 2026-09-24: D6 = A (`smp_store.mark_dirty` struck; §6 now names `smp_store.api.upsert_player(rec)`, applied by P1 — no `smp_store` API will be added)** |

---

## Mission

`spec/features/f13-ranks.md` was audited as clean — no defects in
`smp_ranks` itself. The two gaps are **other features' mods reading the rank
record directly instead of the perk API**: `smp_orders` ignores `expires_at`
(so an expired tier1 still grants 45 order slots), and `smp_tp` reads its own
cooldown table instead of `smp_ranks.rtp_cooldown`. The consumer edits belong
to the f04 and f08 briefs; your job is coordination: specify the exact API
contract those consumers must call, add an `smp_ranks`-side test that pins the
contract down, and record both hand-offs in §10 of your feature file — plus
flag the spec-side `mark_dirty` phantom (D6). Player consequence today: rank
perks leak past expiry in orders, and `/rtp` cooldown truth is duplicated in
two places.

## Read this first (in order)

1. `AGENTS.md` — hard rules 1–8.
2. `spec/features/f13-ranks.md` — §4.2.4 (perk API, lines 60–64), §5
   (schema), §6 (pseudocode incl. the phantom at line 114), §7 (config),
   §8, §9 (T1–T8), §10, §11.1 (API signatures), §11.3 (cross-mod findings,
   lines 225–232), `## Proposed shared changes`.
3. `spec/shared/02-architecture.md`, `04-ui-kit.md`, `05-command-reference.md`,
   `06-config-reference.md`, `08-ui-strings.md` — **READ ONLY**.
4. `spec/plan/acceptance-tests.md` — your row is the merge gate:
   `f13-ranks` (line 27, T1–T8).
5. `SPEC-CONFORMANCE-REPORT.md` §4 f13 (lines 658–676) and §5 row f13
   (line 805).
6. The target mod source (`friedcake/mods/smp_ranks/` — `init.lua`,
   `perk.lua`, `grant.lua`, `expiry.lua`, `formspec.lua`, `tiers.lua`,
   `test.lua`) + `friedcake/dev-tests/test_ranks.lua`. Also read the two
   consumer sites you are documenting but **must not edit**:
   `friedcake/mods/smp_orders/orders.lua:200-210` and
   `friedcake/mods/smp_tp/rtp.lua:178-186`.

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| R-01 | f13 §4.2.4 (`f13:60-64`), §11.3.2 (`f13:229-232`) | A consumer reads `rec.rank` directly and ignores `expires_at` — an expired tier1 keeps 45 order slots (lazy-expiry bug + §4.2.4 violation) | `smp_orders/orders.lua:204-206` (`smp_orders.slot_limit` takes `rec.rank.tier` with no expiry check) | **ESCALATE to the f04 brief (`fixes/f04-orders.md`)** — the edit belongs to `smp_orders`: `slot_limit` must delegate to `smp_ranks.order_limit(name)`. Your side, all three: (a) specify the API contract (next subsection), (b) add the `smp_ranks`-side contract test, (c) record the hand-off in §10 of `spec/features/f13-ranks.md` and annotate §11.3.2 as handed off | ESCALATE (fixes/f04-orders.md) |
| R-02 | f13 §11.3.1 (`f13:225-228`), §4.2.4 | A consumer reads its own `cfg.rtp.cooldown[tier] or default` instead of `smp_ranks.rtp_cooldown` — cooldown truth lives in two places (the fallback masks the missing-tier nil) | `smp_tp/rtp.lua:182` (inside `smp_tp.cooldown_secs`, `kind == "rtp"` branch) | **ESCALATE to the f08 brief (`fixes/f08-teleport.md`)** — the edit belongs to `smp_tp`: the rtp branch must return `smp_ranks.rtp_cooldown(name)`. Your side: same three steps as R-01 — contract, contract test, §10 hand-off + §11.3.1 annotation | ESCALATE (fixes/f08-teleport.md) |
| R-03 | f13 §6 (`f13:114`) | Pseudocode calls `smp_store.mark_dirty` — the helper does not exist; write-through `upsert_player` is the equivalent (behaviour OK, naming wrong) | `spec/features/f13-ranks.md:114`; grep `mark_dirty` across `friedcake/mods/` finds only `smp_orders.mark_dirty` (its own order-id helper), never `smp_store.mark_dirty`; the real pattern is `smp_ranks/grant.lua:38` (`smp_store.api.upsert_player(rec)`) | **ESCALATE → D6** (`fixes/01-integrator-decisions.md:46`): spec-side naming fix — amend §6 to name `upsert_player`, or specify `mark_dirty` and hand it to `smp_store`. **No code change.** Record the D6 dependency in §10 and leave §6's pseudocode untouched until D6 rules | ESCALATE (D6) |

### API contract the consumers must call

Name these exactly when writing the hand-off (verified against source):

```lua
smp_ranks.order_limit(who)    -- smp_ranks/perk.lua:76
smp_ranks.rtp_cooldown(who)   -- smp_ranks/perk.lua:84
-- record mutations stay here, never in consumers:
smp_ranks.grant(who, tier, days)  -- smp_ranks/grant.lua:19
smp_ranks.clear(who)              -- smp_ranks/grant.lua:44
```

Contract semantics (each point must be pinned by the contract test below):

1. **Accepts a player name or a PlayerRef**, normalised by
   `smp_ranks.name_of(who)` (`perk.lua:28`); unusable input reads as the safe
   default rather than erroring (f13 §11.1).
2. **Effective tier honours `expires_at`**: `smp_ranks.tier(who)`
   (`perk.lua:44`) returns `"default"` for an absent, invalid or expired
   `rank` record, with **no record mutation** (f13 §5, §8, T2). Therefore an
   expired record `{tier = "tier1", expires_at = <past>}` must yield
   `order_limit == 9`, `home_limit == 2`, `rtp_cooldown == 60` — even though
   a raw read of `rec.rank.tier` still says `"tier1"`. That divergence is
   exactly the bug at `smp_orders/orders.lua:204-206`.
3. **Values come from live configuration**, never hard-coded tables
   (`perk.lua:63-95`); `rtp_cooldown` falls back to `cooldowns.default` and
   is **never nil** (V-76: only tier1 is short by default; `media` aliases
   `tier3` — f13 §11.2.2/§11.2.4). This is what `smp_tp/rtp.lua:182` must
   consume instead of its private `cfg.rtp.cooldown` table.
4. **Consumers never read or write `rec.rank` directly** (f13 §4.2.4:
   "Consumers MUST call these rather than read the rank record directly, so
   the tier table lives in exactly one place") and never write the record at
   all — stacking/expiry bookkeeping lives in `grant`/`clear` (single
   read-modify-write via `smp_store.api.upsert_player` plus the watch-set
   update in `expiry.lua:16`) and in the expiry sweep
   (`expiry.lua:39,56`).

## Acceptance criteria

1. [R-01] The contract for `smp_ranks.order_limit(who)` (`perk.lua:76`) is
   documented in this brief and reproduced in the §10 hand-off entry that
   points at `fixes/f04-orders.md`, naming `smp_orders/orders.lua:204-206`.
2. [R-01] A new `smp_ranks`-side contract test is green: with a record seeded
   directly as `{tier = "tier1", expires_at = <past>}`, `tier() == "default"`,
   `order_limit == 9`, `home_limit == 2`, the raw `rec.rank.tier` still reads
   `"tier1"` (documenting why raw reads are wrong), and the record is
   unmutated.
3. [R-02] The contract for `smp_ranks.rtp_cooldown(who)` (`perk.lua:84`) is
   green: a **live** `tier2` (and `media`) record returns `60` via the
   default fallback — never nil — and live `tier1` returns `30`; the §10
   hand-off entry points at `fixes/f08-teleport.md` and
   `smp_tp/rtp.lua:182`.
4. [R-03] §10 carries the D6 entry (`mark_dirty` phantom at
   `f13-ranks.md:114`, equivalent `upsert_player` at `grant.lua:38`); §6 is
   not edited before D6 rules.
5. All 76 existing checks plus the new contract checks pass — no regression
   in the Confirmed-OK list below.
6. [R-01, R-02] The external halves are named as external (in the test
   comments and §10): they are **not** faked green with counterpart stubs
   (the failure mode `00-P0-blockers.md` B4 documents).

## Tests

- Extend `friedcake/dev-tests/test_ranks.lua` with a `CONTRACT` section (a
  comment header citing f13 §4.2.4 and the two §10 hand-offs):
  - **C1 (R-01):** seed `smp_store` record with
    `rank = { tier = "tier1", expires_at = os.time() - 1 }` → assert
    `smp_ranks.tier(A) == "default"`, `smp_ranks.order_limit(A) == 9`,
    `smp_ranks.home_limit(A) == 2`, raw `rec.rank.tier == "tier1"`, and the
    record after the calls is byte-identical (no mutation).
  - **C2 (R-02):** seed a *live* `rank = { tier = "tier2", expires_at =
    os.time() + 86400 }` → assert `smp_ranks.rtp_cooldown(A) == 60`
    (default fallback, never nil); keep T8's live-tier1 `30` as the
    counterpart. Optionally add `media` → `60`/tier3-alias if your config
    fixture carries it.
- Extend the in-mod `friedcake/mods/smp_ranks/test.lua` (AGENTS step 7) with
  the same C1/C2 assertions.
- **What stays external (do not stub, do not edit their files):** T4's
  enforcement half at create-time in `f09`/`f03`/`f04` (the `f04` half is
  R-01-blocked), T5's chat half in `f11` (`fixes/f11-social.md`), and T8's
  consumption half in `f08` (R-02). Record each in §10 with its owning brief.
  What you verify locally today: T4's local half (`test_ranks.lua:97-99,
  376-391` — expired limits, watch-set, notification, no mutation), T5's
  local half (`:415-419` — `chat_prefix() == ""`, accepts a ref), T8's local
  half (`:480-491` — 60 vs 30, revert after clear).
- Do **not** edit `friedcake/dev-tests/test_orders.lua` or
  `friedcake/dev-tests/test_tp.lua` — they are f04/f08's suites; re-run them
  only to confirm you left them green.
- The exact command that must exit 0:

  ```
  luajit friedcake/dev-tests/test_ranks.lua
  ```

## Constraints

Standing rules (from `AGENTS.md`, repeated in every brief):

- **No edits to `spec/shared/`, `spec/plan/`, `spec/README.md`.** All shared
  files above are READ ONLY; proposals flow through your feature file's
  `## Proposed shared changes` / §10.
- **No edits to `smp_core`, `smp_store`, `smp_admin`** — R-03's `mark_dirty`
  lives there if D6 chooses the API route; you only record it.
- **One agent per feature file.** Your edit surface: `smp_ranks`, its test
  files, `friedcake/dev-tests/test_ranks.lua`, and your own
  `spec/features/f13-ranks.md`. Do **not** touch `smp_orders` (R-01),
  `smp_tp` (R-02), `smp_social`, or any other feature's mod — cross-mod
  seams are propose-only via §10 / `## Proposed shared changes`.
- Your own feature file `f13-ranks.md` is yours to update for: §10 hand-off
  entries (H-ids suggested; follow the table's existing two-column shape),
  annotating §11.3.1/§11.3.2 as handed off, and test-status notes — **never
  rewrite or downgrade an OBSERVED row** (f13's §6/§7/§11 stay as the
  integrator left them until D6 rules).
- **Money is integer cents**, always rendered via `smp_core.fmt_money` —
  (`ranks.store_text` may embed prices; render amounts through the formatter).
- **All player-facing strings through `core.get_translator`** — including the
  §11.2.8 admin strings, which must stay **verbatim** (see Confirmed OK).
- **No yields between validate and mutate** in any economic operation
  (shared §2.3) — `grant`/`clear` already comply; keep them that way.
- **Verbatim UI strings character-exact.**
- **Config keys must match `shared/06`** — propose mirror changes (your file
  already carries the flat-key proposal), never hand-edit.
- **Never downgrade an OBSERVED requirement.**
- Do not remove the `core.register_on_globalstep` fake at
  `dev-tests/test_ranks.lua:254` — that cleanup is `00-P0-blockers.md` B4-1.

## Out of scope

- Any edit to `smp_orders` or `smp_tp` — those land via `fixes/f04-orders.md`
  and `fixes/f08-teleport.md`; your deliverable is contract + test + hand-off.
- The D6 spec edit itself (integrator ruling), and any `smp_store` API work.
- New behaviour: chat prefixes, new perks, new config keys, `/ranks` redesign.
- f09's bridge (`home_limit(player)` works as written — f13 §11.3.3) and
  f11's `/ranks` fallback (`smp_social/info.lua:150,164` guard) — preserve,
  don't touch.
- Harness-wide seam policy (D11) and the B4-1 fake removal (brief 00).

### Confirmed OK — preserve, do not regress

- `/ranks` and the `/buy`/`/store` fallback (via
  `smp_social/info.lua:150,164`).
- The menu rendering **live config** (tiers, perks, prices) with store field
  and `Back` (`formspec.lua`).
- **Admin strings §11.2.8 verbatim**: `Granted @1 to @2 for @3 days`,
  `Cleared @1's rank`, `Your rank has expired`,
  `Unknown tier: @1. Tiers: default, tier1, tier2, tier3, media`,
  `Days must be a whole number of at least 1`.
- Grant and stacking rules (same-tier extends, different-tier restarts —
  `grant.lua:19-41`, T3).
- Perk application (`perk.lua:63-100`) and tier lookup (`perk.lua:44`).
- The expiry watch-set sweep (`expiry.lua:16,39,56`) — dirty candidates
  only, notification once per run, no record mutation (T2).
- All §7 config keys read from live settings.
- Hygiene: translator, verbatim strings, `modpack.conf` entry, no duplicate
  command registration.
- T1–T8 (76 checks) as they stand, with the integration halves per Tests.

### Beyond spec

None found — the audit records "no beyond-spec behaviour" in this mod. If you
discover any while working, record it in §10 rather than deleting it.

## Definition of done

1. Every issue ID above is fixed or escalated with a reason recorded in §10
   of `spec/features/f13-ranks.md` (R-01 → f04 brief, R-02 → f08 brief,
   R-03 → D6), with §11.3.1/§11.3.2 annotated as handed off.
2. `luajit friedcake/dev-tests/test_ranks.lua` exits 0 — all 76 existing
   checks plus the new CONTRACT checks (paste output into the branch
   description).
3. In-mod `friedcake/mods/smp_ranks/test.lua` updated with the same contract
   assertions.
4. `git checkout -b agent/f13-ranks-fixes` from `main`; commit with a message
   referencing `SPEC-CONFORMANCE-REPORT.md §4 f13`; push the **branch**,
   never `main`.
5. Report back with a mapping table: issue ID → evidence (`file:line`) →
   outcome (escalated + target brief/decision), plus the exact contract
   function names the f04 and f08 agents will call.
