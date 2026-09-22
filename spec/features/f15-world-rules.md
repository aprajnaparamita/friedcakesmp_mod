# f15 — World Rules and Server Configuration

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | none — server configuration and policy; the four hooks shipped in a new `smp_world` mod (the spec originally placed them in `smp_core`; fold-in offer in §10 → Proposed shared changes) |
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

**Strings owned by this feature** (PROPOSED house style, no frame evidence —
they belong here, not in `08-ui-strings.md`): `This area is protected.`
(refusal inside the spawn area, §6) and `You have reached the world border.`
(soft-border push-back, §6), plus two added with the shipped implementation:
`Alt-account flag: @1 accounts from one IP (joiner: @2)` (staff
notification, §10.1) and `This name is reserved for staff` (kick reason under
`world.staff_name_action = kick`, §10.1).

## 4. Behaviour

### 4.1 Rules and enforcement

The reference server's rules [S18] and their Luanti enforcement:

| Rule | Luanti enforcement | Status |
|---|---|---|
| No hacked clients or unfair modifications (movement, inventory, health indicators, radar, ESP, freecam, automatic placement, macros, auto-clickers) | Keep server-side anticheat enabled — ship `anticheat_flags = digging,interaction,movement`; `disable_anticheat` (the original spelling) has been **removed from the engine** and is migrated to this key (engine-verified 2026-09-23, §10.1); restrict client-side mods with `csm_restriction_flags = 63` (engine default 62); staff tooling for the rest | PROPOSED mapping |
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

**Implementation deviation (PROPOSED — `V-88 (proposed)`, §10):** no store
maps accounts to IPs as written — `smp_store` player records have no IP
field, `core.get_player_ip` is online-only, and offline player meta is
unreachable. As shipped, `smp_world` keeps a **sha1-keyed** index (key
`accounts_per_ip`) in its own mod storage; no `smp_store` table is added or
owned. See §10.1.

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

**As shipped (§10.1):** in `smp_world`, not `smp_core` — the exports are
`smp_world.is_spawn_protected` and `smp_world.enforce_border`; the
`core.is_protected` wrap also honours the engine's `protection_bypass`
privilege; `mapgen_limit` is read **live** per check with fallback 31007
(the engine default, not the 31000 above); `mapgen_limit = 0` disables the
border; and a one-second accumulator sweeps connected players once per
accumulated second (sub-second remainder kept, whole seconds discarded, so a
lag spike never causes a burst) instead of checking per server step.

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `world.spawn_protect_radius` | 128 | PROPOSED |
| `world.soft_border` | true | PROPOSED |
| `world.border_margin` | 16 nodes inside `mapgen_limit` | PROPOSED |
| `world.max_accounts_per_ip` | 5 (flag only) | LIVE [S18]; enforcement PROPOSED |
| `world.staff_name_filter` | comma-separated Lua patterns — built-in default list; `""` disables | PROPOSED (added by f15) |
| `world.staff_name_action` | `flag` (`kick` and `off` supported; unknown values degrade to `flag`) | PROPOSED (added by f15) |
| `world.entity_caps` | `{}` (per-type, sized for Luanti) | PROPOSED — inert pending `V-81` |
| `world.bedrock_breakable` | false | PROPOSED — inert pending `V-82` |

## 8. Mineclonia implementation

- Spawn protection MUST integrate with `core.is_protected` so every mod's
  protection checks (`f07` spawner digging, `f06` amethyst tools) honour it
  automatically.
- The border check is a once-per-second per-player test inside the existing
  globalstep budget — no per-node scanning.
- `csm_restriction_flags` and `anticheat_flags` (successor of the removed
  `disable_anticheat`) are `minetest.conf` settings; ship a recommended
  `minetest.conf` snippet (`friedcake/minetest.conf.example`) with the mod
  set rather than trying to set them from Lua.
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
| V-88 (proposed) | §5 says the account-per-IP counter is "derived … from the player database … no table is owned", but no store maps accounts to IPs (`smp_store` has no IP field, `core.get_player_ip` is online-only, offline player meta is unreachable). Shipped as a sha1-keyed index in `smp_world`'s own mod storage — integrator: confirm that contract, or grant an explicit `last_ip_hash` field in `smp_store` and move the index there. Cross-list in `spec/plan/open-questions.md` when you next touch it |

### 10.1 Implementation notes (f15, 2026-09-23)

Shipped on `agent/f15-world-rules` as `friedcake/minetest.conf.example`,
`friedcake/WORLD_RULES.md` and the `smp_world` mod (four hooks + in-game
`test.lua`), verified by `dev-tests/test_world.lua` — **99 checks, T1, T3,
T5, T6 guard, T7 green** under `tools/agent-flow.sh test`.

**PROPOSED decisions taken while implementing**

| Decision | Choice | Why |
|---|---|---|
| Hook location | new `smp_world` mod, `depends = smp_core, mcl_worlds`, enabled below the existing `modpack.conf` entries | `smp_core` is integrator-owned (AGENTS.md rule 4); fold-in offer in Proposed shared changes below |
| Spawn protection | square of half-width `world.spawn_protect_radius` (128) around the origin, **Overworld only**, `O(1)` | §4.2.1 default; layout itself is `V-80`/`f08`'s |
| Chain composition | wraps `core.is_protected`, never replaces it; verified to survive an outer wrapper (later-loaded mod wrapping ours) | §6/§8; Mineclonia's `mcl_levelgen` already wraps the engine default — both directions compose |
| `protection_bypass` | honoured inside the radius | engine privilege text is "Can bypass node protection in the world"; builtin dig/place never checks it, so the wrap must — otherwise staff cannot build at spawn |
| Violation message | registered unconditionally per §6 pseudocode (no `is_spawn_protected` guard in the callback) | Mineclonia's only other source today is `mcl_levelgen`'s ungenerated-chunk guard, where the same message is accurate |
| Border read | `core.get_mapgen_setting("mapgen_limit")` **live**, fallback 31007 (engine default; §6's `31000` is stale), `0`/unset → no border | value is stored **per world** (`map_meta.txt` wins); live read honours post-startup edits and made the unlimited case testable |
| Border cadence | 1 s accumulator: keeps the sub-second remainder, discards whole seconds | one sweep over connected players per accumulated second — `O(online)`/s (§4.4); a lag spike sweeps once instead of bursting |
| Account index | `smp_world` mod storage, key `accounts_per_ip`, buckets keyed `sha1(ip)` — IPs never stored in the clear | see §5 deviation note and `V-88 (proposed)` |
| Flag rule | flag when a **new** distinct account pushes the count past `world.max_accounts_per_ip`; rejoin never re-flags; handler returns always — it *cannot* block | T5 wording ("sixth distinct account … not blocked") and the rule's "flag, do not ban automatically" [S18] |
| Name filter | `world.staff_name_filter`: comma-separated Lua patterns on the lower-cased name; built-in default list anchors admin/staff/mod/moderator/operator/owner/server with digit/separator tails (so `model` and `administrator2` pass, `Admin_Dude` and `staff` match); `""` disables | §4.1 row was silent on mechanics; precision over recall, operators tune |
| Filter action | `world.staff_name_action = flag` default; `kick` / `off` supported; unknown values degrade to `flag`, never `kick` | moderation-first, consistent with the account-per-IP philosophy; the kick refusal string is PROPOSED (§3) |
| CSM flags | `csm_restriction_flags = 63` (all six bits; engine default 62) | the rule says *restrict* client-side mods; bit 0 additionally stops client mods loading (engine enum verified in `networkprotocol.h`) |
| Anticheat key | ship `anticheat_flags = digging,interaction,movement` | `disable_anticheat` was **removed from the engine** — `migratesettings.h` rewrites it to `anticheat_flags` on load; §4.1/§8 spellings updated above (engine-verified 2026-09-23, `~/dev/luanti`) |
| Entity caps | `max_objects_per_block = 256` pinned explicitly (engine default); `world.entity_caps = {}` inert, no code reads it | `V-81` unobserved — no invented numbers |
| Bedrock | no code; `world.bedrock_breakable = false` kept as a commented note | `V-82` unverified — Mineclonia default (unbreakable) retained |
| New strings | `Alt-account flag: @1 accounts from one IP (joiner: @2)`, `Staff impersonation suspected: @1 matched '@2'`, `This name is reserved for staff` | house style (sentence case, §0.5); the two specced strings `This area is protected.` / `You have reached the world border.` reproduced **verbatim** (§3, §6) |
| ABM invariant | runtime check over `core.registered_abms` by `mod_origin` after `register_on_mods_loaded`, plus a static source scan in the dev-test | engine stamps `mod_origin` (`builtin/game/register.lua`) — T7 is enforceable at runtime *and* statically |

**T6 findings (seed — negative test, verify + document).** A tree-wide
search for `get_mapgen_setting("seed")`, `get_mapgen_params` (its table
carries `seed`) and `mapgen_seed` across `friedcake/` and `spec/` on
2026-09-23 found **zero occurrences** — nothing leaks today, including the
`f14` spec's `/api` export description. The same scan is part of
`dev-tests/test_world.lua`, so a future mod cannot introduce a leak
silently; the rule itself is documented in `WORLD_RULES.md §5` (including
the reminder that `map_meta.txt` is host-side only and must never be
shipped to clients).

**V dispositions.** `V-80` untouched (spawn layout stays `f08`'s; f15
protects the 128-square regardless). `V-81` inert-by-default: engine
default pinned, `world.entity_caps = {}` has no reader until evidence
lands. `V-82` default-retained: Mineclonia bedrock stays unbreakable.
`V-26` untouched (f16). New: `V-88 (proposed)` above.

**Acceptance status.** T1, T3, T5, T6, T7 are implemented and green in
both `dev-tests/test_world.lua` (99 checks) and in-game
`smp_world/test.lua`. T2 (`f10` PvP) and T4 (`f08` `/rtp`) are integration
tests owned by those features; the contract they need is live today —
`core.is_protected` answers correctly inside spawn (honouring
`protection_bypass`), plus the `O(1)` exports
`smp_world.is_spawn_protected(pos)`, `smp_world.spawn_radius()` and
`smp_world.border_limit()`. X10 (the cascade: no digging with drill/axe/
shovel at spawn) holds as soon as `f06`/`f07` land — both specs route
their digging through `core.is_protected`, so no edits to those mods are
needed; only their unmerged branches remain to be verified at integration.

**Not done here (deliberately):** `f10`'s no-PvP/no-bounty-at-spawn
decisions, `f08`'s `/rtp` clip, granting `protection_bypass` to staff,
and the `/smp test smp_world` dispatcher line — all proposed below for
the owning side.

## Proposed shared changes

This feature edits neither `spec/shared/` nor `spec/plan/`; the following
are proposals for the integrator:

1. **Fold the `smp_world` hooks into `smp_core`?** §6/§8 originally placed
   `is_spawn_protected` / `enforce_border` there. They shipped in
   `smp_world` because `smp_core` is integrator-owned. Folding means
   moving the six sections of `smp_world/init.lua` behind `smp_core`'s
   namespace, keeping the exports (alias `smp_world.*` or rename — `f08`
   and `f10` consume them either way), and dropping one `load_mod` line.
   Keeping `smp_world` as a standalone P0 mod is equally fine and keeps
   world policy separate from the formatter/menu core. The code is
   namespace-clean: one global (`smp_world`), zero edits to any other mod.
2. **Generic `/smp test` dispatch (touches `smp_economy`, f01's file).**
   The handler hardcodes `target == "" or target == "smp_core"`. One line
   generalising it — look up `core.get_modpath(target)`, `loadfile` its
   `test.lua`, `pcall`, render `{passed, failed, lines}` exactly like
   `run_smp_core_tests` — would serve every feature; `smp_world/test.lua`
   already honours the contract (`{passed, failed, lines}`).
3. **`protection_bypass` for staff (touches `smp_admin`).** Neither
   `smp_admin` nor `smp_moderator` grants `protection_bypass`, so today
   nobody can dig inside the spawn radius (builtin does not check the
   privilege; `smp_world` honours it). Consider granting it to
   `smp_admin` holders.
4. **For `f08` §4.2 and `f10` §4.1** (coordination, not shared edits):
   use `smp_world.is_spawn_protected(pos)` for the `/rtp` landing clip and
   the PvP/no-bounty-in-spawn decisions, `smp_world.border_limit()` for
   clipping candidates to the world border, `smp_world.spawn_radius()` for
   the ring maths — all `O(1)`, no yields between validate and mutate.
5. **Cross-list `V-88 (proposed)`** in `spec/plan/open-questions.md` the
   next time the plan is touched (question IDs are integrator-owned).
