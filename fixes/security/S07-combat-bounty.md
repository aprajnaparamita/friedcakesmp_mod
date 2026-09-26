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

---

## Status (2026-09-27)

Branch `agent/sec-s07-combat`, worktree at `85e4a5d` + the brief commit.
Commits: `fix(smp_combat,smp_bounty): S07 combat/bounty hardening (CB-1,
CB-2)` and `docs(f10): record the S07 fix-wave in §10`.

| ID | Outcome | Landed in |
|---|---|---|
| CB-1 | **FIXED** | `smp_combat/init.lua` (leave handler deferred into `core.register_on_mods_loaded`, load-order comment), `dev-tests/harness_f10.lua` (`register_on_mods_loaded` stub, `H.mods_loaded`, `H.fire_leave`), `dev-tests/test_combat.lua` (fake container mod + drop-order assertions), `smp_combat/test.lua` (live `registered_on_leaveplayers[#]`) |
| CB-2.1 direct-kill payouts | **FIXED** | `smp_combat/init.lua` (`source` = `"death"` / `"fallback"` on `credit_kill`), `combatlog.lua` (`"combatlog"` — still pays, per §4.4.3/T5), `smp_bounty/init.lua` + `abuse.lua` (refuse `fallback` before any money moves) |
| CB-2.2 friend + playtime | **FIXED** | `smp_bounty/abuse.lua` (mutual `smp_social.is_friend`; `MIN_KILLER_PLAYTIME = 3600` s of `rec.playtime`, missing record = 0 fail closed, stands down without `smp_stats`) |
| CB-2.3 `kill` blocked | **FIXED** | `smp_combat/config.lua` `DEFAULT_BLOCKED` (+ `blocks.lua` note) |
| CB-2.4 per-victim window | **FIXED** | `smp_bounty/abuse.lua` (`victim_key`), `escrow.lua` (legacy `killer\|victim` migration), `init.lua` (boot log) |
| CB-3 ignition attribution | **RECORDED** | f10 §10 PROPOSED entry (needs `mcl_tnt`/`mcl_beds` hooks + a damage-history ring — outside this brief's file set) |

**Rule choices recorded (f10 §10):** playtime floor 3,600 s as a local
constant (a new `bounty.*` key would need a `spec/shared/06` mirror row);
friend edge = mutual `is_friend` (one-way follows = open question V-100);
`source` ladder `"death"` / `"fallback"` / `"combatlog"` / `nil`, combat
logs still pay; claim window 3,600 s per **victim** under the unchanged
`bounty.pair_cooldown` key (rename to `bounty.victim_cooldown` escalated,
not done); check order `source → ip → friend → playtime → cooldown → zone`.

**Escalated to the integrator (f10 §10, files this brief does not let me
touch):** f10 §7 + §4.2.4 list no `kill` (shared mirror row `06:104`
points at that list); §9 T7 still says `/kill` pays the bounty; §9 T9 and
§4.4.4 still say "per pair"; §4.2.8 still says suicide cannot deny a
bounty.

**Verification.** `luajit friedcake/dev-tests/test_combat.lua` →
`ALL OK test_combat (T1-T7, T11, T12, X10, CB-1)`; `test_bounty.lua` →
`ALL OK test_bounty (T8-T10, CB-2.1/CB-2.2/CB-2.4, views, X3)`;
`test_engine_apis.lua` → `passed=16 failed=0`. Full suite: **24/27 pass**
— identical to baseline; the three failures are the pre-existing expected
ones (`test_config_mirror` D7 sell./amethyst. rows, `test_enderchest`,
`test_integration` modpack.conf path).

**Push:** `git push -u origin agent/sec-s07-combat` attempted — refused
with `Permission denied (publickey)` (no deploy key in this environment);
the branch exists locally only, two commits ahead of `main`.

**Brief inaccuracies found (no behaviour change):** CB-2 fix 3 says "add
`kill` **and its aliases**" — `/kill` has no aliases (`smp_social`'s
`register_cmd("kill", def)` takes no third argument, f11 §2 alias column
is empty), so a single entry suffices; CB-3's "`on_ignite`-style
callback" does not exist as an engine or Mineclonia API — ignition is
`mcl_item_use` on flint-and-steel/fire/redstone inside `mcl_tnt`, which
is why CB-3 stays a proposal.
