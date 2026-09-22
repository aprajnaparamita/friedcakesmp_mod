# Donut SMP Feature Specification for Re-implementation on Luanti (Mineclonia)

| Field | Value |
|---|---|
| Document type | Functional and technical design specification |
| Version | 0.1 (draft for review) |
| Date | 2026-09-22 |
| Target engine | Luanti 5.10 or later (the minimum declared in Mineclonia's `game.conf`) |
| Target game | Mineclonia (interfaces verified against the GitHub mirror, commit `5bdce566`, 2026-09-21) |
| Reference server | Donut SMP (`donutsmp.net`), as documented through September 2026 |

> **Abstract.** This document catalogues the player-facing features of the Donut SMP Minecraft server (economy, virtual spawners, teleportation, combat, social systems, ranks, statistics, and features Donut SMP has since removed) and specifies how each should behave and be implemented as Luanti mods on top of Mineclonia. Every requirement carries an evidence tag so implementers can separate documented Donut SMP behaviour from behaviour inferred from third-party "Donut-style" clone plugins and from defaults proposed by this specification.

## Table of Contents

0. Conventions
1. Introduction
2. System Architecture
3. Command Reference
4. Economy
5. Virtual Spawners
6. Teleportation and Navigation
7. Combat and PvP
8. Social and Communication
9. Ranks and Membership
10. Statistics, Leaderboards and API
11. Player Settings
12. World Rules and Server Configuration
13. Legacy Features (Removed from Donut SMP)
14. Economic Integrity and Anti-Abuse
15. Implementation Roadmap
16. Open Questions and Verification Checklist
17. Screenshot and Visual Reference Index
18. Sources
- Appendix A. Data Schemas
- Appendix B. GUI Wireframes
- Appendix C. Reference Algorithms
- Appendix D. Luanti and Mineclonia API Mapping
- Appendix E. Consolidated Configuration Reference

---

## 0. Conventions

### 0.1 Requirement keywords

MUST, SHOULD and MAY are used as defined in RFC 2119.

### 0.2 Evidence tags

| Tag | Meaning |
|---|---|
| `LIVE` | Documented as current Donut SMP behaviour (September 2026). |
| `LEGACY` | Documented Donut SMP behaviour that has since been removed. Specified here as an optional module. |
| `CLONE` | Not documented for Donut SMP itself; taken from Donut-style clone plugins. Plausible, not authoritative. |
| `PROPOSED` | A default or design decision introduced by this specification. Replace with measured values where possible. |
| `N/A` | No practical Luanti equivalent; listed for completeness. |

Where a feature is only partly documented, the documented part carries its tag and the undocumented remainder is marked `PROPOSED`.

### 0.3 Citations

Bracketed identifiers such as [S5] or [C1] refer to §18. Prefixes: `S` Donut SMP sources (official or community), `C` clone-plugin documentation, `M` Mineclonia source code, `T` independent tools, `V` videos.

### 0.4 Screenshots

Placeholders use the form `![SS-nn: caption](screenshots/SS-nn-slug.png)`. Save an image at the given relative path and the link resolves; until then it renders as a broken image. The complete list is in §17.2.

### 0.5 Naming

All mods use the working prefix `smp_` (for example `smp_spawners`). Rank tiers are `tier1` to `tier3` in configuration; Donut SMP rank names (Donut+, Donut++, Donut+++) appear only to describe the reference server. The target server should use its own branding: this specification covers mechanics only. Itemstrings are Mineclonia's (for example `mcl_mobitems:bone`).

### 0.6 Units and formatting

- Money is displayed with a `$` prefix and compact suffixes K (10^3), M (10^6), B (10^9) and T (10^12), for example `$1.5M`. Every numeric input MUST accept the same suffixes case-insensitively (`250k`, `1.5m`).
- Durations are in seconds unless stated otherwise.
- "Stack" means a Luanti ItemStack. "Spawner stack" means the number of spawners merged into one spawner node (§5).

---

## 1. Introduction

### 1.1 Purpose

To provide a complete, implementation-ready description of Donut SMP's features so that equivalent gameplay can be built for a public Luanti server running Mineclonia, with emphasis on low server load.

### 1.2 Reference server summary

Donut SMP is a public semi-anarchy survival server for Java and Bedrock whose gameplay centres on base hunting and Crystal PvP; bases are typically found and raided within days to about a month [S1]. The Overworld is served through six regional proxies (NA East, NA West, EU Central, EU West, Asia, Oceania), while the Nether and End exist only on NA East [S1]. Season 1 ended because of an over-inflated economy and duplication; Season 2 is described as permanent [S1].

Between 9 and 29 June 2026 the "Big June Update" linked selling, orders and the auction house, replaced the fixed-price shop with Quick Buy, changed shard earning and adjusted many vanilla mechanics [S2]. Teams and Duels were removed on 2 June 2026 [S12][S13]; crates and the AFK zone were removed in a separate update [S11][S8].

### 1.3 Scope

**In scope:** economy (money, shards, `/sell`, auction house, orders, Quick Buy, shard shop, timed shard tools), virtual spawners, teleportation (random teleport, RTP queue, teleport requests, homes, spawn, warps), combat tagging and combat logging, bounties, chat and social systems, ranks, statistics and leaderboards, player settings, world rules, and legacy modules (crates, AFK zone, teams, duels, kill rewards, fixed-price shop).

**Out of scope:**

| Item | Reason |
|---|---|
| Regional proxy network, Bedrock crossplay | Network infrastructure rather than gameplay; Luanti has no Bedrock client. |
| Web store, subscriptions, payment processing | Commercial integration. Admin grant commands are provided instead (§9). |
| Discord or web account linking, MedalTV promotion | External services. Informational commands only (§8.8). |
| Proximity voice chat | Donut SMP uses Simple Voice Chat [S21]; Luanti has no built-in voice channel. |
| Client integrity checks | Specific to the Java client. Luanti anticheat mapping is in §12.1. |

### 1.4 Design goals for the target server

- **G1 Lag-free.** No mob entities in the spawner economy, no ABMs, lazy O(1) state updates and bounded per-step work.
- **G2 Economic integrity.** Atomic transactions, escrowed commitments, an append-only ledger and duplication-resistant menus. Donut SMP's own first season ended because of inflation and duplication [S1].
- **G3 Configuration-driven.** Every price, rate, limit and timer is a configuration value (Appendix E).
- **G4 Modular.** One mod per feature; legacy features are optional mods.
- **G5 Traceable fidelity.** Reproduce documented behaviour and label every assumption.

---

## 2. System Architecture

### 2.1 Mod decomposition

| Mod | Responsibility | Depends on | Phase |
|---|---|---|---|
| `smp_core` | Configuration, money and number formatting and parsing, translation, per-player menu sessions, shared formspec widgets, event bus | `mcl_formspec`, `mcl_title` (optional) | P0 |
| `smp_store` | Persistence abstraction (mod storage or SQLite), ledger | `smp_core` | P0 |
| `smp_items` | Canonical item keys, matching levels, shulker content codec | `mcl_enchanting`, `mcl_chests` | P0 |
| `smp_economy` | Money and shard balances, `/bal`, `/pay`, `/baltop`, `/shards` | `smp_store` | P0 |
| `smp_ranks` | Tiers, expiry, perk limits, chat prefix | `smp_store` | P0 |
| `smp_admin` | `/eco`, audit and moderation helpers | all | P0 to P7 |
| `smp_sell` | `/sell`, base prices, `/worth`, `/sellhistory`, sell routing | `smp_economy`, `smp_items` | P1 |
| `smp_spawners` | Virtual spawners | `smp_sell`, `mcl_experience`, `mcl_enchanting` | P2 |
| `smp_ah` | Auction house | `smp_economy`, `smp_items` | P3 |
| `smp_orders` | Buy orders, auction and order routing | `smp_ah`, `smp_sell` | P3 |
| `smp_quickbuy` | `/shop` Quick Buy | `smp_ah` | P3 |
| `smp_tp` | Teleport framework, `/rtp`, teleport requests, homes, `/spawn`, `/warp`, `/world` | `mcl_worlds`, `mcl_spawn` | P4 |
| `smp_combat` | Combat tag, combat log | `mcl_death_drop` | P5 |
| `smp_bounty` | Bounties | `smp_combat`, `smp_economy` | P5 |
| `smp_shards` | Playtime shard awards | `smp_economy` | P6 |
| `smp_shardshop` | Shard shop | `smp_shards` | P6 |
| `smp_amethyst` | Timed shard tools and haste potion | `mcl_potions` | P6 |
| `smp_settings` | `/settings` | `smp_core` | P7 |
| `smp_social` | Chat format, `/msg`, `/r`, `/ignore`, `/block`, friends, `/findplayer`, `/kill`, `/nv`, informational commands | `smp_settings` | P7 |
| `smp_stats` | Statistics, leaderboards, API export | economy mods | P7 |
| `smp_rtpqueue` | Paired random teleport | `smp_tp`, `smp_combat` | P8 |
| `smp_crates`, `smp_afk`, `smp_teams`, `smp_duels`, `smp_servershop` | Legacy modules (§13) | various | P8 |

### 2.2 Verified Mineclonia interfaces

The following were verified in the Mineclonia source [M1]. The complete mapping is in Appendix D.

| Interface | Use in this specification |
|---|---|
| `mcl_enchanting.get_enchantments(stack)`, `set_enchantments`, `has_enchantment(stack, id)`, `get_enchantment`, `enchant(stack, id, level)`. Stored as a serialized table in item meta key `mcl_enchanting:enchantments`. | Item matching, shard-shop gear, Silk Touch checks (id `silk_touch`) |
| `mcl_worlds.pos_to_dimension(pos)`; Y bands `mcl_vars.mg_overworld_min/max`, `mg_nether_min/max`, `mg_end_min/max`, `mg_bedrock_nether_top_max` | RTP dimensions, `/findplayer` |
| `mcl_experience.add_xp(player, xp)`, `mcl_experience.throw_xp(pos, xp)` | Spawner XP collection |
| `mcl_title.set(player, type, {text = ..., color = ..., stay = ...})` | Action-bar countdowns |
| `mcl_formspec.get_itemslot_bg_v4(x, y, w, h, size, texture)` | Slot backgrounds in menus |
| `mcl_death_drop.register_dropped_list(inv, listname, drop)`; registered lists `main`, `craft`, `armor`, `offhand`; setting `mcl_keepInventory` | Combat-log drops |
| `mcl_potions.give_effect_by_level(name, object, level, duration, no_particles)`, `clear_effect`, `has_effect`; effect ids `haste`, `night_vision` | Haste potion, `/nightvision` |
| `mcl_spawn.get_world_spawn_pos(obj)`, `mcl_spawn.get_player_spawn_pos(player)` | Spawn, respawn after combat log |
| Mob entity callback `on_die(self, pos, mcl_reason)`, called by `mcl_mobs` on death | Mob-kill statistics |
| Arrow entity field `_shooter` (ObjectRef of the shooter) | Projectile combat attribution |
| Shulker item contents in item meta under `compressed` (base64 of zstd) or the empty key `""` (serialized list); shulkers cannot hold shulkers | Selling from shulkers, auction previews |
| Present: `mcl_tools:mace`, enchantments `density` and `wind_burst`, end crystals (`mcl_end`), respawn anchors (`mcl_beds`). Absent: spears. | Shard shop mapping, PvP notes |

### 2.3 Persistence

`smp_store` MUST expose a small table API with two interchangeable backends:

1. **Mod storage (default).** `core.get_mod_storage()` holding JSON documents (`core.write_json`, `core.parse_json`). In-memory indexes are rebuilt at start-up; writes are batched with dirty flags and flushed every 10 s (`PROPOSED`) and in `core.register_on_shutdown`.
2. **SQLite (recommended at scale).** Through `core.request_insecure_environment()` (the mod must be listed in `secure.trusted_mods`) and a host-installed `lsqlite3` module. Use it for auction listings, auction transactions, orders, sell history and the ledger once record counts exceed roughly 10^4.

| Data | Location |
|---|---|
| Balances, statistics, homes, rank, key balances | `smp_store` player records (offline players must be enumerable for leaderboards) |
| Settings, transient flags (for example combat-logged) | Player meta (`player:get_meta()`) |
| Auction listings and transactions, orders, bounties, sell history, ledger | `smp_store` tables |
| Spawner state | Node metadata of the spawner node |

### 2.4 Transaction model

Luanti runs mod Lua on a single server thread (outside the async environment), so the steps of one callback are never interleaved with another callback. Every economic operation MUST:

1. Validate all preconditions first: balances, inventory space, and that the record is still open and unchanged.
2. Mutate in a fixed order: remove the source value (money or items), add the destination value, append a ledger entry, mark records dirty.
3. Never yield (no `core.after`) between validation and mutation.
4. Record a ledger entry with a monotonically increasing id (schema in Appendix A).

### 2.5 Menu framework

All menus are formspecs laid out like chest interfaces: 9-column grids, a paging row, confirmation dialogs, amount and price inputs with suffix parsing, a search field and a sort toggle, using `formspec_version[6]` or later. Menu state lives server-side in a per-player session keyed by formname; client fields are untrusted and every action is re-validated. Detached inventories (`core.create_detached_inventory(name, callbacks, player_name)`) are used only where drag-and-drop is required (sell container, order delivery), with `allow_put`, `allow_take` and `allow_move` enforcing ownership and eligibility.

### 2.6 Item identity and matching (normative)

The canonical key of a stack consists of:

- `name`: registered name after alias resolution;
- `ench`: sorted `id:level` list from `mcl_enchanting.get_enchantments`;
- `wear`: raw wear value (0 means pristine);
- `named`: whether the stack carries a custom name;
- `contents`: hash of shulker contents, if any;
- `meta_hash`: hash of the remaining non-volatile metadata.

A **plain** stack has no enchantments, zero wear, no custom name, no contents and no other non-volatile metadata.

| Level | Compares | Used by |
|---|---|---|
| M0 | `name`, plain stacks only | `/sell` base prices, `/worth` |
| M1 | `name`, `ench` and `meta_hash`; requires zero wear, no custom name and no contents | Orders, sell routing, Quick Buy |
| M2 | The full key including wear, name flag and contents | Auction display, grouping and search |

Donut SMP notes that a renamed item is not proof of its contents or properties [S5]; M1 therefore rejects named stacks.

### 2.7 Localization

Donut SMP added server translations in 30 languages in a July 2026 beta, selected from the player's client language [S22]. Luanti already translates server strings into each client's language through `core.get_translator(textdomain)` and translation files; every player-facing string MUST use it.

### 2.8 Numeric representation

Money is stored as integer cents in Lua numbers, which are exact up to 2^53. The maximum balance is 10^13 dollars (10^15 cents), following clone defaults [C1]. Inputs MUST reject negative, NaN and infinite values. Fees round down in the payer's favour.

---

## 3. Command Reference

Commands tagged `LIVE` appear in Donut SMP command listings or wiki articles [S24][S26]; `CLONE` commands come from Donut-style plugin documentation [C1]. Luanti's built-in `/msg` is replaced with `core.override_chatcommand`; the built-in `/teleport` is left to staff, and `/tp` is registered separately as a request alias (§6.4). Commands blocked during combat are listed in §7.2.

### 3.1 Economy

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/bal` | `/balance`, `/money` | `[player]` | Show a money balance (another player's balance is `PROPOSED`) | LIVE [S24] |
| `/pay` | — | `<player> <amount>` | Transfer money (§4.2) | LIVE [S24] |
| `/paytoggle` | `/paymenttoggle` | — | Toggle receiving payments | CLONE [C1] |
| `/baltop` | `/moneytop` | `[page]` | Money leaderboard | LIVE [S24] |
| `/sell` | — | — | Open the sell container (§4.3) | LIVE [S3] |
| `/sell hand`, `/sell all` | — | — | Sell the held stack or the whole inventory | CLONE [C1] |
| `/sellhistory` | — | `[page]` | Past server sales | LIVE [S3] |
| `/worth` | — | `[item]` | Show a base price | CLONE [C1] |
| `/ah` | `/auction`, `/auctionhouse` | `[search]` | Open or search the auction house (§4.4) | LIVE [S5] |
| `/ah sell` | `/auction sell` | `<price>` | List the held stack | LIVE [S5] |
| `/orders` | — | — | Open the orders board (§4.5) | LIVE [S6] |
| `/order` | — | `[search]` | Search orders | LIVE [S6] |
| `/shop` | — | — | Quick Buy (§4.6) | LIVE [S7] |
| `/shards` | `/shard` | — | Shard balance | CLONE [C1] |
| `/bounty` | `/bounties` | `[player]` | Bounty list, or one player's bounty (§7.3) | LIVE [S24] |
| `/bounty add` | — | `<player> <amount>` | Place or raise a bounty | LIVE [S24] |

### 3.2 Teleportation

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/rtp` | — | `[dimension or region]` | Random teleport (§6.2) | LIVE [S14][S26][S27] |
| `/rtpqueue` | — | — | Join or leave the paired random-teleport queue (§6.3) | LIVE, beta [S15] |
| `/tpa` | `/tp` | `<player>` | Ask to teleport to a player | LIVE [S26] |
| `/tpahere` | — | `<player>` | Ask a player to teleport to you | LIVE [S26] |
| `/tpaccept` | — | `<player>` | Accept a request (an argument-free form that accepts the newest request is `PROPOSED`) | LIVE [S26] |
| `/tpadeny` | `/tpdeny` | `<player>` | Deny a request | LIVE [S26]; alias CLONE [C1] |
| `/tpacancel` | — | `[player]` | Cancel an outgoing request | LIVE [S26] |
| `/tpauto` | — | — | Toggle automatic acceptance | LIVE [S26] |
| `/tpatoggle`, `/tpaheretoggle` | — | — | Toggle receiving each request type | CLONE [C1] |
| `/home` | `/homes` | `[id]` | Homes menu, or teleport to a home (§6.5) | LIVE [S24][S26] |
| `/sethome` | — | `[name]` | Save the current position as a home | LIVE [S25][S26] |
| `/delhome` | — | `<id>` | Delete a home | LIVE [S24] |
| `/spawn` | — | `[lobby]` | Spawn-lobby menu, or a named lobby | LIVE [S26] |
| `/warp` | — | `<location>` | Teleport to a spawn utility location | LIVE [S26] |
| `/world` | — | — | Return to the position before the last teleport command | LIVE [S26] |
| `/back` | `/return` | — | Previous location; disabled by default (`PROPOSED`) | CLONE [C1] |

### 3.3 Social, information and utility

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/msg` | `/message`, `/tell`, `/w`, `/whisper`, `/pm` | `<player> <message>` | Private message (§8.2) | LIVE [S24]; aliases other than `/message` CLONE [C1] |
| `/r` | `/reply` | `<message>` | Reply to the last private message | CLONE [C1] |
| `/ignore` | — | `<player>` | Ignore a player (§8.3) | LIVE [S24] |
| `/block` | — | `<player>` | Block a player (§8.3) | LIVE [S24] |
| `/friend` | `/friends` | `[list, friends, followers, following, search, addsearch]` | Follow and friends system (§8.4) | LIVE [S24] |
| `/findplayer` | `/fp` | `<player>` | Coarse location of a player (§8.5) | LIVE [S23][S24] |
| `/stats` | — | `[player]` | Statistics menu (§10.1) | LIVE [S23] |
| `/leaderboard` | `/lb`, `/leaderboards` | `[category]` | Leaderboards (§10.2) | LIVE [S24] |
| `/settings` | — | — | Settings menu (§11) | LIVE [S20] |
| `/nightvision` | `/nv` | — | Toggle night vision (§8.7) | LIVE [S28] |
| `/kill` | — | — | Drop items and respawn, after confirmation (§8.6) | LIVE [S24]; confirmation CLONE [C1] |
| `/help`, `/rules` | — | — | Information screens | LIVE [S24] |
| `/discord`, `/media`, `/link`, `/buy`, `/website`, `/ranks`, `/medal` | `/store` (for `/buy`) | — | Informational and external links (§8.8, §9) | LIVE [S24][S2] |
| `/api` | — | `[delete]` | Issue or revoke a personal API key (§10.3) | LIVE [S23][S24] |
| `/ping`, `/list` | `/who`, `/online` (for `/list`) | — | Latency; online players | CLONE [C1] |
| `/report`, `/helpop` | `/ac` (for `/helpop`) | `<player> <reason>`; `<message>` | Reports and messages to staff | CLONE [C1] |

### 3.4 Legacy (optional modules)

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/afk` | — | — | Teleport to the AFK zone (§13.2) | LEGACY [S24][S8] |
| `/team` | — | subcommands in §13.3 | Teams | LEGACY [S12] |
| `/duel` | — | `<player>`; `draw <player>` | Duels (§13.4) | LEGACY [S13] |
| `/warp crates`, `/crates` | — | — | Crates (§13.1) | LEGACY [S11][S25]; `/crates` CLONE [C1] |

### 3.5 Administration

All entries are `PROPOSED` except `/eco`, which follows a clone [C1].

| Command | Arguments | Purpose |
|---|---|---|
| `/eco` | `give`, `take`, `set` or `reset` `<player> <amount>` | Adjust money |
| `/shardsadmin` | `give`, `take` or `set` `<player> <amount>` | Adjust shards |
| `/rank` | `set <player> <tier> <days>`; `clear <player>` | Grant or clear tiers |
| `/spawner` | `give <player> <type> [count]` | Issue spawner items |
| `/ahadmin`, `/orderadmin` | `remove <id>` | Remove a listing or order, with refund |
| `/bountyadmin` | `clear <player>` | Remove a bounty, with refund |
| `/combat` | `untag <player>` | Clear a combat tag |
| `/ledger` | `<player> [page]` | Audit trail |
| `/smp` | `reload` | Reload configuration |

The privileges `smp_admin` (all administration) and `smp_moderator` (read-only audit, mutes) are registered with `core.register_privilege`.

---

## 4. Economy

### 4.1 Currencies

| Property | Money | Shards |
|---|---|---|
| Role | Primary currency [S1] | Secondary currency for premium items [S8] |
| Earned through | `/sell`, auction sales, order deliveries, bounty claims, `/pay` | 1 shard per 10 minutes of playtime for every player [S8]; store purchases (out of scope; admin grant instead) |
| Spent on | Auction purchases, orders, Quick Buy, bounties, `/pay`, optional server shop | Shard shop [S8] |
| Transferable | Yes, with `/pay` | No (`PROPOSED`; one clone offers an optional `/shard pay` [C1]) |
| Leaderboards | `money`, `sell`, `shop` [S23] | `shards` [S23] |

### 4.2 Money: `/bal`, `/pay`, `/baltop` (`LIVE`)

`/bal` shows the caller's balance, `/pay <player> <amount>` transfers money and `/baltop` shows the richest players [S24].

1. `/pay` MUST reject self-payment, unknown recipients, recipients with payments disabled (`eco.pay_accept`, §11) and recipients who have blocked the payer. Amounts below `economy.min_pay` (`PROPOSED` $0.01) are rejected.
2. The transfer follows §2.4 and writes a debit and a credit ledger entry.
3. Both parties are notified; the recipient only if online with `eco.pay_alerts` on. Offline recipients see a summary when they next join (`PROPOSED`).
4. Donut SMP community documentation warns that sending money to low-playtime accounts can get both accounts wiped [S24]. Transfers above `economy.flag_threshold` (`PROPOSED` $1M) to accounts with less than `economy.flag_min_playtime` (`PROPOSED` 2 h) MUST be flagged for staff review; they are not blocked.
5. `/baltop` reads the leaderboard snapshot (§10.2).

### 4.3 Selling to the server: `/sell` (`LIVE`)

**Player view.** `/sell` opens a five-row container. Players drag items into it; eligible items are sold when the container closes (default) or when a Sell button is pressed (the clone "button mode" [C1]). Ineligible items are returned, and a receipt lists quantities, unit values, routing and the total. `/sellhistory` lists earlier sales [S3].

![SS-01: /sell container](screenshots/SS-01-sell-gui.png)

**Behaviour.**

1. *Eligibility.* An item is sellable if it has a base-price entry and matches it at level M0 (plain stacks only, `PROPOSED`); Donut SMP accepts only supported items [S3]. Amethyst items are sellable [S9]; their timer metadata is ignored through an explicit exemption list (`sell.meta_exempt`).
2. *Unit value* equals `base_price × sell.multiplier`. Donut SMP applied a temporary 3× multiplier to every `/sell` price until its planned border expansion [S2]; the multiplier is a live-tunable value with default 1.0.
3. *Routing.* For each item key, if the best compatible open order (M1) pays more per unit than the unit value, items go to orders in descending unit price while they have remaining quantity; the remainder is sold to the server [S4]. The seller receives the order price for routed units.
4. *Shulker boxes.* Eligible contents are sold and the shulker box is returned for reuse, still holding any ineligible items [S2]. Contents are decoded from item meta (`compressed` or the empty key, §2.2) and re-encoded in the same form.
5. *Combat.* `/sell` works while combat-tagged; Donut SMP enabled this in June 2026 [S3].
6. *History.* Each sale appends a record to the player's sell history; the last 100 are kept (`PROPOSED`).
7. *Statistics.* Server and order proceeds both count towards `money_made_from_sell` (`PROPOSED`).
8. *Tuning.* Donut SMP adjusts individual prices over time, for example setting cobblestone and cobblestone walls to 6 and 7 on 27 June 2026 [S2]. Base prices therefore live in a reloadable configuration file.

**Edge cases.** Items that cannot be returned because the inventory is full are dropped at the player's feet (`PROPOSED`). If the player disconnects with the container open, its contents are returned to the inventory before the player is saved (§14, R6).

### 4.4 Auction House: `/ah` (`LIVE`)

**Player view.** `/ah` opens a paginated grid of listings, `/ah <search>` filters by item name and `/ah sell <price>` lists the held stack for a total asking price [S5]. Sorting follows the official API: lowest price, highest price, recently listed and last listed [S23]. A "My listings" view lets sellers cancel active listings and reclaim cancelled or expired ones. Shulker listings show their contents, which the official API also exposes [S23].

![SS-02: Auction house main page](screenshots/SS-02-ah-main.png)
![SS-03: Auction purchase confirmation](screenshots/SS-03-ah-confirm.png)
![SS-04: /ah sell confirmation](screenshots/SS-04-ah-sell.png)

**Behaviour.**

1. *Listing record.* Mirrors the official API: item (id, count, display name, lore, enchantment levels, armour trim, container contents), price, seller and time left; sales are recorded with a millisecond timestamp [S23]. Schema in Appendix A.
2. *Capacity.* Active listings per player are limited by tier: tier1 45, tier2 90 [S17]. The default is `PROPOSED` 9, because Donut's allowance for non-members is not documented [S5].
3. *Duration.* `ah.listing_duration` is `PROPOSED` 48 h. Expired listings move to the seller's reclaim list and are kept for 30 days (`PROPOSED`).
4. *Fees.* `ah.listing_fee_pct` and `ah.sale_tax_pct` are `PROPOSED` 0; the wiki explicitly leaves fees, expiry times and default slots unspecified [S5].
5. *Purchase.* Clicking a listing opens a confirmation. On confirm the server re-validates that the listing is still active and unchanged (version counter) and that the buyer can pay and has inventory space; it then pays the seller immediately and gives the item to the buyer (§2.4). The seller is notified if online with `eco.ah_alerts` on.
6. *Listings sold into orders.* When a compatible (M1) open order would pay more than a listing's total asking price, the listing is sold into that order: the seller receives the order's payment and the order receives the items [S2][S6]. This is evaluated when a listing is created and when a new order is created (§4.5).
7. *Quick Auction Sell.* Announced on 16 June 2026 as an auction convenience feature [S2]; its mechanics are undocumented. `PROPOSED`: the `/ah sell` confirmation offers a "Match lowest" button that sets the price to the lowest active listing with the same M2 key, scaled to the held quantity. Confirmation is still required.
8. *History.* A global transaction log is paginated at 100 entries per page, up to 10 pages, newest first, as in the official API [S23].
9. *Price bounds.* `ah.min_price` is `PROPOSED` $1 and `ah.max_price` is `PROPOSED` $10^12.
10. *Indexes.* In-memory indexes from item key to listing ids sorted by unit price, and from search token to listing ids, let routing, Quick Buy and search avoid full scans.

### 4.5 Orders: `/orders` (`LIVE`)

**Player view.** `/orders` shows open buy orders and `/order <search>` filters them [S6]. A buyer creates an order for an item, a quantity and a unit price; suppliers open the order and deliver items for immediate payment [S6]. Buyers collect delivered items and may cancel the remaining quantity.

![SS-05: Orders board](screenshots/SS-05-orders-board.png)
![SS-06: Order creation](screenshots/SS-06-order-create.png)
![SS-07: Order delivery container](screenshots/SS-07-order-deliver.png)

**Behaviour.**

1. *Creation.* Item picker (search registered items, or "use held item" to copy its M1 key), then quantity, then unit price, then confirmation. The full amount, unit price × quantity, is escrowed at creation (`PROPOSED`; the wiki states only that buyers offer money for items [S6]).
2. *Automatic purchase from the auction house.* Immediately after creation the order buys matching listings priced at or below its unit price, cheapest first, until it is filled [S2][S6]. Each auction seller receives their own listing price; unused escrow stays with the order.
3. *Delivery.* The supplier opens a delivery container. On confirm, matching items (M1) are accepted up to the remaining quantity and paid at the unit price from escrow; everything else is returned. Partial fills are allowed. Players MUST NOT deliver to their own orders (`PROPOSED`).
4. *Routing in.* Orders also receive items routed from `/sell`, from spawner "Sell all", from the amethyst sell axe and from auction listings whenever the order pays more [S2][S4].
5. *Collection.* Delivered items are stored as virtual counts in the order record and converted into stacks when collected.
6. *Selling from one's own order.* The June 9 notes apply the routing logic to selling items from a player's own order [S2]. `PROPOSED` interpretation: "My orders" offers "Sell collected items", which sends delivered items through `/sell` routing.
7. *Cancellation and expiry.* Cancelling refunds unspent escrow; delivered items stay collectible. Orders expire after `orders.duration` (`PROPOSED` 7 days) with the same effect.
8. *Capacity.* Open orders per player: tier1 45, tier2 90 [S17]; default `PROPOSED` 9.
9. *Exclusions.* Amethyst items cannot be ordered [S9]; further exclusions go in `orders.blacklist`.
10. *Notifications.* Delivery notices respect `eco.order_alerts` (the clone `/order toggle` [C1]).

### 4.6 Quick Buy: `/shop` (`LIVE`)

Since 17 June 2026, `/shop` opens Quick Buy, a purchasing interface built on live auction listings [S7].

**Player view.** The player configures entries, each an exact item (including enchantments) and a quantity. Every entry shows the current lowest matching auction price and can be edited or removed on its own [S7].

![SS-08: Quick Buy panel](screenshots/SS-08-quickbuy.png)

**Behaviour.**

1. Matching is exact, including enchantments: M1 plus an enchantment specification [S2][S7].
2. A purchase may spend up to three times the displayed live price so that it still completes when the cheapest listing changes; beyond that threshold a warning screen requires re-confirmation [S7].
3. Quick Buy is unavailable while combat-tagged [S7].
4. Spending counts towards `money_spent_on_shop` [S23].
5. Entries per player: `PROPOSED` 45.

### 4.7 Fixed-price server shop (`LEGACY` and `CLONE`)

Before June 2026, `/shop` was a fixed-price server shop [S7]. Clone recreations use End, Nether, Gear and Food categories with a quantity selector [C5]. The optional `smp_servershop` module is buy-only, configured by category and price, and counts towards `money_spent_on_shop`. It is recommended as a money sink.

### 4.8 Shards (`LIVE`)

1. Every online player receives 1 shard per 600 s of playtime; no rank is required [S8]. `shards.require_activity` is `PROPOSED` false, since Donut pays for playtime.
2. A global step accumulates each player's online time. The award is `floor(playtime / 600)` minus the shards already awarded for playtime; both values are persisted.
3. `/shards` shows the balance, and a `shards` leaderboard exists [S23].
4. Legacy earning (the AFK zone at 1 shard per minute, 10 shards per player kill) is specified in §13 [S8].

### 4.9 Shard Shop (`LIVE`)

Catalogue as documented in September 2026 [S8], mapped to Mineclonia:

| Offer | Shards | Mineclonia item | Notes |
|---|---:|---|---|
| Shard Pickaxe | 3,000 | `smp_amethyst:pickaxe` | §4.10 |
| Shard Axe | 3,000 | `smp_amethyst:axe` | §4.10 |
| Shard Shovel | 3,000 | `smp_amethyst:shovel` | §4.10 |
| Shard Potion of Haste | 6,000 | `smp_amethyst:haste_potion` | Haste II for 24 h |
| Mace (Density, Wind Burst) | 2,000 | `mcl_tools:mace` | Both enchantments exist in Mineclonia [M1] |
| Netherite Spear | 1,500 | none | Mineclonia has no spear [M1]; omit or substitute |
| Netherite Sword | 1,500 | `mcl_tools:sword_netherite` | Maximum enchantments |
| Netherite Pickaxe | 1,000 | `mcl_tools:pick_netherite` | Silk Touch variant and Fortune variant |
| Netherite Shovel | 800 | `mcl_tools:shovel_netherite` | |
| Netherite Axe | 600 | `mcl_tools:axe_netherite` | |
| Netherite Hoe | 500 | `mcl_farming:hoe_netherite` | |
| Bow | 500 | `mcl_bows:bow` | |
| Crossbow | 500 | `mcl_bows:crossbow` | |
| Netherite armour, each piece | 1,500 | Netherite set generated by `mcl_armor.register_set` (set name `netherite`) | Leggings and boots lack Blast Protection [S8]; confirm the generated itemstrings at runtime |

Donut sources describe the gear only as maximally enchanted, so each offer's enchantment list MUST be explicit in configuration (`PROPOSED`). Historical offers from 26 February 2026: spawners at 1,500 shards, the Prime key at 2,000 and the Crimson key at 2,500; the Gold and Amethyst keys were removed [S8].

Flow: grid, offer, confirmation, shard debit, item delivery. The purchase is refused if the inventory has no room.

![SS-09: Shard shop](screenshots/SS-09-shard-shop.png)

### 4.10 Amethyst (Shard) Items (`LIVE`)

Shared properties: bought with shards; sellable and auctionable but not orderable; a self-destruct timer that starts at one day [S9].

Implementation: item meta `smp:expires_at` (Unix time) is set at purchase, and the description is refreshed with the remaining time on use and on join. Using an expired item removes it with a message. Online players' `main` and `offhand` lists are swept on join and every 300 s (`PROPOSED`); items in containers are removed lazily when next used or picked up.

| Item | Documented behaviour | Specification |
|---|---|---|
| Shard Pickaxe ("drill") | Mines nine blocks at once [S9]; deliberately unusable in combat [S19] | When a node is dug, also dig the 8 neighbours in the plane perpendicular to the dug face (`pointed_thing.under` minus `pointed_thing.above`). Each neighbour MUST be diggable by the tool (group `pickaxey`), unprotected (`core.is_protected`) and not blacklisted (bedrock, barriers, spawner nodes and containers, `PROPOSED`). Dig with `core.node_dig` under a per-player re-entrancy guard, applying wear once per use (`PROPOSED`). Refused while tagged. |
| Shard Axe | Fells a tree, taking connected logs and leaves [S9] | Breadth-first search from the dug log through groups `tree` and `leaves` (used by `mcl_trees` [M1]), limited to 512 nodes (`PROPOSED`) and protection-checked. |
| Shard Shovel | Pickaxe-style multi-block digging for dirt-type blocks [S9] | As the pickaxe, restricted to `amethyst.shovel_nodes` (default: dirt-family nodes in group `shovely`, `PROPOSED`). |
| Shard Potion of Haste | Haste II for 24 h [S9] | `mcl_potions.give_effect_by_level("haste", player, 2, 86400)` [M1]. Verify whether effects survive logout; if not, store the expiry in player meta and re-apply it on join. |
| Amethyst Bucket (`LEGACY`) | Drained 27 water blocks at once [S9] | Remove water in a 3×3×3 cube around the pointed position; protection-checked. |
| Amethyst Sell Axe (`LIVE`, behaviour undocumented) | Named in the June 9 routing rules [S2] | `PROPOSED`: punching a container sells its eligible contents through `/sell` routing; protection-checked; refused while tagged. |

![SS-10: Shard pickaxe tooltip and timer](screenshots/SS-10-shard-pickaxe.png)

---

## 5. Virtual Spawners

### 5.1 Overview (`LIVE`)

Donut SMP spawners never spawn entities. They produce the mob's drops, which players take by right-clicking the spawner as they would a chest [S10][S25]. Spawners of one type can be stacked into a single block [S24]. They are the server's main productive asset and a prime raiding target [S10]. As of September 2026 no new spawners enter the game; existing spawners change hands only through trading [S10].

**Player view.**

- Placing a spawner item creates a spawner block.
- Sneaking and right-clicking the block while holding spawners of the same type adds them to it [S24].
- Right-clicking opens the spawner menu: stored drops, stored XP, "Sell all" and "Collect XP".
- Mining with a Silk Touch pickaxe takes spawners back (clone behaviour [C3]).

![SS-11: Spawner menu](screenshots/SS-11-spawner-gui.png)
![SS-12: Spawner stacking feedback](screenshots/SS-12-spawner-stack.png)

### 5.2 Types and outputs

| Type | Mob (label and icon) | Documented output | Default loot per virtual kill (`PROPOSED`) | XP per kill (`PROPOSED`) |
|---|---|---|---|---|
| Skeleton | `mobs_mc:skeleton` | Bones [S10][S24] | `mcl_mobitems:bone` 1.0 | 5 |
| Iron Golem | `mobs_mc:iron_golem` | Iron ingots [S10][S24] | `mcl_core:iron_ingot` 4.0 | 0 |
| Spider | `mobs_mc:spider` | String and spider eyes [S10][S25][S24] | `mcl_mobitems:string` 1.0; `mcl_mobitems:spider_eye` 0.33 | 5 |
| Zombified Piglin | `mobs_mc:zombified_piglin` (`mobs_mc:pigman` is also registered [M1]) | Gold nuggets [S10][S24] | `mcl_core:gold_nugget` 0.5; `mcl_mobitems:rotten_flesh` 0.5 | 5 |
| Blaze | `mobs_mc:blaze` | Blaze rods [S10]. **Conflict:** another source says blaze powder, not rods [S24] | `mcl_mobitems:blaze_rod` 0.5 (verify) | 10 |
| Zombie | `mobs_mc:zombie` | Zombie drops such as rotten flesh [S10][S24] | `mcl_mobitems:rotten_flesh` 1.0 | 5 |
| Pig | `mobs_mc:pig` | Raw porkchop [S10][S25][S24] | `mcl_mobitems:porkchop` 2.0 | 2 |
| Cow | `mobs_mc:cow` | Raw beef, no leather [S10][S24] | `mcl_mobitems:beef` 2.0 | 2 |
| Creeper (conditional) | `mobs_mc:creeper` | Gunpowder; listed by one source only [S24] | `mcl_mobitems:gunpowder` 1.0 | 5 |

Output is deterministic: every item keeps a fractional accumulator, so expected values are produced without random rolls.

### 5.3 Production model (`PROPOSED`, to be calibrated)

Donut SMP documents diminishing returns: the more spawners in one stack, the less each additional spawner adds, and skeleton output levels off near 1,505.35 bones per minute however many are stacked [S24]. The exact curve is not published. This specification uses

`kills_per_min(n) = C × (1 − (1 − r / C)^n)`

where `n` is the stack size, `r` the rate of a single spawner and `C` the asymptotic cap. The function gives `f(1) = r`, rises strictly, has decreasing marginal output and tends towards `C`.

Defaults: `r = 6` virtual kills per minute (roughly a vanilla spawner, which spawns up to four mobs every 10 to 40 s) and `C = 1505.35` for skeletons. Items per minute equal `kills_per_min` multiplied by the expected count per kill. Illustrative skeleton output:

| Stack size n | 1 | 10 | 64 | 100 | 500 | 1,000 |
|---|---:|---:|---:|---:|---:|---:|
| Bones per minute | 6.0 | 58.9 | 339.5 | 495.7 | 1,301.0 | 1,477.6 |

`r` and `C` MUST be calibrated per type from screenshots or timed tests; for skeletons the independent DonutStats production calculator can be used [T1]. The Donut wiki itself advises measuring collected output over a known period instead of trusting estimates [S10].

### 5.4 Storage and XP

- Storage is virtual: an `item → count` table in node metadata, shown in the menu as 45-slot pages.
- Capacity is `min(spawners.storage.hard_cap, spawners.storage.per_spawner × n)` with `per_spawner` `PROPOSED` 2,880 (45 × 64). Production pauses while storage is full; Donut players are advised to watch capacity so that output is not lost [S10].
- XP accumulates up to `spawners.xp.per_spawner_cap × n` (`PROPOSED` 2,000 per spawner) and is granted with `mcl_experience.add_xp(player, xp)` [M1].
- The maximum stack size is the signed 32-bit limit, 2,147,483,647 [S24].

### 5.5 Accrual

State is updated lazily: every interaction converts the time elapsed since `last_update` into output and then sets `last_update` to now. A node timer (`PROPOSED` 60 s) keeps output flowing while the block is loaded. Whether Donut players must stay near their spawners is undocumented [S10], so the policy is configurable:

| `spawners.accrual_mode` | Behaviour |
|---|---|
| `active_only` (default, `PROPOSED`) | Accrue only while the map block is active. Node timers run only in active blocks; on reactivation the callback may receive an elapsed value covering the inactive period, so each tick is clamped to twice the timer interval. |
| `always` | Accrue wall-clock time, limited only by capacity. |
| `capped` | Accrue wall-clock time up to `spawners.offline_cap_hours`. |

### 5.6 Interaction specification

1. **Placement.** Placing `smp_spawners:spawner_item` (item meta `type`) creates `smp_spawners:spawner` with that type, a stack of 1, empty storage and `last_update` set to now. It is a separate node from Mineclonia's `mcl_mobspawners:spawner`, so no mob-spawning code runs.
2. **Stacking.** Sneak and right-click with a spawner item of the same type to add the whole held stack [S24] (`spawners.stack_mode = "all"`; one clone adds one per click and the whole stack only when sneaking [C3]). Other types are rejected. Stacking requires protection access.
3. **Menu.** A header `<Type> Spawner ×n`, a storage page, buttons for Sell all, Collect XP and paging, and lines for rate per minute, stored versus capacity, and stored XP. Clicking an item takes one stack; shift-clicking takes as much as fits.
4. **Sell all.** Sells stored output through `/sell` routing, so higher-paying orders are served first [S2].
5. **Breaking.** Requires Silk Touch (`mcl_enchanting.has_enchantment(tool, "silk_touch")`) [C3][M1]. A normal dig removes one spawner and a sneaking dig removes up to 64 [C3]. Spawner items go to the digger's inventory, with overflow dropped. When the stack reaches zero the node is removed and the remaining storage is lost, as in the clone [C3]; partial removals keep the storage. Digging without Silk Touch is refused (`PROPOSED`).
6. **Access.** Any player may open, take from and sell a spawner, in keeping with semi-anarchy (`PROPOSED`); digging and stacking honour `core.is_protected`. `spawners.open_requires_access` defaults to false.
7. **Explosions and pistons.** Spawners ignore blasts (`on_blast` does nothing) and cannot be pushed (`PROPOSED`, configurable).
8. **Hoppers.** Optional extraction, as in clones [C3]; off by default.
9. **Natural spawners.** One community guide describes obtaining spawners naturally in the world [S24], but current Donut supply is closed [S10]. Dungeon spawners (`mcl_mobspawners:spawner`) therefore stay vanilla by default; converting them into a virtual spawner item when dug with Silk Touch is an option (`spawners.convert_natural`, a clone option [C3]).
10. **Not adopted.** The clone "isolation bonus", which makes spawners that are not adjacent to others produce faster [C3].

### 5.7 Acquisition and supply

| Source | Status |
|---|---|
| No new supply; trading and raiding only | LIVE [S10] |
| Shard shop at 1,500 shards (26 February 2026 price) | LEGACY [S8] |
| Gold crate: any one spawner | LEGACY [S11] |
| Administrative issue (`/spawner give`) | PROPOSED |

Configuration: `spawners.acquisition = {shard_shop = false, crates = false, natural = false, admin = true}`.

### 5.8 Performance and security

No entities, at most one node timer per spawner, O(1) accrual and menus that render only the visible page. Every menu action MUST re-validate that the node still exists, has the same type and a positive stack, and that the player is within 8 nodes. A metadata version counter stops two viewers from collecting the same output twice.

---

## 6. Teleportation and Navigation

### 6.1 Common teleport framework

| Rule | Default | Status |
|---|---|---|
| Warm-up with action-bar countdown | 5 s | CLONE [C7]; PROPOSED outside RTP |
| Cancel the warm-up on movement | more than 1 node | LIVE for RTP [S27]; PROPOSED elsewhere |
| Cancel the warm-up on damage | yes | PROPOSED |
| Refuse while combat-tagged | yes | LIVE for RTP [S27]; PROPOSED elsewhere |
| Per-command cooldown with tier reductions | Appendix E | LIVE for RTP [S27] |
| Damage immunity after arrival | 0 s (optional) | PROPOSED |

The origin of every command-initiated teleport is recorded for `/world`.

### 6.2 Random teleport: `/rtp` (`LIVE`)

**Player view.** Donut SMP's `/rtp` originally opened a menu to choose the Overworld, the Nether or the End [S25][S27] and accepted a dimension argument such as `/rtp overworld` [S27]. A walk-in RTP zone exists at spawn [S27]. Current guides also document `/rtp <region>` and a region-selection menu [S26]. On 15 June 2026 the menu was removed to make random teleport more direct [S14][S2].

**Rules.** A cooldown applies, shorter for Donut+ players; `/rtp` is unavailable in combat and is cancelled by movement [S27].

![SS-13: RTP menu (historical)](screenshots/SS-13-rtp-menu.png)
![SS-14: RTP zone at spawn](screenshots/SS-14-rtp-zone.png)

**Specification.**

1. Arguments: none (the menu if `rtp.menu_enabled`, otherwise the default dimension), a dimension (`overworld`, `nether`, `end`) or a region name.
2. Regions: Donut's regions are regional proxy servers [S1]. On a single world they map to named rectangles such as quadrants, configured in `rtp.regions` (`PROPOSED`).
3. Candidate: a random (x, z) inside the ring from `rtp.min_radius` to `rtp.max_radius` around the region centre, clipped to the world border and outside the spawn radius.
4. Dimension bands come from `mcl_vars` [M1]: Overworld `mg_overworld_min` to `mg_overworld_max`, Nether `mg_nether_min` to `mg_nether_max`, End `mg_end_min` to `mg_end_max`. Only a configured sub-band of each is scanned (`rtp.scan.<dimension>`, Appendix E), because the full Overworld and End ranges are far taller than any surface.
5. Generation: `core.emerge_area(minp, maxp, callback)` for the scanned column. The search runs in the callback, never synchronously.
6. Safe position: a walkable, non-hazardous node with two free, non-liquid nodes above it. Reject water, lava, fire, cactus, magma, campfires, sweet berry bushes, powder snow and leaves (`PROPOSED`, following clone blacklists [C8]). In the Nether, search downward from below the bedrock ceiling (`mg_bedrock_nether_top_max`) and avoid lava; in the End, land only on end stone.
7. At most `rtp.max_attempts` (`PROPOSED` 10) candidates. After a failure the player is told and no cooldown starts.
8. An optional background cache of validated positions per dimension allows instant teleports (`PROPOSED`).
9. RTP zone: a configured box at spawn. A player who stays inside it for `rtp.zone_delay` (`PROPOSED` 3 s) is sent to the Overworld; presence is checked once per second.

### 6.3 RTP queue: `/rtpqueue` (`LIVE`, beta)

Launched in beta on 29 June 2026, the queue matches a player against another player, comparable to the former Duels [S15]. Donut-style clones pair two queued players and teleport both to the same random safe location [C4]. Specification (`PROPOSED` where not sourced):

1. `/rtpqueue` toggles queue membership; it is refused while tagged.
2. First-in, first-out pairing, optionally matched by kill/death ratio or gear score as Duels once were [S13].
3. When a match is found, both players get a 5 s countdown and are teleported to one safe location, `rtpqueue.separation` apart (default 16 to 32 nodes).
4. Queue membership times out after 300 s; disconnecting or teleporting elsewhere also leaves the queue.
5. After landing, normal survival rules apply: the first hit starts combat tags, and death drops items.

### 6.4 Teleport requests (`LIVE`)

Commands are listed in §3.2 [S26].

1. One pending request per sender, target and type. Requests expire after `tpa.expiry` (`PROPOSED` 60 s).
2. A target who has disabled the request type (`tp.tpa_enabled`, `tp.tpahere_enabled`), or who ignores or blocks the sender, produces a generic refusal.
3. `/tpauto` accepts requests automatically [S26]. With `tp.confirm_menu` on, the target sees an Accept/Deny dialog, since Luanti chat has no clickable text.
4. After acceptance, the moving party (the sender for `/tpa`, the target for `/tpahere`) goes through the warm-up.
5. A request is cancelled if either party is tagged, dies or disconnects.
6. `/tp <player>` is an alias of `/tpa`, as on Donut SMP [S26]. Luanti's built-in `/teleport` remains privileged for staff.

### 6.5 Homes (`LIVE`)

| Tier | Home slots | Source |
|---|---:|---|
| Default | 2, plus one team home (historical Donut default; the current default is undocumented) | [S25] |
| tier1 (Donut+) | 9 | [S17] |
| tier2 (Donut++) | 27 | [S17] |
| tier3 (Donut+++) and Media | 90 | [S17] |

1. `/home` opens a menu of named homes. Clicking a home teleports after the warm-up; sneak-clicking deletes it after confirmation (`PROPOSED`). `/home <id>` teleports directly [S26].
2. `/sethome` without a name uses the next free slot (`home1`, `home2` and so on).
3. Names may be up to 32 characters long (`PROPOSED`); Donut raised its limit on 18 June 2026 [S16].
4. When a tier expires, existing homes stay usable, but no new home may exceed the current limit [S17].
5. Home coordinates are never shown to other players, including through `/findplayer`.

![SS-15: Homes menu](screenshots/SS-15-homes.png)

### 6.6 Spawn, lobbies, warps, `/world` and `/back`

- `/spawn` opens a lobby menu, and `/spawn <lobby>` goes to a named lobby [S26]. On a single world, lobbies are named spawn points (`PROPOSED`).
- `/warp <location>` teleports to spawn utility locations [S26], such as the former crates area [S25].
- `/world` returns to the position recorded before the last command-initiated teleport [S26].
- `/back`, taken from a clone [C1], is disabled by default to preserve the stakes of death (`PROPOSED`).

### 6.7 Ender pearls and portals

Donut SMP restored a vanilla pearl behaviour, fixed cross-dimension pearls [S2] and added a setting that stops thrown pearls from disappearing when the thrower dies [S20]. Mineclonia's pearl entity is `mcl_throwing:ender_pearl_entity` [M1]. `PROPOSED`: track in-flight pearls per thrower and remove them on the thrower's death unless `combat.keep_pearls_on_death` is enabled for that player. Low priority.

---

## 7. Combat and PvP

### 7.1 PvP policy

PvP is enabled everywhere except the protected spawn area (`PROPOSED`), consistent with Donut SMP's semi-anarchy design [S1].

### 7.2 Combat tag and combat log (details `CLONE`)

Donut SMP documents restrictions that apply during combat [S7][S19], which implies a combat tag, but its duration and full rules are not published [S19]. Specification:

1. **Trigger.** Damage between two players tags both of them: melee through `core.register_on_punchplayer`; arrows through the arrow entity's `_shooter` field [M1]; explosions from end crystals, respawn anchors and TNT are attributed, on a best-effort basis, to the player who placed, ignited or struck the source within the previous 10 s (`PROPOSED`).
2. **Duration.** `combat.tag_seconds`, `PROPOSED` 20 s, refreshed by every hit.
3. **Display.** An action-bar countdown through `mcl_title.set(player, "actionbar", ...)` or a HUD text element, as in clones [C1].
4. **Restrictions** (configurable list): `/rtp`, `/rtpqueue`, `/tpa`, `/tpahere`, `/tpaccept`, `/home`, `/spawn`, `/warp`, `/world` and `/shop` [S7], and the Shard Pickaxe [S19]. Allowed: `/sell` [S3], `/msg` and browsing `/ah` (`PROPOSED`). Enforced with `core.register_on_chatcommand`, which returns true to cancel.
5. **Elytra.** `combat.disable_elytra` is `PROPOSED` false. Mineclonia implements gliding in `playerphysics/elytra.lua` without a public toggle [M1], so enabling this needs a hook into that module.
6. **Pearl distance cap** while tagged: optional and off by default, as in clones [C1].
7. **Untagging** on the death of the player or of the opponent, as in clones [C1].
8. **Combat log.** When a tagged player disconnects, every list registered with `mcl_death_drop` (`main`, `craft`, `armor`, `offhand` [M1]) is dropped at the logout position, the kill is credited to the last attacker for statistics and bounties, the event is broadcast, and player meta `smp:combat_logged = 1` makes the player respawn at spawn on the next join. This follows clone behaviour [C1].

![SS-16: Combat tag display](screenshots/SS-16-combat-tag.png)

### 7.3 Bounties (`LIVE`; mechanics `PROPOSED` or `CLONE`)

Donut SMP lists `/bounty` for viewing bounties and `/bounty add` for placing one [S24]. Donut-style plugins let anyone add money to a player's bounty and pay the total to whoever kills that player [C6].

1. `/bounty` lists bounties by total, largest first; `/bounty <player>` shows one.
2. `/bounty add <player> <amount>` escrows the amount. Contributions stack. The minimum is `bounty.min_amount` (`PROPOSED` $1,000), and bounties on oneself are refused.
3. **Claim.** When the target is killed by another player, including kills credited through combat logging, the killer receives the whole bounty and a broadcast announces it.
4. **Anti-abuse** (`PROPOSED`): no payout when killer and target share an IP address, a one-hour cooldown per killer and target pair, and no payout for kills inside the spawn safe zone.
5. No cancellation or refund (`PROPOSED`).

![SS-17: Bounty list](screenshots/SS-17-bounty.png)

### 7.4 Crystal PvP and respawn anchors

Crystal PvP is the dominant combat style on Donut SMP [S1]. Mineclonia includes end crystals and respawn anchors [M1], so the style is possible, although explosion timing and knockback differ from Java. Nothing beyond attribution (§7.2) needs to be built.

### 7.5 Kill rewards and duels

Legacy shard rewards for kills and the Duels mode are specified in §13.5 and §13.4. The current matchmaking mode is `/rtpqueue` (§6.3).

---

## 8. Social and Communication

### 8.1 Public chat

Lines are formatted `[Rank] Name: message`. The handler registered with `core.register_on_chat_message` returns true and delivers the formatted line to every recipient who has public chat on (`chat.public_visible`) and does not ignore the sender. Mutes are enforced here. Anti-spam: at most one message per second, plus a duplicate filter (`PROPOSED`).

### 8.2 Private messages

`/msg` and `/r` replace the built-in `/msg` through `core.override_chatcommand("msg", ...)`. Delivery respects `chat.pm_enabled` and the ignore and block lists.

### 8.3 Ignore and block

Donut SMP offers both `/ignore` and `/block` [S24] without documenting the difference. `PROPOSED`:

| Effect | `/ignore` | `/block` |
|---|:---:|:---:|
| Hide the player's public chat and private messages | yes | yes |
| Refuse their teleport requests | no | yes |
| Refuse their payments | no | yes |
| Refuse their follows | no | yes |
| Exclude them from RTP-queue pairing | no | yes |

### 8.4 Friends and follows (`LIVE`)

Donut SMP's friends system is built on follows: `/friend followers`, `/friend following`, `/friend addsearch` to find players to follow, `/friend search` and `/friend list` [S24]. `PROPOSED` semantics: following is one-way; mutual follows are friends; friends receive join and leave notices (`social.friend_notify`); a player can follow at most 200 others.

![SS-18: Friends menu](screenshots/SS-18-friends.png)

### 8.5 `/findplayer` (`LIVE`)

Donut's `/findplayer` returns a location, a rank and the username, the same fields its official lookup endpoint exposes [S23][S24]. On a raiding server exact coordinates would expose bases, so the location MUST be coarse (`PROPOSED`): `Offline`, `Spawn`, or `<Dimension> – <Region>`, with the dimension taken from `mcl_worlds.pos_to_dimension` [M1].

### 8.6 `/kill`

Drops the player's items and respawns them [S24] after a confirmation dialog, as in clones [C1]. If the player is tagged, the death is credited to the last attacker (`PROPOSED`), so `/kill` cannot be used to deny a kill or a bounty.

### 8.7 `/nightvision`

Toggles night vision with `mcl_potions.give_effect_by_level("night_vision", player, 1, duration)` and `mcl_potions.clear_effect` [M1]. The preference persists and is re-applied on join and respawn.

### 8.8 Informational commands

`/help`, `/rules`, `/discord`, `/media`, `/link`, `/buy`, `/website`, `/ranks` and `/medal` display configured text. Luanti cannot open URLs, so links appear in a read-only formspec field from which they can be copied.

### 8.9 Voice chat (`N/A`)

Donut SMP runs proximity voice chat through Simple Voice Chat [S21]; Luanti has no equivalent.

---

## 9. Ranks and Membership

| Tier (config) | Donut name | Homes | Auction slots | Order slots | Other perks |
|---|---|---:|---:|---:|---|
| `default` | none | 2 [S25] | 9 (`PROPOSED`) | 9 (`PROPOSED`) | none |
| `tier1` | Donut+ | 9 | 45 | 45 | Higher placement in the player list [S17] |
| `tier2` | Donut++ | 27 | 90 | 90 | none documented [S17] |
| `tier3` | Donut+++ | 90 | at least 90 (not stated) | at least 90 (not stated) | Priority chunk generation [S17] |
| `media` | Media | as tier3 | as tier3 | as tier3 | Equivalent to Donut+++ since 16 June 2026 [S17] |

1. A tier lasts 30 days per grant [S17]. The record is `{tier, expires_at}`; expiry is checked on join and hourly.
2. On expiry, existing homes, listings and orders remain, but nothing new may exceed the default limits [S17] (`PROPOSED` for listings and orders).
3. Historical perks: Donut+ and Media once gave 5 homes [S25] and let holders earn shards anywhere under the AFK system [S8][S17]; Donut+ also had a shorter RTP cooldown [S27].
4. `N/A`: Luanti has no server-controlled player list to reorder (tier-sorted `/list` output is the substitute) and no per-player priority for chunk generation.
5. `/ranks` shows the perk table and configured store text [S2]. Payment integration is out of scope; tiers are granted with `/rank set` (§3.5).

![SS-24: /ranks menu](screenshots/SS-24-ranks.png)

---

## 10. Statistics, Leaderboards and API

### 10.1 Statistics (`LIVE`)

Fields follow the official API [S23]:

| Field | Collected by |
|---|---|
| `broken_blocks` | `core.register_on_dignode` |
| `placed_blocks` | `core.register_on_placenode` |
| `kills`, `deaths` | `core.register_on_dieplayer(player, reason)`, taking the killer from `reason.object` or from the combat tag's last attacker |
| `mobs_killed` | Wrap `on_die` on every `mobs_mc:*` entity definition in `core.register_on_mods_loaded`; Mineclonia calls `self:on_die(pos, mcl_reason)` on death [M1] (verify which fields of `mcl_reason` identify the killer) |
| `money`, `shards` | Current balances |
| `money_made_from_sell` | `smp_sell` |
| `money_spent_on_shop` | `smp_quickbuy` and the legacy `smp_servershop` |
| `playtime` | Global-step accumulator, persisted every minute |

`/stats [player]` shows these fields in a menu.

![SS-19: /stats menu](screenshots/SS-19-stats.png)

### 10.2 Leaderboards

Categories match the official API: `brokenblocks`, `deaths`, `kills`, `mobskilled`, `money`, `placedblocks`, `playtime`, `sell`, `shards` and `shop` [S23]. `/leaderboard [category]` and `/baltop` read snapshots rebuilt every 300 s, each keeping the top 100 (`PROPOSED`).

![SS-20: Leaderboard menu](screenshots/SS-20-leaderboard.png)

### 10.3 Public API (optional)

Donut SMP issues personal API keys in game with `/api`. Clients send the key as a bearer token, are limited to 250 requests per minute, and can read auction listings (with search and sort), auction transactions, leaderboards, player lookups and statistics [S23].

Luanti mods cannot serve HTTP. Two options:

1. Write JSON snapshots into the world directory with `core.safe_file_write` for an external web server to publish.
2. Push snapshots through the HTTP API returned by `core.request_http_api()` (the mod must be listed in `secure.http_mods`) to an external service that manages keys and rate limits. `/api` then asks that service to issue or revoke a key and shows it to the player.

---

## 11. Player Settings (`/settings`)

Donut SMP documents a categorised settings menu that, since 22 June 2026, includes a General option stopping thrown pearls from disappearing on death [S20]. Clones list toggles such as public chat, private messages, payment alerts, auction alerts, teleport auto-accept and worth display [C1].

| Setting id | Category | Default | Effect | Status |
|---|---|---|---|---|
| `chat.public_visible` | Chat | on | Show public chat | CLONE [C1] |
| `chat.pm_enabled` | Chat | on | Accept private messages | CLONE [C1] |
| `chat.sounds` | Chat | on | Sounds for private messages and mentions | PROPOSED |
| `eco.pay_accept` | Economy | on | Accept `/pay` | CLONE [C1] |
| `eco.pay_alerts` | Economy | on | Payment notifications | CLONE [C1] |
| `eco.ah_alerts` | Economy | on | Auction sale notifications | CLONE [C1] |
| `eco.order_alerts` | Economy | on | Order delivery notifications | CLONE [C1] |
| `tp.tpa_enabled` | Teleport | on | Accept `/tpa` | CLONE [C1] |
| `tp.tpahere_enabled` | Teleport | on | Accept `/tpahere` | CLONE [C1] |
| `tp.auto_accept` | Teleport | off | Same as `/tpauto` | LIVE [S26] |
| `tp.confirm_menu` | Teleport | on | Accept/Deny dialog for requests | CLONE [C1] |
| `combat.keep_pearls_on_death` | General | off | Keep thrown pearls after death | LIVE [S20] |
| `general.nightvision` | General | off | Same as `/nv` | LIVE [S28] |
| `social.friend_notify` | Social | on | Friend join and leave notices | PROPOSED |
| `eco.worth_display` | Economy | not applicable | Base price shown in tooltips | CLONE [C1]; N/A, because tooltips belong to the item rather than the viewer |

Settings are stored as JSON in player meta `smp:settings`. The menu uses `tabheader[]` for categories.

![SS-21: Settings menu](screenshots/SS-21-settings.png)

---

## 12. World Rules and Server Configuration

### 12.1 Rules and enforcement

Donut SMP's rules [S18] and their Luanti enforcement:

| Donut rule | Luanti enforcement |
|---|---|
| No hacked clients or unfair modifications (movement, inventory, health indicators, radar, ESP, freecam, automatic placement, macros, auto-clickers) | Keep server-side anticheat enabled (`disable_anticheat = false`), restrict client-side mods with `csm_restriction_flags`, and provide staff tooling for the rest |
| No bug abuse or item duplication | §14 |
| No real-money trading, cross-server trading or external gambling | Policy and moderation only |
| At most five accounts per person | Count accounts per IP address with `core.get_player_ip` on join; flag rather than ban automatically (`PROPOSED`) |
| No attempts to discover the server seed | Never expose the seed through commands or the API |
| No staff impersonation | Name filters on join |
| No voice-chat spam | N/A |

Raiding and griefing are not prohibited; bases are expected to be found and raided [S1][S18].

### 12.2 World

1. No land claims (`PROPOSED` default) and a protected spawn area through `core.is_protected` (`PROPOSED` radius 128).
2. World border: Donut plans an expansion to 30,000,000 blocks in each direction [S1][S22]. Luanti's hard map limit is about 31,000 nodes from the origin (`mapgen_limit`), so the border is set with `mapgen_limit` plus a soft border that returns players inside it (`PROPOSED`).
3. Entity caps: Donut raised its creeper limit to 2,500 and its item-frame limit to 1,500 in June 2026 [S2]. In Luanti, use `max_objects_per_block` and per-type caps sized for Luanti (`PROPOSED`).

### 12.3 June 2026 mechanic changes

| Donut change [S2] | Luanti mapping |
|---|---|
| TNT duplication enabled | N/A (specific to Java) |
| Bedrock breaking and access below Overworld bedrock | Optional; Mineclonia bedrock (`mcl_core:bedrock`) is unbreakable by default. Off (`PROPOSED`) |
| Vanilla bed and respawn-position logic | Provided by Mineclonia (`mcl_spawn`) |
| Portal cooldown and axis fixes; map scaling | Mineclonia parity; nothing to build |
| Hopper speed kept non-vanilla | Optional tuning |
| Attribute swapping enabled | N/A (a Java 1.21 mechanic) |

### 12.4 Performance budget

No ABMs; global-step work at most O(online players) per second; storage flushes every 10 s; spawner timers every 60 s; leaderboard snapshots every 300 s.

---

## 13. Legacy Features (Removed from Donut SMP)

### 13.1 Crates and keys (`LEGACY`)

1. Five crates, each opened with a matching key [S11]:

| Crate | Rewards |
|---|---|
| Common | Diamond armour and tools |
| Prime | Netherite armour, mace, netherite sword or crossbow |
| Gold | Any one spawner |
| Amethyst | Amethyst items |
| Crimson | Netherite armour, sword, axe or pickaxe |

2. Keys were account balances rather than items, obtained from an hourly "keyall" and from the store [S11]. Shard shop prices on 26 February 2026 were 2,000 shards for a Prime key and 2,500 for a Crimson key; the Gold and Amethyst keys had been removed [S8].
3. Crates were opened at `/warp crates` [S11][S25]. Each opening presented seven rewards, from which the player chose one [S11].
4. Implementation: crate nodes at spawn whose right-click opens the choose-one-of-seven menu; key balances in the player record; keyall grants every online player the configured keys every 3,600 s (`PROPOSED` distribution). Because the player chooses, no randomness is needed.

![SS-22: Crate choice menu](screenshots/SS-22-crate-choice.png)

### 13.2 AFK zone (`LEGACY`)

`/afk` teleported players to an AFK area [S24] where they earned 1 shard per minute [S8]. Donut+ and Media players earned shards anywhere [S8][S17], and the Shard Potion of Haste multiplied AFK shard gain by four [S9]. Implementation: a box region checked every 5 s, awarding shards for each full minute spent inside.

### 13.3 Teams (`LEGACY`)

Removed on 2 June 2026 [S12].

1. `/team create <name>`, `/team disband`, `/team invite <player>` (requires the invite permission) and `/team join <inviter>`; at most 50 members [S12]. `/team leave` and `/team kick` come from clones [C1].
2. Team home: `/team sethome` and `/team home`; the team home also appeared as the leftmost `/home` slot [S12]. Solo players created one-person teams to gain an extra home [S12].
3. Team chat: `/team chat` toggles team-only chat and hides public chat, while `/team chat <message>` sends a single message [S12].
4. Permissions granted by the owner: invite and kick, teleport to the team home, set the team home, and team chat. Members have only team chat by default; the creator holds every permission [S12].
5. Friendly fire: a team PvP toggle, with no combat tags between teammates, as in clones [C1].

![SS-30: Team menu (historical)](screenshots/SS-30-team-menu.png)

### 13.4 Duels (`LEGACY`)

Removed on 2 June 2026 [S13]. `/duel <player>` issued a direct challenge; players could also queue at the duel building at spawn, where random matches showed the opponent's name and win percentile; draws were requested with `/duel draw <player>` [S13]. Matchmaking considered win rate and gear tier, so a diamond-equipped player was never randomly matched against netherite [S13]. Players fought with their own survival gear [S13].

Implementation: pre-built arenas far from the playable area, restored from a schematic after each match (`core.place_schematic`), with the gear tier derived from armour and weapon materials. Whether the loser's items passed to the winner is undocumented, so it is configurable (`PROPOSED`).

### 13.5 Kill shards (`LEGACY`)

10 shards were awarded for directly killing another player [S8], with anti-farming restrictions [S1]. `PROPOSED` restrictions: no reward for the same killer and victim within one hour, for victims with less than 30 minutes of playtime, or for players sharing an IP address.

### 13.6 Other legacy items

The fixed-price `/shop` (§4.7), the Amethyst Bucket (§4.10) and spawners sold in the shard shop (§5.7).

---

## 14. Economic Integrity and Anti-Abuse

| Id | Requirement |
|---|---|
| R1 | Every economic operation follows §2.4. |
| R2 | Orders and bounties hold escrow, and payouts come only from escrow. |
| R3 | Ledger reason codes: `sell`, `ah_list`, `ah_buy`, `ah_sale`, `order_escrow`, `order_payout`, `order_refund`, `pay`, `bounty_escrow`, `bounty_payout`, `shard_award`, `shard_spend`, `admin`. |
| R4 | Formspec handlers check the formname, use the server-side session and re-validate every action. |
| R5 | Detached inventories allow moves only by the owning player and only for eligible items. |
| R6 | When a player leaves, sessions are closed and items in temporary containers (sell container, order delivery) are returned to the inventory before the player is saved. |
| R7 | Node menus (spawners, crates) re-check the node and the player's distance on every action. |
| R8 | Shulker decoding is one level deep; Mineclonia does not allow shulkers inside shulkers [M1]. |
| R9 | Rate limits on `/pay`, `/ah sell` and order creation (`PROPOSED` one per second each). |
| R10 | Alternate-account and real-money-trading heuristics: flags on transfers to low-playtime accounts [S24] and on accounts per IP address [S18]. |
| R11 | Staff audit through `/ledger <player>`, with a manual reversal helper. |
| R12 | Crash safety: flush on shutdown and periodically; multi-record operations write a pending marker that is checked at start-up. |

---

## 15. Implementation Roadmap

| Phase | Deliverables | Acceptance criteria |
|---|---|---|
| P0 Foundation | `smp_core`, `smp_store`, `smp_items`, `smp_economy`, `smp_ranks`, ledger, `/eco` | Persistence survives restarts; unit tests for matching levels M0 to M2 |
| P1 Selling | `/sell` with shulkers and history, base prices, `/worth` | No item loss on close, disconnect or full inventory |
| P2 Spawners | Virtual spawners | Output within 1 % of §5.3; zero entities created |
| P3 Markets | Auction house, orders, routing, Quick Buy | Tests cover every routing path; the 3× price guard works |
| P4 Teleports | Framework, `/rtp` and RTP zone, requests, homes, spawn, warps, `/world` | No landing in liquid, fire or void across 1,000 trials |
| P5 Combat | Combat tag, combat log, bounties | Combat logging drops items and credits the kill |
| P6 Shards | Awards, shard shop, amethyst items | Expired items disappear; the drill respects protection |
| P7 Social and meta | Chat, private messages, ignore and block, friends, `/findplayer`, settings, statistics, leaderboards | Leaderboard rebuild under 50 ms with 10,000 players |
| P8 Optional | RTP queue, crates, teams, duels, AFK zone, API export, server shop | Tests per module |

---

## 16. Open Questions and Verification Checklist

Items to confirm with screenshots or live testing. Each answer replaces a `PROPOSED` value.

| Id | Question | Section |
|---|---|---|
| V-01 | Spawner menu layout, pages and buttons | §5.6 |
| V-02 | Production rate per type and stack size; whether owners must be nearby | §5.3, §5.5 |
| V-03 | Blaze spawner output: rods or powder | §5.2 |
| V-04 | Whether creeper spawners exist | §5.2 |
| V-05 | Spawner storage capacity and behaviour when full | §5.4 |
| V-06 | Auction listing duration, fees and default slots | §4.4 |
| V-07 | Auction menu layout, filters and category tabs | §4.4 |
| V-08 | Quick Auction Sell behaviour | §4.4 |
| V-09 | Order creation steps, escrow, cancellation, expiry and default slots | §4.5 |
| V-10 | Quick Buy panel layout | §4.6 |
| V-11 | Whether `/sell` sells on close or on a button | §4.3 |
| V-12 | Combat tag duration, blocked commands and elytra rule | §7.2 |
| V-13 | RTP cooldowns, ranges and region list | §6.2 |
| V-14 | Teleport request expiry and warm-up | §6.1, §6.4 |
| V-15 | Current default number of homes | §6.5 |
| V-16 | Complete `/settings` list and categories | §11 |
| V-17 | `/findplayer` output format | §8.5 |
| V-18 | Friends and follow semantics | §8.4 |
| V-19 | Bounty minimum, stacking, refunds and anti-abuse rules | §7.3 |
| V-20 | Exact enchantments on shard shop gear | §4.9 |
| V-21 | Amethyst tool details: 3×3 orientation, leaf handling, shovel block list, timer display | §4.10 |
| V-22 | Amethyst sell axe behaviour | §4.10 |
| V-23 | `/stats` and leaderboard layouts | §10 |
| V-24 | Chat format and rank prefixes | §8.1 |
| V-25 | Spawn layout: lobbies, RTP zone and warps | §6.2, §6.6 |
| V-26 | Whether Donut SMP has the rotating NPC trader (`/billford`) that one clone includes [C2] | not specified |
| V-27 | Exact name of the shard balance command | §3.1 |

---

## 17. Screenshot and Visual Reference Index

### 17.1 References located during research

The consulted wikis illustrate their articles with item icons rather than interface screenshots, and no interface screenshots were found. The official videos below show the interfaces in use.

| Id | Reference | Relevant to |
|---|---|---|
| V1 | Official Big June Update showcase video: https://www.youtube-nocookie.com/embed/UXSZmPyCw00 [S2] | Quick Buy, selling, RTP, general interface |
| V2 | Official demonstration of the `/sell` changes: https://www.youtube.com/watch?v=zVahADWQxI8 [S2] | `/sell` routing into orders |
| T1 | DonutStats spawner production calculator: https://www.donutstats.net/prices/calculator [S10] | Calibrating §5.3 (a tool, not a screenshot) |

### 17.2 Screenshot placeholders

| Id | What to capture | Section | File |
|---|---|---|---|
| SS-01 | `/sell` container before and after selling, including the receipt | §4.3 | `screenshots/SS-01-sell-gui.png` |
| SS-02 | Auction house main page with the sort control | §4.4 | `screenshots/SS-02-ah-main.png` |
| SS-03 | Auction purchase confirmation | §4.4 | `screenshots/SS-03-ah-confirm.png` |
| SS-04 | `/ah sell` listing confirmation | §4.4 | `screenshots/SS-04-ah-sell.png` |
| SS-05 | Orders board | §4.5 | `screenshots/SS-05-orders-board.png` |
| SS-06 | Every step of order creation | §4.5 | `screenshots/SS-06-order-create.png` |
| SS-07 | Order delivery container | §4.5 | `screenshots/SS-07-order-deliver.png` |
| SS-08 | Quick Buy panel, including the price warning | §4.6 | `screenshots/SS-08-quickbuy.png` |
| SS-09 | Shard shop | §4.9 | `screenshots/SS-09-shard-shop.png` |
| SS-10 | Shard Pickaxe tooltip and timer | §4.10 | `screenshots/SS-10-shard-pickaxe.png` |
| SS-11 | Spawner menu | §5.1 | `screenshots/SS-11-spawner-gui.png` |
| SS-12 | Spawner stacking feedback | §5.1 | `screenshots/SS-12-spawner-stack.png` |
| SS-13 | RTP menu (historical) | §6.2 | `screenshots/SS-13-rtp-menu.png` |
| SS-14 | RTP zone at spawn | §6.2 | `screenshots/SS-14-rtp-zone.png` |
| SS-15 | Homes menu | §6.5 | `screenshots/SS-15-homes.png` |
| SS-16 | Combat tag display | §7.2 | `screenshots/SS-16-combat-tag.png` |
| SS-17 | Bounty list | §7.3 | `screenshots/SS-17-bounty.png` |
| SS-18 | Friends menu | §8.4 | `screenshots/SS-18-friends.png` |
| SS-19 | `/stats` menu | §10.1 | `screenshots/SS-19-stats.png` |
| SS-20 | Leaderboard menu | §10.2 | `screenshots/SS-20-leaderboard.png` |
| SS-21 | Settings menu, every category | §11 | `screenshots/SS-21-settings.png` |
| SS-22 | Crate choice menu (historical) | §13.1 | `screenshots/SS-22-crate-choice.png` |
| SS-23 | `/sellhistory` output | §4.3 | `screenshots/SS-23-sellhistory.png` |
| SS-24 | `/ranks` menu | §9 | `screenshots/SS-24-ranks.png` |
| SS-25 | Spawn overview: lobbies, RTP zone, warps | §6.6 | `screenshots/SS-25-spawn.png` |
| SS-26 | Chat format and rank prefixes | §8.1 | `screenshots/SS-26-chat.png` |
| SS-27 | "My orders": collect and cancel | §4.5 | `screenshots/SS-27-my-orders.png` |
| SS-28 | "My listings": cancel and reclaim | §4.4 | `screenshots/SS-28-my-listings.png` |
| SS-29 | `/findplayer` output | §8.5 | `screenshots/SS-29-findplayer.png` |
| SS-30 | Team menu (historical) | §13.3 | `screenshots/SS-30-team-menu.png` |

---

## 18. Sources

Retrieved in September 2026. Donut SMP pages change often; each entry states what it supports.

**Donut SMP, official and community**

- [S1] DonutSMP Wiki, "About DonutSMP": server type, gameplay, regions, seasons, planned border. https://donutsmp.wiki/about-donutsmp
- [S2] DonutSMP Wiki, "Big June Update" (9 to 29 June 2026): economy integration, Quick Buy, shard rate, mechanic changes, official videos. https://donutsmp.wiki/big-june-update
- [S3] DonutSMP Wiki, "Selling". https://donutsmp.wiki/selling
- [S4] DonutSMP Wiki, "Sell Routing". https://donutsmp.wiki/sell-routing
- [S5] DonutSMP Wiki, "Auction House". https://donutsmp.wiki/auction-house
- [S6] DonutSMP Wiki, "Orders". https://donutsmp.wiki/orders
- [S7] DonutSMP Wiki, "Quick Buy" and "Shop Command". https://donutsmp.wiki/quick-buy and https://donutsmp.wiki/shop-command
- [S8] DonutSMP Wiki, "Shards": earning, shard shop, removed methods. https://donutsmp.wiki/shards
- [S9] DonutSMP Wiki, "Amethyst Items". https://donutsmp.wiki/amethyst-items
- [S10] DonutSMP Wiki, "Spawners". https://donutsmp.wiki/spawners
- [S11] DonutSMP Wiki, "Crates" (archived). https://donutsmp.wiki/crates
- [S12] DonutSMP Wiki, "Teams" (removed feature). https://donutsmp.wiki/teams
- [S13] DonutSMP Wiki, "Duels" (removed feature). https://donutsmp.wiki/duels
- [S14] DonutSMP Wiki, "Random Teleportation". https://donutsmp.wiki/random-teleportation
- [S15] DonutSMP Wiki, "RTP Queue". https://donutsmp.wiki/rtp-queue
- [S16] DonutSMP Wiki, "Home Commands". https://donutsmp.wiki/home-commands
- [S17] DonutSMP Wiki, "Donut+ Membership". https://donutsmp.wiki/donut-membership
- [S18] DonutSMP Wiki, "Server Rules". https://donutsmp.wiki/server-rules
- [S19] DonutSMP Wiki, "PvP". https://donutsmp.wiki/pvp
- [S20] DonutSMP Wiki, "Settings". https://donutsmp.wiki/settings
- [S21] DonutSMP Wiki, category "Mechanics": voice chat, attribute swapping, entity limits. https://donutsmp.wiki/category/mechanics
- [S22] DonutSMP Wiki, category "Events": language update, world border expansion. https://donutsmp.wiki/category/events
- [S23] DonutSMP Public API definition (Swagger 2.0): auction entries and transactions, leaderboards, lookup, statistics, authentication and rate limit. https://api.donutsmp.net/doc.json
- [S24] Donut Today wiki: command list, spawner guide, getting-started tips. Read through search-engine excerpts because the site blocks automated fetching. https://donut.today/wiki/commands, https://donut.today/wiki/spawners, https://donut.today/wiki/getting-started
- [S25] Earlier Fandom wikis: commands, default homes, RTP menu, crates warp, spawner types. https://donutsmpmc.fandom.com/wiki/Commands, https://donutsmpguide.fandom.com/wiki/Commands, https://dsmp.fandom.com/wiki/Spawners
- [S26] Third-party teleport guides citing the Donutpedia command reference. https://www.cloudspress.com/how-to-tp-in-donut-smp/, https://blog.rottenwifi.com/how-to-tp-in-donut-smp/, https://www.itechguides.com/how-to-tp-in-donut-smp/
- [S27] DonutSMP Wiki, former "Random Teleport (/rtp)" page. Read through a search-engine excerpt; the page now returns HTTP 404. https://donutsmp.wiki/rtp
- [S28] Community short videos demonstrating `/nightvision` and `/nv`. https://www.tiktok.com/discover/tutorial-on-how-to-use-the-command-on-donut-smp

**Clone plugins (not authoritative for Donut SMP)**

- [C1] DonutSMPCore documentation: player commands, economy configuration, combat module. https://opmasterleo.github.io/DonutSMPCore/
- [C2] UltimateDonutSMP wiki. https://github.com/BeestoXd/UltimateDonutSMP/wiki
- [C3] DonutSpawner (DonutSMP-Remake). https://github.com/DonutSMP-Remake/DonutSpawner and https://modrinth.com/plugin/donutsmp-spawner
- [C4] RTPQueuePro. https://modrinth.com/mod/rtpqueuepro
- [C5] DonutShop. https://modrinth.com/plugin/donutshop
- [C6] zBounty (DonutBounty). https://builtbybit.com/resources/zbounty.83070/
- [C7] DonutSMP-RTP. https://modrinth.com/mod/donutsmp-rtp
- [C8] PlainBase teleport module (RTP blacklist). https://github.com/j-gaertig/PlainBase/wiki/Module-Teleport

**Engine and game**

- [M1] Mineclonia source, GitHub mirror at commit `5bdce566` (21 September 2026). https://github.com/mineclonia-mirror/mineclonia

**Tools and videos**

- [T1] DonutStats (independent statistics and price tools). https://donutstats.net/ and https://www.donutstats.net/prices/calculator
- [V1] and [V2]: see §17.1.

---

## Appendix A. Data Schemas

Amounts of money are integer cents. Luanti account names are unique and permanent, so they replace the UUIDs used by the Donut API.

### A.1 Player record (`smp_store`, table `players`)

```lua
{
  name = "Alice",
  first_join = 1758500000,            -- Unix time
  money = 125000000,                  -- $1,250,000.00
  shards = 420,
  playtime = 86400,                   -- seconds online
  shards_for_playtime = 144,          -- shards already awarded for playtime
  rank = { tier = "tier1", expires_at = 1761100000 },
  homes = {
    { id = 1, name = "base", pos = { x = 1200, y = 64, z = -340 }, created = 1758500100 },
  },
  stats = { broken_blocks = 0, placed_blocks = 0, kills = 0, deaths = 0, mobs_killed = 0,
            money_made_from_sell = 0, money_spent_on_shop = 0 },
  social = { following = { "Bob" }, ignored = {}, blocked = {} },
  quickbuy = { { key = "mcl_tools:sword_netherite", ench = { sharpness = 5 }, qty = 1 } },
  keys = { common = 0, prime = 0, gold = 0, amethyst = 0, crimson = 0 },  -- legacy crates
}
```

### A.2 Ledger entry

```lua
{ id = 981234, time = 1758500200, type = "ah_sale", actor = "Bob", counterparty = "Alice",
  amount = 64000000, currency = "money", item_key = "mcl_core:diamond", qty = 64,
  ref = "ah:10452", flags = {} }
```

### A.3 Auction listing (mirrors `api.Ah` [S23])

```lua
{
  id = 10452, version = 1,
  state = "active",                   -- active, sold, cancelled, expired or routed
  seller = "Alice",
  stack = "mcl_core:diamond 64",      -- ItemStack:to_string()
  key = "<M2 key>",
  display = { name = "Diamond", lore = {}, ench = {}, trim = nil, contents = nil },
  price = 64000000,                   -- total asking price
  unit_price = 1000000,               -- derived
  created = 1758500000, expires = 1758672800,
}
```

### A.4 Auction transaction (mirrors `api.PurchaseItem` [S23])

```lua
{ id = 55120, listing = 10452, stack = "mcl_core:diamond 64", price = 64000000,
  seller = "Alice", buyer = "Bob", sold_at_ms = 1758500200123 }
```

### A.5 Order

```lua
{
  id = 3301, version = 4,
  state = "open",                     -- open, filled, cancelled or expired
  buyer = "Carol",
  key = "<M1 key>", template = "mcl_mobitems:bone", ench = {},
  qty = 6400, delivered = 1200, collected = 800,
  unit_price = 1500,                  -- $15.00 per item
  escrow = 7800000,                   -- unit_price * (qty - delivered)
  created = 1758500000, expires = 1759104800,
  suppliers = { Bob = 600, Alice = 600 },
}
```

### A.6 Bounty

```lua
{ target = "Dave", total = 500000000, contributors = { Alice = 300000000, Bob = 200000000 },
  created = 1758500000, updated = 1758503600 }
```

### A.7 Spawner node metadata

| Key | Type | Meaning |
|---|---|---|
| `smp:type` | string | Spawner type id, for example `skeleton` |
| `smp:stack` | integer | Spawners in the stack |
| `smp:last_update` | float | Unix time of the last accrual |
| `smp:store` | string | Serialized table of item name to fractional count |
| `smp:xp` | float | Stored XP |
| `smp:version` | integer | Incremented on every change |
| `infotext` | string | For example `Skeleton Spawner x128` |

### A.8 Sell-history entry

```lua
{ time = 1758500300,
  lines = { { item = "mcl_mobitems:bone", qty = 640, server = 400, order = 240, order_ids = { 3301 } } },
  server_total = 400000,              -- 400 bones at $10.00
  order_total = 360000 }              -- 240 bones at $15.00
```

### A.9 Settings (player meta `smp:settings`, JSON)

```json
{ "chat.public_visible": true, "chat.pm_enabled": true, "tp.auto_accept": false,
  "combat.keep_pearls_on_death": false }
```

### A.10 Team (legacy)

```lua
{ name = "Raiders", owner = "Alice", created = 1758500000,
  members = { Alice = { invite = true, kick = true, home = true, sethome = true, chat = true },
              Bob   = { chat = true } },
  home = { x = 100, y = 70, z = 200 }, pvp = false }
```

### A.11 Crate definition (legacy; example values)

```lua
{ id = "prime", title = "Prime",
  rewards = {                         -- exactly seven; the player chooses one
    { item = "mcl_tools:sword_netherite", ench = { sharpness = 5, unbreaking = 3, mending = 1 } },
    { item = "mcl_tools:mace", ench = { density = 5, wind_burst = 3 } },
    -- five more entries
  } }
```

---

## Appendix B. GUI Wireframes

Layouts are `PROPOSED` until replaced by the corresponding screenshots (§17.2). Figures use the default configuration and a base price of $10.00 per bone.

### B.1 Spawner menu (stack of 128)

```
+----------------------------------------------------------------------+
| Skeleton Spawner x128                          602.5 bones/min       |
| Stored 12,480 / 368,640 items                  XP 3,210 / 256,000    |
+----------------------------------------------------------------------+
| [bone 64][bone 64][bone 64][bone 64][bone 64][bone 64][bone 64] ...  |
|  5 rows x 9 columns of virtual slots (read-only; click to take)      |
+----------------------------------------------------------------------+
| [< Prev]  Page 1 / 5  [Next >]      [Sell all: $124.8K] [Collect XP] |
+----------------------------------------------------------------------+
| Player inventory (4 x 9)                                             |
+----------------------------------------------------------------------+
```

### B.2 Auction house

```
+----------------------------------------------------------------------+
| Auction House    Search [diamond________] [Go]   Sort [Lowest price] |
+----------------------------------------------------------------------+
| 45 listing icons (5 x 9). Tooltip: total price, unit price, seller,  |
| time left, enchantments, shulker contents                            |
+----------------------------------------------------------------------+
| [< Prev]  Page 2 / 17  [Next >]   [My listings]  [History]  [Close]  |
+----------------------------------------------------------------------+
```

### B.3 Sell container

```
+----------------------------------------------------------------------+
| Sell items                                          Total: $7.6K     |
+----------------------------------------------------------------------+
| 5 x 9 drop area (detached inventory, owner only)                     |
+----------------------------------------------------------------------+
| To orders: 240 bones at $15.00       To server: 400 bones at $10.00  |
| [Sell] in button mode; closing the menu sells in close mode          |
+----------------------------------------------------------------------+
| Player inventory (4 x 9)                                             |
+----------------------------------------------------------------------+
```

### B.4 Order creation

```
Step 1  Item       [search field]  or  [Use held item]   -> item grid
Step 2  Quantity   [ 6400 ]   (accepts 6.4k)
Step 3  Price      [ 15.00 ] per item          Escrow: $96K
Step 4  Confirm    "Buy 6,400 x Bone at $15.00 each ($96K)?"   [Confirm] [Back]
        After confirmation the order buys matching auction listings at or below $15.00
```

### B.5 Quick Buy

```
+----------------------------------------------------------------------+
| Quick Buy                                              [+ Add entry] |
+----------------------------------------------------------------------+
| Netherite Sword (Sharpness V, Unbreaking III)  x1   $2.1M  [Buy]     |
| Diamond                                       x64   $640K  [Buy]     |
| Every row: [Edit] [Remove]                                           |
+----------------------------------------------------------------------+
| If the cost exceeds 3 x the shown price: "Price rose to $X. Confirm?"|
+----------------------------------------------------------------------+
```

### B.6 Homes

```
+----------------------------------------------------------------------+
| Homes (3 / 9)                                                        |
| [bed: base] [bed: farm] [bed: nether] [empty] [empty] ... (9 slots)  |
| Click: teleport after a 5 s warm-up     Sneak-click: delete          |
+----------------------------------------------------------------------+
```

---

## Appendix C. Reference Algorithms

Pseudocode in Luanti Lua style; `cfg` is the loaded configuration and `S` the translator.

### C.1 Selling with routing

```lua
function smp_sell.sell(player, stacks)
  local receipt = smp_sell.new_receipt()
  for _, group in ipairs(smp_items.group_m0(stacks)) do         -- one group per item key
    local base = smp_sell.base_price(group.key)
    if not base or not group.plain then
      smp_sell.return_items(player, group.stacks)                -- ineligible
    else
      local unit = base * cfg.sell.multiplier
      local qty = group.count
      for _, order in ipairs(smp_orders.best_for(group.key)) do  -- unit price descending
        if qty == 0 or order.unit_price <= unit then break end
        local take = math.min(qty, order.qty - order.delivered)
        smp_orders.accept(order, player, take)                   -- paid from escrow
        receipt:add(group.key, take, order.unit_price, "order", order.id)
        qty = qty - take
      end
      if qty > 0 then
        smp_economy.credit(player, math.floor(unit * qty), "sell")
        receipt:add(group.key, qty, unit, "server")
      end
    end
  end
  smp_sell.history_append(player, receipt)
  return receipt
end
```

### C.2 Order creation with automatic auction purchase

```lua
function smp_orders.create(buyer, key, qty, unit_price)
  smp_ranks.check_limit(buyer, "orders")
  local escrow = qty * unit_price
  smp_economy.debit(buyer, escrow, "order_escrow")
  local order = smp_orders.insert{ buyer = buyer, key = key, qty = qty,
                                   unit_price = unit_price, escrow = escrow }
  for _, listing in ipairs(smp_ah.listings_for(key)) do           -- unit price ascending
    local remaining = order.qty - order.delivered
    if remaining == 0 or listing.unit_price > unit_price then break end
    if listing.count <= remaining then                             -- whole listings only (PROPOSED)
      smp_ah.sell_into_order(listing, order)                       -- seller receives listing.price
    end
  end
  return order
end
```

### C.3 Listing creation with order routing

```lua
function smp_ah.create_listing(seller, stack, price)
  smp_ranks.check_limit(seller, "ah")
  local key, count = smp_items.key(stack), stack:get_count()
  local best = smp_orders.best_for(key)[1]
  if best and smp_items.m1_eligible(stack)
     and best.unit_price * count > price
     and best.qty - best.delivered >= count then
    smp_orders.accept(best, seller, count)                         -- seller receives the order price
    return "routed", best.id
  end
  return "listed", smp_ah.insert(seller, stack, price)
end
```

### C.4 Quick Buy with price guard

```lua
function smp_quickbuy.buy(player, entry, shown_total)
  if smp_combat.is_tagged(player:get_player_name()) then
    return false, S("Not available during combat.")
  end
  local plan, cost = smp_ah.cheapest_plan(entry.key, entry.ench, entry.qty)
  if not plan then return false, S("Not enough matching listings.") end
  if cost > cfg.quickbuy.price_guard * shown_total then
    return smp_quickbuy.warn_and_reconfirm(player, entry, cost)
  end
  for _, listing in ipairs(plan) do smp_ah.buy(player, listing) end
  smp_stats.add(player, "money_spent_on_shop", cost)
  return true
end
```

### C.5 Spawner accrual

```lua
local function kills_per_min(def, n)
  return def.C * (1 - (1 - def.r / def.C) ^ n)
end

function smp_spawners.accrue(meta, now, max_dt)
  local def = smp_spawners.types[meta:get_string("smp:type")]
  local n = meta:get_int("smp:stack")
  local dt = math.max(0, now - meta:get_float("smp:last_update"))
  if max_dt then dt = math.min(dt, max_dt) end
  local kills = kills_per_min(def, n) * dt / 60
  local store = core.deserialize(meta:get_string("smp:store")) or {}
  local cap = math.min(cfg.spawners.storage.hard_cap, cfg.spawners.storage.per_spawner * n)
  local used = 0
  for _, count in pairs(store) do used = used + count end
  for item, per_kill in pairs(def.loot) do
    local add = math.min(kills * per_kill, math.max(0, cap - used))
    store[item] = (store[item] or 0) + add
    used = used + add
  end
  local xp_cap = cfg.spawners.xp.per_spawner_cap * n
  meta:set_float("smp:xp", math.min(xp_cap, meta:get_float("smp:xp") + kills * def.xp))
  meta:set_string("smp:store", core.serialize(store))
  meta:set_float("smp:last_update", now)
  meta:set_int("smp:version", meta:get_int("smp:version") + 1)
end
```

### C.6 Random-teleport search

```lua
function smp_tp.rtp(name, dim, region, attempt)
  attempt = attempt or 1
  if attempt > cfg.rtp.max_attempts then
    return core.chat_send_player(name, S("No safe location found. Try again."))
  end
  local band = cfg.rtp.scan[dim]                       -- sub-band of the mcl_vars range
  local x, z = smp_tp.random_in_ring(region, cfg.rtp.min_radius, cfg.rtp.max_radius)
  core.emerge_area(vector.new(x, band.min, z), vector.new(x, band.max, z),
    function(_, _, remaining)
      if remaining > 0 then return end
      local player = core.get_player_by_name(name)
      if not player then return end                    -- left while the area generated
      local pos = smp_tp.find_safe_y(x, z, band, dim)  -- top-down scan with the reject list
      if pos then
        smp_tp.teleport_with_warmup(player, pos, "rtp")
      else
        smp_tp.rtp(name, dim, region, attempt + 1)
      end
    end)
end
```

### C.7 Combat tag lifecycle

```lua
core.register_on_punchplayer(function(victim, hitter)
  local attacker = smp_combat.resolve_attacker(hitter)    -- a player, or an arrow's _shooter
  if attacker and attacker:is_player()
     and attacker:get_player_name() ~= victim:get_player_name()
     and smp_combat.pvp_allowed(victim, attacker) then
    smp_combat.tag(victim, attacker)
    smp_combat.tag(attacker, victim)
  end
end)

core.register_on_chatcommand(function(name, command)
  if smp_combat.is_tagged(name) and cfg.combat.blocked_commands[command] then
    core.chat_send_player(name, S("You cannot use /@1 during combat.", command))
    return true                                           -- cancels the command
  end
end)

core.register_on_leaveplayer(function(player)
  local name = player:get_player_name()
  if smp_combat.is_tagged(name) then
    smp_combat.drop_death_lists(player)                   -- same lists as mcl_death_drop
    smp_combat.credit_kill(smp_combat.last_attacker(name), name)
    player:get_meta():set_int("smp:combat_logged", 1)
  end
end)
```

### C.8 Bounty claim

```lua
core.register_on_dieplayer(function(victim, reason)
  local vname = victim:get_player_name()
  local killer = smp_combat.killer_from(reason) or smp_combat.last_attacker(vname)
  if not killer or killer == vname then return end
  local bounty = smp_bounty.get(vname)
  if bounty and bounty.total > 0 and not smp_bounty.is_abuse(killer, vname) then
    smp_economy.credit(killer, bounty.total, "bounty_payout", vname)
    smp_bounty.clear(vname)
    core.chat_send_all(S("@1 claimed the @2 bounty on @3.", killer,
      smp_core.format_money(bounty.total), vname))
  end
end)
```

---

## Appendix D. Luanti and Mineclonia API Mapping

| Need | Luanti engine API | Mineclonia API [M1] | Notes |
|---|---|---|---|
| Commands | `core.register_chatcommand`, `core.override_chatcommand`, `core.unregister_chatcommand`, `core.register_on_chatcommand` | none | The last one blocks commands during combat |
| Menus | `core.show_formspec`, `core.close_formspec`, `core.register_on_player_receive_fields` | `mcl_formspec.get_itemslot_bg_v4` | `formspec_version[6]` or later |
| Drag-and-drop | `core.create_detached_inventory(name, callbacks, player_name)` | none | Owner-only callbacks |
| Persistence | `core.get_mod_storage`, `player:get_meta()`, `core.get_meta(pos)`, `core.write_json`, `core.parse_json`, `core.serialize`, `core.deserialize`, `core.safe_file_write`, `core.register_on_shutdown` | none | |
| SQLite | `core.request_insecure_environment` (mod in `secure.trusted_mods`) | none | Requires `lsqlite3` on the host |
| HTTP export | `core.request_http_api` (mod in `secure.http_mods`) | none | Outbound requests only |
| Timers | `core.register_globalstep`, `core.after`, `core.get_node_timer(pos)` | none | |
| World access | `core.emerge_area`, `core.get_voxel_manip`, `core.get_node_or_nil`, `core.node_dig`, `core.is_protected` | `mcl_worlds.pos_to_dimension`, `mcl_vars.mg_*` bands | |
| Player events | `core.register_on_joinplayer`, `core.register_on_leaveplayer`, `core.register_on_dieplayer`, `core.register_on_respawnplayer`, `core.register_on_punchplayer`, `core.register_on_player_hpchange` | `mcl_spawn.get_player_spawn_pos`, `mcl_spawn.get_world_spawn_pos` | |
| Block statistics | `core.register_on_dignode`, `core.register_on_placenode` | none | |
| Mob kills | `core.register_on_mods_loaded`, `core.registered_entities` | Entity callback `on_die(self, pos, mcl_reason)` | Wrap every `mobs_mc:*` definition |
| Projectile attribution | none | Arrow entity field `_shooter` | |
| XP | none | `mcl_experience.add_xp`, `mcl_experience.throw_xp` | |
| Enchantments | none | `mcl_enchanting.get_enchantments`, `set_enchantments`, `has_enchantment`, `enchant` | Id `silk_touch` for spawner mining |
| Effects | none | `mcl_potions.give_effect_by_level`, `clear_effect`, `has_effect` | Ids `haste`, `night_vision` |
| Death drops | none | `mcl_death_drop.registered_dropped_lists`; setting `mcl_keepInventory` | |
| Titles and HUD | `player:hud_add`, `player:hud_change` | `mcl_title.set` | |
| Shulker contents | `ItemStack:get_meta()`, `core.compress`, `core.decompress`, `core.encode_base64`, `core.decode_base64` | Item meta `compressed` (zstd) or `""` | |
| Translation | `core.get_translator` | none | |
| Accounts and network | `core.get_player_ip`, `core.get_player_information(name)` (field `avg_rtt`) | none | `/ping`, accounts per IP |
| Privileges | `core.register_privilege`, `core.check_player_privs` | none | `smp_admin`, `smp_moderator` |

---

## Appendix E. Consolidated Configuration Reference

| Key | Default | Status | Section |
|---|---|---|---|
| `economy.min_pay` | $0.01 | PROPOSED | §4.2 |
| `economy.max_balance` | $10^13 | CLONE [C1] | §2.8 |
| `economy.flag_threshold` | $1,000,000 | PROPOSED | §4.2 |
| `economy.flag_min_playtime` | 7,200 s | PROPOSED | §4.2 |
| `sell.multiplier` | 1.0 (Donut used a temporary 3.0 [S2]) | PROPOSED | §4.3 |
| `sell.mode` | `close` | CLONE [C1] | §4.3 |
| `sell.history_size` | 100 | PROPOSED | §4.3 |
| `sell.meta_exempt` | amethyst items | PROPOSED | §4.3 |
| `ah.slots` | `{default = 9, tier1 = 45, tier2 = 90, tier3 = 90}` | LIVE [S17] except default and tier3 (PROPOSED) | §4.4 |
| `ah.listing_duration` | 172,800 s | PROPOSED | §4.4 |
| `ah.listing_fee_pct`, `ah.sale_tax_pct` | 0, 0 | PROPOSED | §4.4 |
| `ah.min_price`, `ah.max_price` | $1, $10^12 | PROPOSED | §4.4 |
| `ah.page_size` | 45 | PROPOSED | §4.4 |
| `ah.history` | 100 per page, 10 pages | LIVE [S23] | §4.4 |
| `orders.slots` | `{default = 9, tier1 = 45, tier2 = 90, tier3 = 90}` | LIVE [S17] except default and tier3 (PROPOSED) | §4.5 |
| `orders.duration` | 604,800 s | PROPOSED | §4.5 |
| `orders.blacklist` | amethyst items | LIVE [S9] | §4.5 |
| `quickbuy.price_guard` | 3.0 | LIVE [S7] | §4.6 |
| `quickbuy.max_entries` | 45 | PROPOSED | §4.6 |
| `shards.interval` | 600 s | LIVE [S8] | §4.8 |
| `shards.require_activity` | false | PROPOSED | §4.8 |
| `amethyst.lifetime` | 86,400 s | LIVE [S9] | §4.10 |
| `amethyst.felling_limit` | 512 | PROPOSED | §4.10 |
| `amethyst.sweep_interval` | 300 s | PROPOSED | §4.10 |
| `spawners.r` | 6 kills per minute | PROPOSED | §5.3 |
| `spawners.C.skeleton` | 1505.35 | LIVE [S24] (documented asymptote) | §5.3 |
| `spawners.timer_interval` | 60 s | PROPOSED | §5.5 |
| `spawners.accrual_mode` | `active_only` | PROPOSED | §5.5 |
| `spawners.stack_mode` | `all` | LIVE [S24] | §5.6 |
| `spawners.storage.per_spawner` | 2,880 | PROPOSED | §5.4 |
| `spawners.storage.hard_cap` | 2,147,483,647 | PROPOSED | §5.4 |
| `spawners.xp.per_spawner_cap` | 2,000 | PROPOSED | §5.4 |
| `spawners.require_silk_touch` | true | CLONE [C3] | §5.6 |
| `spawners.sneak_break_max` | 64 | CLONE [C3] | §5.6 |
| `spawners.open_requires_access` | false | PROPOSED | §5.6 |
| `spawners.blast_immune` | true | PROPOSED | §5.6 |
| `spawners.convert_natural` | false | PROPOSED | §5.6 |
| `spawners.acquisition` | `{shard_shop = false, crates = false, natural = false, admin = true}` | LIVE [S10] (closed supply) | §5.7 |
| `tp.warmup` | 5 s | CLONE [C7] | §6.1 |
| `tp.cancel_move_distance` | 1 node | PROPOSED | §6.1 |
| `rtp.cooldown` | `{default = 60, tier1 = 30}` s | PROPOSED (Donut: shorter for Donut+ [S27]) | §6.2 |
| `rtp.min_radius`, `rtp.max_radius` | 500; the border minus 500 | PROPOSED | §6.2 |
| `rtp.scan.overworld` | y from -32 to 256 (adjust to the world's terrain) | PROPOSED | §6.2 |
| `rtp.scan.nether` | `mg_nether_min` to a few nodes below `mg_bedrock_nether_top_max` | PROPOSED | §6.2 |
| `rtp.scan.end` | `mg_end_min` to `mg_end_min + 128` | PROPOSED | §6.2 |
| `rtp.max_attempts` | 10 | PROPOSED | §6.2 |
| `rtp.menu_enabled` | false (menu removed on Donut SMP, 15 June 2026) | LIVE [S14] | §6.2 |
| `rtp.zone_delay` | 3 s | PROPOSED | §6.2 |
| `rtpqueue.timeout` | 300 s | PROPOSED | §6.3 |
| `rtpqueue.separation` | 16 to 32 nodes | PROPOSED | §6.3 |
| `tpa.expiry` | 60 s | PROPOSED | §6.4 |
| `homes.slots` | `{default = 2, tier1 = 9, tier2 = 27, tier3 = 90}` | LIVE [S17]; default LEGACY [S25] | §6.5 |
| `homes.name_max` | 32 | PROPOSED | §6.5 |
| `combat.tag_seconds` | 20 | PROPOSED | §7.2 |
| `combat.blocked_commands` | list in §7.2 | LIVE [S7][S27] and PROPOSED | §7.2 |
| `combat.disable_elytra` | false | PROPOSED | §7.2 |
| `bounty.min_amount` | $1,000 | PROPOSED | §7.3 |
| `bounty.pair_cooldown` | 3,600 s | PROPOSED | §7.3 |
| `leaderboards.refresh`, `leaderboards.size` | 300 s, 100 | PROPOSED | §10.2 |
| `store.flush_interval` | 10 s | PROPOSED | §2.3 |
| `world.spawn_protect_radius` | 128 | PROPOSED | §12.2 |
| `legacy.keyall_interval` | 3,600 s | LEGACY [S11] | §13.1 |
| `legacy.afk_shards_per_min` | 1 | LEGACY [S8] | §13.2 |
| `legacy.team_max_members` | 50 | LEGACY [S12] | §13.3 |
| `legacy.kill_shards` | 10 | LEGACY [S8] | §13.5 |

---

## Document History

| Version | Date | Change |
|---|---|---|
| 0.1 | 2026-09-22 | Initial draft from wiki, API and clone-plugin research; Mineclonia interfaces verified against source. Screenshots pending (§17.2). |
