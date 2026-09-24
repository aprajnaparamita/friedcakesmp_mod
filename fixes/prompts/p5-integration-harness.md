# Agent prompt — P5: D11 — integration load-order harness

| Field | Value |
|---|---|
| Feature spec | no feature file — seam policy recorded in `spec/plan/acceptance-tests.md` (integrator-owned; delegated by this prompt for one paragraph) |
| Target | new `friedcake/dev-tests/test_integration.lua` |
| Audit source | `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D11 = Option A |
| Verdict at audit | high — no test ever loads two real mods together; that is exactly how B1/B4 survived |
| Branch | `agent/rulings-integration-test` (base: tip of `agent/integrator-decisions` **after P2 and P4 merged**) |
| Wave | 3 — run after P4 (seams include `smp_admin.*`) and P3 (shares `acceptance-tests.md`) |

## Mission

Every existing dev-test stubs its counterpart; nothing proves the real mods
load together, in dependency order, against the real engine API surface. D11=A
builds that one modpack-level headless test: dofile every enabled mod in
dependency order with a strict `core` backed by the recorded 542-name surface
`dev-tests/engine_api_surface.txt`, fail on any unknown `core.*` access, any
load error, or any missing cross-mod seam — and record the seam policy in the
plan layer. This is the regression harness for the whole B1/B4 bug class.

## Read this first (in order)

1. `AGENTS.md` — rules 1–8, and the **engine source-of-truth block**: use the
   local clones `~/dev/luanti` (engine) — never a stale SHA or memory for how
   mods are loaded.
2. `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D11 row.
3. `friedcake/dev-tests/test_engine_apis.lua` — the static guard you
   complement: it greps `core.*` names against the surface at *text* level;
   you catch what a static grep cannot (dynamic lookups, load-order nil
   errors, missing seams).
4. `friedcake/dev-tests/engine_api_surface.txt` — the recorded surface,
   including its "deliberately absent" section (e.g.
   `core.get_detached_inventory` — engine-absent, `and`-guarded in `smp_ah`/
   `smp_orders`, silently nil: guarded access must be tolerated, unguarded
   call must fail loudly).
5. `friedcake/modpack.conf` (`load_mod` list) and every
   `friedcake/mods/*/mod.conf` (`depends` / `optional_depends`).
6. `spec/plan/acceptance-tests.md` — intro and the X1–X10 table (your
   paragraph lands here).

## Requirements

**R1 — engine-faithful loading (verify, don't recall).**
- Open the engine clone and find how a mod's Lua files are discovered and in
  what order they execute (and in what order mods execute relative to each
  other given `depends`). Cite `file:line` of the engine source in your test
  header comment. Implement exactly that; if the engine sorts alphabetically,
  your harness sorts alphabetically.
- Mod set: every mod with `load_mod = true` in `modpack.conf` (23 today —
  derive, don't hardcode).
- Order: topological over `mod.conf depends` (hard deps only), matching the
  engine's rule; the harness must **fail** (not warn) if the graph has a cycle
  or a hard dep is missing from the set.

**R2 — strict `core` from the recorded surface.**
- Parse `dev-tests/engine_api_surface.txt` (skip comments/blank/"deliberately
  absent" sections). Build `core` so that:
  - every listed name resolves to a recording no-op (captures calls, returns
    `nil` — sufficient at load time);
  - `core.__index` for an unlisted name **records the miss** (name + call
    site if obtainable) and returns `nil` — so an *unguarded* use fails with
    a real error the pcall reports, while a *guarded* `core.x and core.x()`
    evaluates false without crashing;
  - after loading, any recorded miss **outside** the deliberately-absent list
    → test failure listing `<mod>: <core.name> not in engine_api_surface.txt`.
  - accesses to deliberately-absent names are tolerated but printed as a
    note (they are the known silent-nil case; `test_engine_apis.lua` owns
    their static story).
- Plus the non-`core` engine surface the mods legitimately touch at load:
  `core.settings` (`get`/`get_bool`/`get_np`/`get_string`/`set_*` — return
  `default`/`nil` so code takes its configured defaults), `get_translator`
  (identity function), `get_modpath` (real directory), `DIR_DELIM`,
  `get_worldpath`, `get_mod_storage` (table-backed fake, per-mod namespace),
  `write_json`/`parse_json` (just enough), `register_*` family (record into
  tables — chatcommands, privs, node/item defs — return nil), callback
  registrars (`register_on_*`, `register_globalstep`, …) record, never fire.

**R3 — foreign namespaces: strict, but scoped.**
- Provide stubs **only** for names that appear in some loaded mod's
  `depends`/`optional_depends` (`mcl_init`, `mcl_formspec`, `tt`, …) plus an
  explicit builtin allowlist in the test (`vector`, `ItemStack`, `Settings`,
  `VoxelArea`, `Profiler`, … — read the engine clone for the builtin list and
  cite it). Stub tables auto-stub their fields with recorders (a missing
  Mineclonia helper must not crash your harness; recording it is enough).
- Any **other** unknown global referenced during load → failure naming the
  mod: `unknown global '<name>' at load (mod: smp_x)`. This is the rule that
  stops `minetest.*` typos and forgotten deps from hiding.
- Never stub a `core.*` name the engine does not have (B4-1 anti-pattern).

**R4 — seam checklist (after a full clean load).**
Assert exists and is callable (verify each name by grep before asserting —
if the real name differs from this list, the grep wins and you report the
discrepancy):
`smp_core.fmt_money`, `smp_economy.give`, `smp_ranks.order_limit`,
`smp_ah.cheapest_for`, `smp_orders.best_open_order`,
`smp_orders.fill_from_stack`, `smp_sell.sell`, `smp_social.blocks`,
`smp_settings.get`, `smp_store.api.*` (spot-check `upsert_player`,
`take_money`, `add_money`, `ledger_for`), `smp_admin.flag`,
`smp_admin.is_muted` (P4), `smp_quickbuy`'s bridge targets (grep
`smp_quickbuy/bridges.lua`), `smp_spawners`' routing target (grep for the
f02 sell-all seam). Failure message names seam + expecting mod.

**R5 — degraded pass.**
Second run: exclude every mod that is **not** a hard dependency of any other
mod (compute from the `depends` graph). The remaining set must still load
clean with all seams that are still present — this exercises the
`optional_depends` guards (`smp_quickbuy` without `smp_ah`, `smp_orders`
without `smp_sell`, `smp_social` without `smp_admin`/`smp_settings`, …).
Optional-layer seams are asserted only in the full pass.

**R6 — prove it catches the bug class.**
Before finishing, run a throwaway snippet (do not commit it): feed the
loader a synthetic mod that calls `core.register_on_globalstep` (absent from
the surface) and one that references `smp_orders.nope` — confirm both produce
non-zero exit with the right message. Paste the two outputs in your reply.

**R7 — seam policy paragraph in `spec/plan/acceptance-tests.md`.**
- Add a short subsection (after the X1–X10 table or in the intro — pick the
  spot that reads best): cross-mod **seam existence** and **load order** are
  covered headlessly by `dev-tests/test_integration.lua` (D11, 2026-09-24),
  run with the rest of the suite at every phase boundary; the X1–X10 drills
  remain the in-game behavioural layer (stub-free seam *behaviour* still
  needs a live server). One paragraph, no table changes.

## Out of scope (hard)

- Fixing feature mods. If a real mod fails to load in dependency order, that
  is a **finding**: record it (mod, error, engine-cited cause) and report —
  fix it only if it is a load-order/nil-guard with zero behavioural change
  **and** in an integrator-owned mod (`smp_core`, `smp_store`, `smp_admin`).
  Anything else → ESCALATE to the owning brief.
- Static engine-name guarding (`test_engine_apis.lua`), other dev-tests,
  `spec/shared/06` (P2), `spec/features/**`, `fixes/**`, `smp_admin` edits
  (P4 — you consume its API, you don't change it).

## Tests

- `luajit friedcake/dev-tests/test_integration.lua` → exit 0; prints load
  order, seam table, miss count 0, degraded pass OK.
- Full suite green: every `friedcake/dev-tests/test_*.lua` exits 0 (your file
  joins the glob — it must not depend on execution order with the others).
- R6 negative demonstrations captured in your reply.

## Constraints

- Money integer cents; translator strings if you emit any user-visible text
  (prefer none — this is a test); no yields in anything you add; the harness
  may not require a world or a client.
- Files you may write: `friedcake/dev-tests/test_integration.lua`,
  `spec/plan/acceptance-tests.md` (one paragraph per R7 — P3 has already
  landed its f16 row edits there by wave order). Everything else → ESCALATE +
  stop.

## Definition of done

1. R1–R7 complete; test green; suite green; R6 outputs pasted in the reply.
2. Reply with: engine citation for file/mod order, final load order (topo
   list), seam checklist results, `DECLARED` findings if any mod failed to
   load (and whether you fixed or escalated each), and the exact paragraph
   added to `acceptance-tests.md`.
3. Commit with `D11` in the message; push `agent/rulings-integration-test`,
   never `main`.
