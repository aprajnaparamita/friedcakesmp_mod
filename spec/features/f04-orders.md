# f04 — Orders

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_orders` |
| Phase | P3 |
| Depends on | `f03-auction`, `f02-sell`, `f01-economy-core` |
| Frame evidence | **47 frames** — the best-covered feature. Fulfilling 00:02:34–00:03:04, creating 00:03:04–00:03:45 |
| Confidence | **High.** Both the creation flow and the delivery flow were recorded end to end. |

## 2. Commands

| Command | Arguments | Behaviour | Status |
|---|---|---|---|
| `/orders` | — | Open the orders board | **OBSERVED** [F0155–F0158] |
| `/order` | `[search]` | Search orders | LIVE [S6] |

## 3. Observed UI

### 3.1 `Orders (Page 1)` — the board [F0156–F0187, F0209–F0212]

![Orders board](../../frames/frame_0158.jpg)

A **container menu**, middle 40–60% of the screen, opaque light grey. A grid of
open orders above an `Inventory` label and the player's inventory.

Controls:

| Item | Tooltip | Opens | Frames |
|---|---|---|---|
| book | `Orders` / `Request and deliver items` | the board itself (header item) | F0156, F0158 |
| hopper | `Filter` / `Click to change` + option list | cycles the sort | F0180, F0181 |
| chest | `Your Orders` | `Orders -> Your Orders` | F0186, F0190 |
| amethyst shard | `Shard Shop` / `Click to view` | the shard shop (`f06`) | F0179, F0182 |

> The shard shop is reachable from the orders board. `f06` must expose an entry
> point callable from here.

**Order tooltip** — the richest observed tooltip [F0164, F0165]:

```
Netherite Helmets                                            ← PLURAL display name
Protection IV, Respiration III, Aqua Affinity, Unbreaking III, Mending
$ 4M each                                                    ← unit price
251/350 Delivered                                            ← progress
Click to deliver items                                       ← affordance
minecraft:netherite_helmet                                   ← itemstring (translate)
20 component(s)                                              ← DROP
```

Observed orders, showing the scale the design must carry:

| Item | Unit price | Progress | Frame |
|---|---|---|---|
| `Beacons` | `$ 182K each` | `2.1k/2.5k Delivered` | F0159 |
| `Gold Ingots` | `$ 1K each` | `753k/1.3m Delivered` | F0160 |
| `Netherite Helmets` (enchanted) | `$ 4M each` | `251/350 Delivered` | F0164 |
| `Totems of Undying` | `$ 30K each` | `167k/200k Delivered` | F0212 |
| `Empty Maps`, `Bones` | — | — | F0161, F0171 |

Two consequences that are easy to miss:

1. **The enchantment line is part of the order's identity**, not decoration. An
   order for Protection IV / Respiration III / Aqua Affinity / Unbreaking III /
   Mending netherite helmets is not filled by a plain one. This is what the M1
   matching level exists for (`shared §2.5`).
2. **Quantities reach 1.3 million.** Delivered counts must be virtual integers,
   never stacks in a container.

### 3.2 `Filter` — sort options [F0180, F0181]

```
Filter
Click to change
• Most Per Item
• Most Paid
• Recently Listed
```

**Different from the auction's three** (`Lowest Price`, `Highest Price`,
`Recently Listed`). A supplier wants the best-paying orders; a buyer wants the
cheapest listings. Do not share the sort enum between the two mods.

### 3.3 Creating an order

Path: `Orders (Page 1)` → `Your Orders` → `Orders -> Your Orders` [F0190] →
an empty slot → the wizard.

**Step 1 — `Choose Item`** [F0191, F0192, F0194, F0196, F0197]

![Choose Item](../../frames/frame_0192.jpg)

```
Choose Item  ⚠
      Search
  [ totem              ]
  [ Search ]
  ▸ Acacia Boat
    Acacia Button
    Acacia Door
    … alphabetical, scrolling, icon beside each name
  [ Cancel ]
```

After searching, the title becomes `Choose Item (1 results)` [F0198] and the
list narrows to `Totem of Undying`. **Reproduce the ungrammatical `(1 results)`
exactly** (`shared §0.5`).

Hovering an item shows its worth [F0192] — the base price from `f02`, giving
the buyer a reference before naming a price.

**Step 2 — `How many?`** [F0199]

```
How many?  ⚠
  Amount
  [ 1                  ]     ← pre-filled with 1
  [ Cancel ]      [ Next ]
```

**Step 3 — `Price per item?`** [F0202, F0203]

```
Price per item?  ⚠
  [ 10_                ]
  [ Cancel ]   [ Review Order ]
```

The final step's forward button is named for the next screen, not `Next`.

**Step 4 — `Review Order`** [F0204–F0208]

![Review Order](../../frames/frame_0204.jpg)

```
Review Order  ⚠
          [item icon]
     Item: Totem of Undying
     Amount: 1
     Price: $ 10 each
     Total: $ 10

  [ Cancel!       ]  [ Change Item  ]
  [ Change Amount ]  [ Change Price ]
        [ Create Order ]
```

One `Change …` button per collected value, so a mistake costs one step rather
than the whole wizard. `Cancel!` carries its exclamation mark. On
`Create Order` the interface returns to `Orders (Page 1)` [F0209].

### 3.4 Delivering into an order

Path: click an order on the board (`Click to deliver items`).

**`Orders -> Deliver Items`** [F0214, F0215, F0216]

A **container menu** with an empty grid to drop items into, above the player's
inventory. Note the separator `->`, unlike the auction's `>`.

**`Orders -> Confirm Delivery`** [F0218, F0219, F0222]

![Confirm Delivery](../../frames/frame_0219.jpg)

The placed stack plus a detail panel:

```
Totems of Undying
300K requested
$30K each
You're delivering 1 Totems of Undying
minecraft:totem_of_undying
15 component(s)                    ← DROP
```

The confirm control is a **lime stained glass pane** [F0222]:

```
Confirm
Click to deliver items ($30K)      ← the payout is in the affordance line
```

> `You're delivering 1 Totems of Undying` keeps the plural noun at quantity 1.
> The reference server does not inflect. Reproduce it (`shared §0.5`).

**Feedback** [F0226, F0227]:

- Action bar: `Delivering...`
- Chat: `You delivered 1 Totem of Undying and received $30K`

Here the chat message *does* use the singular. The interface is internally
inconsistent; both strings are reproduced as observed.

### 3.5 Not observed

Cancelling an order; collecting delivered items; escrow display; expiry;
partial-fill rejection; what happens when delivering to your own order; the
`Orders -> Your Orders` slot layout in detail.

## 4. Behaviour

1. **Board.** Paginated, title `Orders (Page @1)` (`OBSERVED`), sortable by
   `Most Per Item`, `Most Paid`, `Recently Listed` (`OBSERVED`).
2. **Creation flow** (`OBSERVED`, all four steps):
   `Choose Item` → `How many?` → `Price per item?` → `Review Order` →
   `Create Order`.
3. **Item identity** is M1, **including enchantments** (`OBSERVED` via the
   enchantment line [F0164]). Named stacks are rejected (`shared §2.5`).
4. **Escrow.** `unit_price × quantity` is escrowed at creation (`PROPOSED`; the
   wiki says only that buyers offer money for items [S6]). `Total: $ 10` on
   `Review Order` [F0204] is the amount committed.
5. **Automatic purchase from the auction house.** Immediately after creation
   the order buys matching listings at or below its unit price, cheapest first,
   until filled [S2][S6]. Each seller receives their own listing price; unused
   escrow stays with the order.
6. **Delivery** (`OBSERVED`): supplier opens `Orders -> Deliver Items`, places
   items, moves to `Orders -> Confirm Delivery`, confirms via the lime pane.
   Matching items (M1) are accepted up to the remaining quantity and paid at
   the unit price from escrow; everything else is returned. Partial fills are
   allowed (`251/350 Delivered` [F0164] is a live partial fill).
7. **Self-delivery** MUST be refused (`PROPOSED`).
8. **Routing in.** Orders also receive items routed from `/sell`, from spawner
   "Sell all", from the amethyst sell axe, and from auction listings whenever
   the order pays more [S2][S4].
9. **Collection.** Delivered items are stored as **virtual counts** in the
   order record and converted into stacks when collected. Required by the
   observed scale (§3.1).
10. **Cancellation and expiry.** Cancelling refunds unspent escrow; delivered
    items stay collectible. Orders expire after `orders.duration`
    (`PROPOSED` 7 days) with the same effect.
11. **Capacity.** tier1 45, tier2 90 [S17]; default `PROPOSED` 9.
12. **Exclusions.** Amethyst items cannot be ordered [S9]; further exclusions
    go in `orders.blacklist`.
13. **Notifications** respect `eco.order_alerts` (`f12`).

## 5. Data schema

```lua
{
  id = 3301, version = 4,
  state = "open",                     -- open | filled | cancelled | expired
  buyer = "Carol",
  key = "<M1 key>",
  template = "mcl_potions:totem",
  ench = { protection = 4, respiration = 3, aqua_affinity = 1,
           unbreaking = 3, mending = 1 },   -- part of the M1 key [F0164]
  qty = 200000, delivered = 167000, collected = 120000,
  unit_price = 3000000,               -- $30K in cents
  escrow = 99000000000,               -- unit_price * (qty - delivered)
  created = 1758500000, expires = 1759104800,
  suppliers = { Bob = 600, Alice = 600 },
}
```

`qty`, `delivered` and `collected` are integers, not stack counts:
`753k/1.3m Delivered` [F0160] exceeds any container.

## 6. Algorithms

### 6.1 Creation with automatic auction purchase

```lua
function smp_orders.create(player, key, qty, unit_price)
  if not smp_orders.can_create(player) then return refuse("slot limit") end
  if smp_orders.blacklisted(key) then return refuse("item cannot be ordered") end
  local total = unit_price * qty
  if smp_economy.get(player) < total then return refuse("insufficient funds") end

  smp_economy.take(player, total)                              -- escrow
  local id = smp_store.insert_order{ buyer = player:get_player_name(),
    key = key, qty = qty, unit_price = unit_price, escrow = total,
    delivered = 0, collected = 0, state = "open", created = os.time(),
    expires = os.time() + cfg.orders.duration }
  smp_store.ledger("order_escrow", player, nil, total, { ref = "order:" .. id })

  -- sweep the auction house for listings at or below unit_price, cheapest first
  for _, l in ipairs(smp_ah.listings_at_or_below(key, unit_price)) do
    local o = smp_store.get_order(id)
    if o.delivered >= o.qty then break end
    local take = math.min(ItemStack(l.stack):get_count(), o.qty - o.delivered)
    smp_orders.absorb_listing(o, l, take)                      -- seller paid l.price
  end
  return id
end
```

### 6.2 Delivery

```lua
function smp_orders.deliver(player, order_id, stacks, seen_version)
  local o = smp_store.get_order(order_id)
  if not o or o.state ~= "open" or o.version ~= seen_version then
    return refuse("order changed")
  end
  if o.buyer == player:get_player_name() then return refuse("own order") end

  local accepted, payout = 0, 0
  for _, s in ipairs(stacks) do
    if smp_items.matches(s, o.key, "M1") then
      local n = math.min(s:get_count(), o.qty - o.delivered - accepted)
      accepted = accepted + n
      payout   = payout + n * o.unit_price
      if n < s:get_count() then return_to(player, s, s:get_count() - n) end
    else
      return_to(player, s, s:get_count())                      -- non-matching returned
    end
  end
  if accepted == 0 then return refuse("nothing matched") end

  -- no yields from here (shared §2.3)
  o.delivered = o.delivered + accepted
  o.escrow    = o.escrow - payout
  o.version   = o.version + 1
  o.suppliers[player:get_player_name()] =
    (o.suppliers[player:get_player_name()] or 0) + accepted
  if o.delivered >= o.qty then o.state = "filled" end
  smp_economy.give(player, payout)
  smp_store.ledger("order_payout", o.buyer, player, payout,
                   { ref = "order:" .. order_id })
  chat(player, S("You delivered @1 @2 and received $@3",
                 accepted, item_name(o.key, accepted), fmt(payout)))   -- [F0227]
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `orders.slots` | `{default = 9, tier1 = 45, tier2 = 90, tier3 = 90}` | LIVE [S17]; default and tier3 PROPOSED |
| `orders.duration` | 604,800 s | PROPOSED |
| `orders.blacklist` | amethyst items | LIVE [S9] |
| `orders.sorts` | `{most_per_item, most_paid, recently_listed}` | **OBSERVED** [F0180] |
| `orders.default_amount` | 1 | **OBSERVED** [F0199] |
| `orders.allow_self_delivery` | false | PROPOSED |
| `orders.page_size` | 45 | PROPOSED |
| `orders.min_price` | $1 | PROPOSED |
| `orders.flush_interval` | 10 s | PROPOSED |
| `orders.expire_check_interval` | 60 s | PROPOSED |

## 8. Mineclonia implementation

- Board, `Your Orders`, `Deliver Items` and `Confirm Delivery` are **container
  menus**; the four wizard steps are **prompt menus**.
- The wizard needs a server-side session holding `{item, amount, price, step}`.
  `Change Item` / `Change Amount` / `Change Price` jump to that step with the
  other values intact — the session, not the client, holds the state.
- `Deliver Items` needs a **detached inventory**, owner-only, returning
  contents on disconnect (`shared §2.6` R6).
- Order tooltips are multi-line `tooltip[]`; build the enchantment line from
  `mcl_enchanting.get_enchantments` in the observed order (as registered), with
  Roman numerals and level 1 omitted.
- Progress counters are integers; format with the shared lower-case suffix
  formatter (`2.1k/2.5k`, `753k/1.3m`).
- Action bar during delivery: `mcl_title.set(player, "actionbar",
  {text = S("Delivering...")})`.
- Re-validate `order.version` on every delivery click.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | The board title reads exactly `Orders (Page 1)`; `Filter` cycles the three **orders** sorts, not the auction's |
| T2 | An order tooltip renders name, enchantments, `$ @1 each`, `@1/@2 Delivered`, `Click to deliver items`, itemstring — in that order |
| T3 | Order display names are plural; the delivery chat message is singular. Both as observed |
| T4 | `Choose Item` search narrows the list and the title becomes `Choose Item (1 results)` |
| T5 | Each `Change …` button returns to that step alone, preserving the other two values |
| T6 | `Create Order` escrows exactly `Total`, and the balance drops by that amount |
| T7 | A new order immediately absorbs cheaper matching auction listings, cheapest first |
| T8 | Delivering an unenchanted helmet to an enchanted-helmet order is rejected and the item returned |
| T9 | Over-delivering fills to the remaining quantity and returns the surplus |
| T10 | Delivery pays exactly `unit_price × accepted` from escrow, and escrow never goes negative |
| T11 | Delivering to your own order is refused |
| T12 | An order of 1,300,000 items renders `753k/1.3m Delivered` and never materialises stacks |
| T13 | Disconnecting with `Deliver Items` open returns every item |
| T14 | Cancelling refunds unspent escrow exactly; delivered items stay collectible |

## 10. Open questions

| Id | Question |
|---|---|
| V-09 | **Closed for the flow.** Creation and delivery are fully known. Escrow, cancellation, expiry and default slots remain unobserved |
| V-43 | How are delivered items collected by the buyer? `Your Orders` was opened but no order was clicked |
| V-44 | Is escrow shown anywhere? `Review Order` shows `Total` but no later screen shows a balance |
| V-45 | Is delivering to one's own order actually blocked on the reference server? |
| V-46 | What does the worth shown on `Choose Item` hover represent — the `/sell` base price, or the current lowest auction price? |
| V-47 | Are partial deliveries paid immediately, or held until the order fills? The observed `Delivering...` → payment sequence suggests immediately |
| V-48 | What does `orders.sorts.most_paid` rank by — total committed (unit × qty) or total paid out? Implemented PROPOSED as total committed |
| V-49 | Does `@1 requested` on Confirm Delivery show the total `qty` or the remaining? Implemented PROPOSED as total `qty` |
| V-50 | Do open orders occupy a slot until fully collected (so a filled-but-uncollected order blocks the slot)? Implemented PROPOSED as "occupies while delivered > collected" |
| V-51 | Does `Choose Item` offer only plain (unenchanted) items? No enchantment-selection UI was observed; the wizard creates plain M1 orders. PROPOSED: yes |
| V-52 | When an order absorbs an auction listing larger than its remaining quantity, is the listing split or skipped? f03's `consume_listing` closes whole listings, so f04 skips it. PROPOSED |

## Proposed shared changes

These need integrator action; feature agents must not edit `spec/shared/` directly.

1. **`smp_items` is no longer a stub.** f04 filled it in with the §2.5
   contract (`key`, `matches`, `parse_key`, `stack_from_key`, `plain`,
   `meta_hash`, `display_name`). f02 (`smp_sell/items.lua`) and f03
   (`smp_ah/keys.lua`) both wrote deferral shims that pick the real
   implementation up automatically, so no other agent needs to change
   anything — but the integrator should confirm the three agree on the
   key spelling: `m0|<name>`, `m1|<name>|<ench>|<meta_hash>`,
   `m2|<name>|<ench>|<wear>|<named>|<contents>|<meta_hash>`.

2. **Orders persistence lives in smp_orders' own mod storage**, not in
   `smp_store`, because `smp_store` exposes no order table API and feature
   mods may not edit it. When the integrator adds orders to `smp_store`
   (SQLite at scale, shared §2.2), `smp_orders/orders.lua` is the only
   file that changes: `save_dirty`/`load_all` swap their storage backend
   and the CRUD/query/index layer above them stays put.

3. **`/smp test <feature>` is hardcoded to `smp_core`** in smp_economy.
   f04 ships `friedcake/mods/smp_orders/test.lua` (returns
   `{passed, failed, lines}`) but it is only discoverable if the
   integrator generalises the loader to `<modpath>/test.lua`. Until then,
   `/smp test smp_orders` reports "Unknown test target".

4. **Itemstring corrections** (Mineclonia @ `5bdce566`): the grey/lime
   confirm panes are `mcl_panes:pane_grey` / `mcl_panes:pane_lime`, NOT
   the `mcl_core:glass_pane_gray`/`lime` guessed in `04-ui-kit.md §4.3`.
   The totem is `mcl_totems:totem`, not the `mcl_potions:totem` written in
   f04 §5's schema example. `04-ui-kit.md` and f04 §5 should be corrected.

5. **Two f03 integration seams to reconcile before merge:**
   - `smp_ah.consume_listing` writes an `ah_sale` ledger row *and* f04's
     absorb path writes an `order_payout` row — one credit, two ledger
     entries (breaks X4). Propose `consume_listing(id, buyer, price,
     reason, opts)` with `opts.ledger = false` for the f04 path, or pick
     one reason code.
   - f03's `create_listing` treats any non-error `fill_from_stack` return
     as `"routed"` and discards the stack; f04's `fill_from_stack` returns
     `nil, reason` on refusal (self-delivery, oversized stack, changed
     order), which f03 would mis-read as success and drop items. f03 must
     distinguish `(nil, reason)` refusals (X1 item-loss risk).

## 11. Implementation notes (f04 agent)

**Contracts implemented (called by other features):**

- `smp_orders.best_open_order(m1_key)` → order | nil (f03 §6.1).
- `smp_orders.fill_from_stack(order, player_or_name, stack)` →
  `{accepted, payout, remaining=0}` or `nil, reason`. Consumes the WHOLE
  stack or refuses (never partial — see f03 seam above).
- `smp_orders.open_orders_above(key, unit_cents, [seller_name])` →
  descending-unit-price open orders with remaining > 0; own orders
  skipped when `seller_name` is given (f02 §6).
- `smp_orders.absorb_from_sell(order, player_or_name, key, qty)` →
  `accepted_count, cents_paid` (f02 §6; their adapter reads the two-value
  shape). Key may be M0 or M1 (`to_m1` normalises).
- `smp_orders.au.listings_at_or_below(key, unit_price)` — forwards to
  `smp_ah.listings_at_or_below(key, unit_price, os.time())`, `{}` when
  smp_ah is absent (`TODO(f03)`).
- `smp_orders.au.consume_listing(listing_id, buyer, price)` — forwards to
  `smp_ah.consume_listing(listing_id, buyer, price, "routed")`.

**T13 approach:** delivery uses a **detached inventory**
(`smp_orders_deliver_<name>`, owner-only callbacks). Contents are returned
on menu close without confirm (quit field), on confirm-failure-with-items,
and on `leaveplayer`; the inventory is then removed. Matched/consumed
items are annihilated into the order's virtual `delivered` count — nothing
is materialised until `collect()` (T12).

**PROPOSED decisions worth surfacing:** plural rule ("X of Y" pluralises
the first word, otherwise the last), quantity lower-casing
(`300k requested` vs observed `300K`), the "skip oversized listing" sweep
rule, the whole-stack `fill_from_stack` rule, `orders.page_size = 45`,
`orders.min_price = $1` (observed `Minimum: $ 1`), `orders.default
slot 9`, order manage/collect/cancel UI (`Collect Items` / `Cancel Order`
/ `Escrow: $ @1` / `@1 collected` / `New Order` / `Click to manage`,
house style after f09), creation rate limit 1/s (R9), and every unobserved
refusal message (`You reached order limits`, `This item cannot be
ordered`, `You cannot deliver to your own order`, `This order has
changed`, `Nothing matched this order`, `Order created`, `Order
cancelled, @1 refunded`, …). The `⚠` warning triangle on prompt titles is
omitted — no Mineclonia texture exists and its meaning is unresolved
(V-28).
