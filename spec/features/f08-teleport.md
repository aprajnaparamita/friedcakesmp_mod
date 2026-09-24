# f08 — Teleportation: Framework, `/rtp`, RTP Queue, Requests, Spawn, Warps

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_tp` (framework, `/rtp`, requests, spawn, warps); `smp_rtpqueue` (P8) |
| Phase | P4 (`smp_rtpqueue` P8) |
| Depends on | `mcl_worlds`, `mcl_spawn`; homes are split out to `f09`; combat interaction with `f10` |
| Frame evidence | **1 frame** [F0037], 00:00:21–00:00:43, plus the clickable-chat affordance seen later [F0270, F0284, F0288] |
| Confidence | **Research only.** `/rtp` was narrated and typed on camera but no teleport UI exists to observe — the reference server removed the RTP menu on 15 June 2026 [S14]. Everything structural below comes from documentation and clones. |

Homes (`/homes`, `/sethome`, `/delhome`) are **not** in this file; they are
`f09`, which depends on the warm-up framework specified here.

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/rtp` | — | `[dimension or region]` | Random teleport | **OBSERVED** [F0037] |
| `/rtpqueue` | — | — | Join or leave the paired random-teleport queue | LIVE, beta [S15] |
| `/tpa` | `/tp` | `<player>` | Ask to teleport to a player | LIVE [S26] |
| `/tpahere` | — | `<player>` | Ask a player to teleport to you | LIVE [S26] |
| `/tpaccept` | — | `<player>` | Accept a request (argument-free form accepts the newest, `PROPOSED`) | LIVE [S26] |
| `/tpadeny` | `/tpdeny` | `<player>` | Deny a request | LIVE [S26]; alias CLONE [C1] |
| `/tpacancel` | — | `[player]` | Cancel an outgoing request | LIVE [S26] |
| `/tpauto` | — | — | Toggle automatic acceptance | LIVE [S26] |
| `/tpatoggle`, `/tpaheretoggle` | — | — | Toggle receiving each request type | CLONE [C1] |
| `/spawn` | — | `[lobby]` | Spawn-lobby menu, or a named lobby | LIVE [S26] |
| `/warp` | — | `<location>` | Teleport to a spawn utility location | LIVE [S26] |
| `/world` | — | — | Return to the position before the last teleport command | LIVE [S26] |
| `/back` | `/return` | — | Previous location; disabled by default | CLONE [C1] |

`/tp <player>` is an alias of `/tpa`, as on the reference server [S26].
Luanti's built-in `/teleport` is left to staff privileges and is not touched.

## 3. Observed UI

### 3.1 `/rtp` [F0037]

![/rtp typed](../../frames/frame_0037.jpg)

No menu opens. The frame shows the standard HUD, public chat scrolling on the
left, and the command input holding the partially typed `/rtpa` — the player
mid-keystroke on `/rtp` (the trailing `a` is one VLM reading of one frame and
may be noise or the start of a second word). The narrator's description is the
real evidence:

> "This allows you to teleport around the world to somewhere completely
> random. You can do this over and over till you like the [place you're] in."

Three requirements fall out of that narration, all tagged **OBSERVED** (spoken
on camera) rather than merely documented:

1. `/rtp` teleports to a **completely random** location.
2. It is **repeatable at will** — "over and over" — so any cooldown is short
   enough not to interrupt a tutorial.
3. There is **no menu**: the command acts directly. This matches the documented
   removal of the RTP menu on 15 June 2026 [S14] and sets
   `rtp.menu_enabled = false`.

The player is standing in a jungle biome in the frame; whether that is the RTP
destination or the spawn area cannot be determined from one frame.

### 3.2 Clickable-chat teleport requests [F0270, F0284, F0288]

Hovering a player's name in chat offers
`Click to send @1 a teleport request` — the reference server's `/tpa` entry
point is a **chat affordance**, not only a command. Luanti chat is not
clickable; the decided substitution is a plain hint line plus an Accept/Deny
formspec for the recipient (`shared/04-ui-kit.md §4.8`, `f11`). This file owns
the Accept/Deny formspec side:

```
Teleport Request  ⚠
  <sender> wants to teleport to you.      ← or: ...wants you to teleport to them.
  [ Deny ]              [ Accept ]
```

`Deny` red on the left, `Accept` green on the right, following the observed
colour convention for Cancel/Search (`shared/04-ui-kit.md §4.6`). The screen
itself is unobserved; the layout is `PROPOSED` in the observed grammar.

### 3.3 Not observed

Any warm-up display, cooldown message, arrival message, the RTP zone at spawn,
`/rtpqueue` pairing, `/spawn` lobby menu, `/warp` list and `/world`. All are
`PROPOSED` or documented below.

## 4. Behaviour

### 4.1 Common teleport framework

Every command-initiated teleport in this file and in `f09` goes through one
warm-up path. Defaults:

| Rule | Default | Status |
|---|---|---|
| Warm-up with action-bar countdown | 5 s | CLONE [C7]; PROPOSED outside RTP |
| Cancel on movement | more than `tp.cancel_move_distance` (1 node) | LIVE for RTP [S27]; PROPOSED elsewhere |
| Cancel on damage | yes | PROPOSED |
| Refuse while combat-tagged | yes | LIVE for RTP [S27]; PROPOSED elsewhere; the blocked-command list lives in `f10` |
| Per-command cooldown, tier-reduced | `rtp.cooldown` etc. | LIVE for RTP [S27] |
| Post-arrival damage immunity | 0 s (optional) | PROPOSED |

1. The warm-up countdown MUST be displayed on the action bar through
   `mcl_title.set` (`PROPOSED` display, unobserved), the same channel as the
   observed `Delivering...` indicator [F0226].
2. The origin of every command-initiated teleport MUST be recorded for
   `/world` before the player moves [S26] — written on the successful path
   only, immediately before `set_pos`, so a cancelled warm-up leaves the
   previous origin alone (fix row TP9).
3. A warm-up MUST NOT be used to bypass `f10` combat restrictions: tagging
   either party cancels the teleport — the mover and the stationary
   counterparty (`opts.with`, §4.4) are both checked at start, on every
   countdown tick and again at fire (fix row TP2).

### 4.2 `/rtp`

1. **No menu.** Bare `/rtp` teleports immediately (subject to warm-up) to the
   default dimension (`OBSERVED` directness, `LIVE` menu removal [S14]).
   `/rtp <dimension>` accepts `overworld`, `nether`, `end`; `/rtp <region>`
   accepts a configured region name [S26][S27].
2. **Regions.** The reference server's regions are regional proxy servers
   [S1]. On a single Luanti world they map to named rectangles (for example
   quadrants) configured in `rtp.regions` (`PROPOSED`).
3. **Candidate selection.** A random (x, z) inside the ring from
   `rtp.min_radius` to `rtp.max_radius` around the region centre, clipped to
   the world border and outside the protected spawn radius (`f15`).
4. **Dimension bands** come from `mcl_vars` [M1]: Overworld
   `mg_overworld_min`–`mg_overworld_max`, Nether `mg_nether_min`–
   `mg_nether_max`, End `mg_end_min`–`mg_end_max`. Only the configured sub-band
   of each (`rtp.scan.<dimension>`) is scanned.
5. **Generation is asynchronous**: `core.emerge_area` first, search in the
   callback, never a synchronous scan (`PROPOSED`, performance budget
   `shared §2.7`).
6. **Safe position.** A walkable, non-hazardous node with two free non-liquid
   nodes above. Reject water, lava, fire, cactus, magma blocks, campfires,
   sweet berry bushes, powder snow and leaves (`PROPOSED`, following clone
   blacklists [C8]). In the Nether, search downward from below
   `mg_bedrock_nether_top_max` and avoid lava; in the End, land only on end
   stone.
7. At most `rtp.max_attempts` (`PROPOSED` 10) candidates; on total failure the
   player is told and **no cooldown starts** (`PROPOSED`).
8. **Repeatability.** The cooldown MUST be short enough to permit the observed
   "over and over" usage: `rtp.cooldown` defaults to 60 s for default players
   and 30 s for tier1 (`PROPOSED`; Donut+ had a shorter cooldown [S27]).
9. **RTP zone.** A configured box at spawn: a player who stays inside it for
   `rtp.zone_delay` (`PROPOSED` 3 s) is sent to the Overworld; presence is
   checked once per second [S27].

### 4.3 `/rtpqueue` (`smp_rtpqueue`, P8)

Launched in beta on 29 June 2026; matches a player against another player,
comparable to the removed Duels [S15]. Clone behaviour pairs two queued
players and teleports both to one random safe location [C4]. Specification
(`PROPOSED` where not sourced):

1. `/rtpqueue` toggles queue membership; refused while combat-tagged.
2. First-in, first-out pairing; optional matchmaking by kill/death ratio or
   gear score, as Duels once used [S13].
3. On a match, both players get a 5 s countdown and are teleported to one safe
   location (§4.2 rules), `rtpqueue.separation` apart (16 to 32 nodes).
4. Membership times out after `rtpqueue.timeout` (300 s); disconnecting or
   teleporting elsewhere also leaves the queue.
5. After landing, normal survival rules apply: the first hit starts combat
   tags (`f10`), death drops items.
6. Players who **block** each other (`f11`) MUST NOT be paired
   (`PROPOSED`). The exclusion is the *block* graph only — `/ignore` does
   not exclude a pairing (f11 F11-4; fix row TP13).

### 4.4 Teleport requests

1. One pending request per (sender, target, type). Requests expire after
   `tpa.expiry` (`PROPOSED` 60 s).
2. A target who disabled the request type (`/tpatoggle`, `/tpaheretoggle`),
   or who ignores or blocks the sender (`f11`), produces a **generic**
   refusal — the sender is not told which privacy rule fired, matching the
   observed refusal style
   (`This user only accepts messages from friends or followed players`
   [F0276–F0285] is the chat analogue).
3. With `tp.confirm_menu` on, the target sees the Accept/Deny formspec (§3.2)
   instead of needing `/tpaccept` in chat — the decided substitute for
   clickable chat.
4. `/tpauto` accepts requests automatically [S26].
5. After acceptance, the moving party (the sender for `/tpa`, the target for
   `/tpahere`) goes through the §4.1 warm-up.
6. A request is cancelled if either party is combat-tagged, dies or
   disconnects.
7. Sending a request to a player whose chat privacy is `Friends/Followed`
   SHOULD respect the same setting for requests (`PROPOSED`; the privacy
   model is `f12`, the friend graph is `f11`).

### 4.5 Spawn, lobbies, warps, `/world`, `/back`

1. `/spawn` opens a lobby menu; `/spawn <lobby>` goes directly to a named
   lobby [S26]. On a single world, lobbies are named spawn points
   (`PROPOSED`). Spawn positions come from `mcl_spawn.get_world_spawn_pos`
   [M1].
2. `/warp <location>` teleports to spawn utility locations [S26], such as the
   former crates area (`f16`) [S25]. Warp points are server configuration,
   not player data.
3. `/world` returns to the position recorded before the last
   command-initiated teleport [S26]. One level deep only; `/world` does not
   chain backwards (`PROPOSED`).
4. `/back` [C1] is disabled by default to preserve the stakes of death
   (`PROPOSED`). When enabled it returns to the last death or teleport
   location.
5. `/spawn` and `/warp` use the §4.1 warm-up; both are on the `f10` combat
   block list.

### 4.6 Ender pearls

The reference server restored vanilla pearl behaviour, fixed cross-dimension
pearls [S2] and added a setting that stops thrown pearls disappearing when the
thrower dies [S20]. Mineclonia's pearl entity is
`mcl_throwing:ender_pearl_entity` [M1]. `PROPOSED`: track in-flight pearls per
thrower and remove them on the thrower's death unless the player's
`combat.keep_pearls_on_death` setting (`f12` General category) is on. Low
priority.

## 5. Data schema

Transient (player meta or in-memory; none of this survives a restart except
where noted):

```lua
-- per player
smp_tp.state[name] = {
  warmup = nil,                  -- mirror of smp_tp.warmup[name]:
                                 -- {token, kind, name, from, to, started,
                                 --  duration, with, record_from} while warming
  last_teleport_from = nil,      -- pos, for /world (written only when the
                                 -- teleport fires — f08 §4.5, fix row TP9)
  cooldowns = { rtp = 0 },       -- expiry timestamps
  requests_out = {},             -- (target, type) -> expiry
  requests_in  = {},             -- (sender, type) -> expiry
}
```

Queue membership is **not** part of this schema: `/rtpqueue` keeps its own
`smp_rtpqueue.members[name] = {joined_at, at}` table inside `smp_rtpqueue`.
An earlier draft of this schema listed an `rtpqueue = {joined_at}` field that
no code ever read or written; it is struck so §5 describes the code
(fix row TP7, §10 Fix-wave record). The OBSERVED queue *behaviour* — the 5 s
countdown, 16–32 nodes apart, 300 s timeout — is unchanged.

Warp points and lobby spawn points are **configuration**, not player data:

```lua
warps   = { crates = {x = 12, y = 70, z = -40} }
lobbies = { main = {x = 0, y = 72, z = 0} }
rtp_regions = { nw = {minx = -30000, maxx = 0, minz = -30000, maxz = 0, cx = -15000, cz = -15000} }
```

## 6. Algorithms

### 6.1 Warm-up

```lua
function smp_tp.teleport_with_warmup(player, pos, kind)
  local name = player:get_player_name()
  if smp_combat and smp_combat.is_tagged(name) then
    return refuse(name, "teleport")                       -- f10 owns the block list
  end
  local from = player:get_pos()
  smp_tp.state[name].warmup = { started = os.clock(), from = from, to = pos, kind = kind }
  core.after(cfg.tp.warmup, function()
    local p = core.get_player_by_name(name)
    local w = smp_tp.state[name].warmup
    if not p or not w then return end                     -- left, or cancelled
    if vector.distance(p:get_pos(), w.from) > cfg.tp.cancel_move_distance then
      smp_tp.state[name].warmup = nil
      return chat(p, S("Teleport cancelled"))             -- PROPOSED string
    end
    smp_tp.state[name].warmup = nil
    smp_tp.state[name].last_teleport_from = from          -- for /world
    p:set_pos(pos)
  end)
end
```

Damage cancellation hooks `core.register_on_player_hpchange`; the countdown
display ticks once per second through `mcl_title.set`.

### 6.2 Random-teleport search

```lua
function smp_tp.rtp(name, dim, region, attempt)
  attempt = attempt or 1
  if attempt > cfg.rtp.max_attempts then
    return core.chat_send_player(name, S("No safe location found. Try again."))
  end
  local band = cfg.rtp.scan[dim]
  local x, z = smp_tp.random_in_ring(region, cfg.rtp.min_radius, cfg.rtp.max_radius)
  core.emerge_area(vector.new(x, band.min, z), vector.new(x, band.max, z),
    function(_, _, remaining)
      if remaining > 0 then return end
      local player = core.get_player_by_name(name)
      if not player then return end                       -- left while generating
      local pos = smp_tp.find_safe_y(x, z, band, dim)     -- top-down scan, reject list
      if pos then
        smp_tp.teleport_with_warmup(player, pos, "rtp")
        smp_tp.state[name].cooldowns.rtp = os.time() + cfg.rtp.cooldown[smp_ranks.tier(name)]
      else
        smp_tp.rtp(name, dim, region, attempt + 1)
      end
    end)
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `smp_tp.tp.warmup` | 5 s | CLONE [C7] |
| `smp_tp.tp.cancel_move_distance` | 1 node | PROPOSED |
| `smp_tp.tp.confirm_menu` | true | CLONE [C1]; the decided substitute for clickable chat |
| `smp_tp.tp.back_enabled` | false | PROPOSED |
| `rtp.cooldown_default` | 60 s | PROPOSED (Donut: shorter for Donut+ [S27]) |
| `rtp.cooldown_tier1` | 30 s | PROPOSED (Donut: shorter for Donut+ [S27]) |
| `rtp.cooldown_tier2` | 30 s | PROPOSED (beyond-spec, implemented; the read landed with fix row TP8a) |
| `rtp.cooldown_tier3` | 30 s | PROPOSED (beyond-spec, implemented; the read landed with fix row TP8a) |
| `rtp.cooldown_media` | 60 s — falls back to the default when unset | PROPOSED (beyond-spec, implemented; fix row TP8a) |
| `smp_tp.rtp.min_radius`, `smp_tp.rtp.max_radius` | 500; the border minus 500 | PROPOSED |
| `smp_tp.rtp.scan.overworld` | y from −32 to 256 (adjust to the world's terrain) | PROPOSED |
| `smp_tp.rtp.scan.nether` | `mg_nether_min` to a few nodes below `mg_bedrock_nether_top_max` | PROPOSED |
| `smp_tp.rtp.scan.end` | `mg_end_min` to `mg_end_min + 128` | PROPOSED |
| `smp_tp.rtp.max_attempts` | 10 | PROPOSED |
| `smp_tp.rtp.menu_enabled` | false (menu removed 15 June 2026) | LIVE [S14]; read from settings since fix row TP8b |
| `smp_tp.rtp.zone_delay` | 3 s | PROPOSED |
| `smp_tp.rtp.regions` | `{}` | PROPOSED |
| `world.spawn_protect_radius` | 128 | PROPOSED (f15's key; **consumed** by f08 as the `/rtp` landing exclusion, §4.2.3 — fix row TP5) |
| `smp_tp.rtpqueue.timeout` | 300 s | PROPOSED |
| `smp_tp.rtpqueue.min_separation` | 16 nodes | PROPOSED (read since fix row TP8c) |
| `smp_tp.rtpqueue.max_separation` | 32 nodes | PROPOSED (read since fix row TP8c) |
| `smp_tp.tpa.expiry` | 60 s | PROPOSED |

## 8. Mineclonia implementation

- The Accept/Deny dialog is a **prompt menu** (`shared/04-ui-kit.md §4.1`):
  `formspec_version[6]`, `bgcolor[#000000C0]`, two coloured buttons
  (`style[accept;bgcolor=green]`, `style[deny;bgcolor=red]`).
- The warm-up action-bar countdown uses `mcl_title.set(player, "actionbar",
  {text = ..., stay = 20})` re-issued each second [M1].
- `core.register_on_player_hpchange` covers damage cancellation; movement is
  checked at fire time (§6.1), not polled.
- `/rtpqueue` lives in `smp_rtpqueue` and depends on both `smp_tp` (safe
  search) and `smp_combat` (tag check).
- Re-validate everything at fire time: the player may have moved, logged off,
  been tagged, or had the target log off during the warm-up. Client fields
  carry nothing trusted.
- Dimension detection for `/rtp <dimension>` and for `/findplayer` (`f11`)
  uses `mcl_worlds.pos_to_dimension` [M1].

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | `/rtp` opens no menu and begins a warm-up immediately |
| T2 | Across 1,000 `/rtp` trials in each dimension, no landing is in liquid, fire, or the void, and every landing has two breathable nodes above |
| T3 | Moving more than 1 node during the warm-up cancels the teleport; the player is told |
| T4 | Taking damage during the warm-up cancels the teleport |
| T5 | A failed search (all attempts exhausted) sends the failure message and starts no cooldown |
| T6 | The cooldown blocks a second `/rtp` and the tier1 cooldown is shorter |
| T7 | `/tpa` to a blocking target produces a generic refusal revealing nothing about which rule fired |
| T8 | Accepting a `/tpa` warms up the sender; accepting a `/tpahere` warms up the target |
| T9 | A request where either party is tagged, dies or disconnects before acceptance is cancelled |
| T10 | `/world` returns to the exact position before the last teleport and does not chain |
| T11 | Two mutually blocking players are never paired by `/rtpqueue` |
| T12 | The RTP zone teleports a player who stands in it for `rtp.zone_delay`, and does not teleport one who passes through |
| T13 | `tp.confirm_menu` shows the Accept/Deny formspec with `Deny` left/red and `Accept` right/green |

## 10. Open questions

| Id | Question |
|---|---|
| V-13 | RTP cooldowns, ranges and region list — unobserved. Narration implies a short cooldown |
| V-14 | Teleport request expiry and warm-up duration — unobserved |
| V-25 | Spawn layout: lobbies, RTP zone and warps — unobserved |
| V-63 | Is there a visible warm-up countdown on `/rtp`, or is the wait silent? The narrator's "just wait a second" [F0037] suggests a delay exists but nothing is shown |
| V-64 | Does `/rtp` announce the arrival (coordinates, biome) in chat? |
| V-65 | Does `/rtpqueue` still exist post-beta, and what are its matchmaking rules? |
| V-66 | Does `/spawn` open a menu of named lobbies on the current server, and what are they called? |
| V-67 | Does `/world` chain (multiple history entries) or hold exactly one? |

### Implementation notes (f08 implementer, 2026-09-22)

| Id | Note |
|---|---|
| Q-1 | **Engine bug found while testing: pattern-mode `string.find`/`string.match` is unreliable in the current LuaJIT build** (`/opt/homebrew/bin/luajit`, 2.1.1767980792). Repro: `("ab-cd"):find("b-c")` returns `4` (correct: `2 4`); `("friedcake/dev-tests/x"):find("dev-tests")` returns `nil` (the substring is present); `("1.7,0.8;"):find("%.%d+,%.%d+")` returns `nil`. Plain-mode find (fourth arg `true`) is always correct. smp_tp/smp_rtpqueue ship **no pattern-mode calls in their own code paths** (trim and lobby-field parsing use byte/sub operations); dev-tests use plain-mode find. Existing smp_core/smp_economy pattern uses (`^%s*(.-)%s*$`, `@(%d+)`) were spot-checked and currently work, but this should be investigated at the engine level — it can silently break any mod code. |
| Q-2 | `mcl_title.set`'s `stay` is in Minecraft ticks (20/s). The spec example's `stay = 1` would vanish after 50 ms; smp_tp uses `stay = 20` re-issued once per second for the countdown. |
| Q-3 | Ender-pearl-on-death (§4.6) is intentionally **not** implemented in f08: it requires hooking the mcl_throwing pearl entity's death and is low priority. Flagged for a later phase. |
| Q-4 | `/smp test <feature>` (dispatcher in smp_economy, f01's file) is hardcoded to `smp_core` — same issue f03 and f04 hit. smp_tp and smp_rtpqueue both ship `test.lua`; `/smp test smp_tp` reports "Unknown test target" until the dispatcher is generalized. **Proposed shared change:** the dispatcher maps `<target>` → `core.get_modpath(<target>) .. "/test.lua"` for any loaded mod. |
| Q-5 | **Fix-wave record (fix brief, 2026-09-25):** see §10.1 below. |

## Proposed shared changes

The following mirror rows should be added to `spec/shared/06-config-reference.md` to match the keys read by `smp_tp` (beyond the existing `smp_tp.tp.*`, `smp_tp.rtp.*`, `smp_tp.rtpqueue.*`, `smp_tp.tpa.*` rows). All defaults are the hardcoded values currently in `cfg.rtp.cooldown` — bare `/rtp` with **no menu** and the 60/30 s cooldowns are Confirmed-OK behaviour and must not shift.

| Key | Default | Status | Spec |
|---|---|---|---|
| `rtp.cooldown_tier2` | 30 s | PROPOSED | f08 |
| `rtp.cooldown_tier3` | 30 s | PROPOSED | f08 |
| `rtp.cooldown_media` | 60 s — falls back to the default when unset | PROPOSED | f08 |

These three keys are read via `get_num()` in `config.lua:93-97` but were missing from the mirror after P2's rename pass (D7). The other `smp_tp.*` cooldown keys (tpa/spawn/warp/world/back) are **not** read from settings — they are hardcoded in `cfg.tp.cooldown` and therefore do not require mirror rows.

## 10.1 Fix-wave record (fix brief, 2026-09-25)

| Row | Outcome | Evidence (file:line) |
|---|---|---|
| TP1 | VERIFIED | `smp_tp/init.lua:20` uses `core.get_modpath`; no `core.modpath` in `smp_tp`/`smp_rtpqueue` |
| TP2 | CLOSED | `warmup.lua:75-79` `either_tagged()` checks both parties; `tick_countdown` calls it every tick; `teleport_with_warmup` checks at start (116-117) and fire (167) |
| TP3 | CLOSED | (a) `requests.lua:181-185` drops request on sender-tagged; `187-191` drops on acceptor-tagged; (b) `requests.lua:44-46` `cancel_requests_of` uses `drop_request_out` for sender's outbox |
| TP4 | CLOSED | `config.lua:185-192` probes `core.get_world_border` before assigning `smp_tp._border` and `cfg.rtp.max_radius`; fallback 30000 preserved |
| TP5 | CLOSED | `config.lua:119-125` reads `world.spawn_protect_radius` (default 128) into `cfg.rtp.spawn_protect_radius`; `rtp.lua:170-174` excludes landings inside radius |
| TP6 | DEFERRED | Spec §4.6 / §10 Q-3 explicitly defers pearls; no code added; cross-ref `fixes/f10-combat.md` `combat.keep_pearls_on_death` has no consumer |
| TP7 | CLOSED (spec amended) | §5 now states queue state lives in `smp_rtpqueue.members`; struck the phantom `rtpqueue = {joined_at}` field; behaviour unchanged |
| TP8 | CLOSED | (a) `rtp.cooldown_tier2`, `rtp.cooldown_tier3`, `rtp.cooldown_media` documented as PROPOSED in §7 and proposed in `## Proposed shared changes`; (b) `rtp.menu_enabled` read via `setting()` at `config.lua:75-81`; (c) `rtpqueue.min/max_separation` read at `config.lua:156-159`; other `smp_tp.*` cooldowns are hardcoded, not settings keys |
| TP9 | CLOSED | `warmup.lua:180-188` writes `last_teleport_from` only on successful fire; cancelled warm-up leaves origin untouched |
| TP10 | CLOSED | `formspec.lua:22` `TRIANGLE = "\226\154\160"` (U+26A0); test asserts three-byte glyph, no lone `\241` |
| TP11 | CLOSED | `formspec.lua:39,43,44` `S("Teleport Request")`, `S("Deny")`, `S("Accept")`; `formspec.lua:92,96` `S("Spawn")`, `S("Main")` all through translator |
| TP12 | CLOSED (spec amended) | §8 line 345 changed to `stay = 20` (docs follow renderer — D5 precedent); `warmup.lua:43` uses `stay = 20`; Q-2 note retained |
| TP13 | CLOSED | `smp_rtpqueue/init.lua:53-54` `blocked()` calls `smp_tp.bridge.blocks_only`; `bridge.lua:47-55` delegates to `smp_social.blocks_only`; f11-finish merged 2026-09-25, predicate available at dispatch |
