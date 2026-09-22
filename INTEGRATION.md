# Integration notes — first merge pass

Written by the integrator after merging all feature branches into `main`.
Everything below is the current state of the merged tree.

## What was merged

13 feature branches, in dependency order, each with `--no-ff`:

| Merge | Branches folded in | Mods |
|---|---|---|
| f13 ranks | agent/f13-ranks | smp_ranks |
| f03 auction | agent/f03-auction | smp_ah |
| f02 sell | agent/f02-sell | smp_sell |
| f04 orders | agent/f04-orders | smp_orders + **smp_items fill** |
| f05 quickbuy | agent/f05-quickbuy | smp_quickbuy |
| f07 spawners | agent/f07-spawners | smp_spawners |
| f06 shards | agent/f06-shards | smp_shards, smp_shardshop, smp_amethyst |
| f12 + f10 | agent/f12-settings | smp_settings, smp_combat, smp_bounty |
| f09 + f08 | agent/f09-homes | smp_tp, smp_rtpqueue (homes subsystem) |
| f14 + f11 | agent/f14-stats | smp_stats, smp_social |
| f15 world | agent/f15-world-rules | smp_world |

Three branches were folded into their successors rather than merged
separately, because they were already contained:
- **f10 ⊂ f12** (settings branched from combat; identical smp_combat/smp_bounty)
- **f08 ⊂ f09** (homes merged teleport as its base; identical smp_tp)
- **f11 ⊂ f14** (stats branched from social; identical smp_social)

`modpack.conf` was rewritten once per conflict as the union of `load_mod`
lines. Final load order (22 mods):

```
smp_core smp_store smp_items smp_economy smp_ranks smp_admin
smp_sell smp_ah smp_orders smp_quickbuy smp_spawners
smp_shards smp_shardshop smp_amethyst smp_combat smp_bounty
smp_tp smp_rtpqueue smp_settings smp_social smp_stats smp_world
```

## Test status

`tools/agent-flow.sh test` — **all 20 dev-test scripts green.**

One test needed a fix as part of integration (see the commit
`fix(f03 test): stub smp_ranks perk API during T10`): the f03 auction test
manipulated `smp_ah.cfg.slots.default` directly, but after f13 landed,
`smp_ah.slots()` consults the authoritative `smp_ranks.ah_limit()`. The test
now stubs both `smp_ranks.ah_limit` and `smp_ranks.limit` during the T10
section to exercise f03's own config fallback.

## Known gaps — status

### 1. `smp_ah.cheapest_for` — **FIXED** (commit e8f024b)

Implemented `smp_ah.cheapest_for(key, ench, qty, now)` as an adapter over the
M1 index (matches on the `m1|<name>|<ench>|` prefix, ignoring meta hash —
exactly f05 §4.2's "exact item including enchantments" width). Aggregates
whole listings cheapest-first until `qty` is met, returns
`{listings, cost_cents}` or nil. Covered by dev-test X-h.

### 2. Two M1/M2 key implementations — **RESOLVED, no code change needed**

On inspection, `smp_ah/keys.lua` already *delegates* `key` and `matches` to
`smp_items` at load time (`foreign()`), and the two key formats are identical
(`m0|name`, `m1|name|ench|meta_hash`, `m2|name|ench|wear|named|contents|meta_hash`).
Since `smp_items` loads before `smp_ah` in modpack order, f03 uses the shared
implementation. The only remaining copies are f03-internal helpers
(`equals`, `parts`, `display`, `parse`) that `smp_items` does not provide —
these are not cross-mod contracts. Stale comments updated; no drift risk.

### 3. Bridge stubs are deliberate graceful-degradation — **DOCUMENTED**

The `TODO(fNN)` labels in the delegating bridges were updated where the target
mod now ships (`smp_quickbuy/bridges.lua`); the pattern is otherwise correct
and self-resolving.

### 4. Non-issue: `smp_economy.credit/debit`

f14 correctly hooks `smp_store.api.add_money/take_money/set_money` (the real
mutators) rather than the spec's suggested `smp_economy.credit/debit`. Nothing
to do.

## Remaining follow-ups (not blockers)

1. A full end-to-end load test: load all 22 mods together under a real engine
   (the dev-tests each load a subset, so cross-mod load-order edge cases are
   only partially covered). See `MANUAL_TEST_GUIDE.md`.
2. The `smp_orders/au_bridge.lua` hardcoded fallbacks (`return {}` / `false`)
   now delegate to the real `smp_ah` but could log on the delegation path for
   observability.
