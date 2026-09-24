# f13 — Ranks and Membership

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_ranks` |
| Phase | P0 — slot limits are consulted by `f03`, `f04`, `f08`, `f09` from the start |
| Depends on | `smp_store` |
| Frame evidence | **0 frames** |
| Confidence | **Research only.** No rank UI, rank chat prefix or `/ranks` screen appears in the video. Worse, the observed chat carries **no rank prefix on any line** [F0269, F0282, F0283], which contradicts v0.1's `[Rank] Name: message` assumption — see `f11` V-24. |

Payment integration is out of scope (`shared/01-overview.md §1.3`); tiers are
granted by administrators. This file specifies the tier model every other mod
consults.

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/ranks` | — | — | Show the perk table and configured store text | LIVE [S2] |
| `/rank` | — | `set <player> <tier> <days>`; `clear <player>` | Grant or clear tiers (admin) | PROPOSED |
| `/buy` | `/store` | — | Informational store link (display text only; owned with `f11`'s informational commands) | LIVE [S24] |

## 3. Observed UI

**None.** No frame shows a rank menu, a purchase prompt or a prefixed chat
name. The perk table below is documentation [S17], not observation.

Proposed `/ranks` screen, in the observed grammar, to be replaced by evidence:
a prompt menu titled `Ranks` listing one row per tier with its perks, plus a
`Back` button (`PROPOSED`).

![SS-24: /ranks menu](../../screenshots/SS-24-ranks.png)

## 4. Behaviour

### 4.1 Tiers

Tier ids are `default`, `tier1`, `tier2`, `tier3`, `media` (`shared §0.5` —
Donut names appear only when describing the reference server).

| Tier | Donut name | Homes (`f09`) | Auction slots (`f03`) | Order slots (`f04`) | Other perks |
|---|---|---:|---:|---:|---|
| `default` | none | 2 [S25] | 9 (`PROPOSED`) | 9 (`PROPOSED`) | none |
| `tier1` | Donut+ | 9 | 45 | 45 | Higher placement in the player list [S17]; shorter `/rtp` cooldown [S27] |
| `tier2` | Donut++ | 27 | 90 | 90 | none documented [S17] |
| `tier3` | Donut+++ | 90 | at least 90 (unstated) | at least 90 (unstated) | Priority chunk generation [S17] |
| `media` | Media | as tier3 | as tier3 | as tier3 | Equivalent to Donut+++ since 16 June 2026 [S17] |

### 4.2 Rules

1. **Duration.** A tier lasts 30 days per grant [S17]. The record is
   `{tier, expires_at}`; consecutive grants extend `expires_at` by 30 days
   each (`PROPOSED` stacking rule).
2. **Expiry check** runs on join and hourly.
3. **Grandfathering.** On expiry, existing homes, auction listings and orders
   remain usable; nothing new may be created beyond the default limits [S17]
   (`PROPOSED` for listings and orders).
4. **Perk API.** `smp_ranks` exposes one query per limit:
   `home_limit(name)`, `ah_limit(name)`, `order_limit(name)`,
   `rtp_cooldown(name)`, `tier(name)`. Consumers MUST call these rather than
   read the rank record directly, so the tier table lives in exactly one
   place.
5. **Player-list priority** [S17] is `N/A`: Luanti has no server-controlled
   player list to reorder. Substitute: tier-sorted `/list` output (`f11`)
   (`PROPOSED`).
6. **Priority chunk generation** [S17] is `N/A`: Luanti has no per-player
   emerge priority.
7. **Chat prefix.** v0.1 specified `[Rank] Name: message`. No observed chat
   line carries any rank prefix [F0269, F0282, F0283]. `smp_ranks` therefore
   MUST NOT add one by default; an optional `ranks.chat_prefix` config exists
   for servers that want it, default empty. The contradiction is tracked as
   V-24 (`f11`).
8. **Historical perks** (do not implement): Donut+ and Media once gave 5
   homes [S25] and let holders earn shards anywhere under the AFK system
   [S8][S17]. The AFK system is legacy (`f16`).
9. **`/ranks`** shows the perk table and the configured store text [S2].
   Luanti cannot open URLs; links appear in a read-only formspec field for
   copying (`f11` informational-command pattern).

## 5. Data schema

In the player record (`f01 §5.1`):

```lua
rank = { tier = "tier1", expires_at = 1761100000 }
```

Absent or expired `rank` means `default`. Offline grants are possible because
the record lives in `smp_store`, not player meta.

## 6. Algorithms

```lua
function smp_ranks.tier(name)
  local r = smp_store.player(name).rank
  if r and r.expires_at > os.time() then return r.tier end
  return "default"
end

function smp_ranks.limit(name, perk)            -- perk in {"homes","ah","orders"}
  local tiers = cfg[perk == "homes" and "homes.slots"
                   or perk == "ah" and "ah.slots" or "orders.slots"]
  return tiers[smp_ranks.tier(name)] or tiers.default
end

function smp_ranks.grant(name, tier, days)
  local rec = smp_store.player(name)
  local now = os.time()
  local base = (rec.rank and rec.rank.tier == tier and rec.rank.expires_at > now)
               and rec.rank.expires_at or now
  rec.rank = { tier = tier, expires_at = base + days * 86400 }
  smp_store.api.upsert_player(rec) -- single read-modify-write, no yields
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `ranks.grant_days` | 30 | LIVE [S17] |
| `ranks.chat_prefix` | `""` (no prefix) | **OBSERVED** by absence [F0269] — see V-24 |
| `ranks.expiry_check_interval` | 3,600 s | PROPOSED |
| `ranks.store_text` | configurable store URL and blurb | PROPOSED |
| Slot tables (`homes.slots_default`-family, `ah.slots.*`, `orders.slots.*`) | declared in `f09`, `f03`, `f04` | LIVE [S17] except defaults/tier3 |

## 8. Mineclonia implementation

- The expiry sweep is one `core.after` loop over **dirty candidates only**
  (players whose `expires_at` is in the past), not a full table scan; at
  hourly cadence either is within budget (`shared §2.7`).
- Expiry itself is lazy: `tier()` computes from `expires_at`, so no mutation
  is required when a tier lapses. The sweep exists only to emit the
  notification.
- `/rank` requires the `smp_admin` privilege.
- `/ranks` is a prompt menu (`shared/04-ui-kit.md §4.1`) rendering the tier
  table from configuration — never hard-code perk numbers into the formspec,
  or the screen and the enforcement will drift.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | Granting tier1 raises the home, auction and order limits through the perk API, and clearing reverts them |
| T2 | An expired tier reads as `default` from `tier()` without any record mutation |
| T3 | Two consecutive 30-day grants produce `expires_at = now + 60d` |
| T4 | After expiry, existing homes/listings/orders remain usable but creating beyond the default limit is refused (integration with `f09`, `f03`, `f04`) |
| T5 | Chat lines carry no prefix with the default configuration (integration with `f11`) |
| T6 | `/rank set` works on an offline player and applies on next join |
| T7 | `/ranks` renders every configured tier from the live config |
| T8 | tier1's `/rtp` cooldown is shorter than the default (integration with `f08`) |

## 10. Open questions

| Id | Question |
|---|---|
| V-24 | Owned by `f11`, cross-listed: no observed chat line has a rank prefix. Do ranked players carry one at all? |
| V-72 | What are tier3's exact auction and order slot counts? Documented only as "at least" the tier2 numbers [S17] |
| V-73 | What does `/ranks` look like — a menu, a chat dump, or a link? |
| V-74 | Do consecutive grants stack additively on the reference server? |
| V-75 | Does the Media tier exist as a purchasable grant, or is it assigned manually? (Out of scope for implementation; affects only `/ranks` display text) |
| V-76 | Does tier1's shorter `/rtp` cooldown extend to tier2/tier3/media? [S27] documents it only for tier1, but a perk that regresses at tier2 would be odd. Implemented literally: only `tier1` is short; every other tier falls back to `default` (`PROPOSED`) |

## Fix-wave record (fix brief, 2026-09-25)

| Row | Outcome | Evidence | Target |
|---|---|---|---|
| R-01 | ESCALATED | `spec/features/f13-ranks.md:229-232` (§11.3.2) → hand-off H1 | `fixes/f04-orders.md` |
| R-02 | ESCALATED | `spec/features/f13-ranks.md:225-228` (§11.3.1) → hand-off H2 | `fixes/f08-teleport.md` |
| R-03 | ESCALATED | `spec/features/f13-ranks.md:114` (§6 pseudocode); `fixes/01-integrator-decisions.md:67` (D6 ruled) | D6 (`upsert_player`) |

### Hand-off entries

**H1 (R-01 → f04)** `smp_orders.slot_limit` at `friedcake/mods/smp_orders/orders.lua:204-206` reads `rec.rank` directly and ignores `expires_at`. Consumer must call `smp_ranks.order_limit(name)` instead. Contract: `order_limit(who)` accepts name or PlayerRef, honours `expires_at` lazily (returns `default` limits for expired), reads live config, never mutates record. Contract test added: `test_ranks.lua` CONTRACT C1 seeds `{tier="tier1", expires_at=past}` → asserts `tier()=="default"`, `order_limit==9`, `home_limit==2`, raw `rec.rank.tier=="tier1"`, record unmutated. §11.3.2 annotated as handed off.

**H2 (R-02 → f08)** `smp_tp.cooldown_secs` at `friedcake/mods/smp_tp/rtp.lua:182` reads `cfg.rtp.cooldown[tier]` directly, yielding `nil` for tier2/tier3/media. Consumer must call `smp_ranks.rtp_cooldown(name)` instead. Contract: `rtp_cooldown(who)` accepts name or PlayerRef, honours `expires_at` via `tier()`, returns `cooldowns[tier] or cooldowns.default` (never nil; only `tier1` is short by default). Contract test added: `test_ranks.lua` CONTRACT C2 seeds live `tier2` and `media` records → asserts `rtp_cooldown==60` (default fallback), live `tier1` returns `30`. §11.3.1 annotated as handed off.

**H3 (R-03 → D6)** §6 pseudocode line 114 names `smp_store.mark_dirty("players", name)` which does not exist; the real pattern is `smp_store.api.upsert_player(rec)` at `grant.lua:38`. D6 ruled 2026-09-24: amend §6 to `upsert_player`, no `mark_dirty` API will be added. §6 left untouched until integrator applies the ruling.

## 11. Implementation notes (agent/f13-ranks)

### 11.1 Public API — exact signatures (f07, f08, f09, f03, f04 depend on these)

Every perk function accepts **either** a player name string **or** a
Player ObjectRef, normalised by `smp_ranks.name_of(who)`; anything
unusable reads as the safe default rather than erroring:

```lua
smp_ranks.tier(who)          -> "default" | "tier1" | "tier2" | "tier3" | "media"
smp_ranks.home_limit(who)    -> int
smp_ranks.ah_limit(who)      -> int
smp_ranks.order_limit(who)   -> int
smp_ranks.rtp_cooldown(who)  -> int (seconds)
smp_ranks.chat_prefix(who)   -> string ("" with the default config)
smp_ranks.limit(who, perk)   -> int   -- perk in {"homes","ah","orders"}, §6
```

`grant(name, tier, days)` / `clear(name)` (§6) also take either shape.
`days` defaults to `ranks.grant_days` (30). f11's bridge contract
(`chat_prefix(name)`, `tier(name)`) and f09's `home_limit(player)` are
both satisfied by the same functions.

### 11.2 PROPOSED decisions made while implementing

1. **tier3 auction/order slots = 90** — the spec says "at least" tier2
   [S17]; 90 it is (V-72).
2. **media aliases tier3** in all three slot tables and in the `/rtp`
   cooldown (§4.1), so config only carries the four `default..tier3`
   entries per perk.
3. **Stacking (V-74):** consecutive *same-tier* grants extend
   `expires_at` by `days` each; a grant for a *different* tier restarts
   the clock from `now` (the §6 algorithm's base rule). T3 verifies the
   same-tier path gives `now + 60d`.
4. **`/rtp` fallback (V-76):** `rtp_cooldown()` returns
   `cooldowns[tier] or cooldowns.default`; only `tier1` is short by
   default.
5. **Expiry (§8):** a watch set holds dirty candidates (names with a
   live `expires_at`, populated by grants and joins). The hourly
   `core.after` sweep and the join check only emit
   `Your rank has expired` (`PROPOSED`) once per server run — no record
   is ever mutated (T2). The sweep never scans the full table.
6. **`/ranks` (V-73, PROPOSED):** a prompt menu titled `Ranks`
   (`04-ui-kit.md §4.1`) with one label row per configured tier —
   `Donut+: 9 homes, 45 auction slots, 45 order slots, 30s rtp` — built
   from the live tier table (T7 mutates the table and re-renders to
   prove it), a `Store` field holding `ranks.store_text` for copying
   (`(no store link configured)` when unset; Luanti cannot open URLs,
   §4.2.9), and a `Back` button.
7. **`chat_prefix` configured form:** when `ranks.chat_prefix` is
   non-empty, `@1` in the template is substituted with the player's
   display tier name. Default stays `""` — OBSERVED by absence (T5,
   V-24).
8. **Admin/notification strings (none observed, all PROPOSED):**
   `Granted @1 to @2 for @3 days`, `Cleared @1's rank`,
   `Your rank has expired`, `Unknown tier: @1. Tiers: default, tier1,
   tier2, tier3, media`, `Days must be a whole number of at least 1`.

### 11.3 Cross-mod findings for the integrator (not edited — other agents' files)

1. **f08 §6.2** indexes `cfg.rtp.cooldown[smp_ranks.tier(name)]`
   directly. That yields `nil` for tier2/tier3/media (f08's table has
   only `default` and `tier1`). It should call
   `smp_ranks.rtp_cooldown(name)` instead.
   **[HANDED OFF → H2 / `fixes/f08-teleport.md`]**
2. **`smp_orders.slot_limit(name)`** reads `rec.rank` directly and
   ignores `expires_at`, so an expired tier1 keeps 45 order slots —
   both a §4.2.4 violation and a lazy-expiry bug. It should call
   `smp_ranks.order_limit(name)`.
   **[HANDED OFF → H1 / `fixes/f04-orders.md`]**
3. **f09** `home_limit(player)` works as written.
4. **f11** registers its `info.ranks` fallback `/ranks` only when f13
   has not registered first (`smp_social/info.lua` guard); `smp_social`
   lists `smp_ranks` in its `optional_depends`, so it loads after this
   mod and the perk-table screen wins while the fallback stays dormant
   — as f11 §10 specifies.
5. **Slot config keys:** `smp_ranks` reads the flattened settings keys
   `homes.slots_default|tier1|tier2|tier3` (and the same for `ah.` and
   `orders.`, plus `rtp.cooldown_default|tier1|…`), because the
   table-shaped entries in `shared/06-config-reference.md` cannot
   survive a `.conf` file. See the proposed shared change below.

## Proposed shared changes

For the integrator to merge into `spec/shared/` (I do not edit it):

1. **`06-config-reference.md` — materialise the slot tables as flat
   settings keys.** One config value must drive both the `/ranks`
   screen and the enforcement (§8), so the mirror should list the keys
   `smp_ranks` actually reads:

   | Key | Default | Spec |
   |---|---|---|
   | `homes.slots_default` / `homes.slots_tier1` / `homes.slots_tier2` / `homes.slots_tier3` | 2 / 9 / 27 / 90 | f09 §7 (`homes.slots`) |
   | `ah.slots_default` / `ah.slots_tier1` / `ah.slots_tier2` / `ah.slots_tier3` | 9 / 45 / 90 / 90 | f03 §7 (`ah.slots`) |
   | `orders.slots_default` / `orders.slots_tier1` / `orders.slots_tier2` / `orders.slots_tier3` | 9 / 45 / 90 / 90 | f04 §7 (`orders.slots`) |
   | `rtp.cooldown_default` / `rtp.cooldown_tier1` | 60 / 30 | f08 §7 (`rtp.cooldown`) |

   `media` is not a key: it aliases `tier3` (§4.1). `smp_orders`
   already reads `orders.slots_*` in exactly this shape, so no
   consumer changes.
2. **Consumers must call the perk API (§4.2.4).** The concrete edits
   belong to the owning feature files and are listed in §11.3: f08
   should call `rtp_cooldown(name)`, f04's `slot_limit` should call
   `order_limit(name)`. I have not touched either file.
