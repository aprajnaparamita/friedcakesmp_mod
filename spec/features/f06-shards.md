# f06 — Shards, Shard Shop and Amethyst Items

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_shards`, `smp_shardshop`, `smp_amethyst` |
| Phase | P6 |
| Depends on | `f01-economy-core` |
| Frame evidence | **0 dedicated frames.** Two indirect observations (below) |
| Confidence | **Research only** for the shop and the items; the award message and the entry point are observed |

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/shards` | `/shard` | — | Shard balance | CLONE [C1] |
| `/shardsadmin` | — | `give｜take｜set <player> <amount>` | Adjust shards (admin) | PROPOSED |

## 3. Observed UI

Two indirect observations, both worth acting on:

1. **The shard shop is reachable from the orders board.** An amethyst shard
   control there carries the tooltip `Shard Shop` / `Click to view`
   [F0179, F0182]. `smp_shardshop` MUST expose an entry point that `f04` can
   call. It is not a standalone command-only screen.
2. **The award message is observed verbatim**:
   `You earned 1 Shard for playing the server` [F0037, F0055, F0088–F0092].
   Note the capital `S` in `Shard` and the absence of a full stop.

The shop screen itself was never opened.

![SS-09: Shard shop](../../screenshots/SS-09-shard-shop.png)
![SS-10: Shard Pickaxe tooltip and timer](../../screenshots/SS-10-shard-pickaxe.png)

## 4. Behaviour

### 4.1 Earning

1. Every online player receives 1 shard per 600 s of playtime; no rank required
   [S8]. `shards.require_activity` is `PROPOSED` false, since Donut pays for
   presence.
2. A global step accumulates online time. The award is
   `floor(playtime / 600)` minus shards already awarded for playtime; both
   values persist.
3. Each award emits exactly `You earned 1 Shard for playing the server`
   (`OBSERVED`).
4. A `shards` leaderboard exists [S23].
5. Legacy earning (AFK zone at 1 per minute, 10 per player kill) is in `f16` (f16 descoped permanently — D8, 2026-09-24; never ships).

### 4.2 Shard Shop

Catalogue as documented in September 2026 [S8], mapped to Mineclonia:

| Offer | Shards | Mineclonia item | Notes |
|---|---:|---|---|
| Shard Pickaxe | 3,000 | `smp_amethyst:pickaxe` | §4.3 |
| Shard Axe | 3,000 | `smp_amethyst:axe` | §4.3 |
| Shard Shovel | 3,000 | `smp_amethyst:shovel` | §4.3 |
| Shard Potion of Haste | 6,000 | `smp_amethyst:haste_potion` | Haste II, 24 h |
| Mace (Density, Wind Burst) | 2,000 | `mcl_tools:mace` | Both enchantments exist [M1] |
| Netherite Spear | 1,500 | **none** | Mineclonia has no spear [M1]; omit or substitute |
| Netherite Sword | 1,500 | `mcl_tools:sword_netherite` | Maximum enchantments |
| Netherite Pickaxe | 1,000 | `mcl_tools:pick_netherite` | Silk Touch and Fortune variants |
| Netherite Shovel | 800 | `mcl_tools:shovel_netherite` | |
| Netherite Axe | 600 | `mcl_tools:axe_netherite` | |
| Netherite Hoe | 500 | `mcl_farming:hoe_netherite` | |
| Bow | 500 | `mcl_bows:bow` | |
| Crossbow | 500 | `mcl_bows:crossbow` | |
| Netherite armour, per piece | 1,500 | `mcl_armor.register_set` netherite set | Leggings and boots lack Blast Protection [S8]; confirm itemstrings at runtime |

Donut sources describe the gear only as "maximally enchanted", so each offer's
enchantment list MUST be explicit in configuration (`PROPOSED`).

Historical offers from 26 February 2026: spawners 1,500 shards, Prime key
2,000, Crimson key 2,500; Gold and Amethyst keys removed [S8].

Flow: grid → offer → confirmation → shard debit → item delivery. Refused if the
inventory has no room.

### 4.3 Amethyst (shard) items

Shared properties: bought with shards; sellable and auctionable but **not
orderable** [S9] (enforced by `orders.blacklist`, `f04`); a self-destruct timer
starting at one day.

Implementation: item meta `smp:expires_at` (Unix time) set at purchase; the
description refreshes with remaining time on use and on join. Using an expired
item removes it with a message. Online players' `main` and `offhand` lists are
swept on join and every 300 s (`PROPOSED`); items in containers are removed
lazily when next used or picked up.

| Item | Documented behaviour | Specification |
|---|---|---|
| Shard Pickaxe ("drill") | Mines nine blocks at once [S9]; deliberately unusable in combat [S19] | On dig, also dig the 8 neighbours in the plane perpendicular to the dug face (`pointed_thing.under` minus `above`). Each neighbour must be diggable by the tool (group `pickaxey`), unprotected (`core.is_protected`) and not blacklisted (bedrock, barriers, spawner nodes, containers — `PROPOSED`). Dig with `core.node_dig` under a per-player re-entrancy guard, applying wear once per use. Refused while tagged |
| Shard Axe | Fells a tree with connected logs and leaves [S9] | Breadth-first search from the dug log through groups `tree` and `leaves` (used by `mcl_trees` [M1]), limited to `amethyst.felling_limit` nodes, protection-checked |
| Shard Shovel | Pickaxe-style multi-block digging for dirt types [S9] | As the pickaxe, restricted to `amethyst.shovel_nodes` (dirt-family nodes in group `shovely`, `PROPOSED`) |
| Shard Potion of Haste | Haste II for 24 h [S9] | `mcl_potions.give_effect_by_level("haste", player, 2, 86400)` [M1]. Verify whether effects survive logout; if not, store expiry in player meta and re-apply on join |
| Amethyst Bucket (`LEGACY`) | Drained 27 water blocks at once [S9] | Remove water in a 3×3×3 cube around the pointed position; protection-checked |
| Amethyst Sell Axe (`LIVE`, undocumented) | Named in the June 9 routing rules [S2] | `PROPOSED`: punching a container sells its eligible contents through `f02` routing; protection-checked; refused while tagged |

## 5. Data schema

Shard balance and `shards_for_playtime` live in the player record
(`f01 §5.1`). Amethyst expiry lives in item meta `smp:expires_at`.

## 6. Algorithms

```lua
function smp_shards.on_step(dtime)
  for _, player in ipairs(core.get_connected_players()) do
    local rec = smp_store.player(player:get_player_name())
    rec.playtime = rec.playtime + dtime
    local earned = math.floor(rec.playtime / cfg.shards.interval)
    local owed   = earned - rec.shards_for_playtime
    if owed > 0 then
      rec.shards = rec.shards + owed
      rec.shards_for_playtime = earned
      smp_store.ledger("shard_award", player, nil, owed, { currency = "shards" })
      for _ = 1, owed do
        chat(player, S("You earned 1 Shard for playing the server"))  -- exact [F0037]
      end
    end
  end
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `shards.interval` | 600 s | LIVE [S8] |
| `shards.require_activity` | false — inert (V-61 closed, D8 2026-09-24); still read, never enabled; emits warning when true | PROPOSED |
| `shards.transferable` | false | PROPOSED |
| `shards.flush_interval` | 30 s | PROPOSED |
| `amethyst.lifetime` | 86,400 s | LIVE [S9] |
| `amethyst.felling_limit` | 512 | PROPOSED |
| `amethyst.sweep_interval` | 300 s | PROPOSED |
| `amethyst.haste_level` | 2 | PROPOSED |
| `amethyst.haste_duration` | 86,400 s | PROPOSED |
| `amethyst.shovel_nodes` | "" (empty; group `shovely` is the default/fallback) | PROPOSED |
| `shardshop.offers` | table above (18 offers) | LIVE [S8] |

## 8. Mineclonia implementation

- The shop is a container menu following the shared UI kit, opened both by
  command and from the orders board control (§3).
- Multi-block digging must use `core.node_dig` with a re-entrancy guard, or the
  tool will recurse into itself.
- Verify the netherite armour itemstrings generated by
  `mcl_armor.register_set` at runtime rather than hard-coding them.
- The expiry sweep is a global step over online players only. Never scan
  containers.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | A player online for 10 minutes receives exactly 1 shard and exactly one award message with the observed wording |
| T2 | Shards awarded across a restart do not double-count |
| T3 | An expired amethyst item is removed on use and on join |
| T4 | The Shard Pickaxe digs 9 blocks, skips protected and blacklisted nodes, and applies wear once |
| T5 | The Shard Pickaxe is refused while combat-tagged |
| T6 | The Shard Axe stops at `amethyst.felling_limit` |
| T7 | Amethyst items cannot be ordered but can be sold and auctioned |
| T8 | A shop purchase with a full inventory is refused and debits nothing |
| T9 | The shard shop opens from the orders board control as well as by command |

## 10. Open questions

| Id | Question |
|---|---|
| V-20 | Exact enchantments on shard shop gear |
| V-21 | Amethyst tool details: 3×3 orientation, leaf handling, shovel block list, timer display |
| V-22 | Amethyst sell axe behaviour |
| V-27 | Exact name of the shard balance command |
| V-60 | Shard shop layout — never opened |
| V-61 | Are shards awarded while AFK, given the AFK zone was removed? **Closed (D8, 2026-09-24): f16 descoped permanently; no AFK zone will ever exist. `shards.require_activity` stays read, default false, documented inert.** |

### Fix-wave record (fix brief, 2026-09-25)

| Row | Outcome | Evidence |
|-----|---------|----------|
| F06-1 | VERIFIED | `smp_amethyst/init.lua:179` already iterates names; join test added to `test_amethyst.lua` |
| F06-2 | CLOSED (code) / ESCALATED (mirror) | `smp_shardshop/catalogue.lua:49-180` reads `shardshop.offers` from settings; mirror row proposed to D7 via this file |
| F06-3 | ESCALATED → D8 | V-61 closed by D8 (2026-09-24); f16 descoped permanently; recorded in §10 V-61 |
| F06-4 | CLOSED | `smp_shards/init.lua:43,57` emits warning at load and reload when `require_activity=true` |
| F06-5 | CLOSED (code + §7) / ESCALATED (mirror) | `smp_amethyst/init.lua:43` reads `shovel_nodes`; `shovel.lua:15-18` uses it as additional restriction; key added to §7; mirror proposed to D7 |
| F06-6 | CLOSED | Dev-tests updated: T2 reloads module; T4 places blacklisted node + wear-once stub; T7 adds sell/auction acceptance |
| F06-7 | VERIFIED | `smp_shardshop/formspec.lua:92` already uses `S("Shards: @1", …)` |
| F06-8 | CLOSED (`mcl_armor`) / ESCALATED (`mcl_potions`) | `smp_shardshop/mod.conf:4` adds `mcl_armor`; `mcl_potions` spec-vs-code divergence escalated to integrator (`shared/02` is read-only) |
| F06-9 | CLOSED (§7) / ESCALATED (mirror) | Three keys (`shards.flush_interval`, `amethyst.haste_level`, `amethyst.haste_duration`) already in §7 with defaults; mirror proposed to D7 |
| F06-10 | DEPENDS-BLOCKER | Awaits `fixes/00-P0-blockers.md` B1-4/B1-5/B4-1 |
| F06-11 | CLOSED | `smp_shards/init.lua:229` stripped terminal full stop from refusal string |

## Proposed shared changes

Cross-mod contracts this feature relies on, for the integrator to merge
into the owning feature files / shared docs. None of these are hard
dependencies at load time (all are `optional_depends` and guarded), so
f06 ships and degrades safely if a peer is absent.

1. **f02 (`smp_sell`) — a single sell entry point.** The Amethyst Sell
   Axe (§4.3, V-22) routes each container stack to the best open order
   first, then falls back to base-price sell routing. It needs a single
   `smp_sell.sell(player, stack) -> boolean` (true when the stack was
   paid for). `smp_sell` currently exposes the three-step
   `plan`/`validate`/`pay` (`sell.lua`); please add the thin one-call
   wrapper the sell axe calls. Until then the sell axe leaves the stack
   in the container (no route = no loss).

2. **f04 (`smp_orders`) — order routing for the sell axe.** The sell axe
   calls `smp_orders.best_open_order(m1_key)` (returns the best-paying
   open order for the key, or nil) and, on a hit,
   `smp_orders.fill_from_stack(order, player, stack)` (pays the seller
   from escrow, returns true when the whole stack was accepted). These
   are already sketched in f03 §6.1; f06's sell axe depends on both. The
   orders **blacklist** is the inverse contract: `smp_amethyst/blacklist.lua`
   is a flat list of the six amethyst itemstrings that f04 imports and
   refuses (f04 §4.12 `orders.blacklist`, LIVE [S9]).

3. **f10 (`smp_combat`) — tag query.** Every amethyst tool is "refused
   while tagged" (§4.3, [S19] for the pickaxe). f06 calls
   `smp_combat.is_tagged(player_name) -> boolean`. It is an
   `optional_depends`; when f10 is absent the tools are simply usable.

4. **f01 (`smp_economy`) — `/smp test` dispatch.** `/smp test` currently
   dispatches only `smp_core`. f06 ships `test.lua` for `smp_shards`,
   `smp_amethyst` and `smp_shardshop`; please generalise the dispatcher
   to load `friedcake/mods/smp_<feature>/test.lua` for any feature name.

### PROPOSED behaviours this implementation introduces

The spec is silent on the following; each is marked PROPOSED here and
in the code, and surfaced above in §10 where an existing V-id applies.

- **V-22 sell axe behaviour.** Punching a container with the Amethyst
  Sell Axe routes each stack's M1 key to `smp_orders.best_open_order`,
  else `smp_sell`; a stack is removed from the container only once a
  route accepted it. Protection-checked; refused while tagged.
- **V-60 shop layout.** The shop was never opened, so the whole layout
  is PROPOSED: a container menu titled `Shard Shop`, a 2×9 offer grid
  over the player inventory, offer tooltips in the listing shape
  (name / `<qty> Shards` / `Click to buy` / itemstring), and a light
  confirm prompt before the shard debit. Only the entry point (the
  orders-board amethyst shard control) is observed [F0179, F0182].
- **V-20 enchantments.** Each offer's enchantment list is explicit in
  `smp_shardshop/catalogue.lua` (PROPOSED "maximally enchanted" sets);
  leggings and boots lack Blast Protection [S8].
- **V-21 shovel node list.** The Shard Shovel's multi-block dig is
  restricted to group `shovely` (dirt family), PROPOSED.
- **Haste persistence.** Mineclonia effects do not survive logout, so the
  24 h window is mirrored in player meta `smp:haste_until` and re-applied
  on join (PROPOSED mechanism; the 24 h Haste II itself is LIVE [S9]).
- **Dig blacklist.** Multi-block digs skip bedrock, `not_diggable`
  nodes, `mcl_core:barrier`, `mcl_core:realm_barrier`,
  `mcl_mobspawners:spawner`, and any node carrying an inventory
  (containers) — PROPOSED.
- **Refusal/result wording.** All amethyst and shop messages
  ("You cannot use this while in combat", "Nothing to mine here",
  "Felled @1 blocks.", "You bought 1 @2 for @3 Shards", "Your inventory
  is full", …) are PROPOSED house-style strings; only the award line and
  the `You bought …` shape are grounded in observation.
