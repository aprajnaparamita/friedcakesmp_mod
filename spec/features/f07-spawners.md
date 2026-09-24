# f07 — Virtual Spawners

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_spawners` |
| Phase | P2 |
| Depends on | `f02-sell` (Sell all routing), `mcl_experience`, `mcl_enchanting` |
| Frame evidence | **0 frames** |
| Confidence | **Research only.** Spawners never appear in the source video. The production model is an unvalidated proposal and the menu layout is a guess. |

Spawners are the reference server's main productive asset [S10], so this is the
largest body of unverified specification in the project. Treat every number
below as provisional until calibrated.

## 2. Commands

| Command | Arguments | Behaviour | Status |
|---|---|---|---|
| `/spawner` | `give <player> <type> [count]` | Issue spawner items (admin) | PROPOSED |

Spawners are otherwise interacted with as nodes, not commands.

## 3. Observed UI

**None.** Proposed layout, following the shared container-menu grammar:

```
Skeleton Spawner x128
  Stored 12,480 / 368,640          XP 3,210 / 256,000
  ┌──────────────────────────────────────────────┐
  │ [bone 64][bone 64][bone 64] …   5 × 9        │
  │ [< Prev] Page 1 of 5 [Next >] [Sell all][XP] │
  └──────────────────────────────────────────────┘
  Inventory
```

![SS-11: Spawner menu](../../screenshots/SS-11-spawner-gui.png)
![SS-12: Spawner stacking feedback](../../screenshots/SS-12-spawner-stack.png)

## 4. Behaviour

### 4.1 Overview

Donut spawners never spawn entities. They produce the mob's drops, taken by
right-clicking as with a chest [S10][S25]. Spawners of one type stack into a
single block [S24]. As of September 2026 no new spawners enter the game;
existing ones change hands only through trading [S10].

### 4.2 Types and outputs

| Type | Mob | Documented output | Default loot per virtual kill (`PROPOSED`) | XP (`PROPOSED`) |
|---|---|---|---|---:|
| Skeleton | `mobs_mc:skeleton` | Bones [S10][S24] | `mcl_mobitems:bone` 1.0 | 5 |
| Iron Golem | `mobs_mc:iron_golem` | Iron ingots [S10][S24] | `mcl_core:iron_ingot` 4.0 | 0 |
| Spider | `mobs_mc:spider` | String, spider eyes [S10][S25] | `mcl_mobitems:string` 1.0; `mcl_mobitems:spider_eye` 0.33 | 5 |
| Zombified Piglin | `mobs_mc:zombified_piglin` | Gold nuggets [S10][S24] | `mcl_core:gold_nugget` 0.5; `mcl_mobitems:rotten_flesh` 0.5 | 5 |
| Blaze | `mobs_mc:blaze` | Blaze rods [S10]. **Conflict:** another source says powder [S24] | `mcl_mobitems:blaze_rod` 0.5 (verify) | 10 |
| Zombie | `mobs_mc:zombie` | Rotten flesh [S10][S24] | `mcl_mobitems:rotten_flesh` 1.0 | 5 |
| Pig | `mobs_mc:pig` | Raw porkchop [S10][S25] | `mcl_mobitems:porkchop` 2.0 | 2 |
| Cow | `mobs_mc:cow` | Raw beef, no leather [S10][S24] | `mcl_mobitems:beef` 2.0 | 2 |
| Creeper (conditional) | `mobs_mc:creeper` | Gunpowder; one source only [S24] | `mcl_mobitems:gunpowder` 1.0 | 5 |

Output is deterministic: every item keeps a fractional accumulator, so expected
values are produced without random rolls.

### 4.3 Production model (`PROPOSED`, to be calibrated)

Donut documents diminishing returns: the more spawners in a stack, the less
each adds, and skeleton output levels off near 1,505.35 bones per minute
however many are stacked [S24]. The curve is not published. This specification
uses

```
kills_per_min(n) = C × (1 − (1 − r / C)^n)
```

with `n` the stack size, `r` a single spawner's rate and `C` the asymptote.
It gives `f(1) = r`, rises strictly, has decreasing marginal output and tends
to `C`.

Defaults: `r = 6` virtual kills per minute (roughly a vanilla spawner) and
`C = 1505.35` for skeletons. Illustrative skeleton output:

| Stack n | 1 | 10 | 64 | 100 | 500 | 1,000 |
|---|---:|---:|---:|---:|---:|---:|
| Bones/min | 6.0 | 58.9 | 339.5 | 495.7 | 1,301.0 | 1,477.6 |

`r` and `C` MUST be calibrated per type from screenshots or timed tests; for
skeletons the DonutStats calculator can be used [T1]. The Donut wiki itself
advises measuring collected output over a known period rather than trusting
estimates [S10].

### 4.4 Storage and XP

- Storage is virtual: an `item → count` table in node metadata, shown as
  45-slot pages.
- Capacity is `min(spawners.storage.hard_cap, spawners.storage.per_spawner × n)`
  with `per_spawner` `PROPOSED` 2,880 (45 × 64). Production pauses when full;
  Donut players are advised to watch capacity so output is not lost [S10].
- XP accumulates to `spawners.xp.per_spawner_cap × n` (`PROPOSED` 2,000 each)
  and is granted with `mcl_experience.add_xp` [M1].
- Maximum stack size is the signed 32-bit limit, 2,147,483,647 [S24].

### 4.5 Accrual

State updates lazily: every interaction converts elapsed time since
`last_update` into output, then sets `last_update`. A node timer (`PROPOSED`
60 s) keeps output flowing while the block is loaded. Whether Donut players
must stay near their spawners is undocumented [S10], so the policy is
configurable:

| `spawners.accrual_mode` | Behaviour |
|---|---|
| `active_only` (default) | Accrue only while the map block is active. On reactivation the callback may report elapsed time covering the inactive period, so each tick is clamped to twice the timer interval |
| `always` | Accrue wall-clock time, limited only by capacity |
| `capped` | Accrue wall-clock time up to `spawners.offline_cap_hours` |

Conformance (F07-7): *every* interaction converts elapsed time before it
reads or writes storage — menu open, take, `Take all`, Collect XP, Sell all,
stacking, digging and hopper extraction all call `accrue(pos)` first, and the
state object that gets written is read after it. The 60 s node timer is only
the background driver, so no interaction can show or pay less than the
elapsed time it covers.

### 4.6 Interaction

1. **Placement.** `smp_spawners:spawner_item` (item meta `type`) creates
   `smp_spawners:spawner` with that type, stack 1, empty storage,
   `last_update` now. A separate node from `mcl_mobspawners:spawner`, so no
   mob-spawning code runs.
2. **Stacking.** Sneak and right-click with a spawner item of the same type
   adds the whole held stack [S24] (`spawners.stack_mode = "all"`, the
   default); `spawners.stack_mode = "one"` adds a single spawner per click
   and any other value warns at load and behaves as `all` (F07-10). Other
   types are rejected. Requires protection access.
3. **Menu.** Header `<Type> Spawner x<n>`, a storage page, Sell all, Collect XP,
   paging, and lines for rate per minute, stored versus capacity, and stored
   XP. Clicking an item takes one stack; taking as much as fits is the
   `Take all` button — Luanti formspecs expose no shift-click state, so the
   clone's shift-click is an **accepted substitution** recorded in V-01
   (F07-12, documentation only; not re-litigated here).
4. **Sell all.** Sells stored output through `f02` routing, so higher-paying
   orders are served first [S2].
5. **Breaking.** Requires Silk Touch
   (`mcl_enchanting.has_enchantment(tool, "silk_touch")`) [C3][M1]. A normal
   dig removes one spawner; a sneaking dig removes up to 64 [C3]. Items go to
   the digger's inventory, overflow dropped. At zero the node is removed and
   remaining storage is lost, as in the clone [C3]; partial removals keep
   storage. Digging without Silk Touch is refused (`PROPOSED`).
6. **Access.** Any player may open, take from and sell a spawner, in keeping
   with semi-anarchy (`PROPOSED`); digging and stacking honour
   `core.is_protected`. `spawners.open_requires_access` defaults false.
7. **Explosions and pistons.** Spawners ignore blasts (`on_blast` does nothing)
   and cannot be pushed (`PROPOSED`, configurable).
8. **Hoppers.** Optional extraction, as in clones [C3]; off by default.
9. **Natural spawners.** One guide describes obtaining spawners naturally
   [S24], but current supply is closed [S10]. Dungeon spawners stay vanilla by
   default; conversion on Silk Touch dig is optional
   (`spawners.convert_natural`) [C3].
10. **Not adopted.** The clone "isolation bonus" [C3].

### 4.7 Acquisition and supply

| Source | Status |
|---|---|
| No new supply; trading and raiding only | LIVE [S10] |
| Shard shop at 1,500 shards (Feb 2026 price) | LEGACY [S8] |
| Gold crate: any one spawner | LEGACY [S11] |
| Administrative issue (`/spawner give`) | PROPOSED |

### 4.8 Performance and security

No entities, at most one node timer per spawner, O(1) accrual, menus rendering
only the visible page. Every menu action MUST re-validate that the node still
exists, has the same type and a positive stack, and that the player is within
8 nodes. A metadata version counter stops two viewers collecting the same
output twice.

## 5. Data schema

| Key | Type | Meaning |
|---|---|---|
| `smp:type` | string | Spawner type id, e.g. `skeleton` |
| `smp:stack` | integer | Spawners in the stack |
| `smp:last_update` | float | Unix time of the last accrual |
| `smp:store` | string | Serialized table of item name → fractional count |
| `smp:xp` | float | Stored XP |
| `smp:version` | integer | Incremented on every change |
| `infotext` | string | e.g. `Skeleton Spawner x128` |

## 6. Algorithms

```lua
function smp_spawners.accrue(pos)
  local meta  = core.get_meta(pos)
  local n     = meta:get_int("smp:stack")
  local last  = meta:get_float("smp:last_update")
  local now   = os.time()
  local mins  = (now - last) / 60
  if mins <= 0 or n <= 0 then return end

  local def   = cfg.spawners.types[meta:get_string("smp:type")]
  local kills = cfg.spawners.C[def.id] *
                (1 - (1 - cfg.spawners.r / cfg.spawners.C[def.id]) ^ n) * mins

  local store = core.deserialize(meta:get_string("smp:store")) or {}
  local cap   = math.min(cfg.spawners.storage.hard_cap,
                         cfg.spawners.storage.per_spawner * n)
  local total = sum(store)
  for item, per_kill in pairs(def.loot) do
    local add = math.min(kills * per_kill, cap - total)     -- pause when full
    store[item] = (store[item] or 0) + math.max(add, 0)
    total = total + math.max(add, 0)
  end
  meta:set_string("smp:store", core.serialize(store))
  meta:set_float("smp:xp", math.min(meta:get_float("smp:xp") + kills * def.xp,
                                    cfg.spawners.xp.per_spawner_cap * n))
  meta:set_float("smp:last_update", now)
  meta:set_int("smp:version", meta:get_int("smp:version") + 1)
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `spawners.r` | 6 kills/min | PROPOSED |
| `spawners.C.skeleton` | 1505.35 | LIVE [S24] |
| `spawners.timer_interval` | 60 s | PROPOSED |
| `spawners.accrual_mode` | `active_only` | PROPOSED |
| `spawners.offline_cap_hours` | 24 | PROPOSED |
| `spawners.stack_mode` | `all` | LIVE [S24] |
| `spawners.storage.per_spawner` | 2,880 | PROPOSED |
| `spawners.storage.hard_cap` | 2,147,483,647 | PROPOSED |
| `spawners.xp.per_spawner_cap` | 2,000 | PROPOSED |
| `spawners.require_silk_touch` | true | CLONE [C3] |
| `spawners.sneak_break_max` | 64 | CLONE [C3] |
| `spawners.open_requires_access` | false | PROPOSED |
| `spawners.blast_immune` | true | PROPOSED |
| `spawners.convert_natural` | false | PROPOSED |
| `spawners.hopper_extraction` | false | PROPOSED |
| `spawners.enable_creeper` | true | PROPOSED |
| `spawners.acquisition` | `{shard_shop = false, crates = false, natural = false, admin = true}` | LIVE [S10] |

## 8. Mineclonia implementation

- A node with metadata and a node timer. **Never** an entity, and **never** an
  ABM (goal G1).
- Menu: container menu over virtual counts rendered as read-only slots. There
  is no real inventory; clicks are handled as take requests against the count
  table.
- Silk Touch: `mcl_enchanting.has_enchantment(tool, "silk_touch")` [M1].
- XP: `mcl_experience.add_xp(player, xp)` [M1].
- Re-validate node, type, stack and player distance on every received field.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | A stack of 1 produces `r` kills per minute within 1% over 10 simulated minutes |
| T2 | Output is monotonic in stack size and marginal output decreases |
| T3 | A stack of 1,000 skeletons approaches but never exceeds `C` |
| T4 | Zero entities are created at any stack size |
| T5 | Production pauses at capacity and resumes after collection; nothing is lost silently |
| T6 | Two players collecting simultaneously cannot double-collect (version counter) |
| T7 | Digging without Silk Touch is refused |
| T8 | A sneaking dig removes up to 64 and keeps the storage; the last spawner removes the node |
| T9 | Sell all routes into better-paying orders before the server |
| T10 | An action on a node dug since the menu opened fails safely |

## 10. Open questions

| Id | Question | Decision (f07 implementer, branch `agent/f07-spawners`) |
|---|---|---|
| V-01 | Spawner menu layout, pages and buttons | PROPOSED layout implemented per §3: header `<Type> Spawner x<n>`, `Stored / capacity` + `XP` line, rate line, 5×9 page of item-image slots, footer `< Prev`, `Page n of m`, `Next >`, `Sell all`, `Collect XP`, `Take all`, `Close`. No shift state in Luanti formspecs, so the clone's "shift-click takes as much as fits" is substituted by a `Take all` button; a plain click takes one stack (up to 64 whole items). |
| V-02 | Production rate per type and stack size; whether owners must be nearby | r = 6 and all non-skeleton C are implemented as PROPOSED uncalibrated defaults (C = 250 for every non-skeleton type). `spawners.C.<type>` setting overrides exist for calibration without code changes. Accrual proximity policy is the `spawners.accrual_mode` setting, default `active_only`. |
| V-03 | Blaze output: rods or powder? Sources conflict | **Rods.** [S10] (more recent than [S24]) is taken to win the conflict; implemented as `mcl_mobitems:blaze_rod` 0.5 per virtual kill, still marked PROPOSED (verify). |
| V-04 | Do creeper spawners exist? | §4.2 marks the type "conditional". Implemented as a real type (gunpowder 1.0, PROPOSED) gated on `spawners.enable_creeper` (default true), because the single source documenting it [S24] is recent. If the integrator rules it out, set the key to false; no other code path references the creeper. |
| V-05 | Storage capacity and behaviour when full | Implemented per §4.4: `min(hard_cap, per_spawner × n)`. At full, production pauses, the overflow is discarded, `smp:last_update` still advances (no hidden banking), and the menu shows `Storage full`, so the pause is visible rather than silent (T5). |
| V-62 | Is the diminishing-returns curve exponential as modelled, or another shape? Only the asymptote is published | Implemented as the §4.3 exponential. The curve function is isolated (`smp_spawners.curve`) so an alternative shape can be substituted in one place once a second data point is published. |
| V-63 | (new) Sell-all message when f02 is absent | The f02 branch is not on `main`; `smp_sell` is an `optional_depends` and Sell all reports `Selling is not available yet` and takes nothing out of storage until `smp_sell.sell(player, stacks)` (f02 §6) exists. Marked `TODO(f02)` in `routing.lua`. |

## 10.1 Fix-wave record (fix brief, 2026-09-25)

| Row ID | Outcome | Evidence (file:line) |
|---|---|---|
| F07-1 | VERIFIED | `routing.lua:70-78` — `smp_sell.sell` called first; storage decremented + `write_state` only on `true` return; comment fixed |
| F07-2 | VERIFIED | `init.lua:54-56` — `bool()` uses `core.settings:get_bool(key, default)` so stored `false` wins; all four default-true keys + `open_requires_access` behave correctly for unset/true/false |
| F07-3 | VERIFIED | `formspecs.lua:178-184` — `Inventory` label + `list[current_player;main;...]` player inventory rows present; virtual storage grid stays `item_image_button[]` take-requests |
| F07-4 | VERIFIED | `node.lua:162-163` — `groups = { ..., unmovable_by_piston = 1, container = 7 }`; Mineclonia aborts push when `core.get_item_group(name, "unmovable_by_piston") == 1` |
| F07-5 | VERIFIED | `node.lua:194-195` `_on_hopper_out` hook registered; `performance.lua:63-95` `hopper_extract` gated on `cfg.hopper_extraction` (default `false`), accrues first, pulls one item, respects hopper room |
| F07-6 | VERIFIED | `node.lua:200-254` — `convert_natural` overrides vanilla `mcl_mobspawners:spawner` `on_dig`; converts on Silk Touch dig when enabled, reads `Mob` key, respects `enable_creeper` gate and protection |
| F07-7 | VERIFIED | `interaction.lua:162` `revalidate` calls `accrue`; all menu actions (take, Collect XP, Sell all), stacking, dig, hopper pull route through `revalidate` or call `accrue` directly — elapsed time always converted before read/mutate |
| F07-8 | VERIFIED | `init.lua:175-197` `apply_C_overrides` reads documented `spawners.C.<type>` dotted keys (win) and compound `spawners.C` back-compat fallback |
| F07-9 | VERIFIED | `init.lua:92-122` `build_cfg` reads documented `spawners.acquisition` table key first; flat `spawners.acquisition.<src>` keys remain as back-compat fallback; defaults unchanged |
| F07-10 | VERIFIED | `interaction.lua:107-109` honors `stack_mode = "one"` (adds 1) vs `"all"` (adds whole stack); `init.lua:83-90` warns on unknown values, degrades to `"all"` behaviour |
| F07-11 | VERIFIED | `node.lua:176-180` `on_blast` checks `cfg.blast_immune`: `true` → no-op (spec default); `false` → `stop_timer` + `remove_node` (normal blast behaviour) |
| F07-12 | N/A | Accepted substitution per V-01 (Luanti formspecs have no shift state); `Take all` button remains — no code change |
| F07-13 | VERIFIED | `test_spawners.lua:861-983` — T9 rewritten: stub returns `true`/`false` per f02 contract; both refusal paths (balance-cap, empty plan) assert storage/version byte-identical, stacks handed intact, fallback message; success path asserts storage decremented exactly by sold lots, version bumped, f02 receipt lines relayed |
| F07-14 | ESCALATED → D5 | Documentation only; spec §3/§4.6.3 wording splits (`Page 1/5` vs `Page n of m`, `×n` vs `x<n>`) — code renders `x` / `Page n of m` consistently (observed/V-01 forms); D5 ruled 2026-09-24: normalise spec to code, never reverse; `formspecs.lua:89` comment still says `×n` but line 90 renders `x@2` — left as-is pending D5 |

## Proposed shared changes

For the integrator (feature agents do not edit `spec/shared/`):

1. **`shared/06-config-reference.md`** — add the keys implemented beyond the
   existing mirror rows:

   | Key | Default | Status | Spec |
   |---|---|---|---|
   | `spawners.offline_cap_hours` | 24 | PROPOSED | f07 |
   | `spawners.enable_creeper` | true | PROPOSED | f07 |
   | `spawners.hopper_extraction` | false | PROPOSED | f07 |
   | `spawners.C.<type>` | per-type defaults in `smp_spawners/types.lua` (skeleton 1505.35 LIVE [S24]; others 250 PROPOSED) | PROPOSED | f07 |

2. **f02 (`smp_sell`)** — no shared change required; the routing-in
   contract already exists in f02 §6 as `smp_sell.sell(player, stacks)`.
   Flag only that `smp_spawners` is a caller (spawner Sell all), alongside
   the f04/f05 callers, for the f02 merge review.

3. **`shared/08-ui-strings.md`** — the spawner strings implemented are all
   PROPOSED (no frames): `Skeleton Spawner x@1` header family, `Stored @1
   / @2    XP @3 / @4`, `Rate: @1 kills/min`, `Storage full`, `Sell all`,
   `Collect XP`, `Take all`, `Page @1 of @2`, `< Prev`, `Next >`, `You
   took @1`, `You collected @1 XP`, `Silk Touch is required to dig a
   spawner`, `Different spawner types cannot be stacked`, `This spawner
   has been removed`, `This spawner has changed`, `Nothing stored to
   sell`, `Selling is not available yet`. Add to the catalogue on merge.
