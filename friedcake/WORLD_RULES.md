# WORLD_RULES — reference-server rules mapped to Luanti

Owner: **f15** (`spec/features/f15-world-rules.md`). This file is the
documentation half of f15's config package: it explains every setting in
`minetest.conf.example`, restates the rule → Luanti mapping from the spec
(§4.1, §4.2, §4.3), and records what the code hooks in `smp_world` enforce.

**Evidence discipline** (`spec/shared/00-conventions.md §0.2`): the rule
*statements* are documented reference-server behaviour **LIVE [S18]**; the
*enforcement mapping* to Luanti is this specification's proposal — every row
below carries its status. Frame evidence for f15 is 0 frames.

## Applying this package

1. Copy the wanted settings from `minetest.conf.example` into the server's
   `minetest.conf` (or pass them on the command line).
2. Keep `load_mod = smp_world` in `modpack.conf` — the four hooks (spawn
   protection, soft border, account-per-IP flag, name filter) live there.
3. Engine pins were verified against the local Luanti source (`~/dev/luanti`)
   on 2026-09-23; `mapgen_limit` is stored per world, so set it before the
   world's first run or fix up `map_meta.txt`.

## 1. Rules and enforcement (spec §4.1)

| Rule [S18] | Luanti enforcement | Implemented by | Status |
|---|---|---|---|
| No hacked clients or unfair modifications (movement, inventory, health indicators, radar, ESP, freecam, automatic placement, macros, auto-clickers) | Server anticheat on: `anticheat_flags = digging,interaction,movement` (engine-verified successor of the spec's `disable_anticheat = false`, which current Luanti migrates away); client-side mods restricted with `csm_restriction_flags = 63`; staff tooling for the rest | `minetest.conf.example` | PROPOSED mapping (engine-verified 2026-09-23) |
| No bug abuse or item duplication | `shared §2.6` economic-integrity rules (escrow, version-checked menus, no yields between validate and mutate) | other features' code | PROPOSED mapping |
| No real-money trading, cross-server trading or external gambling | Policy and moderation only | — | N/A to code |
| At most five accounts per person | Count distinct accounts per IP (`core.get_player_ip` on join, persisted index); **flag, do not ban automatically** | `smp_world` join hook | PROPOSED |
| No attempts to discover the server seed | Never expose the seed through commands, menus or the API export (f14); guarded by a scan (§5 below) | policy + `dev-tests/test_world.lua` guard | PROPOSED |
| No staff impersonation | Name filter on join (`world.staff_name_filter` patterns; default action flags staff, optionally kicks) | `smp_world` join hook | PROPOSED |
| No voice-chat spam | N/A — no voice channel (`shared/01-overview.md §1.3`) | — | N/A |

Raiding and griefing are **not** prohibited; bases are expected to be found
and raided [S1][S18]. No land-claim mod is installed (PROPOSED default) —
the only protected area is the spawn square below.

## 2. World shape (spec §4.2)

### 2.1 Spawn protection

- Square of half-width `world.spawn_protect_radius` (**PROPOSED 128**) around
  the origin, **Overworld only** (`mcl_worlds.pos_to_dimension(pos) ==
  "overworld"`).
- Enforced **through `core.is_protected`** — `smp_world` wraps the existing
  chain (engine default → Mineclonia's `mcl_levelgen` area protection →
  `smp_world`) and never replaces it. Every mod that asks `core.is_protected`
  therefore honours it automatically: f07 spawner digging, f06 amethyst tools,
  f10 PvP-area decisions, f08 `/rtp` landing checks.
- A refused dig/place fires `register_on_protection_violation`, and the
  player sees the verbatim f15 string: `This area is protected.`
- Holders of the engine privilege `protection_bypass` ("Can bypass node
  protection in the world") are exempt inside the radius, so staff can build
  at spawn.
- PvP is disabled inside the area — f10's damage hook consults the same
  chain (f10 §4.1; T2, X10).

### 2.2 World border

- Luanti's hard map-generation limit is **31007 nodes** (`mapgen_limit`,
  engine max, stored per world). The reference server's planned
  30,000,000-block expansion [S1][S22] has no Luanti equivalent; the observed
  coordinate X −47,114 [F0055] belongs to the Java server and is explicitly
  **not** a target.
- A **soft border** pushes players back inside `mapgen_limit -
  world.border_margin` (PROPOSED 16 nodes), checked **once per second per
  online player** in a single globalstep — O(online players) per second, no
  per-node scanning (spec §4.4 budget).
- A player who crosses it is moved to the clamped position and told the
  verbatim f15 string: `You have reached the world border.`
- `mapgen_limit = 0` (unlimited) disables the soft border.

### 2.3 Entity caps — V-81 open

The reference server's June 2026 caps (creepers 2,500, item frames 1,500
[S2]) are **unobserved for Luanti** (V-81). Per `world.entity_caps = {}`
(spec §7), no per-type caps are configured and **no numbers are invented**;
`max_objects_per_block` keeps the engine default 256, pinned explicitly for
documentation. Caps, when V-81 closes, are enforced at spawn time by
configuration — never by a scanning ABM (§4.4).

### 2.4 Mapgen

Mineclonia default. No claim, plot or protection mod beyond the spawn area.

## 3. June 2026 mechanic changes (spec §4.3)

| Reference-server change [S2] | Luanti mapping | Shipped? |
|---|---|---|
| TNT duplication enabled | N/A — Java-specific mechanic | N/A |
| Bedrock breaking / access below Overworld bedrock | `mcl_core:bedrock` unbreakable by default; `world.bedrock_breakable = false` (V-82 unverified) | Off, default retained |
| Vanilla bed and respawn logic | `mcl_spawn` | Nothing to build |
| Portal cooldown and axis fixes; map scaling | Mineclonia parity | Nothing to build |
| Hopper speed kept non-vanilla | Optional `mcl_hoppers` tuning | Off (PROPOSED) |
| Attribute swapping enabled | N/A — Java 1.21 mechanic | N/A |

## 4. Performance budget (normative, spec §4.4)

- **No ABMs anywhere in the `smp_` mod set.** Guarded by
  `dev-tests/test_world.lua` (static scan of every `smp_` mod's Lua sources)
  and by `smp_world`'s post-load check of `core.registered_abms` (entries
  carry `mod_origin`) — see T7.
- Global-step work at most O(online players) per second — the border sweep
  is the only f15 globalstep and runs at 1 Hz.
- Storage flushes every 10 s; spawner node timers every 60 s; leaderboard
  snapshots every 300 s (owned by `smp_store` / f07 / f14).
- Menu rendering bounded by page size, never table size.

## 5. The seed rule (spec §4.1, acceptance T6)

**The map seed must never reach a player.** No command, menu or API output
may call `core.get_mapgen_setting("seed")` or the deprecated
`core.get_mapgen_params()` (whose table carries `seed`), and no chatcommand
may print `mapgen_seed`. This includes f14's `/api` world export.

T6 is a negative test: there is nothing to implement, only to verify.

- **Findings (2026-09-23):** a tree-wide search for
  `get_mapgen_setting("seed")`, `get_mapgen_params` and `mapgen_seed` across
  `friedcake/` and `spec/` found **zero occurrences** — nothing leaks today,
  including the f14 spec's `/api` description.
- **Guard:** `friedcake/dev-tests/test_world.lua` repeats that scan on every
  run, so a future mod cannot introduce a leak silently.

Server operators: the seed is also readable from `map_meta.txt` on the host
— that file is server-side only; never ship it to clients (the engine never
sends it; do not add it to any HTTP export).

## 6. Hooks shipped in `smp_world` (for other features)

| Export | Purpose | Consumer |
|---|---|---|
| `smp_world.is_spawn_protected(pos)` | O(1) spawn-square test (Overworld only) | f10 (no PvP tag, no bounty payout inside), f08 (`/rtp` landing must be outside it) |
| `smp_world.spawn_radius()` | configured radius (128) | f08 RTP ring clipping |
| `smp_world.border_limit()` | soft-border clamp coordinate, or `false` when unlimited | f08 (RTP candidates clipped to the border) |
| `smp_world.enforce_border(player)` | clamp one player, message them | globalstep (internal) |
| `smp_world.accounts_on_ip(ip)` | distinct-account count for an IP | moderation / future f01 alt-flag |
| `smp_world.flag_staff(msg)` | log + notify online `smp_admin`/`smp_moderator` | internal; reusable by other mods |
| `core.is_protected` | wrapped chain | everyone (f06, f07, f10, f08) |

## 7. Configuration keys (spec §7 + f15 additions)

| Key | Default | Read by | Status |
|---|---|---|---|
| `world.spawn_protect_radius` | 128 | `smp_world.is_spawn_protected` | PROPOSED |
| `world.soft_border` | true | `smp_world.enforce_border` | PROPOSED |
| `world.border_margin` | 16 | `smp_world.border_limit` | PROPOSED |
| `world.max_accounts_per_ip` | 5 (flag only) | join hook | LIVE rule [S18]; enforcement PROPOSED |
| `world.staff_name_filter` | built-in pattern list; `""` disables | join hook | PROPOSED (f15 §7) |
| `world.staff_name_action` | `flag` (`kick` / `off` supported) | join hook | PROPOSED (f15 §7) |
| `world.entity_caps` | `{}` (per-type, sized for Luanti) | nothing yet — V-81 | PROPOSED, inert |
| `world.bedrock_breakable` | false | nothing yet — V-82 | PROPOSED, inert |

Engine-side keys: `anticheat_flags`, `csm_restriction_flags`,
`mapgen_limit`, `max_objects_per_block`, `secure.trusted_mods` — all pinned
and commented in `minetest.conf.example`.

## 8. Open items

| Id | Disposition |
|---|---|
| V-80 | Spawn layout (lobbies, RTP zone, warps) belongs to f08; f15 protects the 128-radius Overworld square around the origin regardless |
| V-81 | Entity caps unobserved — `world.entity_caps` stays `{}`, `max_objects_per_block` stays at the engine default; **no invented numbers** |
| V-82 | Bedrock breaking unverified — Mineclonia default (unbreakable) retained |
| V-26 | Rotating NPC trader — unrelated to f15; remains f16's call |
| Account-per-IP storage | The spec says the counter is "derived … from the player database … no table is owned", but no store maps accounts to IPs (smp_store has no IP field, `core.get_player_ip` is online-only, offline player meta is unreachable). `smp_world` keeps a sha1-keyed index in its **own mod storage** — see the proposal in f15 §10 |
