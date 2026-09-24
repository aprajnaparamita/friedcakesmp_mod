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
| 00 | [`00-P0-blockers.md`](00-P0-blockers.md) | cross-cutting | `smp_store`, `smp_ah`, `smp_orders`, `smp_shards`, `smp_amethyst`, `smp_stats`, `smp_tp` | 3 classes | **blocker — nothing loads** | `agent/p0-engine-apis` |
| 01 | [`01-integrator-decisions.md`](01-integrator-decisions.md) | spec-side | `spec/*`, mirrors, `smp_admin` | 11 decisions | **high — blocks several fixes** | `agent/integrator-decisions` |
| f01 | [`f01-economy-core.md`](f01-economy-core.md) | Economy core | `smp_economy`, `smp_items` | ~14 | high | `agent/f01-economy-fixes` |
| f07 | [`f07-spawners.md`](f07-spawners.md) | Virtual spawners | `smp_spawners` | 14 | **high — item loss** | `agent/f07-spawner-fixes` |
| f09 | [`f09-homes.md`](f09-homes.md) | Homes | `smp_tp` (homes) | 4 | **high — feature never loads** | `agent/f09-homes-fixes` |
| f11 | [`f11-social.md`](f11-social.md) | Social | `smp_social` | 5 | high — 0 tests | `agent/f11-social-fixes` |
| f08 | [`f08-teleport.md`](f08-teleport.md) | Teleport | `smp_tp`, `smp_rtpqueue` | 8 | high | `agent/f08-teleport-fixes` |
| f14 | [`f14-stats.md`](f14-stats.md) | Stats | `smp_stats` | 4 | high (incl. blocker site) | `agent/f14-stats-fixes` |
| f06 | [`f06-shards.md`](f06-shards.md) | Shards | `smp_shards`, `smp_shardshop`, `smp_amethyst` | 5 | medium | `agent/f06-shard-fixes` |
| f01→f03 | [`f03-auction.md`](f03-auction.md) | Auction | `smp_ah` | 4 | medium | `agent/f03-auction-fixes` |
| f04 | [`f04-orders.md`](f04-orders.md) | Orders | `smp_orders` | 3 + 1 consumer | medium | `agent/f04-orders-fixes` |
| f12 | [`f12-settings.md`](f12-settings.md) | Settings | `smp_settings` | 4 | medium | `agent/f12-settings-fixes` |
| f10 | [`f10-combat.md`](f10-combat.md) | Combat | `smp_combat`, `smp_bounty` | 2 | low | `agent/f10-combat-fixes` |
| f02 | [`f02-sell.md`](f02-sell.md) | Sell | `smp_sell` | 2 | low | `agent/f02-sell-fixes` |
| f13 | [`f13-ranks.md`](f13-ranks.md) | Ranks | `smp_ranks` | 2 (consumer-side) | low — coordination | `agent/f13-ranks-fixes` |
| f16 | [`f16-legacy.md`](f16-legacy.md) | Legacy | *(none exist)* | 37 | scope call → `01` | `agent/f16-legacy-decide` |

**No document for f05 (Quick Buy) or f15 (world rules)** — both audited
`COMPLETE` with zero gaps.

## Suggested order

1. `00-P0-blockers.md` — without it no fix can be verified in-game.
2. `01-integrator-decisions.md` — several feature briefs carry **ESCALATE**
   items that cannot be closed until these rulings land.
3. `f07`, `f09`, `f11`, `f08`, `f14` — the high-severity items (item loss,
   unwired feature, untested OBSERVED strings, wrong engine APIs).
4. Everything else, in any order — the remaining briefs are independent and can
   run in parallel (one agent per feature file, per AGENTS.md).

## Standing rules (repeated in every brief)

- `spec/shared/`, `spec/plan/`, `spec/README.md` are **read-only**.
- `smp_core`, `smp_store`, `smp_admin` are **integrator-owned** — escalate.
- One agent per feature file; do not edit another feature's mod.
- Money is integer cents; display only through `smp_core.fmt_money`.
- Every player-facing string through `core.get_translator`.
- No yields between validate and mutate in any economic operation.
- Verbatim UI strings must match the spec character for character.
- Never downgrade an `OBSERVED` requirement.
