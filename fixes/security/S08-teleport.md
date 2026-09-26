# S08 — Teleport: `/tpahere` traps, request-state growth

**Target mods:** `smp_tp`, `smp_rtpqueue` · **Branch:** `agent/sec-s08-tp`
**Audited at:** `85e4a5d`

## Mission

Teleports are consent-based, so their main abuse is luring players into
death traps. Also bound the per-name request state.

## Findings

| ID | Sev | Status | Where | One line |
|---|---|---|---|---|
| TP-1 | Medium | CONFIRMED | `requests.lua:195`, `warmup.lua` | `/tpahere` fixes the destination at accept time, and the sender can build a lethal trap during the warm-up. `/tpauto` accepts it with no prompt |
| TP-2 | Low | CONFIRMED | `requests.lua:86-106` | `core.player_exists` is true for offline accounts, so `/tpa` spam allocates state for any name in the auth DB |

### TP-1 — `/tpahere` death trap

`accept_request` reads `p_from:get_pos()` at accept time
(`requests.lua:195`), and `teleport_with_warmup` moves the target there
`tp.warmup` seconds (5) later. The target's own movement cancels the
teleport. The sender's does not. The sender can:
1. Stand over the trap, get the request accepted, then place lava or dig a
   void shaft in the 5 s warm-up.
2. Target a player running `/tpauto`. `send_request` accepts
   immediately when `tstate.auto_accept` is set, for **both** `tpa` and
   `tpahere`.

**Fix.**
- `/tpauto` should auto-accept only `tpa` (the requester comes to you).
  `tpahere` always prompts.
- At fire time, check the destination: the feet and head nodes are not
  damaging (`damage_per_second > 0`, `lava`/`fire` groups) or solid, and
  there is walkable ground within a few nodes below. Otherwise cancel with
  "The destination is not safe".

**Tests.** Auto-accept on and a `tpahere` request: a prompt is shown, with
no teleport. A lava node at the destination when the warm-up ends: the
teleport is cancelled.

### TP-2 — Request state for offline names

`send_request` calls `smp_tp.get_state(target)` for any name that exists
in the auth database, online or not. Refuse offline targets with the
generic refusal (T7 already prescribes one string for every rule), and
reject when `core.get_player_by_name(target)` is nil.

## Verified OK

- The warm-up re-checks the combat tag, the player's presence and movement
  at fire time. Damage cancels. Leave and death cancel warm-ups and
  requests.
- Every teleport command checks `is_tagged` in the command and again inside
  `teleport_with_warmup`.
- `smp_rtpqueue` refuses tagged players and removes a queued fighter on
  their first hit.
- The homes formspecs escape every user string (`homes.lua`, 33 `fesc`
  call sites).
