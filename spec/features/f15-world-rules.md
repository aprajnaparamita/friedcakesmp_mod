# f15 — World Rules and Server Configuration

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | none — server configuration and policy, plus small hooks in `smp_core` |
| Phase | P0 — spawn protection and the world border shape where every other feature may operate |
| Depends on | — |
| Frame evidence | **0 frames** |
| Confidence | **Research only.** The rules themselves are documented [S18]; their enforcement mapping to Luanti is this specification's proposal. |

This file covers the rules of the reference server, the world shape (spawn
protection, border, entity caps) and the June 2026 mechanic changes, mapped
to Luanti equivalents.

## 2. Commands

Not applicable. This feature exposes no player commands; its surface is
configuration and moderation policy. Staff-facing commands (`/report`,
`/helpop`) live in `f11`; audit tooling (`/ledger`) in `f01`.

## 3. Observed UI

**None.** Rules and world configuration are invisible in the video. The only
adjacent observation is the scale of the world implied by coordinates: the
player's home `rock` sits at X −47,114, Z −12,735 [F0055] — beyond Luanti's
default map generation radius, which constrains §4.2 directly.

## 4. Behaviour

### 4.1 Rules and enforcement

The reference server's rules [S18] and their Luanti enforcement:

| Rule | Luanti enforcement | Status |
|---|---|---|
| No hacked clients or unfair modifications (movement, inventory, health indicators, radar, ESP, freecam, automatic placement, macros, auto-clickers) | Keep server-side anticheat enabled (`disable_anticheat = false`), restrict client-side mods with `csm_restriction_flags`, staff tooling for the rest | PROPOSED mapping |
| No bug abuse or item duplication | `shared §2.6` economic-integrity rules | PROPOSED mapping |
| No real-money trading, cross-server trading or external gambling | Policy and moderation only | N/A to code |
| At most five accounts per person | Count accounts per IP with `core.get_player_ip` on join; **flag, do not ban automatically** | PROPOSED |
| No attempts to discover the server seed | Never expose the seed through commands, menus or the API export (`f14`) | PROPOSED |
| No staff impersonation | Name filters on join | PROPOSED |
| No voice-chat spam | N/A — no voice channel (`shared/01-overview.md §1.3`) | N/A |

Raiding and griefing are **not** prohibited; bases are expected to be found
and raided [S1][S18]. No land-claim mod is installed (`PROPOSED` default).

### 4.2 World shape

1. **Spawn protection.** A protected spawn area enforced through
   `core.is_protected`, radius `world.spawn_protect_radius` (`PROPOSED`
   128). PvP is disabled inside it (`f10`).
2. **World border.** The reference server plans an expansion to 30,000,000
   blocks in each direction [S1][S22]. Luanti's hard map limit is about
   31,000 nodes from the origin (`mapgen_limit`), so the border is set with
   `mapgen_limit` plus a soft border that pushes players back inside
   (`PROPOSED`). The observed coordinate X −47,114 [F0055] exceeds ±31,000 —
   that is the Java server, not a target for Luanti; the Luanti border is
   what `mapgen_limit` allows.
3. **Entity caps.** The reference server raised its creeper limit to 2,500
   and its item-frame limit to 1,500 in June 2026 [S2]. Luanti equivalents:
   `max_objects_per_block` plus per-type caps sized for Luanti's entity
   costs (`PROPOSED`; Luanti numbers will be far lower).
4. **Mapgen.** Mineclonia default. No claim, plot or protection mods beyond
   the spawn area.

### 4.3 June 2026 mechanic changes

| Reference-server change [S2] | Luanti mapping | Status |
|---|---|---|
| TNT duplication enabled | N/A — a Java-specific mechanic | N/A |
| Bedrock breaking and access below Overworld bedrock | Optional; `mcl_core:bedrock` is unbreakable by default. Off | PROPOSED |
| Vanilla bed and respawn-position logic | Provided by Mineclonia (`mcl_spawn`) | nothing to build |
| Portal cooldown and axis fixes; map scaling | Mineclonia parity | nothing to build |
| Hopper speed kept non-vanilla | Optional tuning of `mcl_hoppers` | PROPOSED, off |
| Attribute swapping enabled | N/A — a Java 1.21 mechanic | N/A |

### 4.4 Performance budget (normative)

Restated from `shared §2.7` so the operations checklist lives here:

- No ABMs anywhere in the `smp_` mod set.
- Global-step work at most O(online players) per second.
- Storage flushes every 10 s; spawner node timers every 60 s; leaderboard
  snapshots every 300 s.
- Menu rendering bounded by page size, never table size.
- Entity caps (§4.2) enforced at spawn time by configuration, not by a
  scanning ABM.

## 5. Data schema

Not applicable. The account-per-IP counter is derived at join time from
`core.get_player_ip` and the player database; no table is owned.

## 6. Algorithms

```lua
-- spawn protection: one callback, O(1) per check
local r = cfg.world.spawn_protect_radius
core.register_on_protection_violation(function(pos, name)
  core.chat_send_player(name, S("This area is protected."))
end)
function smp_core.is_spawn_protected(pos)
  return math.abs(pos.x) <= r and math.abs(pos.z) <= r
         and mcl_worlds.pos_to_dimension(pos) == "overworld"
end
-- registered into core.is_protected via core.register_on_protection_violation
-- plus old_is_protected wrapping in core.is_protected's chain

-- soft world border, checked once per second per player (globalstep budget)
local limit = tonumber(core.get_mapgen_setting("mapgen_limit")) or 31000
function smp_core.enforce_border(player)
  local p = player:get_pos()
  if math.abs(p.x) > limit - 16 or math.abs(p.z) > limit - 16 then
    player:set_pos(vector.new(
      math.max(-limit + 16, math.min(limit - 16, p.x)), p.y,
      math.max(-limit + 16, math.min(limit - 16, p.z))))
    core.chat_send_player(player:get_player_name(), S("You have reached the world border."))
  end
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `world.spawn_protect_radius` | 128 | PROPOSED |
| `world.soft_border` | true | PROPOSED |
| `world.border_margin` | 16 nodes inside `mapgen_limit` | PROPOSED |
| `world.max_accounts_per_ip` | 5 (flag only) | LIVE [S18]; enforcement PROPOSED |
| `world.entity_caps` | `{}` (per-type, sized for Luanti) | PROPOSED |
| `world.bedrock_breakable` | false | PROPOSED |

## 8. Mineclonia implementation

- Spawn protection MUST integrate with `core.is_protected` so every mod's
  protection checks (`f07` spawner digging, `f06` amethyst tools) honour it
  automatically.
- The border check is a once-per-second per-player test inside the existing
  globalstep budget — no per-node scanning.
- `csm_restriction_flags` and `disable_anticheat` are `minetest.conf`
  settings; ship a recommended `minetest.conf` snippet with the mod set
  rather than trying to set them from Lua.
- Name filters and the seed rule are policy enforced by configuration; no
  code beyond a join-time name check.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | Digging inside the spawn radius is refused through `core.is_protected`; digging outside succeeds |
| T2 | PvP inside the spawn area does not tag either player (integration with `f10`) |
| T3 | A player crossing the soft border is moved back inside and told |
| T4 | `/rtp` never lands a player inside the protected radius or outside the border (integration with `f08`) |
| T5 | A sixth distinct account joining from one IP raises a staff flag and is not blocked |
| T6 | No command, menu or API output exposes the map seed |
| T7 | The full `smp_` mod set registers zero ABMs |

## 10. Open questions

| Id | Question |
|---|---|
| V-80 | Spawn layout (lobbies, RTP zone, warps) — cross-listed with `f08` V-25; determines the protected area's contents |
| V-81 | What are the reference server's actual entity caps post-June-2026, and what Luanti equivalents keep parity of feel? |
| V-82 | Is bedrock breaking currently enabled on the reference server? Documented as a June change; persistence unverified |
| V-26 | Does the reference server have the rotating NPC trader (`/billford`) one clone includes [C2]? If it exists it gets its own feature file |
