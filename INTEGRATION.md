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

## Known gaps (not yet fixed)

### 1. `smp_ah.cheapest_for` is missing (f05 ← f03 contract)

f05 (Quick Buy) bridges to `smp_ah.cheapest_for(key, ench, qty)`, but f03
only ships `smp_ah.listings_at_or_below(m1_key, unit_price)` (which f04's
order-routing sweep uses). `cheapest_for` aggregates the cheapest matching
listings until `qty` is met and returns `{listings, cost_cents}`.

Consequence: Quick Buy's purchase path currently returns "not enough
listings" always — the bridge falls through to `nil`. Everything else about
Quick Buy (entry CRUD, the 3× price guard, the re-confirm screen) is wired
and tested; only the final price lookup is missing its source.

**Recommended fix:** add `smp_ah.cheapest_for` as a thin adapter over
`listings_at_or_below` (filter by M1 key + enchant set, walk cheapest-first,
sum until qty). It belongs in `smp_ah`, not `smp_quickbuy`.

### 2. Two M1/M2 key implementations (smp_ah.keys vs smp_items)

f03 shipped its own `smp_ah/keys.lua` (because `smp_items` was a stub when
it started). f04 filled `smp_items` with the shared M0/M1/M2 keying, and f02
(`smp_sell`) + f04 (`smp_orders`) use `smp_items`. So there are two
implementations of the same §2.5 spec.

Both should produce identical keys (same spec), but they are two copies and
will drift. **Recommended fix:** make `smp_ah` consume `smp_items` and delete
`friedcake/mods/smp_ah/keys.lua`, so the canonical key code lives once.

### 3. Bridge stubs are deliberate graceful-degradation

Nearly every `TODO(fNN)` marker in the tree is a *delegating bridge* — e.g.
`if smp_combat and smp_combat.is_tagged then return smp_combat.is_tagged(p)
end`. These resolve automatically now that all mods are loaded; the `TODO`
labels are documentation, not missing work. The two exceptions worth a look
are the hardcoded fallbacks in `smp_orders/au_bridge.lua` (return `{}` /
`false`), which now delegate to the real `smp_ah` but log nothing on the
delegation path.

### 4. Non-issue noted: `smp_economy.credit/debit`

f14's spec §8 suggested hooking `smp_economy.credit`/`debit`, but those do
not exist — f01 routes every money mutation through
`smp_store.api.add_money/take_money/set_money`. f14 correctly hooks those
instead. Nothing to do; recorded so nobody "fixes" it back.

## Next steps

1. Implement `smp_ah.cheapest_for` (gap 1) — the only functional hole.
2. Consolidate key code onto `smp_items` (gap 2).
3. A full end-to-end load test: load all 22 mods together under a real
   engine (the dev-tests each load a subset, so cross-mod load-order edge
   cases are only partially covered).
4. Resolve the `TODO(fNN)` labels to plain comments now that the targets
   exist, so the tree reads as "wired" rather than "stubbed".
