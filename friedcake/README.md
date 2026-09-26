# FriedcakeSMP

A Mineclonia / Luanti modpack that recreates the Donut SMP player-facing
interface. The recreation is **verbatim** for menu titles, button labels and
server chat strings (see `spec/shared/00-conventions.md` §0.5), and uses a
clean, modular Lua implementation for everything underneath.

The project layout splits two concerns:

| Path | What |
|---|---|
| `friedcake/mods/` | The modpack (the directory containing `modpack.conf`). Drop into Mineclonia's `mods/` folder. |
| `../spec/` | The specification each `smp_*` mod is built against. |

The spec is the source of truth. The mod code lives here.

## Status

| Mod | Phase | State | Owner spec | Notes |
|---|---|---|---|---|
| `smp_core` | P0 | **implemented** | `spec/shared/04-ui-kit.md` | Formatter, parser, menu sessions |
| `smp_store` | P0 | **implemented (mod_storage, SQLite, Postgres)** | `spec/shared/02-architecture.md §2.2–2.3` | Player records, ledger |
| `smp_economy` | P0 | **implemented** | `spec/features/f01-economy-core.md` | `/bal`, `/pay`, `/paytoggle`, `/baltop`, `/shards`, `/eco`, `/ledger`, `/smp` |
| `smp_admin` | P0 | **implemented (privileges only)** | `spec/shared/05-command-reference.md §5.5` | `smp_admin`, `smp_moderator` |
| `smp_ranks` | P0 | stub | `spec/features/f13-ranks.md` | Reserved |
| `smp_items` | P0 | stub | `spec/shared/02-architecture.md §2.5` | Reserved |

The remaining features (P1–P8) are not started; their `smp_*` mods will appear
under this directory as parallel agents pick them up. See
`spec/plan/roadmap.md`.

## Storage backends

`smp_store` is backend-agnostic. Four are shipped:

| `store.backend` | Status | Notes |
|---|---|---|
| `mod_storage` | working | `core.get_mod_storage()` + JSON. Zero setup. |
| `sqlite` | working | `lsqlite3` via `request_insecure_environment()`. Mod must be in `secure.trusted_mods`. (Note: `lsqlite3` is not bundled in Luanti 5.17.0.) |
| `auto` | working | Tries SQLite → falls back to mod_storage. The default. |
| `postgres` | working | HTTP/JSON to a local `pg_proxy.py`, which owns the PostgreSQL connection. Mod must be in `secure.http_mods`. See `mods/smp_store/STORAGE.md` for setup. |

See `mods/smp_store/STORAGE.md` for the driver contract, the schema, and the
list of operations every backend must implement.

## Installation

The modpack is `friedcake/mods/` (the directory that contains `modpack.conf`).
Drop it into Mineclonia's `mods/` directory as `friedcake`, or symlink it into
a world's `worldmods/` directory:

```sh
ln -s /path/to/friedcakesmp_mod/friedcake/mods "<world path>/worldmods/friedcake"
```

Then add to `minetest.conf`:

```
secure.trusted_mods = smp_store
secure.http_mods = smp_store
```

`secure.trusted_mods` lets `smp_store` reach the insecure environment (SQLite
backend); `secure.http_mods` is required for the Postgres backend's HTTP
proxy. With `store.backend = mod_storage` neither is needed.

## Load order

The modpack enforces this through `modpack.conf`:

```
smp_core → smp_store → smp_items → smp_economy → smp_ranks → smp_admin
```

Every later mod depends only on earlier ones. Other agents that pick up
features at later phases MUST add their `load_mod = smp_<feature>` line below
the existing ones and declare their dependencies in their `mod.conf`.

## How parallel agents work

1. **Claim a mod.** Pick one feature from `spec/features/fNN-*.md`. Add it
   to the `modpack.conf` `load_mod` list **below** the existing entries.
2. **Implement it.** Follow `spec/shared/00-conventions.md` for fidelity.
   The shared formatting / parsing / session helpers live in `smp_core`.
3. **Wire it.** Add your commands to your `init.lua` and your privilege
   additions to `smp_admin` (which already registers the standard privileges).
4. **Test it.** Run `luaunit`-style tests under `mods/smp_<feature>/test.lua`
   if you ship one. They run from `/smp test <feature>` once registered, or
   via Luanti's `unittests` mod if present.
5. **Mirror the spec.** When you add a command or config key, flag the spec
   change to the integrator. They own `shared/05-command-reference.md` and
   `shared/06-config-reference.md`.

## Running

FriedcakeSMP is meant to run against a recent Mineclonia checkout. The
local source-of-truth is `~/dev/mineclonia-git` (tracking upstream `main`) and
`~/dev/luanti`. The pinned Luanti version is 5.17.0; Mineclonia's `game.conf`
declares `min_minetest_version = 5.10`.

In-game commands after install:

| Command | Privilege | Purpose |
|---|---|---|
| `/bal [player]` | none | Show a money balance |
| `/pay <player> <amount>` | none | Transfer money |
| `/paytoggle` | none | Toggle receiving payments |
| `/baltop [page]` | none | Money leaderboard |
| `/shards` | none | Shard balance |
| `/eco give\|take\|set\|reset <player> <amount>` | `smp_admin` | Adjust money |
| `/ledger <player> [page]` | `smp_admin` / `smp_moderator` | Audit trail |
| `/smp reload\|test\|backend` | `smp_admin` | Reload config, run tests, show backend |

## Repository layout (top level)

The modpack lives under `friedcake/mods/`; the parent repo also contains the
spec, the source pipeline, and the agent-flow tooling. See
`/Volumes/Dara/dev/coconut/README.md`, `AGENTS.md`, `CONTRIBUTING.md` and
`tools/agent-flow.sh` for the workflow.

A parallel agent working on a feature would:

```sh
# 1. Claim a feature branch.
../tools/agent-flow.sh start f02-sell

# 2. Implement under friedcake/mods/smp_sell/.
# ... write code ...

# 3. Run the dev smoke tests.
../tools/agent-flow.sh test

# 4. Commit and push.
git add friedcake/mods/smp_sell/
git commit -m "f02: shulker-aware sell container and history"
git push origin agent/f02-sell
```
