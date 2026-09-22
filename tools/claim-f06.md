# AGENT BRIEFING — f06 Shards, Shard Shop, Amethyst Items

You are an AI agent picking up **f06 (Shards, Shard Shop, Amethyst
Items)** in the FriedcakeSMP / Donut SMP recreation repository at
`/Volumes/Dara/dev/coconut/`.

This is three small mods, not one. `smp_shards` is the playtime
award loop; `smp_shardshop` is the catalogue; `smp_amethyst` is the
self-destructing items and their multi-block abilities. Each has its
own concerns but they share data (the player's shard balance lives
in the player record from f01).

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
FEATURE = f06-shards
SPEC    = spec/features/f06-shards.md
MODDIRS = friedcake/mods/smp_shards
         friedcake/mods/smp_shardshop
         friedcake/mods/smp_amethyst
BRANCH  = agent/f06-shards
```

Read `spec/features/f06-shards.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f06 row, T1–T9, is your merge
  gate.
- `spec/shared/04-ui-kit.md §4.3` — the item-as-button mapping for
  the orders board's `Shard Shop` entry (amethyst shard item).
- `spec/features/f01-economy-core.md §5.1` — the player record
  fields you read and write. Your shard data lives there.
- `spec/features/f04-orders.md §4.7` — the `orders.blacklist`
  contract; `smp_amethyst` items MUST be in that blacklist. **f04
  may not be done yet**; stub the blacklist in `smp_amethyst`'s own
  registry and let the integrator merge.

## Two things to know up front

1. **Three small mods, not one.** The spec covers three concerns:

   - `smp_shards` — the playtime award loop (one shard per 600 s).
     §4.1, §6.
   - `smp_shardshop` — the catalogue UI and purchase flow. §4.2.
   - `smp_amethyst` — self-destructing items with multi-block
     abilities (Pickaxe, Axe, Shovel, Haste Potion, Sell Axe). §4.3.

   Ship them as three directories under `friedcake/mods/`, each with
   its own `mod.conf` and `init.lua`. The modpack.conf order in
   `tools/agent-flow.sh start`'s `load_mod =` list is
   `smp_shards`, `smp_shardshop`, `smp_amethyst`. The `smp_shardshop`
   and `smp_amethyst` lines depend on `smp_shards`.

2. **Two integration points, both with stubs:**

   - The orders board (`f04`) renders an amethyst shard control that
     opens the shard shop. f04's agent needs to call
     `smp_shardshop.open(player)`. **You write that signature** in
     `friedcake/mods/smp_shardshop/init.lua`; f04 imports it. Stub
     it with `TODO(f06)` if f04 is done first; otherwise define it
     and let f04 import it.

   - The amethyst sell axe (`smp_amethyst`) routes container contents
     into orders [S2]. It calls `smp_orders.best_open_order(key)`.
     Same deal: **you write the stub**, f04 implements.

   - Amethyst items are in the orders blacklist (`f04 §4.7`). Define
     the blacklist in `smp_amethyst/blacklist.lua`; f04 imports it.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f06-shards
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_shards/
   ├── mod.conf         # name=smp_shards, depends on smp_economy smp_store smp_core
   ├── init.lua         # /shards, /shardsadmin; on_step global; award message
   └── test.lua         # /smp test smp_shards
   friedcake/mods/smp_shardshop/
   ├── mod.conf         # name=smp_shardshop, depends on smp_shards smp_economy smp_core
   ├── init.lua         # .open(player); purchase flow; entry point for f04
   ├── catalogue.lua    # the §4.2 table as data, queryable at runtime
   └── formspec.lua     # shop container menu (PROPOSED layout)
   friedcake/mods/smp_amethyst/
   ├── mod.conf         # name=smp_amethyst, depends on smp_shards smp_core
   ├── init.lua         # registers items, expiry sweep
   ├── pickaxe.lua      # 9-block dig (re-entrancy guarded)
   ├── axe.lua          # tree felling (BFS, protection-checked)
   ├── shovel.lua       # dirt-family multi-dig
   ├── haste.lua        # 24h Haste II
   ├── sell_axe.lua     # container sell routing
   ├── expiry.lua       # meta `smp:expires_at`, sweep every 300s
   ├── blacklist.lua    # smp_orders.blacklist registration (TODO(f04))
   └── test.lua         # /smp test smp_amethyst
   friedcake/dev-tests/test_shards.lua        # standalone smoke tests
   friedcake/dev-tests/test_amethyst.lua      # standalone smoke tests
   ```

   Add three `load_mod = …` lines to `friedcake/modpack.conf` below
   the existing entries, in this order:

   ```
   load_mod = smp_shards
   load_mod = smp_shardshop
   load_mod = smp_amethyst
   ```

3. Implement in this order (so each step is testable):

   1. **`smp_shards` first.** §6 algorithm. Every 600 s of online
      playtime → exactly one `You earned 1 Shard for playing the
      server` chat message [F0037]. Use `core.register_on_globalstep`
      with a per-player accumulator. The award message wording is
      **OBSERVED verbatim** — including the capital `S` in `Shard`
      and the absence of a full stop. T1 tests this.
   2. **`smp_amethyst/blacklist.lua` first** — so when f04 ships
      `orders.blacklist`, the imports are wired.
   3. **`smp_amethyst/expiry.lua`** — `smp:expires_at` meta key,
      86,400 s default, swept on join and every 300 s.
   4. **`smp_amethyst/pickaxe.lua`** — 9-block dig with re-entrancy
      guard. Read `spec §4.3 Shard Pickaxe` carefully. T4 tests this.
   5. **`smp_amethyst/axe.lua`** — BFS through `tree` and `leaves`
      groups, capped at `amethyst.felling_limit` (default 512). T6.
   6. **`smp_amethyst/shovel.lua`** — pickaxe-style for dirt-family.
      Restrict to `shovely` group; configurable list.
   7. **`smp_amethyst/haste.lua`** — Haste II, 24 h, via
      `mcl_potions.give_effect_by_level("haste", player, 2, 86400)`.
   8. **`smp_amethyst/sell_axe.lua`** — punch a container to sell its
      contents via `smp_orders.best_open_order`. Stub f04 contract.
   9. **`smp_shardshop/catalogue.lua`** — the §4.2 table as data.
      Note: Netherite Spear has no Mineclonia item. **Omit it.**
      Verify the netherite armour itemstrings at runtime against
      `mcl_armor.register_set` output, never hard-code.
   10. **`smp_shardshop/formspec.lua` + `init.lua`** — container
       menu. Layout is `PROPOSED — no frame evidence`; mark every
       visual choice in `f06-shards.md §3` so the next agent who
       finds a screenshot can fix it.
   11. **Integration: `smp_shardshop.open(player)`** — entry point
       for f04's orders board. Stub if f04 not done; otherwise
       expose and import.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Money formatting | `smp_core.fmt_money(cents, style)` |
   | Quantity formatting | `smp_core.fmt_qty(n)` |
   | Player records | `smp_store.api.{get_player,upsert_player,add_shards,take_shards}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Enchantment query | `mcl_enchanting.get_enchantments(stack)` |
   | Potions | `mcl_potions.give_effect_by_level(name, obj, level, duration)` |
   | Protection check | `core.is_protected(pos, name)` |
   | Block dig | `core.node_dig(pos, digger)` |
   | Item registration | `core.register_item` / `core.register_tool` |

5. Strings MUST go through `S`. The verbatim strings f06 owns:

   - `You earned 1 Shard for playing the server` (chat, OBSERVED) —
     `smp_shards`
   - `Shard Shop` (tooltip line 1) — `smp_shardshop` / `smp_amethyst`
   - `Click to view` (tooltip line 2) — `smp_shardshop` / `smp_amethyst`

   Reuse from elsewhere (already in `shared/08-ui-strings.md`):

   - `Inventory`, `Cancel`, `Back`, `Search`, `Confirm`

   The shard shop layout strings (`PROPOSED — no frame evidence`)
   live in `f06-shards.md §3` until first screenshot.

6. Money is integer cents. Shards are integer count.

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: a multi-block dig must use a per-player re-entrancy
   guard (`smp_amethyst._digging[player_name] = true`) so the tool's
   own on_dig callback doesn't recurse into itself.

8. **The Haste potion must survive logout.** Spec §4.3:
   `mcl_potions.give_effect_by_level(...)` may not persist across
   disconnect. If it doesn't, store expiry in player meta
   (`smp:haste_until`) and re-apply on `register_on_joinplayer`.

9. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_shards.lua` for the award loop and
   `friedcake/dev-tests/test_amethyst.lua` for the dig/fell/haste
   paths. Also a `friedcake/mods/smp_shards/test.lua` and
   `friedcake/mods/smp_amethyst/test.lua` for the in-game paths.

10. Commit on the branch, never on main. Format:

    ```
    f06: <imperative summary>

    <body>
    ```

    Examples:

    - `f06: shards on_step accumulator with verbatim award message`
    - `f06: amethyst item registration with smp:expires_at meta`
    - `f06: Shard Pickaxe 9-block dig with re-entrancy guard`
    - `f06: shard shop catalogue and formspec (PROPOSED layout)`

11. When T1–T9 pass, push:

    ```
    git push origin agent/f06-shards
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f06-shards`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- Every `PROPOSED` decision you made on the shard shop layout, with
  the reasoning. The next agent who finds a screenshot will use this.
- The exact signature of `smp_shardshop.open(player)` — f04's agent
  is depending on this.
- The blacklist contract in `smp_amethyst/blacklist.lua` — f04's
  agent imports this.
- The sell axe's contract: how it calls `smp_orders.best_open_order`.
- Any unresolved V-NN questions you made a `PROPOSED` decision on.

## When you get stuck

- The shard shop layout is silent: pick something that follows the
  shared UI kit and mark it `PROPOSED`. Don't get stuck on the
  visual.
- A netherite armour itemstring doesn't exist: query
  `mcl_armor.registered_armor` (or whatever the actual API is) at
  load time; if missing, drop that offer from the catalogue and log
  a warning.
- The Haste potion doesn't survive logout: implement the
  `smp:haste_until` re-apply path. T3 doesn't cover this but it's
  documented.
- Multi-block dig recurses into itself: the re-entrancy guard is
  mandatory. Without it the server infinite-loops.
