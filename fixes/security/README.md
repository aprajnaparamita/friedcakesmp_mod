# Security & economy-abuse audit — FriedcakeSMP

**Audited:** 2026-09-27, `agent/ui-layout-fixes` @ `85e4a5d`, about 31k
lines of Lua across 23 `smp_*` mods. Engine behaviour was checked against
`~/dev/luanti` and `~/dev/mineclonia-git`. The method and threat model are
in [`00-PLAN.md`](00-PLAN.md).

Each `S0x` brief is **self-contained**, in the same format as the parent
`fixes/` briefs. Hand one to an agent verbatim. Rows marked **ESCALATE**
touch `smp_core`, `smp_store`, `smp_admin` or `spec/shared/`, and go to the
integrator.

## Fix these first

| # | ID | Sev | One line | Brief |
|---|---|---|---|---|
| 1 | **SP-1** | 🔴 Critical | `/spawner give` uses `privilege =` instead of `privs =`, so **any player can mint spawners**, and through them unlimited loot, XP and money | [S06](S06-spawners.md) |
| 2 | **QB-1** | 🔴 Critical | Quick Buy passes an ObjectRef as a name, so `luaL_checkstring` throws and **any player can shut the server down** | [S05](S05-shops-shards.md) |
| 3 | **AH-1** | 🟠 High | A listing routed into an order is **deleted** when the order refuses. Griefable: open a 1-item order and every matching AH listing vanishes | [S03](S03-auction.md) |
| 4 | **AX-1** | 🟠 High | The sell axe has the same misread (`accepted ~= false`) and deletes container stacks | [S05](S05-shops-shards.md) |
| 5 | **SE-4 / CB-1** | 🟠 High | Combat-log escape: items parked in `/sell` (or the orders grid) are returned **after** the combat drop | [S02](S02-sell.md) · [S07](S07-combat-bounty.md) |
| 6 | **SE-3** | 🟠 High | The $7 cobble anchor is on `mcl_walls:cobble` (the wall), so a cobble generator plus a stonecutter pays 7× | [S02](S02-sell.md) |
| 7 | **SE-1** | 🟠 High | `sell.default_price` pays $1 for every registered item: moss, bone-meal flora and craft-multiplier faucets | [S02](S02-sell.md) |
| 8 | **SE-2** | 🟠 High | $500/enchant-level bonus: XP and lapis → $2.5K–$5K per enchant. Shard gear → about $100K | [S02](S02-sell.md) |
| 9 | **SP-2 / SP-3** | 🟠 High | Spawner withdrawals destroy items (`if not add_item` never fires; `set_count > 65535` clears) | [S06](S06-spawners.md) |

## Everything else

| ID | Sev | One line | Brief |
|---|---|---|---|
| SH-2 | 🟡 Medium | AFK playtime → shards → shop gear → `/sell` at about $1K per AFK hour per alt | [S05](S05-shops-shards.md) |
| SP-4 | 🟡 Medium | Spawner menu, loot, XP and "Sell all" ignore protection by default | [S06](S06-spawners.md) |
| CB-2 | 🟡 Medium | Bounty laundering: any tagged death (including `/kill`) credits the last attacker, and the only check is same-IP | [S07](S07-combat-bounty.md) |
| OR-1 | 🟡 Medium | Orders and AH records flush every 10 s while money writes immediately, so a hard crash splits them (double refund) | [S04](S04-orders.md) |
| OR-2 | 🟡 Medium | The `fill_from_stack` refusal contract is easy to misread (the root of AH-1 and AX-1) | [S04](S04-orders.md) |
| SH-1 | 🟡 Medium | The shard shop handler uses the ObjectRef as a name, so the menu can never buy and sessions leak | [S05](S05-shops-shards.md) |
| EC-2 | 🟡 Medium | `smp_economy`'s leave handler has the same bug, so sessions are never cleared (stale Quick Buy confirm skips the 3× guard) | [S01](S01-economy-core.md) |
| EC-3 | 🟡 Medium | Unbounded offline-pay queue (1-cent spam) | [S01](S01-economy-core.md) |
| EC-4 / SE-5 | 🟡 Medium | O(N) work per `/baltop`, `/ledger` and **every sale** (mod_storage key scan) | [S01](S01-economy-core.md) · [S02](S02-sell.md) |
| TP-1 | 🟡 Medium | `/tpahere` trap: the destination is fixed at accept, the sender builds lava during warm-up, and `/tpauto` accepts without a prompt | [S08](S08-teleport.md) |
| AX-2 | 🟡 Medium | Sell axe loops `0..size-1`, so the last slot is never processed | [S05](S05-shops-shards.md) |
| EC-1 | ⚪ Low | Store primitives accept negative or NaN (a negative `take` mints). ESCALATE | [S01](S01-economy-core.md) |
| EC-5 | ⚪ Low | `/pay` into a capped balance destroys the overflow | [S01](S01-economy-core.md) |
| EC-6 | ⚪ Low | `pg_proxy.py` is unauthenticated and CSRF-able from a local browser. ESCALATE | [S01](S01-economy-core.md) |
| EC-7 | ⚪ Low | API keys come from `math.random`. Use `SecureRandom` | [S01](S01-economy-core.md) |
| SH-3 | ⚪ Low | `open_session` ignores `initial` when a session exists, so stale ids survive. ESCALATE | [S05](S05-shops-shards.md) |
| AH-2 | ⚪ Low | Type-guard `smp_ah.buy` and friends against non-string names | [S03](S03-auction.md) |
| AH-3 / OR-3 | ⚪ Low | The auction sweep underpays sellers by up to count−1 cents | [S04](S04-orders.md) |
| AH-4 | ⚪ Low | The AH insert inventory stays writable after the price step, and its items are wiped at commit | [S03](S03-auction.md) |
| AH-5 | ⚪ Low | Quick Buy matching ignores the meta hash | [S03](S03-auction.md) |
| OR-4 | ⚪ Low | The delivery version guard is re-synced on every render | [S04](S04-orders.md) |
| CB-3 | ⚪ Low | Explosion kill credit goes to the nearest TNT or anchor *puncher* | [S07](S07-combat-bounty.md) |
| TP-2 | ⚪ Low | `/tpa` to offline names allocates state | [S08](S08-teleport.md) |
| MS-1..3 | ⚪ Low | Block `/kill` in combat; add the chat-command lint; add the strict engine stub to the harness | [S09](S09-admin-social-misc.md) |

## Cross-cutting lessons (worth a CONTRIBUTING note)

1. **Chat-command definitions:** the key is `privs = {…}`. Unknown keys
   are silently ignored, so a lint is the only defence.
2. **Engine callback arguments are ObjectRefs, not names.**
   `register_on_leaveplayer` and `register_on_player_receive_fields` pass
   a player object. Three mods treated it as a name. Any C++ function that
   takes a name **raises** on an ObjectRef, which is fatal inside a
   callback. The dev-test stubs must be as strict as the engine.
3. **`InvRef:add_item` returns the leftover stack**, which is always
   truthy. `if not inv:add_item(...)` is always a bug.
4. **`ItemStack:set_count(n)` clears the stack when `n > 65535`.**
5. **`pcall(f)` success is not `f`'s success.** Read the returned values.
6. **The server price table is a faucet list.** Any price above the
   cheapest way to make the item is unlimited money. Guard it with the
   recipe-arbitrage test in S02.
7. **Leave-handler order is load order.** Anything that must run last,
   like the combat-log drop, registers in `on_mods_loaded`.

## Scope notes

- Checked end to end: `smp_core`, `smp_store` (all 3 backends and the
  proxy), `smp_economy`, `smp_items`, `smp_sell`, `smp_ah`,
  `smp_orders`, `smp_quickbuy`, `smp_shardshop`, `smp_spawners`,
  `smp_bounty`, `smp_combat`, the `smp_tp` warm-up and requests,
  `smp_enderchest`, `smp_amethyst` sell axe, `smp_social` `/kill`, and
  the admin command privileges pack-wide.
- Skimmed only: `smp_ranks`, `smp_settings`, `smp_stats` boards,
  `smp_world` (beyond protection), `smp_rtpqueue`, the `smp_tp` homes
  CRUD, and `smp_shards` beyond the award rate. No findings there, but not
  audited line by line.
- **Nothing was reproduced in a running engine.** "CONFIRMED" means the path
  was traced through the mod code **and** the relevant engine source. The
  first step of each brief's fix should be an in-engine or dev-test repro.
