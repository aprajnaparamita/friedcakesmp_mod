# FriedcakeSMP

A Mineclonia / Luanti modpack that recreates the Donut SMP player-facing
interface. The recreation is **verbatim** for menu titles, button labels and
server chat strings (see `spec/shared/00-conventions.md` §0.5), and uses a
clean, modular Lua implementation for everything underneath.

The project layout splits two concerns:

| Path | What |
|---|---|
| `friedcake/` (this directory) | The modpack. Drop into Mineclonia's `mods/` folder. |
| `../spec/` | The specification each `smp_*` mod is built against. |

The spec is the source of truth. The mod code lives here.

## Status

| Mod | Phase | State | Owner spec | Notes |
|---|---|---|---|---|
| `smp_core` | P0 | **implemented** | `spec/shared/04-ui-kit.md` | Formatter, parser, menu sessions |
| `smp_store` | P0 | **implemented (SQLite primary, mod_storage fallback, Postgres stub)** | `spec/shared/02-architecture.md §2.2–2.3` | Player records, ledger |
| `smp_economy` | P0 | **implemented** | `spec/features/f01-economy-core.md` | `/bal`, `/pay`, `/paytoggle`, `/baltop`, `/shards`, `/eco`, `/ledger`, `/smp` |
| `smp_admin` | P0 | **implemented (privileges only)** | `spec/shared/05-command-reference.md §5.5` | `smp_admin`, `smp_moderator` |
| `smp_ranks` | P0 | stub | `spec/features/f13-ranks.md` | Reserved |
| `smp_items` | P0 | stub | `spec/shared/02-architecture.md §2.5` | Reserved |

The remaining features (P1–P8) are not started; their `smp_*` mods will appear
under this directory as parallel agents pick them up. See
`spec/plan/roadmap.md`.

## Storage backends

`smp_store` is backend-agnostic. Three are shipped today, one stub:

| `store.backend` | Status | Notes |
|---|---|---|
| `mod_storage` | working | `core.get_mod_storage()` + JSON. Zero setup. |
| `sqlite` | working (recommended) | `lsqlite3` via `request_insecure_environment()`. Mod must be in `secure.trusted_mods`. |
| `auto` | working | Tries SQLite → falls back to mod_storage. The default. |
| `postgres` | **stub** | API defined; refuses to load with a clear error. The eventual driver goes over `core.request_http_api()` to a local `pgwire` proxy — direct TCP from the Lua sandbox is not available. |

See `mods/smp_store/STORAGE.md` for the driver contract, the schema, and the
list of operations every backend must implement.

## Installation

Drop `friedcake/` into Mineclonia's `mods/` directory, or add its parent
directory to `secure.mods` in `minetest.conf`. Then add to `minetest.conf`:

```
secure.trusted_mods = smp_store
secure.http_mods = smp_store
```

(The second line is only required once a Postgres backend is wired in.)

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
