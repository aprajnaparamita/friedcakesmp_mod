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

## Rulings — 2026-09-24 (integrator)

All eleven decisions are **ruled**. The work they unlock is written up as
requirements in [`fixes/REQUIREMENTS.md`](REQUIREMENTS.md) and split into five
standalone agent prompts under [`fixes/prompts/`](prompts/). Execution waves
and file-ownership are fixed there so parallel agents cannot collide.

| ID | Ruled | Choice | Follow-up change (exact sites) | Executed by |
|---|---|---|---|---|
| **D1** | 2026-09-24 | **A** — period-free OBSERVED form wins | Drop the period at `spec/features/f05-quickbuy.md:194` and `friedcake/mods/smp_quickbuy/buy.lua:87`. `shared/08:148`, `f03:194`, `f01:65` are already period-free — untouched. | `prompts/p1-spec-rulings.md` |
| **D2** | 2026-09-24 | **A** — the chat receipt *is* the design | Amend `f02 §6` (replace `receipt:show(player)` at `f02-sell.md:140` with the real chat-emitting call from `smp_sell/receipt.lua:164-214`); close V-55 (`f02-sell.md:186`) as ruled. No formspec receipt will be built. V-94 (`append_sell_history`) is **not** covered by D2 — see Open item OPEN-1. | `prompts/p1-spec-rulings.md` |
| **D3** | 2026-09-24 | **A** — code and observed screen are right | Rewrite §4.7 item 7 (`f12-settings.md:140-141`) and the §5.1 sample default (`f12-settings.md:~178`) to the implemented truth: `chat.private_messages`, `chat.death_messages`, `chat.advancements`, `chat.join_leave` default `FRIENDS_FOLLOWED`, everything else `ON`. Strike `settings.categories` from f12 §7 (`:205`) — the OBSERVED [F0237] category list must remain documented in §4 prose (move it if the §7 row is its only home). Annotate F12-B/F12-C (`:249-250`) and `:302` as decided. Mirror half: strike `06:76` (P2). | `prompts/p1-spec-rulings.md` (feature file) + `prompts/p2-config-mirror.md` (mirror) |
| **D4** | 2026-09-24 | **§7 corrected to `snapshot`** | `f14-stats.md:187` default cell `off` → `snapshot` (options list unchanged); annotate F14-D5 (`:237`) and the §10 note (`:257`) as resolved. Code stays as-is (already `snapshot`, `smp_stats/init.lua:43-50`). | `prompts/p1-spec-rulings.md` |
| **D5** | 2026-09-24 | **Normalise spec to what code renders** | `f07-spawners.md:34` `Page 1/5` → `Page 1 of 5`; `:129` `×n` → `x<n>`. The grid `5 × 9` (`:33`) and the §5.3 formulas (`:76,99,102`) keep `×` — they are not UI strings. V-01 and §5 already conform. Never the reverse. | `prompts/p1-spec-rulings.md` |
| **D6** | 2026-09-24 | **Amend §6 to `upsert_player`** | `f13-ranks.md:114` `smp_store.mark_dirty("players", name)` → `smp_store.api.upsert_player(rec)` (pattern: `smp_ranks/grant.lua:38`). Grep the whole spec for `mark_dirty` and eliminate the phantom. No `mark_dirty` API will be added to `smp_store`. | `prompts/p1-spec-rulings.md` |
| **D7** | 2026-09-24 | **A — mirror and §7 follow code, both directions** | Full reconciliation of `shared/06-config-reference.md`: add the declared-but-unmirrored keys (`sell.base_prices`, `orders.allow_self_delivery`, `quickbuy.page_size`, `shards.transferable`, `shardshop.offers`, `settings.cycle_order`, `homes.delete_confirm`, `combat.log_broadcast`, `world.*`, …), add every code-read key the sweep finds (`scoreboard.title`, `stats.persist_interval`, `api.mode` default `snapshot`, `ledger.page_size`, `store.max_balance`, …); rename the `tp.*`/`rtp.*`/`rtpqueue.*`/`tpa.*`/`homes.*` rows (`06:50-68`) and the matching `f08`/`f09` §7 rows to the exact full names the code reads (`smp_tp.` prefix — grep `smp_tp/config.lua` + `homes.lua`); settle the slot encoding (`06:17,24`) as dotted-primary scalars with the underscore alias noted (f04 O3); resolve `store.max_balance` vs `economy.max_balance` and `ah.history` (stays f03's, `pending:` marker). New guard: `friedcake/dev-tests/test_config_mirror.lua`. | `prompts/p2-config-mirror.md` |
| **D8** | 2026-09-24 | **B, hardened — descoped permanently: f16 will never be built** ("never going to be written… no need for legacy mods") | Strike `legacy.*` from `06:81-84` (P2). Close V-61 (`f06-shards.md:175`): `shards.require_activity` stays read, default false, documented inert. Mark `spec/features/f16-legacy.md` DESCOPED; de-f16 `plan/roadmap.md:24,42` (keep `smp_rtpqueue`/f08 and f14 `/api`); strike/annotate the f16 row (`plan/acceptance-tests.md:30`) and X1's "crate choice" (`:40`); annotate f16 references across `plan/`, `spec/README.md`, `shared/02`, `shared/05`. `fixes/f16-legacy.md` is CANCELLED and the README index updated by this brief. | `prompts/p3-f16-descope.md` (+ P2 for the mirror rows) |
| **D9** | 2026-09-24 | **A — build the API** | Add `smp_admin.flag(kind, detail)` (persisted ring buffer + `core.log("warning", …)` + notify online staff holding `smp_admin`/`smp_moderator`) with `friedcake/dev-tests/test_admin.lua`. `f01 §4.2.5` unchanged. Wiring at `smp_economy/init.lua:234-236` stays the **f01 brief's** job. | `prompts/p4-admin-apis.md` |
| **D10** | 2026-09-24 | **A — build the producer** | Add `smp_admin.mute(name, seconds)` / `unmute(name)` / `is_muted(name)` (mod-storage, offline- and restart-safe, lazy expiry) plus `/mute <player> [duration]` and `/unmute <player>` (priv `smp_moderator` or `smp_admin`; duration in seconds, omitted = permanent), rows in `shared/05-command-reference.md §5.5`, tests in `test_admin.lua`. `f11 §4.1.3` unchanged; the probe at `smp_social/bridges.lua:97-104` starts working as written; the honesty/TODO cleanup stays the **f11 brief's** job. | `prompts/p4-admin-apis.md` |
| **D11** | 2026-09-24 | **A — build the harness** | New `friedcake/dev-tests/test_integration.lua`: load-order dry run of every `load_mod`-enabled mod against the strict recorded surface `dev-tests/engine_api_surface.txt` (542 names), engine-determined per-mod file order (verify against the `~/dev/luanti` clone and cite it), cross-mod seam existence checklist, and a degraded pass with the optional layer removed. Record the seam policy in `plan/acceptance-tests.md`. | `prompts/p5-integration-harness.md` |
| **D12** | 2026-09-24 | **One generic history API** (was OPEN-1) | Extend `smp_store` with `smp_store.api.append_history(kind, name, entry) -> id`, mirroring the existing ledger helpers and backed by all three drivers; caller-supplied cap (default 100, matching `sell.history_size`), FIFO prune. Amend `f02 §11`'s `append_sell_history` proposal and `f02 §6:139` to the generic call, and `f03 §6`'s `append_history(kind, payload)` to the final signature. Consumer wiring — f02's local `history.lua` `_read`/`_write` seam (V-94) and f03's history storage — stays the **f02/f03 briefs'** rows. | `prompts/p6-store-history.md` |

**OBSERVED preservation notes (AGENTS rule 5 / `spec/README.md:104`):** none of
these rulings downgrades an OBSERVED row. D3 *moves* the OBSERVED [F0237]
category list out of the config-key table into prose — the fact must still be
documented. D7 *renames* key spellings while keeping every Status/Spec cell;
settings-file spellings were never themselves observed on video. D1/D5 move
spec text *toward* the observed/rendered form.

**OPEN-1 → ruled as D12 (2026-09-24, same session):** the sell-history seam
(`f02 §11` / V-94 / `f03 §6`) is settled by one generic
`smp_store.api.append_history(kind, name, entry)` that serves both features —
executed by `prompts/p6-store-history.md` (wave 3). The f02/f03 briefs no
longer wait; their remaining row is wiring their consumers onto the API.

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
