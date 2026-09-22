# AGENT BRIEFING — f05 Quick Buy

You are an AI agent picking up **f05 (Quick Buy / `/shop`)** in the
FriedcakeSMP / Donut SMP recreation repository at
`/Volumes/Dara/dev/coconut/`.

This feature has **zero frames** of evidence. It exists entirely in
the wiki and the June update notes. Your job is to ship a working
Quick Buy that follows the spec's `PROPOSED` layout, marked clearly
as unverified, and let the spec evolve when real screenshots show up.

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
FEATURE = f05-quickbuy
SPEC    = spec/features/f05-quickbuy.md
MODDIR  = friedcake/mods/smp_quickbuy
BRANCH  = agent/f05-quickbuy
```

Read `spec/features/f05-quickbuy.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f05 row, T1–T7, is your merge
  gate.
- `spec/shared/04-ui-kit.md §4.3, §4.7` — item-as-button vocabulary;
  the `Review Order` pattern for the 3× guard's re-confirm screen.
- `spec/features/f03-auction.md §6.2` — the `smp_ah.buy()` and
  `smp_ah.cheapest_for()` signatures you depend on. **You write the
  stub for `cheapest_for`; f03's agent writes the implementation.**
- `spec/features/f10-combat.md §4` (skim) — `smp_combat.is_tagged()`
  blocks Quick Buy [S7]. Stub if f10 isn't done yet.
- `spec/features/f14-stats.md §4` (skim) — `smp_stats.add(player,
  "money_spent_on_shop", cost)` updates the stat [S23]. Stub if f14
  isn't done yet.

## Three things to know up front

1. **f03, f10, f14 may all not be done yet.** Your algorithm calls:

   - `smp_ah.cheapest_for(key, ench, qty)` (f03)
   - `smp_ah.buy(player, id, version)` (f03)
   - `smp_combat.is_tagged(player)` (f10)
   - `smp_stats.add(player, "money_spent_on_shop", cost)` (f14)

   Stub each under `friedcake/mods/smp_quickbuy/bridges.lua` (or
   split into `au_bridge.lua`, `combat_bridge.lua`, `stats_bridge.lua`)
   with `TODO(fNN)` markers. Don't block on any of them. The
   integrator wires them together when those branches land.

   The contract shapes you write matter — they're what the other
   agents' code must match:

   ```lua
   -- f03 stub:
   smp_quickbuy.au.cheapest_for(key, ench, qty)
     -> nil | { listings = { {id, version, count, unit_price, ...}, ... },
                cost_cents = N }
   -- nil means "not enough listings"; the second value is the total cost.

   -- f03 stub:
   smp_quickbuy.au.buy(player, id, version)
     -> nil | { stack = ItemStack }

   -- f10 stub:
   smp_quickbuy.combat.is_tagged(player) -> bool

   -- f14 stub:
   smp_quickbuy.stats.add(player, key, value) -> nil
   ```

2. **The 3× price guard is the central mechanic.** §4.3 / §6 of the
   spec:

   > A purchase may spend up to three times the displayed live price
   > so that it still completes when the cheapest listing changes;
   > beyond that threshold a warning screen requires re-confirmation
   > [S7].

   Reproduce this exactly. Don't relax the guard to 2× because it
   "feels nicer" — the wiki says 3, T3 tests 3. The warning screen
   follows the `Review Order` pattern (`shared/04-ui-kit.md §4.7`)
   and gives the player a chance to back out.

3. **No screenshots, so everything visual is `PROPOSED`.** The spec
   says this explicitly. Your container-menu layout, entry tooltips,
   "Add entry" affordance — all of it is your best guess. Mark every
   visual decision in your feature file's §3 with `PROPOSED — no
   frame evidence`. When the first screenshot lands, swap the
   `PROPOSED` strings for whatever the real server shows.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f05-quickbuy
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_quickbuy/
   ├── mod.conf          # name=smp_quickbuy, depends on smp_economy smp_store smp_core smp_ah
   ├── init.lua          # /shop; event handlers; menu dispatcher
   ├── entries.lua       # CRUD over a player's quickbuy entry list
   ├── price.lua         # live price lookup + 3× guard logic
   ├── formspec.lua      # every menu formspec, marked PROPOSED
   ├── bridges.lua       # f03 / f10 / f14 stubs (or split per agent)
   └── test.lua          # /smp test smp_quickbuy
   friedcake/dev-tests/test_quickbuy.lua   # standalone smoke tests
   ```

   Add `load_mod = smp_quickbuy` to `friedcake/modpack.conf` below
   the existing entries.

3. Implement in this order (so each step is testable):

   1. **Bridge stubs** (`bridges.lua`). Stub f03 / f10 / f14 with the
      signatures above, returning safe defaults (`nil`, `false`, `nil`).
      These are the contracts other agents will implement against.
   2. **Entries** (`entries.lua`). CRUD over the player's quickbuy
      list. The data shape is in §5 — `key`, `ench`, `qty`. Persist
      under the player's `quickbuy` field in `smp_store.api`.
      Capacity: `cfg.quickbuy.max_entries` (default 45).
   3. **Price lookup** (`price.lua`). `cheapest_for(key, ench, qty)`
      wraps `smp_quickbuy.au.cheapest_for` and returns a stable
      `(price_cents, version)` pair. NEVER cache across redraws —
      the guard compares against the displayed price, and a stale
      price defeats the guard.
   4. **Guard** (`price.lua`). `within_guard(shown, current)` returns
      `true` if `current <= shown * cfg.quickbuy.price_guard`. Default
      guard is 3.0.
   5. **Formspecs** (`formspec.lua`). Mark everything visual as
      `PROPOSED`. The menu grammar is from `shared/04-ui-kit.md §4.1`,
      the entry tooltip shape is from `04-ui-kit.md §4.4`, the
      re-confirm screen follows §4.7 (`Review Order`).
   6. **Commands** (`init.lua`): `/shop`. Tab-completion: `PROPOSED`.
   7. **Buy path** (`init.lua`). §6: refuse combat, look up cheapest
      listings, check guard, refuse if over budget (prompt for
      re-confirm), debit + absorb + ledger entry + stats tick.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Money formatting | `smp_core.fmt_money(cents, style)` |
   | Quantity formatting | `smp_core.fmt_qty(n)` |
   | Amount parsing | `smp_core.parse_amount(text)` |
   | Player records | `smp_store.api.{get_player,upsert_player}` |
   | Money mutation | `smp_store.api.{add_money,take_money}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Menu sessions | `smp_core.{open_session,get_session,close_session}` |
   | Live price | `smp_quickbuy.au.cheapest_for(...)` (the f03 bridge) |

5. Strings MUST go through `S`. The Quick Buy panel and entry tooltip
   strings are `PROPOSED — no frame evidence` and go in your feature
   file §3, not in `08-ui-strings.md`. The integrator mirrors later.

   The verbatim strings Quick Buy owns:

   - `Quick Buy (Page @1)` — title
   - `Add entry` — affordance
   - `Your entries` — affordance
   - `Click to buy` — entry tooltip
   - `@1` / `@2` / `@3` — entry tooltip lines (display name, price,
     itemstring)

   Reuse from elsewhere:

   - `Cancel!` (with the exclamation mark, per `shared §0.5`)
   - `Confirm` and the re-confirm screen's affordance text

6. Money is integer cents. Storage is cents.

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: between computing the cost and debiting the buyer
   there must be no `core.after`, no HTTP, no `wait_for`.

8. **Re-validate every auction listing you touch.** Even within the
   guard, call `smp_ah.buy(player, id, version)` for each listing
   rather than mass-debiting. Each call does its own version check;
   if one listing was bought out from under you, you get a nil back
   and the partial purchase still happens for the rest. T7 tests this.

9. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_quickbuy.lua` for the price lookup and
   guard, and `friedcake/mods/smp_quickbuy/test.lua` for the buy path
   (with the bridges stubbed to deterministic values).

10. Commit on the branch, never on main. Format:

    ```
    f05: <imperative summary>

    <body>
    ```

    Examples:

    - `f05: bridge stubs for f03 / f10 / f14 with TODO markers`
    - `f05: entry CRUD under player.quickbuy`
    - `f05: 3x price guard with re-confirm screen`
    - `f05: buy path absorbing cheapest listings with re-validation`

11. When T1–T7 pass, push:

    ```
    git push origin agent/f05-quickbuy
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f05-quickbuy`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- Every `PROPOSED` decision you made on the visual layout, with the
  reasoning. The next agent who finds a screenshot will use this.
- Any unresolved V-NN questions you made a `PROPOSED` decision on.
- Any `## Proposed shared changes` block (the integrator merges).
- The exact signature of every bridge — f03, f10, f14 agents depend
  on these.

## When you get stuck

- The spec is silent on layout: pick something that follows the
  shared UI kit and mark it `PROPOSED`. Don't get stuck on the
  visual.
- f03 / f10 / f14 haven't shipped their bridge function: stub with
  `TODO(fNN)`. Don't block.
- Tests fail in a way you can't explain: ask the integrator. Do not
  loosen the assertions to make them pass.
- The 3× guard feels wrong: it isn't. The wiki is explicit. Trust
  the spec.
