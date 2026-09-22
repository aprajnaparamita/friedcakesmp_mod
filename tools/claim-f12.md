# AGENT BRIEFING — f12 Player Settings

You are an AI agent picking up **f12 (Player Settings)** in the
FriedcakeSMP / Donut SMP recreation repository at
`/Volumes/Dara/dev/coconut/`.

This is one mod — `smp_settings` — and it is the **storage and
presentation layer** for every per-player setting in the project.
Critically, it does **not** enforce anything: f11 enforces the chat
settings, f08 enforces the teleport toggles, f10 reads the pearl
setting. Your job is to store values and render the observed menu —
nothing else.

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
FEATURE = f12-settings
SPEC    = spec/features/f12-settings.md
MODDIR  = friedcake/mods/smp_settings
BRANCH  = agent/f12-settings
```

Read `spec/features/f12-settings.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f12 row, T1–T9, is your merge
  gate.
- `spec/shared/04-ui-kit.md §4.5` — the toggle-row pattern (the value
  is inside the label; `checkbox[]` cannot express three states).
- `spec/shared/04-ui-kit.md §4.1, §4.9` — prompt-menu construction.
- `spec/shared/00-conventions.md §0.5` — the one genericised string,
  `Choose a category to change your @1 settings` (the `@1` is
  `server.name`).

## The critical integration point (read this first)

**This file is a rewrite, not a revision.** v0.1's five categories
(Chat/Economy/Teleport/General/Social) and fifteen boolean settings
are **wrong**. The observed menu has **seven categories** and
**three-valued** toggles. Do not implement v0.1's table. The clone
settings survive only as *candidates* for the six unopened categories,
clearly marked (§10) — never as observed fact.

**Several agents call `smp_settings.get(...)`.** f01 (pay_accept),
f08 (tpa/tpahere toggles), f10 (keep_pearls_on_death), f11 (chat
privacy). Grep what they assumed — note the function name may be
inconsistent (`get` vs `get_name` across specs):

```
grep -rn "smp_settings\.\|get_name\|settings\.get" friedcake/mods/ spec/features/ | grep -iv "mods/smp_settings"
```

**You own the canonical accessor.** Pick one name, implement it, and
note in `f12-settings.md §10` that the other specs should be normalised
to it. The integrator reconciles the call sites.

## Three things to know up front

1. **Seven categories, observed order.** §3.1. `Chat`,
   `Notifications`, `PvP`, `Visuals`, `Privacy`, `Scoreboard`,
   `General`. Seven `button[]` in a 2×2×2 grid with `General` centred
   beneath. Tooltip per button: `Open <Category> settings`. Purple
   hover highlight (`style[<id>:hovered;bgcolor=#7B2FBE]`, hue
   unverified). T1, T2 test the category menu.

2. **The value lives inside the label.** §3.2, §4.2, `04-ui-kit.md §4.5`.
   A toggle is `button[]` labelled `<Name>: <Value>` — not a
   `checkbox[]`. Clicking advances to the next value and redraws in
   place. Three values: `ON`, `OFF`, `Friends/Followed` (stored as
   `FRIENDS_FOLLOWED`). T5, T6 test the toggle behaviour.

3. **Storage is player meta, not `smp_store`.** §5, §4.6,
   `shared/02-architecture.md §2.2`. Settings live in player meta
   `smp:settings` as JSON. Unknown keys are preserved on write (a
   downgrade must not discard a newer setting). T7 tests persistence
   and unknown-key preservation.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f12-settings
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_settings/
   ├── mod.conf         # name=smp_settings, depends on smp_core
   ├── init.lua         # /settings command; field handler
   ├── registry.lua     # register_category / register; the §5.1 API
   ├── store.lua        # JSON in player meta smp:settings; unknown-key preserve
   ├── accessor.lua     # smp_settings.get / set — the canonical API
   ├── formspec.lua     # category menu + category screen
   ├── chat.lua         # register the seven Chat settings (§5.1)
   └── test.lua         # /smp test smp_settings
   friedcake/dev-tests/test_settings.lua    # standalone smoke tests
   ```

   Add `load_mod = smp_settings` to `friedcake/modpack.conf` below the
   existing entries.

3. Implement in this order (so each step is testable):

   1. **Store** (`store.lua`). JSON read/write of player meta
      `smp:settings`. Preserve unknown keys on write. T7.
   2. **Accessor** (`accessor.lua`). `smp_settings.get(player_or_name,
      id)` and `smp_settings.set(...)`. This is the canonical API other
      agents call. Return the default when unset.
   3. **Registry** (`registry.lua`). §5.1.
      `smp_settings.register_category(...)` and
      `smp_settings.register(...)` with `category`, `label`, `values`,
      `default`, `display`. Settings are registered, not hard-coded,
      so unopened categories can be filled in later.
   4. **Chat settings** (`chat.lua`). Register the seven Chat settings
      from §5.1 with their observed labels and values.
   5. **Category menu** (`formspec.lua`). §3.1. Seven buttons, tooltips
      `Open <Category> settings`, purple hover. Subtitle
      `Choose a category to change your @1 settings` with `@1` =
      `server.name`. T1, T2, T3.
   6. **Category screen** (`formspec.lua`). §3.2. `Settings - Chat`
      (space-hyphen-space). Toggle rows as `button[]` labelled
      `<Label>: <Value>`, `tooltip[<id>;Click to toggle]`, then
      `Back`. T4.
   7. **Toggle handler** (`init.lua`). §6. Look up the id in the
      registry (untrusted field — T8), cycle the value, wrap, redraw
      in place. T5, T6.
   8. **Command** (`init.lua`). `/settings`.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Player meta | `player:get_meta():get_string / set_string` |
   | JSON | `core.write_json / core.parse_json` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Menu sessions | `smp_core.{open_session,get_session,close_session}` |
   | Server name | `core.settings:get("server.name")` (or the smp_core config) |

5. Strings MUST go through `S`. The verbatim strings f12 owns:

   - `Settings` (menu title)
   - `Choose a category to change your @1 settings` (subtitle; `@1` =
     `server.name` — the one genericised string, §0.5)
   - `Chat`, `Notifications`, `PvP`, `Visuals`, `Privacy`,
     `Scoreboard`, `General` (category buttons)
   - `Open @1 settings` (category tooltip)
   - `Settings - Chat` (category screen title — space, hyphen, space)
   - `Public Chat`, `Private Messages`, `Server Chat Messages`,
     `Server Hotbar Messages`, `Death Messages`,
     `Advancement Messages`, `Join/Leave Messages` (toggle labels)
   - `ON`, `OFF`, `Friends/Followed` (toggle values)
   - `Click to toggle` (toggle tooltip)
   - `Back`

   All from `shared/08-ui-strings.md §8.1, §8.2, §8.4, §8.5`.

   Note the **OCR conflict**: `Scoreboard` (4 readings) vs `Social`
   (1 reading) — use `Scoreboard`. And `Server Hotbar Messages` (4) vs
   `Server nowar messages` (1) — use the former.

6. Money is integer cents (not used here).

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: the toggle handler's registry lookup and the
   `smp_settings.set` write must be atomic, or a forged id racing a
   redraw can write a key that doesn't exist.

8. **Never trust the received setting id.** §8. Look it up in the
   registry and ignore unknown ids. T8.

9. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_settings.lua` covering T1 (category
   order), T5/T6 (toggle cycle/wrap), T7 (persistence + unknown-key
   preserve), T8 (forged id). Plus `friedcake/mods/smp_settings/test.lua`.

10. Commit on the branch, never on main. **Stage only your own paths**:

    ```
    git add friedcake/mods/smp_settings/ friedcake/dev-tests/test_settings.lua
    git commit -m "f12: settings registry and the seven-category menu"
    ```

    Never `git add -A`. Format:

    ```
    f12: <imperative summary>

    <body>
    ```

    Examples:

    - `f12: JSON store in player meta with unknown-key preservation`
    - `f12: setting registry with category and tri-state values`
    - `f12: Settings category menu with purple hover`
    - `f12: Settings - Chat toggle rows`

11. When T1–T9 pass, push:

    ```
    git push origin agent/f12-settings
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f12-settings`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- The canonical accessor name you picked (`get` vs `get_name`) and the
  normalisation the other specs need. The integrator reconciles.
- Every `PROPOSED` decision you made (cycle order, which settings are
  binary vs tri-state, the six unopened categories).
- Whether you registered any candidate settings for the unopened
  categories, and that they're `CLONE`/`PROPOSED` not `OBSERVED`.
- Any unresolved V-NN questions you made a `PROPOSED` decision on.

## When you get stuck

- The function name is inconsistent across specs (`get` vs `get_name`):
  pick one, implement it, note the normalisation in §10. Don't block.
- f11 hasn't landed its enforcement: you don't need it — you only
  store/present. T9 (the `/msg` integration) is f11's test, not yours.
- Six categories are unopened and unobserved: register only the seven
  Chat settings and the category titles. Do NOT invent settings for
  the six unopened categories — leave them empty and mark §10.
- The purple hue is sampled (`#7B2FBE`) and unverified: use it, mark
  it `PROPOSED`.
