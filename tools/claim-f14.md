# AGENT BRIEFING — f14 Statistics, Leaderboards, Scoreboard, API

You are an AI agent picking up **f14 (Statistics, Leaderboards,
Scoreboard and API)** in the FriedcakeSMP / Donut SMP recreation
repository at `/Volumes/Dara/dev/coconut/`.

This is one mod — `smp_stats` — that collects every counter in the
project into one place: block events, kills/deaths, mob kills, sell
and shop proceeds, playtime, and the live money/shards balances. It
also drives the **scoreboard** — the one thing about f14 that is
actually observed in the recording.

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
FEATURE = f14-stats
SPEC    = spec/features/f14-stats.md
MODDIR  = friedcake/mods/smp_stats
BRANCH  = agent/f14-stats
```

Read `spec/features/f14-stats.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f14 row, T1–T11, is your merge
  gate.
- `spec/shared/03-mineclonia-api.md §3.3` — the HUD/scoreboard
  substitution (`player:hud_add` / `hud_change`), and the explicit
  "coordinate readout is Lunar Client, do NOT reimplement" note.
- `spec/features/f01-economy-core.md §3.2` — the **third money
  formatting convention** (lower-case suffix, scoreboard only).
- `spec/features/f02-sell.md §4.8`, `f05-quickbuy.md §4.5` — the two
  stats you consume from the economy mods.
- `spec/features/f10-combat.md §4.3` — combat-log kills must credit
  `kills`/`deaths`.

## The critical integration point (read this first)

**f05 stubbed `smp_stats.add(player, key, value)` with `TODO(f14)`.**
f02, by contrast, wrote directly to `rec.stats.money_made_from_sell`
in the player record. Both target the same place — the `stats` field
of the player record (`f01 §5.1`, `f14 §5`) — so they are compatible,
but only if your `smp_stats.add` also writes to `rec.stats[key]`.

Grep what exists today:

```
grep -rn "smp_stats\.\|money_made_from_sell\|money_spent_on_shop" friedcake/mods/ spec/features/ | grep -iv "features/f14"
git grep -n "smp_stats\|money_made_from_sell" agent/f02-sell -- 'friedcake/mods/smp_sell/*'
git show agent/f05-quickbuy:friedcake/mods/smp_quickbuy/bridges.lua | grep -A8 "f14 stats"
```

Your public surface is:

- `smp_stats.add(player_or_name, key, value)` — increment a counter.
  f05 calls it with a **player ObjectRef**; accept name-or-player and
  normalise. Keys include `money_spent_on_shop`,
  `money_made_from_sell`.
- `smp_stats.get(player_or_name, key) -> number` — read a counter.
- The stats live in `rec.stats` of the `smp_store` player record, so
  leaderboards can enumerate offline players.

f02 already writes `money_made_from_sell` directly to `rec.stats` —
that's fine and consistent. Your `add` writes to the same table, so
the two paths agree.

## Three things to know up front

1. **The scoreboard is the only observed part, and it's specific.**
   §3.1, §4.3. A bottom-right HUD element showing the live money
   balance with a **lower-case suffix** (`723k`, `754k`) — the third
   formatting convention from `f01 §3.2`, distinct from both the
   inline `$700` and the body `$ 5.1K`. Use a new formatter mode, or a
   wrapper over `smp_core` — do NOT reuse `fmt_money`'s upper-case
   suffix. T6 tests the lower-case suffix. Update on balance change
   (`hud_change`), never poll. The title is `server.name`-configurable
   (observed `Voire`, unexplained V-76). The coordinate readout beside
   it is Lunar Client HUD — **do NOT reimplement it** (§1.2, §3.3).

2. **Leaderboards are snapshots, never live queries.** §4.2. Ten
   categories matching the official API: `brokenblocks`, `deaths`,
   `kills`, `mobskilled`, `money`, `placedblocks`, `playtime`, `sell`,
   `shards`, `shop`. Rebuild every `leaderboards.refresh` (300 s), keep
   top `leaderboards.size` (100). **Must stay under 50 ms at 10,000
   player records** (§2.7) — T8 tests this. Offline players must appear
   (records in `smp_store`) — T9.

3. **`/api` has three modes; default `snapshot`.** §4.4, §7. Luanti
   mods can't serve HTTP. Default (`snapshot`) writes JSON into the
   world directory via `core.safe_file_write` for an external web
   server to publish. The `push` mode (outbound via
   `core.request_http_api`) and `off` are the other two. Pick
   `snapshot` unless told otherwise. T10 is mode-dependent — test the
   default path.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f14-stats
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_stats/
   ├── mod.conf         # name=smp_stats, depends on smp_core smp_store
   ├── init.lua         # /stats, /leaderboard, /baltop, /api
   ├── counters.lua     # add / get over rec.stats; block/place hooks
   ├── combat.lua       # kill/death hooks + f10 combat-log credit
   ├── mobs.lua         # wrap mobs_mc:* on_die for mobs_killed
   ├── playtime.lua     # globalstep accumulator, 60 s flush
   ├── scoreboard.lua   # HUD text, lower-case money, hud_change on balance
   ├── boards.lua       # snapshot rebuild, top-100, <50 ms
   ├── api.lua          # /api snapshot/push/off
   ├── formspec.lua     # /stats and /leaderboard menus (PROPOSED)
   └── test.lua         # /smp test smp_stats
   friedcake/dev-tests/test_stats.lua    # standalone smoke tests
   ```

   Add `load_mod = smp_stats` to `friedcake/modpack.conf` below the
   existing entries.

3. Implement in this order (so each step is testable):

   1. **Counters** (`counters.lua`). `add` / `get` over `rec.stats`,
      name-or-player normalisation. Wire `core.register_on_dignode`
      and `core.register_on_placenode`. T1.
   2. **Combat** (`combat.lua`). `core.register_on_dieplayer`; killer
      from `reason.object` or f10's `last_attacker`. Combat-log kills
      credit `kills`/`deaths`. T2.
   3. **Mobs** (`mobs.lua`). Wrap every `mobs_mc:*` `on_die` in
      `core.register_on_mods_loaded`; call the original, then inspect
      `mcl_reason` for the killer. Verify the killer-identifying field
      against `~/dev/mineclonia-git` (V-79). T3.
   4. **Playtime** (`playtime.lua`). One globalstep, O(online players),
      flush to store every 60 s. T11.
   5. **Scoreboard** (`scoreboard.lua`). `player:hud_add` text,
      bottom-right, lower-case money. `hud_change` on balance change
      (hook the economy credit/debit) and on join. T6.
   6. **Boards** (`boards.lua`). Ten categories, snapshot rebuild,
      top-100, sub-50 ms. T7, T8, T9.
   7. **Formspecs** (`formspec.lua`). `/stats` (prompt menu of
      `<Field>: <Value>` lines) and `/leaderboard` (container menu
      `<Category> (Page N)`). Both `PROPOSED` layout.
   8. **API** (`api.lua`). `/api` and `/api delete` under `snapshot`
      mode by default. T10.
   9. **Commands** (`init.lua`). `/stats`, `/leaderboard` (+`/lb`,
      `/leaderboards`), `/baltop` (data source; command owned by f01),
      `/api`.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Player records | `smp_store.api.{get_player,upsert_player,all_player_names}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | HUD | `player:hud_add`, `player:hud_change` |
   | Block hooks | `core.register_on_dignode`, `core.register_on_placenode` |
   | Death hook | `core.register_on_dieplayer` |
   | Entity wrapping | `core.registered_entities`, `core.register_on_mods_loaded` |
   | File write | `core.safe_file_write` |
   | Money format | `smp_core.fmt_money` — but see the lower-case note below |

5. Strings MUST go through `S`. The verbatim strings f14 owns:

   - The scoreboard title is `server.name`-configurable (observed
     `Voire`, unexplained — use `server.name` default, V-76)
   - `Stats`, `Leaderboard`, `Broken Blocks`, `Placed Blocks`,
     `Kills`, `Deaths`, `Mob Kills`, `Money`, `Shards`,
     `Money from Selling`, `Spent in Shop`, `Playtime` — field labels
     (`PROPOSED` house style)

   Reuse from elsewhere: `Back`, `Cancel` (already in
   `shared/08-ui-strings.md`).

   **The scoreboard money is lower-case.** Do not use
   `smp_core.fmt_money`'s upper-case suffix for the scoreboard — it is
   the third convention (`f01 §3.2`). Write a small local
   `fmt_scoreboard(cents)` producing `723k`, `754k`, `1.2m`.

6. Money is integer cents. Stats counters are integers (playtime in
   seconds; money in cents).

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: the snapshot rebuild must not `core.after` mid-sort,
   or a board can capture a half-updated record set.

8. **Performance budget.** §2.7, §8. The playtime accumulator is O(online
   players) per second. The snapshot rebuild runs outside the hot path
   (an `core.after` chain), never in globalstep. T8 (50 ms at 10k) is a
   hard gate.

9. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_stats.lua` covering T1 (block hooks), T2
   (kill credit), T8 (rebuild under 50 ms with 10k synthetic records),
   T9 (offline players). Plus `friedcake/mods/smp_stats/test.lua`.

10. Commit on the branch, never on main. **Stage only your own paths**:

    ```
    git add friedcake/mods/smp_stats/ friedcake/dev-tests/test_stats.lua
    git commit -m "f14: stats counters and block/combat hooks"
    ```

    Never `git add -A`. Format:

    ```
    f14: <imperative summary>

    <body>
    ```

    Examples:

    - `f14: stats counters over rec.stats with block hooks`
    - `f14: kill/death attribution with combat-log credit`
    - `f14: scoreboard HUD with lower-case money`
    - `f14: leaderboard snapshot rebuild under 50 ms`

11. When T1–T11 pass, push:

    ```
    git push origin agent/f14-stats
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f14-stats`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- The exact `smp_stats.add` / `smp_stats.get` signatures and the
  name-or-player normalisation. f05 stubbed `add(player, key, value)`;
  f02 wrote `rec.stats.*` directly. Confirm both are consistent with
  your schema.
- Which `mcl_reason` field identifies the mob killer (V-79) — the
  engine-verification task.
- The scoreboard formatter you used and how it differs from
  `fmt_money` (the third convention).
- Every `PROPOSED` decision you made (menu layouts, field labels,
  `/api` mode).
- Any unresolved V-NN questions you made a `PROPOSED` decision on.

## When you get stuck

- The scoreboard `Voire` title is unexplained: use `server.name`, mark
  `PROPOSED`, note V-76.
- The mob-kill `mcl_reason` killer field is undocumented: inspect
  `~/dev/mineclonia-git/mods/ENTITIES/` for how `on_die(self, pos,
  mcl_reason)` is called and what `mcl_reason` carries. Note findings
  in §10 (V-79).
- The 50 ms rebuild target feels tight: sort top-100 with a partial
  selection, don't sort all 10k records. T8 is a hard gate.
- f02 wrote `rec.stats.*` directly while f05 calls `add()`: your
  `add()` writes to `rec.stats[key]`, so both land in the same place.
  Don't create a second store.
- The scoreboard must update on balance change: hook
  `smp_economy.credit`/`debit`; if those aren't hookable yet, fall
  back to `hud_change` on the `smp_store` dirty-flush, and note it.
