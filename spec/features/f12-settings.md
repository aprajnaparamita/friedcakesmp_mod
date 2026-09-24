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
   (`OBSERVED`). The seven categories, in observed order — `chat`,
   `notifications`, `pvp`, `visuals`, `privacy`, `scoreboard`, `general` —
   are **OBSERVED** [F0237] (documented here because D3 struck the §7
   `settings.categories` config-key row; the fact itself is unchanged).
   Each button opens `Settings - <Category>` (`OBSERVED` for
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
7. **Defaults.** The four chat-adjacent settings (`chat.private_messages`,
   `chat.death_messages`, `chat.advancements`, `chat.join_leave`) default to
   `FRIENDS_FOLLOWED` so a fresh profile reproduces the observed first-open
   screen [F0242] (§0.5 fidelity) — settled by D3, 2026-09-24. Every other
   setting defaults to its most permissive value (`ON`) — `PROPOSED`.
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
  default  = "FRIENDS_FOLLOWED",
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
| F12-A | **Canonical accessor name: `smp_settings.get(player_or_name, id)`.** f11 §6 and `smp_orders/routing.lua` already call `get`; f01 §6 and `claim-f08` call `get_name`. Only `get` is implemented — integrator should normalise `get_name` → `get` at those two call sites |
| F12-B | **Defaults conflict.** §4.7 says "most permissive" and §5.1's sample shows `default = "ON"` for `chat.private_messages`, but §5's stored schema and the first-open frames [F0242] show `Friends/Followed`. Implemented: four rows (`private_messages`, `death_messages`, `advancements`, `join_leave`) default `FRIENDS_FOLLOWED`, the rest `ON`, so a fresh profile reproduces the observed screen (§0.5 fidelity). Reverting to §4.7 is one `default` line per setting in `chat.lua` — **decided: D3, 2026-09-24 — §4.7 rewritten to the implemented defaults and the §5.1 sample set to `FRIENDS_FOLLOWED`; code unchanged.** |
| F12-C | §7's `settings.cycle_order` is read from config (comma list); `settings.categories` is NOT — the seven categories are registered in observed order in code (structure, not a rate/timer per G3). PROPOSED: leave as code, or wire a config read if the integrator wants it — **decided: D3, 2026-09-24 — leave as code; the `settings.categories` row is struck from §7 and the OBSERVED list moved to §4.1 prose.** |
| F12-D | `server.name` (§7, the genericised key) is read and falls back to `Donut SMP`. The engine's own setting is `server_name` (verified in luanti `builtin/settingtypes.txt`) — deliberately NOT aliased; the two must not be conflated |

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

### Implementation notes (f12 agent)

Decisions taken while building `friedcake/mods/smp_settings/`. Open items
are in the table above (F12-A … F12-D); the rest are settled here.

- **Accessor name (F12-A).** One canonical pair, one signature:
  `smp_settings.get(player_or_name, id)` → `value | nil`,
  `smp_settings.set(player_or_name, id, value)` → `boolean`.
  `player_or_name` accepts a `PlayerRef` or an online player's name;
  normalisation lives in `smp_settings.player_name`. `get_name` is not
  implemented.
- **V-29 decided:** cycle order `ON → FRIENDS_FOLLOWED → OFF`, read from
  config `settings.cycle_order` (comma list, this order as default).
  Binary settings cycle `ON → OFF` (§5.1 sample, §4.4); `FRIENDS_FOLLOWED`
  is simply not in their value domain.
- **V-37 decided:** tri-state = `private_messages`, `death_messages`,
  `advancements`, `join_leave` (all three values appear in §3.2's
  "Values" column). Binary = `public`, `server_messages`,
  `hotbar_messages` (only `ON`/`OFF` observed). If a later frame shows
  `Friends/Followed` on a binary row, adding it is one `values` line.
- **V-38 decided:** `Scoreboard` (majority of frames), per §3.1.
- **V-36 / V-39:** all six unopened categories are registered with their
  titles only and render empty screens (title + `Back`, zero rows).
  None of the §10 candidate keys (`eco.pay_accept`, `eco.order_alerts`,
  `tp.tpa_enabled`, `privacy.show_money`, `combat.keep_pearls_on_death`,
  …) are registered, so consumers calling `get` on them receive `nil`
  and apply their own fallback until their category opens with evidence.
- **PROPOSED decisions (new behaviour, not in the OBSERVED parts):**
  the defaults conflict (F12-B), purple `#7B2FBE` applied to every
  button's `:hovered` state (single sampled hue, §3.1 marks it
  PROPOSED), screen geometry (sizes/pitch, follows the §4.9 prompt-menu
  scale), the `Click to toggle` row tooltip (§4.9 pattern, row hover not
  captured on video), `/settings`'s house-style description string, and
  keeping `settings.categories` as code (F12-C) — decided: D3,
  2026-09-24, §4.7 rewritten, row struck.
- **Storage limitation:** player meta exists only for online players,
  so `get` on an offline name returns the registered default and `set`
  on an offline name returns `false`. f01's `get_name(target, …)` calls
  therefore see defaults for offline targets — flagged for f01/f11.
- **`/smp test smp_settings`:** `mods/smp_settings/test.lua` follows the
  same loader contract as smp_orders' (f04 §10); the generic test loader
  is still integrator-owned. Headless coverage runs today via
  `luajit friedcake/dev-tests/test_settings.lua` (T1–T8, plus the
  in-game suite; T9 is f11's).

### Fix-wave record (fix brief, 2026-09-25)

Branch `agent/f12-settings-fixes` (base `2b5f16c`), brief
`fixes/f12-settings.md`. Every row F12-1…F12-7 with its outcome and
file:line evidence (line numbers at this commit):

| Row | Outcome | Evidence |
|---|---|---|
| **F12-1** | **CLOSED** | The warning triangle is drawn right of the title in **both** renders as the correct three-byte U+26A0 sequence `"\226\154\160"` (same bytes as `smp_tp/homes.lua:72`, never a truncated single byte): constant `friedcake/mods/smp_settings/formspec.lua:35`; category menu `Settings ⚠` `:75-76`; category screen `Settings - Chat ⚠` `:122-123`. The title's x is still `centre_x(w, title)` — the glyph is appended after the title, so no observed pixel moves. Tests assert the element in the category-menu render **and** the `Settings - Chat` render, the exact 3-byte sequence, and the absence of a lone `\241` byte: `friedcake/dev-tests/test_settings.lua:353-370`, in-mod `friedcake/mods/smp_settings/test.lua:199-217`. The glyph's *meaning* stays open at V-28 (out of scope per brief); §0.5 rule 2 makes the observed layout normative. |
| **F12-2** | **ESCALATED → D3** | `settings.categories` is still never read — the only config read is `settings.cycle_order` (`smp_settings/init.lua:39-45`, key at `:43-44`); the seven categories are registered in code (`init.lua:88-101`, chat at `chat.lua:18-21`). **Code side unchanged by this brief** (never change the F12-2 code). D3 ruled **A** on 2026-09-24 and both halves were applied before this brief: §7 declares only `settings.cycle_order` + `server.name` (`:210-213`), the OBSERVED seven-category list lives in §4.1 prose (`:126-132`), F12-C is annotated decided (`:256`), and the mirror carries the strike marker `spec/shared/06-config-reference.md:125`. Nothing is outstanding for the ruling to land as; those are the single-edit sites if D3 is ever re-opened. |
| **F12-3** | **ESCALATED → D3** (doc-side only; **no code change**) | The §4.7 amendment this brief asks to draft already landed when D3=A was executed: §4.7 item 7 now reads that the four chat-adjacent settings default to `FRIENDS_FOLLOWED` — "settled by D3, 2026-09-24" (`:144-148`) — and the §5.1 sample shows `default = "FRIENDS_FOLLOWED"` (`:189`); F12-B is annotated decided (`:255`). Code untouched: `chat.lua:41,62,69,76` default `FRIENDS_FOLLOWED`, `chat.lua:34,48,55` default `ON`. T1's observed-value assertions are unchanged: `dev-tests/test_settings.lua:332-340` (`Public Chat: ON`, `Private Messages: Friends/Followed`, …) and in-mod `test.lua:92-100`. |
| **F12-4** | **CLOSED** | T9 delivered through f11's harness — no second harness built: `friedcake/dev-tests/test_social.lua:647-673` asserts the recipient's `chat.private_messages = FRIENDS_FOLLOWED` (`:650-652`), that the sender is a stranger in both directions (`:653-656`), that `/msg` answers exactly `This user only accepts messages from friends or followed players` (`:660-663`, T9 leg `:668-669`), and that nothing is delivered (`:670-673`); header cross-reference `:29-31`. `luajit friedcake/dev-tests/test_social.lua` exits 0. `dev-tests/test_settings.lua:5-6` points at the leg (T9 stays out of the settings harness). |
| **F12-5** | **CLOSED** | `smp_settings/init.lua:218` — `description = S("Open the settings menu")`, terminal full stop removed (shared §0.5 rule 4). Asserted at `dev-tests/test_settings.lua:517-522` and in-mod `test.lua:220-226`. |
| **F12-6** | **CLOSED** | The duplicate `local fs = smp_settings.fs` was removed; exactly one remains in `init.lua` at `:82` (the only other occurrence in the mod is `test.lua:31`, that file's own local). No behaviour change — `fs` is first used at `init.lua:110`. |
| **F12-7** | **ESCALATED → D7** | `settings.cycle_order` is declared in §7 (`:212`) and read by the code (`init.lua:43-44`). The mirror-addition proposal already exists in `## Proposed shared changes` item 2 below — **referenced, not duplicated** (the brief cites `f12-settings.md:324-329`, which is the same proposal block before P1's D3 edits shifted it). D7 ruled **A** on 2026-09-24 and P2 applied the mirror half before this brief: `spec/shared/06-config-reference.md:124` now carries `settings.cycle_order`. **No hand-edit to `shared/06` was made**, and `dev-tests/test_config_mirror.lua` is green in both directions. |

**fixes/README.md annotation** (this agent may not write there — for the
overseer to apply):

```text
- f12-settings — F12-1 closed (⚠ in both renders + byte-exact tests) · F12-2, F12-3 ESCALATED → D3 (ruled A; pre-applied, verified) · F12-4 closed (T9 leg in test_social.lua) · F12-5, F12-6 closed (hygiene) · F12-7 ESCALATED → D7 (mirror applied at shared/06:124, verified)
```

## Proposed shared changes

*(for the integrator — this agent does not edit `spec/shared/`)*

1. **`spec/shared/08-ui-strings.md` §8.5** — add the category-button
   tooltip row observed at [F0237, F0238, F0239, F0241]:

   | String | Where | Source |
   |---|---|---|
   | `Open @1 settings` | A Settings category button | OBSERVED [F0237, F0238, F0239, F0241] |

2. **`spec/shared/06-config-reference.md`** — add `settings.cycle_order`
   (§7 of this file declares it but the mirror does not carry it):

   | Key | Type | Default | Tags | Owner |
   |---|---|---|---|---|
   | `settings.cycle_order` | list | `{ON, FRIENDS_FOLLOWED, OFF}` | PROPOSED (V-29) | f12 |

3. **`spec/features/f01-*.md` §6 / claim-f08** — normalise
   `smp_settings.get_name(...)` → `smp_settings.get(...)` (F12-A).
