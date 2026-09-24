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
| `money_spent_on_shop` | `f05` (and the legacy `smp_servershop`, `f16`) — servershop will never ship *(f16 descoped — D8, 2026-09-24)* |
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
| `api.mode` | `snapshot` (`off`, `snapshot`, `push`) | PROPOSED |

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
| V-79 | Which `mcl_reason` fields identify the killer in `on_die`? (Engine verification task, not a Donut question) — **RESOLVED, see F14-D2** |
| F14-D1 | `smp_stats.add(player_or_name, key, value) -> new_total \| nil, err` and `smp_stats.get(player_or_name, key) -> number` (PROPOSED signatures): both accept an ObjectRef (f05's stub) or a player name (f10's call) and normalise through `name_of`. `add` writes `rec.stats[key]` (integer, `ensure -> mutate -> upsert`, no yields); f02's direct `rec.stats.money_made_from_sell = ...` assignment lands in the same field — both paths agree, no second store. `get`/`add` treat `money`, `shards` and `playtime` as **live fields**: `get` reads them at the record top level (`playtime` plus this server's unflushed pending seconds), `add` refuses them (money moves through `smp_store.api`, playtime through `add_playtime(name, seconds)` per §6). |
| F14-D2 | V-79 answered (engine-verified @ `~/dev/mineclonia-git`): `mcl_damage.from_punch` sets `mcl_reason.direct` = the punching object and `mcl_reason.source` = `luaentity._source_object` for projectiles (the shooter); `finish_reason` folds `source = source or direct`. Wrapper reads `source or direct`, then `name_from_object` walks player -> `_source_object` -> `entity.owner` (tamed wolf credits its owner). `on_die(self, pos, mcl_reason)` only fires when the def defines it (`mcl_mobs/physics.lua:217`, which treats a `true` return as "death handled") — so `register_on_mods_loaded` wraps every `mobs_mc:*` def, preserving the original's return. Player kills: `reason.object`, then `reason._mcl_reason` source/direct. With `f10` present (optional dep) our dieplayer hook credits only `deaths` (f10's `credit_kill` owns `kills`), and our leave hook — registered first, since `smp_combat` depends on `smp_stats` — credits `deaths` to a tagged logger under exactly the condition f10 credits the attacker's kill. |
| F14-D3 | Scoreboard formatter (V-53): local `smp_stats.fmt_scoreboard(cents)` — the third convention (f01 §3.2), lower-case `k/m/b/t` at `fmt_money`'s thresholds, no `$` (the HUD renders `title` + newline + `$ ` + readout, choosing F0287's `Voire $ 754k` form over F0055's), dollars with cents below $1,000 (`7`, `5.50`). `smp_core.fmt_money` is untouched — chat stays `$ 754K`. T6 pins both. |
| F14-D4 | f12 wiring (V-78): when `smp_settings` is present, `scoreboard.show` (`ON`/`OFF`, default `ON`, label `Scoreboard`) is registered into the observed `Scoreboard` category from `register_on_mods_loaded`. PROPOSED — the category's contents are unobserved (f12 V-36). `scoreboard.enabled` (§7, OBSERVED) remains a separate config gate. `smp_settings` exposes no change callback, so a toggle applies at the next balance update or rejoin; `/stats`'s own display is unaffected. |
| F14-D5 | `api.mode` default: §7's table says `off`, claim-f14 instructs `snapshot` — implemented **`snapshot`** (the JSON-snapshot path is option 1, §4.4's stated default). `push` is a warned stub (needs `core.request_http_api()` + an external key service); `off` refuses. `/api` issues `fcsmp_ .. sha1` once (`rec.api_key = {key, created}`, §5), re-shows the existing key, `/api delete` revokes, re-issue mints a new key (T10). Message wording PROPOSED (unobserved). Snapshots: `<worldpath>/friedcake_api/leaderboards.json` + `players.json`, rewritten after every rebuild. — **resolved (D4, 2026-09-24): §7 now says `snapshot`; code was already `snapshot` (`smp_stats/init.lua:43-50`), unchanged.** |
| F14-D6 | V-23 layouts (PROPOSED): `/stats` = prompt menu `Stats` / `Stats - <name>` of `Label: Value` rows + `Back`; `/leaderboard` = prompt picker `Leaderboard` with the ten category buttons in §4.2.1 order + `Back`; `/leaderboard <cat>` = container menu `<Category> (Page N)`, textlist rows `@1. @2 — @3`, page size 10, `<`/`>`/`Back`, player inventory (smp_orders grammar). Field labels are the claim's verbatim strings; unknown categories and forged `cat_*` fields are refused/ignored. |
| F14-D7 | `/baltop` (f01-owned command, f14-owned data source per §4.2.2): `core.override_chatcommand` keeps f01's exact chat output — `--- Money Top (page @1/@2) ---` + ten `@1. @2 — @3` rows — but reads the `money` snapshot (top `leaderboards.size`, so pagination covers the top 100) instead of a live full-table sort. Falls back to f01's live implementation until the first rebuild publishes a board. PROPOSED; no `spec/shared` change needed. |
| F14-D8 | Display details (PROPOSED): leaderboard money rows use the body chat spacing (`1. rich01 — $ 1M`), counts the lower-case quantity suffix, playtime raw seconds (§0.6 silent); `/stats` money rows likewise body-spaced. HUD updates hook `smp_store.api.add_money/take_money/set_money` and join — never poll (§8). |
| F14-D9 | T11 budget: playtime accrues in memory (`_pending_playtime`), flushes at `stats.persist_interval` (60 s), on leave and on shutdown (upsert, then `pcall(smp_store._driver.flush)` — `smp_store`'s own shutdown callback runs first). A crash loses at most one interval; the store-layer delay ≤10 s is f01's T8 budget. Measured: T8 rebuild of 10,000 records = **10.8 ms** (gate 50 ms). |

### §10 implementation note (claim-f14 write-up)

- **Public surface:** `smp_stats.add(player_or_name, key, value)`,
  `smp_stats.get(player_or_name, key)`, `smp_stats.add_playtime(name, s)`,
  `smp_stats.boards[cat]`, `smp_stats.rebuild()`, plus
  `smp_stats.build_from(records, size)` for tests (F14-D1).
  f05's `add(player, "money_spent_on_shop", cost)` and f10's
  `add(name, "kills", 1)` both verified against the sibling branches and
  covered by `dev-tests/test_stats.lua` (T2/T5).
- **V-79** answered in F14-D2; killer fields confirmed against
  `mcl_damage/init.lua` and `mcl_mobs/physics.lua` in the live clone.
- **Formatter** in F14-D3 (the third convention; T6 pins `754k` vs
  `$ 754K`).
- **All PROPOSED decisions:** F14-D1 … F14-D9 above — signatures, f12
  wiring, `api.mode` default conflict (§7 `off` vs claim `snapshot`) —
  resolved (D4, 2026-09-24: §7 default corrected to `snapshot`, code
  already `snapshot`),
  menu layouts (V-23), `/baltop` override, display details, T11 budget.
- **Acceptance:** T1–T11 all green under `luajit
  friedcake/dev-tests/test_stats.lua` (now 234 assertions; 186 before the
  fix-brief pass) plus the in-game suite `mods/smp_stats/test.lua`
  (now 82 assertions; 71 before the fix-brief pass — no regression); T8
  measured 10.8 ms at 10,000 synthetic records against the 50 ms gate.
- **Proposed shared changes: none.** No `spec/shared/` edit is required:
  the `/baltop` data-source swap and the `scoreboard.show` registration
  are local integrations recorded above (F14-D4, F14-D7).

### §10 fix-brief closure record (`fixes/f14-stats.md`, branch `agent/f14-stats-fixes`, 2026-09-25)

| ID | Outcome | Evidence |
|---|---|---|
| S1 | **CLOSED — pre-fixed on `main`, verified only** | `smp_stats/playtime.lua:59` reads `core.register_globalstep`; the dev-test harness captures it under the same name and the new S1 assertions pin it (+1 globalstep handler at load, callable, stepped by T11). Zero matches for the nonexistent name across `friedcake/mods/` (grep clean). The rename at `dev-tests/test_stats.lua` and the "stub must not fake it" guard were done under **B4-1** before this branch (`fixes/STATUS.md` §3) — that literal now lives only in `dev-tests/test_engine_apis.lua`, by design; this branch's own S1 check avoids it so the B4-1/B4-3 guard stays green. |
| S2 | **CLOSED by D4 (pre-applied, verified only)** | §7's `api.mode` default cell already reads `snapshot` (D4, 2026-09-24; F14-D5 annotated resolved above); code unchanged. Not redone. |
| S3 | **CLOSED** | `init.lua` → `smp_stats.resolve_api_mode()`: unset (`nil`) defaults silently; set-but-invalid (`""`, non-string, unknown word) logs `core.log("warning", …)` naming the bad value **and** the fallback, then falls back as today; valid values pass through; never a hard crash over a config string. Default unchanged (`snapshot`, per D4). Dev-test S3 block asserts all four branches incl. load-time silence. |
| S4 | **CLOSED** | `counters.lua` `add()` rejects `value < 0` with `nil, err` (`"counters are monotonic: negative increment"`) in the validate phase — before `ensure_player`, so a rejection never touches the store (shared §2.3). Monotonicity is enforced, not conventional; F14-D1's live-field refusals (`money`/`shards`/`playtime`) unchanged; all shipped callers pass positives. Asserted in `dev-tests/test_stats.lua` (S4: unchanged counter + `nil, err` + positive path + live fields) and in in-mod `test.lua` (S4 block, rejection-only → stays a pure check). |
| S5 | **CLOSED — honest labelling + D11 seam note, mirrored here** | T4/T5 in `dev-tests/test_stats.lua` are **contract-shape tests**: they verify `rec.stats` field agreement with f02's and f05's write *shape*, **not** a live `/sell` or Quick Buy flow. File header, section label and assertions say so explicitly; the ids T4/T5 are kept (they are `plan/acceptance-tests.md`'s merge gate) and no end-to-end claim is made anywhere. **Seam note:** the real f02/f05 flows land with **D11's** integration harness (`dev-tests/test_integration.lua`, ruled A 2026-09-24; seam policy recorded in `plan/acceptance-tests.md`) — this is that note, in my file as required. |
| S6 | **CLOSED — verified/kept** | `api.lua` load-time `push` warning fires (proven by re-running the chunk under `api.mode=push`: exactly one `warning:` naming `push` and "PROPOSED stub"); `off` loads silently; `/api` refuses with the explanatory message in **both** `off` and `push` (T10 assertions kept green; push message content now asserted too). No partial push implementation — §4.4 option 2 stays PROPOSED. |
| S7 | **CLOSED (this mod only)** | Terminal full stops stripped at every listed site, all still inside `core.get_translator`: `init.lua` `/stats`, `/leaderboard`, `/lb`, `/leaderboards` descriptions; `api.lua` `/api` description; all four `formspec.lua` `Player @1 does not exist` refusals. None of them appears in `spec/shared/08-ui-strings.md` (verified), so no OBSERVED string changed. |

**Escalations (outside this brief's edit scope — overseer/feature owners):**

1. **`fixes/README.md` f14 row annotation (brief DoD 6) not applied** — this
   agent's dispatch rules forbid writing anywhere under `fixes/`. Intended
   text: *S1 verify-only (fixed on `main`), S2 → D4, S3/S4/S5/S6/S7 closed
   on `agent/f14-stats-fixes`.*
2. **Same `Player @1 does not exist.` §0.5 drift in other mods:**
   `smp_economy/init.lua:110,200` (f01), `smp_shards/init.lua:218` (f06),
   `smp_bounty/init.lua:144` (f10 — its dev-test asserts the period at
   `dev-tests/test_bounty.lua:122`, so that test must move with the
   string). One-agent-per-feature: not edited here.
3. **`api.lua` refusal strings beyond the brief's listed sites** —
   `The public API is disabled on this server.`,
   `The public API push mode is not configured yet.`, `API key revoked.`,
   `You have no API key.` also carry terminal full stops (same §0.5 class,
   PROPOSED wording, unobserved). Deliberately **not** touched: they are
   not among the brief's seven listed sites — flagged for a follow-up
   sweep so scope stays auditable.
4. **`dev-tests/test_integration.lua:1047` cites the wrong spec path** for
   the `smp_stats.add` seam: `spec/features/f07-stats.md:55` — this
   feature is `f14-stats.md` (seam contract F14-D1, `counters.lua:42`).
   P5-owned file; not edited here.

*Overseer outcomes (2026-09-25): **1** applied — `fixes/README.md` f14 row
annotated. **2** routed — row **F06-11** in `fixes/f06-shards.md` and row
**C4** in `fixes/f10-combat.md` (incl. the `test_bounty.lua:122` literal);
the two `smp_economy` sites are an overseer follow-up once f01 merges.
**3** fixed here — four terminal full stops stripped in
`smp_stats/api.lua:125,130,134,136`. **4** fixed — and the drift was wider
than reported: the whole `SEAM_CHECKS` `spec` column in
`dev-tests/test_integration.lua` cited the pre-final feature numbering
(`f07-stats`, `f06-combat`, `f02-orders`, `f03-ah`, `f04-sell`,
`f10-spawners`, `spec/shared/01-conventions.md` — none exist); all 24 rows
re-anchored to verified `file:line` (printed-only column).*
