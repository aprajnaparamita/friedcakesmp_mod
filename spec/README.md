# Donut SMP → Luanti (Mineclonia) Specification

**Version 0.2** · 2026-09-22 · supersedes `archive/donut-smp-feature-spec-v0.1.md`

Specification for re-implementing the player-facing features of Donut SMP
(`donutsmp.net`) as Luanti mods on top of Mineclonia.

> **Engine source-of-truth (agents, read this first):** the local clones
> below are fresher than the commit SHA pinned further down — always verify
> against them before quoting API behaviour, formspec syntax, or `game.conf`
> fields.
>
> - **Mineclonia (latest):** `~/dev/mineclonia-git` — clone of
>   `mineclonia/mineclonia`, tracking upstream `main`. Use this for any
>   reference to Mineclonia mod structure, default mods, crafts, spawn
>   tables, or bundled API mods.
> - **Luanti (updated):** `~/dev/luanti` — local checkout of the Luanti
>   engine. Use this for any reference to Lua API, formspec, builtin
>   privileges, mod security, or engine defaults.
>
> Do **not** treat "verified against GitHub mirror, commit `5bdce566`,
> 2026-09-21" (below) as current — that mirror lags `~/dev/mineclonia-git`.

| Field | Value |
|---|---|
| Target engine | Luanti 5.10 or later (minimum declared in Mineclonia's `game.conf`) |
| Target game | Mineclonia (verified against local clone `~/dev/mineclonia-git`, tracking upstream `main` — see source-of-truth note above; the `5bdce566` / 2026-09-21 GitHub-mirror pin is stale) |
| Reference server | Donut SMP, as documented and observed through September 2026 |
| UI fidelity | **Verbatim clone** — see [`shared/00-conventions.md §0.5`](shared/00-conventions.md) |

---

## Read this first

Every implementer reads all of `shared/`. It is short and it is the contract
between mods. Then read the one feature file you own.

| File | What it settles |
|---|---|
| [`shared/00-conventions.md`](shared/00-conventions.md) | Requirement keywords, **evidence tags**, citation formats, UI fidelity rule |
| [`shared/01-overview.md`](shared/01-overview.md) | Purpose, reference server, scope, design goals |
| [`shared/02-architecture.md`](shared/02-architecture.md) | Mod decomposition, persistence, transactions, item identity |
| [`shared/03-mineclonia-api.md`](shared/03-mineclonia-api.md) | Verified Mineclonia and Luanti interfaces |
| [`shared/04-ui-kit.md`](shared/04-ui-kit.md) | **The observed Donut menu grammar → reusable formspec widgets** |
| [`shared/05-command-reference.md`](shared/05-command-reference.md) | Every command, one table |
| [`shared/06-config-reference.md`](shared/06-config-reference.md) | Every configuration key, one table |
| [`shared/07-sources.md`](shared/07-sources.md) | Citations, including the video frame corpus |
| [`shared/08-ui-strings.md`](shared/08-ui-strings.md) | Verbatim string catalogue for translation |

---

## Feature files and ownership

One agent per file. Nobody edits a file they do not own.

| File | Mod | Phase | Depends on | Frames | Evidence |
|---|---|---|---|---:|---|
| [`features/f01-economy-core.md`](features/f01-economy-core.md) | `smp_economy` | P0 | — | 4 | Mixed |
| [`features/f02-sell.md`](features/f02-sell.md) | `smp_sell` | P1 | f01 | 7 | Medium |
| [`features/f03-auction.md`](features/f03-auction.md) | `smp_ah` | P3 | f01 | 28 | **High** |
| [`features/f04-orders.md`](features/f04-orders.md) | `smp_orders` | P3 | f02, f03 | 47 | **High** |
| [`features/f05-quickbuy.md`](features/f05-quickbuy.md) | `smp_quickbuy` | P3 | f03 | 0 | Research only |
| [`features/f06-shards.md`](features/f06-shards.md) | `smp_shards`, `smp_shardshop`, `smp_amethyst` | P6 | f01 | 0 | Research only |
| [`features/f07-spawners.md`](features/f07-spawners.md) | `smp_spawners` | P2 | f02 | 0 | Research only |
| [`features/f08-teleport.md`](features/f08-teleport.md) | `smp_tp`, `smp_rtpqueue` | P4 | — | 1 | Research only |
| [`features/f09-homes.md`](features/f09-homes.md) | `smp_tp` (homes) | P4 | f08 | 12 | **High** |
| [`features/f10-combat.md`](features/f10-combat.md) | `smp_combat`, `smp_bounty` | P5 | f01 | 0 | Research only |
| [`features/f11-social.md`](features/f11-social.md) | `smp_social` | P7 | f12 | 23 | **High** |
| [`features/f12-settings.md`](features/f12-settings.md) | `smp_settings` | P7 | — | 19 | **High** |
| [`features/f13-ranks.md`](features/f13-ranks.md) | `smp_ranks` | P0 | — | 0 | Research only |
| [`features/f14-stats.md`](features/f14-stats.md) | `smp_stats` | P7 | f01 | 0 | Research only |
| [`features/f15-world-rules.md`](features/f15-world-rules.md) | server config | P0 | — | 0 | Research only |
| [`features/f16-legacy.md`](features/f16-legacy.md) | `smp_crates`, `smp_afk`, `smp_teams`, `smp_duels`, `smp_servershop` | n/a *(f16 descoped — D8, 2026-09-24)* | various | 0 | Research only |

"Frames" counts video frames showing that feature. **A feature with 0 frames
is unverified against the live server**; its UI layout is a proposal, not an
observation. Do not treat the two kinds of file as equally settled.

### Planning

| File | What |
|---|---|
| [`plan/roadmap.md`](plan/roadmap.md) | Phases, dependency graph, acceptance criteria |
| [`plan/open-questions.md`](plan/open-questions.md) | Verification checklist; video-resolved items marked closed |
| [`plan/acceptance-tests.md`](plan/acceptance-tests.md) | Per-feature test matrix |

---

## Rules for working in parallel

1. **One agent per `features/*.md`.** Do not edit another agent's file. If you
   need a change there, note it in your own file under
   `## 10. Open questions` and flag it to the integrator.
2. **`shared/` is read-only to feature agents.** Propose changes in a
   `## Proposed shared changes` block at the end of your own file. The
   integrator merges them. This keeps merge conflicts confined to the two
   integrator-owned tables.
3. **Config keys** are declared in your feature file (section 7) and mirrored
   into `shared/06-config-reference.md` by the integrator. Never hand-edit the
   mirror.
4. **Commands** are declared in your feature file (section 2) and mirrored into
   `shared/05-command-reference.md` by the integrator. Same rule.
5. **Never downgrade an `OBSERVED` requirement to a guess.** If you disagree
   with an observation, record the disagreement; do not silently rewrite it.

---

## Feature file template

Every `features/*.md` has the same ten sections:

| § | Section | Contents |
|---|---|---|
| 1 | Status and ownership | Mod name, phase, dependencies, evidence coverage |
| 2 | Commands | Syntax, aliases, permissions |
| 3 | Observed UI | Verbatim titles, labels and states, with frame citations |
| 4 | Behaviour | Normative MUST/SHOULD, numbered, each evidence-tagged |
| 5 | Data schema | Tables this mod owns |
| 6 | Algorithms | Pseudocode |
| 7 | Configuration | Keys and defaults |
| 8 | Mineclonia implementation | Concrete formspec and API notes |
| 9 | Acceptance tests | What "done" means |
| 10 | Open questions | What still needs verification |

Sections that do not apply say "Not applicable" rather than being deleted, so
the shape stays predictable.

---

## Source material

Kept in the repository root, outside `spec/`:

| Path | What |
|---|---|
| `frames/frame_NNNN.jpg` | 141 frames at 1 fps from the source tutorial video |
| `frame_descriptions_vlm.{md,csv,json}` | Per-frame UI descriptions from Qwen2.5-VL-72B |
| `feature_index.md` | Feature segment boundaries |
| `topics.md`, `*.srt` | Subtitle timeline |
| `archive/donut-smp-feature-spec-v0.1.md` | The superseded single-file spec |
