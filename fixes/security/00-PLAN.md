# Security & economy-abuse audit — plan

**Started:** 2026-09-27 · **Branch audited:** `agent/ui-layout-fixes` @ `85e4a5d`
**Scope:** `friedcake/mods/smp_*` (~31k lines Lua). Out of scope: engine
(Luanti / Mineclonia) bugs, unless a mod relies on an unsafe engine behaviour.

## Threat model

The attacker is an **ordinary logged-in player** with a modified client. A
modified client can:

- send **any** `fields` table to `on_player_receive_fields`, under **any**
  `formname`, at any time — including for a formspec that was never shown,
  or one that was shown and has since been closed;
- send fields repeatedly and quickly (double-click, macro, packet replay);
- send strings of any length or content (negative numbers, `nan`, `inf`,
  `1e308`, hex, formspec escape characters, newlines, colour codes);
- move items between inventory lists that the server exposes to it
  (detached inventories, node inventories, `current_player`);
- disconnect at any moment (mid-transaction, while combat-tagged, while a
  `core.after` callback is pending);
- log in as two accounts, and coordinate them.

Secondary attacker: a player holding a **lesser privilege** (rank perks,
`smp_mod`-style privileges) who tries to reach admin-only functions.

## What counts as a finding

| Class | Examples |
|---|---|
| **Dupe** | items or money created without being removed elsewhere |
| **Economic** | arbitrage loops, rounding leaks, negative amounts, overflow, price manipulation, refunds larger than the charge |
| **Authorisation** | a player acting on another player's listing, order, home, spawner or balance; missing privilege checks |
| **Input trust** | trusting `fields` from a client, unbounded strings or numbers, formspec or chat injection |
| **State/race** | yield between validate and mutate (AGENTS.md rule 8), stale session state, leave or crash mid-operation, persistence lost on crash |
| **DoS** | unbounded loops, per-player storage growth, spam of expensive operations |
| **Gameplay abuse** | escaping combat, teleporting into protected or other areas, bypassing cooldowns |

Severity: **Critical** (unbounded money/item creation, or admin takeover) ·
**High** (bounded dupe, theft from another player, or permanent state
corruption) · **Medium** (bypass of a rule or limit, or a DoS a single player
can trigger) · **Low** (hardening, info leak, cosmetic injection).

## Steps

Each step records its findings in its own brief. The briefs are
self-contained, the same way the `fixes/` briefs are: any one of them can be
handed to an agent as its task.

| Step | Area | Files | Output |
|---|---|---|---|
| 1 | Money primitives: parse and format, balances, `/pay`, ledger, persistence flush | `smp_core`, `smp_store`, `smp_economy` | `S01-economy-core.md` |
| 2 | Formspec plumbing: sessions, formname routing, field trust | `smp_core` (session and widget), every `on_player_receive_fields` | folded into each brief, and summarised in `README.md` |
| 3 | Sell pipeline: prices, enchant bonus, sell GUI inventory, sell axe | `smp_sell` | `S02-sell.md` |
| 4 | Auction house: list, buy, cancel, expire, reclaim | `smp_ah` | `S03-auction.md` |
| 5 | Orders: escrow, delivery, collect, cancel refund | `smp_orders` | `S04-orders.md` |
| 6 | Quick Buy, shards, shard shop, amethyst tools | `smp_quickbuy`, `smp_shards`, `smp_shardshop`, `smp_amethyst` | `S05-shops-shards.md` |
| 7 | Spawners: accrual, stacking, loot and XP withdrawal, break and pickup | `smp_spawners` | `S06-spawners.md` |
| 8 | Combat, combat log, bounty escrow | `smp_combat`, `smp_bounty` | `S07-combat-bounty.md` |
| 9 | Teleport, homes, RTP, RTP queue | `smp_tp`, `smp_rtpqueue` | `S08-teleport.md` |
| 10 | Admin, ranks, social, settings, stats, world, enderchest | the rest | `S09-admin-social-misc.md` |
| 11 | Triage: dedupe, rank, index | — | `README.md` |

## Method for each step

1. Enumerate every **entry point**: chat commands, formspec handlers, node
   callbacks, detached-inventory callbacks, globalsteps, `on_joinplayer` and
   `on_leaveplayer`.
2. For each economic operation, trace **validate → mutate → ledger** and
   check the following:
   - number parsing (sign, NaN, infinity, fraction, overflow);
   - ownership and authorisation;
   - a yield between validation and mutation;
   - item removal *before* credit;
   - partial failure: a full inventory, the item disappearing from the
     inventory, or an offline recipient.
3. Record each finding with a **`file:line`**, a **reproduction** for a
   modified client, the **impact**, and a **fix guide** that includes a test.
4. Where you can, confirm the finding against the code a second time (by
   tracing callers) before you write it down. Mark each finding
   **CONFIRMED** (traced end to end) or **SUSPECTED** (still needs an
   in-engine repro).

## Constraints the fix guides must respect (AGENTS.md)

- `smp_core`, `smp_store`, `smp_admin`: fixes there are **ESCALATE**. Propose
  them for the integrator; do not edit.
- Money is integer cents. `smp_core.fmt_money`. No floats.
- No yield between validate and mutate.
- Tests: `friedcake/dev-tests/test_<feature>.lua` + in-mod `test.lua`.
