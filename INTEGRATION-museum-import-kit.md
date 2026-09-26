# Museum-import-kit integration — weekly re-seed loop

Status: **PLANNED** — this file is the working brief for the museum
deployment. Nothing here is built yet; it records the intent and the open
design questions so the work is unambiguous.

FriedcakeSMP is being deployed as the **gameplay layer** on top of the
[2b2t museum-import-kit](https://github.com/aprajnaparamita/museum-import-kit)
world. The museum kit imports the 2b2tmuseum-WDL archive (205 historic
bases) into a single packed Mineclonia world; FriedcakeSMP supplies the
Donut SMP feature set (economy, auction house, homes, teleports, combat,
stats, world rules) on top of that terrain.

## The plan

1. **Load FriedcakeSMP** for the Donut SMP features — the 22-mod
   `friedcake/` pack dropped into the museum world's `worldmods/`.
2. **Import all the bases** with the museum kit
   (`tools/prepare_world.sh` + `tools/supervise.sh` in `museum-import-kit`).
3. **Re-import weekly with a different seed.** The seed only reshuffles the
   procedurally-generated terrain *between* bases; the 205 imported bases
   are re-placed identically each week. This keeps the small Mineclonia map
   from going stale.
4. **Eventually: player "bases".** A new feature lets a player claim and
   protect a base, which is preserved and moved along with the museum bases
   on every weekly re-import — so player progress survives the seed change.

## Why re-seed

The museum world is a *packed* world: 205 bases in a small Mineclonia map.
Without a changing map, exploration is one-and-done. Re-seeding the
surrounding terrain weekly keeps the map fresh each week while the museum
bases — the reason people show up — stay intact.

## Cross-repo split

| Repo | Owns |
|---|---|
| `museum-import-kit` | Base import (Anvil/NBT decode, block resolution, VoxelManip placement, gap-fill), loot/mob/kit systems, warps, the supervised batch runner, and the re-seed pipeline. |
| `friedcakesmp_mod` | The Donut SMP feature modpack and this integration brief. |

## Interaction points to settle (open)

- **Seed rule vs. weekly re-seed.** `smp_world` f15 §5 forbids exposing the
  seed to players. A weekly re-seed makes last week's seed stale, but the
  *current* seed must still never reach players (no command, menu, or API
  output may surface `mapgen_seed`).
- **Persistence across re-imports.** `smp_store` (economy, homes, settings,
  ranks, stats) lives in `mod_storage.sqlite` — decide whether player data
  carries across weekly re-imports (preserve the DB, wipe the world) or
  resets with the map.
- **Spawn protection / border.** The re-import pipeline must place bases
  outside `smp_world`'s 128-radius spawn square, or re-tune
  `world.spawn_protect_radius`, so weekly mapgen never fights the protected
  spawn.
- **Player-base protection (new feature).** The planned base feature should
  hook the same `core.is_protected` chain `smp_world` wraps, so claim
  protection is honoured automatically by spawner digging, amethyst tools,
  PvP decisions, and RTP landing checks.

## Proposed feature: player bases

Tentatively **f17 — player bases** (not yet in `spec/features/`). It would:

- let a player claim a base region (a protected area they own),
- serialize that region (blocks + container contents + metadata),
- re-place it each weekly re-import alongside the 205 museum bases, and
- protect it via `core.is_protected` for the rest of the week.

This stays tracked here until it gets a feature file and an owner.
