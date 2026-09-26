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
  smp_store.api.append_history("sell", player, receipt:to_entry())
  -- The chat receipt is the design (D2); there is no formspec receipt.
  for _, line in ipairs(receipt:messages(cfg.receipt_max_lines)) do    -- receipt.lua:164
    core.chat_send_player(player, line)
  end
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `sell.mode` | `button` | **OBSERVED** [F0094] |
| `sell.multiplier` | 1.0 (Donut used a temporary 3.0 [S2]) | PROPOSED |
| `sell.history_size` | 100 | PROPOSED |
| `sell.history_page_size` | 5 | PROPOSED |
| `sell.receipt_max_lines` | 8 | PROPOSED |
| `sell.meta_exempt` | amethyst items | PROPOSED |
| `sell.base_prices` | reloadable table | LIVE [S2] |
| `sell.default_price` | 100 ($1); 0 disables | PROPOSED (V-98) |
| `sell.enchant_bonus` | 50000 ($500) per enchantment level, curses excluded; 0 disables | PROPOSED (V-99) |
| `sell.enchanted` | `true` — sell unworn enchanted stacks | PROPOSED (V-99) |

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
| V-55 | **Closed (D2, 2026-09-24): the chat receipt is the design; no formspec receipt. §6 amended.** Is there a receipt screen? `$ 189` appears on the HUD but no breakdown was shown |
| V-56 | Is routing surfaced to the seller at all, or is it silent? |
| V-57 | **Closed (PROPOSED).** The grid accepts any item on drop and rejects ineligible items on confirm, returning them — the §4.1 "returned, not consumed" reading. Drop-time refusal was rejected because it contradicts T3/T6 (there would be nothing to return) and because the price table is reloadable, so eligibility can change while a menu is open. |
| V-88 | **[NEW, PROPOSED]** The cobblestone "6" and cobblestone-wall "7" prices in [S2] state no unit. `prices_default.lua` reads them as **dollars** (600/700 cents), matching the inflated Donut economy seen elsewhere (`$30K` totems, `$ 4M` helmets). |
| V-89 | **[NEW, PROPOSED]** Money rounding when `sell.multiplier` is fractional: unit value = `floor(base × multiplier + 0.5)` (round to the nearest cent). §0.7 only pins rounding for *fees*; a price rounding rule is not specified. |
| V-90 | **[NEW, PROPOSED]** The §5 history schema stores only quantities and totals. To render `/sellhistory` lines without re-deriving unit prices, smp_sell adds two per-line fields, `server_cents` and `order_cents`. They are additive to the §5 schema. |
| V-91 | **[NEW]** The §4.8 house-style sell result (`You sold … and received …`) renders money with `smp_core.fmt_money(cents, "body")`, i.e. `$ 30K` with a space, per §0.6. The observed delivery message `You delivered 1 Totem of Undying and received $30K` [F0227] shows the suffixed form *without* a space — a direct contradiction of §0.6 that f04's string also trips over. Needs an integrator ruling for the whole modpack. |
| V-92 | **[NEW, PROPOSED]** The confirm pane tooltip is `Confirm` / `Click to sell items`, without the parenthesised amount that the delivery confirm carries [F0222]. Showing a live total would require re-rendering the formspec on every container change, which risks cancelling an in-flight drag. |
| V-93 | **[NEW, PROPOSED]** Routing is surfaced in chat only: `You sold @1 @2 to an open order and received @3`, emitted only when routing actually happened. V-56's "silent" alternative is retained for the HUD (no routing breakdown appears in any frame). |
| V-94 | **[NEW]** Sell history currently lives in `smp_sell`'s own mod-storage namespace, not in a `smp_store` table (shared §2.2), because `smp_store` has no such API and its sqlite/postgres backends persist exactly six nested player blobs. The smp_store extension is proposed in §11 below; the seam is local (`history.lua` `_read`/`_write`). **Decided (D12, 2026-09-24): `smp_store.api.append_history` now exists — see §11; the f02 brief wires `history.lua` onto it and closes this row (paged read still proposed).** |
| V-97 | **Closed (user-supplied guide, 2026-09-27): no bulk-sell removal; the grid is the design.** The guide describes `/sell` as a drop-in GUI that, on confirm, fills matching player orders (`/order`) at the order price and sells the rest to the server at the fixed baseline — exactly §4 items 3–4 and §6. Order-first routing only when the order beats the baseline is kept (it gives the seller "the best possible price right now"). The gap it recorded — unlisted items returned even when an order wants them — is addressed by V-98. |
| V-98 | **[NEW, PROPOSED — implemented, user decision 2026-09-27]** Every registered item has a server price. A user-supplied guide says "every single item in the game has a default … value" shown by `/worth`. Items missing from the price table now sell at `sell.default_price` (default $1) instead of being returned, which also lets them route to open orders first. An entry configured as `0`/`false` still makes an item unsellable (the operator's deny list); `air`/`ignore`/`unknown` never sell. `smp_sell.base_price` returns the default too, so `/worth` and `smp_orders.worth_of` agree; `/worth` marks it "(default price …)". |
| V-99 | **[NEW, PROPOSED — implemented, user decision 2026-09-27]** Enchanted gear sells. The same guide says high-tier enchantments "add a flat cash bonus on top of the /worth base price". An enchanted stack that is otherwise plain (unworn, unnamed, no contents, no other metadata) now sells for `base + sell.enchant_bonus × Σ levels` (curses excluded), times `sell.multiplier`. It groups and routes under its own M1 key (never the plain key; an enchanted stack `smp_items` cannot key is simply not routed). Worn gear is still returned. Armour-trim bonuses ("certain updates") are not implemented. `sell.enchanted = false` restores the old refusal. |

### Fix-wave record (fix brief, 2026-09-25)

| Row ID | Outcome | Evidence |
|---|---|---|
| F02-1 | **ESCALATED → D12 (integrator)** | `history.lua:43-59,101-117` wired to `smp_store.api.append_history`; V-94 updated; paged read stays local |
| F02-2 | **VERIFIED (D2, 2026-09-24)** | §6 amended per D2 Option A; V-55 closed; `receipt.lua:164-214` chat path is the design |
| F02-3 | **ESCALATED → D7** | `init.lua:94` reads `sell.base_prices`; proposed in §11 item 5 for mirror |
| F02-4 | **DEPENDS-BLOCKER (B4-1)** | `test_sell.lua:685` shim for `register_on_globalstep`; fixed by 00-P0-blockers.md |

**Additional escalations noted:**
- `smp_sell ↔ smp_orders` `optional_depends` cycle in `mod.conf:4` (P5 finding, f04 shares blame) — recorded for integrator resolution; not fixed here to avoid breaking cross-mod routing adapter.
- `smp_economy.give` referenced in §6 pseudocode but code uses `smp_store.api.add_money` (f01 coordination) — pseudocode reflects intent; implementation follows shared §2.3 via store API.

## 11. Proposed shared changes (for the integrator)

Flagging per AGENTS.md rule 1; none of these are required for smp_sell to ship
standalone — every one degrades gracefully at runtime.

1. **`smp_store` history seam — decided (D12, 2026-09-24): one generic API.**
    `smp_sell` still keeps history in its own mod storage (V-94); the seam is
    local (`history.lua` `_read`/`_write`) until the f02 brief wires
    `history.lua` onto the API. The append half of the proposal is ruled:
    one generic `smp_store.api.append_history(kind, name, entry, cap) -> id`
    serves every feature, so the sell call is
    `smp_store.api.append_history("sell", player, entry)` (see §6) —
    append-only per `(kind, name)`, FIFO-pruned to `cap` (optional argument,
    default 100, matching `sell.history_size`), with a monotonic integer id
    per `(kind, name)` and money inside the entry kept as integer cents. The
    paged read half of the original proposal —
    `smp_store.api.sell_history_for(name, page, size) -> {entries, total_pages}`
    — is **not** covered by D12 and stays proposed for the integrator; until it
    lands, `history.lua` remains the implementation of reads.
    **Wiring (this brief):** `history.lua` now delegates `append()` to
    `smp_store.api.append_history` when the API is present (mod loaded after
    `smp_store`), falling back to local mod storage. Reads stay local.
2. **`smp_store.api.add_money` item detail.** The ledger row a sale writes
    uses reason `sell` with the item key and quantity in `ref`
    (`"sell:<key>:<qty>"`) because `add_money` has no `item_key`/`qty`
    parameters. Proposing an `opts` table (`add_money(name, cents, reason,
    ref, { item_key = …, qty = … })`) so the ledger columns are populated
    directly (X4 reconstruction).
3. **`smp_items` key format + plainness.** smp_sell delegates M0/M1/M2 keys
    to `smp_items.key(stack, level)` when present (owner: f04) and keeps
    its own equivalent when smp_items is still the stub. Two proposals:
    (a) `smp_items.named()` should not treat a derived tooltip `description`
    meta as a custom name — Mineclonia's `tt.reload_itemstack_description`
    sets it on enchanted tools and shulker boxes, which would reject them at
    M1; (b) a `sell.meta_exempt` exemption (amethyst `smp:expires_at` timers,
    §4.1 [S9]) needs a way into the shared plainness check, e.g. a
    `ctx`/`exempt` parameter on `smp_items.plain`/`key`.
4. **Glass-pane itemstrings.** shared/04-ui-kit.md §4.3 lists
    `mcl_core:glass_pane_lime`, which does not exist in Mineclonia. The real
    names (verified against `~/dev/mineclonia-git` `mcl_panes`) are
    `mcl_panes:pane_lime_flat` / `mcl_panes:pane_lime` (and `_silver` for the
    light-grey `List` pane). smp_sell resolves the pane at runtime from a
    candidate list, so the shared table can be corrected without breaking it.
5. **Config mirror: `sell.base_prices`.** The key is declared in §7 and read
    at `init.lua:94` (`cfg.base_prices_path = get_str("sell.base_prices", "")`)
    but is absent from `spec/shared/06-config-reference.md`. Proposing mirror
    row through D7 (2026-09-24 ruling: mirror and §7 follow code, both
    directions). This is a declared-only key for the config mirror guard.
6. **Config mirror: `sell.default_price`, `sell.enchant_bonus`,
    `sell.enchanted`** (V-98, V-99). Declared in §7 and read in `init.lua`
    `reload_cfg`; proposing mirror rows in `spec/shared/06-config-reference.md`
    through D7. Until then `test_config_mirror.lua` lists them as violations.

## 12. Implementation status (agent/f02-sell)

Implemented under `friedcake/mods/smp_sell/` and `friedcake/dev-tests/test_sell.lua`:

- Observed `Sell` container: detached inventory, 9×5 grid (44 drop slots +
  the lime confirm pane in the bottom-right cell [F0094]), `Inventory`
  4×9 below, Mineclonia chest geometry. `sell.mode = "button"` default,
  `"close"` clone mode kept [C1].
- `/sell`, `/sell hand`, `/sell all`, `/sellhistory [page]`, `/worth [item]`.
- M0/M1/M2 keys, plainness, and the shulker codec (compressed + empty key),
  with runtime delegation to `smp_items` and a `smp_orders` routing adapter.
- Crash-safe container: contents mirrored to mod storage on every change and
  recovered on the next join (R6/R12 spirit); returns on confirm, close,
  leave, death and shutdown. Full inventory drops at the player's feet (T8).
- Integer cents throughout; `smp_core.fmt_money` for all rendering;
  `core.get_translator` for every string.
- `/smp reload` (wrapped, not edited) re-reads the price table; `/smp test
  smp_sell` runs `test.lua`.

All ten acceptance tests (T1–T10) pass in `friedcake/dev-tests/test_sell.lua`
under `luajit`, and the in-game `test.lua` (64 assertions) passes under the
dev harness.

## 13. Security audit fixes (fixes/security/S02-sell.md, 2026-09-27)

### 13.1 SE-1 — Default price for every registered item (V-98)
**Fixed:** `sell.default_price` default changed from `100` ($1) to `0` (feature off).
An operator must explicitly opt in by setting a positive value.
- `init.lua:97` default changed to `0`
- `prices.lua:189` only applies fallback when `fallback > 0`
- Mirror change required in `spec/shared/06-config-reference.md` → ESCALATE via D7

### 13.2 SE-2 — Enchant bonus cap (V-99)
**Fixed:** `prices.enchant_bonus` now caps at `base_price`: `bonus = min(levels × per_level, base)`.
An enchanted item can never exceed 2× its base value. $500/level default kept.
Enchanted books priced from price table, not from bonus.
- `prices.lua:199-210` signature changed to accept `base_price` parameter
- `sell.lua:87` and `init.lua:426` pass `base` to `enchant_bonus`
- Recorded in f02 §10 V-99

### 13.3 SE-3 — Cobblestone anchor on wall (V-88)
**Fixed:** Cobblestone anchor keyed on `mcl_core:cobble` (600 cents), not `mcl_walls:cobble` (the wall).
Walls, stairs and slabs priced at or below cobble-equivalent:
- `prices_default.lua`: `mcl_core:cobble` = 600 (anchor), `mcl_walls:cobble` = 700 (wall)
- Added stairs/slabs at ≤ cobble-equivalent prices
- Mirror change for wall price → ESCALATE via D7

### 13.4 SE-4 — Combat-log escape through sell container
**Fixed:** Container `allow_put` refuses while `smp_combat.is_tagged(name)` (soft check).
- `menu.lua:336-339` adds combat-tag check before owner check
- `/sell hand` and `/sell all` work while tagged (sell immediately, no container)
- Coordinates with S07 CB-1 (combat registers leave handler last) and S03/S04 (AH/orders grids)

### 13.5 SE-5 — Rate limit and store prune
**Fixed (local):** `/sell` and container confirm rate-limited to ~1/s via `sell_cooldown` table.
- `init.lua:113-140` cooldown implementation
- `init.lua:373,386` cooldown on `/sell hand` and `/sell all`
- `menu.lua:413-415,435` cooldown on container confirm (set only on successful sell)
- Store prune-index escalated to f02 §10 (integrator-owned `smp_store`)

### 13.6 SH-2 hand-off — Refuse shard-shop gear
**Fixed:** `items.sellable` refuses stacks with `smp:shardshop="1"` meta.
- `items.lua:376-380` checks for shard-shop meta tag
- Coordinates with S05 (shardshop stamps stacks, shards adds AFK detection)

### 13.7 Recipe-arbitrage regression test
**Added:** `dev-tests/recipe_scan.lua` (static) + in-engine path in `smp_sell.test.lua`.
Walks all craft recipes + stonecutter recipes, asserts `sell_value(output) × output_count ≤ Σ sell_value(inputs) + tolerance`. Prints every violating recipe.