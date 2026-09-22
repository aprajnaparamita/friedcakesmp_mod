# FriedcakeSMP — Donut SMP recreation for Mineclonia

This repository contains two things:

| | What |
|---|---|
| **`spec/`** | The complete specification for re-implementing Donut SMP's player-facing features on top of Mineclonia (Luanti). 16 features (f01–f16), shared conventions, UI kit, command and config mirrors, source citations. |
| **`friedcake/`** | The modpack itself. Drop `friedcake/` into Mineclonia's `mods/` directory and you get `/bal`, `/pay`, `/baltop`, `/shards`, `/eco`, `/ledger`, `/smp` plus all the menu and storage plumbing that every other feature will sit on. |

The recreation is a **verbatim UI clone** of Donut SMP, drawn from 141
frames of the source tutorial video plus the public wiki. Mechanics
underneath the interface are clean-room Lua; nothing is copy-pasted.

## Engine source-of-truth (agents, read this first)

The local clones below are fresher than any commit SHA pinned in `spec/`:

- **Mineclonia (latest):** `~/dev/mineclonia-git` — clone of
  `mineclonia/mineclonia`, tracking upstream `main`.
- **Luanti (updated):** `~/dev/luanti` — local checkout, 5.17.0.

Do **not** treat "verified against GitHub mirror, commit `5bdce566`,
2026-09-21" in the original spec as current. That mirror lags.

## Status

| Spec | Mod | State |
|---|---|---|
| f01 economy | `smp_economy` | implemented; T1–T10 acceptance tests pass |
| shared §2.2 store | `smp_store` | implemented (mod_storage, sqlite, postgres stub) |
| shared formatter | `smp_core` | implemented |
| privileges | `smp_admin` | implemented (sm_admin, sm_moderator) |
| shared §2.5 items | `smp_items` | stub |
| f13 ranks | `smp_ranks` | stub |
| f02–f16 | — | not started; see `spec/plan/roadmap.md` |

## Repository workflow

Parallel agents work on `agent/<feature>` branches off `main`. The
integrator merges. See `CONTRIBUTING.md` for the contract.

The `tools/agent-flow.sh` wrapper automates the boring parts:

```sh
tools/agent-flow.sh start f02-sell   # cut a feature branch
tools/agent-flow.sh test             # run the smoke tests
tools/agent-flow.sh spec f02-sell    # page through the spec file
tools/agent-flow.sh check            # confirm we're not on main
```

For AI agents: read `AGENTS.md` first. It is the authoritative set of
rules for any agent working in this repository.

## Repository layout

```
.
├── AGENTS.md                 # AI-agent rules (read this first)
├── CONTRIBUTING.md           # human workflow + branching model
├── HANDOFF.md                # background: how the spec was produced
├── LICENSE.txt               # MIT (spec/scripts) + LGPL-2.1 (modpack)
├── README.md                 # this file
├── archive/                  # superseded v0.1 of the feature spec
├── build_*.py                # source pipeline (yt-dlp + VLM)
├── run_qwen_vl_describe.py   # client that drives the describer
├── setup_qwen_vl.sh          # provisioning script for the VLM box
├── spec/                     # the specification
│   ├── README.md
│   ├── features/f01–f16      # one .md per feature
│   ├── shared/00–08          # conventions, architecture, UI kit, etc.
│   └── plan/                 # roadmap, open questions, acceptance tests
├── friedcake/                # the modpack (drop into Mineclonia mods/)
│   ├── README.md
│   ├── modpack.conf          # load order
│   ├── mods/                 # one directory per smp_* mod
│   └── dev-tests/            # standalone luajit smoke tests
├── tools/
│   └── agent-flow.sh         # wrapper for parallel-agent workflow
└── topics.md, feature_index.*, frame_index.csv   # source-pipeline outputs
```

## Source media

The 1920×1080 source frames and the source MP4 are *not* in this
repository — they are regenerated from the YouTube link documented in
`HANDOFF.md`. Same for the `.srt` subtitles and the per-frame VLM
descriptions (those are in `friedcake/dev-tests/`'s upstream pipeline).

## Verification

Without spinning up Luanti:

```sh
luajit friedcake/dev-tests/test_fmt.lua      # formatter, parser, sessions
luajit friedcake/dev-tests/test_store.lua    # mod_storage backend contract
luajit friedcake/dev-tests/test_economy.lua  # /pay /bal /ledger /eco paths
```

or just:

```sh
tools/agent-flow.sh test
```

In-game (after install):

```
/smp test smp_core
/smp test smp_economy
```
