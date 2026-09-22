# f05 — Quick Buy (`/shop`)

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_quickbuy` |
| Phase | P3 |
| Depends on | `f03-auction` |
| Frame evidence | **0 frames** |
| Confidence | **Research only.** `/shop` is never used in the source video. Everything here comes from the Donut wiki [S7] and the June update notes [S2]. The layout below is a proposal. |

Since 17 June 2026, `/shop` opens Quick Buy, a purchasing interface built on
live auction listings [S7].

## 2. Commands

| Command | Arguments | Behaviour | Status |
|---|---|---|---|
| `/shop` | — | Open Quick Buy | LIVE [S7] |

## 3. Observed UI

**None.** No frame shows `/shop`.

Proposed layout, to be replaced the moment a screenshot exists. It follows the
observed container-menu grammar (`shared/04-ui-kit.md`) so it will not look
foreign beside the screens that *are* evidenced:

```
Quick Buy (Page 1)
  ┌──────────────────────────────────────────────┐
  │  entry  entry  entry  …                      │
  │  [sign]                        [chest]       │   ← Add entry / Your entries
  └──────────────────────────────────────────────┘
  Inventory
```

Entry tooltip, following the observed listing-tooltip shape:

```
Netherite Sword
Sharpness V, Unbreaking III
$ 2.1M
Click to buy
mcl_tools:sword_netherite
```

![SS-08: Quick Buy panel](../../screenshots/SS-08-quickbuy.png)

## 4. Behaviour

1. The player configures entries, each an exact item (including enchantments)
   and a quantity. Every entry shows the current lowest matching auction price
   and can be edited or removed individually [S7].
2. Matching is exact, including enchantments: M1 plus an enchantment
   specification [S2][S7].
3. **Price guard.** A purchase may spend up to three times the displayed live
   price so that it still completes when the cheapest listing changes; beyond
   that threshold a warning screen requires re-confirmation [S7].
4. Quick Buy is unavailable while combat-tagged [S7].
5. Spending counts towards `money_spent_on_shop` [S23].
6. Entries per player: `PROPOSED` 45.
7. A purchase consumes auction listings through `f03`, so every purchase MUST
   re-validate each listing's version (`f03 §6.2`).

## 5. Data schema

In the player record (`f01 §5.1`):

```lua
quickbuy = {
  { key = "mcl_tools:sword_netherite", ench = { sharpness = 5 }, qty = 1 },
  { key = "mcl_core:diamond",          ench = {},                qty = 64 },
}
```

## 6. Algorithms

```lua
function smp_quickbuy.buy(player, entry_index, shown_price)
  if smp_combat.is_tagged(player) then return refuse("unavailable in combat") end
  local e = smp_quickbuy.entry(player, entry_index)
  local listings, cost = smp_ah.cheapest_for(e.key, e.ench, e.qty)
  if not listings then return refuse("not enough listings") end

  if cost > shown_price * cfg.quickbuy.price_guard then
    return smp_quickbuy.warn(player, entry_index, shown_price, cost)  -- re-confirm [S7]
  end
  if smp_economy.get(player) < cost then return refuse("insufficient funds") end

  for _, l in ipairs(listings) do smp_ah.buy(player, l.id, l.version) end
  smp_stats.add(player, "money_spent_on_shop", cost)
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `quickbuy.price_guard` | 3.0 | LIVE [S7] |
| `quickbuy.max_entries` | 45 | PROPOSED |

## 8. Mineclonia implementation

- A container menu built with the shared UI kit.
- Prices are read live from the `f03` unit-price index; never cache them across
  a redraw, or the guard compares against a stale figure.
- The warning screen is a prompt menu following the `Review Order` pattern
  (`shared/04-ui-kit.md §4.7`).

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | An entry shows the current lowest matching auction price and updates on redraw |
| T2 | A purchase within the guard completes without extra confirmation |
| T3 | A purchase above 3× the shown price triggers the warning and completes only after re-confirmation |
| T4 | Enchantment matching is exact: a Sharpness IV sword does not fill a Sharpness V entry |
| T5 | Quick Buy is refused while combat-tagged |
| T6 | Spending increments `money_spent_on_shop` by exactly the amount paid |
| T7 | A listing bought out from under the purchase does not partially charge the buyer |

## 10. Open questions

| Id | Question |
|---|---|
| V-10 | Quick Buy panel layout — entirely unobserved |
| V-58 | Does Quick Buy buy across multiple listings to fill a quantity, or only from one? |
| V-59 | Is the 3× guard per purchase or per entry? |
