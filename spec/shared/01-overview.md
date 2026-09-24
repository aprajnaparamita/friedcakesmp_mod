# 1. Overview

## 1.1 Purpose

To provide a complete, implementation-ready description of Donut SMP's
features so that equivalent gameplay and an equivalent interface can be built
for a public Luanti server running Mineclonia, with emphasis on low server
load.

## 1.2 Reference server summary

Donut SMP is a public semi-anarchy survival server for Java and Bedrock whose
gameplay centres on base hunting and Crystal PvP; bases are typically found and
raided within days to about a month [S1]. The Overworld is served through six
regional proxies (NA East, NA West, EU Central, EU West, Asia, Oceania), while
the Nether and End exist only on NA East [S1]. Season 1 ended because of an
over-inflated economy and duplication; Season 2 is described as permanent [S1].

Between 9 and 29 June 2026 the "Big June Update" linked selling, orders and the
auction house, replaced the fixed-price shop with Quick Buy, changed shard
earning and adjusted many vanilla mechanics [S2]. Teams and Duels were removed
on 2 June 2026 [S12][S13]; crates and the AFK zone were removed in a separate
update [S11][S8].

### Observed client context

The source video was recorded on Lunar Client running `Version 1.21.11
(v2.22.23-2630)` [F0142, F0242]. Two consequences:

1. Some on-screen elements belong to the **client**, not the server: the
   coordinate and biome readout, the `[Sprinting (Toggled)]` indicator, the
   `LUNAR CLIENT` watermark, the FPS/ping readout. These MUST NOT be
   reimplemented as server features. They are noted in feature files where
   they could be mistaken for server UI.
2. The money readout `Voire $ 754k` bottom-right [F0287] **is** server-driven
   (a scoreboard), and a `Scoreboard` settings category exists [F0237], so it
   is in scope.

## 1.3 Scope

**In scope:** economy (money, shards, `/sell`, auction house, orders, Quick
Buy, shard shop, timed shard tools), virtual spawners, teleportation (random
teleport, RTP queue, teleport requests, homes, spawn, warps), combat tagging
and combat logging, bounties, chat and social systems, ranks, statistics and
leaderboards, player settings, world rules, and legacy modules (crates, AFK
zone, teams, duels, kill rewards, fixed-price shop) — documentation only,
permanently descoped (D8, 2026-09-24), never to be built.

**Out of scope:**

| Item | Reason |
|---|---|
| Regional proxy network, Bedrock crossplay | Network infrastructure rather than gameplay; Luanti has no Bedrock client |
| Web store, subscriptions, payment processing | Commercial integration. Admin grant commands are provided instead (f13) |
| Discord or web account linking, MedalTV promotion | External services. Informational commands only (f11) |
| Proximity voice chat | Donut SMP uses Simple Voice Chat [S21]; Luanti has no built-in voice channel |
| Client integrity checks | Specific to the Java client. Luanti anticheat mapping is in f15 |
| Client-side HUD mods (Lunar Client overlays) | Not server features; see §1.2 |

## 1.4 Design goals

| Id | Goal |
|---|---|
| G1 | **Lag-free.** No mob entities in the spawner economy, no ABMs, lazy O(1) state updates, bounded per-step work |
| G2 | **Economic integrity.** Atomic transactions, escrowed commitments, an append-only ledger, duplication-resistant menus. Donut SMP's own first season ended because of inflation and duplication [S1] |
| G3 | **Configuration-driven.** Every price, rate, limit and timer is a configuration value (`06-config-reference.md`) |
| G4 | **Modular.** One mod per feature; legacy features were planned as optional mods — permanently descoped (D8, 2026-09-24), never to be built |
| G5 | **Traceable fidelity.** Reproduce observed behaviour exactly, reproduce documented behaviour faithfully, and label every assumption |

G5 is the goal this version strengthens. 141 frames of interface evidence mean
much of the interface no longer needs to be inferred.
