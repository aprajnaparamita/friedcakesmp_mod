# FriedcakeSMP — a Donut SMP recreation for Mineclonia

Play Donut SMP with the same interface — no cracked client, no subscription.

FriedcakeSMP is a **verbatim UI clone** of Donut SMP: menu titles, button
labels and server chat strings are reproduced character for character (the
rule is stated in `spec/shared/00-conventions.md` §0.5). The mechanics
underneath are clean-room Lua, written from 141 frames of a source tutorial
video and the public wiki. Nothing is copied from the original.

## Contents

- [Package contents](#package-contents)
- [Documentation](#documentation)
- [Status](#status)
- [Repository layout](#repository-layout)
- [Engine source of truth](#engine-source-of-truth)
- [Repository workflow](#repository-workflow)
- [Verification](#verification)
- [Source media](#source-media)
- [How this repository was built](#how-this-repository-was-built)
- [Licence](#licence)

## Package contents

| Path | Contents |
|---|---|
| `spec/` | The specification: 16 feature files (`spec/features/f01-economy-core.md` … `f16-legacy.md`), the shared contract (`spec/shared/00-conventions.md` … `08-ui-strings.md`) and the plan (`spec/plan/` — roadmap, open questions, acceptance tests). |
| `friedcake/` | The modpack — 22 `smp_*` mods covering the economy, auction house, orders, Quick Buy, selling, spawners, shards, teleports, homes, combat, bounties, settings, social, statistics and world rules. |

Install it by dropping `friedcake/mods/` (the modpack) into Mineclonia's
`mods/` directory as `friedcake`, or symlinking it into a world's `worldmods/`
directory. Installation, storage backends and load order are documented in
[`friedcake/README.md`](friedcake/README.md).

## Documentation

| Document | Purpose |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Authoritative rules for AI agents working in this repository. Read this first. |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Human workflow: branching model, feature ownership, merge contract. |
| [`HANDOFF.md`](HANDOFF.md) | Background on how the specification was produced, including the source-video link. |
| [`INTEGRATION.md`](INTEGRATION.md) | Integrator's notes from the first merge pass: what merged, what was fixed, what remains. |
| [`INTEGRATION-museum-import-kit.md`](INTEGRATION-museum-import-kit.md) | Deployment brief: running FriedcakeSMP on the 2b2t museum world with a weekly re-seed loop. |
| [`MANUAL_TEST_GUIDE.md`](MANUAL_TEST_GUIDE.md) | End-to-end manual verification procedure for the merged mod set. |
| [`SPEC-CONFORMANCE-REPORT.md`](SPEC-CONFORMANCE-REPORT.md) | Audit of specification against implementation (2026-09-23), with a per-feature verdict. |
| [`fixes/`](fixes/) | One self-contained fix brief per gap found by that audit. `fixes/00-P0-blockers.md` is the boot blocker. |
| [`friedcake/README.md`](friedcake/README.md) | Modpack-level documentation: installation, storage backends, command list. |
| [`LICENSE.txt`](LICENSE.txt) | MIT for the specification, scripts and documentation; LGPL-2.1-or-later for the mod code. |

## Status

Thirteen feature branches have been merged (see [`INTEGRATION.md`](INTEGRATION.md));
`friedcake/mods/modpack.conf` declares 22 mods, and features f01–f15 are
implemented. Feature f16 (legacy modules) has not been started. The verdicts
below are the audit's, summarised from
[`SPEC-CONFORMANCE-REPORT.md`](SPEC-CONFORMANCE-REPORT.md).

| Spec | Mod(s) | State |
|---|---|---|
| shared §2.2 storage | `smp_store` | implemented — `mod_storage`, SQLite, Postgres |
| shared §0.4 UI kit | `smp_core` | implemented — money formatter, amount parser, menu sessions |
| shared §2.5 items | `smp_items` | implemented — M0–M2 item keys |
| shared §5.5 privileges | `smp_admin` | implemented — `smp_admin`, `smp_moderator` |
| f01 economy | `smp_economy` | implemented — PARTIAL (14 gaps) |
| f02 sell | `smp_sell` | implemented — MOSTLY COMPLETE (2 gaps) |
| f03 auction | `smp_ah` | implemented — MOSTLY COMPLETE (4 gaps) |
| f04 orders | `smp_orders` | implemented — MOSTLY COMPLETE (3 gaps) |
| f05 Quick Buy | `smp_quickbuy` | implemented — COMPLETE |
| f06 shards | `smp_shards`, `smp_shardshop`, `smp_amethyst` | implemented — MOSTLY COMPLETE (5 gaps) |
| f07 spawners | `smp_spawners` | implemented — PARTIAL (14 gaps) |
| f08 teleport | `smp_tp`, `smp_rtpqueue` | implemented — MOSTLY COMPLETE (8 gaps) |
| f09 homes | `smp_tp` (homes subsystem) | implemented — wired into `smp_tp` (config-key gaps remain) |
| f10 combat | `smp_combat`, `smp_bounty` | implemented — MOSTLY COMPLETE (2 gaps) |
| f11 social | `smp_social` | implemented — MOSTLY COMPLETE (5 gaps) |
| f12 settings | `smp_settings` | implemented — MOSTLY COMPLETE (4 gaps) |
| f13 ranks | `smp_ranks` | implemented — MOSTLY COMPLETE (2 gaps) |
| f14 stats | `smp_stats` | implemented — MOSTLY COMPLETE (4 gaps) |
| f15 world rules | `smp_world` | implemented — COMPLETE |
| f16 legacy | — | not implemented |

> **Gap counts above are the audit's original figures.** The remediation
> (2026-09-23) closed the P0 boot blockers, the P1 data-loss/integrity
> defects, and the clear P2 bugs (teleport-request mirror, RTP spawn
> exclusion and border probe, i18n holes, `/pay` blocked-recipient check).
> See `SPEC-CONFORMANCE-REPORT.md` §"Remediation applied" for the exact
> list; the remaining per-feature gaps are tracked in `fixes/`.

Two things to know before testing:

1. **The gate is a fully green run of the 20 dev-test suites**
   (`tools/agent-flow.sh test`); it is green on 2026-09-23.
2. **The P0 boot blockers are fixed.** The audit's two classes of
   nonexistent-engine-API call (`core.register_on_globalstep`,
   `core.modpath`) were corrected, and f09 homes was wired into `smp_tp`
   (commits `68b5bf5`–`87c0eae`). The pack is expected to boot on a real
   server; in-game verification is in
   [`MANUAL_TEST_GUIDE.md`](MANUAL_TEST_GUIDE.md). Remaining gaps are
   tracked per feature in
   [`SPEC-CONFORMANCE-REPORT.md`](SPEC-CONFORMANCE-REPORT.md) and
   [`fixes/`](fixes/).

## Repository layout

```
.
├── AGENTS.md                        # rules for AI agents (read this first)
├── CONTRIBUTING.md                  # human workflow + branching model
├── HANDOFF.md                       # background: how the spec was produced
├── INTEGRATION.md                   # first merge pass: state of the tree
├── LICENSE.txt                      # MIT (spec/scripts/docs) + LGPL-2.1 (modpack)
├── MANUAL_TEST_GUIDE.md             # end-to-end manual test walkthrough
├── README.md                        # this file
├── SPEC-CONFORMANCE-REPORT.md       # spec vs. implementation audit (2026-09-23)
├── archive/
│   └── donut-smp-feature-spec-v0.1.md   # superseded first draft of the spec
├── fixes/                           # one fix brief per audit gap (00 = P0 blockers)
├── spec/
│   ├── README.md                    # integrator-owned overview
│   ├── features/f01–f16             # one .md per feature
│   ├── shared/00–08                 # conventions, architecture, UI kit, mirrors
│   └── plan/                        # roadmap, open questions, acceptance tests
├── friedcake/                       # modpack wrapper (docs, dev-tests, mods/)
│   ├── README.md                    # installation, storage backends, commands
│   ├── WORLD_RULES.md               # f15 rules → engine settings mapping
│   ├── minetest.conf.example        # recommended server configuration
│   ├── dev-tests/                   # standalone luajit smoke tests (20 suites)
│   └── mods/                        # the modpack (drop into Mineclonia mods/ as "friedcake")
│       ├── modpack.conf             # pack metadata + intended load order
│       └── smp_*/                   # 23 mods, one directory per feature area
├── tools/
│   ├── agent-flow.sh                # wrapper for the parallel-agent workflow
│   └── *.md                         # agent prompts, claim files, integrator notes
├── build_descriptions.py            # source pipeline: VLM description builder
├── build_frame_index.py             # source pipeline: frame index builder
├── build_navigation.py              # source pipeline: thumbnail navigation
├── split_descriptions_per_frame.py  # source pipeline: per-frame split
├── run_qwen_vl_describe.py          # client that drives the frame describer
├── setup_qwen_vl.sh                 # provisioning script for the VLM host
├── topics.md                        # source-pipeline outputs (in git)
├── feature_index.md / .csv, frame_index.csv          # source-pipeline outputs
├── old-donut-smp-feature-spec-luanti-mineclonia.md   # pre-spec draft (gitignored)
├── frames/                          # 1920×1080 source frames (gitignored)
├── *.mp4, *.srt                     # source video + subtitles (gitignored)
└── frame_descriptions_vlm.*, thumbnail_grid.jpg      # VLM artefacts (gitignored)
```

## Engine source of truth

The local clones below are fresher than any commit SHA pinned in `spec/`:

| Engine | Local clone | Notes |
|---|---|---|
| Mineclonia (latest) | `~/dev/mineclonia-git` | clone of `mineclonia/mineclonia`, tracking upstream `main` |
| Luanti | `~/dev/luanti` | local checkout, 5.17.0 — binary at `bin/luanti`, with `mineclonia` symlinked into `games/` |

Do **not** treat "verified against GitHub mirror, commit `5bdce566`,
2026-09-21" in the original specification as current: that mirror lags.
Verify against the local clones.

## Repository workflow

Parallel agents work on `agent/<feature>` branches cut from `main`. The
integrator merges. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the contract;
AI agents must read [`AGENTS.md`](AGENTS.md) first.

The `tools/agent-flow.sh` wrapper automates the routine steps:

```sh
tools/agent-flow.sh start f02-sell   # cut a feature branch
tools/agent-flow.sh test             # run the dev-test suites
tools/agent-flow.sh spec f02-sell    # page through the spec file
tools/agent-flow.sh check            # confirm we're not on main
```

## Verification

Headless, without starting the engine:

```sh
tools/agent-flow.sh test                       # all 20 suites
luajit friedcake/dev-tests/test_fmt.lua        # or one at a time
luajit friedcake/dev-tests/test_store.lua
luajit friedcake/dev-tests/test_economy.lua
```

Expected: `[agent-flow] all dev-tests green`. Every suite prints `ALL OK`
and exits 0 on success. See
[`friedcake/dev-tests/README.md`](friedcake/dev-tests/README.md) for the
coverage table. If the run is red while the P0 fix brief is in flight, see
[Status](#status).

In-game, once the pack boots (privilege `smp_admin`):

```
/smp test smp_core       # f01 T1–T3 + store smoke checks
/smp test smp_ah         # auction house T1–T10
/smp test smp_sell       # selling suite
/smp test smp_quickbuy   # Quick Buy suite
```

Each prints `Passed: N` / `Failed: 0`. The remaining mods ship
`mods/<mod>/test.lua` but are not registered with the dispatcher yet, so
`/smp test <mod>` answers `Unknown test target` until the integrator adds
the generic test registry; those suites still run headlessly.

The full in-game procedure — setup, feature walkthroughs and the failure
reporting path — is in [`MANUAL_TEST_GUIDE.md`](MANUAL_TEST_GUIDE.md).

## Source media

The 1920×1080 frames, the source MP4, the subtitles and the generated VLM
descriptions are present in a working checkout but excluded from git by
[`.gitignore`](.gitignore): they are large and regenerable from the YouTube
link documented in [`HANDOFF.md`](HANDOFF.md).

| Artefact | Path | In git |
|---|---|---|
| Source frames | `frames/` | no |
| Source video | `How to get Started on the Donut SMP … .mp4` | no |
| Subtitles | `*.srt` | no |
| VLM descriptions | `frame_descriptions_vlm.{csv,json,md}` | no |
| Thumbnail grid | `thumbnail_grid.jpg` | no |
| Frame index | `frame_index.csv` | yes |
| Feature index | `feature_index.md`, `feature_index.csv` | yes |
| Topic list | `topics.md` | yes |

The pipeline scripts that rebuild them are `setup_qwen_vl.sh`,
`run_qwen_vl_describe.py`, `build_descriptions.py`, `build_frame_index.py`,
`build_navigation.py` and `split_descriptions_per_frame.py`.

## How this repository was built

The starting point was written with AI assistance ("vibe coded") rather than
by hand. The author is a software engineer and former CTO with 20 years of
experience, and saw no good reason not to use the same tooling the industry
is moving to — with the additional goal of evaluating how current models
perform on a real, spec-driven codebase.

**Process**

1. **Frame analysis.** Qwen2.5-VL-72B-Instruct examined and described the
   141 frames extracted from the source tutorial video.
2. **Feature research.** Opus 5.5 (maximum reasoning effort) read the public
   Donut SMP wiki and summarised the feature set.
3. **Specification.** The frame analysis and the wiki summary were fed back
   into Opus to re-evaluate and formalise the specification, which was then
   broken out into the 16 feature files, the shared conventions and the
   agent-coding setup.
4. **Implementation.** Features were assigned across several models —
   Opus 5.5, MiMo-V2.6-Flash, DeepSeek 4 Pro, Qwen3.8-2.4T-A95B and
   Qwen 3.8 27B — in order to compare their code quality. The results were
   then reviewed to the standard one would apply to a junior engineer's
   work.

**Evaluation notes**

| Model | Notes |
|---|---|
| MiMo-V2.6-Flash | Best result of the exercise: excellent code quality at a strong cost per token. |
| Qwen 3.8 27B | Cost-efficient and free of the problems seen elsewhere, although it was assigned the simpler features. |
| Qwen3.8-2.4T-A95B | Weakest result: several key mistakes, and roughly $20 spent within minutes. |
| Opus 5.5 | Used for the specification, feature breakdown and the agent workflow design. |
| DeepSeek 4 Pro | Included in the evaluation set for code-quality comparison. |

## Licence

MIT for the specification, scripts and supporting documentation; the mod code
under `friedcake/` is dual-licensed LGPL-2.1-or-later to match Mineclonia and
Luanti. See [`LICENSE.txt`](LICENSE.txt).
