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
| `combat.keep_pearls_on_death` | false (per-player setting, `f12`) | LIVE [S20] |
| `combat.log_broadcast` | true | PROPOSED |
| `bounty.min_amount` | $1,000 | PROPOSED |
| `bounty.pair_cooldown` | 3,600 s | PROPOSED |

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
