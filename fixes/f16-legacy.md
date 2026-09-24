# Fix brief — f16 Legacy modules

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f16-legacy.md` |
| Target mod(s) | `smp_crates`, `smp_afk`, `smp_teams`, `smp_duels`, `smp_servershop` — **(none exist)** |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f16 |
| Verdict at audit | **NOT IMPLEMENTED** · 1 OK · 1 PARTIAL · **37 MISSING** · **0/11 tests** |
| Branch | `agent/f16-legacy-decide` |
| Depends on | **D8** (f16 scope call, `01-integrator-decisions.md`); **D7** (the four `legacy.*` mirror rows) |

---

## Mission

All five specified mods are entirely absent, and nothing implements or stubs
them. Evidence (re-verified):

- `ls friedcake/mods` → 22 directories, **none** of `smp_crates`, `smp_afk`,
  `smp_teams`, `smp_duels`, `smp_servershop`;
- `friedcake/modpack.conf` → 22 `load_mod` entries, **none** for the five;
- glob `**/smp_{crates,afk,teams,duels,servershop}/**` → no files;
- `grep legacy\.` across `friedcake/` → **zero matches** — none of the 7 §7
  keys exist anywhere, including the four mirrored at
  `spec/shared/06-config-reference.md:81-84`;
- tests: **0 of 11** §9 acceptance tests exist.

The spec treats these as P8 work (`spec/plan/roadmap.md:24`: "P8:
smp_rtpqueue (f08), smp_crates/smp_afk/smp_teams/smp_duels/smp_servershop
(f16)"), but the repo contains no skeleton. **This brief is a decision and
scoping document first, a build brief second — it refuses to start
implementation until D8 is ruled.** Its product is: the D8 ruling recorded, the
scope either descoped cleanly (mirror rows struck, V-61 closed, spec status
updated — all by the integrator) or split into five immediately actionable
sub-briefs with the one cross-mod safety item (the `/shop` startup conflict
check) specified first.

## Read this first (in order)

1. `AGENTS.md` — hard rules 1–8 (note rule 4: `smp_store`/`smp_admin` are not
   yours; note step 7: one `test.lua` **per mod**).
2. `spec/features/f16-legacy.md` — the whole file (§2 commands, §3 proposed
   screens, §4 behaviours, §5 schemas, §6 algorithms, §7 config, §8
   implementation notes, §9 T1–T11, §10 open questions V-83…V-87).
3. `spec/shared/02-architecture.md` (**§2.6 R7** at `:126` — node-menu
   re-checks), `04-ui-kit.md` (§4.3 prompt-menu grammar for the three
   placeholder screens), `05-command-reference.md`, `06-config-reference.md:81-84`
   (the four orphan `legacy.*` rows), `08-ui-strings.md` (READ ONLY).
4. `spec/plan/acceptance-tests.md:30` — f16's T1–T11 row is the merge gate
   (if option A is chosen); `spec/plan/roadmap.md:24,42`.
5. `SPEC-CONFORMANCE-REPORT.md` §4 f16 (lines 743–785).
6. Target: **no mod source exists** — instead read the integration seams you
   would touch: `smp_store/init.lua:201` (`keys = {}` slot),
   `smp_quickbuy/init.lua:286` (`/shop`), `smp_quickbuy/buy.lua:91` and
   `smp_stats/boards.lua:56` (`money_spent_on_shop`), `smp_shards/init.lua:41-57`
   (`shards.require_activity`), `smp_tp/config.lua:99-101` (commented warp
   sample), and `friedcake/dev-tests/test_settings.lua` as a harness model.

## Issues to fix

Decision row first — **nothing below it may be coded before F16-0 is ruled**:

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| F16-0 | f16 §1 / `roadmap.md:24` / D8 | Five specified mods entirely absent (37 gaps, 0/11 tests); scope undecided — build or descope | report §4 f16 rows 1–4 (all re-verified above); `shared/06:81-84` already advertises four `legacy.*` keys no code reads | **Do not write code until D8 is ruled.** Present the two options **verbatim** from `fixes/01-integrator-decisions.md` D8: **(A)** "schedule f16 at P8 as `roadmap.md:24` says." **(B)** "descoped — strike the `legacy.*` mirror rows, close V-61 (`require_activity` stays inert, documented), and mark `f16-legacy.md` deferred." The ruling lands in `fixes/01-integrator-decisions.md` (D8 row, chosen option filled in) and is applied **by the integrator** to `shared/06:81-84`, `spec/features/f16-legacy.md` (status line/§10), `spec/features/f06-shards.md` §10 V-61, and `spec/plan/roadmap.md` (integrator-owned). Your brief's deliverable: the decision request + this scoping backlog | **DECISION (D8)** |
| F16-1 | §8 / `roadmap.md:42` / T11 | `smp_servershop` + `smp_quickbuy` must **fail loudly at startup** — the only cross-mod safety item. No such check exists even in skeleton form | grep `mutually exclusive\|both claim` across `friedcake/` → **zero**; `conflict` → only an unrelated comment at `smp_spawners/types.lua:10` ("Blaze conflict: rods per S10"); `/shop` is registered solely by Quick Buy at `smp_quickbuy/init.lua:286` — the two **would collide** | **Specify first, even before any other build item**, if D8 = A: the check must be defined (who raises, at what load point, exact error text) before `smp_servershop` exists — it is the only place two live mods claim one command. If D8 = B: record that the check stays unbuilt and unneeded (only Quick Buy's `/shop` survives) | **DECISION (D8)** → then IN-SCOPE in `smp_servershop` (never edit `smp_quickbuy` — f05 is COMPLETE and not yours) |
| F16-2 | §7 / `shared/06:81-84` / D7 | Mirror advertises four `legacy.*` keys (`keyall_interval`, `afk_shards_per_min`, `team_max_members`, `kill_shards`) that **no code reads** | `grep legacy\.` across `friedcake/` → zero; mirror rows confirmed at `shared/06:81-84` | Option B: **integrator** strikes the four rows so `shared/06` stops advertising keys no code reads (your job is to specify that strike in the D8 request — you may not hand-edit the mirror). Option A: the five sub-briefs implement all 7 §7 keys and the rows become live | **ESCALATE → D7/D8 (integrator)** |
| F16-3 | f06 V-61 / §4.2 | `shards.require_activity` is inert pending f16's AFK tracking | `smp_shards/init.lua:43,57` reads the setting; `spec/features/f06-shards.md:175` V-61 open; the on_step sweep `smp_shards/init.lua:129-150` has **no exclusivity guard** — unavoidable while `smp_afk` is absent | Option B: V-61 closed as "`require_activity` stays inert, documented" **by the integrator** (f06 is another agent's file). Option A: `smp_afk` implements the zone and the exclusivity documented at `f16 §4.2.3` (no concurrent f06 playtime award) | **ESCALATE → D8** (f06 row 3 of `01-integrator-decisions.md`) |

**Legacy leakage check — an acceptance criterion under BOTH options**
(re-verified): grepping `crate|afk|duel|team|servershop|keyall` across
`friedcake/` finds five hits, **none is legacy behaviour**:

1. `smp_spawners/init.lua:76` (and its assert at `smp_spawners/test.lua:127`) —
   f07's legitimate `spawners.acquisition.crates` flag (report cites `:75` for
   the sibling `shard_shop` flag — both are f07, not f16);
2. `smp_shards/init.lua:41` — an f16 comment (`"f16's AFK tracking … does not exist yet"`);
3. `smp_tp/config.lua:99-101` — the commented-out warp sample
   (`-- crates = { … }`) — note **only a commented-out warp sample exists**;
4. Quick Buy's `/shop` (`smp_quickbuy/init.lua:286`);
5. f14's counters (`money_spent_on_shop`: `smp_quickbuy/buy.lua:91`,
   `smp_stats/boards.lua:56`, `dev-tests/test_stats.lua:538-542`).

Nothing from f16 was absorbed elsewhere either. Under option B this exact list
is the proof the descoped feature left no residue (plus striking
`shared/06:81-84`); under option A it is the baseline the five sub-briefs must
stay inside.

**Confirmed OK / PARTIAL — do not "fix":**

- **OK (1 row, two cross-references):** §4.7's two items that live in other
  features are fine — Amethyst Bucket in f06 (`smp_amethyst/bucket.lua:31-74`)
  and the spawner acquisition flag in f07 (`smp_spawners/init.lua:75`).
- **PARTIAL:** the `keys = {}` player-record slot exists —
  `smp_store/init.lua:201`, backends `smp_store/backends/mod_storage.lua:60`
  and `backends/sqlite.lua:142`, `STORAGE.md:52` — but the five named balances
  (`common, prime, gold, amethyst, crimson`, §5.1) are never initialised, read
  or written. It is an **f01 schema slot, not f16 behaviour**; option A's
  crates brief writes through it, option B leaves it alone.

---

## Build backlog (option A only — makes D8=A immediately actionable)

Write this up as-is; **split into five briefs** before any coding (see
Constraints). Ordering inside each row is the spec's own.

### §2 — Commands (all MISSING)

| Item | Evidence / notes |
|---|---|
| `/afk` | teleport to the AFK zone |
| `/team` + subcommands (`create`, `disband`, `invite`, `join`, `leave`, `kick`, `sethome`, `home`, `chat`) | §4.3 |
| `/duel <player>`, `/duel draw <player>` | §4.4 |
| `/warp crates`, `/crates` | only a commented-out warp sample exists: `smp_tp/config.lua:99-101` |

### §3 — Observed UI (0 frames → layouts are PROPOSALS)

Three placeholder screens in the observed grammar (`shared/04-ui-kit.md`): the
**crate choice** prompt menu (crate-name title, seven item buttons,
listing-tooltip-shaped tooltips without a price line), the **team menu**
(`Team`, member list, permission toggles as tri-state rows per f12's toggle
grammar), and the **fixed-price shop** (`<Category> (Page N)` container menu,
category tabs, item slots, `How many?` numeric prompt). Screenshots SS-22/SS-30
referenced in the spec are historical images, not frames.

### §4.1 — Crates (`smp_crates`)

Five crates (Common/Prime/Gold/Amethyst/Crimson) each opened with a **matching**
key; keys are **account balances, not items** (§5.1 schema), obtained from the
hourly `keyall` and from the store; `keyall` grants every online player
`legacy.keyall_keys` every `legacy.keyall_interval` (3,600 s); each opening
presents **exactly seven rewards from which the player chooses one**
(deterministic, no randomness); **R7 node-menu rules** (`shared/02:126`):
re-check node, key balance and distance on **every** action — including inside
`smp_crates.open` and `.choose` (§6 algorithms).

### §4.2 — AFK zone (`smp_afk`)

`/afk` teleports to a configured box region checked every 5 s;
`legacy.afk_shards_per_min` = 1 shard per full minute inside, nothing outside;
Donut+/Media earn anywhere; Shard Potion of Haste ×4; **exclusivity with f06's
600 s playtime award** — note `smp_shards/init.lua:129-150` currently has **no
exclusivity guard**, unavoidable while `smp_afk` is absent (F16-3); also
document `shards.interval` disabling to avoid double-paying (`f16 §4.2.3`).

### §4.3 — Teams (`smp_teams`)

Full subcommand set; **50-member cap** (`legacy.team_max_members`) with join
refusal over the cap; **team home as the leftmost `/homes` slot** via
`register_extra_tab` — grep `register_extra_tab` across `friedcake/` and
`spec/` finds it **only in `f16-legacy.md:214`** (the `f09` hook f16 says f09
"SHOULD expose" does **not** exist anywhere — propose it to f09, never fork
`f09`); team chat toggles hide public chat and deliver to members only;
permissions table (invite/kick/home/sethome/chat, creator holds all);
friendly-fire toggle integrating with `smp_combat.pvp_allowed`
(`smp_combat/attribution.lua:217`) — no combat tags between teammates.

### §4.4 — Duels (`smp_duels`)

Direct challenge + queue at the spawn duel building (random matches show
opponent name and win percentile); `/duel draw`; matchmaking by **win rate and
gear tier** (diamond never matched against netherite); players fight with
**own gear**; pre-built arenas far from the playable area, **schematic
snapshot/restore** (`core.place_schematic`) after each match; teleport through
f08 with warm-up skipped; `legacy.duels_keep_inventory` (default true).

### §4.5 — Kill shards (lives in `smp_afk`)

10 shards per direct kill (`legacy.kill_shards`) hooking f10's kill credit
(`smp_combat` kill-attribution path), with anti-farming **inside `smp_afk`**:
no reward for the same killer–victim pair within one hour, victims with <30 min
playtime, or same-IP accounts. **No kill-shard code exists in `smp_combat` or
anywhere** (grep `kill_shards|keyall|shop_prices|duels_keep|team_max|afk_shards`
across `friedcake/` → **zero** matches).

### §4.6 — Fixed-price server shop (`smp_servershop`)

Buy-only, configured by category and price (`legacy.shop_prices`, End/Nether/
Gear/Food categories, quantity selector — CLONE [C5]); counts towards
`money_spent_on_shop` — the counter exists (`smp_quickbuy/buy.lua:91`,
`smp_stats/boards.lua:56`) but **nothing feeds it from a legacy shop**;
**`/shop` is currently registered by Quick Buy (`smp_quickbuy/init.lua:286`) —
the two would collide, which is exactly why T11 exists** (F16-1).

### §5 — Schemas (all MISSING)

`keys = { common, prime, gold, amethyst, crimson }` in the player record (the
empty `keys = {}` slot at `smp_store/init.lua:201` is f01's, never read/written
for these five balances); the team record (§5.2: name/owner/created/members
permissions/home/pvp) as an `smp_store` table; the crate definition (§5.3: id,
title, **exactly seven** rewards with enchantments).

### §6 — Algorithms (all MISSING)

`smp_crates.open` and `smp_crates.choose` exactly as pseudocode'd — distance
re-check (R7), key re-validation, one-key spend, `give_or_drop`,
`smp_store.ledger("admin", "crate", …)` — note no yields between the
validation and the mutation (`shared/02 §2.3`).

### §7 — Config (all 7 keys MISSING)

`legacy.keyall_interval` (3,600 s), `legacy.keyall_keys` (`{common = 1}`),
`legacy.afk_shards_per_min` (1), `legacy.team_max_members` (50),
`legacy.kill_shards` (10), `legacy.duels_keep_inventory` (true),
`legacy.shop_prices` (`{}`) — four of them already mirrored at
`shared/06:81-84`, the other three absent from the mirror (all seven flow
through D7).

### §8 — Implementation notes (all MISSING)

Crate nodes unbreakable (`groups = {unbreakable = 1}`) with `on_rightclick`;
the 7-choice prompt of `item_image_button[]` with tooltips (`shared/04 §4.3`);
duels schematic snapshot/restore; `register_extra_tab` team-home hook (propose
to f09); and **the `smp_servershop`/`smp_quickbuy` mutual-exclusion
fail-loudly-at-startup check** — grep finds only the unrelated
`smp_spawners/types.lua:10` comment, so the detection does not exist even in
skeleton form, yet `roadmap.md:42` requires it for P8 (F16-1).

### §9 — Tests (0 of 11 exist)

T1 crate refusal/seven choices; T2 key spend + enchanted reward; T3 keyall
incl. one-second-before-join player; T4 AFK 1/min + **no** concurrency with the
f06 award; T5 team cap + permission gating; T6 leftmost `/homes` team slot;
T7 team chat isolation; T8 friendly-fire/tag integration with f10; T9 arena
restore; T10 same-IP anti-farming pays nothing; T11 startup conflict fails
loudly.

## Acceptance criteria

**If D8 = B (descoped) — this brief's own outcome:**

1. D8 ruling recorded in `fixes/01-integrator-decisions.md`, dated, option
   chosen.
2. The integrator (not you) strikes the four `legacy.*` rows at
   `shared/06:81-84` so the mirror stops advertising keys no code reads; your
   D8 request names this strike explicitly (F16-2).
3. The integrator updates `spec/features/f16-legacy.md`'s status line to
   deferred and closes f06 §10 **V-61** with "`shards.require_activity` stays
   inert, documented" (F16-3) — you write the request, they apply it.
4. **Legacy leakage check passes:** the greps above return only the five known
   non-legacy hits (listed in this document) — re-run and paste the output.

**If D8 = A (build):**

1. D8 ruling recorded; five sub-briefs written (one per mod), each carrying
   its slice of §9, with **F16-1's startup conflict check specified first** —
   it is the only cross-mod safety item.
2. Leakage baseline (the five hits) recorded before any code lands, re-run
   after.
3. All 37 gaps assigned to exactly one sub-brief — none orphaned, none
   duplicated.

## Tests

- **D8 undecided or D = B:** no new executable tests — the evidence commands
  are this brief's gate; each must print what this document claims:

```sh
ls friedcake/mods                                                    # none of the five
grep -rn "legacy\." friedcake/                                       # zero matches
grep -rn "crate\|afk\|duel\|team\|servershop\|keyall" friedcake/ -i  # only the five known hits
grep -rn "mutually exclusive\|both claim" friedcake/                 # zero (types.lua:10 covers "conflict")
```

- **D8 = A:** per-sub-brief dev-tests (proposed mapping — confirm in each
  sub-brief), each must exit 0, plus the in-mod `test.lua` files:

```sh
luajit friedcake/dev-tests/test_crates.lua      # T1–T3
luajit friedcake/dev-tests/test_afk.lua         # T4, T10 (kill shards live in smp_afk)
luajit friedcake/dev-tests/test_teams.lua       # T5–T8
luajit friedcake/dev-tests/test_duels.lua       # T9
luajit friedcake/dev-tests/test_servershop.lua  # T11 (startup conflict check)
```

## Constraints

- **f16 is FIVE mods** and would be **five `test.lua` files** under AGENTS
  step 7 — one per mod directory. If option A is chosen, **split this into five
  briefs** (one per mod): "one agent per feature file" is per-*file*, so five
  agents would be editing `spec/features/f16-legacy.md` §10 simultaneously —
  coordinate every spec-side note **through `f16-legacy.md` §10 in this parent
  brief** (or serialise §10 edits) so the single spec file is not edited by
  five agents at once. Sub-briefs may edit only their own mod + their own §10
  entries.
- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — the
  `shared/06:81-84` strike, V-61 closure and `roadmap.md` changes are
  **integrator** actions requested via D8.
- No edits to `smp_core`, `smp_store`, `smp_admin` (AGENTS rule 4); no edits to
  another feature's mod — `smp_quickbuy` (f05, COMPLETE), `smp_shards` (f06),
  `smp_combat` (f10), `smp_tp` (f08/f09) and `smp_stats` (f14) are all
  propose-only seams; propose the f09 `register_extra_tab` hook in f16 §10, do
  not fork f09.
- Money is integer cents, displayed only through `smp_core.fmt_money`
  (`legacy.shop_prices` is cents; the shop and keyall never use floats).
- All player-facing strings through `core.get_translator` (rule 7) — including
  `S("You need a @1 key.", …)` from §6.
- No yields between validate and mutate in the crate open/choose and shop
  purchase paths (`shared/02 §2.3`).
- Verbatim UI strings character-exact; config keys must match `shared/06`
  (all seven via D7 — propose, never hand-edit); never downgrade an `OBSERVED`
  requirement (these are LEGACY/PROPOSED rows — mark any invention `PROPOSED`).
- Frame evidence is **0** — §3 layouts are proposals in the observed grammar;
  do not present them as observed.

## Out of scope

- Coding anything before D8 is ruled (F16-0 refuses the start).
- Re-litigating the two §4.7 OK cross-references (Amethyst Bucket → f06,
  spawner flag → f07) or the `keys = {}` PARTIAL slot (f01's schema).
- f08's `/rtpqueue` (the live-server duels equivalent) and f05's Quick Buy —
  both already implemented elsewhere.
- Any of the other `fixes/fNN-*.md` briefs' gaps.

## Definition of done

1. **D8 ruled and recorded** in `fixes/01-integrator-decisions.md` — this brief
   is not "done" as a build until that row is filled.
2. **If deferred (option B):** the four `legacy.*` mirror rows resolved via
   D7/D8 (strike requested, applied by the integrator); `f16-legacy.md` status
   line updated **by the integrator**; `shards.require_activity` inertness
   documented (V-61 closed) — each with the request or ruling referenced.
3. **If build (option A):** five sub-briefs written (each mapping its §2–§9
   slice, its mod, its `test.lua`) and the **startup mutual-exclusion check
   specified first** (F16-1) — the only cross-mod safety item.
4. Under both options: the legacy-leakage greps re-run and pasted into the
   branch description showing only the five known non-legacy hits.
5. `git checkout -b agent/f16-legacy-decide` from `main`; commit references
   `SPEC-CONFORMANCE-REPORT.md §4 f16` and `D8`; push the **branch**, never
   `main`. Issue ID → evidence mapping (F16-0/1/2/3 plus the backlog sections)
   in the branch description.
