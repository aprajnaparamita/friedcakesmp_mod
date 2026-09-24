# Implementation Roadmap

Phases follow the dependency graph in `shared/02-architecture.md §2.1`. The
acceptance criteria column is the gate: a phase is done when its criteria pass,
not when its code exists. Per-test detail is in `acceptance-tests.md`.

## Dependency graph

```
smp_core ── smp_store ── smp_items ── smp_economy (f01) ── smp_ranks (f13)
                                │
        ┌───────────────────────┼─────────────────────────────┐
        ▼                       ▼                             ▼
  smp_sell (f02)          smp_ah (f03)                  smp_shards (f06)
        │                       │                             │
        ▼                       ▼                             ▼
  smp_spawners (f07)      smp_orders (f04)              smp_shardshop,
                            │                           smp_amethyst (f06)
                            ▼
                      smp_quickbuy (f05)

smp_tp (f08) ── f09 homes                smp_combat (f10) ── smp_bounty (f10)
smp_settings (f12) ── smp_social (f11)   smp_stats (f14)
P8: smp_rtpqueue (f08)  # (f16 descoped — D8, 2026-09-24)
```

`f15` (world rules) has no mod of its own but gates P4 (RTP must respect the
border and spawn protection) and P5 (PvP policy).

## Phases

| Phase | Deliverables | Spec files | Acceptance criteria |
|---|---|---|---|
| **P0 Foundation** | `smp_core`, `smp_store`, `smp_items`, `smp_economy`, `smp_ranks`, ledger, `/eco`, spawn protection, world border | f01, f13, f15, shared §2 | Persistence survives restarts; unit tests for matching levels M0–M2; the money formatter reproduces both observed spacings; tier limits answer through the perk API; spawn protection honoured via `core.is_protected` |
| **P1 Selling** | `/sell` with shulkers and history, base prices, `/worth` | f02 | No item loss on close, disconnect or full inventory; the observed `Sell` menu and confirm control reproduced |
| **P2 Spawners** | Virtual spawners | f07 | Output within 1 % of the §5.3 model; zero entities created; Silk Touch gating works |
| **P3 Markets** | Auction house, orders, routing, Quick Buy | f03, f04, f05 | Tests cover every routing path; the 3× price guard works; observed menus (`Auction (Page N)`, `Orders (Page N)`, `Choose Item`, `How many?`, `Review Order`, delivery flow) reproduced verbatim |
| **P4 Teleports** | Framework, `/rtp` and RTP zone, requests, homes, spawn, warps, `/world` | f08, f09 | No landing in liquid, fire or void across 1,000 trials; observed `Homes` tab row and submenu reproduced |
| **P5 Combat** | Combat tag, combat log, bounties | f10 | Combat logging drops all four registered lists and credits the kill; blocked commands refuse while tagged |
| **P6 Shards** | Awards, shard shop, amethyst items | f06 | Expired items disappear; the drill respects protection; the observed award message is verbatim |
| **P7 Social and meta** | Chat, private messages, ignore/block, friends, `/findplayer`, settings, statistics, leaderboards, scoreboard | f11, f12, f14 | The observed chat format, `/msg` refusal, seven settings categories and scoreboard are reproduced; leaderboard rebuild under 50 ms at 10,000 players |
| **P8 Optional** | RTP queue, API export *(f16 descoped — D8, 2026-09-24)* | f08 (`smp_rtpqueue`), f14 (`/api`) | Tests per module |

## Suggested order inside phases

1. **P0** is strictly first — every mod touches `smp_economy`, `smp_store` or
   `smp_ranks`.
2. **P1 before P2 before P3**: spawner "Sell all" routes through `/sell`;
   orders route through the auction house; Quick Buy rides on both.
3. **P4 and P5 can run parallel** to P1–P3 (no shared dependencies except
   `smp_core`).
4. **P7** needs `f12` before `f11` (the friends/followed privacy values are
   settings), and `f11` before `f14`'s `/findplayer` display if staff
   formatting is reused. `f14` can start once P0 exists.
5. **P8** modules are independent of each other; schedule by demand.

## Evidence-driven re-verification points

Before building each phase, re-check its open questions
(`open-questions.md`). The highest-value captures, in order:

1. **f07 spawner menu** (V-01, V-02) — the whole production model is a guess.
2. **f03 auction economics** (V-06) — fees, duration, default slots.
3. **f06 shard shop** (V-20, V-60) — prices and enchantment lists.
4. **f10 combat tag** (V-12, V-68) — duration and display.
5. **f13 ranks** (V-24) — whether ranked players carry a chat prefix at all.

Each answer replaces a `PROPOSED` value with an `OBSERVED` one and may change
acceptance tests; update the feature file and its test matrix together.
