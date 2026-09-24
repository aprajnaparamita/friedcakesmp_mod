# Fix brief — 01: integrator decisions (spec-side and integrator-owned)

| Field | Value |
|---|---|
| Feature spec | `spec/README.md`, `spec/shared/*`, `spec/features/*` §7/§10 tables |
| Target | spec text, shared mirrors, `smp_admin`/`smp_store` APIs |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §3.1, §3.4, §4 (ESCALATE items) |
| Verdict at audit | **high — several feature fixes cannot close until these rulings land** |
| Branch | `agent/integrator-decisions` |
| Decisions | 11 |

---

## Mission

The audit found places where the spec contradicts *itself*, where the shared
config mirror advertises keys no code reads (and omits keys the code needs), and
where required behaviour sits in integrator-owned mods (`smp_admin`,
`smp_store`) that feature agents may not touch. Each item below needs a ruling,
then the corresponding spec line, mirror row, or API is updated **by the
integrator** — feature agents have proposed these in their own files' §10 /
`## Proposed shared changes` blocks, as AGENTS.md requires.

Work the decisions in order; several feature briefs in `fixes/` carry `ESCALATE`
rows that name the decision they are waiting on.

## Read this first (in order)

1. `AGENTS.md` — especially rules 1–5 (who owns what) and 2–3 (proposed changes
   flow through feature files, never hand-edited into `shared/` or `plan/`).
2. `SPEC-CONFORMANCE-REPORT.md` §3.1 (config contract) and §3.4 (spec-side notes).
3. `spec/shared/00-conventions.md` §0.5–§0.6 (verbatim UI, money spacing) and
   `08-ui-strings.md` (string catalogue).
4. The `## Proposed shared changes` and `## 10. Open questions` blocks of every
   feature file that appears below.

## Decisions to make

| ID | Decision | Evidence / options | Affected files | Blocks |
|---|---|---|---|---|
| **D1** | **Race-string terminal period.** `shared/08:148` and the OBSERVED source say `This item was already bought` (no period); `f05:194` says the same string *with* a period. `smp_ah/init.lua:169` implements period-free, `smp_quickbuy/buy.lua:87` implements with-period — the two mods disagree in production. | **Option A:** correct `f05:194` to the OBSERVED period-free form and drop the period in `buy.lua:87` (favoured: never downgrade an OBSERVED string). **Option B:** keep both and record the divergence in `08-ui-strings.md`. | `spec/features/f05-quickbuy.md:194`, `friedcake/mods/smp_quickbuy/buy.lua:87`, possibly `spec/shared/08-ui-strings.md:148` | f05 brief note; f01 §3.3 row |
| **D2** | **V-55 receipt screen.** `f02 §6` pseudocode calls `receipt:show(player)`; the code emits chat lines (`smp_sell/receipt.lua:164-214`) and V-55 in `f02 §10` is still open. | **Option A:** close V-55 as "chat receipt is the design" and amend §6. **Option B:** require a formspec receipt — a new build task, ~1 screen. | `spec/features/f02-sell.md` §6 + §10 V-55 | f02 brief |
| **D3** | **f12 self-acknowledged conflicts.** F12-B: §4.7 says defaults are "most permissive" but the observed screen needs four `FRIENDS_FOLLOWED` defaults; F12-C: §7 declares `settings.categories` as a config key but the code hard-registers categories. | **Option A (recommended):** rewrite §4.7 to match §5/observed reality and strike `settings.categories` from §7 — the code is deliberately right. **Option B:** change the code (would break the observed first-open screen, so not viable for F12-B). | `spec/features/f12-settings.md:205,249-250`, `spec/shared/06-config-reference.md:76` | f12 brief rows 2–3 |
| **D4** | **f14 `api.mode` default.** §7 table says `off`; §4.4 says "pick option 1 by default"; code defaults to `snapshot` (`smp_stats/init.lua:43-50`). F14-D5 records the conflict. | **Option A:** correct §7 to `snapshot`. **Option B:** correct the code to `off` and re-read §4.4. | `spec/features/f14-stats.md:187,237` | f14 brief row 2 |
| **D5** | **f07 internal wording splits** the code had to break: header `x128` (§3/§5) vs `×n` (§4.6.3); sketch `Page 1/5` (§3) vs V-01 `Page n of m`. Code follows §3/V-01 consistently. | Normalise the spec to what the code renders (both are the observed/V-01 forms) — never the reverse. | `spec/features/f07-spawners.md` §3, §4.6.3 | f07 brief (documentation only) |
| **D6** | **`smp_store.mark_dirty` phantom API.** `f13 §6` pseudocode names a helper that does not exist; write-through `upsert_player` is the equivalent. | Amend `f13 §6` to name `upsert_player`, or specify `mark_dirty` and hand the helper to `smp_store` (integrator-owned). | `spec/features/f13-ranks.md` §6, maybe `smp_store` | f13 brief |
| **D7** | **Config mirror reconciliation (one pass, both directions).** *Add* the feature-declared keys missing from `shared/06`: `sell.base_prices`, `orders.allow_self_delivery`, `quickbuy.page_size`, `shards.transferable`, `shardshop.offers`, `settings.cycle_order`, `homes.delete_confirm`, `combat.log_broadcast`, `world.*` (f15). *Resolve* the four `legacy.*` keys at `06:81-84` that describe an unbuilt feature (D8). *Settle the encoding* for the two slot tables — one convention shared by `ah.slots.*` and `orders.slots.*` (`06:17,24` currently documents a table neither mod reads literally). | Feature agents may not edit `shared/06`; all of these were surfaced as proposals in feature §10 blocks. | `spec/shared/06-config-reference.md` (+ the §7 tables it mirrors) | f01, f02, f04, f06, f09, f10, f12 briefs |
| **D8** | **f16 scope call.** The five legacy mods do not exist (37 gaps, 0/11 tests), yet `06:81-84` already advertises four `legacy.*` keys and f06's `shards.require_activity` is inert pending f16's AFK tracking (V-61). | **Option A:** schedule f16 at P8 as `roadmap.md:24` says. **Option B:** descoped — strike the `legacy.*` mirror rows, close V-61 (`require_activity` stays inert, documented), and mark `f16-legacy.md` deferred. | `spec/shared/06-config-reference.md:81-84`, `spec/features/f16-legacy.md`, `f06-shards.md` V-61, `spec/plan/roadmap.md` (**integrator-owned**) | f16 brief, f06 row 3 |
| **D9** | **`smp_admin.flag` API (f01 §4.2.5).** Spec requires transfer flags to reach `smp_admin`; `smp_admin` is 26 lines of priv registration with no flag API, and `/pay` currently only calls `core.log("warning")`. Feature agents may not add it. | Provide a minimal `smp_admin.flag(kind, detail)` (persisted or staff-notified — specify), **or** amend f01 §4.2.5 to "logged warning". | `smp_admin/` (integrator-owned), `spec/features/f01-economy-core.md` §4.2.5 | f01 brief row 3 |
| **D10** | **Mute producer (f11 §4.1.3).** The chat callback enforces mutes but nothing in the pack can set one — `smp_admin` has no `mute`/`is_muted`, so the bridge always returns false. | Add a mute API to `smp_admin` (+ `/mute`, `/unmute` and a duration), **or** amend f11 §4.1.3 to note enforcement-only-until-moderation-tooling. | `smp_admin/` (integrator-owned), `spec/features/f11-social.md` §4.1.3 | f11 brief row 4 |
| **D11** | **Integration-test seam policy.** Every cross-mod seam (f03↔f04, f03↔f05, f07→f02, f08→f11) is tested with the counterpart stubbed; no test ever loads two real mods together, which is exactly how B1/B4 in `00-P0-blockers.md` survived. | Commission one modpack-level headless test that loads the real mods in dependency order (or record in `plan/acceptance-tests.md` — integrator-owned — that seam tests are out of scope for the dev harness). | `spec/plan/acceptance-tests.md` (**integrator-owned**), new `friedcake/dev-tests/test_integration.lua` | all briefs (structural) |

## Acceptance criteria

1. Every ID D1–D11 has a written ruling in this file (fill in the chosen
   option), dated, with the follow-up spec/code change listed.
2. Where the ruling changes spec text: the edit lands in the owning feature
   file (or `shared/`/`plan/` directly — you are the integrator), and no
   `OBSERVED` row is downgraded (AGENTS rule 5 / `spec/README.md:104`).
3. Where the ruling changes the shared mirror: `06-config-reference.md` ends up
   with **exactly** the set of keys the mods read — no orphans in either
   direction — and each feature's §7 table matches it.
4. D9/D10 produce either an API (with a dev-test) or a spec amendment that
   unblocks the `ESCALATE` rows in the f01 and f11 briefs.
5. `fixes/README.md` marks `01` ✅ and each now-unblocked feature brief is
   annotated with the decision ID it depends on.

## Tests

- For D9/D10 (if APIs are chosen): add `friedcake/dev-tests/test_admin.lua`
  covering flag and mute/unmute round-trips, and wire the f01/f11 consumers to
  it — the consuming feature agents do the wiring under their own briefs.
- For D7: a small guard in `dev-tests` that parses `shared/06-config-reference.md`
  and greps each key into `friedcake/mods/**` (fail on an advertised key nobody
  reads, and on a `settings:get*` key absent from the mirror). This directly
  prevents recurrence of the §3.1 failure mode.
- For D11: see the brief row.

## Constraints

- You own `spec/shared/`, `spec/plan/`, `spec/README.md` and the integrator-owned
  mods — this is the one brief allowed to touch them. Everyone else escalates to
  here.
- Never downgrade an `OBSERVED` requirement to a guess; disagreements get
  recorded, not silently rewritten.
- Money stays integer cents; verbatim strings stay verbatim; configuration
  defaults stay configuration-driven (goal G3).

## Out of scope

- All behavioural fixes inside feature mods — those belong in the `fNN-*.md`
  briefs. This document produces rulings and integrator-owned changes only.

## Definition of done

1. D1–D11 ruled; spec/mirror/API changes landed; new guards green.
2. `git checkout -b agent/integrator-decisions` from `main`; commit and push the
   **branch**, never `main`.
3. Reply to the agents holding blocked briefs (f01, f02, f06, f11, f12, f13,
   f14, f16) with their decision IDs.
