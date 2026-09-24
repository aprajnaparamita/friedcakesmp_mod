# Fix brief — f06 Shards, shard shop, amethyst items

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f06-shards.md` |
| Target mod(s) | `smp_shards`, `smp_shardshop`, `smp_amethyst` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f06 |
| Verdict at audit | MOSTLY COMPLETE (5 gaps) · 30 OK · T1/T3–T6/T8/T9 strong; T2/T4/T7 weak |
| Branch | `agent/f06-shard-fixes` |
| Depends on | `00-P0-blockers.md` **B1-4, B1-5** + B4 shims (load blocker — the pack does not boot until it lands); `01-integrator-decisions.md` **D8** (f16 scope / V-61), **D7** (config mirror) — **ruled 2026-09-24: D8 = descoped permanently (f16 never built; V-61 closed by P3 — F06-3 is pre-applied, verify and close; F06-4 loudness warning is still yours), D7 = A (mirror + f06 §7 `require_activity` annotation by P2)** |

---

## Mission

Three mods, five audited gaps plus hygiene. One is a real **defect**: the
join-time amethyst description refresh loops over numeric indices, so it never
touches a single inventory list — items show stale/expired descriptions until
the 300 s sweep happens to run. The other four are configuration-contract
failures (a declared key never read, a declared key read but inert, a named key
never read, three tests that claim more than they assert) plus i18n/dependency
hygiene. "Fixed" means: the join refresh works, every key f07 §7-style contract
in f06 §7 either actually does something or says loudly that it does not, the
weak tests assert what their names claim — and everything currently byte-exact
stays byte-exact. Consequence of failure: operators tune keys that silently do
nothing, and the shard/amethyst behaviour the audit verified can regress
untouched.

## Read this first (in order)

1. `AGENTS.md` — hard rules 1–8.
2. `spec/features/f06-shards.md` — end to end: §4.3 (82–101, join refresh
   "on use and on join"), §4.2 (52–80, "explicit in configuration"),
   §7 (129–139), §9 (152–164), §10 (166–175, V-61), `## Proposed shared
   changes` (177–244).
3. `spec/shared/02-architecture.md` (§2.1 dependency table, line 23 —
   `smp_amethyst` ↔ `mcl_potions`), `04-ui-kit.md`, `05-command-reference.md`,
   `06-config-reference.md` (lines 31–35: only `shards.interval`,
   `shards.require_activity`, `amethyst.*` are mirrored), `08-ui-strings.md`
   (READ ONLY).
4. `spec/plan/acceptance-tests.md` — f06 row (T1–T9) is the merge gate.
5. `SPEC-CONFORMANCE-REPORT.md` §4 — f06 (lines 371–405), §2 B1 (sites 4–5),
   §3.3 weak tests.
6. Target sources: `friedcake/mods/smp_shards/init.lua`,
   `smp_shardshop/{init,catalogue,formspec}.lua`, `smp_amethyst/*.lua`;
   dev-tests `test_shards.lua`, `test_shardshop.lua`, `test_amethyst.lua`;
   in-mod `test.lua` in each mod.

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| F06-1 | f06 §4.3 ("description refreshes with remaining time on use **and on join**") | **Defect — join-time description refresh is a silent no-op.** `for list in ipairs({"main","offhand"})` binds `list` to the numeric index, so `inv:get_size(list)` queries list *1* (no such list → size 0) and the loop body never runs. Amethyst items keep stale descriptions until the 300 s sweep | `friedcake/mods/smp_amethyst/init.lua:179` (`for list in ipairs({ "main", "offhand" }) do` → `inv:get_size(list)`); join sweep at `:175` works and must stay | Iterate the **names**: `for _, list in ipairs({ "main", "offhand" }) do` (or equivalent). Add a join test: an amethyst item with `smp:expires_at` in `main` **and** one in `offhand` are both description-refreshed on join. Top priority — do this first | **IN-SCOPE** |
| F06-2 | f06 §7 (`shardshop.offers`, line 139) + §4.2 ("MUST be explicit in configuration") | Declared key never read: the catalogue is hard-coded in Lua (values do match the spec table), and the key is absent from `shared/06` too | `friedcake/mods/smp_shardshop/catalogue.lua:49` (`M.offers = {`); mirror absence verified by grep (D7 lists `shardshop.offers`) | Read `shardshop.offers` from settings with the current table as the default, so an operator can override enchantment sets without code changes; **keep the current values as defaults** (they match the spec). Propose the `shared/06` row via your feature file → **D7**. If the integrator prefers a different mechanism to satisfy "explicit in configuration", that is D7's call — the values themselves are right either way | **IN-SCOPE** (code) · **ESCALATE → D7** (mirror row) |
| F06-3 | f06 §7 (`shards.require_activity`, line 134) + V-61 | Key read but **inert** — no AFK tracking exists anywhere in the pack; depends on absent f16 | `friedcake/mods/smp_shards/init.lua:43` (load) and `:57` (`reload_cfg`); V-61 at `f06:175` | No behaviour change: AFK tracking is f16 scope. Record in §10 (V-61) that the key stays inert pending **D8** (Option A schedules f16; Option B descopes and documents the inertness) and stop | **ESCALATE → D8** (V-61) — **ruled 2026-09-24: descoped permanently; V-61 closed and f06 §7 annotated by `prompts/p3-f16-descope.md` + P2 — pre-applied, verify, don't redo** |
| F06-4 | f06 §7 (`shards.require_activity`) — loudness | The inert state is *silent*: an operator sets `= true` and gets no feedback that nothing changed | `friedcake/mods/smp_shards/init.lua:43,57` | At load **and** in `reload_cfg`, emit `core.log("warning", …)` when the key is true, stating that activity/AFK gating is unimplemented pending f16 (V-61/D8). Do **not** implement AFK tracking yourself | **IN-SCOPE** |
| F06-5 | f06 §4.3 (line 98: "restricted to `amethyst.shovel_nodes` (dirt-family nodes in group `shovely`)") | Named config key never read — only the `shovely` group check exists; the key is also absent from §7 and from `shared/06` | `friedcake/mods/smp_amethyst/shovel.lua:15-17` (`groups.shovely or 0) > 0`; grep of `spec/` finds `shovel_nodes` only at `f06:98` | Read the key (node-name list) as an **additional** restriction, with the existing `shovely`-group check as the default/fallback so current behaviour is unchanged when unset. Add the key to f06 §7 (your feature file) and propose the mirror row → **D7** | **IN-SCOPE** (code + §7) · **ESCALATE → D7** (mirror) |
| F06-6 | f06 §9 T2 / T4 / T7 | Weak tests that claim more than they assert: T2's "restart" never reloads the module (only drops an in-memory map); T4's comment claims a blacklisted neighbour but no blacklisted node is ever placed and `add_wear` is a no-op stub; T7's "can be sold and auctioned" half is untested (only the orders-blacklist half exists) | T2: `friedcake/dev-tests/test_shards.lua:244-275` (`connected = {}` at :252, no module reload). T4: `test_amethyst.lua:193` (`function IS:add_wear() end`), `:293-300` (only a **protected** neighbour is set up; comment says "protected and blacklisted"). T7: `test_amethyst.lua:262-263` asserts the 6-item blacklist only; no sell/auction acceptance case | (a) **T2:** re-execute the module's load path against the *persisted* record — simulate restart by reloading the module's state, not just clearing a local map — then assert no double-count (f06 §9 T2 wording). (b) **T4:** place an actually-blacklisted node (e.g. `mcl_mobspawners:spawner` or `mcl_core:barrier` per the dig-blacklist proposal) in the drill plane and assert it survives; make the `add_wear` stub **count calls** and assert wear applied exactly once per use. (c) **T7:** add the missing half — an amethyst item is accepted by the sell path and by an auction-listing path (counterparts may be stubbed per D11; the claim under test is f06's acceptance, not the peer's internals) | **IN-SCOPE** |
| F06-7 | i18n hygiene (report §4 f06 "Deviations"; shared §3.2 — all player strings via `core.get_translator`) | Hard-coded untranslated `Shards: ` prefix in the shop label | `friedcake/mods/smp_shardshop/formspec.lua:91` — `string.format("label[8.35,0.05,Shards: %s]", …)` with no `S()`/`F()` on the prefix | Wrap the prefix in the mod's translator, e.g. `S("Shards: @1", …)` (keep the rendered output character-identical: `Shards: <n>`); note the new string in the feature file's §10/§08 proposal as PROPOSED house-style | **IN-SCOPE** |
| F06-8 | `spec/shared/02-architecture.md:23` (§2.1) vs `smp_amethyst/mod.conf:4`; `mcl_armor` dependency | Two dependency-contract problems: (a) §2.1 lists `mcl_potions` as a **hard** dependency of `smp_amethyst` but `mod.conf:4` has it `optional_depends`, guarded at `haste.lua:29`; (b) `mcl_armor` is used with no matching `optional_depends` anywhere | `spec/shared/02-architecture.md:23`; `friedcake/mods/smp_amethyst/mod.conf:4` (`optional_depends = … mcl_potions …`); guard at `smp_amethyst/haste.lua:29-32`; `mcl_armor` use at `smp_shardshop/catalogue.lua:31`; `smp_shardshop/mod.conf:4` has no `mcl_armor` | (b) **IN-SCOPE:** add `mcl_armor` to `smp_shardshop/mod.conf` `optional_depends` (code-side only). (a) Pick one alignment and document it: recommended — keep the code optional (the guard is correct; without the mod, Haste simply cannot apply) and escalate the §2.1 wording to the integrator (`shared/02` is read-only for you) via f06 §10; the alternative (make it hard by moving `mcl_potions` to `depends`) is code-side but would drop the shop's gear/other features if `mcl_potions` is absent — state your choice and reason | `mcl_armor`: **IN-SCOPE** · `mcl_potions` spec-vs-code divergence: **ESCALATE (integrator, `shared/02`)** |
| F06-9 | f06 §7 / `shared/06` | Undeclared keys read by code: `shards.flush_interval`, `amethyst.haste_level`, `amethyst.haste_duration` (defaults already match spec behaviour: 30 s flush, level 2, 86 400 s) | `smp_shards/init.lua:47,59`; `smp_amethyst/init.lua:40-41`; all three absent from `spec/features/f06-shards.md` §7 and from `shared/06` | Declare them in f06 §7 with their defaults and status (`PROPOSED`), or remove the reads if you can argue they are redundant — declaring is the expected answer since defaults match spec behaviour. Propose the mirror rows → **D7**; do not hand-edit `shared/06` | **IN-SCOPE** (§7) · **ESCALATE → D7** (mirror) |
| F06-10 | — (test harness) | Dev-test suites stub `core.register_on_globalstep`, masking the load blocker in **your** mods | `test_shards.lua:179`, `test_amethyst.lua:228` (B1 sites: `smp_shards/init.lua:262`, `smp_amethyst/init.lua:193`) | Do **not** re-specify — fixed by `fixes/00-P0-blockers.md` B1-4/B1-5/B4-1. Re-run all three suites after that brief lands with the shims deleted | **DEPENDS-BLOCKER (B1-4, B1-5, B4-1)** |

**Status of everything else:** 30 audited rows are `OK` and must stay OK —
including the byte-exact award message, the 17-offer catalogue, all six amethyst
tools, and the five mirrored §7 keys.

## Preserve (do not regress)

- **Byte-exact** award message `You earned 1 Shard for playing the server`
  (capital `S`, **no** full stop) — `f06 §3/§6`, OBSERVED [F0037…].
- The 600 s award with the floor formula `floor(playtime / 600) −
  shards_for_playtime`, atomic persistence of `shards` +
  `shards_for_playtime`, one message per shard.
- Verbatim `Shard Shop` / `Click to view` tooltip on the orders-board entry
  point (rendered by `smp_orders`; `smp_shardshop.open(player)` must keep
  existing) — OBSERVED [F0179, F0182].
- The 17-offer catalogue and its prices (spec §4.2 table) — F06-2 changes
  only *where the table lives*, never the values.
- All six amethyst tools: pickaxe plane ⊥ dig face with protection/blacklist
  and **wear-once**, BFS felling capped at `amethyst.felling_limit` (512),
  shovel plane, Haste II 86 400 s with re-apply on join, 3×3×3 legacy bucket,
  sell axe with orders-first routing + protection + tag checks.
- Amethyst blacklisted from orders while staying **sellable/auctionable**.
- 1-day self-destruct timer stamped at purchase; join + 300 s sweep over
  `main`/`offhand` only; containers never scanned.
- The five mirrored §7 keys and their exact defaults (`shards.interval` 600,
  `shards.require_activity` false, `shards.transferable` false,
  `amethyst.lifetime` 86 400, `amethyst.felling_limit` 512,
  `amethyst.sweep_interval` 300 — mirror at `shared/06:31-35`).
- Buy flow: validate → debit → deliver, no yields, refund-on-impossible-
  failure; full-inventory refusal debits nothing (T8).

## Beyond spec — keep, but declare

- `/shardshop` standalone command (self-marked PROPOSED in the code).
- Refund-on-impossible-failure path in the buy flow.
- `reload_cfg` refresh path; the amount suffix parser (`/shardsadmin`).
- Catalogue fallback rendering when `mcl_armor` elements are unavailable.
- Playtime batching every 30 s (§6 is illustrative; semantics preserved) —
  declared via F06-9's `shards.flush_interval` declaration.
- `shards.transferable` is implemented but also missing from `shared/06`
  (D7 already lists it) — confirm your feature file proposes it.

## Acceptance criteria

1. **F06-1:** an amethyst item carried in `main` **and** in `offhand` gets its
   description refreshed on join (assert both in a dev-test); the join sweep
   at `init.lua:175` still runs; `smp_amethyst` still passes `test_amethyst.lua`.
2. **F06-2:** `shardshop.offers` is read; overriding it in settings changes
   the rendered offers; unset → defaults identical to the current/spec table
   (assert the 17 offers + prices unchanged in `test_shardshop.lua`).
3. **F06-3:** V-61 + D8 target recorded in §10; no AFK-tracking code added.
4. **F06-4:** setting `shards.require_activity = true` produces exactly one
   load-time (and one reload-time) warning naming V-61/D8; default false
   produces no warning.
5. **F06-5:** `amethyst.shovel_nodes = "custom:dirt"` shovels `custom:dirt`
   even without the `shovely` group **and** still shovels group nodes when the
   key is unset; key declared in f06 §7.
6. **F06-6:** T2 reloads the module across its "restart"; T4 places and
   asserts a surviving blacklisted neighbour **and** wear-once (stub counts);
   T7 asserts sell- and auction-acceptance of an amethyst item.
7. **F06-7:** `Shards: ` renders identically but arrives via `S()`; `rg -n
   '"Shards: ' smp_shardshop/formspec.lua` finds no untranslated literal
   outside the translator call.
8. **F06-8:** `smp_shardshop/mod.conf` declares `mcl_armor`;
   the `mcl_potions` choice (recommended: keep optional, amend §2.1 via
   escalation) is recorded in f06 §10 with a reason.
9. **F06-9:** the three keys appear in f06 §7 with defaults + status, and as
   proposals pointing at D7; `shared/06` untouched by you.
10. **F06-10:** all three suites exit 0 now and after `00` lands without the
    `register_on_globalstep` shims.
11. Every "Preserve" item above still has a passing assertion.

## Tests

Exact commands (all verified green on 2026-09-23; each must exit 0 when you
are done):

```sh
luajit friedcake/dev-tests/test_shards.lua
luajit friedcake/dev-tests/test_shardshop.lua
luajit friedcake/dev-tests/test_amethyst.lua
```

- New/changed cases map to F06-1 (join refresh, both lists), F06-2 (override
  + defaults), F06-4 (warning fires/doesn't), F06-5 (key override + group
  fallback), F06-6 (T2 reload, T4 blacklist + wear-once, T7 sell/auction
  halves).
- In-mod: update `smp_shards/test.lua`, `smp_shardshop/test.lua`,
  `smp_amethyst/test.lua`; `/smp test smp_shards|smp_shardshop|smp_amethyst`
  must pass.

## Constraints

- No edits to `spec/shared/`, `spec/plan/`, `spec/README.md` — propose via
  your own feature file (`## Proposed shared changes` / §10). D7 collects
  mirror rows; you never hand-edit `shared/06`.
- No edits to `smp_core`, `smp_store`, `smp_admin`.
- One agent per feature file: touch only `smp_shards`, `smp_shardshop`,
  `smp_amethyst` (and your own `spec/features/f06-shards.md`). Cross-mod seams
  (`smp_orders` entry point, `smp_combat` tag, `smp_sell` sell axe, f16) are
  propose-only.
- Money is integer cents; shard amounts are integers; display money only via
  `smp_core.fmt_money`.
- All player-facing strings via `core.get_translator`.
- No yields between validate and mutate (buy flow: validate → debit →
  deliver).
- Verbatim UI strings character-exact — the award message, `Shard Shop`,
  `Click to view` are frozen.
- Config keys must match `shared/06` — propose mirror changes (D7), never
  hand-edit.
- Never downgrade an `OBSERVED` requirement (the award string and the entry
  point are OBSERVED).
- If the spec is silent and you invent: mark `PROPOSED` in the feature file.

## Out of scope

- f16 / AFK tracking (D8's call) — F06-3 waits; F06-4 only makes the inert
  state loud.
- `shards.transferable` behaviour, leaderboard, `/shardsadmin` semantics —
  audited OK.
- Anything in `00-P0-blockers.md` (B1-4/B1-5/B4) — owned by that brief.
- Changes to `smp_orders`, `smp_combat`, `smp_sell`, `smp_economy`.
- Redesigning the shop layout (V-60) or enchantment sets (V-20) — only the
  *configurability* of the catalogue is in scope (F06-2).

## Definition of done

1. Every issue ID (F06-1…F06-10) is fixed or escalated with a written reason
   and its named target (D8 / D7 / integrator / `00`) — no silent drops.
2. The three dev-test commands above exit 0; all three in-mod `test.lua`
   files updated and green.
3. `git checkout -b agent/f06-shard-fixes` from `main`; commit referencing
   `SPEC-CONFORMANCE-REPORT.md §4 f06`; push the **branch, never `main`**.
4. Issue ID → evidence mapping in the commit/PR description (F06-1 →
   `smp_amethyst/init.lua:179`; F06-2 → `catalogue.lua:49`; F06-3/4 →
   `smp_shards/init.lua:43,57`; F06-5 → `shovel.lua:15-17`; F06-6 →
   `test_shards.lua:244-275`, `test_amethyst.lua:193,293-300`; F06-7 →
   `formspec.lua:91`; F06-8 → `mod.conf:4` + `shared/02:23`; F06-9 →
   `smp_shards/init.lua:47,59`, `smp_amethyst/init.lua:40-41`; F06-10 →
   `test_shards.lua:179`, `test_amethyst.lua:228`).
5. `fixes/README.md`'s f06 row flips to ✅ only when D8 and the D7 mirror rows
   have landed (otherwise annotate "pending D7/D8").
