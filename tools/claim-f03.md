# AGENT BRIEFING — f03 Auction House

You are an AI agent picking up **f03 (Auction House)** in the
FriedcakeSMP / Donut SMP recreation repository at
`/Volumes/Dara/dev/coconut/`.

This is the most ambitious feature in P3. It has 28 frames of interface
evidence, a documented external API, and integrates with f04 (orders).
Read the rules, read the spec, then plan, then implement.

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
FEATURE = f03-auction
SPEC    = spec/features/f03-auction.md
MODDIR  = friedcake/mods/smp_ah
BRANCH  = agent/f03-auction
```

Read `spec/features/f03-auction.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — your merge gate is the f03 row, T1–T10.
- `spec/shared/04-ui-kit.md §4.3` — the item-as-button mapping for
  Search (oak sign → `mcl_signs:wall_sign`), Filter (hopper →
  `mcl_hoppers:hopper`), Your Items (chest → `mcl_chests:chest`),
  Confirm (lime pane → verify the itemstring against Mineclonia).
- `spec/shared/00-conventions.md §0.5.1` — drop the `15 component(s)`
  Java line; keep everything else verbatim.
- `spec/features/f04-orders.md` — read for context; you'll implement
  `smp_orders.best_open_order()` integration in T7 but f04 itself is
  another agent's job. Stub the call if f04 doesn't exist yet, with a
  clear `TODO(f04)` in your code.

## Heads-up

Two things the spec doesn't say but you'll need:

1. **`smp_items` is currently a stub.** The M1/M2 key functions it
   defines (`smp_items.key(stack, level)`) are referenced in §5 and
   §6 of the spec. Two options:

   a. **Implement the M1/M2 keying yourself under `smp_ah/keys.lua`.**
      The spec section `shared/02-architecture.md §2.5` is the
      reference. This is the smallest amount of `smp_items` you need
      to ship a working auction house.

   b. **Wait for the `smp_items` agent.** If you don't want to do the
      keying work, propose what you need under
      `## Proposed shared changes` at the bottom of `f03-auction.md`
      and stop. The integrator will route it.

   Pick (a) unless explicitly told otherwise. It's a couple hundred
   lines and it's clearly within f03's scope — the spec calls out
   M1/M2 in §5.

2. **Glass pane itemstrings must be verified at runtime.** The
   spec calls this out at `shared/04-ui-kit.md §4.3`: the grey and
   lime pane itemstrings are the least certain mapping in the table.
   Don't ship hard-coded strings; query `core.registered_items` at
   load time and pick the matching name (or `mcl_core:glass_pane`
   with a `:colorize` overlay if Mineclonia doesn't ship stained
   variants).

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f03-auction
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_ah/
   ├── mod.conf         # name=smp_ah, depends on smp_economy smp_store smp_core
   ├── init.lua         # /ah, /auction, /auctionhouse, /ah sell; event handlers
   ├── keys.lua         # M1/M2 keying (see Heads-up #1)
   ├── listings.lua     # in-memory listing store + indexes
   ├── formspec.lua     # every menu formspec, verbatim strings
   └── test.lua         # /smp test smp_ah
   friedcake/dev-tests/test_ah.lua   # standalone smoke tests
   ```

   Add `load_mod = smp_ah` to `friedcake/mods/modpack.conf` below the
   existing entries.

3. Implement in this order (so each step is testable):

   1. **Keys** (`keys.lua`). M1 = `name + ench + meta_hash` with zero
      wear/no name/no contents. M2 = full key. Two functions:
      `smp_items.key(stack, level)` returning the canonical string,
      `smp_items.equals(k1, k2, level)` for level-bounded equality.
      Add `friedcake/dev-tests/test_ah_keys.lua`.
   2. **Listings** (`listings.lua`). CRUD over an in-memory table,
      with three indexes: by id, by seller, by M1 key sorted on unit
      price. Persist by serializing the table to `smp_store.api`
      (mod storage or SQLite, whichever the operator picked). The
      schema in §5 is the source.
   3. **Formspecs** (`formspec.lua`). Build each menu form, in this
      order, with the observed strings:
      - `Auction (Page N)` (board)
      - `Auction > Your Items`
      - `Insert Item`
      - `Edit Sign Message` (price prompt)
      - `Confirm Listing`
      - `Search Auction`
      Use `shared/04-ui-kit.md §4.9` for the formspec constructions.
      Use `item_image_button[]` + `tooltip[]` for controls.
   4. **Commands** (`init.lua`): `/ah`, `/auction`, `/auctionhouse`,
      `/ah sell`. Tab-completion of search terms is `PROPOSED` —
      defer.
   5. **Purchase** (in `init.lua` or a separate `purchase.lua`).
      Re-validate version; debit buyer; credit seller; deliver stack;
      log transaction; ledger entry. The exact race-loss message is
      `This item was already bought` [F0037] — copy verbatim.
   6. **Routing stub** for f04. `smp_orders.best_open_order(key)`
      returns `nil` for now; mark with `TODO(f04)`.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Money formatting | `smp_core.fmt_money(cents, style)` |
   | Amount parsing | `smp_core.parse_amount(text)` |
   | Player records | `smp_store.api.{get_player,ensure_player,upsert_player}` |
   | Money mutation | `smp_store.api.{add_money,take_money,set_money}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Menu sessions | `smp_core.{open_session,get_session,close_session}` |
   | Item slots | `core.registered_items[itemstring]` |

5. Strings MUST go through `S`. The verbatim catalogue is in
   `spec/shared/08-ui-strings.md`. The auction house owns these new
   strings (and they go in your feature file §3, not 08 — the
   integrator mirrors later):

   - `Auction (Page @1)`
   - `Auction > Your Items`
   - `Insert Item`
   - `Edit Sign Message`
   - `Type price`
   - `Confirm Listing`
   - `Search Auction`
   - `Search`, `Filter`, `Your Items`, `List`, `Confirm`
   - `Lowest Price`, `Highest Price`, `Recently Listed`
   - `You're going to sell this item for $@1`
   - `You bought @1 @2 for $ @3`
   - `This item was already bought`

   All from `08-ui-strings.md §8.1, §8.2, §8.5`. The `15 component(s)`
   line is the **one** string you drop — see `00-conventions.md §0.5.1`.

6. Money is integer cents. No float. Storage is cents.

7. No yields between validate and mutate. See
   `spec/shared/02-architecture.md §2.3`.

8. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_ah.lua` for your keys/listings and
   `friedcake/mods/smp_ah/test.lua` for the in-game paths.

9. Commit on the branch, never on main. Format:

   ```
   f03: <imperative summary>

   <body>
   ```

   Examples:

   - `f03: M1/M2 keying for stack identity`
   - `f03: in-memory listings with seller/M1 indexes`
   - `f03: Auction (Page N) container menu and three controls`
   - `f03: purchase path with version re-validation`

10. When the feature is complete and T1–T10 in
    `spec/plan/acceptance-tests.md` pass, push:

    ```
    git push origin agent/f03-auction
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f03-auction`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- Any unresolved V-NN questions you made a `PROPOSED` decision on.
- Any `## Proposed shared changes` block (the integrator merges).
- Anything f04 needs to know about how you call
  `smp_orders.best_open_order(key)` — that's a contract they're
  depending on.

## When you get stuck

- The spec contradicts itself: pick the OBSERVED reading and note the
  conflict in your feature file §10.
- You need a shared helper that doesn't exist: write a
  `## Proposed shared changes` block at the bottom of your feature
  file listing exactly what you need. Stop there.
- Tests fail in a way you can't explain: ask the integrator. Do not
  loosen the assertions to make them pass.
- The Mineclonia pane itemstring doesn't exist: query
  `core.registered_items` and `minetest.registered_aliases` for
  variants; if there's no match, fall back to `mcl_core:glass_pane`
  with `colorize = "#bfbfbf"` (grey) and `"#7fff00"` (lime).
