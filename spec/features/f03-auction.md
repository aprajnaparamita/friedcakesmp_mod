# f03 — Auction House

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_ah` |
| Phase | P3 |
| Depends on | `f01-economy-core`, `smp_items`; routes with `f04-orders` |
| Frame evidence | **28 frames** — browse and search 00:01:47–00:02:07, listing 00:02:07–00:02:25 |
| Confidence | **High for the interface**, low for economics (fees, durations and slot limits are never on screen) |

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/ah` | `/auction`, `/auctionhouse` | `[search]` | Open the auction house, optionally pre-filtered | **OBSERVED** [F0105–F0107] |
| `/ah sell` | `/auction sell` | `<price>` | List the held stack | LIVE [S5] |

> The observed listing path is **not** `/ah sell`. The player goes
> `/ah` → `Your Items` → `List` → `Insert Item` → price → `Confirm Listing`
> [F0126–F0142]. `/ah sell` is documented [S5] and should exist as a shortcut,
> but the menu path is the primary and is what the interface teaches.

## 3. Observed UI

### 3.1 `Auction (Page 1)` — the board [F0107–F0129]

![Auction board](../../frames/frame_0124.jpg)

A **container menu**, middle 50% of the screen, opaque light grey, a grid of
listings above an `Inventory` label and the player's own inventory.

```
Auction (Page 1)
  ┌───────────────────────────────────────┐
  │  listing  listing  listing  …         │   ← ~6 rows × 9 columns
  │  …                                    │
  │  [sign]  [hopper]  [chest]            │   ← control row
  └───────────────────────────────────────┘
  Inventory
  ┌───────────────────────────────────────┐
  │  player inventory 4 × 9               │
  └───────────────────────────────────────┘
```

Controls are items with tooltips (`shared/04-ui-kit.md §4.3`):

| Item | Tooltip | Opens | Frames |
|---|---|---|---|
| oak sign | `Search` / `Click to search` | `Search Auction` | F0111, F0125 |
| hopper | `Filter` / `Click to change` + option list | cycles the sort | F0118–F0123 |
| chest | `Your Items` / `Click to view` | `Auction > Your Items` | F0126–F0129 |

**Listing tooltip** [F0108, F0124, F0115]:

```
Ender Pearl                 ← singular display name
$700                        ← total price
minecraft:ender_pearl       ← itemstring (translate to Mineclonia)
15 component(s)             ← DROP
```

Observed prices: `$700` [F0108], `$ 9K` (Diamond) [F0124], `$ 25K` (Diamond
Shovel) [F0115]. Gear listings additionally show vanilla stat lines
(`When in Main Hand:`, `5.5 Attack Damage`, `1 Attack Speed`) [F0115] — client
renderings, not cloned (`shared/00-conventions.md §0.5.1`).

**Note what is absent from the tooltip:** no seller name, no time remaining, no
unit price. v0.1 §4.4 specified all three. They may live on a detail screen
that was never opened, but they are not on the board.

### 3.2 `Filter` — sort options [F0118–F0123]

The hopper tooltip carries the option list:

```
Filter
Click to change
• Lowest Price
• Highest Price
• Recently Listed
```

Three options, cycled by clicking. `Lowest Price` is highlighted as current in
F0120 and `Recently Listed` in F0122, confirming a cycle rather than a submenu.

> The official API documents a fourth sort, "last listed" [S23]. It is **not**
> in the menu. Either the API exposes more than the interface, or the fourth
> was removed. See `plan/open-questions.md` V-06.

### 3.3 `Search Auction` [F0114]

![Search Auction](../../frames/frame_0114.jpg)

A **prompt menu**:

```
Search Auction  ⚠
      Search
  [ diamon            ]
  [ Cancel ]  [ Search ]
      red        green
```

`Cancel` renders in red and `Search` in green. Submitting returns to
`Auction (Page 1)` filtered — F0115 shows diamond-only results after the
search.

### 3.4 `Auction > Your Items` [F0131]

![Your Items](../../frames/frame_0131.jpg)

A **container menu**. Note the separator: `>`, not the `->` that orders uses
(`shared/04-ui-kit.md §4.2`).

Holds the player's active listings, plus a control:

| Item | Tooltip | Frames |
|---|---|---|
| gray stained glass pane | `List` / `Click to sell an item` | F0131 |

### 3.5 `Insert Item` [F0132, F0136]

A small **container menu**, about a quarter of the screen: a row of slots to
drop the stack into, an `Inventory` label, and the player's inventory. The
player moves a stack up into the insert row.

### 3.6 `Edit Sign Message` — price entry [F0139, F0140, F0141]

![Edit Sign Message](../../frames/frame_0140.jpg)

```
Edit Sign Message
  [ Type price          ]   ← placeholder text
  [ Done ]
```

**This is Minecraft's sign editor, repurposed as a text prompt.** The
placeholder is `Type price`; the confirm button is `Done`. F0141 shows a typed
`1` above the placeholder line.

Luanti has no sign-edit screen. **Substitution** (decided in
`shared/03-mineclonia-api.md §3.3`): a prompt menu titled
`Edit Sign Message` with a `field[]` labelled `Type price` and a `Done` button.
The strings are kept; the widget changes. This is the only observed interaction
whose *mechanism* is replaced rather than re-rendered.

### 3.7 `Confirm Listing` [F0142]

![Confirm Listing](../../frames/frame_0142.jpg)

A **container menu** showing the stack about to be listed. Its tooltip states
the outcome in the second person:

```
Dirt
You're going to sell this item for $1
minecraft:dirt
13 component(s)          ← DROP
```

The pattern `You're going to sell this item for $@1` matches the
second-person phrasing used in the orders delivery confirmation
(`You're delivering @1 @2` [F0219]).

### 3.8 Not observed

Cancelling or reclaiming a listing; expiry; fees; listing slot limits; the
purchase confirmation dialog; sale notification to the seller; `/ah sell`;
shulker content previews; the transaction history.

## 4. Behaviour

1. **Listing record.** Mirrors the official API: item (id, count, display name,
   lore, enchantment levels, armour trim, container contents), price, seller,
   time left; sales recorded with a millisecond timestamp [S23]. Schema §5.
2. **Board.** Paginated, title `Auction (Page @1)` (`OBSERVED`). Page size
   `ah.page_size` `PROPOSED` 45; the observed grid is roughly 6×9 with the
   bottom row given to controls, so 45 is consistent but unconfirmed.
3. **Sort.** Three options, cycled through the `Filter` control
   (`OBSERVED`): `Lowest Price`, `Highest Price`, `Recently Listed`.
4. **Search.** `Search Auction` filters by item name (`OBSERVED`). `/ah <term>`
   is the command equivalent [S5].
5. **Listing flow** (`OBSERVED`):
   `Your Items` → `List` → `Insert Item` → place stack → `Edit Sign Message`
   → type price → `Done` → `Confirm Listing` → confirm.
6. **Price** is a **total asking price for the stack**, not a unit price:
   `You're going to sell this item for $1` for a stack of dirt [F0142].
7. **Purchase.** Clicking a listing opens a confirmation (`PROPOSED`; never
   observed). On confirm the server MUST re-validate that the listing is still
   active and unchanged (version counter) and that the buyer can pay and has
   room, then pay the seller and deliver the item (`shared §2.3`). A lost race
   produces exactly `This item was already bought` [F0037] — `OBSERVED`, and
   proof that the reference server re-validates.
8. **Capacity.** tier1 45, tier2 90 [S17]; default `PROPOSED` 9.
9. **Duration.** `ah.listing_duration` `PROPOSED` 48 h. Expired listings move
   to the seller's reclaim list, kept 30 days (`PROPOSED`).
10. **Fees.** `ah.listing_fee_pct` and `ah.sale_tax_pct` `PROPOSED` 0; the wiki
    leaves fees, expiry and default slots unspecified [S5].
11. **Routing into orders.** When a compatible (M1) open order would pay more
    than a listing's total asking price, the listing is sold into that order:
    the seller receives the order's payment and the order receives the items
    [S2][S6]. Evaluated when a listing is created and when an order is created
    (`f04`).
12. **Quick Auction Sell.** Announced 16 June 2026 [S2]; mechanics
    undocumented, nothing matching seen in the recording. `PROPOSED`: a
    "Match lowest" button on `Confirm Listing`.
13. **History.** Global transaction log, 100 per page, up to 10 pages, newest
    first [S23].
14. **Price bounds.** `ah.min_price` `PROPOSED` $1 (a $1 listing was created on
    camera [F0142], so the floor is at most $1); `ah.max_price` `PROPOSED`
    $10¹².
15. **Indexes.** In-memory maps from item key to listing ids sorted by unit
    price, and from search token to listing ids, so routing, Quick Buy and
    search avoid full scans.

## 5. Data schema

```lua
-- listing, mirrors api.Ah [S23]
{
  id = 10452, version = 1,
  state = "active",                   -- active | sold | cancelled | expired | routed
  seller = "Alice",
  stack = "mcl_core:diamond 64",      -- ItemStack:to_string()
  key = "<M2 key>",
  display = { name = "Diamond", lore = {}, ench = {}, trim = nil, contents = nil },
  price = 900000,                     -- TOTAL asking price in cents
  unit_price = 14063,                 -- derived
  created = 1758500000, expires = 1758672800,
}

-- transaction, mirrors api.PurchaseItem [S23]
{ id = 55120, listing = 10452, stack = "mcl_core:diamond 64", price = 900000,
  seller = "Alice", buyer = "Bob", sold_at_ms = 1758500200123 }
```

## 6. Algorithms

### 6.1 Listing creation with order routing

```lua
function smp_ah.create_listing(player, stack, total_price)
  if not smp_ah.can_list(player) then return refuse("slot limit") end
  if total_price < cfg.ah.min_price or total_price > cfg.ah.max_price then
    return refuse("price out of range")
  end
  local key  = smp_items.key(stack, "M1")
  local unit = total_price / stack:get_count()

  -- route to a better-paying order first [S2][S6]
  local order = smp_orders.best_open_order(key)
  if order and order.unit_price > unit then
    return smp_orders.fill_from_stack(order, player, stack)   -- seller paid order price
  end

  local id = smp_store.insert_listing{ seller = player:get_player_name(),
    stack = stack:to_string(), key = smp_items.key(stack, "M2"),
    price = total_price, unit_price = unit, state = "active",
    created = os.time(), expires = os.time() + cfg.ah.listing_duration }
  smp_ah.index_add(id)
  smp_store.ledger("ah_list", player, nil, 0, { ref = "ah:" .. id })
end
```

### 6.2 Purchase with re-validation

```lua
function smp_ah.buy(player, id, seen_version)
  local l = smp_store.get_listing(id)
  if not l or l.state ~= "active" or l.version ~= seen_version then
    return chat(player, S("This item was already bought"))    -- exact observed string
  end
  if smp_economy.get(player) < l.price then return refuse("insufficient funds") end
  local stack = ItemStack(l.stack)
  if not player:get_inventory():room_for_item("main", stack) then
    return refuse("no inventory space")
  end
  -- no yields from here (shared §2.3)
  smp_economy.take(player, l.price)
  smp_economy.give(l.seller, l.price)
  player:get_inventory():add_item("main", stack)
  l.state, l.version = "sold", l.version + 1
  smp_store.insert_transaction{ listing = id, buyer = player:get_player_name(),
    seller = l.seller, price = l.price, stack = l.stack, sold_at_ms = now_ms() }
  smp_store.ledger("ah_buy", player, l.seller, l.price, { ref = "ah:" .. id })
  chat(player, S("You bought @1 @2 for $ @3", stack:get_count(),
                 stack:get_description(), fmt(l.price)))       -- observed form [F0055]
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `ah.slots` | `{default = 9, tier1 = 45, tier2 = 90, tier3 = 90}` | LIVE [S17]; default and tier3 PROPOSED |
| `ah.listing_duration` | 172,800 s | PROPOSED |
| `ah.listing_fee_pct`, `ah.sale_tax_pct` | 0, 0 | PROPOSED |
| `ah.min_price`, `ah.max_price` | $1, $10¹² | PROPOSED ($1 floor consistent with [F0142]) |
| `ah.page_size` | 45 | PROPOSED |
| `ah.sorts` | `{lowest_price, highest_price, recently_listed}` | **OBSERVED** [F0118] |
| `ah.history` | 100 per page, 10 pages | LIVE [S23] |

## 8. Mineclonia implementation

- Board, `Your Items`, `Insert Item` and `Confirm Listing` are **container
  menus**; `Search Auction` and the price prompt are **prompt menus**.
- Controls: `item_image_button[]` with the mapped Mineclonia items
  (`shared/04-ui-kit.md §4.3`). Confirm the grey and lime pane itemstrings at
  runtime — they are the least certain mapping.
- `Insert Item` needs a **detached inventory** (`allow_put` restricted to the
  owner, `allow_take` returning the stack) so the stack is never duplicated.
  Return contents on disconnect (`shared §2.6` R6).
- Price entry: `field[]` inside a prompt menu titled `Edit Sign Message`
  (§3.6). Parse with the shared suffix parser (`shared §0.6`).
- Re-validate `listing.version` on every purchase click; the client's page and
  slot index are untrusted.
- Index listings in memory by M1 key sorted on unit price so `f04` routing is
  O(log n).

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | The board title reads exactly `Auction (Page 1)` and pages correctly |
| T2 | The three controls carry exactly the observed two-line tooltips |
| T3 | `Filter` cycles the three observed sorts in order and re-sorts the board |
| T4 | `Search Auction` filters by display name; `Cancel` is red and `Search` green |
| T5 | The full listing flow completes and the price entered is the **total**, not per item |
| T6 | Two players buying the same listing: one succeeds, the other gets exactly `This item was already bought`, and the item is not duplicated |
| T7 | A listing undercutting a better-paying open order routes to the order instead (`f04` integration) |
| T8 | Disconnecting with `Insert Item` open returns the stack to the inventory |
| T9 | A forged listing id or version in a formspec field changes nothing |
| T10 | Listing at the slot limit is refused |

## 10. Open questions

| Id | Question |
|---|---|
| V-06 | **Partly closed.** Sorts are known. Fees, duration and default slots remain unobserved. Why does the API document a fourth sort the menu lacks? |
| V-07 | **Closed.** The board layout, controls and tooltips are known |
| V-08 | Quick Auction Sell mechanics — nothing matching appeared |
| V-28 | What does the yellow warning triangle on prompt menus mean? |
| V-30 | Is the sign-edit substitution acceptable, or should price entry use an anvil-style rename instead? |
| V-40 | Is there a purchase confirmation dialog? Never opened on camera |
| V-41 | Where are seller name and time remaining shown? Not on the board tooltip |
| V-42 | How are listings cancelled or reclaimed? `Your Items` was opened but no listing was clicked |
