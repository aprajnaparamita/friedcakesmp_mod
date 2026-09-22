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

**None.** No frame shows `/shop`. Every element below is `PROPOSED — no frame
evidence` and lives here (not in `shared/08-ui-strings.md`) until the first
screenshot lands. Layouts follow the observed container-menu grammar
(`shared/04-ui-kit.md`) so the panel does not look foreign beside the screens
that *are* evidenced.

### 3.1 Main panel (`PROPOSED` container menu)

```
Quick Buy (Page 1)
  ┌──────────────────────────────────────────────┐
  │  entry  entry  entry  …                      │
  │  [sign]                        [chest]       │   ← Add entry / Your entries
  └──────────────────────────────────────────────┘
  Inventory
```

| Element | `PROPOSED` decision |
|---|---|
| Title | `Quick Buy (Page @1)` — follows the `Auction (Page @1)` / `Orders (Page @1)` grammar |
| Entry grid | 5 rows × 9 columns of `item_image_button[]`, one per entry, aligned with the inventory list below it. Page size `quickbuy.page_size` (45); with `quickbuy.max_entries` 45 there is effectively one page, but the pager renders `<`/`>` when the list overflows |
| `[sign]` | `mcl_signs:wall_sign` with tooltip `Add entry` / `Click to add the held item` — opens the add-entry flow (§3.2) |
| `[chest]` | `mcl_chests:chest` with tooltip `Your entries` / `Click to view` — opens the manage screen (§3.3) |
| Clicking an entry | **Buys it** (the tooltip says `Click to buy`) |

### 3.2 Add-entry flow (`PROPOSED`, follows §4.6 numeric prompt)

`[sign]` snapshots the held stack (itemstring + enchantments via
`mcl_enchanting.get_enchantments`) and opens a `How many?` prompt (reused
title and `Amount` label) pre-filled with the held count, `[Cancel]` left and
`[Add]` right. `Add` writes the entry and returns to the main panel. Holding
nothing refuses with `Hold the item you want to add.` The quantity field
accepts the shared k/m/b suffixes (§0.6).

### 3.3 Manage screen (`PROPOSED` prompt menu)

`[chest]` opens `Your entries`: one row per entry — the item icon (with the
full tooltip), the description and price, an `Edit` button (re-opens
`How many?` to change the quantity) and a `Remove` button — plus `Back`.
Edit keeps the entry's item and enchantments; it only changes `qty`.

### 3.4 Entry tooltip (`PROPOSED`, follows §4.4 listing tooltip)

```
Netherite Sword                 ← display name (singular)
Sharpness V, Unbreaking III     ← enchantments, omitted when unenchanted
$ 2.1M                          ← current lowest price (body spacing)
Click to buy                    ← affordance
mcl_tools:sword_netherite       ← itemstring
```

When there are not enough listings the price line reads `No listings`.
Enchantment names come from `mcl_enchanting.get_enchantment_description`
(roman levels); the dev-test fallback capitalises the id and appends the
roman level.

### 3.5 Price-guard re-confirm screen (`PROPOSED`, follows §4.7 Review Order)

When the live cost exceeds 3× the shown price, a prompt menu titled with the
item name shows the summary block — `Item: @1`, `Amount: @1`,
`Shown price: $ @1`, `Current price: $ @1`, `Total: $ @1` — and a warning
line `The price rose beyond three times what was shown. Confirm to buy
anyway.` Commit is `Confirm`, back-out is `Cancel!` (the exclamation mark is
reproduced, §0.5). The §4.2 yellow warning triangle is not rendered (its
texture and meaning are unverified, V-28).

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
| V-10 | Quick Buy panel layout — entirely unobserved. Everything in §3 is `PROPOSED` |
| V-58 | Does Quick Buy buy across multiple listings to fill a quantity, or only from one? |
| V-59 | Is the 3× guard per purchase or per entry? |

### Decisions taken (all `PROPOSED`, no frame evidence)

- **V-58 — multi-listing fill.** `PROPOSED`: `smp_ah.cheapest_for(key, ench,
  qty)` returns the cheapest active listings whose combined `count` reaches
  `qty`, bought **whole**; the last listing may overshoot `qty` by less than
  one stack. The displayed price and the guard both use the summed
  `cost_cents`, so what the entry shows is exactly what the purchase costs.
- **V-59 — guard per purchase.** `PROPOSED`: the guard is applied **per entry
  purchase** — the displayed price of that entry against the live cost of that
  entry — not once over the whole panel.
- **Guard boundary.** `cost <= shown * price_guard` proceeds; `cost > shown *
  price_guard` warns. `price_guard` is exactly 3.0, so T3 exercises the 3×
  boundary. No guard is applied when no price was displayed (entry showed
  `No listings`).
- **On re-confirm** the purchase re-runs `cheapest_for` and pays the
  then-current live price (listings are re-validated by version), not the
  warned figure; the confirm screen's price is advisory.
- **Success chat.** The per-listing `You bought @1 @2 for $ @3` messages come
  from `smp_ah.buy` (f03 §6.2). Quick Buy itself does not send a success
  line; it sends its own refusals (`Quick Buy is unavailable during combat.`,
  `There are not enough listings to fill this entry.`, `Insufficient funds.`)
  and reuses `This item was already bought.` when every listing was raced.
- **Capacity.** `quickbuy.max_entries` 45 is enforced by `entries.add`
  returning `nil, "capacity"`.

### Bridge contracts (the f03 / f10 / f14 agents implement these)

Written in `friedcake/mods/smp_quickbuy/bridges.lua`; each delegates to the
real mod when present and otherwise returns a safe default.

- `smp_quickbuy.au.cheapest_for(key, ench, qty)` — `key` itemstring, `ench`
  `{ id = level }`, `qty` integer. Returns `nil` when listings are
  insufficient, else `{ listings = { { id, version, count, price, unit_price,
  … }, … }, cost_cents = <integer> }`; `price` on each listing is the integer
  cents the buyer pays for that listing in full, and `cost_cents` is their
  sum. **f03 note:** this is the f05 §6 signature; f03 must translate
  `(itemstring, ench)` to its M1 key internally (`smp_ah.listings.cheapest`
  and `listings_at_or_below` already exist in `f03` — this is the layer above
  them). Exact enchantment matching is required (M1).
- `smp_quickbuy.au.buy(player, id, version)` — re-validates the listing and,
  on success, debits the buyer and returns `{ stack = ItemStack }`; `nil` on
  any failure with no charge. Quick Buy calls this once per listing so a raced
  listing fails cleanly (T7).
- `smp_quickbuy.combat.is_tagged(player)` — boolean (f10).
- `smp_quickbuy.stats.add(player, key, value)` — increments the stat key
  `money_spent_on_shop` by `value` cents (f14).

### Notes for the integrator

- `mod.conf` declares `optional_depends = smp_ah, smp_combat, smp_stats`
  because none of the three has landed yet. When f03 lands and
  `smp_ah.cheapest_for` exists, the `optional_depends` entry may become a hard
  `depends`; the bridge delegation is already wired either way.
- `/smp test smp_quickbuy` is reached through a
  `core.register_on_chatcommand` interception in `init.lua`, because the `/smp`
  dispatcher in `smp_economy` only knows `smp_core` today. Fold this into a
  generic per-mod test registry when one exists.

## Proposed shared changes

None that require a `spec/shared/` edit yet — the Quick Buy strings live in
§3 above until a screenshot exists. Two coordination requests for other agents
(no shared-file edits needed):

1. **f03:** implement `smp_ah.cheapest_for(key, ench, qty)` and make
   `smp_ah.buy(player, id, version)` return `nil | { stack = ItemStack }` per
   the contracts above. The current `smp_ah.listings.cheapest(m1_key)` /
   `listings.listings_at_or_below(m1_key, unit_price)` are the right building
   blocks; `cheapest_for` adds the M1-key translation and the qty-filling
   loop.
2. **f14:** `smp_stats.add(player, "money_spent_on_shop", cents)` must add the
   cents to the existing counter (T6 asserts an exact increment).
