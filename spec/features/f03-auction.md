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

### 6.3 History storage seam (decided D12, 2026-09-24)

Auction history rows append through the generic store API — the same seam
f02 uses, namespaced by `kind`, one API serving both features:

```lua
smp_store.api.append_history("auction", name, entry)   -- -> id
```

`kind` is `"auction"`; `name` is the history owner's player name (offline
names work, same rule as the rest of the store); `entry` is a plain table
carried verbatim — the driver stamps `t = os.time()` unless the caller set
one, and money inside stays integer cents. Appends are append-only per
`(kind, name)` and FIFO-pruned to `cap` (optional argument, default 100);
`id` is a monotonic integer per `(kind, name)`, never a float. Wiring
`smp_ah`'s history storage onto this call stays the f03 brief's row.

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `ah.slots` | `{default = 9, tier1 = 45, tier2 = 90, tier3 = 90}` | LIVE [S17]; default and tier3 PROPOSED |
| `ah.listing_duration` | 172,800 s | PROPOSED |
| `ah.listing_fee_pct`, `ah.sale_tax_pct` | 0, 0 | PROPOSED |
| `ah.min_price`, `ah.max_price` | $1, $10¹² | PROPOSED ($1 floor consistent with [F0142]) |
| `ah.page_size` | 45 | PROPOSED |
| `ah.reclaim_days` | 30 d | PROPOSED |
| `ah.insert_slots` | 5 | PROPOSED |
| `ah.rate_limit` | 1 | PROPOSED |
| `ah.sweep_interval` | 60 s | PROPOSED |
| `ah.sweep_budget` | 200 | PROPOSED |
| `ah.history_page`, `ah.history_pages` | 100, 10 | PROPOSED (back-compat aliases for `ah.history`) |
| `ah.sorts` | `lowest_price,highest_price,recently_listed` | **OBSERVED** [F0118]; comma-separated list |
| `ah.history` | `100,10` | LIVE [S23]; comma-list `per_page,pages` (PROPOSED encoding) |
| `ah.reclaim_days` | 30 d | PROPOSED |
| `ah.insert_slots` | 5 | PROPOSED |
| `ah.rate_limit` | 1 | PROPOSED |
| `ah.sweep_interval` | 60 s | PROPOSED |
| `ah.sweep_budget` | 200 | PROPOSED |

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
| A2 | **PROPOSED:** `Match lowest` button on `Confirm Listing` — tooltip `Click to match lowest price`; when no active listings exist for the item, the draft price is left unchanged; the matched price is the lowest *unit* price from the index, multiplied by the stack count to produce a total price; out-of-bounds result is caught by the normal validation path (no yields). |
| A4 | **PROPOSED:** `ah.history` encoding as comma-list `per_page,pages` (e.g. `100,10`). The legacy keys `ah.history_page` / `ah.history_pages` remain as back-compat aliases; if both are set, `ah.history` wins. |
| A5 | **ESCALATED (D7):** `ah.slots` table uses dotted scalars (`ah.slots.default`, `ah.slots.tier1`, …) while f04's `orders.slots` uses underscore scalars (`orders.slots_default`, `orders.slots_tier1`, …). D7 (2026-09-24) ruled "dotted scalar primary + underscore alias" for both. f03 keeps the documented dotted spelling so an operator's `ah.slots.default = 45` works; the mirror reconciliation is D7's. |
| A6 | **PROPOSED (§7 bookkeeping):** five keys read by code but undeclared in f03 §7 are now declared above with their defaults — `ah.reclaim_days` (30 d), `ah.insert_slots` (5), `ah.rate_limit` (1/s), `ah.sweep_interval` (60 s), `ah.sweep_budget` (200). `ah.reclaim_days` was already sanctioned by §11.1; rate limiting by shared §2.6 R9. Mirror additions are D7's (proposed in §10, never hand-edited). |
| V-95 | **Closed (user decision, 2026-09-27): `ah.sale_tax_pct` stays 0 for now.** A post-overhaul summary mentions "a small transaction fee" on sales but gives no rate; revisit if a sourced figure appears. Expiry (48 h, §4 item 9) already matches the summary's "24–48 hours". |
| S03/AH-1 | **Closed (fix brief `fixes/security/S03-auction.md`, 2026-09-27).** `create_listing` read `pcall`'s success flag as `"routed"`, so every `fill_from_stack` refusal (`nil, "full"`, the seller's own order, …) deleted the seller's stack on both the menu and `/ah sell` paths. Now routed only on an explicit `ok and type(res) == "table" and (res.accepted or 0) > 0`, with the count re-read from the stack afterwards; a refusal or a raise falls through to a normal listing, and a soft pre-check (`smp_orders.remaining(order) >= count`, `order.buyer ~= pname`) skips orders that must refuse without calling them. A missing piece of the f04 contract is treated as "proceed to call", never as "no". Tests: `S3-AH-1` (a–e) and `S3-AH-1s` (a–d) in `dev-tests/test_ah.lua`. |
| S03/AH-2 | **Closed (2026-09-27).** `buy`, `withdraw`, `create_listing` and `validate_listing` refuse a non-empty-string player name with `nil, "offline"` before anything runs, and the `chat` / `player_of` / `money_of` helpers harden the choke points (the engine's `l_chat_send_player` / `l_get_player_by_name` both `luaL_checkstring` argument 1). An ObjectRef from `register_on_player_receive_fields` now gets a refusal instead of a fatal error. Tests: `S3-AH-2` in `dev-tests/test_ah.lua`, AH-2 block in `smp_ah/test.lua`. Root caller is S05/QB-1 (not this feature). |
| S03/AH-4 | **Closed + PROPOSED (2026-09-27).** `allow_put` now accepts items only while the flow stage is `insert`, so nothing can be parked in the grid during the price/confirm steps to be wiped by `restore_inserted` or `remove_detached_inventory`; `take_inserted` returns any second stack instead of discarding it, `restore_inserted` drains the row before re-adding, and `commit_listing` drains it before removing the detached inventory. **PROPOSED (coordination A, S02/S07 SE-4):** the same callback also refuses while `smp_combat.is_tagged(name)` — a soft runtime check, because `smp_ah` deliberately does **not** declare `optional_depends = smp_combat`. It loads before `smp_combat` alphabetically, so its `on_leaveplayer` (which returns grid items to `main`) runs before the combat drop; adding the edge would flip that order and reintroduce SE-4. Integrator: confirm the soft check and the missing dependency edge. Tests: `S3-AH-4` in `dev-tests/test_ah.lua`. |
| S03/AH-5 | **Recorded for f05 — target file `spec/features/f05-quickbuy.md` §10 (V-58-adjacent; that file is not editable from f03 or from S03).** `listings.cheapest_for` matches Quick Buy entries on the `m1\|name\|ench\|` prefix and ignores `<meta_hash>`, so Quick Buy can buy a stack whose remaining metadata differs from what the entry describes. f05 must decide whether an item whose meta carries value pins `meta_hash = "0"` in its entry (or whether the matcher must compare `meta_hash`). **No code change made here**: the matching rule is the Quick Buy contract, and `smp_ah` is out of scope for f05's decisions. |
| S03/AH-O1 | **Open.** Should `/ah sell` be refused while the seller is combat-tagged? The S03/AH-4 gate blocks parking items in the insert grid during a tag, but `/ah sell` takes the wielded stack straight from `main` and never touches `allow_put`, so a tagged player can still convert items to money instantly. Left as-is (selling is not item parking and does not defeat the combat-log drop); SE-4's owner should rule. |
| S03/OR-1 | **Recorded (coordination B, from `fixes/security/S04-orders.md`).** Listing writes that move money or items now write through to storage instead of waiting for the 10 s flush: `listings.insert`, `set_state`, `purge` and `insert_transaction` (including the history trim) call `save`/`save_seq` directly; only the cosmetic `touch` version bump stays batched. A crash can no longer leave a paid sale saying "active" on disk. Tests: `S3-OR1` in `dev-tests/test_ah.lua`. |

## 11. Implementation notes (agent/f03-auction)

Written while implementing `smp_ah`. This section is the f03 agent's handoff
to the integrator; it is owned by the f03 agent, not by `spec/plan/` or
`spec/shared/`.

### 11.1 PROPOSED decisions made (open questions this feature had to answer)

Every decision below is marked `PROPOSED` in the code and listed here so the
integrator can replace the defaults with measured values.

| Decision | Value | Why |
|---|---|---|
| Board listing sort | `unit_price` (total price only as a tie-break) | §4.15 indexes by unit price; the board tooltip shows the total. `Lowest Price` is read as per-item. |
| `Insert Item` row size | 5 slots, one stack at a time | The observed menu is a small container; `allow_put` accepts one stack (§4.5: the price applies to one stack). |
| `Your Items` pagination | silent, no `(Page N)` suffix | The observed title has no page suffix (V-42); tier2/3 allow 90 listings, which must still be reachable. |
| `Your Items` listing affordance | `Click to cancel` (active) / `Click to reclaim` (expired) | Cancellation/reclaim were never observed (V-42); house style `Click to <verb>` (shared §0.5.4). |
| `Auction > Confirm Purchase` | container menu, title follows the `>` separator | §4.7 says clicking a listing opens a confirmation (V-40 never opened). |
| Purchase confirm control | lime pane `Confirm` / `Click to buy item ($@1)` | §4.3's Confirm mapping; the amount is parenthesised with no space, matching `Click to deliver items ($30K)` [F0222]. |
| Cancel control | red pane `Cancel` / `Click to go back` | F0142 shows a red block in the `Confirm Listing` grid; `Cancel` is red elsewhere [F0114]. |
| Back-to-board control | anvil `Auction` / `Buy and sell items` | F0107 shows an anvil entry point with these exact lines; reused for navigation. |
| Board pager | `<` / `>` buttons in the control row | Paged-list grammar (shared §4.9); the reference server's pager was never on camera. |
| Seller notification | `You sold @1 @2 and received $@3` | §4.8 rule 2, modelled on `You delivered 1 Totem of Undying and received $30K` [F0227]; §3.8 says sale notification was never observed. |
| Expired/sold reclaim | expired listings reclaimable for `ah.reclaim_days` (30 d); sold listings appear in the transaction log only | §4.9 PROPOSED. |
| Enchantment lines on listings | Mineclonia's own descriptions, grey, between the name and the price | §4.4 rule 4: vanilla stat lines are not cloned; Mineclonia's tooltip conventions apply. |

### 11.2 `smp_items` collision (SHARED §2.5 — two implementations now exist)

While f03 was being implemented, the f04 agent filled in the `smp_items` stub
with its own M1/M2 keying (see the uncommitted `friedcake/mods/smp_items/`
working tree). Two independent §2.5 implementations now exist, and they are
**not byte-compatible**:

| Aspect | `smp_items` (f04) | `smp_ah/keys.lua` (f03) |
|---|---|---|
| Key format | `m0\|name`, `m1\|name\|ench\|meta_hash`, `m2\|name\|ench\|wear\|named\|contents\|meta_hash` | **same** (`m0\|`, `m1\|`, `m2\|`) |
| meta hash | djb2 32-bit hex, empty = `"0"` | `core.sha1` (40 hex) when available, empty = hash of `""` |
| `named` | meta `name` ≠ "" **or** `description` ≠ "" | meta `name` ≠ "" only |
| contents | hash of `key=value` | hash of `key=value` |

f03 deliberately ships **format-compatible** keys (same tags, field order and
separators) so `parse_key` works across both, and it **delegates** to
`smp_items.key`/`smp_items.matches` when a real implementation is loaded
(`smp_items` loads before `smp_ah` in modpack.conf, so the shared owner wins).
This keeps every economy mod on one keying at runtime.

The remaining divergences are the integrator's call (see Proposed shared
changes below). In particular, f04's `named` treats Mineclonia's
`tt`-generated `description` meta as a custom name, which makes **most tools
and armour M1-ineligible** (tt writes a description onto anything with stat
lines) — an enchanted-netherite-helmet order could never be filled. f03
treats `description` as derived/volatile (it is regenerated by `tt` on load)
and only `name` as the custom-name marker, which matches §2.5's wording
("whether the stack carries a custom name").

### 11.3 Contract for f04

- f03 calls `smp_orders.best_open_order(m1_key)` → `{ id, unit_price, ... } | nil`,
  then `smp_orders.fill_from_stack(order, seller_name, stack)` when
  `order.unit_price > unit`. f03 ships a stub of `best_open_order` returning
  `nil` (marked `TODO(f04)`); `smp_orders` replaces it when it loads.
- f04 calls `smp_ah.listings_at_or_below(m1_key, unit_price)` (cheapest
  first) and `smp_ah.consume_listing(id, buyer, price)` to close a listing
  it absorbs; f05 calls `smp_ah.listings.cheapest(m1_key)`.
- The routing test (T7) injects a fake `smp_orders` and exercises both sides
  of this contract headlessly (dev-tests/test_ah.lua).

### 11.4 Latent bug observed in f01 (not fixed — not this feature's file)

`smp_economy`'s `/smp` handler references `run_smp_core_tests` (a `local
function` declared *later* in the file) as a global, so `/smp test smp_core`
raises "attempt to call global 'run_smp_core_tests'". f03's `/smp test
smp_ah` hook falls through to that handler for other targets and is not
affected. Proposing the integrator forward-declare the local or register test
targets through a shared registry (see below).

## Proposed shared changes

Nothing here is edited by the f03 agent; the integrator merges what it wants.

1. **One keying per mod set.** Recommend `smp_items` remain the sole owner of
   §2.5 and that `smp_ah/keys.lua` be deleted once `smp_items` is merged —
   but first align `smp_items.named` with §2.5 (ignore tt's `description`
   meta; only `name` is a custom name), and pick one meta-hash function
   (sha1 vs djb2). f03's delegation already makes runtime behaviour identical;
   this is about the stored-key migration and the M1 tool bug.

2. **`smp_core.fmt_money` "auto" style.** §0.6 requires "suffixed → space,
   bare → no space". The two existing styles (`inline` = never a space,
   `body` = always a space) cannot both express this; f03 derives the §0.6
   form from the two sanctioned styles (`smp_ah.fs.money`) instead of
   reimplementing. Propose a third style (`"auto"` or `"observed"`) in
   `smp_core` so every mod reads the same helper.

3. **Shared test-target registry.** `smp_ah` monkey-patches the `/smp`
   dispatcher to add `/smp test smp_ah` (smp_economy is f01's file and
   `run_smp_core_tests` is out of scope to touch). Propose
   `smp_core.register_test_target(name, fn)` so later features don't have to
   wrap the dispatcher.

4. **`08-ui-strings.md` catalogue phrasing.** The observed `$` spacing (§0.6)
   cannot be expressed with a literal `$` in a translated template. f03 writes
   the money placeholder carrying the full formatted amount
   (`You bought @1 @2 for @3` renders `You bought 1 Ender Chest for $ 5.1K`),
   and uses `$@1`-shaped templates only where the tail is passed in
   (`You're going to sell this item for $@1` with `@1 = "1"` / `" 9K"`).
   Propose the catalogue generalisations be written with the `$` inside the
   placeholder, or with a note explaining the tail convention.

5. **CONTRIBUTING.md indentation.** The style guide says "4-space indent" but
   every shipped Lua file (smp_core, smp_store, smp_economy, the dev tests)
   uses tabs. f03 uses tabs to match. Propose the guide be corrected or the
   files be re-indented.

## Fix-wave record (fix brief, 2026-09-25)

| Row | Outcome | Evidence |
|---|---|---|
| A1 | VERIFIED | `smp_ah/init.lua:1276` uses `core.register_globalstep`; `ah_harness.lua:776` provides it; `rg 'register_on_globalstep' friedcake/mods` = 0 hits |
| A2 | CLOSED | `smp_ah/formspec.lua` adds `Match lowest` button on `Confirm Listing`; `smp_ah/init.lua` handler rewrites draft price from unit-price index; PROPOSED details in §10 A2 |
| A3 | CLOSED | `smp_ah/init.lua` `reload_cfg` parses `ah.sorts` as comma-list; `smp_ah/listings.lua` `SORTS` table driven by config; garbage falls back to default |
| A4 | CLOSED | `smp_ah/init.lua` reads `ah.history` (comma `per_page,pages`); `ah.history_page`/`ah.history_pages` as aliases; `listings.lua` caps use configured values |
| A5 | ESCALATED | Recorded in §10 A5 pointing at D7; dotted spelling kept in code; mirror reconciliation is integrator-owned |
| A6 | CLOSED | Five keys added to §7 as PROPOSED with defaults; §10 A6 notes mirror is D7's |
| A7 | VERIFIED | `grep -rn "TODO(f03)" friedcake/mods` matches only `smp_orders` (f04's mod); `smp_ah/init.lua:656-661` stub retained |
