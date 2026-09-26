# AGENT BRIEFING — f08 Teleportation

You are an AI agent picking up **f08 (Teleportation: framework,
`/rtp`, RTP queue, requests, spawn, warps)** in the FriedcakeSMP /
Donut SMP recreation repository at `/Volumes/Dara/dev/coconut/`.

This is two mods: `smp_tp` (P4 — the warm-up framework, `/rtp`,
`/tpa` family, `/spawn`, `/warp`, `/world`, `/back`) and
`smp_rtpqueue` (P8 — the paired random-teleport queue). `smp_tp` is
the more important half: **every other teleport feature, including
homes (f09), rides on its warm-up path.**

## Setup

```
cd /Volumes/Dara/dev/coconut
git status                 # confirm you're on a clean agent branch
cat AGENTS.md              # the rules (read first)
cat CONTRIBUTING.md        # the workflow (read second)
cat tools/claim.md         # the generic claim briefing
```

Engine source-of-truth (DO NOT trust the stale SHA in the spec):

- Mineclonia: `~/dev/mineclonia-git`
- Luanti:     `~/dev/luanti`

## Your feature

```
FEATURE = f08-teleport
SPEC    = spec/features/f08-teleport.md
MODDIRS = friedcake/mods/smp_tp
         friedcake/mods/smp_rtpqueue
BRANCH  = agent/f08-teleport
```

Read `spec/features/f08-teleport.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f08 row, T1–T13, is your merge
  gate.
- `spec/shared/04-ui-kit.md §4.8` — the clickable-chat substitution;
  the Accept/Deny formspec is yours to own.
- `spec/shared/04-ui-kit.md §4.1, §4.6` — prompt-menu construction
  and the red-left/green-right colour convention.
- `spec/shared/03-mineclonia-api.md §3.1` — `mcl_worlds.pos_to_dimension`,
  `mcl_vars.mg_*` bands, `mcl_spawn.get_world_spawn_pos`,
  `mcl_title.set` (action-bar countdown).
- `spec/features/f09-homes.md` (skim) — f09 calls your
  `smp_tp.teleport_with_warmup`. The signature you expose is a
  contract f09 depends on.

## Three things to know up front

1. **`/rtp` has no menu.** §3.1, §4.2. The narrator's on-camera
   description is the evidence: `/rtp` teleports "completely random"
   and "over and over". `rtp.menu_enabled = false` (the menu was
   removed 15 June 2026). Bare `/rtp` starts the warm-up immediately.
   Do **not** build a menu for it. T1 tests exactly this.

2. **The warm-up framework is the real deliverable.** §4.1, §6.1.
   `smp_tp.teleport_with_warmup(player, pos, kind)` is called by
   `/rtp`, `/tpa` acceptance, `/tpahere` acceptance, `/spawn`,
   `/warp` — and later by f09's `/home`. Every command-initiated
   teleport goes through it. Get it right once, and the rest of the
   feature is plumbing. T2, T3, T4, T8, T9 all hinge on it.

   The warm-up MUST:
   - Refuse while combat-tagged (f10 — see below).
   - Cancel on movement > `tp.cancel_move_distance` (1 node).
   - Cancel on damage (`core.register_on_player_hpchange`).
   - Record `last_teleport_from` **before** the player moves, for
     `/world`.
   - Re-validate at fire time: the player may have left, been tagged,
     or the target may have logged off during the countdown.

3. **Four external bridges, all stubs you write:**

   - `smp_combat.is_tagged(name)` (f10) — blocks teleports while
     combat-tagged. **Stub with `TODO(f10)`** returning `false`.
   - `smp_ranks.tier(name)` (f13) — the RTP cooldown is tier-reduced
     (`rtp.cooldown = {default = 60, tier1 = 30}`). **Stub with
     `TODO(f13)`** returning `"default"`.
   - `smp_social.blocks(a, b)` (f11) — `/rtpqueue` never pairs
     mutually-blocking players. **Stub with `TODO(f11)`** returning
     `false`.
   - `smp_settings.get_name(name, key)` (f12) — chat privacy and
     `combat.keep_pearls_on_death` (§4.6). **Stub with `TODO(f12)`**
     returning a permissive default.

   Put all four in `friedcake/mods/smp_tp/bridges.lua` (or split per
   feature). The contract shapes you write are what the other agents
   implement against.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f08-teleport
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_tp/
   ├── mod.conf        # name=smp_tp, depends on smp_core mcl_worlds mcl_spawn
   ├── init.lua        # command registrations; dispatcher
   ├── warmup.lua      # §6.1 teleport_with_warmup; hpchange cancellation
   ├── rtp.lua         # §6.2 random search; emerge_area; safe-y finder
   ├── requests.lua    # tpa/tpahere/accept/deny/cancel/auto; expiry
   ├── spawn.lua       # /spawn, /warp, /world, /back
   ├── zone.lua        # RTP zone at spawn (§4.2.9)
   ├── bridges.lua     # f10 / f13 / f11 / f12 stubs with TODO(fNN)
   ├── formspec.lua    # Accept/Deny prompt menu
   ├── state.lua       # §5 per-player transient state table
   └── test.lua        # /smp test smp_tp
   friedcake/mods/smp_rtpqueue/
   ├── mod.conf        # name=smp_rtpqueue, depends on smp_tp smp_combat
   ├── init.lua        # /rtpqueue; FIFO pairing
   └── test.lua        # /smp test smp_rtpqueue
   friedcake/dev-tests/test_tp.lua      # standalone smoke tests
   ```

   Add two `load_mod = …` lines to `friedcake/mods/modpack.conf` below the
   existing entries:

   ```
   load_mod = smp_tp
   load_mod = smp_rtpqueue
   ```

3. Implement in this order (so each step is testable):

   1. **State** (`state.lua`). The §5 per-player table:
      `warmup`, `last_teleport_from`, `cooldowns`, `requests_out`,
      `requests_in`, `rtpqueue`. Pure Lua, no engine calls — easy to
      unit-test.
   2. **Warm-up** (`warmup.lua`). §6.1. This is the heart of the
      feature. `teleport_with_warmup`, the action-bar countdown via
      `mcl_title.set`, damage cancellation via
      `core.register_on_player_hpchange`, the movement check at fire
      time. Record `last_teleport_from` before moving.
   3. **RTP** (`rtp.lua`). §6.2. `emerge_area` (async, never a
      synchronous scan — performance budget `shared §2.7`),
      `find_safe_y` with the reject list from §4.2.6 (water, lava,
      fire, cactus, magma, campfires, sweet berry, powder snow,
      leaves), dimension bands from `mcl_vars`. At most
      `rtp.max_attempts` (10); on failure, no cooldown starts.
   4. **Requests** (`requests.lua`). §4.4. `/tpa`, `/tpahere`,
      `/tpaccept`, `/tpadeny`, `/tpacancel`, `/tpauto`,
      `/tpatoggle`, `/tpaheretoggle`. One pending request per
      (sender, target, type). Expiry `tpa.expiry` (60 s). Generic
      refusal reveals nothing about which privacy rule fired (T7).
   5. **Spawn/warp/world/back** (`spawn.lua`). §4.5. `/world` is one
      level deep only (T10); `/back` disabled by default.
   6. **Zone** (`zone.lua`). §4.2.9. Check once per second; teleport
      a player who stays inside for `rtp.zone_delay` (3 s); don't
      teleport one who passes through (T12).
   7. **Accept/Deny formspec** (`formspec.lua`). §3.2. Prompt menu,
      `bgcolor[#000000C0]`, `Deny` left/red, `Accept` right/green
      (T13).
   8. **Commands** (`init.lua`). Wire them all up. `/tp` is an alias
      of `/tpa`.
   9. **`smp_rtpqueue`** (`init.lua`). §4.3. FIFO pairing, refused
      while combat-tagged, 5 s countdown, `rtpqueue.separation`
      apart (16–32 nodes), timeout 300 s, mutual-block refusal (T11).

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Money formatting | `smp_core.fmt_money(cents, style)` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Action-bar countdown | `mcl_title.set(player, "actionbar", {text = ..., stay = 1})` |
   | Dimension | `mcl_worlds.pos_to_dimension(pos)` |
   | Spawn position | `mcl_spawn.get_world_spawn_pos(obj)` |
   | Area generation | `core.emerge_area(pos1, pos2, callback)` |
   | Damage hook | `core.register_on_player_hpchange` |
   | Combat tag | `smp_tp.bridges.combat.is_tagged(name)` (f10 stub) |

5. Strings MUST go through `S`. The verbatim strings f08 owns:

   - `Click to send @1 a teleport request` — clickable-chat hint line
     (the non-clickable substitute; see `shared/04-ui-kit.md §4.8`)
   - `Teleport Request` — Accept/Deny formspec title (PROPOSED)
   - `Deny`, `Accept` — buttons
   - `@1 wants to teleport to you.` / `@1 wants you to teleport to them.`
     (PROPOSED)

   Reuse from elsewhere (already in `shared/08-ui-strings.md`):

   - `Cancel`, `Back`

   The warm-up / cooldown / arrival strings are `PROPOSED — no frame
   evidence` and live in your feature file §3 until first screenshot.

6. Money is integer cents (only used if you ever render a fee — you
   don't, but the helper is the only sanctioned way).

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: the movement check at warm-up fire time must be the
   *last* thing before `set_pos` — no `core.after` between the check
   and the move.

8. **Re-validate everything at fire time.** The player may have moved,
   logged off, been tagged, or had the target log off during the
   warm-up. `core.get_player_by_name` returns nil for a logged-off
   player — treat that as "cancelled silently".

9. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_tp.lua` covering the warm-up state machine
   (T3, T4, T8, T9), the safe-y finder (T2, with a fake world), and
   the cooldown logic (T6). Add `friedcake/mods/smp_tp/test.lua` and
   `friedcake/mods/smp_rtpqueue/test.lua` for the in-game paths.

10. Commit on the branch, never on main. Format:

    ```
    f08: <imperative summary>

    <body>
    ```

    Examples:

    - `f08: warm-up framework with action-bar countdown and hpchange cancel`
    - `f08: async RTP search with safe-y finder and reject list`
    - `f08: tpa request family with generic privacy refusal`
    - `f08: Accept/Deny prompt menu`
    - `f08: rtpqueue FIFO pairing with mutual-block refusal`

11. When T1–T13 pass, push:

    ```
    git push origin agent/f08-teleport
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f08-teleport`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- Every `PROPOSED` decision you made on the warm-up display, cooldown
  message, and arrival message.
- The exact signature of `smp_tp.teleport_with_warmup(player, pos,
  kind)` — **f09's agent depends on this.** Make it a clean contract:
  what `kind` values exist, what the caller can assume after it
  returns, whether it's synchronous or async.
- The four bridge signatures in `bridges.lua` — f10, f13, f11, f12.
- Any unresolved V-NN questions you made a `PROPOSED` decision on.

## When you get stuck

- The RTP safe-y scan: the reject list is long and `PROPOSED`. Pick
  the §4.2.6 list, mark it `PROPOSED`, and move on. The test only
  checks "not liquid/fire/void, two breathable nodes above" (T2).
- f10 / f13 / f11 / f12 haven't shipped their bridge: stub with
  `TODO(fNN)` returning the permissive default. Don't block.
- `emerge_area` callback receives `remaining` — check it's 0 before
  searching. Ignoring this is the classic async-Lua bug.
- The movement check races with the countdown: check at fire time
  only, not polled (spec §8). Don't over-engineer.
