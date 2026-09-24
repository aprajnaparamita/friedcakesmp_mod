# 2. System Architecture

## 2.1 Mod decomposition

| Mod | Responsibility | Depends on | Phase | Spec file |
|---|---|---|---|---|
| `smp_core` | Configuration, money and number formatting and parsing, translation, per-player menu sessions, shared formspec widgets, event bus | `mcl_formspec`, `mcl_title` (optional) | P0 | `04-ui-kit.md` |
| `smp_store` | Persistence abstraction (mod storage or SQLite), ledger | `smp_core` | P0 | §2.3 |
| `smp_items` | Canonical item keys, matching levels, shulker content codec | `mcl_enchanting`, `mcl_chests` | P0 | §2.6 |
| `smp_economy` | Money and shard balances, `/bal`, `/pay`, `/baltop`, `/shards` | `smp_store` | P0 | `f01` |
| `smp_ranks` | Tiers, expiry, perk limits, chat prefix | `smp_store` | P0 | `f13` |
| `smp_admin` | `/eco`, audit and moderation helpers | all | P0–P7 | `f01` |
| `smp_sell` | `/sell`, base prices, `/worth`, `/sellhistory`, sell routing | `smp_economy`, `smp_items` | P1 | `f02` |
| `smp_spawners` | Virtual spawners | `smp_sell`, `mcl_experience`, `mcl_enchanting` | P2 | `f07` |
| `smp_ah` | Auction house | `smp_economy`, `smp_items` | P3 | `f03` |
| `smp_orders` | Buy orders, auction and order routing | `smp_ah`, `smp_sell` | P3 | `f04` |
| `smp_quickbuy` | `/shop` Quick Buy | `smp_ah` | P3 | `f05` |
| `smp_tp` | Teleport framework, `/rtp`, teleport requests, homes, `/spawn`, `/warp`, `/world` | `mcl_worlds`, `mcl_spawn` | P4 | `f08`, `f09` |
| `smp_combat` | Combat tag, combat log | `mcl_death_drop` | P5 | `f10` |
| `smp_bounty` | Bounties | `smp_combat`, `smp_economy` | P5 | `f10` |
| `smp_shards` | Playtime shard awards | `smp_economy` | P6 | `f06` |
| `smp_shardshop` | Shard shop | `smp_shards` | P6 | `f06` |
| `smp_amethyst` | Timed shard tools and haste potion | `mcl_potions` | P6 | `f06` |
| `smp_settings` | `/settings` | `smp_core` | P7 | `f12` |
| `smp_social` | Chat format, `/msg`, `/r`, `/ignore`, `/block`, friends, `/findplayer`, `/kill`, `/nv`, informational commands | `smp_settings` | P7 | `f11` |
| `smp_stats` | Statistics, leaderboards, scoreboard, API export | economy mods | P7 | `f14` |
| `smp_rtpqueue` | Paired random teleport | `smp_tp`, `smp_combat` | P8 | `f08` |
| `smp_crates`, `smp_afk`, `smp_teams`, `smp_duels`, `smp_servershop` | Legacy modules | various | n/a *(f16 descoped — D8, 2026-09-24)* | `f16` |

**Dependency note (f01 §10.2 F-1, ruled 2026-09-25):** `smp_economy`
deliberately does **not** declare `optional_depends = smp_social`, even
though it calls `smp_social.blocks_only()` — declaring it would close the
boot cycle `economy → social → combat → stats → economy`
(`smp_social` optionally depends on `smp_combat`, `smp_combat` optionally
depends on `smp_stats`, `smp_stats` hard-depends on `smp_economy`), which
aborts real boots. The call is guarded (`if smp_social and …`) and runs at
command time, so load order cannot break it. Do not "fix" this by adding
the edge.

## 2.2 Persistence

`smp_store` MUST expose a small table API with two interchangeable backends:

1. **Mod storage (default).** `core.get_mod_storage()` holding JSON documents
   (`core.write_json`, `core.parse_json`). In-memory indexes are rebuilt at
   start-up; writes are batched with dirty flags and flushed every 10 s
   (`PROPOSED`) and in `core.register_on_shutdown`.
2. **SQLite (recommended at scale).** Through
   `core.request_insecure_environment()` (the mod must be listed in
   `secure.trusted_mods`) and a host-installed `lsqlite3` module. Use it for
   auction listings, auction transactions, orders, sell history and the ledger
   once record counts exceed roughly 10⁴.

The observed server runs at a scale that makes the second backend the realistic
choice: a single order for `300K requested` totems [F0219] and another
`167k/200k Delivered` [F0212] imply order and delivery volumes far above what
mod storage handles comfortably.

| Data | Location |
|---|---|
| Balances, statistics, homes, rank, key balances | `smp_store` player records (offline players must be enumerable for leaderboards) |
| Settings, transient flags (for example combat-logged) | Player meta (`player:get_meta()`) |
| Auction listings and transactions, orders, bounties, sell history, ledger | `smp_store` tables |
| Spawner state | Node metadata of the spawner node |

## 2.3 Transaction model

Luanti runs mod Lua on a single server thread (outside the async environment),
so the steps of one callback are never interleaved with another callback. Every
economic operation MUST:

1. Validate all preconditions first: balances, inventory space, and that the
   record is still open and unchanged.
2. Mutate in a fixed order: remove the source value (money or items), add the
   destination value, append a ledger entry, mark records dirty.
3. Never yield (no `core.after`) between validation and mutation.
4. Record a ledger entry with a monotonically increasing id (schema in `f01`).

The observed interface confirms this matters: the chat line
`This item was already bought` [F0037, F0055] is the reference server's
response to a purchase losing a race. An equivalent message and an equivalent
re-validation are required.

## 2.4 Menu framework

All menus are formspecs laid out like chest interfaces, matching the observed
design. The reusable widget set, the observed menu grammar and the formspec
mapping are specified in `04-ui-kit.md`.

Menu state lives server-side in a per-player session keyed by formname; client
fields are untrusted and every action is re-validated. Detached inventories
(`core.create_detached_inventory(name, callbacks, player_name)`) are used only
where drag-and-drop is required (sell container, auction insert, order
delivery), with `allow_put`, `allow_take` and `allow_move` enforcing ownership
and eligibility.

## 2.5 Item identity and matching (normative)

The canonical key of a stack consists of:

- `name`: registered name after alias resolution;
- `ench`: sorted `id:level` list from `mcl_enchanting.get_enchantments`;
- `wear`: raw wear value (0 means pristine);
- `named`: whether the stack carries a custom name;
- `contents`: hash of shulker contents, if any;
- `meta_hash`: hash of the remaining non-volatile metadata.

A **plain** stack has no enchantments, zero wear, no custom name, no contents
and no other non-volatile metadata.

| Level | Compares | Used by |
|---|---|---|
| M0 | `name`, plain stacks only | `/sell` base prices, `/worth` |
| M1 | `name`, `ench` and `meta_hash`; requires zero wear, no custom name and no contents | Orders, sell routing, Quick Buy |
| M2 | The full key including wear, name flag and contents | Auction display, grouping and search |

Donut SMP notes that a renamed item is not proof of its contents or properties
[S5]; M1 therefore rejects named stacks.

**M1 includes enchantments, and the observed interface proves it.** An order
for `Netherite Helmets` lists `Protection IV, Respiration III, Aqua Affinity,
Unbreaking III, Mending` in its tooltip [F0164] — the enchantment set is part
of what is being ordered, and a delivery MUST match it. An order display
therefore renders the enchantment list between the item name and the price.

## 2.6 Economic integrity and anti-abuse

| Id | Requirement |
|---|---|
| R1 | Every economic operation follows §2.3 |
| R2 | Orders and bounties hold escrow, and payouts come only from escrow |
| R3 | Ledger reason codes: `sell`, `ah_list`, `ah_buy`, `ah_sale`, `order_escrow`, `order_payout`, `order_refund`, `pay`, `bounty_escrow`, `bounty_payout`, `shard_award`, `shard_spend`, `admin` |
| R4 | Formspec handlers check the formname, use the server-side session and re-validate every action |
| R5 | Detached inventories allow moves only by the owning player and only for eligible items |
| R6 | When a player leaves, sessions are closed and items in temporary containers (sell container, auction insert, order delivery) are returned to the inventory before the player is saved |
| R7 | Node menus (spawners, crates) re-check the node and the player's distance on every action |
| R8 | Shulker decoding is one level deep; Mineclonia does not allow shulkers inside shulkers [M1] |
| R9 | Rate limits on `/pay`, auction listing and order creation (`PROPOSED` one per second each) |
| R10 | Alternate-account and real-money-trading heuristics: flags on transfers to low-playtime accounts [S24] and on accounts per IP address [S18] |
| R11 | Staff audit through `/ledger <player>`, with a manual reversal helper |
| R12 | Crash safety: flush on shutdown and periodically; multi-record operations write a pending marker that is checked at start-up |

## 2.7 Performance budget

No ABMs; global-step work at most O(online players) per second; storage flushes
every 10 s; spawner timers every 60 s; leaderboard snapshots every 300 s.

Menu rendering is bounded by page size, never by table size. The observed
auction and orders menus are paginated (`Auction (Page 1)` [F0108],
`Orders (Page 1)` [F0156]) precisely because the underlying tables are large.
