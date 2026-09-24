# Requirements — rulings D1–D11 and their execution (2026-09-24)

| Field | Value |
|---|---|
| Source of authority | [`fixes/01-integrator-decisions.md`](01-integrator-decisions.md) § **Rulings — 2026-09-24** |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §3.1 (config contract), §3.4 (spec-side), §4 (ESCALATE items) |
| Status | **Rulings written; execution delegated** to the six prompts in [`fixes/prompts/`](prompts/) |
| Open items | OPEN-1 was ruled as **D12** (2026-09-24); remaining: GAP-1, NOTE-1 — see §5 |

This document is the master work breakdown: what each ruling requires, which
files change, who executes it, and in what order. The prompts are
self-contained and may be handed to agents verbatim; this file exists so the
integrator can audit the whole pack at a glance.

---

## 1. Execution units and sequencing

| Unit | Prompt | Branch | Wave | Owns (write) |
|---|---|---|---|---|
| P1 | [`prompts/p1-spec-rulings.md`](prompts/p1-spec-rulings.md) | `agent/rulings-spec-text` | **1** (parallel) | D1–D6 text edits in `f05`, `f02`, `f12`, `f14`, `f07`, `f13` + `smp_quickbuy/buy.lua:87` |
| P3 | [`prompts/p3-f16-descope.md`](prompts/p3-f16-descope.md) | `agent/rulings-f16-descope` | **1** (parallel) | D8 spec-side: `f16-legacy.md`, `f06` §10, `plan/*`, `spec/README.md`, `shared/02`, `shared/05` f16 mentions |
| P4 | [`prompts/p4-admin-apis.md`](prompts/p4-admin-apis.md) | `agent/rulings-admin-apis` | **1** (parallel) | D9+D10: `smp_admin/*`, `dev-tests/test_admin.lua`, `shared/05 §5.5` mute rows |
| P2 | [`prompts/p2-config-mirror.md`](prompts/p2-config-mirror.md) | `agent/rulings-config-mirror` | **2** (after P1+P3) | D7: `shared/06-config-reference.md`, all feature **§7 tables**, `dev-tests/test_config_mirror.lua` |
| P5 | [`prompts/p5-integration-harness.md`](prompts/p5-integration-harness.md) | `agent/rulings-integration-test` | **3** (after P2+P4, ∥ P6) | D11: `dev-tests/test_integration.lua`, seam-policy note in `plan/acceptance-tests.md` |
| P6 | [`prompts/p6-store-history.md`](prompts/p6-store-history.md) | `agent/rulings-store-history` | **3** (after P1, ∥ P5) | D12: `smp_store` history API + drivers, `dev-tests/test_store.lua`, `f02` §6:139/§11, `f03` §6 |

Base branch for every unit: the then-current tip of
**`agent/integrator-decisions`** (it carries `fixes/`, the rulings, and the 00
engine-API fixes). Push the unit's branch; never `main`.

**Why the waves:** P2's guard test compares feature §7 tables against the
mirror, so it must run after P1 has struck `settings.categories` (f12 §7) and
fixed `api.mode` (f14 §7), and after P3 has annotated f06 §7's
`require_activity`. P5's seam checklist includes `smp_admin.flag`/`is_muted`
(P4) and shares `plan/acceptance-tests.md` with P3. P6 edits `f02 §6`
(adjacent to P1's D2 line) so it must wait for P1 — but is file-disjoint from
P5, so both run in wave 3 in parallel.

**Conflict matrix (why wave 1 is safe in parallel):**

| File | Writer |
|---|---|
| `spec/features/f02, f05, f07, f12, f13, f14` | P1 only |
| `spec/features/f16-legacy.md`, `f06` §10 | P3 only |
| `spec/features/f06` §7, all other §7 tables | P2 only |
| `spec/shared/06-config-reference.md` | P2 only |
| `spec/shared/05-command-reference.md` | P3 = f16/legacy annotations outside §5.5; P4 = new `/mute`,`/unmute` rows inside §5.5 (line-disjoint) |
| `spec/plan/*` | P3 (wave 1), then P5 (wave 3) |
| `smp_admin/*` | P4 only |
| `smp_store/*` (code), `dev-tests/test_store.lua` | P6 only |
| `spec/features/f02-sell.md` §6:139 + §11, `f03-auction.md` §6 | P6 (P1 owns the rest of f02 §6 — different lines, sequential waves) |
| `fixes/*` | **already annotated by the integrator — no prompt edits `fixes/`** |

**After P1–P5:** the feature briefs (`f01`, `f02`, `f03`, `f04`, `f06`, `f07`,
`f11`, `f12`, `f13`, `f14`) are unblocked and run per the order in
[`fixes/README.md`](README.md) — they are already self-contained prompts.
`f16` is cancelled. **Caveat:** `fixes/f08-teleport.md`, `f09-homes.md`,
`f10-combat.md` are indexed but do not exist (14 unassigned gaps, see
[`STATUS.md`](STATUS.md)) — they must be written before those features get fix
agents.

---

## 2. Ruling → requirement (exact sites)

### D1 = A — race string loses its period
- `spec/features/f05-quickbuy.md:194`: `` `This item was already bought.` `` → drop the terminal period inside the backticks.
- `friedcake/mods/smp_quickbuy/buy.lua:87`: `S("This item was already bought.")` → `S("This item was already bought")`. Check for `.tr` files referencing the old msgid (there should be none).
- Untouched (already correct): `shared/08:148`, `f03:194/273/331`, `f01:65`, `smp_ah/init.lua:169`, `dev-tests/test_ah.lua:435,649`.

### D2 = A — chat receipt is the design
- `f02-sell.md:140` in §6 pseudocode: replace `receipt:show(player)` with the **real** chat-emitting call — grep `smp_sell/receipt.lua:164-214` for the function name and cite `file:line` in a comment.
- `f02-sell.md:186` V-55: close — "ruled D2, 2026-09-24: the chat receipt is the design; no formspec receipt."
- No code change (code already emits chat lines). V-94 / `append_sell_history` stays open (OPEN-1).

### D3 = A — f12 defaults and categories
- `f12-settings.md:140-141` §4.7 item 7: rewrite to — the four chat keys (`chat.private_messages`, `chat.death_messages`, `chat.advancements`, `chat.join_leave`) default `FRIENDS_FOLLOWED` (reproduces the first-open screen [F0242], §0.5 fidelity); all other settings default to their most permissive value. Drop the blanket "most permissive" claim.
- `f12-settings.md:~178` §5.1 `smp_settings.register("chat.private_messages", …)` sample: `default` field must show `FRIENDS_FOLLOWED`, matching §5's schema (`:152-157`) and the implementation.
- `f12-settings.md:205` §7: strike the `settings.categories` row. Preserve the OBSERVED [F0237] fact in §4 prose (verify it is there; move it if the row was its only home).
- Annotate F12-B (`:249`), F12-C (`:250`), `:302` as decided 2026-09-24.
- Mirror half → P2: strike `06:76`.

### D4 = §7 corrected to snapshot
- `f14-stats.md:187`: default cell `off` → `snapshot`; keep `(`off`, `snapshot`, `push`)`.
- Annotate F14-D5 (`:237`) and the §10 line (`:257`) resolved. Code untouched.

### D5 = spec text follows the renderer
- `f07-spawners.md:34`: `Page 1/5` → `Page 1 of 5`.
- `f07-spawners.md:129`: ``Header `<Type> Spawner ×n` `` → ``Header `<Type> Spawner x<n>` `` (V-01's spelling; code renders `x128`).
- Keep `×` at `:33` (grid `5 × 9`) and `:76,99,102` (formulas) — not UI strings. V-01 (`:262`) and §5 (`:292`) already conform.

### D6 = upsert_player, mark_dirty struck
- `f13-ranks.md:114`: `smp_store.mark_dirty("players", name)` → `smp_store.api.upsert_player(rec)` with the `grant.lua:38` comment style.
- Grep `mark_dirty` across `spec/` — zero hits must remain.

### D7 = A — config mirror, both directions
- **Add (declared in a feature §7, missing from `shared/06`)** — minimum set from the audit, defaults copied from the owning §7:
  `sell.base_prices` (f02:152), `orders.allow_self_delivery` (f04:336),
  `quickbuy.page_size` (f05 §7 / code default 45), `shards.transferable`
  (f06:135), `shardshop.offers` (f06:139), `settings.cycle_order` (f12 §7),
  `homes.delete_confirm` (f09:208), `combat.log_broadcast` (f10:192),
  `world.soft_border`, `world.border_margin`, `world.max_accounts_per_ip`,
  `world.staff_name_filter`, `world.staff_name_action`, `world.entity_caps`
  (f15:153-158).
- **Add (read by code, declared nowhere or missing)** — the bidirectional sweep
  is authoritative; known sites: `scoreboard.title` (`smp_stats/init.lua:57`),
  `stats.persist_interval`, `api.mode` (default **`snapshot`** after D4),
  `ledger.page_size` (`smp_economy/init.lua:35,47`), `economy.tab_complete`
  (`smp_economy/init.lua:253`), `store.*` prefix keys
  (`smp_store/init.lua:29`), `store.max_balance`, `quickbuy.max_entries`,
  `quickbuy.price_guard`, `amethyst.*`, `spawners.*`. Undeclared reads get a
  §7 row in the owning feature file (P2 is granted that edit).
- **Rename (D7=A: docs follow code)** — `06:50-68` (`tp.*`, `rtp.*`,
  `rtpqueue.*`, `tpa.*`, `homes.*`) and the matching `f08 §7:301-315` /
  `f09 §7:204-208` rows → the exact full names the code reads under the
  `smp_tp.` prefix (`smp_tp/config.lua:11`, `homes.lua:46` — grep the key
  tables; `rtpqueue.separation` becomes whatever split keys exist,
  `config.lua:110-111`). Keep every Status/Spec cell.
- **Slots encoding** — `06:17,24` documented tables neither mod reads
  literally. New convention: dotted scalar keys (`ah.slots.default`,
  `ah.slots.tier1`, … / `orders.slots.*`) as the primary spelling, with the
  underscore alias noted (f04 O3). Where code does not yet read the documented
  spelling (f04 alias work, f07 `spawners.C` compound reads → F07-8/9), the
  row is kept and the guard records it under `DECLARED_ONLY` keyed to its
  brief — code changes belong to those briefs, never to P2.
- **Ambiguities resolved** — `store.max_balance` gets a row (Spec: shared
  §2.2) cross-noted against `economy.max_balance` (f01, E-18 is f01's);
  `ah.history` keeps its row with `pending:f03` (f03 brief A6 owns the seam).
- **Strike** — `settings.categories` (`06:76`, D3) and the four `legacy.*`
  rows (`06:81-84`, D8), each left with a one-line comment recording the
  strike + date so history stays traceable.
- **Guard** — new `friedcake/dev-tests/test_config_mirror.lua` (see the prompt
  for the full three-set spec: READ / DECLARED / MIRROR, prefix-pattern table,
  foreign-namespace allowlist, `DECLARED_ONLY` drain list, exit non-zero on
  any unexplained row in either direction).

### D8 = descoped permanently
- Strike `legacy.*` from `shared/06` → P2. Everything else → P3:
  `spec/features/f16-legacy.md` §1 banner + status → **DESCOPED — will never
  be built (2026-09-24)**; `f06-shards.md:175` V-61 closed ("f16 descoped;
  `shards.require_activity` stays read, default false, documented inert" —
  P2 annotates the f06 §7 row `:134` accordingly); `plan/roadmap.md:24,42`
  drop the five legacy mods but keep `smp_rtpqueue` (f08) and f14 `/api`
  (adjust the P8 acceptance cell: the `smp_servershop`+`smp_quickbuy` conflict
  check no longer applies); `plan/acceptance-tests.md:30` f16 row struck,
  X1 (`:40`) "crate choice" removed/annotated; then grep `f16|legacy|crate|
  /shop|duel|teams` through `plan/`, `spec/README.md`, `shared/02`,
  `shared/05` and annotate every in-scope presentation as descoped —
  historical `[S…]` citations stay as-is; other feature files
  (`f01,f08,f13,f14,f15`): annotate only text that states f16 behaviour as
  future work.
- `fixes/f16-legacy.md` CANCELLED + README index updated → done by this brief
  (brief 01's own acceptance criteria), not by P3.

### D9 = A — `smp_admin.flag(kind, detail)`
- Persisted ring buffer in `smp_admin` mod storage (cap e.g. 500, FIFO),
  `core.log("warning", …)`, and a translated chat notice to every online
  player holding `smp_admin` or `smp_moderator`. Returns the entry id.
- Tests in `dev-tests/test_admin.lua` + new in-mod `smp_admin/test.lua`
  (pattern: `smp_ranks/test.lua`). No `modpack.conf` change — `smp_admin` is
  already `load_mod = 1` (`modpack.conf:11`).
- `f01 §4.2.5` unchanged; wiring at `smp_economy/init.lua:234-236` is the f01
  brief's consumer row.

### D10 = A — mute producer
- `smp_admin.mute(name, seconds)` (nil/0 = permanent), `unmute(name)`,
  `is_muted(name)` → boolean (+ remaining seconds). Mod-storage backed, works
  for offline names, lazy expiry, survives restart.
- `/mute <player> [duration]` / `/unmute <player>`: duration in seconds,
  omitted = permanent; privs `{smp_moderator = true}` **or** `smp_admin` (Luanti
  has no priv hierarchy — check both). All strings through
  `core.get_translator`. Rows in `shared/05 §5.5` table.
- `f11 §4.1.3` unchanged; `smp_social/bridges.lua:97-104` starts returning
  real answers; F11-5's honesty cleanup remains the f11 brief's.

### D11 = A — integration load-order harness
- `dev-tests/test_integration.lua`: strict `core` built from
  `engine_api_surface.txt` (recording no-op per name; `__index` miss → record
  and return `nil` so guarded accesses pass but unguarded calls fail loudly;
  fail on any miss outside the file's "deliberately absent" list), foreign
  namespaces limited to names declared in some `mod.conf` `depends`/
  `optional_depends` plus a builtin allowlist (vector, ItemStack, Settings,
  …) — anything else unknown = failure naming the referencing mod.
- Per-mod file execution order: determine from the engine clone
  (`~/dev/luanti`, per AGENTS.md) and cite `file:line` in the test header.
- Mod set + topological order from `mod.conf depends` × `modpack.conf`.
- Seam checklist after full load (names grep-verified by the agent):
  `smp_core.fmt_money`, `smp_economy.give`, `smp_ranks.order_limit`,
  `smp_ah.cheapest_for`, `smp_orders.best_open_order`,
  `smp_orders.fill_from_stack`, `smp_sell.sell`, `smp_social.blocks`,
  `smp_settings.get`, `smp_store.api.*`, `smp_admin.flag`, `smp_admin.is_muted`.
- Degraded pass: remove every mod that is nobody's hard dependency — the rest
  must still load (exercises the optional-dependency guards).
- Demonstrate (throwaway snippet, not committed) that the test fails on an
  unknown `core.*` call and on a missing seam.
- Add the seam-policy paragraph to `plan/acceptance-tests.md`.

### D12 = one generic history API (ruled 2026-09-24; was OPEN-1)
- New `smp_store.api.append_history(kind, name, entry) -> id`, mirroring the
  shape of the existing ledger helpers (`smp_store/ledger.lua` — read it and
  copy its API/driver/test conventions). Append-only, FIFO prune to a
  caller-supplied `cap` (default 100, matching `sell.history_size`); entries
  carry `t = os.time()`; any money inside an entry is integer cents.
- Extend **all three** drivers the same way (`backends/mod_storage.lua`,
  `backends/sqlite.lua`, `backends/postgres.lua`) — parity is the rule; if the
  harness cannot reach one, say so and mirror however the ledger is currently
  tested for it.
- `spec/features/f02-sell.md` §11: proposal amended to the ruled signature
  (`append_sell_history` → generic) and marked decided D12; §6 line 139
  `smp_store.append_sell_history(player, receipt)` → the generic call
  (P1 was instructed to leave :139 alone — P6 owns that line).
- `spec/features/f03-auction.md` §6: `append_history(kind, payload)` PROPOSED
  → ruled D12 final signature with an explicit `name` parameter.
- Tests: extend `friedcake/dev-tests/test_store.lua` — append returns id,
  cap/FIFO prune, per-kind and per-name isolation, offline name works, entry
  round-trip equals what was stored.
- **Not P6's:** wiring `smp_sell/history.lua` onto the API (closes V-94) and
  f03's history storage remain the f02/f03 briefs' consumer rows.

---

## 3. Cross-cutting requirements (every prompt repeats these)

1. Money is integer cents; display only through `smp_core.fmt_money`.
2. Every player-facing string via `core.get_translator`.
3. No yields between validate and mutate in any economic operation.
4. Never downgrade an OBSERVED requirement; renames/moves preserve Status+Spec.
5. Touch only the files your prompt lists; anything else → record an ESCALATE
   entry and stop.
6. Full dev suite green before you finish: every `friedcake/dev-tests/test_*.lua`
   exits 0 (baseline in [`STATUS.md`](STATUS.md)).
7. Branch `<unit-branch>` from `agent/integrator-decisions`; commit and push
   the branch, never `main`. Do not edit anything under `fixes/`.

## 4. Pack-level definition of done

- P1–P5 branches green and merged (or ready to merge) in wave order 1→2→3.
- `shared/06` passes `test_config_mirror.lua` with an empty `DECLARED_ONLY`
  drain list *except* entries keyed to briefs that have not run yet.
- `test_integration.lua` loads all 23 mods in dependency order with zero
  unknown `core.*` accesses and all seams present.
- The feature briefs run afterwards per `fixes/README.md`; f08/f09/f10 briefs
  still need to be authored (open gap — see STATUS.md).

## 5. Open items

| ID | Item | State |
|---|---|---|
| OPEN-1 → **D12** | f02 §11 / V-94 `append_sell_history` vs f03 §6 `append_history` | **Ruled 2026-09-24:** one generic `smp_store.api.append_history(kind, name, entry)` — executed by `p6-store-history.md`; f02/f03 no longer wait, they wire consumers |
| GAP-1 | `fixes/f08-teleport.md`, `f09-homes.md`, `f10-combat.md` indexed but missing (14 gaps) | Unassigned — must be authored before those features get fix agents |
| NOTE-1 | E-09 (f01): `run_smp_core_tests` called at `smp_economy/init.lua:473`, declared `:489` | f01 brief's scope — verify there |
