# Fix documents — FriedcakeSMP spec-conformance remediation

Generated from [`SPEC-CONFORMANCE-REPORT.md`](../SPEC-CONFORMANCE-REPORT.md)
(audit of 2026-09-23). One document per feature that has gaps, plus two
integrator-level documents.

**Every document is self-contained.** Each one carries its own mission, the
issues with `file:line` evidence, acceptance criteria, tests to write, the
AGENTS.md constraints, and a definition of done — so you can hand any single
file **verbatim to a sub-agent** as its task prompt (or open a fresh session and
paste it). No other context is required.

## How to use

1. Pick a document from the index below (start with `00-P0-blockers.md` — the
   pack does not currently boot).
2. Hand the file's contents to a sub-agent, or run the work yourself.
3. The agent branches `agent/<id>-<short>`, fixes, extends
   `friedcake/dev-tests/test_<feature>.lua` and the in-mod `test.lua`, runs the
   suite, commits and pushes **the branch, never `main`**.
4. Anything that requires touching `spec/shared/`, `spec/plan/`,
   `smp_core`/`smp_store`/`smp_admin`, or another feature's mod is marked
   **ESCALATE** in the brief: the agent records it in §10 of its own feature
   file and stops — the integrator collects those in `01-integrator-decisions.md`.

## Index

| # | Document | Feature | Target mod(s) | Gaps | Severity | Branch |
|---|---|---|---|---:|---|---|
| 00 | [`00-P0-blockers.md`](00-P0-blockers.md) | cross-cutting | `smp_store`, `smp_ah`, `smp_orders`, `smp_shards`, `smp_amethyst`, `smp_stats`, `smp_tp` | 3 classes | **✅ fixed — pack boots** | `agent/p0-engine-apis` |
| 01 | [`01-integrator-decisions.md`](01-integrator-decisions.md) | spec-side | `spec/*`, mirrors, `smp_admin` | 12 decisions | **✅ ruled & executed 2026-09-24 (P1–P6 merged)** | `agent/integrator-decisions` |
| f01 | [`f01-economy-core.md`](f01-economy-core.md) | Economy core | `smp_economy`, `smp_items` | ~14 | **✅ merged 2026-09-25 (`f0c66bb`) — 18 rows closed (incl. E-01 wiring, E-18 `give` clamp, E-20 reversible codec, E-22 settings chain), 8 escalated in §10.1 (E-05/06/12/15/17/19/21 = store/core, E-28), findings F-1…F-8 in §10.2; suite now 27 (`test_items.lua` added)** | merged → `agent/integrator-decisions` |
| f07 | [`f07-spawners.md`](f07-spawners.md) | Virtual spawners | `smp_spawners` | 14 | **✅ merged 2026-09-25 (`8b51f3e`) — F07-1/F07-2 verify-only (pre-fixed), F07-3..F07-13 verified, F07-14 ESCALATED → D5 (doc normalisation only); suite 27/27 on main** | merged → `agent/integrator-decisions` |
| f09 | [`f09-homes.md`](f09-homes.md) | Homes | `smp_tp` (homes) | 4 | **✅ merged 2026-09-25 (`bab9913`) — H1/H2/H3 VERIFIED (B3 wiring landed), H4 FIXED (config default_icon default aligned, mirror change §11.4), in-mod tests added (134 assertions); 27/27 on main (pre-existing failures)** | merged → `agent/integrator-decisions` |
| f11 | [`f11-social.md`](f11-social.md) | Social | `smp_social` | 5 | **✅ merged 2026-09-25 (`8cd7620`) — F11-2 contract test, F11-3 `follow_blocked`, F11-4 `blocks_only` (+ consumer switch escalated to f08 TP13), F11-5 D10 honesty, F11-6 N/A, F11-7/8 verified; record in `spec/features/f11-social.md` §10.2** | merged → `agent/integrator-decisions` |
| f08 | [`f08-teleport.md`](f08-teleport.md) | Teleport | `smp_tp`, `smp_rtpqueue` | 13 | **✅ merged 2026-09-25 (`1c9195e`) — TP1 VERIFIED, TP2–TP5/TP7–TP13 CLOSED, TP6 DEFERRED (spec §4.6), TP13 `blocks_only()` wiring via bridge; test_config_mirror ✅; 27/27 on main (pre-existing test_engine_apis)** | merged → `agent/integrator-decisions` |
| f14 | [`f14-stats.md`](f14-stats.md) | Stats | `smp_stats` | 4 | **✅ merged 2026-09-25 (`fd62e64`) — S1 verify-only (fixed on `main`), S2 → D4, S3/S4/S5/S6/S7 closed; record in `spec/features/f14-stats.md` §10** | merged → `agent/integrator-decisions` |
| f06 | [`f06-shards.md`](f06-shards.md) | Shards | `smp_shards`, `smp_shardshop`, `smp_amethyst` | 11 | **✅ merged 2026-09-25 (`a0bdb9c`) — F06-1 VERIFIED, F06-2/5/9 CLOSED code + ESCALATED → D7 (mirror), F06-3 → D8, F06-4 CLOSED (warning), F06-6 CLOSED (T2/T4/T7 rewritten), F06-7 VERIFIED, F06-8 mcl_armor CLOSED + mcl_potions → integrator, F06-10 DEPENDS-BLOCKER, F06-11 CLOSED (string style); cycle cut: amethyst→orders removed** | merged → `agent/integrator-decisions` |
| f03 | [`f03-auction.md`](f03-auction.md) | Auction | `smp_ah` | 7 | **✅ merged 2026-09-25 (`61fc3c9`) — A1 VERIFIED, A2 CLOSED (Match lowest), A3 CLOSED (ah.sorts), A4 CLOSED (ah.history), A5 ESCALATED → D7, A6 CLOSED (5 keys), A7 VERIFIED; 27/27 on main** | merged → `agent/integrator-decisions` |
| f04 | [`f04-orders.md`](f04-orders.md) | Orders | `smp_orders` | 9 | **✅ merged 2026-09-25 (`cb7d392`) — O2..O9 CLOSED (O3/O8 mirror→D7, O6 sell_axe→f06); O1 VERIFIED; test_orders 598 assertions; 25/27 on main (pre-existing failures)** | merged → `agent/integrator-decisions` |
| f12 | [`f12-settings.md`](f12-settings.md) | Settings | `smp_settings` | 7 | **✅ merged 2026-09-25 (`ffb6a08`) — F12-1 closed (⚠ in both renders + byte-exact tests) · F12-2, F12-3 ESCALATED → D3 (ruled A; pre-applied, verified) · F12-4 closed (T9 leg in `test_social.lua`) · F12-5, F12-6 closed (hygiene) · F12-7 ESCALATED → D7 (mirror already at `shared/06:124`, verified)** | merged → `agent/integrator-decisions` |
| f10 | [`f10-combat.md`](f10-combat.md) | Combat | `smp_combat`, `smp_bounty` | 4 | **✅ merged 2026-09-25 (`439a931`) — C1 elytra disable implemented (new elytra.lua), C2 keep_pearls_on_death re-scoped to pending:f08, C3 cycle verified (stats↔combat order-critical edge kept), C4 bounty string style fixed; 27/27 on main (pre-existing test_engine_apis failure)** | merged → `agent/integrator-decisions` |
| f02 | [`f02-sell.md`](f02-sell.md) | Sell | `smp_sell` | 2 | low | `agent/f02-sell-fixes` |
| f13 | [`f13-ranks.md`](f13-ranks.md) | Ranks | `smp_ranks` | 3 | **✅ merged 2026-09-25 (`68b99a4`) — R-01→H1/f04 (order_limit contract test), R-02→H2/f08 (rtp_cooldown contract test), R-03→H3/D6 (upsert_player hand-off); 25/27 on main (pre-existing failures)** | merged → `agent/integrator-decisions` |
| f16 | [`f16-legacy.md`](f16-legacy.md) | Legacy | *(none exist)* | 37 | **❌ cancelled — descoped permanently (D8, 2026-09-24), never to be built** | — |

### Row 00 ✅ — closed on `agent/p0-engine-apis`

B1–B3 had already landed in `68b5bf5`. This branch adds the missing B4-3
regression guard, `dev-tests/test_engine_apis.lua`, backed by a recorded
542-name **server** API surface (`dev-tests/engine_api_surface.txt`,
extracted from the local engine clone with `l_client.cpp` excluded — that
file registers the client-mod API, which is nil on a server). Two B4-1
blind-replace remnants are gone as well.

Brief 00's own audit turned out to be incomplete: the criterion-6 surface
diff found three further sites **of the same class**, none of which it
listed. All fixed:

| Site | Was | Now |
|---|---|---|
| `smp_amethyst/init.lua:205` | `core.register_on_pickup` — **load-time crash, pack still did not boot** | `core.register_on_item_pickup` (signature-compatible) |
| `smp_economy/init.lua:161`, `smp_shards/init.lua:196` | `core.get_player_names()` — client-only, runtime crash on a server | `core.get_connected_players()` + `:get_player_name()` |
| `smp_sell/items.lua:478` | `core.get_translated` | `core.get_translated_string` |

Nine harnesses stubbed `get_player_names` and one stubbed
`register_on_pickup`, masking every row above — exactly the B4-1
anti-pattern ("never stub a name the engine does not have"). Those fakes
are removed, and the guard now diffs **every** `core.*` name the mods
reference against the recorded surface, so the whole bug class is
covered rather than the two literals brief 00 happened to name.

**Nothing escalated. One site deferred:** `core.get_detached_inventory`
(7 sites in `smp_ah`, `smp_orders`) is engine-absent but `and`-guarded,
so it cannot crash — it silently resolves to `nil`. The engine offers
`create`/`remove_detached_inventory` but **no getter**, so a real fix
needs a module-local inventory registry, a behavioural change beyond a
rename. Listed under "deliberately absent" in `engine_api_surface.txt`.

**No document for f05 (Quick Buy) or f15 (world rules)** — both audited
`COMPLETE` with zero gaps.

---

### Row 01 ✅ — ruled 2026-09-24, execution in [prompts/](prompts/)

All twelve decisions are written up with dated rulings, chosen options and
exact change sites in
[`01-integrator-decisions.md`](01-integrator-decisions.md) § *Rulings —
2026-09-24*:

| Decision | Ruled | Decision | Ruled |
|---|---|---|---|
| D1 | **A** — race string loses its period | D7 | **A** — mirror + §7 follow code |
| D2 | **A** — chat receipt is the design | D8 | **descoped permanently — f16 never built** |
| D3 | **A** — §4.7/§5.1 rewritten, categories struck | D9 | **A** — `smp_admin.flag` built |
| D4 | **§7 → `snapshot`** | D10 | **A** — mute producer + `/mute`,`/unmute` |
| D5 | **normalise spec to renderer** | D11 | **A** — `test_integration.lua` built |
| D6 | **`upsert_player`, `mark_dirty` struck** | D12 | **one generic `smp_store.api.append_history`** (was OPEN-1) |

Execution was split into six standalone prompts — **all six executed and
merged 2026-09-24** (results in [`STATUS.md`](STATUS.md) §8–§9)
([`prompts/README.md`](prompts/README.md) — waves, branches, conflict matrix),
master requirements in [`REQUIREMENTS.md`](REQUIREMENTS.md):

- **Wave 1 (parallel):** [P1 spec-rulings](prompts/p1-spec-rulings.md) (D1–D6),
  [P3 f16-descope](prompts/p3-f16-descope.md) (D8 spec-side),
  [P4 admin-apis](prompts/p4-admin-apis.md) (D9+D10)
- **Wave 2:** [P2 config-mirror](prompts/p2-config-mirror.md) (D7 + mirror
  halves of D3/D8) — after P1 and P3
- **Wave 3 (parallel):** [P5 integration-harness](prompts/p5-integration-harness.md)
  (D11) — after P2 and P4; [P6 store-history](prompts/p6-store-history.md)
  (D12) — after P1

Each feature brief below now carries its ruling outcome on its **Depends on**
row (criterion 5). Brief `f16` is cancelled. Briefs `f08`, `f09`, `f10`
were missing at audit (GAP-1) and were **authored 2026-09-24** from the
audit's f08/f09/f10 sections with the P0/D7/pack-level resolutions baked in
as verify-don't-redo rows — they are dispatchable like the rest.

**Caveat:** every branch below is local — push is blocked (SSH passphrase).
Branch bases: before the 2026-09-24 fast-forward, from
`agent/integrator-decisions` (it carried `fixes/`, the rulings, and the 00
engine-API fixes); from then on `main` and `agent/integrator-decisions`
point at the **same commit**, so branch from either (they are identical).

## Suggested order

1. `00-P0-blockers.md` — **done** (✅, `agent/p0-engine-apis`); merge it first,
   it is the load blocker for everything below.
2. `01-integrator-decisions.md` — **ruled** (✅); run its five
   [`prompts/`](prompts/) in wave order 1 → 2 → 3 (each branches from
   `agent/integrator-decisions`).
3. `f07`, `f09`, `f11`, `f08`, `f14` — the high-severity items (item loss,
   unwired feature, untested OBSERVED strings, wrong engine APIs).
   `f08`/`f09` briefs are authored (GAP-1 closed 2026-09-24).
4. Everything else, in any order — the remaining briefs are independent and can
   run in parallel (one agent per feature file, per AGENTS.md). `f16` is
   cancelled (D8). All D-escalations are already ruled — see each brief's
   **Depends on** row.

## Standing rules (repeated in every brief)

- `spec/shared/`, `spec/plan/`, `spec/README.md` are **read-only**.
- `smp_core`, `smp_store`, `smp_admin` are **integrator-owned** — escalate.
- One agent per feature file; do not edit another feature's mod.
- Money is integer cents; display only through `smp_core.fmt_money`.
- Every player-facing string through `core.get_translator`.
- No yields between validate and mutate in any economic operation.
- Verbatim UI strings must match the spec character for character.
- Never downgrade an `OBSERVED` requirement.
