# S09 — Admin, social, ender chest, formspecs: what was checked

**Audited at:** `85e4a5d`. This brief is mostly a **verified-OK record**, so
the next auditor does not repeat the work. The actionable items are small.

## Actionable

| ID | Sev | Where | Fix |
|---|---|---|---|
| MS-1 | Low | `smp_social/kill.lua` | `/kill` is not combat-blocked. It is the cheapest bounty-laundering step (S07 CB-2): add it to `combat.blocked_commands` defaults |
| MS-2 | Low | pack-wide | Add the **chat-command lint** from S06 SP-1: no `privilege` key, and every admin-sounding command declares `privs` or does an explicit check |
| MS-3 | Low | pack-wide dev-test harness | Add the **strict engine stub** from S05 QB-1: `core.get_player_by_name`, `core.chat_send_player` and similar raise on non-string names, as `luaL_checkstring` does. Two crash or no-op bugs (QB-1, SH-1, EC-2) slipped through because the stubs are lenient |

## Verified OK

- **Admin commands.** `/eco`, `/smp`, `/smp_backend`, `/orderadmin`,
  `/ahadmin`, `/bountyadmin`, `/shardsadmin`, `/rank`, `/combat untag`
  and `/sellreload` declare `privs = { smp_admin = true }`. `/ledger`,
  `/mute` and `/unmute` do an explicit admin-OR-moderator check.
  `core.override_chatcommand("smp", {func=…})` in `smp_sell`, and the
  in-place `func` wrappers in `smp_ah`, keep the original `privs`.
  **Exception: `/spawner` (S06 SP-1, critical).**
- **Ender chest** (`smp_enderchest`). The 54-slot list lives in
  `current_player`, and every put, take or move touching it requires an
  ender chest node within hand range
  (`register_allow_player_inventory_action`). The list is not in
  `mcl_death_drop` lists, so it is kept on death (the intended ender chest
  semantics). Legacy migration moves an item only when there is room, and
  clears only the migrated slots.
- **Formspec escaping.** Every file that renders user or item strings uses
  a local `F`/`E`/`fesc` = `core.formspec_escape`: `smp_ah`,
  `smp_orders`, `smp_stats`, `smp_settings`, `smp_shardshop`, `smp_tp`
  homes, `smp_quickbuy`, `smp_spawners` and `smp_social`. Player names
  are engine-restricted to `[A-Za-z0-9_-]`. The remaining free-text
  sources are anvil names (item descriptions), home names and search
  queries, and all of these are escaped where rendered.
- **Spawn protection** (`smp_world`). It wraps `core.is_protected` for
  `world.spawn_protect_radius` around the origin, Overworld only. Outside
  that radius there is **no protection** unless the operator adds a claims
  mod. Findings that depend on protection (S05 sell-axe note, S06 SP-4) are
  written with that in mind.
