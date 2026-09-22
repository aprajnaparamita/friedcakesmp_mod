# f16 — Legacy Features (Removed from the Reference Server)

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_crates`, `smp_afk`, `smp_teams`, `smp_duels`, `smp_servershop` — all optional |
| Phase | P8 |
| Depends on | crates: `f01`; afk: `f06`; teams: `f09` (team home), `f10` (friendly fire), `f11` (team chat); duels: `f08`, `f10`; servershop: `f01` |
| Frame evidence | **0 frames** — everything here was removed from the reference server before the video was recorded |
| Confidence | **LEGACY throughout.** Documented, but as history. Nothing in this file is verified against the live server; layouts are proposals in the observed grammar. |

These features were removed from Donut SMP: crates and the AFK zone in one
update [S11][S8], Teams and Duels on 2 June 2026 [S12][S13], the fixed-price
shop on 17 June 2026 [S7]. They are specified as optional modules because
private servers recreating "classic" Donut gameplay will want them — and
because the shard economy (`f06`) originally depended on the AFK zone.

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/afk` | — | — | Teleport to the AFK zone | LEGACY [S24][S8] |
| `/warp crates`, `/crates` | — | — | Go to the crates area | LEGACY [S11][S25]; `/crates` CLONE [C1] |
| `/team` | — | subcommands in §4.3 | Teams | LEGACY [S12] |
| `/duel` | — | `<player>`; `draw <player>` | Duels | LEGACY [S13] |

## 3. Observed UI

**None by definition.** Proposed screens, in the observed grammar
(`shared/04-ui-kit.md`), to be treated as placeholders:

- **Crate choice** — a prompt menu titled with the crate name showing seven
  item buttons; tooltip per item follows the listing-tooltip shape without a
  price line.
- **Team menu** — a prompt menu `Team` with member list and the permission
  toggles as tri-state rows (`f12` toggle grammar).
- **Fixed-price shop** — a container menu `<Category> (Page N)` with
  category tabs, item slots and a `How many?` numeric prompt for quantity.

![SS-22: Crate choice menu](../../screenshots/SS-22-crate-choice.png)
![SS-30: Team menu (historical)](../../screenshots/SS-30-team-menu.png)

## 4. Behaviour

### 4.1 Crates and keys (`smp_crates`)

1. Five crates, each opened with a matching key [S11]:

| Crate | Rewards |
|---|---|
| Common | Diamond armour and tools |
| Prime | Netherite armour, mace, netherite sword or crossbow |
| Gold | Any one spawner |
| Amethyst | Amethyst items (`f06`) |
| Crimson | Netherite armour, sword, axe or pickaxe |

2. Keys were **account balances**, not items, obtained from an hourly
   "keyall" and from the store [S11]. Shard shop prices on 26 February 2026:
   Prime key 2,000 shards, Crimson key 2,500; Gold and Amethyst keys already
   removed [S8].
3. Crates were opened at `/warp crates` [S11][S25]. Each opening presented
   **seven rewards, from which the player chose one** [S11].
4. **Implementation.** Crate nodes at spawn whose right-click opens the
   choose-one-of-seven menu; key balances in the player record (`keys`,
   `f01 §5.1`); keyall grants every online player the configured keys every
   `legacy.keyall_interval` (3,600 s, `PROPOSED` distribution). Because the
   player chooses, no randomness is required.
5. Node-menu rules from `shared §2.6` R7 apply: re-check node, key balance
   and distance on every action.

### 4.2 AFK zone (`smp_afk`)

1. `/afk` teleported players to an AFK area [S24] earning
   `legacy.afk_shards_per_min` (1) shard per minute [S8].
2. Donut+ and Media earned shards anywhere under this system [S8][S17]; the
   Shard Potion of Haste multiplied AFK shard gain by four [S9].
3. **Implementation.** A configured box region checked every 5 s, awarding
   shards for each full minute inside. The June 2026 shard system (`f06`,
   1 per 10 minutes everywhere [S8]) replaced this; enable `smp_afk` only
   with `shards.interval` disabled to avoid double-paying.

### 4.3 Teams (`smp_teams`)

Removed 2 June 2026 [S12].

1. `/team create <name>`, `/team disband`, `/team invite <player>` (requires
   the invite permission), `/team join <inviter>`; at most
   `legacy.team_max_members` (50) [S12]. `/team leave` and `/team kick` from
   clones [C1].
2. **Team home.** `/team sethome` and `/team home`; the team home also
   appeared as the **leftmost `/homes` slot** [S12]. Solo players created
   one-person teams to gain the extra home [S12]. Integration with `f09`:
   when `smp_teams` is loaded, the homes tab row gains the team home first.
3. **Team chat.** `/team chat` toggles team-only chat and hides public chat;
   `/team chat <message>` sends a single message [S12].
4. **Permissions** granted by the owner: invite and kick, teleport to the
   team home, set the team home, team chat. Members have only team chat by
   default; the creator holds every permission [S12].
5. **Friendly fire.** A team PvP toggle, with no combat tags between
   teammates [C1] — integration with `f10`'s `pvp_allowed`.

### 4.4 Duels (`smp_duels`)

Removed 2 June 2026 [S13].

1. `/duel <player>` issued a direct challenge; players could also queue at
   the duel building at spawn, where random matches showed the opponent's
   name and win percentile; draws were requested with `/duel draw <player>`
   [S13].
2. Matchmaking considered win rate and gear tier — a diamond-equipped
   player was never randomly matched against netherite [S13].
3. Players fought with their own survival gear [S13].
4. **Implementation.** Pre-built arenas far from the playable area, restored
   from a schematic after each match (`core.place_schematic`); gear tier is
   derived from armour and weapon materials. Whether the loser's items
   passed to the winner is undocumented — configurable
   (`legacy.duels_keep_inventory`, `PROPOSED` true).
5. The current equivalent on the live server is `/rtpqueue` (`f08`).

### 4.5 Kill shards

10 shards were awarded for directly killing another player [S8], with
anti-farming restrictions [S1]. `PROPOSED` restrictions: no reward for the
same killer–victim pair within one hour, for victims with less than 30
minutes of playtime, or for players sharing an IP address. Lives in
`smp_afk` (same legacy shard economy) and hooks `f10`'s kill credit.

### 4.6 Fixed-price server shop (`smp_servershop`)

Before June 2026, `/shop` was a fixed-price server shop [S7]. Clone
recreations use End, Nether, Gear and Food categories with a quantity
selector [C5]. The module is **buy-only**, configured by category and price,
and counts towards `money_spent_on_shop` (`f14`). Recommended as a money
sink; do not load alongside `smp_quickbuy` — both claim `/shop`.

### 4.7 Other legacy items

The Amethyst Bucket (drained a 3×3×3 water cube) is specified in `f06` with
the other amethyst items. Spawners in the shard shop (1,500 shards on
26 February 2026 [S8]) are covered by `f07`'s
`spawners.acquisition.shard_shop` flag.

## 5. Data schema

### 5.1 Key balances (in the player record, `f01 §5.1`)

```lua
keys = { common = 0, prime = 0, gold = 0, amethyst = 0, crimson = 0 }
```

### 5.2 Team (`smp_store` table)

```lua
{ name = "Raiders", owner = "Alice", created = 1758500000,
  members = { Alice = { invite = true, kick = true, home = true, sethome = true, chat = true },
              Bob   = { chat = true } },
  home = { x = 100, y = 70, z = 200 }, pvp = false }
```

### 5.3 Crate definition (example values)

```lua
{ id = "prime", title = "Prime",
  rewards = {                         -- exactly seven; the player chooses one
    { item = "mcl_tools:sword_netherite", ench = { sharpness = 5, unbreaking = 3, mending = 1 } },
    { item = "mcl_tools:mace",            ench = { density = 5, wind_burst = 3 } },
    -- five more entries
  } }
```

## 6. Algorithms

```lua
-- crate opening: deterministic choice, one key spent
function smp_crates.open(player, pos, crate_id)
  if not within_distance(player, pos, 8) then return end               -- R7
  local keys = smp_store.player(player:get_player_name()).keys
  if (keys[crate_id] or 0) < 1 then
    return chat(player, S("You need a @1 key.", crate_id))
  end
  smp_crates.show_choice(player, pos, crate_id)                        -- seven item buttons
end

function smp_crates.choose(player, pos, crate_id, index)
  if not within_distance(player, pos, 8) then return end               -- R7
  local keys = smp_store.player(player:get_player_name()).keys
  if (keys[crate_id] or 0) < 1 then return end                         -- re-validate
  keys[crate_id] = keys[crate_id] - 1
  give_or_drop(player, build_reward(crate_id, index))                  -- enchanted per §5.3
  smp_store.ledger("admin", "crate", player:get_player_name(), 0, { ref = crate_id })
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `legacy.keyall_interval` | 3,600 s | LEGACY [S11] |
| `legacy.keyall_keys` | `{common = 1}` | PROPOSED |
| `legacy.afk_shards_per_min` | 1 | LEGACY [S8] |
| `legacy.team_max_members` | 50 | LEGACY [S12] |
| `legacy.kill_shards` | 10 | LEGACY [S8] |
| `legacy.duels_keep_inventory` | true | PROPOSED |
| `legacy.shop_prices` | `{}` (category → item → price) | CLONE [C5] |

## 8. Mineclonia implementation

- Crate nodes are decorative (`groups = {unbreakable = 1}`) with
  `on_rightclick`; they are spawn fixtures, not mineable blocks.
- The seven-choice menu is a prompt menu of seven `item_image_button[]` with
  tooltips; layout per `shared/04-ui-kit.md §4.3`.
- Team home integration adds a tab to `f09`'s tab row through a registered
  callback (`f09` SHOULD expose `register_extra_tab`); do not fork `f09`.
- Duels arenas: place schematic once at setup; snapshot and restore with
  `core.place_schematic` after each match; teleport both players through the
  `f08` framework with warm-up skipped (`PROPOSED`).
- `smp_servershop` and `smp_quickbuy` are mutually exclusive: both register
  `/shop`. Fail loudly at startup if both are enabled.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | Opening a crate without a key refuses; with a key, presents exactly seven choices |
| T2 | Choosing consumes exactly one key and delivers the chosen reward with its configured enchantments |
| T3 | Keyall grants every online player the configured keys on the interval, including a player who joined one second before |
| T4 | The AFK zone awards 1 shard per full minute inside and nothing outside; it cannot run concurrently with the `f06` playtime award |
| T5 | A team over 50 members refuses joins; permissions gate invite/kick/sethome exactly as documented |
| T6 | The team home appears as the leftmost `/homes` tab when `smp_teams` is loaded |
| T7 | Team chat hides public chat while toggled and delivers to members only |
| T8 | With friendly fire off, teammates cannot tag each other (integration with `f10`) |
| T9 | A duel restores the arena schematic afterwards and returns both players with their gear |
| T10 | Kill-shard farming across two same-IP accounts pays nothing |
| T11 | Loading `smp_servershop` and `smp_quickbuy` together fails at startup with a clear error |

## 10. Open questions

| Id | Question |
|---|---|
| V-83 | Exact contents of each crate's seven choices — only reward *categories* are documented |
| V-84 | Did crate opening animate (a rolling display) before the choice? |
| V-85 | Were team homes separate from or shared with personal `/sethome` limits? |
| V-86 | Duel arena layouts and whether losers' items transferred — undocumented |
| V-87 | Did the AFK zone kick players after a limit, or pay indefinitely? |
