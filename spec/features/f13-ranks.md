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
  smp_store.mark_dirty("players", name)
end
```

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `ranks.grant_days` | 30 | LIVE [S17] |
| `ranks.chat_prefix` | `""` (no prefix) | **OBSERVED** by absence [F0269] — see V-24 |
| `ranks.expiry_check_interval` | 3,600 s | PROPOSED |
| `ranks.store_text` | configurable store URL and blurb | PROPOSED |
| Slot tables (`homes.slots`, `ah.slots`, `orders.slots`) | declared in `f09`, `f03`, `f04` | LIVE [S17] except defaults/tier3 |

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
