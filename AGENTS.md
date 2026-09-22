# AGENTS.md — instructions for AI agents

This file is read by AI agents working in this repository. If you are a
human, you probably want `CONTRIBUTING.md` instead.

## Repository layout

| Path | What |
|---|---|
| `spec/` | Authoritative specification. Read this before you implement anything. |
| `spec/features/fNN-*.md` | Per-feature spec files. Owned by the agent working on that feature. |
| `spec/shared/` | Shared conventions, API mapping, UI grammar, command and config mirrors. Integrator-owned. Read but do not edit. |
| `spec/plan/` | Roadmap, open questions, acceptance tests. Integrator-owned. |
| `friedcake/` | The modpack. Drop into Mineclonia's `mods/` directory. |
| `friedcake/mods/` | One directory per feature mod (`smp_*`). |
| `friedcake/dev-tests/` | Standalone `luajit` smoke tests. No engine required. |
| `frames/`, `*.mp4`, `*.srt` | Source media. NOT in git; regenerate from the YouTube link if lost. |

## Engine source-of-truth (DO NOT trust stale SHA)

- **Mineclonia (latest):** `~/dev/mineclonia-git`
- **Luanti (updated):** `~/dev/luanti`

`spec/README.md` and `HANDOFF.md` carry a source-of-truth block at the top
that says the same. Anything pinned to a specific commit in the spec is
**stale**; verify against the local clones.

## How to claim a feature

1. Read `spec/features/fNN-*.md` for the feature you want.
2. Read `spec/shared/` end to end — it is short and it is the contract
   between mods.
3. Read `spec/plan/acceptance-tests.md` for your feature — those tests are
   the merge gate.
4. Branch: `git checkout -b agent/fNN-<short-name>` from `main`.
5. Implement under `friedcake/mods/smp_<feature>/`.
6. Add `load_mod = smp_<feature>` to `friedcake/modpack.conf` **below** the
   existing entries.
7. Add `friedcake/mods/smp_<feature>/test.lua`.
8. Verify locally: `luajit friedcake/dev-tests/test_<feature>.lua`.
9. Commit and push the branch. Do not push to `main`.

## Hard rules

1. **Do not edit `spec/shared/`.** Propose changes in your feature file
   under `## Proposed shared changes`. The integrator merges.
2. **Do not edit `spec/plan/`.** Propose changes in your feature file's
   open-questions section.
3. **Do not edit `spec/README.md`.** It's the integrator's overview.
4. **Do not edit `smp_core`, `smp_store`, or `smp_admin`** unless the
   integrator has explicitly asked for the change. Propose in your feature
   file.
5. **One agent per feature file.** If you start work on a file another
   agent is on, stop and notify the integrator.
6. **Money is integer cents.** Always `smp_core.fmt_money`. Storage is
   always cents. Floats are forbidden for money.
7. **All player-facing strings go through `core.get_translator`.**
8. **No yields between validate and mutate** in any economic operation
   (see `spec/shared/02-architecture.md §2.3`).

## Where to ask questions

If a spec is unclear or contradicts itself, do not silently rewrite the
OBSERVED parts. Add an entry to the open-questions table in
`spec/features/fNN-*.md §10`. The integrator and the next agent to pick up
the file will see it.

If the spec is silent on something and you have to invent, mark the new
behaviour `PROPOSED` in the file you touch and surface it in §10 of your
own feature file.
