# f12 — Player Settings

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_settings` |
| Phase | P7 |
| Depends on | `smp_core` |
| Frame evidence | **19 frames**, 00:03:51–00:04:14 |
| Confidence | **High for structure**, partial for content — one of seven category screens was opened |

> **This file is a rewrite, not a revision.** v0.1 §11 listed categories
> Chat / Economy / Teleport / General / Social and fifteen boolean settings
> drawn from clone plugins [C1]. The observed menu has **seven different
> categories** and **three-valued** toggles. Almost none of the v0.1 table
> survives contact with the evidence. The clone-derived settings are retained
> below only as candidates for the six unopened categories, clearly marked.

## 2. Commands

| Command | Arguments | Behaviour | Status |
|---|---|---|---|
| `/settings` | — | Open the `Settings` category menu | **OBSERVED** [F0234–F0236] |

## 3. Observed UI

### 3.1 `Settings` — category menu [F0236–F0241, F0253]

![Settings](../../frames/frame_0237.jpg)

A **prompt menu**, middle 40% of the screen, translucent dark, warning triangle
beside the title.

```
Settings  ⚠
   Choose a category to change your Donut SMP settings

   [ Chat        ]  [ Notifications ]
   [ PvP         ]  [ Visuals       ]
   [ Privacy     ]  [ Scoreboard    ]
            [ General ]
```

Seven categories in a 2-column grid with `General` centred beneath:

| # | Category | Hover tooltip |
|---|---|---|
| 1 | `Chat` | `Open Chat settings` [F0237, F0241] |
| 2 | `Notifications` | `Open Notifications settings` [F0239] |
| 3 | `PvP` | `Open PvP settings` [F0238] |
| 4 | `Visuals` | `Open Visuals settings` [F0236, F0240] |
| 5 | `Privacy` | — |
| 6 | `Scoreboard` | — |
| 7 | `General` | — |

The tooltip pattern is `Open @1 settings`. The hovered button is highlighted
with a **purple** background [F0236].

> **OCR conflict.** Category 6 reads `Scoreboard` in F0237, F0238, F0239 and
> F0241, and `Social` in F0240. Four readings to one: `Scoreboard` is taken as
> correct, reinforced by the observed scoreboard sidebar [F0287]. Recorded, not
> silently resolved.

The subtitle names the server and is the one genericised string
(`shared/00-conventions.md §0.5`):
`Choose a category to change your @1 settings`.

### 3.2 `Settings - Chat` [F0242–F0246, F0254, F0255]

![Settings - Chat](../../frames/frame_0245.jpg)

The only category screen opened in the recording.

```
Settings - Chat  ⚠
  [ Public Chat: ON                          ]  ← tooltip "Click to toggle"
  [ Private Messages: Friends/Followed       ]
  [ Server Chat Messages: ON                 ]
  [ Server Hotbar Messages: ON               ]
  [ Death Messages: Friends/Followed         ]
  [ Advancement Messages: Friends/Followed   ]
  [ Join/Leave Messages: Friends/Followed    ]
  [ Back                                     ]
```

Seven toggles in a single vertical column, then `Back`. The title is
`Settings - Chat` — **space, hyphen, space**, not the `->` used by the orders
tree.

| Setting | Values seen | Frames |
|---|---|---|
| `Public Chat` | `ON` [F0245], `OFF` [F0242] | both states observed, toggling live |
| `Private Messages` | `Friends/Followed` | F0242–F0246 |
| `Server Chat Messages` | `ON` | F0242–F0246 |
| `Server Hotbar Messages` | `ON` | F0243, F0245, F0246, F0254 |
| `Death Messages` | `Friends/Followed` | F0242–F0246 |
| `Advancement Messages` | `Friends/Followed` | F0242–F0246 |
| `Join/Leave Messages` | `Friends/Followed` | F0242–F0246 |

> **OCR conflict.** `Server Hotbar Messages` reads as `Server nowar messages`
> in F0242 alone. Four readings to one; the majority wins.

**`Public Chat` was toggled on camera** — `OFF` at F0242 and `ON` at F0245 —
which confirms the label-carries-the-value pattern and in-place redraw
(`04-ui-kit.md §4.5`).

### 3.3 The `Friends/Followed` state

The decisive finding. Four of the seven chat settings sit at
`Friends/Followed`, a third state between on and off, and it is **enforced**:
`/msg` to a stranger returns
`This user only accepts messages from friends or followed players` [F0276–F0285].

Settings are therefore three-valued, and the friends/follow system (`f11`) is a
dependency of the settings model rather than a peer of it.

### 3.4 Not observed

The contents of Notifications, PvP, Visuals, Privacy, Scoreboard and General;
the cycle order of the three states; whether every category uses the same
toggle-row pattern; whether any category has a non-toggle control.

## 4. Behaviour

1. **Categories.** `/settings` opens a seven-button category menu
   (`OBSERVED`). Each button opens `Settings - <Category>` (`OBSERVED` for
   Chat; `PROPOSED` by symmetry for the rest).
2. **Toggles.** A setting is a button labelled `<Name>: <Value>`. Clicking
   advances to the next value and redraws in place (`OBSERVED`).
3. **Value domain.** `ON`, `OFF`, `Friends/Followed` (`OBSERVED`). Not every
   setting need accept all three: `Server Chat Messages` and
   `Server Hotbar Messages` are plausibly binary, but only `ON` was seen.
4. **Cycle order.** `PROPOSED` `ON → Friends/Followed → OFF → ON`. Never
   observed; a binary setting cycles `ON → OFF`.
5. **Enforcement** belongs to the consuming mod, not to `smp_settings`, which
   only stores and presents values. `f11` enforces the chat settings.
6. **Persistence.** JSON in player meta `smp:settings`. Unknown keys are
   preserved on write so a downgrade does not discard a newer setting.
7. **Defaults.** Every setting defaults to its most permissive value except
   where stated. `PROPOSED`.
8. **Back** returns to the category menu; closing the category menu closes the
   interface.

## 5. Data schema

Player meta `smp:settings`, JSON:

```json
{
  "chat.public":            "ON",
  "chat.private_messages":  "FRIENDS_FOLLOWED",
  "chat.server_messages":   "ON",
  "chat.hotbar_messages":   "ON",
  "chat.death_messages":    "FRIENDS_FOLLOWED",
  "chat.advancements":      "FRIENDS_FOLLOWED",
  "chat.join_leave":        "FRIENDS_FOLLOWED"
}
```

Values are the strings `ON`, `OFF`, `FRIENDS_FOLLOWED`. Storing a tri-state as
a string rather than a boolean is deliberate: the observed domain is not
boolean and a boolean schema would have to be migrated later.

### 5.1 Setting registry

Categories and settings are registered, not hard-coded, so unopened categories
can be filled in as evidence arrives:

```lua
smp_settings.register_category("chat", { title = S("Chat"), order = 1 })
smp_settings.register("chat.public", {
  category = "chat",
  label    = S("Public Chat"),
  values   = { "ON", "OFF" },
  default  = "ON",
})
smp_settings.register("chat.private_messages", {
  category = "chat",
  label    = S("Private Messages"),
  values   = { "ON", "FRIENDS_FOLLOWED", "OFF" },
  default  = "ON",
  display  = { FRIENDS_FOLLOWED = S("Friends/Followed") },
})
```

## 6. Algorithms

```lua
function smp_settings.on_toggle(player, id)
  local def = smp_settings.registered[id]
  if not def then return end                        -- untrusted field
  local cur  = smp_settings.get(player, id)
  local i    = index_of(def.values, cur) or 0
  local next = def.values[(i % #def.values) + 1]    -- cycle, wrapping
  smp_settings.set(player, id, next)
  smp_settings.show_category(player, def.category)  -- redraw in place
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `settings.categories` | `{chat, notifications, pvp, visuals, privacy, scoreboard, general}` | **OBSERVED** [F0237] |
| `settings.cycle_order` | `{ON, FRIENDS_FOLLOWED, OFF}` | PROPOSED |
| `server.name` | `Donut SMP` | **OBSERVED** [F0236] |

## 8. Mineclonia implementation

- Both screens are **prompt menus**. Category menu: seven `button[]` in a 2×2×2
  grid plus a centred seventh, each with
  `tooltip[<id>;Open <Category> settings]`.
- Toggle rows: `button[0.5,y;9,0.8;toggle_<id>;<Label>: <Value>]` with
  `tooltip[toggle_<id>;Click to toggle]`. The value is **inside the label**;
  do not use `checkbox[]`, which cannot express three states and would not
  match.
- Highlight the hovered button purple:
  `style[<id>:hovered;bgcolor=#7B2FBE]` (sampled from [F0236]; exact hue
  unverified).
- Never trust the received setting id — look it up in the registry and ignore
  unknown ids.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | `/settings` shows exactly seven categories in the observed order |
| T2 | Each category button's tooltip reads `Open <Category> settings` |
| T3 | The subtitle substitutes `server.name` and reads `Choose a category to change your <name> settings` |
| T4 | `Settings - Chat` shows the seven observed toggles in the observed order, then `Back` |
| T5 | Clicking `Public Chat: ON` yields `Public Chat: OFF` and redraws without closing |
| T6 | A tri-state setting cycles through all three values and wraps |
| T7 | Settings survive a restart; an unknown key in stored JSON is preserved |
| T8 | A forged setting id in a received formspec field changes nothing |
| T9 | `Private Messages: Friends/Followed` actually blocks a stranger's `/msg` with the exact observed refusal (integration with `f11`) |

## 10. Open questions

| Id | Question |
|---|---|
| V-16 | **Closed as "v0.1 was wrong."** Categories and the Chat contents are now known |
| V-29 | What is the cycle order of `ON` / `Friends/Followed` / `OFF`? |
| V-36 | Contents of Notifications, PvP, Visuals, Privacy, Scoreboard and General |
| V-37 | Which settings are binary and which are tri-state? Only `Public Chat` was seen in two states |
| V-38 | Is category 6 `Scoreboard` or `Social`? Four frames to one favour `Scoreboard` |
| V-39 | Where did v0.1's clone-derived settings go — `pay_accept`, `ah_alerts`, `order_alerts`, `tpa_enabled`, `auto_accept`, `keep_pearls_on_death`? `keep_pearls_on_death` is documented as living under General [S20]; the rest are unplaced |

### Candidate settings for the unopened categories

Carried from v0.1 as **candidates only**. Do not implement as observed fact.

| Candidate | Likely category | Status |
|---|---|---|
| Accept `/pay` | Privacy | CLONE [C1] |
| Payment notifications | Notifications | CLONE [C1] |
| Auction sale notifications | Notifications | CLONE [C1] |
| Order delivery notifications | Notifications | CLONE [C1] |
| Accept `/tpa`, `/tpahere` | Privacy | CLONE [C1] |
| Auto-accept teleports | Privacy | LIVE [S26] |
| Keep thrown pearls on death | General | LIVE [S20] |
| Night vision | Visuals | LIVE [S28] |
| Friend join and leave notices | Notifications | PROPOSED |
