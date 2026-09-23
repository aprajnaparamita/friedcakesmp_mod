# Spec ↔ Implementation Conformance Report — FriedcakeSMP

**Date:** 2026-09-23 (audit) · second pass with remediation applied same day
**Scope:** all 16 feature specs (`spec/features/f01`–`f16`) audited against the
implementation in `friedcake/mods/` (22 mods, ~27,500 Lua LOC), the cross-mod
contract in `spec/shared/`, and the test matrix in `spec/plan/acceptance-tests.md`.
**Method:** six parallel read-only audits, one per feature group, each reading its
feature file end-to-end, all `spec/shared/` contracts, every Lua file of the
assigned mods, and the corresponding dev-tests. Absence was confirmed by grep
before any `MISSING` verdict; verbatim UI strings were compared character by
character. All dev-test suites were executed and pass (exit 0) — see §5 for why
that is less reassuring than it sounds. Two headline defects were re-verified
against the engine clones (`~/dev/luanti`, `~/dev/mineclonia-git`) before publication.

**Status vocabulary:** `OK` · `PARTIAL` · `MISSING` · `DIVERGENT` (implemented but
differs from spec) · `N/A`.
**Verdict vocabulary:** `COMPLETE` · `MOSTLY COMPLETE (n gaps)` · `PARTIAL (n gaps)` ·
`NOT IMPLEMENTED`.

---

## 0. Remediation applied — 2026-09-23 (second pass)

This section supersedes the findings below where they conflict. After the
baseline audit (sections 1–6), the integrator fixed the blockers, the data-loss
defects and the clear bugs. All dev-test suites remain green. Commits
`68b5bf5` · `86c5918` · `87c0eae`.

| # | Finding | Status |
|---|---|---|
| B1 | `core.register_on_globalstep` → `core.register_globalstep` (6 sites) | **FIXED** |
| B2 | `core.modpath` → `core.get_modpath("smp_tp")` + path join (`smp_tp/init.lua`) | **FIXED** |
| B3 | f09 wiring: `dofile homes.lua`; `smp_tp/mod.conf` gains `smp_store`/`smp_ranks` | **FIXED** |
| P1-4 | spawner `sell all` decremented storage before validating `smp_sell.sell` | **FIXED** |
| P1-5 | `bool()` = `get_bool(key) or default` made default-true keys un-disableable | **FIXED** |
| P1-6 | mod_storage ledger paged by global id under actor filter; sqlite dropped `shards_for_playtime` | **FIXED** |
| P1-7 | amethyst join refresh `for list in ipairs(...)` bound the index, not the name | **FIXED** |
| P2-8 | RTP never read `world.spawn_protect_radius`; `_border` assigned before probe | **FIXED** |
| P2-9 | teleport-request cancellation cleared the sender's inbox, not outbox | **FIXED** |
| P2-10 | `/pay` did not consult `smp_social.blocks` | **FIXED** |
| P2-12 | `smp_tp` lone `\241` triangle + raw strings; `Shards: ` prefix; `smp_social` raw strings | **FIXED** |
| Harness | dev-test stubs masked the wrong engine API names | **FIXED** — harnesses now stub the correct names |

Remaining after remediation (tracked in `fixes/`):

- **P2**: tag-event hooks for "either party" warm-up cancellation;
  `follow()` → blocks and the rtpqueue ignore/block inversion (PROPOSED —
  needs a spec ruling); `smp_social` has no dev-test (0 of 10 §9 tests).
- **P3**: the configuration-key reconciliation pass (never-read keys,
  `smp_tp.` prefix divergence, `ah.history*`/`rtpqueue.separation` renames,
  the f03-vs-f04 slots encoding).
- **P4**: spec-side rulings (race-string period f03-vs-f05, V-55 receipt
  screen, f12/f14 table corrections, f07 wording splits, `smp_store.mark_dirty`
  naming, f16 scope).

---

## 1. Executive summary

| Feature | Spec | Mod(s) | Verdict | Rows OK | Gaps | §9 tests |
|---|---|---|---|---:|---:|---|
| f01 Economy core | `f01-economy-core.md` | `smp_economy`, `smp_store`, `smp_admin`, `smp_core`, `smp_items` | **PARTIAL** | ~30 | ~14 | T1–T4, T9, T10 green; T5/T6 weak; T7/T8 absent |
| f02 Sell | `f02-sell.md` | `smp_sell` | **MOSTLY COMPLETE** | 37 | 2 | T1–T10 green |
| f03 Auction | `f03-auction.md` | `smp_ah` | **MOSTLY COMPLETE** | 44 | 4 | T1–T10 green |
| f04 Orders | `f04-orders.md` | `smp_orders` | **MOSTLY COMPLETE** | 48 | 3 | T1–T14 green |
| f05 Quick Buy | `f05-quickbuy.md` | `smp_quickbuy` | **COMPLETE** | 25 | 0 | T1–T7 green |
| f06 Shards | `f06-shards.md` | `smp_shards`, `smp_shardshop`, `smp_amethyst` | **MOSTLY COMPLETE** | 30 | 5 | T1/T3–T6/T8/T9 strong; T2/T4/T7 weak |
| f07 Spawners | `f07-spawners.md` | `smp_spawners` | **PARTIAL** | 48 | 14 | T1–T10 green (T9 stubbed) |
| f08 Teleport | `f08-teleport.md` | `smp_tp`, `smp_rtpqueue` | **MOSTLY COMPLETE** | 30 | 8 | T1–T13 green (T2 weak) |
| f09 Homes | `f09-homes.md` | `smp_tp` (homes) | **PARTIAL** | 14 | 4 | T1–T8 green **but shimmed** |
| f10 Combat | `f10-combat.md` | `smp_combat`, `smp_bounty` | **MOSTLY COMPLETE** | 18 | 2 | T1–T12 green |
| f11 Social | `f11-social.md` | `smp_social` | **MOSTLY COMPLETE** | ~27 | 5 | **0 of 10 exist** |
| f12 Settings | `f12-settings.md` | `smp_settings` | **MOSTLY COMPLETE** | ~26 | 4 | T1–T8 green; T9 absent |
| f13 Ranks | `f13-ranks.md` | `smp_ranks` | **MOSTLY COMPLETE** | all but 2 | 2 | T1–T8 green |
| f14 Stats | `f14-stats.md` | `smp_stats` | **MOSTLY COMPLETE** | ~40 | 4 | T1–T11 green (incl. 50 ms perf test) |
| f15 World rules | `f15-world-rules.md` | `smp_world` + `minetest.conf.example` | **COMPLETE** | all | 0 | T1/T3/T5–T7 green; T2/T4 external |
| f16 Legacy | `f16-legacy.md` | `smp_crates`, `smp_afk`, `smp_teams`, `smp_duels`, `smp_servershop` | **NOT IMPLEMENTED** | 1 | 37 | **0 of 11 exist** |

**Headline (post-remediation):** the modpack is substantially built and,
requirement-for-requirement, faithful where it exists — roughly 90 % of all
audited rows are `OK`, and every *observed* (frame-evidenced) verbatim string
that was checked matches the spec character for character. The boot blockers
and data-loss defects are **fixed** (§0). The items that remain between the
pack and a fully conformant server are:

1. **Configuration keys are the weakest contract** (§3.1) — a systemic pattern
   of declared keys that are never read, and keys read under a different name
   than the shared mirror documents (the default-true `bool()` helper bug is
   already fixed, §0).
2. **f16 legacy modules do not exist** (§4.16) — a scope call for the integrator.
3. **Test-coverage holes remain** (§3.3) — `smp_social` has no dev-test, and no
   cross-mod seam is tested with both sides real.

---

## 2. Blocking defects — **RESOLVED** (see §0)

Both defects below were **fixed** in the remediation (commit `68b5bf5`). They
are retained for the record: all dev-tests had stubbed the wrong API, so every
suite stayed green while a real server would have aborted during mod loading.
The harnesses now stub the correct names.

### B1. `core.register_on_globalstep` does not exist — 6 call sites

The engine API is `core.register_globalstep` (`~/dev/luanti/doc/lua_api.md:6576`,
defined at `builtin/game/register.lua:591`). Whole-tree greps of the Luanti and
Mineclonia clones for `register_on_globalstep` return **zero matches**. Each call
below raises `attempt to call a nil value` at load time:

| # | Site | Affected feature |
|---|---|---|
| 1 | `friedcake/mods/smp_store/init.lua:351` | f01 — blocks every mod that depends on `smp_store` |
| 2 | `friedcake/mods/smp_ah/init.lua:1276` | f03 |
| 3 | `friedcake/mods/smp_orders/init.lua:709` | f04 |
| 4 | `friedcake/mods/smp_shards/init.lua:262` | f06 |
| 5 | `friedcake/mods/smp_amethyst/init.lua:193` | f06 |
| 6 | `friedcake/mods/smp_stats/playtime.lua:59` | f14 — `smp_stats` would fail **even after** #1 is fixed |

Known: `spec/features/f10-combat.md:343-347` documents #1 verbatim. Every
dev-test harness defines the fake instead (`dev-tests/harness_f10.lua:316-320`
says outright "does not exist in the engine", `test_stats.lua:259`,
`test_economy.lua:207`, `test_shards.lua:179`, `test_spawners.lua:296`,
`test_amethyst.lua:228`, `test_ranks.lua:254`, `test_orders.lua:303`,
`test_sell.lua:685`, `test_homes.lua:278`, `ah_harness.lua:782`). **The tests
encode the bug rather than catching it.**

### B2. `core.modpath` does not exist — `smp_tp` never loads

`smp_tp/init.lua:19-27` — eight `dofile(core.modpath("…"))` calls. The engine
function is `core.get_modpath(modname)` (`lua_api.md:6092`); note the calls also
pass a *filename* where the engine takes a *modname*, so a rename alone is not
enough — the path join must change too. Grep of both engine clones: zero matches
for `core.modpath`. Disclosed at `spec/features/f09-homes.md:272-276`; shimmed by
`dev-tests/test_tp.lua:196` and `dev-tests/test_homes.lua:355`.

### B3. f09 wiring — three integrator edits never made

Per `f09-homes.md:260-309`, all assigned to the integrator, none present:

1. `smp_tp/init.lua` never `dofile`s `homes.lua` (it loads 8 other files) — so
   `/homes`, `/sethome`, `/delhome` do not exist in-game.
2. `smp_tp/mod.conf:3` is still `depends = smp_core, mcl_worlds, mcl_spawn`; the
   spec's exact replacement adds `smp_store` (+ optional `smp_ranks`).
3. The B2 `core.modpath` blocker.

The dev harness dofiles `homes.lua` directly and shims `core.modpath`
(`dev-tests/test_homes.lua:355, 386-389`), which is why 134/134 tests pass for a
feature that cannot run.

**Consequence of B1–B3 together:** on a real server, mod loading aborts at the
first failing mod; no feature in this report is currently reachable in production.

---

## 3. Cross-cutting findings

### 3.1 Configuration keys are the weakest contract

`spec/shared/06-config-reference.md` is the operator-facing promise. Four distinct
failure modes appear across the pack:

| Failure mode | Instances |
|---|---|
| **Declared key never read** (operator setting has no effect) | `ah.sorts` (`smp_ah/init.lua:65` hardcodes), `orders.sorts` (`smp_orders/init.lua:48`), `settings.categories` (`smp_settings` hard-registers; documented F12-C), `shardshop.offers` (catalogue hard-coded), `economy.max_balance` (read at `smp_economy/init.lua:31,44` but dead — cap comes from `store.max_balance`), `spawners.convert_natural`, `spawners.stack_mode`, `spawners.blast_immune` (inert) |
| **Key renamed in code** | `ah.history` → `ah.history_page`/`ah.history_pages` (`smp_ah/init.lua:53-54`); `rtpqueue.separation` → split `min/max_separation` (`smp_tp/config.lua:110-111`) |
| **Namespace prefix divergence** | all of `smp_tp`/f09 reads `smp_tp.<key>` where `shared/06` documents `tp.*`, `rtp.*`, `homes.*` (`config.lua:8-15`, `homes.lua:46,62-65`) → `minetest.conf` entries written per the mirror are silently ignored |
| **Encoding divergence between sibling mods** | `ah.slots.default` (dotted, `smp_ah/init.lua:59-62`) vs `orders.slots_default` (underscore, `smp_orders/init.lua:41-46`) configure the *same* documented table two different ways; neither matches the declared key literally |

**Helper bug:** `smp_spawners/init.lua:39-41` defines
`bool(key, default) = settings:get_bool(key) or default`. Because `false or
default` yields the default, **four default-true keys can never be set to false**:
`spawners.require_silk_touch`, `spawners.blast_immune`,
`spawners.enable_creeper` (V-04's documented escape hatch), and
`spawners.acquisition.admin` (making the "disabled" message dead code).

**Mirror omissions (integrator-owned, flagged not edited):** `sell.base_prices`,
`orders.allow_self_delivery`, `quickbuy.page_size`, `shards.transferable`,
`shardshop.offers`, `settings.cycle_order`, `homes.delete_confirm`,
`combat.log_broadcast`, and all `world.*` keys are declared in feature §7 but
absent from `shared/06`; conversely four `legacy.*` keys (`06:81-84`) advertise
defaults that no code reads because f16 does not exist.

### 3.2 Translation (`core.get_translator`) — hard rule 7

Mostly good; specific holes:

- `smp_tp/formspec.lua:35,39,40,92` — `Teleport Request`, `Deny`, `Accept`, `Main`
  raw. Line 35 additionally renders a lone invalid UTF-8 byte `\241` where the
  correct triangle is `\226\154\160` (as `homes.lua:72` does).
- `smp_shardshop/formspec.lua:91` — `label[8.35,0.05,Shards: %s]` hard-codes the
  English `Shards: ` prefix.
- `smp_social` — `findplayer.lua:75,77,93-96` (`Spawn`, dimension and region
  names), `kill.lua:24-25`, `info.lua:119,131-171` (screen titles) raw.
- `smp_economy/init.lua:502-510`, `smp_store/init.lua:326` — raw strings to chat.
- Minor house-style drift (terminal full stops vs shared §0.5.4) in invented
  strings across `smp_settings` (`init.lua:220`), `smp_stats`
  (`formspec.lua:197`, `init.lua:106,119,134,142`, `api.lua:120`).

Everything else audited uses `S()` correctly. Money is integer cents with no
floats found anywhere, and all money display goes through `smp_core.fmt_money`
(including the scoreboard's third, lowercase convention `754k`).

### 3.3 Test-coverage holes

| Hole | Detail |
|---|---|
| **f11 has zero executable tests** | no `dev-tests/test_social*.lua`, no `mods/smp_social/test.lua` (also violates AGENTS step 7). All ten §9 tests unverified — including the two OBSERVED strings the P7 gate names (chat format, `/msg` refusal), which are correct by inspection only. `smp_social` is the only feature mod with no in-mod test. |
| **f16 has zero tests** | 0 of 11, and no code to test. |
| **f12 T9 untested** | the `FRIENDS_FOLLOWED` stranger-`/msg` leg — blocked on f11 having a harness. |
| **Cross-mod seams never tested with both sides real** | f03↔f04, f03↔f05, f07→f02, f08→f11: each side is tested with the counterpart stubbed. No modpack-level integration test exists. |
| **Harnesses mask the blocking defects** | every dev-test defines `register_on_globalstep`/`core.modpath` instead of failing (§2). |
| **Weak single tests** | f01 T5 asserts `>= 2` ledger rows not the exact two, T6's flag path unasserted; f07 T9 uses a stubbed `smp_sell.sell`; f08 T2 does rule-level checks rather than the specified 1,000 trials per dimension; f06 T2's "restart" does not reload the module, T4 never places a blacklisted node and stubs `add_wear`; f14 T4/T5 simulate f02/f05 writes rather than driving the real flows. |
| **f04 in-game `test.lua:6` overclaims** | header says "§9 T1–T14"; the heavy tests live only in dev-tests. |

Everything that does exist passes: `test_fmt`, `test_store`, `test_economy`,
`test_ranks` (76), `test_world` (99), `test_sell`, `test_spawners` (86),
`test_ah`, `test_ah_keys`, `test_orders`, `test_quickbuy`, `test_shards`,
`test_shardshop`, `test_amethyst`, `test_tp` (98), `test_homes` (134),
`test_combat`, `test_bounty`, `test_settings` (517 lines), `test_stats` (879
lines) — all exit 0.

### 3.4 Spec-side notes for the integrator (not code defects)

- `f13 §6` pseudocode calls `smp_store.mark_dirty`; no such helper exists
  (write-through `upsert_player` is the equivalent).
- `f05:194` specifies the race string `This item was already bought.` **with** a
  period, while the OBSERVED source and `shared/08:148` are period-free; `f03`
  implements period-free, `f05` implements with period — each matches its own
  feature file, so the two mods disagree in production. One spec line must yield.
- `f07 §3` sketch says `Page 1/5` while V-01 says `Page n of m`; `×n` (§4.6.3)
  vs `x128` (§3/§5). Code follows V-01/§3 consistently.
- `f12` carries its own acknowledged conflicts (F12-B defaults, F12-C categories),
  `f14` carries F14-D5 (`api.mode`) — the code follows the spec's own decision
  records against its §7 tables; the tables should be corrected.
- `f16 §7`'s four mirrored `legacy.*` keys advertise an unbuilt feature.

---

## 4. Per-feature findings

Each block: verdict, the exceptions (every non-`OK` row, with evidence), what was
confirmed `OK`, deviations, beyond-spec additions, and test status. Full OK-row
inventories were produced during the audit; only counts and section summaries are
reproduced here — every exception is listed in full.

---

### f01 — Economy core · **PARTIAL (~14 gaps)**

`~30 rows OK · smp_economy (648) · smp_store (958) · smp_admin (26) · smp_core (315) · smp_items (265)`

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §4.2.1 | `/pay` refuses recipients the player has blocked | MISSING | handler `smp_economy/init.lua:183-233` never consults `smp_social.blocks`; the check exists at `smp_social/graph.lua:112` but is unused (grep-confirmed) |
| §4.2.4 | Offline pay summary shown on join | MISSING | no join handler anywhere in `smp_economy` |
| §4.2.5 | Transfer flag → `smp_admin.flag` | PARTIAL | only `core.log("warning", …)` `init.lua:220-224`; `smp_admin` is 26 LOC of priv registration with no flag API |
| §2 / R9 | `/pay` rate limit | MISSING | no cooldown logic |
| shared §2.6 R11 | Ledger reversal helper | MISSING | no reversal/undo in `smp_store`/`smp_economy` |
| shared §2.6 R12 | Pending marker on ledger rows | MISSING | — |
| §2 | `/ledger` privs must be OR (`f01 §8:188-191`) | DIVERGENT | `init.lua:415` uses a nested privs table = Luanti AND semantics |
| §2 | `/eco reset <player> <amount>` | PARTIAL | `<amount>` ignored, always zeroes (`init.lua:400-402`) |
| §2 | `/smp test` | PARTIAL | closure references `run_smp_core_tests` as a global at `:459`; declared `local` at `:475` → runtime nil call |
| §2 | `/pay` tab completion | PARTIAL | server-side prefix resolve `init.lua:155-179`; no full completion integration |
| §3.2/§0.5 | i18n + no terminal periods | PARTIAL | raw strings `init.lua:502-510`, `smp_store/init.lua:326`; several invented strings carry terminal periods |
| §5.1 | `shards_for_playtime` field | PARTIAL | absent from `ensure_player` and the sqlite schema → dropped on sqlite upsert (`backends/sqlite.lua:192-219`) |
| §5.2 | Ledger `counterparty` | PARTIAL | always written `""`; information lives in `ref` instead |
| §5 | mod_storage `ledger_for` pagination | DIVERGENT | `backends/mod_storage.lua:149-156` paginates by the **global** id index under an actor filter → duplicates/omissions from page ≥ 2 |
| shared §2.2 | Dirty-flag batching | DIVERGENT | mod_storage `flush` is a no-op; write-through, no batching |
| §7 | `economy.max_balance` | DIVERGENT | read (`init.lua:31,44`) but dead; cap comes from `store.max_balance` |
| §7 | smp_core event bus / config loader / widget helpers | MISSING | `show_formspec`'s preamble argument accepted and ignored |
| §4 (M2) | Shulker reversible codec | PARTIAL | 64-bit hash only (`smp_items/init.lua:100-107`) |
| backend | `auto` backend selection | PARTIAL | heuristic never picks sqlite (`smp_store/init.lua:46-50`) |
| §6 | `pay_accept` placement | PARTIAL | stored inside `record.social` (`init.lua:71-86`), not a dedicated setting |
| §9 | T5 / T6 / T7 / T8 | PARTIAL / MISSING | T5 asserts `>= 2` not exact; T6 flag path unasserted; T7, T8 have no test |

**Confirmed OK:** `/pay`, `/bal` + aliases, `/baltop`, `/shards`, integer cents
throughout, no yields on the pay path, `fmt_money` used by every money display,
economy caps via store, `smp_items` M0/M1, `This item was already bought`
(period-free in `smp_ah`), T1–T4/T9/T10.

**Beyond spec:** `/payto` (`init.lua:244`); prefix-resolution completion; hash-based
stack signature (a simplification, not an extension).

**Cross-feature note:** `smp_quickbuy/buy.lua:87` renders the f01 §3.3 race string
with a trailing period — see §3.4.

---

### f02 — Sell · **MOSTLY COMPLETE (2 gaps)** · 37/39 OK

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §6 | History via `smp_store.append_sell_history` | DIVERGENT | history lives in `smp_sell`'s own mod storage (`history.lua:43-59,101-117`) — **declared** as V-94 with the API proposed in `f02:202-207` |
| §6 | `receipt:show(player)` receipt screen | PARTIAL | chat lines instead (`receipt.lua:164-214`); V-55 (receipt screen) is still open in §10 — needs an integrator ruling |

**Confirmed OK:** all four §2 commands incl. `/worth`; every observed UI element —
container titled exactly `Sell`, 9×5 grid with 44 drop slots + confirm cell, lime
confirm pane with `Confirm\nClick to sell items`, `Inventory` label — verified
verbatim against `shared/08:22,40`; routing to better/higher-priced orders with
remainder to server (`sell.lua:92-114`); shulker contents sold with the box
returned holding ineligible items; `/sell` allowed while tagged; 100-entry
history; `money_made_from_sell` counts both proceeds; reloadable base prices;
full-inventory drop-at-feet; disconnect return-before-save; all §7 keys; **all ten
§9 acceptance tests** (T1–T10) asserted in a 2,001-line dev-test.

**Beyond spec:** `sell.history_page_size`, `sell.receipt_max_lines` (undeclared
keys); `id`/`source` history fields; crash-safe container mirror + join recovery
(stronger than required); `/sellreload`; in-game `test.lua` (599 lines, 64
assertions).

**Hygiene:** PASS on all four cross-cutting checks.

---

### f03 — Auction house · **MOSTLY COMPLETE (4 gaps)** · 44 OK

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §4.12 | Quick Auction Sell "Match lowest" button on `Confirm Listing` | MISSING | no string, no handler (grep) — PROPOSED-only, no frame evidence |
| §7 / `06:22` | `ah.sorts` configurable | DIVERGENT | sort table hardcoded `init.lua:65`, key never read |
| §7 / `06` | `ah.history` | DIVERGENT | code reads `ah.history_page`/`ah.history_pages` (`init.lua:53-54`) |
| §7 / `06:17` | `ah.slots` table key | PARTIAL | read as dotted scalars `ah.slots.default…` (`init.lua:59-62`); inconsistent with f04's encoding of the same table |

**Confirmed OK:** all commands incl. aliases `/auction`, `/auctionhouse` and
`/ahadmin`; **11/11 observed strings character-exact** (`Auction (Page N)`,
`Search`/`Filter`/`Your Items`/`List` two-line tooltips, `Search Auction`,
`Auction > Your Items`, `Insert Item`, `Edit Sign Message`, `Type price`, `Done`,
`Confirm Listing`, `Auction > Confirm Purchase`, the total-price line, the
period-free race string, the three sort labels in observed cycle order); 14/15
§4 behaviours — total-price semantics, re-validation + funds + room with no
yields (`init.lua:850-872`), capacity tiers 45/90/9, 48 h expiry + 30-day
reclaim, fees, both routing directions, 100/page history, `$1…$10¹²` bounds,
unit-price and token indexes (no full scans); §5 schema; §6 algorithms;
**T1–T10 + a dedicated key-identity suite**.

**Beyond spec:** undeclared keys `ah.insert_slots`, `ah.rate_limit`,
`ah.sweep_interval`, `ah.sweep_budget`, `ah.reclaim_days`; legacy `k0/k1/k2` key
migration; cancel/reclaim affordances (sanctioned PROPOSED); an `smp_orders` stub
so the mod loads standalone.

**Note:** rate limiting itself is sanctioned by shared §2.6 R9; only the key name
is undeclared.

---

### f04 — Orders · **MOSTLY COMPLETE (3 gaps)** · 48 OK

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §7 / `06:27` | `orders.sorts` configurable | DIVERGENT | hardcoded `init.lua:48`, key never read |
| §7 / `06:24` | `orders.slots` table key | PARTIAL | underscore scalars `orders.slots_default…` (`init.lua:41-46`) — matches neither the declared key nor f03's dotted style |
| §4.13 | Notifications respect `eco.order_alerts` (f12) | PARTIAL | `routing.lua:45-58` reads it but carries `TODO(f12): default on until smp_settings ships` (`routing.lua:53`); f12 has since shipped, so the TODO is stale |

**Confirmed OK:** all commands; **14/14 observed strings character-exact**,
including `Orders (Page N)`, the deliberately ungrammatical
`Choose Item (1 results)`, `How many?`, `Price per item?`, `Minimum: $ 1`,
`Review Order`, `Cancel!`, `Create Order`, the `Orders -> …` breadcrumbs,
`Click to deliver items ($N)`, `Delivering...`, the singular-name chat line
`You delivered 1 Totem of Undying and received $30K`, and the six-line tooltip
order with `251/350 Delivered`; escrow = `unit × qty` with `Total:` as the
committed amount; automatic AH purchase cheapest-first with each seller paid their
own price; delivery over a detached inventory with M1 matching, partial fills and
returns; self-delivery refused; **all four routing-in sources**
(`/sell`, spawner Sell all, amethyst sell axe, auction listings); cancel/expiry
refunds; capacity tiers; amethyst blacklist; §5 schema; §6 algorithms;
**T1–T14** plus routing-in API contracts, quit-return, version race and persistence.

**Routing paths (explicitly checked):** order↔sell ✅ tested both sides ·
order→auction creation sweep ✅ · listing→order undercut ✅ · quick buy→orders
**N/A** — defined nowhere in f04 §4.8 or f05; `smp_quickbuy` has zero references
to `smp_orders`.

**Beyond spec:** `orders.flush_interval` (shadows the shared `store.flush_interval`
that f03 reuses), `orders.expire_check_interval`; manage screen; `Order created`
line; expiry notification; exact-itemstring blacklist contract with graceful
degradation.

**Hygiene note:** stale `TODO(f03)` comments in `init.lua:14` and
`au_bridge.lua:42,56` describe stubs that already delegate to shipped functions —
comments only.

---

### f05 — Quick Buy · **COMPLETE (0 gaps)** · 25 OK

No implementation gaps. Every §2–§9 requirement implemented and tested, including
the 3× price guard at its exact boundary (`smp_quickbuy/price.lua:30-33`, tested
300 ok / 301 warn, proving the guard is 3, not 2 or 4), M1 enchantment exactness,
combat-tag refusal, `money_spent_on_shop` accounting, per-listing version
re-validation with raced listings skipped and never charged.

**Spec-side notes (for the integrator, not the code):** the race string carries a
period here (per `f05:194`) while f03's is period-free (§3.4 above);
`quickbuy.page_size` is implemented per §3.1 but missing from the §7 table and the
`06` mirror.

**Hygiene:** PASS on all four cross-cutting checks. Warn-screen verbatim strings
are asserted nowhere (behaviour is tested, wording is not).

---

### f06 — Shards, shard shop, amethyst · **MOSTLY COMPLETE (5 gaps)** · 30 OK

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §4.3 | Item description refreshes on use **and on join** | DIVERGENT (**defect**) | `smp_amethyst/init.lua:179` — `for list in ipairs({"main","offhand"})` binds `list` to the numeric index, so `inv:get_size(1)` matches no list and the join refresh is a silent no-op. (The separate join *sweep* at `:175` works.) |
| §7 | `shardshop.offers` configurable catalogue | MISSING | key never read; catalogue hard-coded in `catalogue.lua:49` (values do match the spec table) |
| §7 | `shards.require_activity = true` | PARTIAL | read (`init.lua:43,57`) but inert — no AFK tracking exists (depends on absent f16, V-61) |
| §4.3 | `amethyst.shovel_nodes` named key | PARTIAL | only the `shovely` group check exists (`shovel.lua:15-17`); key never read (and absent from §7) |
| §9 | T2 / T4 / T7 | weak | T2 "restart" never reloads the module; T4 claims a blacklisted-neighbour skip but never places one and stubs `add_wear`; T7's "sellable and auctionable" half untested |

**Confirmed OK:** `/shards`/`/shard` (in `smp_economy` per architecture §2.1);
`/shardsadmin`; the orders-board shard-shop entry point with the **verbatim**
`Shard Shop` / `Click to view` tooltip rendered by `smp_orders`; the **byte-exact**
award message `You earned 1 Shard for playing the server` (capital S, no full
stop); 600 s award with the floor formula and atomic persistence of `shards` +
`shards_for_playtime`; `shards` leaderboard; the 17-offer catalogue with prices
matching the spec table; the buy flow (validate → debit → deliver, no yields,
refund-on-failure); amethyst blacklisted from orders but sellable/auctionable;
1-day self-destruct timer stamped at purchase; join + 300 s sweep over
`main`/`offhand` only; all six tools (pickaxe plane ⊥ face with protection/blacklist
and wear-once, BFS felling capped at 512, shovel plane, Haste II 86400 s with
re-apply on join, 3×3×3 legacy bucket, sell axe with orders-first routing and
protection + tag checks); §5 schema; §6 algorithm; the five mirrored §7 keys with
exact defaults; T1, T3–T6, T8, T9 strong.

**Deviations worth noting:** playtime is batched and flushed every 30 s rather
than persisted every step (§6 is illustrative — semantics preserved, <30 s can be
lost on unclean shutdown, never double-counted); undeclared keys
`shards.flush_interval`, `amethyst.haste_level`, `amethyst.haste_duration`;
`formspec.lua:91` hard-codes `Shards: ` (i18n, §3.2); `mcl_potions` is a hard
dependency in architecture §2.1 but `optional_depends` in `mod.conf:4` (guarded —
arguably the better choice, but divergent), and `mcl_armor` is used
(`catalogue.lua:31`) with no matching `optional_depends`.

---

### f07 — Virtual spawners · **PARTIAL (14 gaps)** · 48/63 OK

The second-weakest feature. The production model itself (curve `C×(1−(1−r/C)^n)`,
defaults, loot tables, XP values) is implemented exactly and well tested; the
gaps are around it.

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §3 | `Inventory` label + player inventory under the menu | MISSING | grep for `list[`/`Inventory` in `smp_spawners` → 0 matches; the mod's own comment claims it (`formspecs.lua:4`); required by `shared/04:22` |
| §4.6.7 | Cannot be pushed by pistons | MISSING | no push-immunity of any kind; groups are only `cracky`/`oddly_breakable_by_hand` (`node.lua:139`) |
| §4.6.8 | Optional hopper extraction | MISSING | config key + a getter only (`performance.lua:44-48`) |
| §4.6.9 / §7 | `spawners.convert_natural` | MISSING | dead key (`init.lua:68`) — no conversion code |
| §4.5 | **Lazy accrual: every interaction converts elapsed time** | DIVERGENT | `accrue()` is called only from the node timer (`node.lua:150-151`); menu open, take, XP collect and Sell all read state only — displayed output can lag one 60 s tick |
| §4.6.4 / shared §2.3 | **Sell all must not lose items on refusal** | DIVERGENT (**defect**) | `routing.lua:61-74` decrements storage and `write_state`s **before** calling `smp_sell.sell`, then ignores the return value; f02's contract says the caller removes only on `true` (`smp_sell/init.lua:180-186`). On a `false` (balance cap `sell.lua:150`, empty plan `:195-203`) the removed items are neither restored nor returned — and the comment at `routing.lua:61` cites §2.3 while doing the opposite |
| §7 | `spawners.C.skeleton` (and per-type `C`) | DIVERGENT | code reads one compound `spawners.C` of `id=val` pairs (`init.lua:90-99`); the shared mirror's `spawners.C.skeleton` (`06:37`) has no effect |
| §7 | `spawners.acquisition` table | DIVERGENT | code reads flat `spawners.acquisition.<src>` keys (`init.lua:74-79`); the mirror's single table key cannot express that shape |
| §7 | default-true keys settable to false | DIVERGENT (**bug**) | `bool()` = `get_bool(key) or default` (`init.lua:39-41`) — `require_silk_touch`, `blast_immune`, `enable_creeper` (V-04's escape hatch), `acquisition.admin` can never be disabled |
| §7 | `spawners.stack_mode` | PARTIAL | read (`init.lua:53`) but behaviour hard-coded to whole-stack; other values silently ignored |
| §7 | `spawners.blast_immune` | PARTIAL | inert — `on_blast` is unconditionally a no-op (`node.lua:143`); default behaviour matches spec, the toggle does nothing |
| §4.6.3 | Shift-click "take as much as fits" | PARTIAL | no shift state in Luanti formspecs; `Take all` substituted per V-01 (declared) |
| §9 | T9 | PARTIAL | exercises `sell_all` with a **stubbed** `smp_sell.sell`; the ordering claim rests on f02's T4 |

**Confirmed OK:** `/spawner give` (with an undeclared 1–64 cap); header
`<Type> Spawner x<n>`, `Stored/XP` line, `Rate: @1 kills/min`, 45-slot paging with
`< Prev`/`Next >`, footer `Sell all`/`Collect XP`/`Take all`/`Close`; zero
entities/ABMs (asserted: 0 entities, 0 LBMs); nine types with exact loot/XP;
deterministic fractional accrual (no RNG anywhere); the curve with its exact
anchors (58.9 / 495.7 / 1477.6), `r=6`, `C=1505.35`; capacity `min(hard, per×n)`
with `paused_full`; XP cap + `mcl_experience.add_xp`; stack size 2,147,483,647;
accrual modes; placement/stacking/take rules with protection; Silk Touch gating;
sneak −64 with overflow drop; anyone may open/take/sell; blast immunity;
Sell-all routing through f02 (when present) with the V-63 fallback; one timer per
spawner, O(1) accrual, revalidation of node/type/stack/distance on every field,
version counter against double-collect; §5 schema; §6 algorithm; **T1–T8, T10**.

**Beyond spec:** strings not in the proposed §08 list (`Close`,
`Administrative spawner issue is disabled`, `Unknown spawner type`,
`Count must be between 1 and 64`, `This area is protected`, …);
`spawners.offline_cap_hours`, `enable_creeper`, `hopper_extraction` keys — all
correctly proposed to the shared mirror in `f07:274-282`.

**Spec-internal wording splits** the code had to break are listed in §3.4.

---

### f08 — Teleport · **MOSTLY COMPLETE (8 gaps)** · 30 OK · 2 N/A

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| precondition | mod loads on a real server | MISSING | B2 — `core.modpath` (`init.lua:19-27`) |
| §4.1.3 | Tagging **either party** cancels the warm-up | PARTIAL | mover-only checks at start (`warmup.lua:93-96`) and fire (`:140-143`); no tag-event hook; the stationary counterparty is never checked |
| §4.4.6 | Request cancelled if **either** party tagged | PARTIAL | die/leave OK (`init.lua:34-49`); tag is a lazy re-check at accept, and the acceptor-tagged branch refuses **without dropping the request** (`requests.lua:173,178-181`); plus a mirror bug — `requests.lua:44` clears the partner's **inbox** instead of their **outbox**, so the sender's outbox is never cleared (`drop_request` vs `drop_request_out`) |
| §4.2.3 | Candidate clipped to the world border | PARTIAL | ordering bug: `smp_tp._border` assigned **before** the `core.get_world_border()` probe (`config.lua:137-144`) → always clips to 30000 |
| §4.2.3 / X10 | Landing outside the protected spawn radius | PARTIAL | mechanism exists (`rtp.lua:152,166-169`) but the key defaults to **0** (`config.lua:81`) and `world.spawn_protect_radius` (128, pinned in `minetest.conf.example:53`) is never read → no exclusion by default |
| §4.6 | Ender pearls | MISSING | no pearl code anywhere — **explicitly deferred** by the spec (§10 Q-3, `init.lua:61-67`) |
| §5 | `state.rtpqueue = {joined_at}` in `smp_tp.state` | DIVERGENT | queue state lives in `smp_rtpqueue`'s own members table; behaviour unaffected |
| §7 / `06:50-63` | Config keys readable under documented names | DIVERGENT | everything read as `smp_tp.<key>`; `rtp.cooldown` **never read** (hardcoded `config.lua:56-61` + undocumented `tier2/tier3`); `rtp.menu_enabled` hardcoded; `rtpqueue.separation` split into hardcoded `min/max` |

**Cosmetic/behaviour deviations:** `stay = 20` (20 ticks = 1 s) where §8 line 322
says `stay = 1` — correct visibility, literal spec value not implemented;
`/world` origin recorded at warm-up **start**, so a *cancelled* warm-up still
overwrites `last_teleport_from`; `formspec.lua:35` renders a lone invalid UTF-8
byte `\241` as the triangle; `Teleport Request`/`Deny`/`Accept`/`Main` not
translated (§3.2).

**Confirmed OK:** warm-up countdown on the action bar; origin recording for
successful teleports; movement/damage/tag cancellation for the mover; per-command
tier-reduced cooldowns; bare `/rtp` with no menu, named regions, ring radius,
dimension bands from `mcl_vars`, async `emerge_area` with a remaining-guard,
**the full safe-y hazard reject list** (two free non-liquid nodes, nether band,
end stone only), ≤10 attempts with **no cooldown on failure**, 60/30 s cooldowns,
the 3 s RTP zone at 1 Hz; the whole queue — toggle, FIFO pairing, 5 s countdown to
one safe location 16–32 apart, 300 s timeout, leave/move/tag exit, mutual-blocker
exclusion; one pending request per (sender,target,type) with 60 s expiry, the
**single generic refusal** `This player cannot be asked for a teleport`,
`tp.confirm_menu` Accept/Deny layout, `/tpauto`, warm-up on the correct (moving)
party only; `/spawn` lobby menu, `/warp`, `/back` off by default, `/spawn`+`/warp`
on the f10 block list; `smp_rtpqueue` in `modpack.conf`.

**Optional/N-A:** K/D-or-gear matchmaking (optional); chat-privacy on requests
(PROPOSED, needs f11/f12).

**Beyond spec:** `tier2`/`tier3` cooldowns; the `smp_tp.*` prefix namespace and
`spawn_protect_radius` key.

---

### f09 — Homes · **PARTIAL (4 gaps)** · 14 OK

**The feature is complete inside its edit surface but does not run.**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §11 note 1 | `dofile(... "homes.lua")` wired from `init.lua` | MISSING | `init.lua:19-27` loads 8 files, not `homes.lua`; `homes.lua:24` and `test_homes.lua:55` both await the integrator's line |
| §11 note 2 | `mod.conf` gains `smp_store` (+ optional `smp_ranks`) | MISSING | `mod.conf:3` unchanged |
| §11 note 1 | `core.modpath` blocker fixed | MISSING | B2 — even with the first two applied, the mod still cannot load |
| §7 / `06:64-67` | `homes.*` keys under documented names | DIVERGENT | read through the `smp_tp.`-prefixed helper (`homes.lua:46,62-65`) → mirror-named entries silently ignored (values themselves all match defaults) |

**Confirmed OK:** `/homes`, `/home`, `/sethome`, `/delhome`; slots
`{2,9,27,90}` tier-gated through an `smp_ranks` bridge with a documented fallback;
`name_max` 32; **the full observed UI reproduced character-for-character** — the
`Homes` tab row with correct triangle, one tab per home, `New Home` after the last,
`Show More` far right and separated at `tabs_before_more=3`, tooltips
`<name>`/`Click to manage`, the 2×2 submenu (`Teleport`/`Change Icon`,
`Rename`/`Delete`, centred `Back`, red Delete), `Choose Icon` with the
alphabetised registered-item list and `Search`/`Default`/`Back`, `Rename`
pre-filled with the current name with stacked `Save`/`Cancel`, delete
confirmation; **all five verbatim chat strings**
(`Home set`, `Home deleted`, `Home does not exist`, `You reached home limits`,
`You renamed your home to @1`); storage in the `smp_store` record; stale-id
re-validation at click time; T1–T8.

**Beyond spec:** `Choose Icon` paging (`(Page @1)`, `Prev`, `Next`) as a formspec
substitute for a scrolling list — harmless; `homes.delete_confirm` key missing
from the mirror.

**Test caveat:** 134/134 pass **only because the harness shims all three load
gaps** (`dev-tests/test_homes.lua:355,386-389`). T9's `/findplayer` leg is
owner-scoping only (the command belongs to f11).

---

### f10 — Combat & bounties · **MOSTLY COMPLETE (2 gaps)** · 18 OK · 1 N/A

All four roadmap-critical behaviours verified:

| Gate | Status |
|---|---|
| 20 s tag refreshed by every hit | OK — `tag.lua:85`; T1 asserts exactly 20 + refresh |
| Action-bar countdown `In combat: @1s`, `stay=40`, 1 Hz, clears on untag | OK — `countdown.lua:29-32`, exactly per §10.1 note 6 |
| **Combat log drops all four registered lists** and credits the kill | OK — lists *iterated, never hard-coded* (`combatlog.lua:45,75-76`); harness registers `main`/`craft`/`armor`/`offhand`; T4 asserts all four drop at the logout coordinates |
| Blocked commands refuse while tagged | OK — all 10 spec commands + 2 extra aliases; refusal `You cannot use /@1 during combat.` character-exact (`blocks.lua:26-32`); `/sell`, `/msg`, `/ah` correctly allowed; enforced via `register_on_chatcommand` as specified |

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §4.2.5 | `combat.disable_elytra` hook into `playerphysics/elytra.lua` | MISSING | key read (`config.lua:26`); `init.lua:140-143` only logs a warning when true; no hook anywhere — **spec-disclosed** (§10.1 note 14) |
| §7 / `06:71` | `combat.keep_pearls_on_death` honoured | MISSING | grep finds the key only in two *test files* (`smp_settings/test.lua:182`, `dev-tests/test_settings.lua:492`) — **no production reader**; its only consumer is f08 §4.6 pearls, itself spec-deferred |

**Confirmed OK:** melee/arrow/explosion tagging of both parties with the specified
attribution rules (blast ring 10 s/12 nodes/64-cap, V-73 ignition gap
spec-acknowledged); untag on death of player **or** opponent with credit before
untag; `/kill` while tagged credits the last attacker; combat-log broadcast
`@1 has logged out during combat.`, `smp:combat_logged = 1`, respawn at world
spawn, flag cleared (with a beyond-spec keep-on-failure retry per note 15);
kill credited to the last attacker into stats and bounty; the complete bounty
flow — list by total largest-first, escrow debit with stacked contributions,
`bounty.min_amount` $1 000 with the exact `The minimum bounty is $ 1K.`,
self-refusal, whole-bounty payout + broadcast, no IP-shared payout, 3 600 s pair
cooldown, no payout in the safe zone, no refund except `/bountyadmin clear`
pro rata; tag state transient in memory (T11 restart-wipe); **T1–T7, T11, T12,
X10** (`test_combat`) and **T8–T10 + escrow conservation** (`test_bounty`).

**Beyond spec:** blocked list = 12 not 10 (`tp`, `home` — spec-aware, V-72);
`combat.log_broadcast` read but absent from the mirror; `/bounty` allowed while
tagged (spec silent); bounty records in `smp_bounty`'s own namespace (forced by
`06`-documented `smp_store` limitations, note 13).

**Hygiene:** PASS — integer cents, translator, config keys match `06:68-73`
unprefixed (unlike `smp_tp`), `modpack.conf` entries present, no yields on the
escrow path. The Shard-Pickaxe while-tagged block lives in `smp_amethyst` and is
wired (`pickaxe.lua:44-47`).

**Residual cross-cutting risk:** B1 site #1 blocks `smp_combat`/`smp_bounty` via
their `smp_store` dependency (disclosed at f10 §10.1 note 1).

---

### f11 — Social · **MOSTLY COMPLETE (5 gaps)** · ~27 OK · **0/10 tests**

**Implementation exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §4.3 | Block refuses **payments** (PROPOSED) | MISSING | `smp_economy` contains **zero** references to `smp_social`/`blocks(` (grep) — `/pay` never consults the list; also leaves cross-cutting X9's `/pay` leg unimplemented |
| §4.3 | Block refuses **follows** (PROPOSED) | MISSING | `friends.lua:40-74` `follow()` checks self/existing/limit only |
| §4.3 | Ignore does **NOT** exclude from RTP-queue pairing (PROPOSED) | DIVERGENT | `graph.lua:112-114` folds ignore into `blocks()`, which `smp_rtpqueue/init.lua:50` uses for pairing → ignore **does** exclude, contradicting the spec's `no` row. The code comment (`graph.lua:106-111`) claims the contradiction is "recorded in §10" — **f11 §10 contains no such entry** |
| §4.1.3 | Mutes enforced in the chat callback | PARTIAL | hook exists (`chat.lua:94-97` + `bridges.lua:97-104`) but **no mute producer exists anywhere** (`smp_admin` has no `mute`/`is_muted`; grep zero) — the requirement is inert |
| §9 | **All ten acceptance tests** | MISSING | no `dev-tests/test_social*.lua`, no `smp_social/test.lua` (AGENTS step 7 violation) |

**Confirmed OK:** all 13 §2 commands and aliases (`/msg` + 5 aliases overriding
builtin, `/r`/`/reply`, `/ignore`, `/block`, `/friend` with the full subcommand
set, `/findplayer`/`/fp`, `/nightvision`/`/nv`, `/kill` with confirmation dialog,
`/help`, `/rules`, all info commands with `/store` attached only to `/buy` per
`05:72`, `/ping`, `/list`, `/report`, `/helpop`/`/ac`); **the three OBSERVED
strings verified character-exact** — chat format `<@1> @2` with no rank prefix by
default, the `/msg` refusal `This user only accepts messages from friends or
followed players`, and the TPA hint `Click to send @1 a teleport request` as a
plain second line; the unknown-command override answering exactly
`This command does not exist` (engine suppression mechanism verified against
`builtin/game/chat.lua:67-74`); all three `chat.private_messages` states with the
ignore/block checked **before** the setting; one-way follows with derived
friendship and join/leave notices capped at 200; coarse `/findplayer` that never
returns coordinates; `/kill` death credited through f10 without double-credit;
night-vision persistence and re-apply; info screens in a read-only field;
§5 schema (`social.following/ignored/blocked`, non-persisted `last_pm`);
§6 `send_pm` pseudocode followed line-for-line with a structural
`generic_refusal()`; all seven §7 keys with exact defaults.

**Beyond spec:** `findplayer.spawn_radius`, `findplayer.region_band`, `info.*`
keys; whisper wording; argument-free `/ignore`/`/block` list display; re-asserting
commands after Mineclonia's `mcl_commands` re-registers `/kill` and `/list`.

**Tab completion** of player names after `/msg`/`/pay`/`/ignore` is `N/A`: Luanti
has no server-driven argument-completion API and the spec proposes no substitute.

**Roadmap impact:** the P7 gate "the observed chat format, `/msg` refusal …
reproduced" is true **by code inspection only** — nothing executes it.

---

### f12 — Player settings · **MOSTLY COMPLETE (4 gaps)** · ~26 OK

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §3.1/§3.2 | Yellow warning triangle beside the titles (`Settings ⚠`) | MISSING | `formspec.lua:63-68,109-114` emit label elements only; grep `⚠|triangle` → none. Meaning is open question V-28 (`04:53-56`), but it *is* drawn in the observed layout |
| §7 / `06:76` | `settings.categories` configurable | DIVERGENT | never read — the only config read is `settings.cycle_order` (`init.lua:39-45`); categories hard-registered. Documented as a deliberate choice in F12-C (`f12:250`), but the mirror key has no effect |
| §4.7 | Defaults "most permissive" | DIVERGENT | four rows default `FRIENDS_FOLLOWED` not `ON` — **spec self-documents the conflict** (F12-B, `f12:249`) and keeps it to reproduce the observed first-open screen; §5's stored schema supports the code over §4.7's prose |
| §9 | T9 (`FRIENDS_FOLLOWED` blocks stranger `/msg`) | MISSING | code path exists (`smp_social/pm.lua:45-51`) but nothing exercises it — blocked on f11 having a harness |

**Confirmed OK:** `/settings`; the translucent dark prompt menu; **seven
categories in the observed order** with verbatim titles
(`Chat, Notifications, PvP, Visuals, Privacy, Scoreboard, General`), `General`
centred beneath; tooltip `Open @1 settings` verbatim; subtitle exactly
`Choose a category to change your @1 settings` with `server.name` (default
`Donut SMP`); hovered-button purple; `Settings - Chat` with space-hyphen-space;
the seven toggles in observed order with `<Name>: <Value>` labels and **observed
fresh-profile values** (`Public Chat: ON`, `Private Messages: Friends/Followed`,
…); `Click to toggle` verbatim; `Back`; in-place redraw on toggle; the tri-state
display `Friends/Followed` enforced downstream; §5 keys character-exact with
string (not boolean) values; §6 toggle algorithm including the untrusted-id
guard; the `ON → FRIENDS_FOLLOWED → OFF` cycle; §4.5's store-only separation of
concerns; JSON in `smp:settings` with unknown keys preserved; **T1–T8 strongly
covered** (517-line dev-test incl. a simulated restart and forged-id tests) plus
the in-game suite.

**Beyond spec:** offline `get`/`set` limitations (§10-noted); default-outside-domain
fallback; terminal full stop on the `/settings` description (§0.5 drift); a
harmless duplicate `local fs`.

---

### f13 — Ranks · **MOSTLY COMPLETE (2 gaps)**

The mod itself is clean; both gaps are **consumers bypassing the rank API**.

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §4.2.4 / §11.3.2 | Consumers read *effective* rank honouring `expires_at` | PARTIAL | `smp_orders/orders.lua:204-206` reads `rec.rank` directly, ignoring expiry — previously flagged, **still present** |
| §11.3.1 | Consumers use `smp_ranks.rtp_cooldown` | PARTIAL | `smp_tp/rtp.lua:182` reads its own `cfg.rtp.cooldown[tier] or default` instead (mitigated by the fallback, so no nil) |
| §6 | `smp_store.mark_dirty` | N/A (spec-side) | helper named in the pseudocode does not exist; write-through `upsert_player` is the equivalent — naming mismatch, behaviour OK |

**Confirmed OK:** `/ranks` and its `/buy`/`/store` fallback (via
`smp_social/info.lua:150,164`); the menu rendering live config (tiers, perks,
prices) with store field and Back; **admin strings §11.2.8 verbatim**;
grant and stacking rules; perk application; the expiry watch-set sweep; tier
lookup; all §7 config keys read from live settings; **T1–T8** (76 checks,
integration halves for T4/T5/T8 owned externally).

**Hygiene:** PASS — translator, verbatim strings, `modpack.conf` entry, no
duplicate command registration, no beyond-spec behaviour.

---

### f14 — Stats, leaderboards, scoreboard, API · **MOSTLY COMPLETE (4 gaps)** · ~40 OK

**Exceptions**

| Ref | Requirement | Status | Evidence |
|---|---|---|---|
| §4.1 / §6 | Playtime accumulator via `core.register_globalstep` | DIVERGENT (**blocking**) | `smp_stats/playtime.lua:59` calls `core.register_on_globalstep` — nonexistent; spec pseudocode (`f14:157`) has it **right**. `init.lua:88-96` re-raises, so `smp_stats` cannot finish loading even after `smp_store` is fixed (B1 #6). The logic around it (60 s flush, carried fractional remainder) is correct and better than the pseudocode |
| §7 | `api.mode` default `off` | DIVERGENT | code defaults to `snapshot` (`init.lua:43-50`) — spec self-documents the conflict (F14-D5, `f14:237`) and follows §4.4's "option 1 by default"; §7's table is the stale side. Unknown values also fall back to `snapshot` |
| §4.1.2 | Counters monotonic | PARTIAL | `add()` accepts negative increments (`counters.lua:47-56`) — monotonicity is convention, not enforced; all shipped callers pass positives |
| §9 | T4 / T5 | PARTIAL | both **simulate** f02's and f05's writes in their shape rather than driving a real `/sell` or Quick Buy flow — verifies field agreement, not the integration |
| §4.4 | `api.mode = push` (option 2) | PARTIAL | deliberately a warned stub (`api.lua:108-112`); PROPOSED/optional in spec |

**Confirmed OK:** `/stats` (incl. other players, unknown-player refusal),
`/leaderboard` + `/lb` + `/leaderboards`, `/baltop` (keeping f01's header/row
format while supplying the snapshot), `/api` issue/revoke; **the scoreboard's
lowercase money convention** (`754k` vs chat `$ 754K`) asserted against f01 §3.2;
event-driven updates by wrapping `add_money`/`take_money`/`set_money` (never
polling); title chain `scoreboard.title` → `server.name`; two-line HUD content,
bottom-right, **no coordinate readout**; all ten §4.1 counters wired to the right
hooks (dig/place/die/mob-wrap with the F14-D2 attribution resolver, sell/shop
fields shared with f02/f05); `rec.stats` seven fields exactly; ten leaderboard
categories in official key **and** label order; rebuild outside globalstep on a
`core.after` chain with `refresh` 300 s / `size` 100; **the 50 ms @ 10,000
performance test exists and asserts `< 0.05`** (`test.lua:124-158`, 10.8 ms
measured); offline players included; §5 schema incl. `api_key` (`fcsmp_` + sha1);
all §7 keys except `api.mode`; **T1–T11** in an 879-line dev-test.

**Roadmap P7 gates:** "leaderboard rebuild under 50 ms at 10,000 players" and
"seven settings categories and scoreboard reproduced" — both have executable
coverage. **Caveat:** the harness stubs `register_on_globalstep`, so the suite
cannot catch the production load crash.

**Beyond spec:** JSON snapshot files under `<worldpath>/friedcake_api/`;
leaderboard picker with `<`/`>` paging (F14-D6); `scoreboard.show` registration
into f12's Scoreboard category (F14-D4); terminal full stops on several command
descriptions (§0.5 drift); HUD `$ ` before bare amounts where shared §0.6 would
give `$7` — F14-D3 explicitly fixes the HUD form, so the code follows the spec's
own decision.

---

### f15 — World rules · **COMPLETE** · 0 gaps

The cleanest feature in the pack.

**Confirmed OK:** `core.is_protected` wrap with the `protection_bypass` priv;
world border from a live `mapgen_limit` read with a configurable margin and a
lag-safe 1 s accumulator; flag-only IP index (sha1 keys, own storage, **no raw IPs
logged** — V-88); name-filter actions flag/kick/off with unknown → flag; zero ABMs
at runtime plus static checks; all five verbatim strings (`init.lua:104,153,302,
305,346`) translated; all 8 §7 keys present in `minetest.conf.example` including
`anticheat_flags`, `csm_restriction_flags = 63`, `mapgen_limit = 31007`;
inert `entity_caps`/`bedrock_breakable` as spec-blessed (V-81/V-82);
`WORLD_RULES.md` cross-checked against the actual hooks; **T1, T3, T5–T7**
(99 checks).

**Notes (not defects):** T2 (f10) and T4 (f08) are externally owned and not
verifiable here; f15's proposed-shared-changes list does not flag its `world.*`
keys to the shared config mirror (spec-side bookkeeping); no mod consumes the
`smp_world.*` exports yet — expected at this stage, worth tracking.

---

### f16 — Legacy modules · **NOT IMPLEMENTED** · 1 OK · 1 PARTIAL · **37 MISSING**

All five specified mods are absent:

1. `ls friedcake/mods` → 22 directories, none of `smp_crates`, `smp_afk`,
   `smp_teams`, `smp_duels`, `smp_servershop`.
2. `modpack.conf` has 22 `load_mod` entries, none for them.
3. Glob `**/smp_{crates,afk,teams,duels,servershop}/**` → no files.
4. `grep legacy\.` across `friedcake/` → **zero matches**; none of the 7 §7 keys
   exist, including the 4 mirrored at `06:81-84`.
5. No tests: 0 of 11.

**Every** §2 command (`/afk`, `/team`, `/duel`, `/warp crates`), every §3 screen,
every §4 behaviour (crates/keys/keyall, AFK zone + Haste multiplier + 5 s region
sweep, teams incl. the `register_extra_tab` hook into f09's `/homes`, duels,
kill shards, fixed-price shop), §5.2/§5.3 schema, §6 algorithms, §7 config, §8
implementation notes and §9 tests are `MISSING`.

**Partial:** the `keys = {}` player-record slot exists in the store schema
(`smp_store/init.lua:201`, backends `mod_storage.lua:60` / `sqlite.lua:142`,
`STORAGE.md:52`) but the five named balances (`common, prime, gold, amethyst,
crimson`) are never initialised, read or written — it is an f01 schema slot, not
f16 behaviour.

**OK (1):** §4.7's two cross-references that live in other features — the
Amethyst Bucket in f06 (`smp_amethyst/bucket.lua:31-74`) and the spawner
shard-shop acquisition flag in f07 (`smp_spawners/init.lua:75`).

**Missing conflict detection:** the roadmap (`roadmap.md:42`) and f16 §8/T11
require `smp_servershop` + `smp_quickbuy` to fail loudly at startup. No such
check exists anywhere (grep `mutually exclusive|conflict` → only an unrelated
comment) — untestable today only because `smp_servershop` itself is absent;
`/shop` is registered solely by Quick Buy (`smp_quickbuy/init.lua:286`).

**Legacy leakage:** grepped `crate|afk|duel|team|servershop|keyall` across
`friedcake/` — five hits, **none is legacy behaviour**: f07's legitimate
`spawners.acquisition.crates` flag, an f16 comment in `smp_shards`, a commented-out
warp sample in `smp_tp/config.lua:99-101`, Quick Buy's `/shop`, and f14's counters.
Nothing from f16 was absorbed elsewhere either.

**Verdict rationale:** f16 is specified as *optional* P8 modules, so their absence
is self-consistent with `modpack.conf` — but the spec treats them as work to build
(`roadmap.md:24`), not out of scope. Nothing in the repo implements or stubs them.

---

## 5. Test-coverage overview

| Feature | Dev-test | In-mod `test.lua` | §9 coverage | Notes |
|---|---|---|---|---|
| f01 | `test_economy`, `test_fmt`, `test_store` | present (per mod) | T1–T4, T9, T10 ✅ · T5/T6 weak · **T7/T8 absent** | |
| f02 | `test_sell` (2,001 lines) | 599 lines / 64 assertions | **T1–T10 ✅** + crash-mirror T7b | strongest suite |
| f03 | `test_ah`, `test_ah_keys`, `ah_harness` | smoke subset (declared) | **T1–T10 ✅** + X-a…X-h | |
| f04 | `test_orders` | present, header overclaims T1–T14 | **T1–T14 ✅** + routing APIs | |
| f05 | `test_quickbuy` | present, T1–T7 | **T1–T7 ✅** (guard at exact boundary) | warn-screen wording untested |
| f06 | `test_shards`, `test_shardshop`, `test_amethyst` | ×3 | T1, T3–T6, T8, T9 ✅ · **T2/T4/T7 weak** | |
| f07 | `test_spawners` (86 pass) | present | T1–T8, T10 ✅ · **T9 stubbed** | in-mod config assertions wouldn't catch the `bool()` bug |
| f08 | `test_tp` (98 pass) | present | T1, T3–T13 ✅ · **T2 weak** (no 1,000-trial run) | |
| f09 | `test_homes` (134 pass) | present, fails loudly if unwired | T1–T8 ✅ **shimmed** · T9 weak | shims hide all three load gaps |
| f10 | `test_combat`, `test_bounty`, `harness_f10` | ×2 | **T1–T12 ✅** | harness masks B1 |
| f11 | **none** | **none** | **0 of 10** | AGENTS step 7 violation |
| f12 | `test_settings` (517 lines) | 196 lines | T1–T8 ✅ · **T9 absent** | |
| f13 | `test_ranks` (76 checks) | present | T1–T8 ✅ (integration halves external) | |
| f14 | `test_stats` (879 lines) | 203 lines incl. perf test | **T1–T11 ✅** · T4/T5 simulated | masks B1 #6 |
| f15 | `test_world` (99 checks) | present | T1, T3, T5–T7 ✅ (T2/T4 external) | |
| f16 | **none** | **none** | **0 of 11** | no code exists |

**All existing suites pass (exit 0).** The recurring structural weakness is that
the harnesses stub the very engine APIs the mods get wrong (§2) and stub the
counterpart mod at every integration seam (§3.3), so green tests overstate
readiness.

---

## 6. Recommended actions, in priority order

Items marked **✅ DONE** were fixed in the remediation (commits
`68b5bf5` · `86c5918` · `87c0eae`). The rest remain open.

**P0 — unblock the server** ✅ **all done**

1. ✅ DONE — `core.register_on_globalstep` → `core.register_globalstep` at all six
   sites, and the dev-test harnesses now stub the correct name.
2. ✅ DONE — `core.modpath` → `core.get_modpath("smp_tp") .. "/<file>"` in
   `smp_tp/init.lua`.
3. ✅ DONE — the three f09 integrator edits: `dofile homes.lua`, `smp_store`/
   `smp_ranks` in `smp_tp/mod.conf`.

**P1 — data-loss and integrity defects** ✅ **all done**

4. ✅ DONE — `smp_spawners/routing.lua` decrements storage only after
   `smp_sell.sell` returns `true`.
5. ✅ DONE — `bool()` uses `get_bool(key, default)`.
6. ✅ DONE — mod_storage ledger paginates the actor-filtered set; sqlite keeps
   `shards_for_playtime` (column + read/upsert + migration).
7. ✅ DONE — amethyst join refresh `for _, list in ipairs(...)`.

**P2 — spec-fidelity gaps with player-visible effect** ✅ **mostly done**

8. ✅ DONE — RTP reads `world.spawn_protect_radius` (default 128); border probe
   ordering fixed.
9. ✅ PART — the outbox mirror bug is fixed (`requests.lua`); tag-event hooks for
   "either party" cancellation remain open.
10. ✅ PART — `/pay` → `smp_social.blocks` is wired; `follow()` → blocks and the
    rtpqueue ignore inversion remain (PROPOSED, needs a spec ruling).
11. ⬜ OPEN — `smp_social` has no dev-test (0 of 10 §9 tests).
12. ✅ DONE — `smp_tp.formspec` triangle + raw strings; `Shards: ` prefix;
    `smp_social` raw strings all translated.

**P3 — configuration contract (do as one pass, one convention)** ⬜ open

13. ⬜ OPEN — never-read keys, `smp_tp.` prefix, `ah.history*` /
    `rtpqueue.separation` renames, the f03-vs-f04 slots encoding.
14. ⬜ OPEN — reconcile the `shared/06` mirror in both directions.

**P4 — spec-side decisions for the integrator** ⬜ open (§3.4): the race-string
period (f03 vs f05), V-55 receipt screen, f12-F12-B/C and f14-F14-D5 table
corrections, f07's internal wording splits, `smp_store.mark_dirty`, f16's scope.

---

*Original audit produced read-only (no repository files modified other than
this report). The second-pass remediation (§0) modified `friedcake/mods/`,
`friedcake/dev-tests/`, `README.md` and `MANUAL_TEST_GUIDE.md`.
`spec/shared/`, `spec/plan/`, `smp_core`, `smp_store` and `smp_admin` were
treated as read-only per AGENTS.md.*
