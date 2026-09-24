# f09 — Homes

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_tp` (homes subsystem) |
| Phase | P4 |
| Depends on | `f08-teleport` (warm-up framework), `f13-ranks` (slot limits) |
| Frame evidence | **12 frames**, 00:00:43–00:01:16 |
| Confidence | **High.** The full menu tree was recorded. |

v0.1 §6.5 described a flat home grid with sneak-click to delete. **That is
wrong.** The observed interface is a tab row leading to a per-home submenu.
This file replaces it.

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/homes` | `/home` | `[id]` | Open the `Homes` menu, or teleport directly to a home | **OBSERVED** [F0055, F0061] |
| `/sethome` | — | `[name]` | Save the current position as a home | **OBSERVED** [F0055] |
| `/delhome` | — | `<id>` | Delete a home | LIVE [S24] |

The player types `/homes` [F0055]; the menu is titled `Homes` [F0061]. The
plural is the observed primary form.

## 3. Observed UI

### 3.1 `Homes` — the tab row [F0061]

![Homes menu](../../frames/frame_0061.jpg)

A **prompt menu** occupying roughly the top 20% of the screen, translucent
dark, with a yellow warning triangle beside the title.

```
Homes  ⚠
[ Home 1 ] [ Home 2 ] [ New Home ]                      [ Show More ]
           ↑ tooltip: "Home 1" / "Click to manage"
```

| Element | Text | Note |
|---|---|---|
| Title | `Homes` | |
| Tab 1..n | the home's name (`Home 1`, `Home 2`) | One tab per existing home |
| Tab | `New Home` | Follows the last home; equivalent to `/sethome` |
| Tab, far right | `Show More` | Paging affordance |
| Tooltip on a home tab | `<name>` then `Click to manage` | Two lines |

`Show More` sits at the far right, separated from the home tabs. The player in
the recording has 2 homes and 3 tabs before it, so `homes.tabs_before_more`
defaults to 3 — but that is an inference from one layout, not a measurement.

### 3.2 Per-home submenu [F0063, F0064, F0065, F0067, F0068, F0070, F0075]

![Home submenu](../../frames/frame_0064.jpg)

A **prompt menu**, middle third of the screen, titled with the home's own name
(`Home 2` [F0064], and after renaming, `rock` [F0075]), with the same warning
triangle.

```
Home 2  ⚠
  [ Teleport    ]  [ Change Icon ]
  [ Rename      ]  [ Delete      ]
        [ Back ]
```

A 2×2 grid with `Back` centred beneath. `Delete` renders with **red text** when
hovered [F0068] — the only observed colour-coded destructive action.

### 3.3 `Choose Icon` [F0066]

![Choose Icon](../../frames/frame_0066.jpg)

A tall **prompt menu**, roughly 60% of the screen.

```
Choose Icon  ⚠
        Search
  [                    ]
  [ Search ] [ Default ] [ Back ]

  Acacia Button
  Acacia Chest Boat
  Acacia Door
  … alphabetical, full item list, scrolling
```

The list is every registered item, sorted alphabetically by display name.
`Default` restores the standard icon; `Back` returns to the submenu without
changing it.

### 3.4 `Rename` [F0071, F0074]

![Rename](../../frames/frame_0071.jpg)

```
Rename  ⚠
  New Name
  [ Home 2            ]   ← pre-filled with the CURRENT name
  [ Save   ]
  [ Cancel ]
```

The field is **pre-filled with the existing name** and focused [F0071]. `Save`
and `Cancel` are stacked vertically, centred — not side by side.

### 3.5 Chat messages

| String | When | Frames |
|---|---|---|
| `Home set` | `/sethome` or `New Home` succeeded | F0055 |
| `Home deleted` | `Delete` confirmed | F0055 |
| `Home does not exist` | `/homes <unknown>` | F0055 |
| `You reached home limits` | slots exhausted (note the plural) | F0055 |
| `You renamed your home to @1` | `Save` in `Rename`; reconstructed from a partly garbled frame | F0089 |

### 3.6 Not observed

Teleport warm-up display, a delete confirmation step, the `Show More` target
screen, and behaviour at the slot limit beyond the chat message. All are
`PROPOSED` below.

## 4. Behaviour

1. **Slots.** `OBSERVED` that a limit exists (`You reached home limits`). Per
   tier [S17]:

   | Tier | Slots | Status |
   |---|---:|---|
   | default | 2 | LEGACY [S25]; the current default is undocumented |
   | tier1 (Donut+) | 9 | LIVE [S17] |
   | tier2 (Donut++) | 27 | LIVE [S17] |
   | tier3 (Donut+++), Media | 90 | LIVE [S17] |

2. **`/sethome` without a name** uses the next free slot, named `Home <n>`.
   `OBSERVED`: the recorded player's homes are `Home 1` and `Home 2` [F0061],
   and the speaker says "you should have home one but I have home two".
3. **Names** may be up to `homes.name_max` characters (`PROPOSED` 32). Donut
   raised its limit on 18 June 2026 [S16]. Renaming to `rock` [F0074] shows
   short free-form names are accepted.
4. **Teleport** applies the `f08` warm-up. Cancelled by movement or damage
   (`PROPOSED` — no warm-up is visible in the recording).
5. **Delete** MUST require confirmation (`PROPOSED`). Not observed: the
   recording cuts from the submenu to the result. The `Delete` button's red
   hover styling [F0068] suggests the interface treats it as destructive, but
   an intermediate confirm screen was never shown.
6. **Icons** are per-home, chosen from the full item list, defaulting to a bed
   (`PROPOSED`; the default icon is never seen unobscured).
7. **Rank expiry.** Existing homes stay usable; no new home may exceed the
   current limit [S17].
8. **Privacy.** Home coordinates MUST NOT be shown to other players, including
   through `/findplayer`.

## 5. Data schema

Homes live in the player record (`f01 §5`):

```lua
homes = {
  { id = 1, name = "Home 1", icon = "mcl_beds:bed_red_bottom",
    pos = { x = 1200, y = 64, z = -340 }, created = 1758500100 },
  { id = 2, name = "rock",   icon = "mcl_core:obsidian",
    pos = { x = -47114, y = 66, z = -12735 }, created = 1758500200 },
}
```

`name` is display text and is what the submenu title shows. `id` is stable
across renames.

## 6. Algorithms

```lua
function smp_tp.show_homes(player)
  local homes = smp_store.get_homes(player:get_player_name())
  local limit = smp_ranks.home_limit(player)
  local tabs = {}
  for i = 1, math.min(#homes, cfg.homes.tabs_before_more) do
    tabs[#tabs + 1] = home_tab(homes[i])                  -- tooltip: name / "Click to manage"
  end
  if #homes < limit then tabs[#tabs + 1] = button("New Home") end
  if #homes > cfg.homes.tabs_before_more then tabs[#tabs + 1] = button("Show More") end
  show_prompt(player, S("Homes"), tabs)
end

function smp_tp.on_new_home(player)
  local homes = smp_store.get_homes(player:get_player_name())
  if #homes >= smp_ranks.home_limit(player) then
    return chat(player, S("You reached home limits"))     -- exact observed string
  end
  local n = next_free_index(homes)
  smp_store.add_home(player, { id = n, name = S("Home @1", n),
                               pos = player:get_pos(), created = os.time() })
  chat(player, S("Home set"))
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `homes.slots_default`, `homes.slots_tier1`, `homes.slots_tier2`, `homes.slots_tier3` | `{default = 2, tier1 = 9, tier2 = 27, tier3 = 90}` | LIVE [S17]; default LEGACY [S25] |
| `smp_tp.homes.name_max` | 32 | PROPOSED |
| `smp_tp.homes.tabs_before_more` | 3 | **OBSERVED** [F0061] (inferred from one layout) |
| `smp_tp.homes.default_icon` | `mcl_beds:bed_red_bottom` | PROPOSED |
| `smp_tp.homes.delete_confirm` | true | PROPOSED |

## 8. Mineclonia implementation

- Both screens are **prompt menus** (`04-ui-kit.md §4.1`): `formspec_version[6]`,
  `bgcolor[#000000C0]`, no inventory list.
- Tab row: `item_image_button[]` per home using its chosen icon, with
  `tooltip[<name>;<name>\nClick to manage]`.
- Submenu: four `button[]` in a 2×2 grid plus a centred `Back`. Style `Delete`
  with `style[delete;textcolor=red]` to match [F0068].
- `Choose Icon`: `field[]` for search, three `button[]`, and a paged
  `item_image_button[]` grid over `core.registered_items` sorted by
  `get_description()`. A `textlist[]` is acceptable if icons prove too costly,
  but the observed list shows icons beside names.
- `Rename`: `field[]` pre-filled via the third field argument, plus two stacked
  `button[]`.
- Teleport goes through the `f08` warm-up. Re-validate the home id on receipt:
  the client field is untrusted and the home may have been deleted meanwhile.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | `/sethome` at the slot limit produces exactly `You reached home limits` and creates nothing |
| T2 | `/sethome` below the limit produces exactly `Home set` and the new tab is named `Home <n>` |
| T3 | Renaming updates the submenu title and every tab label; the id is unchanged |
| T4 | Deleting produces exactly `Home deleted` and removes the tab |
| T5 | `/homes <unknown>` produces exactly `Home does not exist` |
| T6 | A player with more homes than `homes.tabs_before_more` sees `Show More` |
| T7 | Icon choice persists across a server restart |
| T8 | A home id deleted while its submenu is open fails safely on the next click |
| T9 | `/findplayer` never reveals a home position |

## 10. Open questions

| Id | Question |
|---|---|
| V-15 | **Closed.** Default slot count still unconfirmed, but the menu structure is now known |
| V-31 | Does `Delete` show a confirmation step? Not visible in the recording |
| V-32 | What does `Show More` open — a second tab page, or a list screen? |
| V-33 | Is there a teleport warm-up, and is it displayed? None visible |
| V-34 | What is the default home icon? |
| V-35 | Is the `Choose Icon` list every registered item, or a curated subset? 19 alphabetical entries were visible, all vanilla |
| V-88 | Delete confirmation (implementation choice while V-31 stays open): a prompt titled `Delete @1?` with `Cancel` (red, left) and `Delete` (red text, right); confirming chats `Home deleted` and returns to the `Homes` row. The intermediate screen, its title and the return target are **PROPOSED** — never observed |
| V-89 | Name/usage refusals (**PROPOSED**, no refusal was ever observed): `Home name is too long`, `Home name cannot be empty`, `Usage: /delhome <id>` |
| V-90 | `Choose Icon` paging (**PROPOSED**): `Prev` / `Next` buttons, and the title gains `(Page @1)` only when page > 1 — the observed screen was page 1 with the plain title [F0066] |
| V-91 | Home names are not required to be unique; ids are. `/homes <key>` matches a numeric id first, then the first case-insensitive name match (**PROPOSED**) |
| V-92 | `/sethome <name>` where a home of that name already exists creates a NEW home rather than moving the old one (**PROPOSED**; never observed) |
| V-93 | `Show More` (implementation choice while V-32 stays open): re-renders the tab row with ALL home tabs (`item_image_button` per home, wrapped 7 per row) and hides `Show More` itself. No second page mechanism (**PROPOSED**) |

## 10. Fix-wave record (fix brief, 2026-09-25)

| Row | Outcome | Evidence |
|---|---|---|
| H1 | VERIFIED | `smp_tp/init.lua:33` `dofile(modpath .. "/homes.lua")` present; `grep -n 'dofile.*homes' friedcake/mods/smp_tp/init.lua` confirms |
| H2 | VERIFIED | `smp_tp/mod.conf:3-4` `depends = smp_core, smp_store, mcl_worlds, mcl_spawn` / `optional_depends = mcl_title, mcl_vars, smp_ranks` present |
| H3 | VERIFIED + HARNESS HONESTY | No `core.modpath` in `smp_tp/` (`grep -r 'core\.modpath' friedcake/mods/smp_tp/` → no matches); `test_homes.lua:381` loads `init.lua` which wires `homes.lua` (real load path); test fails if `homes.lua` removed from `init.lua` (registration-count assertion via `cmd("homes")` in `test_homes.lua:188-196`) |
| H4 | FIXED (code/spec aligned; mirror change proposed) | Code reads 4 keys via `setting()` helper (homes.lua:62-65) → `smp_tp.homes.{name_max,tabs_before_more,default_icon,delete_confirm}`; §7 table updated to match code default for `default_icon` (`mcl_beds:bed_red_bottom`); `shared/06` rows 99-102 have correct prefixed names; mirror default correction proposed in §11.4; `test_config_mirror.lua` passes for homes keys (no violations) |

## 11. Proposed shared changes

The f09 agent's edit surface is `friedcake/mods/smp_tp/homes.lua`,
`friedcake/mods/smp_tp/test_homes.lua` and
`friedcake/dev-tests/test_homes.lua` (plus this file). The following
integration edits are needed and are **not** made by the f09 agent:

1. **`friedcake/mods/smp_tp/init.lua`** (owned by f08) — load the
   subsystem, after the `commands.lua` line:

   ```lua
   dofile(core.modpath("homes.lua"))
   ```

   ⚠ Engine note for the integrator: `smp_tp/init.lua` currently calls
   `core.modpath(...)`, which does **not exist** in Luanti (the engine
   provides only `core.get_modpath(modname)` — verified against
   `~/dev/luanti`; the dev-test harness defines `core.modpath` itself,
   which is why `test_tp.lua` passes). All `dofile(core.modpath(...))`
   calls in `init.lua` must become
   `dofile(core.get_modpath("smp_tp") .. "/" .. ...)` before `smp_tp`
   can load in-game. f09 does not edit f08's file; flagging here.

2. **`friedcake/mods/smp_tp/mod.conf`** (owned by f08) — homes read and
   write player records, so declare the dependency:

   ```
   depends = smp_core, smp_store, mcl_worlds, mcl_spawn
   optional_depends = mcl_title, mcl_vars, smp_ranks
   ```

   (`smp_ranks` is optional: `smp_tp.homes.home_limit` falls back to the
   §4.1 slot table with a `TODO(f13)` until `smp_ranks.home_limit`
   exists.)

3. **`spec/shared/08-ui-strings.md`** (integrator mirror) — the
   observed homes strings are already catalogued there (§8.1, §8.2,
   §8.5, §8.6). The new **PROPOSED** strings this implementation adds
   and should be listed as PROPOSED, not observed:

   | String | Screen / use |
   |---|---|
   | `Home name is too long` | `/sethome`, `Rename` validation (V-89) |
   | `Home name cannot be empty` | `Rename` validation (V-89) |
   | `Usage: /delhome <id>` | `/delhome` with no argument (V-89) |
   | `Delete @1?` | delete confirmation title (V-88) |
   | `Prev`, `Next` | `Choose Icon` paging (V-90) |
   | `Choose Icon (Page @1)` | `Choose Icon` title on page > 1 (V-90) |

4. **`spec/shared/06-config-reference.md`** (integrator mirror, D7
   reconciliation) — the D7 ruling renamed the legacy `homes.*` rows to
   the `smp_tp.homes.*` keys the code actually reads. The mirror at
   `06:99-102` now carries the correct prefixed names. One residual
   mismatch remains: the default for `smp_tp.homes.default_icon` in the
   mirror is `bed` (marked **OBSERVED** [F0066]), but the code's actual
   default is the Mineclonia itemstring `mcl_beds:bed_red_bottom` (the
   default bed is never seen unobscured [§3.6], so the frame cannot
   confirm the spelling). This implementation uses the valid itemstring.
   **Proposed mirror change:** update the default cell for
   `smp_tp.homes.default_icon` from `bed` to `mcl_beds:bed_red_bottom`
   and change the status from **OBSERVED** to PROPOSED.

5. **`/smp test` loader** (f01/f04 concern) — `test_homes.lua` follows
   the `{passed, failed, lines}` contract and is already executed by
   `friedcake/dev-tests/test_homes.lua`; wire it into `/smp test` when
   the generic loader lands.

No changes are needed to `spec/shared/02-architecture.md`,
`04-ui-kit.md`, `05-command-reference.md` (the `/homes`, `/home`,
`/sethome`, `/delhome` rows already exist) or `06-config-reference.md`
beyond the `default_icon` default correction above. The `homes.slots_*`
rows (without the `smp_tp.` prefix) are read by `smp_ranks`, not by
`homes.lua`; their renaming to `smp_tp.homes.slots_*` is tracked in the
D7 follow-up (P2) and is out of f09's direct scope.
