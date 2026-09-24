# Fix brief — P0: engine API blockers (the pack does not boot)

| Field | Value |
|---|---|
| Feature spec | cross-cutting — disclosed at `spec/features/f10-combat.md:343-347` and `spec/features/f09-homes.md:272-276` |
| Target mod(s) | `smp_store`, `smp_ah`, `smp_orders`, `smp_shards`, `smp_amethyst`, `smp_stats`, `smp_tp` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §2 (B1–B3) |
| Verdict at audit | **blocker — mod loading aborts on a real server** |
| Branch | `agent/p0-engine-apis` |
| Issues | 3 classes, 15 call sites + 11 test harnesses |

---

## Mission

The modpack calls two engine functions that **do not exist in Luanti**, at load
time, in seven mods. A real server aborts during mod loading; every feature in
the pack is currently unreachable in production. The dev-test harnesses *define
fakes for both functions*, which is why all suites are green — the tests encode
the bugs instead of catching them. Fix the call sites, then make the harnesses
fail if this class of bug ever returns.

This is the only brief that is allowed to touch more than one mod: it is
explicitly integrator-scoped, and it must be completed **before any other fix
brief is verified in-game**.

## Read this first (in order)

1. `AGENTS.md` — hard rules.
2. `SPEC-CONFORMANCE-REPORT.md` §2 and §3.3.
3. `spec/features/f10-combat.md:340-350` (discloses B1 site #1) and
   `spec/features/f09-homes.md:260-309` (discloses B2/B3 — the three edits are
   assigned there to the integrator).
4. Engine truth: `~/dev/luanti/doc/lua_api.md:6576` (`core.register_globalstep`)
   and `:6092` (`core.get_modpath`). Grepping both engine clones for
   `register_on_globalstep` and `core.modpath` returns **zero matches** — there
   is no alias.

## Issues to fix

### B1 — `core.register_on_globalstep` does not exist → use `core.register_globalstep`

| ID | Site | Feature | Required fix | Severity |
|---|---|---|---|---|
| B1-1 | `friedcake/mods/smp_store/init.lua:351` | f01 | rename the call — **ESCALATE: `smp_store` is integrator-owned (AGENTS rule 4)**; do it only if this brief is executed by/for the integrator, otherwise record in §10 of `f01-economy-core.md` | blocker |
| B1-2 | `friedcake/mods/smp_ah/init.lua:1276` | f03 | rename the call | blocker |
| B1-3 | `friedcake/mods/smp_orders/init.lua:709` | f04 | rename the call | blocker |
| B1-4 | `friedcake/mods/smp_shards/init.lua:262` | f06 | rename the call | blocker |
| B1-5 | `friedcake/mods/smp_amethyst/init.lua:193` | f06 | rename the call | blocker |
| B1-6 | `friedcake/mods/smp_stats/playtime.lua:59` | f14 | rename the call — note `smp_stats` fails **even after** B1-1 is fixed; the spec pseudocode at `f14:157` already has it right | blocker |

Mechanical fix: `core.register_on_globalstep(fn)` → `core.register_globalstep(fn)`.
No callback semantics change (both take `dtime`).

### B2 — `core.modpath` does not exist → `smp_trap` load path

| ID | Site | Required fix | Severity |
|---|---|---|---|
| B2-1 | `friedcake/mods/smp_tp/init.lua:19,21,22,23,24,25,26,27` — eight `dofile(core.modpath("x.lua"))` calls | replace with `dofile(core.get_modpath("smp_tp") .. "/x.lua")`. **Note:** the engine function takes a *modname* and returns a directory, so a straight rename is not enough — the path join must change too. Files: `config.lua`, `bridge.lua`, `state.lua`, `warmup.lua`, `rtp.lua`, `requests.lua`, `formspec.lua`, `commands.lua` | blocker |

### B3 — f09 wiring (three integrator edits, `f09-homes.md:260-309`)

| ID | Site | Required fix | Severity |
|---|---|---|---|
| B3-1 | `smp_tp/init.lua` | add `dofile(core.get_modpath("smp_tp") .. "/homes.lua")` — `homes.lua` (842 lines) is never loaded, so `/homes`, `/home`, `/sethome`, `/delhome` do not exist in-game. `homes.lua:24` and `smp_tp/test_homes.lua:55` both print the waiting instruction | blocker for f09 |
| B3-2 | `smp_tp/mod.conf:3` | `depends = smp_core, mcl_worlds, mcl_spawn` → add `smp_store` and optional `smp_ranks`, exactly as `f09-homes.md:285-286` specifies | blocker for f09 |
| B3-3 | — | covered by B2-1; even with B3-1/B3-2 applied, the mod still cannot load until B2 lands | blocker |

### B4 — the harnesses hide all of the above

| ID | Sites | Required fix |
|---|---|---|
| B4-1 | `dev-tests/harness_f10.lua:316-320` (`core.register_on_globalstep = core.register_globalstep`), `dev-tests/test_stats.lua:259`, `test_economy.lua:207`, `test_shards.lua:179`, `test_spawners.lua:296`, `test_amethyst.lua:228`, `test_ranks.lua:254`, `test_orders.lua:303`, `test_sell.lua:685`, `test_homes.lua:278`, `ah_harness.lua:782` | delete the `register_on_globalstep` fakes — after B1 the mods call the real name, so the fakes are dead weight that would re-mask a regression. Keep fakes only where the harness genuinely stubs `core.*` for headless runs, but **never stub a name the engine does not have** |
| B4-2 | `dev-tests/test_tp.lua:196`, `dev-tests/test_homes.lua:355` (`core.modpath = …`) | delete after B2/B3-1; the shims currently let 98 + 134 tests pass over a mod that cannot load |
| B4-3 | new: `friedcake/dev-tests/test_engine_apis.lua` | **regression guard**: statically scan every `friedcake/mods/**/*.lua` for `register_on_globalstep` and `core.modpath` and fail with the file:line if either appears; additionally assert `core.register_globalstep` and `core.get_modpath` exist in the harness's `core` stub table. This is the test that would have caught all 15 sites |

## Acceptance criteria

1. `rg 'register_on_globalstep|core\.modpath' friedcake/mods` returns **zero**
   matches.
2. `rg 'register_on_globalstep|core\.modpath' friedcake/dev-tests` returns zero
   matches except assertions inside `test_engine_apis.lua` that *forbid* them.
3. `luajit friedcake/dev-tests/test_engine_apis.lua` exits 0 and fails when a
   forbidden symbol is reintroduced (prove it once by temporarily reverting
   one site).
4. `smp_tp/init.lua` loads `config, bridge, state, warmup, rtp, requests,
   formspec, commands, homes` (9 files) and `smp_tp/mod.conf` declares
   `smp_store` + optional `smp_ranks`.
5. Every previously-green suite still exits 0: `test_tp`, `test_homes`,
   `test_stats`, `test_economy`, `test_ah`, `test_orders`, `test_shards`,
   `test_amethyst`, `test_spawners`, `test_ranks`, `test_sell`, the f10 pair.
6. **In-game smoke (the point of the exercise):** the pack reaches
   `*** Server for game … started` with no `attempt to call a nil value` — if a
   real server cannot be run in this environment, state that explicitly and
   substitute a load-order dry run that `dofile`s every mod `init.lua` against a
   recorded `core` API surface, with the list of engine functions each mod calls.

## Constraints

- This brief is **integrator-scoped**: it deliberately spans feature mods that
  each have a different owning feature file. If you are *not* the integrator,
  split it: fix only the sites inside your own feature's mod, and record the
  rest in §10 of your feature file, pointing at this document.
- `smp_store` (B1-1) is integrator-owned under AGENTS rule 4 — escalate unless
  explicitly authorised.
- Do not change any behaviour while renaming: same callbacks, same order, same
  intervals. This is a pure API-name fix plus the f09 wiring.
- Do not edit `spec/shared/`, `spec/plan/`, `spec/README.md`. The disclosures in
  `f10`/`f09` stay as they are — they are correct.
- Money stays integer cents; strings stay behind `core.get_translator`; no new
  yields.

## Out of scope

- Every behavioural gap listed in the other `fixes/fNN-*.md` briefs.
- `combat.disable_elytra`, ender pearls, f16 — unrelated.
- Refactoring the harness architecture beyond deleting the two shim families
  and adding the guard test.

## Definition of done

1. Criteria 1–6 above pass, with command output pasted into the PR/branch
   description.
2. `git checkout -b agent/p0-engine-apis` from `main`; commit with a message
   referencing `SPEC-CONFORMANCE-REPORT.md §2`; push the **branch**, never
   `main`.
3. Update `fixes/README.md`'s row for `00` to ✅ and list any site you escalated
   rather than fixed.
4. Announce to the other agents: until this lands, no fix brief can be verified
   in-game, and the dev-test suites give false assurance.
