# f10 — Combat Tag, Combat Log and Bounties

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_combat`, `smp_bounty` |
| Phase | P5 |
| Depends on | `f01-economy-core` (bounty escrow and payout), `mcl_death_drop` (combat-log drops); consumed by `f08` (teleport blocking), `f02` (`/sell` allowed in combat), `f05` (Quick Buy blocked), `f06` (Shard Pickaxe blocked) |
| Frame evidence | **0 frames** |
| Confidence | **Research only.** Combat never occurs in the source video. The tag's existence is implied by documented combat restrictions [S7][S19]; its duration, display and full block list are unverified. |

The reference server documents restrictions that apply "during combat"
[S7][S19], which implies a combat tag, but publishes neither its duration nor
its complete rules [S19]. The structure below is the clone consensus [C1]
fitted to the documented restriction points.

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/bounty` | `/bounties` | `[player]` | Bounty list, or one player's bounty | LIVE [S24] |
| `/bounty add` | — | `<player> <amount>` | Place or raise a bounty | LIVE [S24] |
| `/bountyadmin` | — | `clear <player>` | Remove a bounty, with refund (admin) | PROPOSED |
| `/combat` | — | `untag <player>` | Clear a combat tag (admin) | PROPOSED |

## 3. Observed UI

**None.** No frame shows combat, a combat tag display or a bounty menu.

Proposed elements, in the observed grammar, to be replaced by evidence:

- **Combat tag countdown** on the action bar (the channel the reference
  server uses for `Delivering...` [F0226]), for example
  `In combat: 20s` (`PROPOSED` string, house style).
- **Bounty list** as a container menu `<Name> (Page N)` with one player head
  per row and a tooltip `<Player>` / `$ <total>` / `Click to view` —
  `PROPOSED`, following the orders-board grammar.

![SS-16: Combat tag display](../../screenshots/SS-16-combat-tag.png)
![SS-17: Bounty list](../../screenshots/SS-17-bounty.png)

## 4. Behaviour

### 4.1 PvP policy

PvP is enabled everywhere except the protected spawn area (`f15`,
`PROPOSED`), consistent with the semi-anarchy design [S1]. Crystal PvP is the
dominant style on the reference server [S1]; Mineclonia ships end crystals
and respawn anchors [M1], so nothing beyond damage attribution (§4.2) is
needed to enable it.

### 4.2 Combat tag

1. **Trigger.** Damage between two players tags **both**: melee through
   `core.register_on_punchplayer`; arrows through the arrow entity's
   `_shooter` field [M1]; explosions from end crystals, respawn anchors and
   TNT are attributed, best-effort, to the player who placed, ignited or
   struck the source within the previous 10 s (`PROPOSED`).
2. **Duration.** `combat.tag_seconds`, `PROPOSED` 20 s, refreshed by every
   hit.
3. **Display.** An action-bar countdown via `mcl_title.set`, or a HUD text
   element, as in clones [C1] (`PROPOSED`; §3).
4. **Blocked while tagged** (the `combat.blocked_commands` list):
   `/rtp`, `/rtpqueue`, `/tpa`, `/tpahere`, `/tpaccept`, `/homes`, `/spawn`,
   `/warp`, `/world` and `/shop` [S7], and the Shard Pickaxe [S19]. Allowed:
   `/sell` — explicitly enabled for combat in June 2026 [S3] — plus `/msg`
   and browsing `/ah` (`PROPOSED`). Enforced with
   `core.register_on_chatcommand`, returning true to cancel.
5. **Elytra.** `combat.disable_elytra` is `PROPOSED` false. Mineclonia
   implements gliding in `playerphysics/elytra.lua` without a public toggle
   [M1]; enabling this needs a hook into that module.
6. **Pearl distance cap** while tagged: optional, off by default, as in
   clones [C1].
7. **Untag** on the death of the player or of the opponent [C1].
8. `/kill` (`f11`) while tagged MUST credit the death to the last attacker
   (`PROPOSED`), so suicide cannot deny a kill or a bounty.

### 4.3 Combat log

When a tagged player disconnects:

1. Every list registered with `mcl_death_drop` (`main`, `craft`, `armor`,
   `offhand` [M1]) is dropped at the logout position.
2. The kill is credited to the last attacker, for statistics (`f14`) and
   bounties (§4.4).
3. The event is broadcast to chat (`PROPOSED`).
4. Player meta `smp:combat_logged = 1` is set; on next join the player
   respawns at spawn (`mcl_spawn.get_world_spawn_pos` [M1]) and the flag
   clears.

This follows clone behaviour [C1]; the reference server does not document it.

### 4.4 Bounties

`/bounty` views and `/bounty add` places [S24]; clone plugins let anyone add
money to a player's bounty and pay the total to whoever kills that player
[C6].

1. `/bounty` lists bounties by total, largest first; `/bounty <player>`
   shows one.
2. `/bounty add <player> <amount>` **escrows** the amount (`shared §2.6`
   R2). Contributions stack. Minimum `bounty.min_amount` (`PROPOSED` $1,000).
   Bounties on oneself are refused.
3. **Claim.** When the target is killed by another player — including kills
   credited through combat logging — the killer receives the whole bounty
   from escrow and a broadcast announces it (`PROPOSED` broadcast text).
4. **Anti-abuse** (`PROPOSED`): no payout when killer and target share an IP
   address; a `bounty.pair_cooldown` (3,600 s) per killer–target pair; no
   payout for kills inside the spawn safe zone.
5. No cancellation or refund, except `/bountyadmin clear`, which refunds
   contributors pro rata from escrow (`PROPOSED`).

## 5. Data schema

### 5.1 Combat tag (in-memory only)

```lua
smp_combat.tags[name] = {
  expires = 1758500220,          -- refreshed per hit
  last_attacker = "Bob",
  last_attacker_at = 1758500205,
}
```

Tags MUST NOT survive a restart: a server crash is a combat log, and the
logout path cannot run. Treat a rejoining player whose tag would have been
live as a normal join (the flag is transient by design, `PROPOSED`).

### 5.2 Bounty (`smp_store` table)

```lua
{ target = "Dave", total = 500000000,
  contributors = { Alice = 300000000, Bob = 200000000 },
  created = 1758500000, updated = 1758503600 }
```

Escrow is money already debited from contributors; payouts come only from
escrow (R2). Ledger codes `bounty_escrow`, `bounty_payout` (R3).

## 6. Algorithms

```lua
core.register_on_punchplayer(function(victim, hitter)
  local attacker = smp_combat.resolve_attacker(hitter)   -- player, or an arrow's _shooter
  if attacker and attacker:is_player()
     and attacker:get_player_name() ~= victim:get_player_name()
     and smp_combat.pvp_allowed(victim, attacker) then
    smp_combat.tag(victim, attacker)
    smp_combat.tag(attacker, victim)
  end
end)

core.register_on_chatcommand(function(name, command)
  if smp_combat.is_tagged(name) and cfg.combat.blocked_commands[command] then
    core.chat_send_player(name, S("You cannot use /@1 during combat.", command))
    return true                                          -- cancels the command
  end
end)

core.register_on_leaveplayer(function(player)
  local name = player:get_player_name()
  if smp_combat.is_tagged(name) then
    smp_combat.drop_death_lists(player)                  -- same lists as mcl_death_drop
    smp_combat.credit_kill(smp_combat.last_attacker(name), name)
    player:get_meta():set_int("smp:combat_logged", 1)
  end
end)

core.register_on_dieplayer(function(victim, reason)
  local vname = victim:get_player_name()
  local killer = smp_combat.killer_from(reason) or smp_combat.last_attacker(vname)
  if not killer or killer == vname then return end
  local bounty = smp_bounty.get(vname)
  if bounty and bounty.total > 0 and not smp_bounty.is_abuse(killer, vname) then
    smp_economy.credit(killer, bounty.total, "bounty_payout", vname)
    smp_bounty.clear(vname)
    core.chat_send_all(S("@1 claimed the @2 bounty on @3.", killer,
      smp_core.format_money(bounty.total), vname))
  end
end)
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `combat.tag_seconds` | 20 | PROPOSED |
| `combat.blocked_commands` | `{rtp, rtpqueue, tpa, tpahere, tpaccept, homes, spawn, warp, world, shop}` | LIVE [S7][S27] and PROPOSED |
| `combat.disable_elytra` | false | PROPOSED |
| `combat.keep_pearls_on_death` | false | PROPOSED — `pending:f08 §4.6` (no production reader; only consumer is spec-deferred ender pearls) |
| `combat.log_broadcast` | true | PROPOSED |
| `bounty.min_amount` | $1,000 | PROPOSED |
| `bounty.pair_cooldown` | 3,600 s | PROPOSED |
| `combat.explosion_window` | 10 s | PROPOSED |
| `combat.explosion_radius` | 12 nodes | PROPOSED |

## 8. Mineclonia implementation

- `resolve_attacker` handles three cases: a player ObjectRef (melee), an
  entity with `_shooter` (arrows [M1]), and nil (environment). Explosion
  attribution is a 10 s ring buffer of (pos, placer) for crystals, anchors
  and TNT.
- The tag countdown reuses the `mcl_title.set` action-bar channel; a HUD
  element is the alternative if title flicker proves distracting
  (`player:hud_add`).
- `drop_death_lists` MUST iterate `mcl_death_drop.registered_dropped_lists`
  rather than hard-coding list names, so Mineclonia changes propagate [M1].
- `mcl_keepInventory` interaction: if the world sets it true, combat-log
  drops still happen — the logout path drops explicitly and does not rely on
  the death path.
- Elytra disabling, when configured on, hooks `playerphysics/elytra.lua`;
  flag the hook as fragile against Mineclonia updates.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | A melee hit tags both parties for `combat.tag_seconds`; a second hit refreshes the timer |
| T2 | An arrow tags shooter and victim; `_shooter` attribution is used |
| T3 | Every blocked command is refused while tagged with a message naming the command; `/sell` and `/msg` still work |
| T4 | Disconnecting while tagged drops `main`, `craft`, `armor` and `offhand` at the logout position |
| T5 | The combat-log kill is credited to the last attacker in statistics and pays an outstanding bounty |
| T6 | The combat-logged player respawns at world spawn on next join; the flag then clears |
| T7 | `/kill` while tagged credits the last attacker and pays the bounty |
| T8 | `/bounty add` debits and escrows; two contributions stack into one total |
| T9 | No payout when killer and target share an IP, inside the safe zone, or within the pair cooldown |
| T10 | `/bountyadmin clear` refunds every contributor in full and removes the bounty |
| T11 | Tag state does not survive a server restart |
| T12 | Untagging occurs on the death of either party |

## 10. Open questions

| Id | Question |
|---|---|
| V-12 | Combat tag duration, full blocked-command list and any elytra rule — all unverified |
| V-19 | Bounty minimum, stacking, refunds and anti-abuse rules — all unverified |
| V-68 | Is the tag displayed, and where (action bar, sidebar, title)? |
| V-69 | Does the reference server broadcast combat logs? |
| V-70 | Are end-crystal and respawn-anchor kills attributed for bounties, or only direct hits? |
| V-71 | Does `/bounty` have a menu, or is it chat-only? |
| V-72 | Should `/sethome`, `/delhome`, `/back`, `/tpacancel` and `/tpadeny` also be blocked? They are not escape paths in the current list; `/tpacancel` is arguably one |
| V-73 | Should right-click-only TNT ignition (flint and steel, fire, redstone) and respawn-anchor charging be attributed? The ring currently records only node placement and punches (best effort, §4.2.1) |

### Fix-wave record (fix brief, 2026-09-25)

| Row | Outcome | Evidence (file:line) |
|-----|---------|----------------------|
| C1  | CLOSED  | `friedcake/mods/smp_combat/elytra.lua` (new); `friedcake/dev-tests/test_combat.lua:176-212` (C1 test cases); `friedcake/dev-tests/harness_f10.lua:452-456` (player `get_attach`/`set_attach`/`set_detach` stubs) |
| C2  | CLOSED  | `spec/features/f10-combat.md:191` (§7 row updated to `pending:f08 §4.6`); `spec/features/f10-combat.md:333-337` (note 16 documenting re-scope) |
| C3  | VERIFIED | `friedcake/mods/smp_combat/mod.conf:4` (`optional_depends = ..., smp_stats` kept); `friedcake/mods/smp_stats/combat.lua:11-14` (load-order comment); `friedcake/mods/smp_combat/*.lua` + `smp_bounty/*.lua` (no `core.register_on_globalstep` / `core.modpath` / `get_player_names` B1-era refs found) |
| C4  | VERIFIED | `friedcake/mods/smp_bounty/init.lua:144` (string `Player @1 does not exist` — no terminal full stop); `friedcake/dev-tests/test_bounty.lua:122` (assertion `"Player ghost does not exist"` — matches) |

### 10.1 Implementation notes — agent f10 (September 2026)

**Consumer contract (f05, f06, f08 already stub these with `TODO(f10)`):**

| Signature | Semantics |
|---|---|
| `smp_combat.is_tagged(who) -> boolean` | Accepts a player name **or** an ObjectRef — f05's bridge forwards the player object, f06 and f08 forward names. Always returns a strict boolean. Lazily drops expired tags. |
| `smp_combat.tag(victim, attacker)` / `smp_combat.untag(who)` | Names or ObjectRefs. `tag` refreshes `expires = os.time() + combat.tag_seconds` and re-records `last_attacker`/`last_attacker_at` on every hit; also shows the countdown immediately. |
| `smp_combat.last_attacker(who) -> string \| nil` | `nil` when untagged or expired. |
| `smp_combat.resolve_attacker(obj) -> string \| nil` | The §8 three cases: player ObjectRef, entity with `_shooter`, `nil`. |
| `smp_combat.pvp_allowed(victim, attacker) -> boolean`, `smp_combat.in_safe_zone(pos) -> boolean` | Safe-zone policy (X10). |
| `smp_combat.killer_from(reason) -> string \| nil` | Reads `reason._mcl_reason.source` (Mineclonia death path), `reason.source`, and `reason.type == "punch"` → `reason.object`; string/unknown reasons give `nil`. |
| `smp_combat.credit_kill(killer, victim, pos) -> boolean` | Statistics credit (`smp_stats.add(killer, "kills", 1)`, `TODO(f14)`) then the kill listeners. f11 may call it directly for `/kill`. |
| `smp_combat.register_on_kill(fn(killer, victim, pos))` | Listener registry; `smp_bounty.try_claim` registers here so `smp_bounty → smp_combat` stays a one-way dependency. |
| `smp_bounty.get(target)`, `smp_bounty.is_abuse(killer, victim, pos?)`, `smp_bounty.try_claim(...)`, `smp_bounty.clear(target)` | The §6 pseudo-code surface; `clear` removes without refund (post-payout), `/bountyadmin clear` refunds via `escrow_refund`. |

**PROPOSED decisions taken while implementing (V-12, V-19, V-68…V-71):**

1. Tag duration 20 s, refreshed per hit; `expires` and `last_attacker` use
   `os.time()` (§5.1 shape, in-memory only — T11 proven by reloading the
   mod and asserting no storage key contains `combat`/`tag`).
2. The blocked list is exactly the §4.2.4 ten plus the alias closure
   `tp` (alias of `/tpa`, f08 §2) and `home` (alias of `/homes`,
   f09 §2) — 12 entries, `PROPOSED`. `combat.blocked_commands` as a
   comma-separated setting replaces the whole set. `/sell` is absent
   (allowed in combat, June 2026 [S3]); `/msg`, `/ah` and `/bounty` are
   allowed. V-72 stays open for the borderline non-escape commands.
3. A punch tags both parties regardless of the computed damage value —
   this mirrors the §6 algorithm literally (no `damage > 0` threshold).
4. Arrow attribution goes through `register_on_player_hpchange` with
   `reason._mcl_reason.source`, which Mineclonia fills from the arrow's
   `_shooter` (verified in `mcl_bows/arrow.lua` + `mcl_damage`); melee
   is caught by both `register_on_punchplayer` and the same hpchange
   path (idempotent). Verified: arrow hits do **not** pass through
   `register_on_punchplayer`, so the hpchange hook is required, not
   redundant.
5. Explosion ring: 10 s window (`combat.explosion_window`), 12 nodes
   (`combat.explosion_radius`), FIFO capped at 64 entries, keyed by
   time + Euclidean distance, victim excluded. Recorded from
   `register_on_placenode`/`register_on_punchnode` on `mcl_tnt:tnt` and
   `mcl_beds:respawn_anchor[_charged_*]`. Punched end crystals need no
   ring — `mcl_end` passes `source = puncher` into
   `mcl_explosions.explode`; TNT passes the primed entity as `direct`;
   anchors pass nothing and key off the victim position. V-73 records
   the un-attributed ignition cases.
6. Countdown: `In combat: @1s` on the `mcl_title` action-bar channel
   (V-68 → action bar, the `Delivering...` channel [F0226]),
   refreshed at 1 Hz. **`stay` is in gameticks in this Mineclonia**
   (`mcl_title.set` divides by 20), so the bar is set with
   `stay = 40` (= 2 s) — `stay = 1` from the briefing would hide in
   50 ms. Cleared explicitly on untag.
7. Combat logs broadcast `@1 has logged out during combat.` when
   `combat.log_broadcast` (default true) — V-69 decided yes, `PROPOSED`.
8. `/bounty` is chat-only for now (V-71): `--- Bounties ---` header,
   rows `N. <name> — $ <total>` sorted largest first; the §3 container
   menu remains `PROPOSED` and unimplemented (no frame evidence).
9. `bounty.min_amount` ($1,000) applies to **each** `/bounty add`, not
   only the first (V-19). Contributions stack into one record keyed by
   `target:lower()`; contributors keep exact names for refunds.
10. Anti-abuse (all `PROPOSED`): same-IP compares live IPs with a
    join-time cache (engine IPs are unknowable after logout — the cache
    covers the combat-log window; **unknown IPs fail open**, flagged
    here); the 3,600 s cooldown is per `killer|victim` pair, persisted
    with the bounty document and pruned on load; the safe-zone check
    prefers `smp_core.is_spawn_protected` when f15 lands and otherwise
    reimplements the f15 rule (overworld only, `world.spawn_protect_radius`
    = 128). A refused payout leaves escrow and bounty untouched.
11. Refunds and cap edges: R3 has no `bounty_refund` code, so refunds
    post `bounty_payout` with ref `bounty:<target>`; a balance-cap
    shortfall during payout or refund stays conserved in escrow
    (orphaned contributors, logged) — never minted, never lost (X3).
12. `/kill` credit (T7) needs no f11 code: the dieplayer hook credits
    `last_attacker` whenever the death reason carries no attacker, so
    suicide cannot deny a kill or a bounty. `TODO(f14)` — the stats key
    `kills` is an assumption pending `smp_stats`.
13. Bounty persistence: `smp_store` exposes no table API yet
    (its `STORAGE.md` lists bounties as "later"), so records live in
    `smp_bounty`'s own mod-storage namespace as JSON, written
    synchronously on every mutation (same pattern as `smp_orders`).
    Money and ledger always go through `smp_store.api`.
14. `combat.disable_elytra` is implemented (2026-09-25 fix brief C1):
    when true, elytra flight is refused while a player is combat-tagged
    (blocks the `attach` method of `mcl_armor:elytra_entity` and
    force-detaches already-flying tagged players on globalstep). Default
    `false` changes no behaviour out of the box.
15. `smp:combat_logged` respawn keeps the flag if
    `mcl_spawn.get_world_spawn_pos` fails, so the respawn retries on the
    next join instead of silently dropping the punishment.
16. `combat.keep_pearls_on_death` re-scoped to `pending:f08 §4.6` (2026-09-25
    fix brief C2): the key has no production reader in the codebase
    (grep finds it only in test files). Its only documented consumer is
    f08's ender pearl retention, which is spec-deferred. Rather than leave
    a lying config key, the §7 row is updated to reflect the pending
    status. If f08 lands the pearl feature, a death-drop seam in
    `smp_combat` or `mcl_death_drop` would be needed to honour it.
17. Verified against `~/dev/mineclonia-git` at implementation time:
    `mcl_death_drop.registered_dropped_lists` entries are
    `{inv, listname, drop}` with `inv = "PLAYER" | function` (iterated,
    never hard-coded); `mcl_title.set` mutates a HUD text and hides it
    after `stay/20` seconds; `register_on_dieplayer` receives the
    `PlayerHPChangeReason` table `set_hp` was called with (Mineclonia
    attaches `_mcl_reason`); `_shooter` is the only arrow attribution.

## Proposed shared changes

*(Proposals for the integrator — implementation proceeded without them;
none of these block f10 or the f05/f06/f08 bridges.)*

1. **`smp_store` crash on load — one-line fix, integrator-owned.**
   `friedcake/mods/smp_store/init.lua:351` calls
   `core.register_on_globalstep(...)`. That function does not exist in
   Luanti (`lua_api.md` documents only `core.register_globalstep`) and
   exists nowhere in Mineclonia either — verified by grep of
   `~/dev/luanti` and `~/dev/mineclonia-git`. On a real server
   `smp_store` raises `attempt to call field 'register_on_globalstep'
   (a nil value)` at load and the whole server fails to start. The
   dev-test harnesses mask this by stubbing the misspelled name
   (`test_economy.lua`, `harness_f10.lua`). Change line 351 to
   `core.register_globalstep`. The same misspelling exists in the
   uncommitted `smp_orders` WIP (`init.lua:709`) — f04 should fix it
   there. **f10 did not edit smp_store (hard rule 4).**
2. **Generic `/smp test` dispatch.**
   `smp_economy`'s `/smp test` only knows the `smp_core` target, so
   `smp_combat/test.lua` and `smp_bounty/test.lua` cannot be reached
   in-game yet (CONTRIBUTING asks for registration under
   `/smp test <feature>`). Suggested dispatch: for
   `target ~= ""`, `loadfile(core.get_modpath(target) .. "/test.lua")`
   and run it if present, falling back to the current `smp_core`
   behaviour. Until merged, the two `test.lua` files run standalone
   (they are exercised by `harness_f10.lua` in CI) and the authoritative
   gate is `luajit friedcake/dev-tests/test_combat.lua` +
   `test_bounty.lua`.
3. **Optional R3 addition: `bounty_refund`.** Shared §2.6 R3 pins the
   ledger codes; there is no refund code for bounties, so
   `/bountyadmin clear` posts `bounty_payout` (distinguishable only by
   its `ref`). If the integrator wants `/ledger` to filter refunds
   cleanly, add `bounty_refund` to R3 and the mirror tables
   (`05`/`06` are integrator-owned); `escrow_refund` would switch one
   string.
