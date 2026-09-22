# f02 — Selling to the Server

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_sell` |
| Phase | P1 |
| Depends on | `f01-economy-core`, `smp_items`; routes into `f04-orders` |
| Frame evidence | **7 frames**, 00:01:31–00:01:46 |
| Confidence | **Medium.** The `Sell` menu was opened and used, but the receipt and the routing display were never shown |

## 2. Commands

| Command | Arguments | Behaviour | Status |
|---|---|---|---|
| `/sell` | — | Open the `Sell` container | **OBSERVED** [F0092–F0096] |
| `/sell hand`, `/sell all` | — | Sell the held stack or the whole inventory | CLONE [C1] |
| `/sellhistory` | `[page]` | Past server sales | LIVE [S3] |
| `/worth` | `[item]` | Show a base price | CLONE [C1] |

## 3. Observed UI

### 3.1 `Sell` [F0093, F0094, F0096]

![Sell menu](../../frames/frame_0093.jpg)

A **container menu**, middle 50% of the screen, opaque light grey with a white
border.

```
Sell
  ┌───────────────────────────────────────┐
  │  drop area                            │
  │  …                              [◼]   │   ← green pane, bottom-right
  └───────────────────────────────────────┘
  Inventory
  ┌───────────────────────────────────────┐
  │  player inventory 4 × 9               │
  └───────────────────────────────────────┘
```

**A green square sits in the bottom-right of the sell grid** [F0094]. Given the
lime stained glass pane used as `Confirm` in the orders delivery flow
[F0222], this is almost certainly the same confirm control.

> **This settles open question V-11.** v0.1 could not determine whether `/sell`
> sells on close or on a button, and defaulted `sell.mode` to `close`. The
> observed menu has a confirm control, so the default becomes `button`. The
> green pane's tooltip was never legible, so the inference rests on the
> pane's colour, position and the confirmed lime-pane idiom elsewhere —
> strong, but not a direct reading.

### 3.2 Result [F0097]

After the menu closes, the HUD shows `$ 189`. No receipt screen and no routing
breakdown appear in any frame.

### 3.3 Not observed

The green pane's tooltip; the receipt; routing feedback; shulker handling;
`/sellhistory`; `/worth`; ineligible-item rejection.

## 4. Behaviour

1. **Eligibility.** An item is sellable if it has a base-price entry and
   matches at level M0 (plain stacks only, `PROPOSED`); Donut accepts only
   supported items [S3]. Amethyst items are sellable [S9]; their timer metadata
   is ignored through `sell.meta_exempt`.
2. **Unit value** is `base_price × sell.multiplier`. Donut applied a temporary
   3× multiplier to every `/sell` price until its planned border expansion
   [S2]; the multiplier is live-tunable, default 1.0.
3. **Sell trigger.** `sell.mode = "button"` (`OBSERVED`, §3.1). The `close`
   mode from clones [C1] remains available as a configuration option.
4. **Routing.** For each item key, if the best compatible open order (M1) pays
   more per unit than the unit value, items go to orders in descending unit
   price while quantity remains; the remainder is sold to the server [S4]. The
   seller receives the order price for routed units.
5. **Shulker boxes.** Eligible contents are sold and the box is returned, still
   holding ineligible items [S2]. Contents are decoded from item meta
   (`compressed` or the empty key, `shared §3.1`) and re-encoded the same way.
6. **Combat.** `/sell` works while combat-tagged; Donut enabled this in June
   2026 [S3].
7. **History.** Each sale appends to the player's sell history; the last 100
   are kept (`PROPOSED`).
8. **Statistics.** Server and order proceeds both count towards
   `money_made_from_sell` (`PROPOSED`).
9. **Tuning.** Donut adjusts individual prices over time — cobblestone and
   cobblestone walls were set to 6 and 7 on 27 June 2026 [S2]. Base prices live
   in a reloadable configuration file.

**Edge cases.** Items that cannot be returned because the inventory is full are
dropped at the player's feet (`PROPOSED`). If the player disconnects with the
container open, contents are returned before the player is saved
(`shared §2.6` R6).

## 5. Data schema

```lua
-- sell-history entry
{ time = 1758500300,
  lines = { { item = "mcl_mobitems:bone", qty = 640,
              server = 400, order = 240, order_ids = { 3301 } } },
  server_total = 400000,              -- 400 bones at $10.00
  order_total  = 360000 }             -- 240 bones at $15.00
```

Base prices are a separate reloadable table keyed by M0 item name.

## 6. Algorithms

```lua
function smp_sell.sell(player, stacks)
  local receipt = smp_sell.new_receipt()
  for _, group in ipairs(smp_items.group_m0(stacks)) do
    local base = smp_sell.base_price(group.key)
    if not base then
      return_to(player, group)                                  -- ineligible
    else
      local unit = base * cfg.sell.multiplier
      local left = group.count

      -- route to better-paying orders first, descending unit price [S4]
      for _, o in ipairs(smp_orders.open_orders_above(group.key, unit)) do
        if left == 0 then break end
        local n = math.min(left, o.qty - o.delivered)
        smp_orders.absorb_from_sell(o, player, group.key, n)     -- pays o.unit_price
        receipt:add_order(group.key, n, o.unit_price, o.id)
        left = left - n
      end

      if left > 0 then                                           -- remainder to the server
        smp_economy.give(player, left * unit)
        smp_store.ledger("sell", player, nil, left * unit, { item_key = group.key })
        receipt:add_server(group.key, left, unit)
      end
    end
  end
  smp_store.append_sell_history(player, receipt)
  receipt:show(player)
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `sell.mode` | `button` | **OBSERVED** [F0094] |
| `sell.multiplier` | 1.0 (Donut used a temporary 3.0 [S2]) | PROPOSED |
| `sell.history_size` | 100 | PROPOSED |
| `sell.meta_exempt` | amethyst items | PROPOSED |
| `sell.base_prices` | reloadable table | LIVE [S2] |

## 8. Mineclonia implementation

- A **container menu** over a **detached inventory** (owner-only `allow_put`,
  `allow_take`, `allow_move`). Never a real node inventory.
- Confirm control: `item_image_button[]` with a lime pane, bottom-right of the
  sell grid, matching [F0094] and the orders idiom.
- Return contents on disconnect and on menu close without confirm
  (`shared §2.6` R6). This is the highest item-loss risk in the mod.
- Routing calls into `f04`; the two mods must agree on the M1 key. Use
  `smp_items` for both — never re-derive a key locally.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | `/sell` opens a container titled exactly `Sell` |
| T2 | Nothing is sold until the confirm control is clicked |
| T3 | Ineligible items are returned, not consumed |
| T4 | Items route to a better-paying order before the server, highest order price first |
| T5 | A shulker's eligible contents are sold and the box returned with ineligible items intact |
| T6 | Closing without confirming returns every item |
| T7 | Disconnecting with the menu open returns every item before the player is saved |
| T8 | A full inventory on return drops items at the player's feet; none vanish |
| T9 | `sell.multiplier = 3.0` triples every server payout and leaves order payouts unchanged |
| T10 | Selling while combat-tagged succeeds |

## 10. Open questions

| Id | Question |
|---|---|
| V-11 | **Closed.** A confirm control exists, so `sell.mode` defaults to `button` |
| V-54 | What is the green pane's tooltip? Never legible |
| V-55 | Is there a receipt screen? `$ 189` appears on the HUD but no breakdown was shown |
| V-56 | Is routing surfaced to the seller at all, or is it silent? |
| V-57 | Does the `Sell` grid accept any item, rejecting on confirm, or refuse ineligible items on drop? |
