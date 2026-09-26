# S02 — `/sell`: money printers from V-98/V-99, combat-log escape, lag

**Target mod:** `friedcake/mods/smp_sell/` · **Branch:** `agent/sec-s02-sell`
**Audited at:** `85e4a5d`. The latest commit (V-98/V-99) introduced SE-1 and
SE-2.

## Mission

The server is the **only buyer that never runs out of money**, so every
mispriced item is an unlimited faucet. Close the faucets that the
default-price and enchant-bonus features opened. Close the combat-log escape
through the sell container.

## Constraints (AGENTS.md)

- Edit only `smp_sell`. Default values of `sell.*` keys are mirrored in
  `spec/shared/06-config-reference.md`, so changing a default is
  **ESCALATE**: record it in `spec/features/f02-sell.md §10` / §11.
- Money is integer cents.
- Tests: `dev-tests/test_sell.lua` + `smp_sell/test.lua`.

## Findings

| ID | Sev | Status | Where | One line |
|---|---|---|---|---|
| SE-1 | High | CONFIRMED | `prices.lua:189`, `init.lua:97` | `sell.default_price` = $1 for **every** registered item makes zero-cost items a money faucet |
| SE-2 | High | CONFIRMED | `prices.lua:199-221`, `init.lua:98` | $500 per enchantment level turns XP and lapis into money, and shard-shop gear into about $100K |
| SE-3 | Low | CONFIRMED (corrected 2026-09-27) | `prices_default.lua:35`, `:48` | Wall ($7) is priced above cobble ($6), so the stonecutter's 1 cobble → 1 wall pays +$1 (about 17%) per block |
| SE-4 | High | CONFIRMED | `mod.conf` (optional_depends `smp_combat`), `init.lua:604` | The sell container is returned **after** the combat-log drop: valuables escape a combat log |
| SE-5 | Medium | CONFIRMED | `history.lua` → `smp_store` `append_history` (`mod_storage.lua:182`) | Every sale scans **all** keys of `smp_store`'s storage, so the cost grows with the ledger |

---

### SE-1 — Default price for every registered item (V-98)

`P.base_price` (`prices.lua:177-194`) returns `fallback` (100 cents by
default, `init.lua:97`) for **any** `core.registered_items` entry missing
from the table. The table lists about 110 items. Mineclonia registers
thousands. Examples verified against `~/dev/mineclonia-git`:

- *(Correction: `mcl_core:cobble`, stone and dirt **are** listed, at
  `prices_default.lua:34-39`. An earlier draft said cobble was unlisted.)*
- Moss: bone meal on a moss block spreads moss
  (`mcl_lush_caves/nodes.lua:86` `_on_bone_meal = bone_meal_moss`). One
  bone ($10) makes 3 bone meal, which grows many moss blocks, carpets and
  azaleas at $1 each. Grass and flowers from bone meal behave the same.
- Craft multipliers among **unlisted** items: 6 glass ($6) → 16 panes
  ($16). Every recipe whose inputs are unlisted and whose output count
  exceeds its input count is profitable at a flat price. (Slabs from
  listed cobble or stone lose money, so they are not a faucet.)

**Fix (pick one and record it in f02 §10 V-98):**
1. Default `sell.default_price = 0`, which is off, until an operator
   opts in. *(Recommended; mirror change → ESCALATE.)*
2. Apply the fallback only to an **allow-list group** (for example items
   with a `smp_sellable=1` group set by a curated list), never to
   everything registered.

**Regression guard (do this whatever the choice):** add an in-engine test
(`/smp test smp_sell`, which needs the real registry) that walks
`core.registered_items`, calls `core.get_all_craft_recipes(name)` for
each, and asserts:

```
sell_value(output) * output_count  <=  sum(sell_value(input_i))  (+ tolerance)
```

Include Mineclonia's stonecutter recipes (`_mcl_stonecutter_recipes` on
node definitions, as in `mcl_walls/init.lua:278`). The test must print
every violating recipe. It catches SE-1, SE-3 and every future pricing
edit.

---

### SE-2 — Enchant bonus is uncapped value from XP (V-99)

`unit = (base + levels × sell.enchant_bonus) × multiplier`, with
`enchant_bonus` defaulting to 50000 cents ($500/level, `init.lua:98`).

- **Enchanting table:** the third slot costs 3 levels and 3 lapis ($180 at
  sell prices). It typically produces 5 to 10 levels of enchantments on a
  book ($12) or a wooden sword ($9), which sells for **$2.5K–$5K** each.
  XP is free from spawners (`smp_spawners.collect_xp`) and mob farms.
- **Fishing:** AFK fishing loot includes enchanted books, bows and rods.
- **Shard shop gear:** see S05 SH-2. A Netherite Axe costs 600 shards and
  sells for $104,500.

**Fix (spec decision, f02 §10 V-99):**
- Cap the bonus relative to the item: `bonus = min(levels × per_level,
  base_price)`. An enchanted $9 sword can then never be worth more than
  $18.
- Exclude `mcl_enchanting:book_enchanted` (or price books from a table).
- Refuse or zero stacks carrying a shop tag (`smp:shardshop=1`,
  coordinate with S05).
- Consider a lower default, for example $10/level.

**Tests.** A wooden sword with `sharpness 5`: its unit value is at most
`2 × base` under the cap. An enchanted book is priced by its table entry,
not by the bonus.

---

### SE-3 — Walls priced above their cobble (corrected)

> **Correction (2026-09-27).** The first version of this finding said
> cobblestone was unlisted and paid $1, which made the wall a "7×" faucet.
> That was wrong: the audit read the price table from line 40 and missed
> `["mcl_core:cobble"] = 600` at `prices_default.lua:35`. The corrected
> finding is small.

`["mcl_walls:cobble"] = 700` (`:48`) is priced above
`["mcl_core:cobble"] = 600` (`:35`). The stonecutter makes 1 cobble → 1
wall (`_mcl_stonecutter_recipes`, `mcl_walls/init.lua:278`), and the
crafting grid makes 6 → 6. So every generator block is worth $7 instead of
$6 when it goes through a stonecutter. Mossy cobble ($9) → mossy wall ($10)
works the same way.

**Fix.** Price walls at or below their source block (wall ≤ cobble). The
SE-1 recipe test enforces this from then on. Severity: **Low**.

---

### SE-4 — Combat-log escape through the sell container

`smp_sell/mod.conf` has `optional_depends = … smp_combat`, so
`smp_sell` always loads **after** `smp_combat`, and its
`register_on_leaveplayer` runs after `smp_combat.on_leave`
(`smp_combat/init.lua:135`). The order on leave while tagged is:

1. `smp_combat.on_leave` → `drop_death_lists` empties `main`, armour and
   so on onto the ground (the killer's loot).
2. `smp_sell`'s leave handler (`init.lua:604`) → `menu.return_contents`
   puts the **sell-container** contents back into the now-empty `main`.
3. The engine saves the player **with those items**.

**Repro.** Get combat-tagged, run `/sell` (explicitly allowed in combat,
`smp_combat/config.lua:36`), drag valuables into the grid **without
confirming**, then disconnect. On rejoin the valuables are in your
inventory. The same happens with the orders delivery grid
(`smp_orders/init.lua:727`, which loads after `smp_combat` alphabetically)
and, depending on resolver order, with the AH insert flow.

**Fix (coordinate with S07, which owns the combat side):**
1. In `smp_sell`, refuse `allow_put` while
   `smp_combat.is_tagged(player_name)`. `/sell hand` and `/sell all`
   still work while tagged, because they sell immediately. Do the same in
   the orders delivery grid and the AH insert grid (their own briefs).
2. Structural fix, in S07: register the combat-log drop **last**. See
   S07 CB-1.

**Test.** Harness: tag the player, put a diamond in the sell grid, run
every registered leave handler in registration order, and assert that the
diamond ends in the dropped set, not in `main`.

---

### SE-5 — Each sale scans all of `smp_store`

`history.append` → `smp_store.api.append_history` → the mod-storage
driver `append_history` (`smp_store/backends/mod_storage.lua:181-187`)
iterates **every key** of the store's mod storage to prune one list. That
storage also holds every ledger row (`ledger:NNNNNNNNNN`), which grows
forever. On the default backend (mod_storage whenever `lsqlite3` is not
installed), every `/sell`, sell-axe use and spawner "Sell all" is
O(total ledger rows). `/sell` has no rate limit, so a player can create
visible lag by spamming it.

**Fix.**
- **ESCALATE** (`smp_store`): track a per-list `oldest` id key and prune
  from it, instead of scanning `get_keys()`.
- Locally: rate-limit `/sell` and the container confirm (for example one
  per second, reusing the `/pay` cooldown pattern from `smp_economy`).

## Verified OK (no action)

- The sell pipeline order is validate → consume → pay → give back. A refused
  sale touches nothing. A partial failure returns exactly the unpaid lots
  (`sell.lua:303-351`).
- The container is owner-only (`is_owner` also re-checks the session). Death
  drops the contents. Shutdown returns them. The crash mirror is written and
  cleared in the same server step as the inventory change, so a clean save
  point cannot hold both copies.

## Definition of done

- SE-3 and SE-4 fixed in code, with tests.
- SE-1 and SE-2 decided in f02 §10 and implemented. The recipe-arbitrage
  test lands and is green.
- SE-5's rate limit is in, and the store change is escalated.

## Status (2026-09-27, verified)

| ID | Outcome | Change |
|---|---|---|
| SE-1 | **FIXED** | `sell.default_price` default → `0` (feature off). Mirror change → ESCALATE (f02 §13.1). |
| SE-2 | **FIXED** | Enchant bonus capped at `base_price`. Enchanted books are unlisted, so unsellable while the default price is 0 (f02 §13.2). |
| SE-3 | **FIXED except the OBSERVED wall** | 17 PROPOSED prices corrected, found by the live-registry scan. The $7 cobble wall ($1 over cobble) is OBSERVED [S2] and awaits an integrator ruling (f02 §13.3). |
| SE-4 | **FIXED** | Sell grid `allow_put` refuses while tagged; `/sell hand` still works in combat (in-game T10 updated). |
| SE-5 | **FIXED** (local) | `/sell` and container confirm rate-limited ~1/s. Store prune-index → ESCALATE. |
| SH-2 hand-off | **FIXED** | `items.sellable` refuses `smp:shardshop="1"` stacks. |
| Recipe test | **ADDED** | `smp_sell/arbitrage.lua`, asserted by `/smp test smp_sell`. Run headless on Luanti 5.17 + Mineclonia: 1834 recipes, 38 → 0 violations; a reverted price is caught. |

**Tests:** `dev-tests/test_sell.lua` ALL OK (it also runs the in-mod suite, 65 assertions).
The arbitrage assertion runs only in-engine (the harness has no recipes).
