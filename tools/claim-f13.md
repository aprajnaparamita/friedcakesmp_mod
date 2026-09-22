# AGENT BRIEFING — f13 Ranks and Membership

You are an AI agent picking up **f13 (Ranks and Membership)** in the
FriedcakeSMP / Donut SMP recreation repository at
`/Volumes/Dara/dev/coconut/`.

This is one small mod — `smp_ranks` — but it is **the most-stubbed
contract in the whole project.** f07, f08 and f09 all call
`smp_ranks.tier(name)` / `smp_ranks.home_limit(name)` and wrote
`TODO(f13)` stubs. f03 and f04 consult the auction/order slot limits.
You are the real implementation that resolves every one of those
stubs. Small surface, high leverage.

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
FEATURE = f13-ranks
SPEC    = spec/features/f13-ranks.md
MODDIR  = friedcake/mods/smp_ranks
BRANCH  = agent/f13-ranks
```

Read `spec/features/f13-ranks.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f13 row, T1–T8, is your merge
  gate.
- `spec/features/f09-homes.md §4.1` — the slot table your
  `home_limit` answers.
- `spec/features/f03-auction.md §7`, `f04-orders.md §7` — the
  auction/order slot tables your `ah_limit` / `order_limit` answer.
- `spec/features/f08-teleport.md §7` — the `rtp.cooldown` table your
  `rtp_cooldown` answers.

## The critical integration point (read this first)

**f07, f08 and f09 already stub you.** Grep the tree to see exactly
what signatures they assumed:

```
grep -rn "smp_ranks\.\|home_limit\|rtp_cooldown\|ah_limit\|order_limit" friedcake/mods/ spec/features/ | grep -iv "features/f13"
```

You will find at least two call shapes:

- `smp_ranks.tier(name)` — f08 §6.2 (a **name string**)
- `smp_ranks.home_limit(player)` — f09 §6 (a **player ref**)

The argument types are inconsistent across specs. **Make every perk
function accept either a name string or a player ObjectRef** — normalise
with a helper (`local n = type(arg) == "string" and arg or arg:get_player_name()`).
The f13 spec §4.2.4 lists the full public surface:

- `smp_ranks.tier(name_or_player) -> "default" | "tier1" | "tier2" | "tier3" | "media"`
- `smp_ranks.home_limit(name_or_player) -> int`
- `smp_ranks.ah_limit(name_or_player) -> int`
- `smp_ranks.order_limit(name_or_player) -> int`
- `smp_ranks.rtp_cooldown(name_or_player) -> int` (seconds)

Implement exactly these names. If a consumer assumed something else,
note the normalisation in `f13-ranks.md §10`.

## Three things to know up front

1. **No rank prefix. v0.1 is wrong — again.** §4.2.7. No observed chat
   line carries a `[Rank]` prefix [F0269, F0282, F0283].
   `ranks.chat_prefix` defaults to `""` and `smp_ranks` MUST NOT add a
   prefix by default. T5 (integration with f11) tests the absence.

2. **Expiry is lazy.** §8, §6. `tier()` computes from `expires_at` —
   an expired tier reads as `"default"` with **no record mutation**.
   T2 tests this. The expiry sweep (hourly) exists *only* to emit the
   notification, not to mutate records.

3. **The perk API is the deliverable, not the UI.** §4.2.4. Consumers
   MUST call `home_limit` / `ah_limit` / `order_limit` /
   `rtp_cooldown` / `tier` rather than reading the rank record
   directly, so the tier table lives in exactly one place. Everything
   else — `/ranks`, `/rank` — is thin on top.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f13-ranks
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_ranks/
   ├── mod.conf         # name=smp_ranks, depends on smp_store smp_core
   ├── init.lua         # /ranks, /rank; expiry sweep
   ├── tiers.lua        # the §4.1 tier table as configuration data
   ├── perk.lua         # tier / home_limit / ah_limit / order_limit / rtp_cooldown
   ├── grant.lua        # grant / clear; the §6 algorithm
   ├── expiry.lua       # hourly sweep, notification only
   ├── formspec.lua     # /ranks prompt menu from live config
   └── test.lua         # /smp test smp_ranks
   friedcake/dev-tests/test_ranks.lua      # standalone smoke tests
   ```

   `smp_ranks` is **already in `friedcake/modpack.conf`** (it was
   scaffolded as a stub). Verify the line is present; do not add a
   duplicate.

3. Implement in this order (so each step is testable):

   1. **Tiers** (`tiers.lua`). The §4.1 table as configuration data.
      Tier ids `default`/`tier1`/`tier2`/`tier3`/`media`. Slot tables:
      homes `{2,9,27,90}`, ah `{9,45,90,90}`, orders `{9,45,90,90}`.
      `rtp.cooldown` `{default = 60, tier1 = 30}`. Media = tier3.
   2. **Perk API** (`perk.lua`). The five functions. `tier()` reads the
      player record's `rank` field, checks `expires_at > os.time()`,
      falls back to `"default"`. Accept name-or-player everywhere. T1,
      T2, T8.
   3. **Grant** (`grant.lua`). §6. `grant(name, tier, days)` with the
      stacking rule: consecutive same-tier grants extend `expires_at`
      by `days * 86400` from the current expiry. `clear(name)`. T3, T6.
   4. **Expiry** (`expiry.lua`). §8. `core.after` loop over **dirty
      candidates only** (players with `expires_at` in the past), not a
      full scan. Emit the notification; no record mutation.
   5. **`/ranks` formspec** (`formspec.lua`). §4.2.9. Prompt menu
      rendering the tier table **from live config**, never hard-coded
      perk numbers. Read-only field for the store URL (Luanti can't
      open URLs). T7.
   6. **Commands** (`init.lua`). `/ranks`, `/rank set <player> <tier>
      <days>`, `/rank clear <player>` (both admin). T6 (offline grant).

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Player records | `smp_store.api.{get_player,upsert_player}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Menu sessions | `smp_core.{open_session,get_session,close_session}` |
   | Offline grant | `smp_store.api.get_player(name)` — the record is in the store, not player meta |

5. Strings MUST go through `S`. The verbatim strings f13 owns:

   - `Ranks` (menu title — PROPOSED)
   - `Back`
   - `/ranks` perk-table row labels (`PROPOSED — no frame evidence`)

   Reuse from elsewhere: `Cancel`, `Back` (already in
   `shared/08-ui-strings.md`).

   Note: **Donut names (`Donut+`, `Donut++`, `Donut+++`, `Media`)
   appear only when describing the reference server** — the spec uses
   `tier1`–`tier3`/`media` internally (`shared §0.5`). Use the tier
   ids in config and formspec data; only the `/ranks` display text may
   name them.

6. Money is integer cents (not used here).

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: the grant's read-modify-write of `expires_at` must be
   atomic, or two rapid `/rank set` calls can clobber the stacking.

8. **Offline grants work** — the record lives in `smp_store`, not
   player meta. `smp_store.api.get_player(name)` returns the record
   even when the player is offline. T6.

9. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_ranks.lua` covering T1 (limit changes via
   perk API), T2 (lazy expiry), T3 (stacking grants). Plus
   `friedcake/mods/smp_ranks/test.lua`.

10. Commit on the branch, never on main. **Stage only your own paths**:

    ```
    git add friedcake/mods/smp_ranks/ friedcake/dev-tests/test_ranks.lua
    git commit -m "f13: perk API resolving the tier/home/ah/orders/rtp contracts"
    ```

    Never `git add -A`. Format:

    ```
    f13: <imperative summary>

    <body>
    ```

    Examples:

    - `f13: tier table as configuration data`
    - `f13: perk API — tier, home_limit, ah_limit, order_limit, rtp_cooldown`
    - `f13: grant with 30-day stacking and lazy expiry`
    - `f13: /ranks menu from live config`

11. When T1–T8 pass, push:

    ```
    git push origin agent/f13-ranks
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f13-ranks`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- The exact perk-API signatures and the name-or-player normalisation
  you chose. f07, f08, f09, f03, f04 all depend on them.
- Every `PROPOSED` decision you made (tier3 exact slot counts — the
  spec says "at least" tier2; stacking rule; expiry notification).
- Whether the `/ranks` menu uses the `Ranks` title and how the store
  URL is displayed.
- Any unresolved V-NN questions you made a `PROPOSED` decision on.

## When you get stuck

- f09 assumed `home_limit(player)` and f08 assumed `tier(name)`:
  accept both argument types in every function. Don't pick one and
  break the other.
- tier3's exact slot counts are unobserved ("at least 90"): use 90,
  mark `PROPOSED`, note V-72.
- The `/ranks` menu is unobserved: build the prompt menu from live
  config, mark `PROPOSED`, move on.
- A consumer hard-coded a limit instead of calling the API: note it in
  §10 and flag the integrator — but don't edit their mod.
