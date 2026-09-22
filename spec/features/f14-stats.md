# f14 — Statistics, Leaderboards, Scoreboard and API

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_stats` |
| Phase | P7 |
| Depends on | `f01-economy-core` (balances, sell/shop counters), `smp_store`; enrichment from every economy mod |
| Frame evidence | **0 dedicated frames** — but the scoreboard sidebar is observed in the background of two frames [F0055, F0287] |
| Confidence | **Research only** for menus and the API; the scoreboard's existence and content are **observed**. |

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/stats` | — | `[player]` | Statistics menu | LIVE [S23] |
| `/leaderboard` | `/lb`, `/leaderboards` | `[category]` | Leaderboards | LIVE [S24] |
| `/baltop` | `/moneytop` | `[page]` | Money leaderboard (command owned by `f01`; data source here) | LIVE [S24] |
| `/api` | — | `[delete]` | Issue or revoke a personal API key | LIVE [S23][S24] |

## 3. Observed UI

### 3.1 Scoreboard sidebar [F0055, F0287]

A sidebar at the **bottom-right** of the screen carries a money readout:

| Frame | Reading | Note |
|---|---|---|
| F0055 | `Voire 723k` | no `$` in this reading |
| F0287 | `Voire $ 754k` | with `$ ` |

`Voire` is the sidebar title — likely the scoreboard's header (a name or
season label); its meaning is unverified (V-76). The amount grew from 723k to
754k between 00:00:54 and 00:04:46, tracking the player's balance through
sales and purchases during the recording — strong evidence the value is the
**live money balance**, updated in place.

Requirements:

1. A server-driven scoreboard sidebar MUST exist and show the player's money
   balance with a lower-case suffix (`723k`, `754k`) — the third formatting
   convention noted in `f01 §3.2`.
2. It MUST update as the balance changes.
3. The title text is `server.name`-configurable, like the settings subtitle
   (`shared §0.5` rule 3); `Voire` is what the reference server displays.

The coordinate readout (`X: … Y: … Z: … C: … Biome: …`) beside it in both
frames is Lunar Client HUD and MUST NOT be reimplemented
(`shared/01-overview.md §1.2`, `shared/03-mineclonia-api.md §3.3`).

### 3.2 Not observed

`/stats`, `/leaderboard`, `/baltop` and `/api` outputs. A `Scoreboard`
settings category exists [F0237] (`f12`), implying the sidebar can be
configured or hidden per player — contents of that category are unobserved
(`f12` V-36).

![SS-19: /stats menu](../../screenshots/SS-19-stats.png)
![SS-20: Leaderboard menu](../../screenshots/SS-20-leaderboard.png)

## 4. Behaviour

### 4.1 Statistics fields

Fields follow the official API [S23]:

| Field | Collected by |
|---|---|
| `broken_blocks` | `core.register_on_dignode` |
| `placed_blocks` | `core.register_on_placenode` |
| `kills`, `deaths` | `core.register_on_dieplayer(player, reason)`, killer from `reason.object` or the `f10` last attacker |
| `mobs_killed` | Wrap `on_die` on every `mobs_mc:*` entity definition in `core.register_on_mods_loaded`; Mineclonia calls `self:on_die(pos, mcl_reason)` on death [M1] (verify which `mcl_reason` fields identify the killer) |
| `money`, `shards` | Current balances, read live from `f01` |
| `money_made_from_sell` | `f02` (server and order proceeds both count, `f02 §4`) |
| `money_spent_on_shop` | `f05` (and the legacy `smp_servershop`, `f16`) |
| `playtime` | Global-step accumulator, persisted every minute |

1. `/stats [player]` shows these fields in a menu (`PROPOSED` layout;
   grammar per `shared/04-ui-kit.md`). Viewing another player's stats
   follows the API, which exposes them publicly [S23].
2. Counters are monotonic and live in the player record, so leaderboards can
   enumerate offline players (`shared §2.2`).
3. Combat-log kills (`f10 §4.3`) MUST increment `kills` for the credited
   attacker and `deaths` for the logger.

### 4.2 Leaderboards

1. Categories match the official API: `brokenblocks`, `deaths`, `kills`,
   `mobskilled`, `money`, `placedblocks`, `playtime`, `sell`, `shards`,
   `shop` [S23].
2. `/leaderboard [category]` and `/baltop` read **snapshots** rebuilt every
   `leaderboards.refresh` (300 s), each keeping the top
   `leaderboards.size` (100) (`PROPOSED`).
3. Rebuild cost MUST stay within the performance budget: target under 50 ms
   at 10,000 player records (`shared §2.7`).
4. Display format: rank, name, formatted value (`PROPOSED`;
   `1. Notch — $ 1.2B` house style).

### 4.3 Scoreboard

1. Enabled by default (`scoreboard.enabled = true`, **OBSERVED** by its
   presence [F0287]); per-player visibility is expected to be controllable
   from the `Scoreboard` settings category (`f12` — unobserved, `PROPOSED`
   wiring).
2. Content: the sidebar title plus the money balance, lower-case suffix
   style. v0.1-era plans for multi-line sidebars (kills, shards, online
   count) are dropped: only money is evidenced. Additions MUST be
   config-gated until observed.
3. Updates on every balance change and on join.

### 4.4 Public API (optional)

The reference server issues personal API keys in game with `/api`; clients
send the key as a bearer token, limited to 250 requests per minute, reading
auction listings (search and sort), auction transactions, leaderboards,
player lookups and statistics [S23].

Luanti mods cannot serve HTTP. Two options:

1. Write JSON snapshots into the world directory with
   `core.safe_file_write` for an external web server to publish.
2. Push snapshots through the HTTP API from `core.request_http_api()` (the
   mod must be in `secure.http_mods`) to an external service that manages
   keys and rate limits. `/api` then asks that service to issue or revoke a
   key and shows it to the player.

Both are `PROPOSED`; pick option 1 by default (no outbound dependency).

## 5. Data schema

In the player record (`f01 §5.1`):

```lua
stats = {
  broken_blocks = 0, placed_blocks = 0,
  kills = 0, deaths = 0, mobs_killed = 0,
  money_made_from_sell = 0, money_spent_on_shop = 0,
}
```

Leaderboard snapshots (in-memory, rebuilt periodically; never persisted —
they are derivable):

```lua
smp_stats.boards.money = { {name = "Alice", value = 125000000}, … }   -- top 100
```

API keys (when option 2 is used) live in the player record:
`api_key = { key = "…", created = 1758500000 }`.

## 6. Algorithms

```lua
-- accumulator: one globalstep, O(online players)
local acc = 0
core.register_globalstep(function(dtime)
  acc = acc + dtime
  if acc < 1 then return end
  acc = 0
  for _, player in ipairs(core.get_connected_players()) do
    smp_stats.add_playtime(player:get_player_name(), 1)   -- flushed to store every 60 s
  end
end)

-- snapshot rebuild, every leaderboards.refresh
function smp_stats.rebuild()
  for _, cat in ipairs(categories) do
    smp_stats.boards[cat] = top_n(all_players_sorted_by(cat), cfg.leaderboards.size)
  end
end
```

`money` and `shards` boards read balances directly from `smp_store` player
records; `sell` and `shop` read `stats.money_made_from_sell` and
`stats.money_spent_on_shop`.

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `leaderboards.refresh` | 300 s | PROPOSED |
| `leaderboards.size` | 100 | PROPOSED |
| `scoreboard.enabled` | true | **OBSERVED** [F0287] |
| `scoreboard.title` | `server.name` | PROPOSED (observed title `Voire` unexplained, V-76) |
| `stats.persist_interval` | 60 s | PROPOSED |
| `api.mode` | `off` (`off`, `snapshot`, `push`) | PROPOSED |

## 8. Mineclonia implementation

- The scoreboard is a HUD element: `player:hud_add` with
  `hud_elem_type = "text"`, anchored bottom-right
  (`shared/03-mineclonia-api.md §3.3`). Position it clear of the hotbar and
  the Minetest default minimap.
- `hud_change` on balance change (hook `smp_economy.credit`/`debit`) and on
  join; do not poll.
- Mob-kill wrapping: iterate `core.registered_entities` in
  `core.register_on_mods_loaded`, wrap each `mobs_mc:*` definition's
  `on_die`, call the original, then inspect `mcl_reason` for the killer.
- `/stats` and `/leaderboard` are menus in the observed grammar
  (`shared/04-ui-kit.md`): a `/stats` screen is a prompt menu of
  `<Field>: <Value>` lines; a leaderboard is a container menu
  `<Category> (Page N)`.
- Snapshot rebuild runs outside globalstep where possible
  (`core.after` chain), never on the hot path.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | Digging and placing nodes increments `broken_blocks` / `placed_blocks` exactly once each |
| T2 | A melee kill increments the killer's `kills` and the victim's `deaths`; a combat log credits the last attacker the same way |
| T3 | Killing a `mobs_mc:*` mob increments `mobs_killed` for the killer only |
| T4 | `/sell` proceeds (server and order portions) increment `money_made_from_sell` by exactly the amount paid (integration with `f02`) |
| T5 | Quick Buy spending increments `money_spent_on_shop` (integration with `f05`) |
| T6 | The scoreboard shows the current balance with a lower-case suffix and updates within one HUD tick of a sale |
| T7 | All ten leaderboard categories build and match the official API's category set |
| T8 | A rebuild with 10,000 synthetic player records completes in under 50 ms |
| T9 | Leaderboards include offline players |
| T10 | `/api` issues a key once and `delete` revokes it (mode-dependent) |
| T11 | Statistics survive a restart; at most `stats.persist_interval` of playtime is lost to a crash |

## 10. Open questions

| Id | Question |
|---|---|
| V-23 | `/stats` and leaderboard menu layouts — unobserved |
| V-53 | Owned by `f01`, cross-listed: is the scoreboard's lower-case money a third format or the same formatter narrower? |
| V-76 | What is `Voire` in the scoreboard title — a season name, a sub-server name, a sponsor? |
| V-77 | Does the scoreboard show anything besides money (kills, shards, playtime)? Only money was visible |
| V-78 | What does the `Scoreboard` settings category (`f12`) control — visibility, content, scale? |
| V-79 | Which `mcl_reason` fields identify the killer in `on_die`? (Engine verification task, not a Donut question) |
