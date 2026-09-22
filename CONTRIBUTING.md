# Contributing to FriedcakeSMP / Donut SMP recreation

This repository is being built by parallel agents, one feature at a time,
following `spec/plan/roadmap.md`. This document is the contract between
agents: how to claim work, how to ship it, how to merge without stepping on
each other.

## Branching model

`main` is always shippable. Feature work happens on branches of the form:

```
agent/<feature>-<short-name>
```

| Example | Feature |
|---|---|
| `agent/f02-sell` | `/sell` |
| `agent/f03-auction` | Auction house |
| `agent/f08-teleport` | Teleport framework |

The integrator (a human or a designated agent) is the only one who merges
into `main`. Agents never push to `main` directly.

## One agent, one feature

Each `spec/features/fNN-*.md` is owned by exactly one agent at a time.
Agents working in parallel MUST edit different files.

`spec/shared/` is read-only to feature agents. Propose changes under a
`## Proposed shared changes` block at the bottom of your feature file; the
integrator merges them.

`spec/plan/`, `spec/README.md`, and the integrator-mirror tables
(`shared/05-command-reference.md`, `shared/06-config-reference.md`,
`shared/08-ui-strings.md`) are owned by the integrator. Agents MUST NOT edit
them directly — flag a change in your feature file's open-questions section.

## Mods under `friedcake/mods/`

Each `smp_*` mod lives in its own directory. Claiming a mod means:

1. Add `load_mod = smp_<feature>` to `friedcake/modpack.conf` below the
   existing entries.
2. Add your `mod.conf` declaring dependencies on earlier mods.
3. Implement under `friedcake/mods/smp_<feature>/`.
4. Add `friedcake/mods/smp_<feature>/test.lua` for unit tests; register them
   with `/smp test <feature>` if your feature has commands.

If you need to extend `smp_core`, `smp_store`, or `smp_admin`, **propose
the change to the integrator first**. They will either merge it or hand
back an alternative.

## Workflow

```
# 1. Stay up to date.
git checkout main
git pull --rebase   # if a remote exists; local-only setups skip this

# 2. Branch off your feature.
git checkout -b agent/f02-sell

# 3. Implement. Commit often; keep commits scoped.
git add friedcake/mods/smp_sell/
git commit -m "f02: shulker-aware sell container and history"

# 4. Push the branch. Without a remote, the integrator pulls it.
git push origin agent/f02-sell

# 5. Open a PR if a remote exists; otherwise notify the integrator.
```

## Commit messages

Use `<feature-id>: <imperative summary>` at the start of every commit.
Examples:

- `f01: add /eco set and /eco reset admin commands`
- `smp_store: SQLite backend schema and migrations`
- `spec: add f08-teleport and f09-homes`
- `tools: split VLM descriptions per frame into per-feature files`

Avoid "wip", "fix", "stuff", or any message a stranger couldn't act on.

## Merge conflicts

The most likely conflict points are:

- `friedcake/modpack.conf` — rebase alphabetically; if both agents add
  entries, the integrator sorts them.
- `spec/README.md` feature table — both agents add rows, integrator merges.
- `spec/shared/` — feature agents don't edit. If a conflict appears, an
  agent has overstepped; the integrator resolves.

If your feature spec depends on a shared change you proposed and the
integrator has not yet merged it, **wait**. Do not commit your feature on
top of an unmerged proposal.

## Acceptance tests

Every feature has an acceptance matrix in
`spec/plan/acceptance-tests.md`. The matrix is the merge gate: your
feature is done when its tests pass, not when its code exists.

Standalone smoke tests live under `friedcake/dev-tests/` and run with
`luajit dev-tests/test_*.lua`. Add yours there.

In-game tests run via `/smp test <feature>` once registered. Add a
`test.lua` per mod; the test loader finds it.

## Style

- Lua: 4-space indent, snake_case, `local function` declarations.
- No globals except `smp_<feature>` tables; mineclonia's `mcl_*` and the
  engine's `core`/`minetest` are fine.
- Strings: always `core.get_translator(...)` — never raw literals that
  might end up user-facing. Verbatim observed strings live under
  `spec/shared/08-ui-strings.md`.
- Money is integer cents. Use `smp_core.fmt_money`, never `tostring`.
