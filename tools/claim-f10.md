# AGENT BRIEFING — f10 Combat Tag, Combat Log, Bounties

You are an AI agent picking up **f10 (Combat Tag, Combat Log,
Bounties)** in the FriedcakeSMP / Donut SMP recreation repository at
`/Volumes/Dara/dev/coconut/`.

This is two mods: `smp_combat` (the tag, the log, the blocked-command
list) and `smp_bounty` (escrowed bounties and their payout). Zero
frames of evidence — the combat tag's existence is *implied* by
documented "during combat" restrictions [S7][S19], but its duration,
display and full rules are unverified. Everything is clone consensus
[C1] fitted to the documented restriction points.

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
FEATURE = f10-combat
SPEC    = spec/features/f10-combat.md
MODDIRS = friedcake/mods/smp_combat
         friedcake/mods/smp_bounty
BRANCH  = agent/f10-combat
```

Read `spec/features/f10-combat.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f10 row, T1–T12, is your merge
  gate.
- `spec/shared/03-mineclonia-api.md §3.1` — the Mineclonia surface you
  depend on: `core.register_on_punchplayer`, arrow `_shooter`,
  `mcl_death_drop.registered_dropped_lists`,
  `mcl_spawn.get_world_spawn_pos`, `core.register_on_chatcommand`,
  `mcl_title.set`.
- `spec/features/f08-teleport.md §4.1` — the blocked-command list is
  consumed by f08's warm-up (it calls `smp_combat.is_tagged`).
- `spec/features/f05-quickbuy.md §4.4` — Quick Buy blocks while tagged.
- `spec/features/f06-shards.md §4.3` — the Shard Pickaxe blocks while
  tagged.
- `spec/features/f02-sell.md §4.6` — `/sell` is *allowed* in combat
  (enabled June 2026) [S3]. Your blocked list must NOT include it.

## The critical integration point (read this first)

**Several other agents have already written bridges that stub
`smp_combat.is_tagged(name)` with `TODO(f10)`.** f05, f06 and f08 all
depend on the exact function you are about to implement for real. This
means your public surface is a contract with three consumers already
in flight:

- `smp_combat.is_tagged(name) -> bool` — the one they all call.
- `smp_combat.tag(player_name, attacker_name)` — tags a player.
- `smp_combat.last_attacker(name) -> string | nil` — used by combat
  log and by f11's `/kill` credit.

Before you start, grep the tree to see exactly what the other agents
assumed:

```
grep -rn "smp_combat\.\|is_tagged\|last_attacker" friedcake/mods/ | grep -v "mods/smp_combat/"
```

Whatever signature they assumed, **match it**. If one of them assumed
something you can't honour, file a `## Proposed shared changes` block
in `f10-combat.md §10` and stop — don't silently break their bridge.

## Three things to know up front

1. **The tag is in-memory only.** §5.1. `smp_combat.tags[name]` with
   `expires`, `last_attacker`, `last_attacker_at`. Tags MUST NOT
   survive a restart — a server crash *is* a combat log, and the
   logout path cannot run on a crashed process. T11 tests that a
   rejoining player whose tag would have been live joins normally.

2. **Combat log is the anti-disconnect mechanism.** §4.3. When a
   tagged player disconnects:
   - Drop every list in `mcl_death_drop.registered_dropped_lists`
     (`main`, `craft`, `armor`, `offhand`) at the logout position.
     **Iterate the registered list, never hard-code the names** —
     `spec §8` is explicit, so Mineclonia changes propagate.
   - Credit the kill to `last_attacker` (statistics via f14, bounty
     via §4.4).
   - Set `smp:combat_logged = 1` meta; on next join respawn at
     `mcl_spawn.get_world_spawn_pos` and clear the flag.
   - **Do not rely on `mcl_keepInventory`** — the logout path drops
     explicitly and independently of the death path.

3. **Bounty escrow, not credit.** §4.4, §5.2, `shared §2.6` R2.
   `/bounty add` debits the contributor immediately (escrow); the
   bounty total is `sum(contributors)`. Payout comes **only** from
   escrow. Ledger codes `bounty_escrow`, `bounty_payout` (R3). Never
   mint money on payout — move existing escrow.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f10-combat
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_combat/
   ├── mod.conf         # name=smp_combat, depends on smp_core smp_store mcl_death_drop
   ├── init.lua         # tag lifecycle, command block list, log hooks
   ├── tag.lua          # is_tagged, tag, untag, refresh, countdown
   ├── attribution.lua  # resolve_attacker: melee, arrow _shooter, explosion ring
   ├── combatlog.lua    # drop_death_lists, credit_kill, respawn-at-spawn
   ├── countdown.lua    # action-bar display via mcl_title.set
   ├── blocks.lua       # blocked_commands list + register_on_chatcommand
   └── test.lua         # /smp test smp_combat
   friedcake/mods/smp_bounty/
   ├── mod.conf         # name=smp_bounty, depends on smp_combat smp_economy smp_store
   ├── init.lua         # /bounty, /bounty add, /bountyadmin, claim path
   ├── escrow.lua       # escrow deposit, payout, pro-rata refund
   ├── abuse.lua        # IP check, pair cooldown, safe-zone check
   └── test.lua         # /smp test smp_bounty
   friedcake/dev-tests/test_combat.lua     # standalone smoke tests
   friedcake/dev-tests/test_bounty.lua     # standalone smoke tests
   ```

   Add two `load_mod = …` lines to `friedcake/mods/modpack.conf` below the
   existing entries:

   ```
   load_mod = smp_combat
   load_mod = smp_bounty
   ```

3. Implement in this order (so each step is testable):

   1. **Tag** (`tag.lua`). The in-memory table, `is_tagged`, `tag`,
      `untag`, refresh-on-hit. T1 tests the refresh; T12 tests untag
      on death.
   2. **Attribution** (`attribution.lua`). §4.2, §8. Three cases:
      melee (`core.register_on_punchplayer`), arrows (entity `_shooter`
      field), environment (nil). Explosion attribution is a 10 s ring
      buffer of (pos, placer) for end crystals, respawn anchors, TNT.
      T2 tests `_shooter`.
   3. **Blocks** (`blocks.lua`). §4.2.4. The blocked-command list,
      enforced via `core.register_on_chatcommand` returning `true` to
      cancel. The message names the command. `/sell` and `/msg` are
      NOT blocked. T3 tests this.
   4. **Countdown** (`countdown.lua`). §4.2.3. Action-bar via
      `mcl_title.set`. String is `PROPOSED` (`In combat: @1s` or
      similar house style).
   5. **Combat log** (`combatlog.lua`). §4.3. Drop the registered
      death lists, credit the kill, set the respawn flag. T4, T5, T6.
   6. **`smp_combat` init** (`init.lua`). Wire the hooks:
      `register_on_punchplayer`, `register_on_chatcommand`,
      `register_on_leaveplayer`, `register_on_dieplayer`.
   7. **Bounty escrow** (`escrow.lua`). §4.4. `/bounty add` debits
      and escrows; two contributions stack; `bounty.min_amount` ($1,000)
      floor; self-bounty refused. T8.
   8. **Bounty abuse** (`abuse.lua`). §4.4.4. Same-IP refusal,
      `bounty.pair_cooldown` (3,600 s) per killer–target pair,
      safe-zone refusal. T9.
   9. **Bounty claim** (`init.lua`). §4.4.3. On kill — including
      combat-log kills — credit the whole bounty from escrow and
      broadcast. T5, T7.
   10. **`/bountyadmin clear`** (`init.lua`). §4.4.5. Pro-rata refund
       from escrow. T10.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Money formatting | `smp_core.fmt_money(cents, style)` |
   | Player records | `smp_store.api.{get_player,upsert_player}` |
   | Money mutation | `smp_store.api.{add_money,take_money,set_money}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Punch hook | `core.register_on_punchplayer` |
   | Command block | `core.register_on_chatcommand` |
   | Death lists | `mcl_death_drop.registered_dropped_lists` |
   | Spawn position | `mcl_spawn.get_world_spawn_pos(obj)` |
   | Action bar | `mcl_title.set(player, "actionbar", {text = ..., stay = 1})` |

5. Strings MUST go through `S`. The combat/bounty strings are
   `PROPOSED — no frame evidence` and live in your feature file §3,
   not in `08-ui-strings.md`. The integrator mirrors later.

   Proposed strings (§3, house style):

   - `In combat: @1s` (action-bar countdown)
   - `You cannot use /@1 during combat.` (blocked-command refusal)
   - `@1 claimed the @2 bounty on @3.` (bounty broadcast)
   - `@1` / `$ @2` / `Click to view` (bounty-list tooltip)

6. Money is integer cents. Bounty escrow is integer cents. Never mint
   on payout — move escrow.

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: the combat-log drop and the kill credit must happen
   in the same callback with no `core.after` between them, or a crash
   between the two loses the kill.

8. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_combat.lua` (tag refresh T1, attribution
   T2, blocks T3, log T4/T5/T6, untag T12) and
   `friedcake/dev-tests/test_bounty.lua` (escrow T8, abuse T9, refund
   T10). Plus `friedcake/mods/smp_combat/test.lua` and
   `friedcake/mods/smp_bounty/test.lua`.

9. Commit on the branch, never on main. **Stage only your own paths**:

   ```
   git add friedcake/mods/smp_combat/ friedcake/mods/smp_bounty/ friedcake/dev-tests/test_combat.lua friedcake/dev-tests/test_bounty.lua
   git commit -m "f10: combat tag and blocked-command list"
   ```

   Never `git add -A` (see the shared-worktree warning). Format:

   ```
   f10: <imperative summary>

   <body>
   ```

   Examples:

   - `f10: combat tag lifecycle with refresh and action-bar countdown`
   - `f10: attacker attribution — melee, arrow _shooter, explosion ring`
   - `f10: combat-log drop of registered death lists and respawn-at-spawn`
   - `f10: bounty escrow, stacking and anti-abuse checks`

10. When T1–T12 pass, push:

    ```
    git push origin agent/f10-combat
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f10-combat`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- Every `PROPOSED` decision you made (tag duration 20 s, blocked list,
  countdown string, broadcast text, anti-abuse thresholds).
- The exact signature of `smp_combat.is_tagged` — three agents are
  already stubbing it. Make it a clean contract.
- Whether the explosion ring buffer is 10 s and how it keys.
- Any unresolved V-NN questions you made a `PROPOSED` decision on.

## When you get stuck

- The blocked list is unverified: use the §4.2.4 list, mark it
  `PROPOSED`, and move on. T3 only checks the commands in the list.
- f14 (`smp_stats`) isn't landed: stub the kill-credit call with
  `TODO(f14)`.
- f11 (`smp_social`, `/kill`) isn't landed: stub the `/kill` credit
  hook with `TODO(f11)`. T7 can still pass via a direct call.
- Elytra disabling needs a hook into `playerphysics/elytra.lua` and
  the spec says it's fragile — leave `combat.disable_elytra = false`
  by default and mark the hook `PROPOSED`/fragile. Don't build it
  unless told.
- The `_shooter` field is the only arrow attribution [M1]; if a bow
  sets a different field, verify against `~/dev/mineclonia-git` and
  note the discrepancy in §10.
