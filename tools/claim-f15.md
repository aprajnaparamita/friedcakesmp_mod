# AGENT BRIEFING — f15 World Rules and Server Configuration

You are an AI agent picking up **f15 (World Rules and Server
Configuration)** in the FriedcakeSMP / Donut SMP recreation repository
at `/Volumes/Dara/dev/coconut/`.

This feature is **different from every other one you've seen**: it has
no mod of its own. Its deliverable is a *configuration package* plus a
handful of small hooks. Most of the work is mapping the reference
server's documented rules [S18] and world shape onto Luanti settings
and Mineclonia defaults — not writing a feature.

## Setup

```
cd /Volumes/Dara/dev/coconut
git status                 # confirm you're on a clean agent branch
cat AGENTS.md              # the rules (read first)
cat CONTRIBUTING.md        # the workflow (read second)
cat tools/claim.md         # the generic claim briefing — read the
                           # "Parallel agents share ONE worktree" warning
```

Engine source-of-truth (DO NOT trust the stale SHA in the spec):

- Mineclonia: `~/dev/mineclonia-git`
- Luanti:     `~/dev/luanti`

## Your feature

```
FEATURE = f15-world-rules
SPEC    = spec/features/f15-world-rules.md
MODDIR  = none — config + policy + small hooks (see "The smp_core question")
BRANCH  = agent/f15-world-rules
```

Read `spec/features/f15-world-rules.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f15 row, T1–T7, is your merge
  gate. Note **T7 is a whole-repo invariant**: the full `smp_` mod set
  must register **zero ABMs**.
- `spec/shared/02-architecture.md §2.7` — the performance budget you
  are re-stating and enforcing.
- `spec/shared/01-overview.md §1.2` — the "do NOT reimplement client
  HUD" note; the world-rules work touches the map seed, which must
  never leak into any command/menu/API.
- `spec/features/f08-teleport.md §4.2` — `/rtp` must respect your
  spawn radius and border (T4 integration).
- `spec/features/f10-combat.md §4.1` — PvP is disabled inside your
  protected spawn area (T2 integration).

## The smp_core question (read this first)

The spec §1 says the small hooks live in `smp_core` — but `smp_core`
is **integrator-owned** (`AGENTS.md`: "do not edit `smp_core` unless
the integrator explicitly asks"). Two ways to handle this:

a. **Ship the hooks in a tiny new mod `smp_world`** and, in
   `f15-world-rules.md §10`, write a `## Proposed shared changes`
   block offering the integrator the option to fold them into
   `smp_core` at merge time. This respects the ownership rule and
   still delivers working hooks.

b. **Deliver only the config package + a proposed-shared-changes
   patch for `smp_core`** and stop — let the integrator apply the
   hooks.

**Default to (a).** It gets the hooks tested and working without you
editing integrator-owned files. The hooks are small enough that the
integrator can fold them into `smp_core` in one mechanical step.

## Three things to know up front

1. **Most of f15 is configuration, not code.** §4, §7, §8. Ship a
   recommended `minetest.conf` snippet (csm_restriction_flags,
   disable_anticheat, mapgen_limit, max_objects_per_block) as a file
   in the repo, plus a `WORLD_RULES.md` documenting the rule→Luanti
   mapping. The code surface is: spawn protection, soft border,
   account-per-IP flag, name filter. Nothing else.

2. **Spawn protection MUST go through `core.is_protected`.** §8. The
   whole point is that every other mod's protection check — f07
   spawner digging, f06 amethyst tools — honours it automatically.
   Do not invent a parallel protection system; wrap or register into
   the existing chain. T1 tests this.

3. **The seed must never leak.** §4.1, T6. No command, menu, or API
   output exposes the map seed. This is a negative test — you can't
   "implement" it, you can only *verify* nothing already leaks it and
   document the rule.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f15-world-rules
   ```

2. Skeleton (this is the whole deliverable — it is small):

   ```
   friedcake/mods/smp_world/        # the tiny hooks mod (option a)
   ├── mod.conf         # name=smp_world, depends on smp_core mcl_worlds
   ├── init.lua         # spawn protection, soft border, account flag, name filter
   └── test.lua         # /smp test smp_world
   friedcake/dev-tests/test_world.lua   # standalone smoke tests
   friedcake/minetest.conf.example      # recommended settings snippet
   friedcake/WORLD_RULES.md             # rule → Luanti mapping (documentation)
   ```

   Add `load_mod = smp_world` to `friedcake/mods/modpack.conf` **below** the
   existing entries (it depends on `smp_core` and `mcl_worlds`).

3. Implement in this order (so each step is testable):

   1. **Config package** (`minetest.conf.example`, `WORLD_RULES.md`).
      The `csm_restriction_flags`, `disable_anticheat = false`,
      `mapgen_limit`, `max_objects_per_block` snippet, and the
      rule→Luanti table from §4.1 / §4.3. This is the bulk of f15.
   2. **Spawn protection** (`init.lua`). §6.
      `smp_world.is_spawn_protected(pos)` using
      `world.spawn_protect_radius` (128), integrated into
      `core.is_protected` so every mod honours it. T1.
   3. **Soft border** (`init.lua`). §6. `enforce_border(player)` in a
      once-per-second per-player globalstep, moving players back
      inside `mapgen_limit - border_margin` (16) with a chat message.
      T3.
   4. **Account-per-IP flag** (`init.lua`). §4.1. On join, count
      accounts for `core.get_player_ip`; a sixth distinct account
      raises a staff flag (log), **does not block**. T5.
   5. **Name filter** (`init.lua`). §4.1. Join-time name check for
      staff-impersonation patterns. Config-gated.
   6. **Seed-leak verification** (`init.lua` + `WORLD_RULES.md`). T6.
      Confirm nothing in the `smp_` set prints the seed; document the
      rule and grep the tree for `get_mapgen_setting("seed")` / `seed`.
   7. **ABM invariant** (`init.lua` + test). T7. A dev-test that
      asserts `core.registered_abms` (or the mod-set equivalent) is
      empty after load. This guards the performance budget.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Protection chain | `core.is_protected` (wrap/register, do not replace) |
   | World shape | `core.get_mapgen_setting("mapgen_limit")`, `mcl_worlds.pos_to_dimension` |
   | Player IP | `core.get_player_ip(name)` |
   | Join hook | `core.register_on_joinplayer` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |

5. Strings MUST go through `S`. The verbatim strings f15 owns:

   - `This area is protected.` (spawn-protection refusal)
   - `You have reached the world border.` (soft-border message)

   Both `PROPOSED` (house style, no frame evidence) — live in your
   feature file §3, not `08-ui-strings.md`.

6. Money is integer cents (not used here).

7. **No yields between validate and mutate** (`shared §2.3`). The
   border check is a per-second globalstep — keep it O(online players),
   no per-node scanning.

8. **Zero ABMs is a hard invariant.** §4.4, T7. You're not adding any,
   but your dev-test should assert the whole `smp_` set is ABM-free
   after load, so a future mod can't quietly introduce one.

9. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_world.lua` covering T1 (spawn protection),
   T3 (border), T5 (account flag), T7 (zero ABMs). Plus
   `friedcake/mods/smp_world/test.lua`.

10. Commit on the branch, never on main. **Stage only your own paths**:

    ```
    git add friedcake/mods/smp_world/ friedcake/dev-tests/test_world.lua friedcake/minetest.conf.example friedcake/WORLD_RULES.md
    git commit -m "f15: world rules config package and smp_world hooks"
    ```

    Never `git add -A`. Format:

    ```
    f15: <imperative summary>

    <body>
    ```

    Examples:

    - `f15: recommended minetest.conf and WORLD_RULES mapping`
    - `f15: spawn protection through core.is_protected`
    - `f15: soft world border and account-per-IP flag`

11. When T1–T7 pass, push:

    ```
    git push origin agent/f15-world-rules
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. **This is why your hooks go in
  `smp_world`, not `smp_core`** — see "The smp_core question".
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f15-world-rules`, stop and
  notify the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- A `## Proposed shared changes` block offering the integrator the
  option to fold `smp_world`'s hooks into `smp_core` at merge time.
- Every `PROPOSED` decision you made (spawn radius 128, border margin
  16, name-filter patterns, entity-cap values).
- Whether anything in the tree currently leaks the seed (T6 findings).
- Any unresolved V-NN questions you made a `PROPOSED` decision on.

## When you get stuck

- The exact entity-cap numbers are unobserved (V-81): leave
  `world.entity_caps = {}` and document the mapping; don't invent
  numbers.
- Bedrock breaking is unverified (V-82): leave
  `world.bedrock_breakable = false` (the Mineclonia default) and note
  it.
- The spawn layout is unobserved (V-80, cross-listed with f08 V-25):
  protect a 128-radius square around world spawn and note the lobbies
  are f08's concern.
- `core.is_protected` wrapping is fiddly: wrap `old_is_protected` in
  the existing chain and register a `register_on_protection_violation`
  for the message. Don't replace the engine function.
- T7 (zero ABMs) fails because another mod added one: that's not your
  bug to fix — flag it to the integrator and note the offending mod in
  §10.
