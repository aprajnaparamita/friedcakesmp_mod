# AGENT BRIEFING — f04 Orders

You are an AI agent picking up **f04 (Orders)** in the FriedcakeSMP /
Donut SMP recreation repository at `/Volumes/Dara/dev/coconut/`.

This is the best-evidenced feature in the project (47 frames, the entire
creation wizard and delivery flow were recorded). It is also one of the
most integrated: orders absorb from auction listings (f03), from `/sell`
(f02), from the amethyst sell axe (f06), and supply items to players
through a virtual-count ledger.

## Setup

```
cd /Volumes/Dara/dev/coconut
git status                 # must be on main, clean
cat AGENTS.md              # the rules (read first)
cat CONTRIBUTING.md        # the workflow (read second)
cat tools/claim.md         # the generic claim briefing
```

Engine source-of-truth (DO NOT trust the stale SHA in the spec):

- Mineclonia: `~/dev/mineclonia-git`
- Luanti:     `~/dev/luanti`

## Your feature

```
FEATURE = f04-orders
SPEC    = spec/features/f04-orders.md
MODDIR  = friedcake/mods/smp_orders
BRANCH  = agent/f04-orders
```

Read `spec/features/f04-orders.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f04 row, T1–T14, is your merge
  gate.
- `spec/shared/04-ui-kit.md §4.3, §4.6, §4.7` — the item-as-button
  vocabulary and the four-step wizard pattern.
- `spec/shared/04-ui-kit.md §4.8` — `Delivering...` action bar and the
  exact `You delivered 1 X and received $Y` chat message.
- `spec/features/f03-auction.md §6` — the `smp_orders.best_open_order`
  contract that f03 depends on, AND the matching
  `smp_ah.listings_at_or_below(key, unit_price)` your algorithm in
  §6.1 calls. **You write that signature; f03's agent writes the
  implementation.**
- `spec/features/f02-sell.md §4` (skim) — `/sell` routes items into
  orders [S2]. You'll need to wire a similar hook from `/sell all` if
  f02 ships first.
- `spec/features/f06-shards.md §4` (skim) — amethyst sell axe routes
  into orders [S9]; orders blacklist amethyst items.

## Two things to know up front

1. **f03 may not be done yet.** Your algorithm calls
   `smp_ah.listings_at_or_below(key, unit_price)`. If f03's agent
   hasn't shipped that function, **do not block.** Stub it in
   `smp_ah/listings.lua` (under `smp_orders/au_bridge.lua` if you want
   strict ownership) returning `{}` and add a `TODO(f03)` comment.
   The integrator wires them together when both branches land.

2. **Plural vs singular is intentional.** Two things to reproduce:

   - **Order tooltip / display name: PLURAL.** "Netherite Helmets"
     even when the player is looking at one. `[F0164]`.
   - **Delivery chat message: SINGULAR.** "You delivered 1 Totem of
     Undying and received $30K". `[F0227]`. Note: the form
     `You're delivering 1 Totems of Undying` on `Confirm Delivery`
     [F0219] is plural — the reference server is internally
     inconsistent. Reproduce both as observed.

   Don't unify them. The acceptance tests T3 specifically calls this
   out.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f04-orders
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_orders/
   ├── mod.conf         # name=smp_orders, depends on smp_economy smp_store smp_core smp_ah
   ├── init.lua         # /orders, /order; event handlers; wizard dispatcher
   ├── orders.lua       # CRUD over open orders; in-memory indexes
   ├── escrow.lua       # escrow deposit / payout / refund; ledger entries
   ├── delivery.lua     # Orders -> Deliver Items / Confirm Delivery
   ├── routing.lua      # sweep cheaper auction listings after creation
   ├── formspec.lua     # every menu formspec, verbatim strings
   └── test.lua         # /smp test smp_orders
   friedcake/dev-tests/test_orders.lua   # standalone smoke tests
   friedcake/mods/smp_orders/au_bridge.lua   # stub for f03's listings_at_or_below
   ```

   Add `load_mod = smp_orders` to `friedcake/mods/modpack.conf` below the
   existing entries.

3. Implement in this order (so each step is testable):

   1. **Orders data layer** (`orders.lua`). CRUD over an in-memory
      table indexed by id, by buyer, and by M1 key. Persist via
      `smp_store.api`. The schema in §5 is the source.
   2. **Escrow** (`escrow.lua`). Three operations: `deposit(buyer,
      total)` (called at create), `payout(buyer, supplier, cents)`
      (called at delivery), `refund(buyer, cents)` (called at cancel
      or expire). All three write ledger entries with reason codes
      `order_escrow` / `order_payout` / `order_refund` per
      `shared/02-architecture.md §2.6` R3.
   3. **Routing stub** (`au_bridge.lua`). Define
      `smp_orders.au.listings_at_or_below(key, unit_price)` returning
      `{}` with `TODO(f03)`. The signature must match what f03's
      agent writes; if it disagrees, file a `## Proposed shared
      changes` block in `f04-orders.md §10` and stop.
   4. **Formspecs** (`formspec.lua`). Build each menu, in order, with
      the observed strings:
      - `Orders (Page N)` (board)
      - `Orders -> Your Orders`
      - `Choose Item`, `Choose Item (@1 results)` (note: results is
        plural even for 1)
      - `How many?`
      - `Price per item?`
      - `Review Order`
      - `Orders -> Deliver Items`
      - `Orders -> Confirm Delivery`

      Use `shared/04-ui-kit.md §4.9` for formspec constructions.
      Item-as-button controls: book, hopper, chest, amethyst shard,
      lime pane — match `shared/04-ui-kit.md §4.3`.

   5. **Wizard dispatcher** (`init.lua`). Server-side session holding
      `{item, amount, price, step}`. `Change Item` / `Change Amount` /
      `Change Price` jumps to that step alone — the session, not the
      client, holds the state. T5 tests this.
   6. **Commands** (`init.lua`): `/orders`, `/order [search]`.
   7. **Creation** (`init.lua` + `routing.lua`). §6.1. On create:
      deposit escrow, sweep cheaper auction listings, ledger entry.
   8. **Delivery** (`delivery.lua`). §6.2. On deliver: re-validate
      version, refuse self-delivery, accept M1 matches up to remaining
      qty, payout from escrow, ledger entry. The chat message is
      plural-name in the form, singular-name in chat — see Heads-up
      #2.
   9. **Routing in** from `/sell`, spawner "Sell all", and amethyst
      sell axe. Each is a one-call interface: if f02 / f06 / f07
      aren't done yet, stub the hooks with `TODO(f02)` / `TODO(f06)`
      / `TODO(f07)`.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Money formatting | `smp_core.fmt_money(cents, style)` |
   | Quantity formatting | `smp_core.fmt_qty(n)` (lower-case suffixes) |
   | Amount parsing | `smp_core.parse_amount(text)` |
   | Player records | `smp_store.api.{get_player,ensure_player,upsert_player}` |
   | Money mutation | `smp_store.api.{add_money,take_money,set_money}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Menu sessions | `smp_core.{open_session,get_session,close_session}` |
   | Enchantment query | `mcl_enchanting.get_enchantments(stack)` |
   | Action bar | `mcl_title.set(player, "actionbar", {text = S("Delivering...")})` |

5. Strings MUST go through `S`. The verbatim catalogue is in
   `spec/shared/08-ui-strings.md`. Orders owns these new strings
   (and they go in your feature file §3, not 08 — the integrator
   mirrors later):

   - `Orders (Page @1)`
   - `Orders -> Your Orders`
   - `Orders -> Deliver Items`
   - `Orders -> Confirm Delivery`
   - `Choose Item`, `Choose Item (@1 results)`
   - `How many?`
   - `Price per item?`
   - `Review Order`
   - `Cancel!` (note the exclamation mark)
   - `Change Item`, `Change Amount`, `Change Price`
   - `Create Order`
   - `Orders`, `Filter`, `Your Orders`, `Shard Shop`
   - `Most Per Item`, `Most Paid`, `Recently Listed`
   - `Click to deliver items`, `Click to deliver items ($@1)`
   - `Confirm`
   - `@1 requested`
   - `You're delivering @1 @2` (plural, even for qty=1)
   - `Delivering...` (action bar)
   - `You delivered @1 @2 and received $@3` (chat, singular)

   All from `08-ui-strings.md §8.1, §8.2, §8.5, §8.6, §8.7`. The
   `15 component(s)` / `20 component(s)` / `14 component(s)` lines
   are dropped per `00-conventions.md §0.5.1`.

6. **Enchantment line is part of order identity.** M1 matching in
   `smp_items` (or `smp_ah/keys.lua` if you implement the keying)
   must include the enchantment set. The order for
   `Protection IV / Respiration III / Aqua Affinity / Unbreaking III
   / Mending` cannot be filled by a plain netherite helmet. T8
   tests this.

   Render the enchantment line in tooltips in registration order,
   Roman numerals (level 4 = IV, etc.), level 1 omitted (`Aqua
   Affinity`, `Mending`). Use `mcl_enchanting.get_enchantments` to
   get the actual IDs and convert with the Roman helper.

7. Money is integer cents. Storage is cents. Escrow is the integer
   `unit_price × (qty − delivered)`.

8. **Virtual counts, not stacks.** Orders track `qty / delivered /
   collected` as integers; the observed `753k/1.3m Delivered` [F0160]
   exceeds any container. When a buyer collects, convert virtual
   count → ItemStacks at collection time, not before. T12 tests
   this.

9. **No yields between validate and mutate** (`shared §2.3`).

10. After every meaningful change, run:

    ```
    tools/agent-flow.sh test
    ```

    These cover `smp_core`, `smp_store`, `smp_economy`. Add
    `friedcake/dev-tests/test_orders.lua` for the data layer and
    `friedcake/mods/smp_orders/test.lua` for the in-game paths.

11. Commit on the branch, never on main. Format:

    ```
    f04: <imperative summary>

    <body>
    ```

    Examples:

    - `f04: orders data layer with id/buyer/key indexes`
    - `f04: escrow deposit, payout, refund with ledger entries`
    - `f04: Orders (Page N) board with three controls`
    - `f04: four-step creation wizard with change-jumps`
    - `f04: delivery path with M1 matching and self-delivery refusal`
    - `f04: routing sweep — absorb cheaper auction listings on create`

12. When T1–T14 pass, push:

    ```
    git push origin agent/f04-orders
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f04-orders`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- Any unresolved V-NN questions you made a `PROPOSED` decision on.
- Any `## Proposed shared changes` block (the integrator merges).
- The exact signature of `smp_orders.au.listings_at_or_below(key,
  unit_price)` — f03's agent is depending on this.
- Whether your delivery path uses a detached inventory (recommended)
  or a different approach; T13 hinges on this.

## When you get stuck

- The spec contradicts itself: pick the OBSERVED reading and note the
  conflict in your feature file §10.
- f03 hasn't shipped `listings_at_or_below` yet: stub with
  `TODO(f03)` returning `{}`. Don't block.
- Tests fail in a way you can't explain: ask the integrator. Do not
  loosen the assertions to make them pass.
- The M1 key function is in `smp_ah/keys.lua` (f03's stub) and you
  need it: import it explicitly. Don't roll your own M1 — the
  contract is shared.
