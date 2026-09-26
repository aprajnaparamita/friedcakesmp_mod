# S07 — Combat log ordering, bounty laundering

**Target mods:** `smp_combat`, `smp_bounty` · **Branch:** `agent/sec-s07-combat`
**Audited at:** `85e4a5d`

## Mission

Make the combat-log penalty impossible to dodge by parking items in
temporary containers. Make bounties hard to collect by collusion.

## Constraints (AGENTS.md)

Edit only `smp_combat` and `smp_bounty`. Friend-graph reads go through
`smp_social`'s public API. Tests: `dev-tests/test_combat*.lua`,
`test_bounty*.lua` and the in-mod `test.lua`.

## Findings

| ID | Sev | Status | Where | One line |
|---|---|---|---|---|
| CB-1 | High | CONFIRMED | `smp_combat/init.lua:135`, `combatlog.lua:156` | The combat-log drop runs **before** other mods return temporary containers, so items escape |
| CB-2 | Medium | CONFIRMED | `smp_combat/init.lua:108-116`, `smp_bounty/abuse.lua:66-77` | Any death while tagged (including `/kill`) credits the last attacker, and the only collusion check is same-IP |
| CB-3 | Low | CONFIRMED | `smp_combat/attribution.lua` (`nearest_placer`) | Explosion kills credit the nearest player who punched a TNT or anchor within 10 s and 12 nodes, so kill credit can be stolen |

---

### CB-1 — Register the combat-log drop last

On leave, callbacks run in registration order. `smp_sell` optionally
depends on `smp_combat`, so it loads later. `smp_orders` has no edge, so
alphabetical resolution puts it later too. Their leave handlers put the sell
grid and delivery grid contents back into `main` **after**
`smp_combat.on_leave` has already dropped `main`. See S02 SE-4 for the
repro.

**Fix.**
```lua
-- init.lua: replace the direct registration at :135
core.register_on_mods_loaded(function()
	core.register_on_leaveplayer(smp_combat.on_leave)
end)
```
Every mod's main chunk has run by `on_mods_loaded`, so this appends the
handler after every other leave handler. Registration there is plain table
insertion, with no load-time restriction. Leave a comment explaining why,
because this ordering is load-bearing.

Also defence in depth (S02, S03 and S04 own their sides): temporary
containers refuse `allow_put` while the player is tagged.

**Test.** Harness: register a fake mod's leave handler that adds a diamond
to `main` **after** smp_combat has loaded. Tag the player, fire the leave
callbacks in order, and assert that the diamond is dropped.

---

### CB-2 — Bounty laundering

`smp_combat.on_die` credits `last_attacker` whenever the victim was tagged
and the reason has no attributable source (`init.lua:109-111`). That covers
fall, lava, void and `/kill` (`smp_social/kill.lua`, which uses
`set_hp(0)` and is not blocked in combat). `smp_bounty.try_claim` refuses
only when the killer and victim share an IP, or the same pair claimed within
`pair_cooldown` (`abuse.lua:66-77`).

**Repro.** Players place a large bounty on X. X's friend Y, on a different
connection, punches X once, and X runs `/kill`. Y receives the whole
bounty, and X had emptied their inventory into a chest first. Repeat with
friend Z an hour later.

**Fix (record the rule choices in f10 §10):**
1. For **bounty** payouts, require a *direct* kill: `killer_from(reason)`
   must name the killer (punch or projectile). Do not use the
   `last_attacker` fallback. Statistics and kill counts can keep the
   fallback.
2. Refuse the claim if killer and victim are friends
   (`smp_social.is_friend`, if exposed; otherwise escalate to f11), or if
   the killer's playtime is below a threshold.
3. Add `kill` (and its aliases) to `DEFAULT_BLOCKED`
   (`smp_combat/config.lua:36`), so a tagged player cannot self-kill to
   hand over credit.
4. Make the cooldown per **victim** (one payout per victim per window),
   not per pair.

**Tests.** A tagged victim dies by `set_hp(0)`: no payout. A friend kill:
no payout. The second payout on the same victim within the window: refused.

### CB-3 — Explosion credit theft

`attribution.nearest_placer` credits the most recent player who **placed
or punched** a TNT or respawn anchor within 12 nodes in the last 10 s. A
bystander who punches a TNT near an explosion kill takes the credit, and
the bounty. Record only **ignition** events (the `on_ignite`-style
callback or a flint-and-steel use), and prefer the player who damaged the
victim within the window.

## Definition of done

- CB-1 fixed and tested.
- CB-2's direct-kill rule and the `/kill` block are in, with the remaining
  rules recorded in f10 §10.
- CB-3 recorded.
