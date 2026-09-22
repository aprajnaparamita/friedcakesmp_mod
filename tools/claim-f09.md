# AGENT BRIEFING — f09 Homes

You are an AI agent picking up **f09 (Homes)** in the FriedcakeSMP /
Donut SMP recreation repository at `/Volumes/Dara/dev/coconut/`.

Homes is **not its own mod.** It is a subsystem of `smp_tp` — the same
mod that owns f08 (teleport framework). This is the ownership collision
you must respect: you and the f08 agent share `friedcake/mods/smp_tp/`.
Read the collision section below before touching anything.

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
FEATURE = f09-homes
SPEC    = spec/features/f09-homes.md
MODDIR  = friedcake/mods/smp_tp          ← SHARED with f08
BRANCH  = agent/f09-homes
```

Read `spec/features/f09-homes.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f09 row, T1–T9, is your merge
  gate.
- `spec/shared/04-ui-kit.md §4.1, §4.6` — prompt-menu construction,
  the pre-filled `field[]` idiom, the red-on-hover destructive
  action.
- `spec/features/f08-teleport.md §4.1, §6.1` — the warm-up you call.
  `smp_tp.teleport_with_warmup(player, pos, kind)`.
- `spec/features/f13-ranks.md §4` (skim) — the slot-limit table. f13
  is a stub; stub the call if not done.

## The ownership collision (read this first)

f08 owns `smp_tp`'s framework: `warmup.lua`, `rtp.lua`, `requests.lua`,
`spawn.lua`, `zone.lua`, `bridges.lua`, `state.lua`, `formspec.lua`.
**f09 adds homes to the same mod directory.** Two consequences:

1. **Do not touch f08's files.** Your surface is **one new file**:
   `friedcake/mods/smp_tp/homes.lua`, plus registering your commands
   and formspec formnames there. If f08's `init.lua` already exists,
   you register your chat commands from `homes.lua` — do **not** edit
   f08's `init.lua`. The integrator will reconcile the command
   registrations at merge time.

2. **If f08 has not landed when you start**, the warm-up function
   `smp_tp.teleport_with_warmup` does not exist yet. Two options:

   a. **Coordinate.** Check `git log --all --oneline | grep f08`. If
      f08 has committed `warmup.lua`, build against its real
      signature.
   b. **Stub it.** If f08 is still in flight, define your own local
      fallback `smp_tp.teleport_with_warmup` guarded so it defers to
      f08's the moment that file exists (`if smp_tp.teleport_with_warmup
      then … end`). Mark it `TODO(f08)`.

   The same applies to `smp_ranks.home_limit(player)` (f13) — stub
   with `TODO(f13)` returning the tier slot limit from §4.1.

## Two things to know up front

1. **The v0.1 flat-grid description is WRONG.** §1. The observed
   interface is a **tab row → per-home submenu**, not a flat grid
   with sneak-click delete. Build the tab row. The spec replaces
   v0.1's §6.5; do not resurrect the old design from any stale
   notes.

2. **Five exact chat strings, all OBSERVED:**

   | String | When |
   |---|---|
   | `Home set` | `/sethome` or `New Home` succeeded |
   | `Home deleted` | `Delete` confirmed |
   | `Home does not exist` | `/homes <unknown>` |
   | `You reached home limits` | slots exhausted — **note the plural "limits"** |
   | `You renamed your home to @1` | `Rename` save; reconstructed from a garbled frame |

   Reproduce them word-for-word, including the plural `limits`. T1,
   T2, T4, T5 test them exactly.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f09-homes
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_tp/
   ├── homes.lua       # YOUR file — all homes logic, commands, formspecs
   └── (everything else belongs to f08 — do not edit)
   friedcake/mods/smp_tp/test_homes.lua   # /smp test smp_tp:homes
   friedcake/dev-tests/test_homes.lua     # standalone smoke tests
   ```

   Do **not** add a new `load_mod` line — homes lives inside `smp_tp`,
   which f08's prompt already added. If `smp_tp` is not yet in
   `friedcake/modpack.conf`, add `load_mod = smp_tp` (not
   `smp_homes`).

3. Implement in this order (so each step is testable):

   1. **Data** (in `homes.lua`). Read/write the `homes` field of the
      player record via `smp_store.api`. The schema is in §5: each
      home is `{ id, name, icon, pos, created }`. `id` is stable
      across renames; `name` is display text.
   2. **Slot limits** (`homes.lua`). §4.1. `smp_ranks.home_limit`
      (stub with `TODO(f13)`). Default 2, tier1 9, tier2 27, tier3 90.
   3. **`/sethome`, `/homes`, `/delhome`** (`homes.lua`). §2, §4.2.
      `/sethome` without a name uses `Home <n>` with the next free
      index. `/homes <unknown>` → `Home does not exist`.
   4. **Tab row** (`homes.lua`). §3.1. Prompt menu, title `Homes`,
      one `item_image_button[]` per home (tooltip `<name>\nClick to
      manage`), then `New Home`, then `Show More` at the far right
      when `#homes > homes.tabs_before_more` (default 3).
   5. **Per-home submenu** (`homes.lua`). §3.2. Title = the home's
      name. 2×2 grid: `Teleport`, `Change Icon`, `Rename`, `Delete`,
      then centred `Back`. Style `Delete` with
      `style[delete;textcolor=red]` [F0068].
   6. **`Choose Icon`** (`homes.lua`). §3.3. Search field, `Search` /
      `Default` / `Back` buttons, and a paged `item_image_button[]`
      grid over `core.registered_items` sorted by `get_description()`.
   7. **`Rename`** (`homes.lua`). §3.4. `field[]` **pre-filled with
      the current name**, two stacked `Save` / `Cancel` buttons. On
      save: `You renamed your home to @1`.
   8. **Teleport** (`homes.lua`). §4.4. Call
      `smp_tp.teleport_with_warmup(player, home.pos, "home")` — the
      f08 contract. Re-validate the home id on receipt (the client
      field is untrusted; the home may have been deleted meanwhile —
      T8).

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Player records | `smp_store.api.{get_player,upsert_player}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Warm-up | `smp_tp.teleport_with_warmup(player, pos, kind)` (f08) |
   | Slot limit | `smp_ranks.home_limit(player)` (f13 — stub) |
   | Menu sessions | `smp_core.{open_session,get_session,close_session}` |
   | Item list | `core.registered_items` sorted by `get_description()` |

5. Strings MUST go through `S`. The verbatim strings f09 owns:

   - `Homes` (menu title)
   - `Home @1` (auto-name)
   - `New Home`, `Show More` (tabs)
   - `Click to manage` (tab tooltip line 2)
   - `Teleport`, `Change Icon`, `Rename`, `Delete`, `Back`
   - `Choose Icon`, `Default`
   - `New Name` (Rename field label)
   - `Save`, `Cancel`
   - `Home set`, `Home deleted`, `Home does not exist`,
     `You reached home limits`, `You renamed your home to @1`

   All from `shared/08-ui-strings.md §8.1, §8.2, §8.3, §8.6`.

6. Money is integer cents (not used here, but the helper is the only
   sanctioned way if you ever render a value).

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: between reading a home's slot and creating it, no
   `core.after` — the slot check and the insert must be atomic, or
   two rapid `/sethome` calls can exceed the limit (T1).

8. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_homes.lua` covering T1 (slot limit),
   T2 (auto-name), T5 (unknown home), T8 (deleted-while-open) and
   `friedcake/mods/smp_tp/test_homes.lua` for the in-game paths.

9. Commit on the branch, never on main. **Stage only your own paths**:

   ```
   git add friedcake/mods/smp_tp/homes.lua friedcake/mods/smp_tp/test_homes.lua friedcake/dev-tests/test_homes.lua
   git commit -m "f09: homes subsystem — tab row, submenu, icon, rename"
   ```

   Never `git add -A` (see the shared-worktree warning). Format:

   ```
   f09: <imperative summary>

   <body>
   ```

   Examples:

   - `f09: homes data layer over the smp_store player record`
   - `f09: Homes tab row and per-home submenu`
   - `f09: Choose Icon grid over core.registered_items`
   - `f09: Rename with pre-filled field and exact chat strings`

10. When T1–T9 pass, push:

    ```
    git push origin agent/f09-homes
    ```

    The integrator merges into main — and reconciles your
    `smp_tp` additions with f08's.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not edit f08's files under `smp_tp/` (warmup.lua, rtp.lua,
  requests.lua, spawn.lua, zone.lua, bridges.lua, state.lua,
  formspec.lua, init.lua). Your surface is `homes.lua`.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f09-homes`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- Every `PROPOSED` decision you made (delete-confirmation step,
  `Show More` target screen, default icon, warm-up display).
- Whether you built against f08's real `teleport_with_warmup` or a
  stub, and the signature you assumed.
- The `smp_ranks.home_limit` signature you assumed (f13).
- Any unresolved V-NN questions you made a `PROPOSED` decision on.

## When you get stuck

- f08 hasn't landed `teleport_with_warmup`: stub with `TODO(f08)`
  and the `if smp_tp.teleport_with_warmup then … end` guard. Don't
  block.
- f13 hasn't landed `home_limit`: stub with `TODO(f13)` returning
  the §4.1 table lookup.
- The `Choose Icon` list is huge (every registered item): page it
  and use `item_image_button[]`; a `textlist[]` is acceptable if
  icons prove too costly (spec §8).
- The `Delete` confirmation step is unobserved: add one, mark it
  `PROPOSED`, and note it in §10 (V-31).
