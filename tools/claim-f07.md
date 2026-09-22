# AGENT BRIEFING — f07 Virtual Spawners

You are an AI agent picking up **f07 (Virtual Spawners)** in the
FriedcakeSMP / Donut SMP recreation repository at
`/Volumes/Dara/dev/coconut/`.

This is the largest body of unverified specification in the project.
**Zero frames** of evidence; the production model, the menu, and most
of the tuning constants are `PROPOSED`. Read this briefing end-to-end
before opening the spec — there are several non-obvious rules.

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
FEATURE = f07-spawners
SPEC    = spec/features/f07-spawners.md
MODDIR  = friedcake/mods/smp_spawners
BRANCH  = agent/f07-spawners
```

Read `spec/features/f07-spawners.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f07 row, T1–T10, is your merge
  gate. T4 ("zero entities created") is the performance contract.
- `spec/shared/04-ui-kit.md §4.3` — item-as-button vocabulary. You
  register a `smp_spawners:spawner_item` and a `smp_spawners:spawner`
  node.
- `spec/shared/03-mineclonia-api.md §3.1` — `mcl_experience.add_xp`,
  `mcl_enchanting.has_enchantment(tool, "silk_touch")`. Use these;
  don't roll your own.
- `spec/features/f02-sell.md §4.4` — sell-all routing into f04.
  f07's `Sell all` button calls into f02's `smp_sell.routing`. **f02
  is in flight on `agent/f02-sell`; check whether it's landed before
  you depend on it.** If not, stub with `TODO(f02)`.

## Three things to know up front

1. **Zero entities. Zero ABMs.** Goal G1 in `spec/shared/01-overview.md`.
   This is the cardinal rule of f07:

   - The spawner is a **node** (`smp_spawners:spawner`) with metadata
     and a node timer. Not an entity. Not an ABM.
   - Right-click reads metadata and converts elapsed time to virtual
     kills. No mob ever spawns, even briefly.
   - `on_blast` does nothing. `on_punch` does nothing. The spawner is
     inert to the vanilla mob-spawner behaviour.
   - T4 fails if any entity is created at any stack size. Verify in
     tests by counting `core.get_objects_inside_radius(pos, 16)` before
     and after a 60-second accrual window.

2. **The production curve is published only for skeletons.** §4.3:

   ```
   kills_per_min(n) = C × (1 − (1 − r / C)^n)
   ```

   `r = 6` kills/min for one spawner. `C = 1505.35` for skeletons is
   the only published asymptote. **All other types use `PROPOSED`
   defaults**, configurable per type. Mark every non-skeleton `C`
   value as `PROPOSED — uncalibrated` in `f07-spawners.md §4.3` and
   in the configuration file.

3. **Three accrual modes, default `active_only`.** §4.5. When a map
   block becomes active again, the node timer callback may report
   elapsed time covering the inactive period — clamp each tick to
   twice the timer interval (default 60 s × 2 = 120 s) so a 30-day
   log-off doesn't produce a 30-day payout.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f07-spawners
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_spawners/
   ├── mod.conf         # name=smp_spawners, depends on smp_economy smp_store smp_core
   ├── init.lua         # /spawner; node timer; formspec dispatcher
   ├── node.lua         # spawner node registration (NOT mcl_mobspawners)
   ├── item.lua         # spawner item registration (meta.type)
   ├── accrue.lua       # §6 algorithm — virtual kills, fractional store
   ├── types.lua        # the §4.2 type table as data; C values marked PROPOSED
   ├── formspec.lua     # menu (PROPOSED layout — §3 shows the proposal)
   ├── interaction.lua  # stacking, breaking, sell-all, collect-xp
   ├── routing.lua      # sells stored output via f02; TODO(f02) if not done
   ├── performance.lua  # on_blast, on_punch no-op; hopper extraction
   └── test.lua         # /smp test smp_spawners
   friedcake/dev-tests/test_spawners.lua    # standalone smoke tests
   ```

   Add `load_mod = smp_spawners` to `friedcake/modpack.conf` below
   the existing entries.

3. Implement in this order (so each step is testable):

   1. **Types** (`types.lua`). The §4.2 table as Lua data. Mark every
      `C` value other than `skeleton` as `PROPOSED — uncalibrated`. The
      blaze rods/powder conflict goes in your feature file §10, not in
      `types.lua` — pick one (the spec leans rods because [S10] is the
      more recent source) and document the choice.
   2. **Item** (`item.lua`). `smp_spawners:spawner_item` with meta key
      `type` (skeleton, blaze, …).
   3. **Node** (`node.lua`). `smp_spawners:spawner` with metadata
      schema in §5, infotext `<Type> Spawner x<n>`, a node timer at
      `cfg.spawners.timer_interval` (default 60 s). Register the
      `on_timer` to call `accrue.lua`'s function. Register
      `on_construct` to set `smp:last_update = os.time()`.
   4. **Accrue** (`accrue.lua`). §6 algorithm. Virtual store is a
      fractional table; clamp each tick; pause at capacity. The
      accrual mode is configurable (`active_only` / `always` / `capped`).
   5. **Interaction** (`interaction.lua`). Stacking (sneak + right-click
      on same-type spawner), breaking (Silk Touch required, normal dig
      removes one, sneaking removes up to `cfg.spawners.sneak_break_max`
      64). Use `mcl_enchanting.has_enchantment(tool, "silk_touch")`.
   6. **Formspecs** (`formspec.lua`). The §3 proposed layout. Mark
      every visual decision `PROPOSED — no frame evidence`.
   7. **Routing** (`routing.lua`). Sell-all button calls f02's
      `smp_sell.routing.sell(player, stacks)`. Stub with `TODO(f02)`
      if f02 isn't done.
   8. **Performance** (`performance.lua`). `on_blast` does nothing;
      `on_punch` does nothing; hopper extraction default off; piston
      pushing default refused.
   9. **Commands** (`init.lua`). `/spawner give <player> <type>
      [count]` with the `smp_admin` privilege.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Money formatting | `smp_core.fmt_money(cents, style)` |
   | Quantity formatting | `smp_core.fmt_qty(n)` |
   | Player records | `smp_store.api.{get_player,upsert_player}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Item registration | `core.register_node`, `core.register_craftitem` |
   | Silk Touch check | `mcl_enchanting.has_enchantment(tool, "silk_touch")` |
   | XP grant | `mcl_experience.add_xp(player, xp)` |
   | Protection check | `core.is_protected(pos, name)` |
   | Sell routing | `smp_sell.routing.sell(...)` (the f02 bridge) |

5. Strings MUST go through `S`. The spawner menu and infotext strings
   are `PROPOSED — no frame evidence` and live in your feature file
   §3, not in `08-ui-strings.md`. The integrator mirrors later.

   The §3 proposal gives you a starting point:

   - `Skeleton Spawner x128` (infotext; other types substitute the name)
   - `Stored <count> / <capacity>`
   - `XP <count> / <capacity>`
   - `<Prev`, `Page N/M`, `Next>`
   - `Sell all`
   - `Collect XP` (or `[XP]` per the §3 proposal)
   - `Inventory` (label, reused from `shared/08-ui-strings.md`)

6. Money is integer cents. Storage counts are integers but the accrual
   algorithm uses floats for fractional kills; the integer boundary is
   the moment a virtual count crosses 1.0 (then one ItemStack appears
   in the menu).

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: between the version-counter check and the storage
   decrement in any collect operation, no `core.after` and no HTTP.

8. **No entities. None. Verify with T4.** Add to
   `friedcake/dev-tests/test_spawners.lua` a check that
   `core.get_objects_inside_radius(pos, 16)` is empty after 60 seconds
   of accrual simulation. If it isn't, you've spawned something —
   find and remove the leak.

9. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`, and (after f02
   lands) `smp_sell`. Add `friedcake/dev-tests/test_spawners.lua`
   covering T1, T2, T3, T4, T5, T6 from the spec — the production
   curve, monotonicity, asymptote, no-entities, capacity-pause,
   double-collect safety.

10. Commit on the branch, never on main. Format:

    ```
    f07: <imperative summary>

    <body>
    ```

    Examples:

    - `f07: spawner node and item with metadata schema`
    - `f07: accrue.lua with the published C × (1 − (1 − r/C)^n) curve`
    - `f07: Silk Touch break + sneak-stack interaction`
    - `f07: sell-all routing via f02 bridge`

11. When T1–T10 pass, push:

    ```
    git push origin agent/f07-spawners
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f07-spawners`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- Every `PROPOSED` decision you made, especially the per-type `C`
  defaults you chose. The next agent who gets calibration data will
  use this to update `types.lua`.
- The blaze rods-vs-powder decision and your reasoning.
- Whether creeper spawners exist (your call based on the §4.2 note).
- The accrual mode default (`active_only`) and the clamp value
  (`2 × timer_interval`) in `accrue.lua`.
- The exact signature of any f02 bridge you depend on.

## When you get stuck

- The production curve is uncalibrated for non-skeleton types: pick
  a `C` value proportional to the type's documented output rate, mark
  it `PROPOSED — uncalibrated`, and move on.
- f02 hasn't shipped the routing bridge: stub with `TODO(f02)`. The
  Sell-all button does nothing until they land.
- The menu layout is silent: pick something that follows the shared
  UI kit and mark it `PROPOSED`. Don't get stuck on the visual.
- T4 fails (an entity spawned): the bug is in your on_punch or
  on_rightclick handler — find where you trigger mob spawning and
  remove it. The whole point of f07 is **no mobs**.
