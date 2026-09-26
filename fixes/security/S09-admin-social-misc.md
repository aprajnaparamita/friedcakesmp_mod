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

## Status (2026-09-27)

Verification pass on branch `agent/sec-s09-admin` (read-only sweep — **no
code was changed**, only this file). Every row of the Verified-OK list
above was re-checked at the audited source; results with `file:line`
evidence are below. The three actionable rows are **ownership records
only** — they are implemented by sibling agents in sibling worktrees.

### MS-1..MS-3 — ownership table (NOT implemented here)

| Row | Finding | Owning brief (fix item) | Target file | Status |
|---|---|---|---|---|
| MS-1 | `/kill` is not combat-blocked → add it to the `combat.blocked_commands` defaults | **S07** — `fixes/security/S07-combat-bounty.md`, CB-2 fix item 3 ("Add `kill` (and its aliases) to `DEFAULT_BLOCKED`") | `friedcake/mods/smp_combat/config.lua` (`DEFAULT_BLOCKED`, line 38) | owned by sibling S07, tracked in fixes/security/S07-combat-bounty.md |
| MS-2 | pack-wide chat-command lint: fail on a `privilege` key, unknown def keys, or an admin-sounding command with neither `privs` nor an inline check | **S06** — `fixes/security/S06-spawners.md`, SP-1 fix item 3 ("Add a pack-wide lint to `dev-tests/`") | new file `friedcake/dev-tests/test_chatcmds.lua` | owned by sibling S06, tracked in fixes/security/S06-spawners.md |
| MS-3 | strict engine stub: `core.get_player_by_name`, `core.chat_send_player` (and similar) raise on non-string names, as `luaL_checkstring` does; each suite applies it | **S05** — `fixes/security/S05-shops-shards.md`, QB-1 "Tests" item 3 ("strict engine stub … to the shared harness") | shared dev-test harness + each suite's own stub (applied per suite) | owned by sibling S05, tracked in fixes/security/S05-shops-shards.md |

State of the three rows at this commit (i.e. all three still open here,
as expected — their fixes land in the sibling worktrees):

- MS-1 open: `smp_combat/config.lua:38-41` `DEFAULT_BLOCKED` contains
  `rtp, rtpqueue, tpa, tp, tpahere, tpaccept, homes, home, spawn, warp,
  world, shop` — no `kill` (grep for `"kill"` in that file: no match).
- MS-2 open: `friedcake/dev-tests/test_chatcmds.lua` does not exist yet
  (31 entries in `dev-tests/`, none named `test_chatcmds`).
- MS-3 open: stubs are still lenient, e.g.
  `dev-tests/harness_f10.lua:268` `core.get_player_by_name = function(n)
  return players[n] end` and `dev-tests/test_sell.lua:698` — they return
  `nil` for a non-string instead of raising.

### Verified OK — re-checked at the audited code

**A. Admin chat-command privileges** (swept every
`core.register_chatcommand` in `friedcake/mods/smp_*/`: 64 static
registration sites + 14 `smp_social.register_cmd` call sites — one of
which, `register_info`, expands to 8 commands)

| Claim | Evidence | Result |
|---|---|---|
| `/eco` declares `privs = { smp_admin = true }` | `smp_economy/init.lua:592` (reg), `:595` (privs) | VERIFIED |
| `/smp` declares `privs = { smp_admin = true }` | `smp_economy/init.lua:831`, `:834` | VERIFIED |
| `/smp_backend` declares `privs = { smp_admin = true }` | `smp_store/init.lua:378`, `:381` | VERIFIED |
| `/orderadmin` declares `privs = { smp_admin = true }` | `smp_orders/init.lua:696`, `:699` | VERIFIED |
| `/ahadmin` declares `privs = { smp_admin = true }` | `smp_ah/init.lua:1333`, `:1336` | VERIFIED |
| `/bountyadmin` declares `privs = { smp_admin = true }` | `smp_bounty/init.lua:209`, `:212` | VERIFIED |
| `/shardsadmin` declares `privs = { smp_admin = true }` | `smp_shards/init.lua:216`, `:219` | VERIFIED |
| `/rank` declares `privs = { smp_admin = true }` | `smp_ranks/init.lua:78`, `:81` | VERIFIED |
| `/combat untag` (whole `/combat` command) declares `privs = { smp_admin = true }` | `smp_combat/init.lua:161`, `:164` | VERIFIED |
| `/sellreload` declares `privs = { smp_admin = true }` | `smp_sell/init.lua:573`, `:576` | VERIFIED (declaration) + caveat: the registration sits in the **`else` branch** of `if smp_cmd …` (`smp_sell/init.lua:543-582`), and `smp_sell/mod.conf` has `depends = …, smp_economy`, so `/smp` always exists and **`/sellreload` is never registered at runtime**. Dead branch, not a hole. |
| `/ledger` does an explicit admin-OR-moderator check | `smp_economy/init.lua:661` `LEDGER_PRIVS = { "smp_admin", "smp_moderator" }`, `:663-669` `ledger_allowed`, gate at `:693` | VERIFIED |
| `/mute`, `/unmute` do an explicit admin-OR-moderator check | `smp_admin/init.lua:58-63` `is_staff` (`smp_admin or smp_moderator`), gates at `:195` and `:215` | VERIFIED |
| `core.override_chatcommand("smp", {func=…})` in `smp_sell` keeps the original `privs` | override passes only `func` (`smp_sell/init.lua:546-569`); Luanti's `override_chatcommand` rawsets only the keys present in the redefinition onto the existing table (`~/dev/luanti/builtin/common/chatcommands.lua:63-70`) | VERIFIED |
| The in-place `func` wrappers in `smp_ah` keep the original `privs` | wrappers reassign `cmd.func` only, on the already-registered `/smp` table: `smp_ah/init.lua:1420-1433` (on_mods_loaded hook) and `:1437-1447` (reload wrapper) | VERIFIED |
| Exception `/spawner` (SP-1, critical) really uses the wrong key | `smp_spawners/init.lua:244` `privilege = "smp_admin",` — the only non-standard def key in the whole pack | VERIFIED |
| (context) MS-1's premise: `/kill` has no privs and is not combat-blocked | `smp_social/kill.lua:33-46` registers without `privs`; `smp_combat/config.lua:38-41` `DEFAULT_BLOCKED` has no `kill` | VERIFIED (fix owned by S07) |

**B. Ender chest (`smp_enderchest`)**

| Claim | Evidence | Result |
|---|---|---|
| The 54-slot list lives in `current_player` | `smp_enderchest/init.lua:57` (`SLOTS = 9*6 = 54`), `:89` (`list[current_player;smp_enderchest;…;9,6;]`), `:131` (`inv:set_size(LIST, 54)` on the player inventory) | VERIFIED |
| Every put/take/move touching it requires an ender chest node within hand range | `smp_enderchest/init.lua:152-170` `register_allow_player_inventory_action`; touches test `:157-162`; range `:164-166`; deny `find_node_near(...)` → `return 0` at `:167-168` | VERIFIED — and it mirrors Mineclonia's own guard verbatim (`~/dev/mineclonia-git/mods/ITEMS/mcl_chests/init.lua:1219-1231`, same node + same range expression). Only `mcl_chests:ender_chest_small` is checked, which is correct: every placed `mcl_chests:ender_chest` converts itself to `_small` in `on_construct` (`mcl_chests/init.lua:1103-1107`) |
| The list is not in `mcl_death_drop` lists, so it is kept on death | `~/dev/mineclonia-git/mods/PLAYER/mcl_death_drop/init.lua:9-12` registers only `main`, `craft`, `armor`, `offhand`; pack-wide grep for `register_dropped_list` matches only `dev-tests/harness_f10.lua` | VERIFIED |
| Legacy migration moves an item only when there is room, and clears only the migrated slots | `smp_enderchest/init.lua:136-144` — `room_for_item` guard `:140`, `add_item` `:141`, `set_stack(ENGINE_LIST, i, "")` `:142` inside that guard (no room → stack stays in the engine list) | VERIFIED |
| `test_enderchest.lua` 74/75 baseline failure explained | FAIL is `T8 modpack.conf readable`: `dev-tests/test_enderchest.lua:471` opens `ROOT .. "/friedcake/modpack.conf"`, but the tracked file is `friedcake/mods/modpack.conf` (`git ls-files \| grep modpack`) and `friedcake/modpack.conf` exists in **no** checkout | VERIFIED — harness path bug, same root cause as the `test_integration.lua` baseline failure; **nothing to do with the ender-chest claims above** |

**C. Formspec escaping** (spot-check of every file that builds a
formspec: a repo-wide grep for `formspec_version[` / element strings
lists exactly 15 non-test files, all of them below)

| Claim | Evidence | Result |
|---|---|---|
| `smp_ah` escapes user/item strings | `smp_ah/formspec.lua:37` `local F = core.formspec_escape`; `label()` escapes at `:104-106`; every tooltip line escaped in `fs.tooltip` `:362-373`; listing cell itemstring/count `:439-450`; confirm grid tooltip escape `:711-717` (F at `:714`) | VERIFIED |
| `smp_orders` escapes | `smp_orders/formspec.lua:28` `local F = …`; item tooltip `:82-84`; `label()` `:89-91`; `button()` text `:96-98` | VERIFIED |
| `smp_stats` escapes (incl. player names on the board) | `smp_stats/formspec.lua:20` `local F = …`; leaderboard cells `F(S("@1. @2 — @3", rank, e.name, …))` `:170-172`; stat rows `F(...)` `:131`; `Stats - <name>` title via `head_prompt` → `F(title)` `:66-72` (called `:127`) | VERIFIED |
| `smp_settings` escapes | `smp_settings/formspec.lua:16` `local F = …`; `button()` `:45-51` (`F(text)`); titles/tooltips `F(...)` at `:76`, `:94`, `:123`, `:132` | VERIFIED |
| `smp_shardshop` escapes | `smp_shardshop/formspec.lua:26` `local F = …`; `fs.tooltip` escapes each line `:74-80`; item/button `F(item)`/`F(btn)` `:110`, `:121`; label `:130` | VERIFIED |
| `smp_tp` homes escape | `smp_tp/homes.lua:98-99` `fesc` = `core.formspec_escape`; home name label **and** tooltip `fesc(hm.name)` `:403-408`; icon picker `fesc(it.t)` `:467-468`; `smp_tp/formspec.lua:24-28` `E()` used for the lobby label `:117-118` | VERIFIED |
| `smp_quickbuy` escapes | `smp_quickbuy/formspec.lua:26` `local esc = …`; entry itemstring `:172`; entry tooltip `esc(entry_tooltip(...))` `:174-175`; labels `:156-157`, `:199-200` | VERIFIED |
| `smp_spawners` escapes | `smp_spawners/formspecs.lua:45-47` `local esc`; item name in button `:171-172`; `esc(item_desc(name))` tooltip `:176-178`; labels `:139-153` | VERIFIED |
| `smp_social` escapes | `smp_social/info.lua:53` (title) and `:55` (textarea content); `smp_social/kill.lua:18` `local E = core.formspec_escape`, used `:25-29` | VERIFIED |
| Search queries are escaped where rendered | `smp_ah/formspec.lua:655-656` `F(query or "")`; `smp_orders/formspec.lua:324-325` `F(session.search or "")`; `smp_tp/homes.lua:484` `fesc(query)`, `:504` `fesc(prefill)` | VERIFIED |
| Home names are escaped where rendered | `smp_tp/homes.lua:403-408` (`fesc(hm.name)` in label + tooltip) | VERIFIED |
| Anvil names (item descriptions) are escaped where rendered | AH: `display.name` → tooltip lines → `fs.tooltip` (`smp_ah/formspec.lua:424` → `:362-373`, confirm grid escape `:711-717`, `fs.confirm_listing` `:730-746`); Orders: `display_name` → `item_button` tooltip `F(...)` (`smp_orders/formspec.lua:82-84`, caller `:340-346`); spawners `esc(item_desc(name))`; quickbuy `esc(entry_tooltip(...))`; sell menu `label()` = `core.formspec_escape` (`smp_sell/menu.lua:265-266`) — plus engine-side tooltips for plain `list[]` stacks | VERIFIED (spot-check; every form-building file has an escape alias and every user/item string I traced passes through it) |
| Player names are engine-restricted to `[A-Za-z0-9_-]` | `~/dev/luanti/src/player.h:17` `PLAYERNAME_ALLOWED_CHARS "a-zA-Z0-9-_"`; enforced at login `~/dev/luanti/src/network/serverpackethandler.cpp:146-150` (`SERVER_ACCESSDENIED_WRONG_CHARS_IN_NAME`) | VERIFIED |
| `core.formspec_escape` covers the injection characters | `~/dev/luanti/builtin/common/misc_helpers.lua:312-315` escapes `[ \ ] , ; $` (newlines are not escaped — both the per-line and the join-then-escape styles used in the pack are therefore safe) | VERIFIED (context for the claim) |

**D. Spawn protection (`smp_world`)**

| Claim | Evidence | Result |
|---|---|---|
| It wraps `core.is_protected` (never replaces it) | `smp_world/init.lua:83-97` — saves `old_is_protected`, `return old_is_protected(pos, name)` at `:96` | VERIFIED |
| It uses `world.spawn_protect_radius` around the origin | `smp_world/init.lua:58-60` (`cfg_number("world.spawn_protect_radius", 128)`), test at `:70` | VERIFIED — nuance: the region is a **square** of half-width r (`|x|>r or |z|>r` → false, `:70-72`), not a circle; the file's own comment (`:62-64`) says "square of half-width" |
| Overworld only | `smp_world/init.lua:73` `mcl_worlds.pos_to_dimension(pos) == "overworld"` | VERIFIED |
| Outside that radius there is no protection unless the operator adds a claims mod | pack-wide grep `function core.is_protected` → only `smp_world/init.lua:85`; Mineclonia-wide grep → only `MAPGEN/mcl_levelgen/post_processing.lua:3264` (ungenerated-chunk guard, which the brief's surrounding comment already notes) | VERIFIED (with the mcl_levelgen exception as documented) |
| Dependent findings are written with that in mind | `S05-shops-shards.md:106` ("no protection unless the operator installs a claims mod"), `S06-spawners.md:152` ("On any server running a claims mod (`smp_world` only protects …)") | VERIFIED |

### New findings from the read-only `register_chatcommand` sweep (input for S06's MS-2 lint)

Nothing to fix here — recorded so the lint covers it:

1. **Only one wrong-key registration exists in the pack:**
   `smp_spawners/init.lua:243-244` `privilege = "smp_admin"` (known
   SP-1). A scan of all 64 static registrations found **no other**
   non-standard def key, and no admin-sounding command that declares
   neither `privs` nor an inline check (the three inline-check commands —
   `/mute`, `/unmute`, `/ledger` — were verified above). The lint's
   key-set check should therefore be `params, description, privs, func,
   mod_origin` and would currently fail exactly one command.
2. **`/kill` will be flagged by a naive lint and must be whitelisted
   (deliberate).** `smp_social/kill.lua:33-46` overrides the builtin
   `/kill`, which ships with `privs = {server = true}`
   (`~/dev/luanti/builtin/game/chat.lua:1351-1354`), and registers it
   with **no** `privs`. It is safe as written — the handler only ever
   kills the caller (`kill.lua:52-67`) — but the lint needs a documented
   exception, or S06's "any admin-sounding name without `privs`" rule
   will trip on it every run. (Side effect worth recording: after the
   override, admins lose the builtin `/kill <other player>`.)
3. **`/sellreload` exists in source but never registers at runtime**
   (`smp_sell/init.lua:571-582` else-branch, because `smp_sell` depends
   on `smp_economy` → `/smp` is always present). A purely static lint
   will see it; a harness-based lint that walks
   `core.registered_chatcommands` will not. Either is fine, but the lint
   should say which one it is.
4. **Aliases are separate registrations.** `/auction`, `/auctionhouse`
   (`smp_ah/init.lua:1324-1330`, no `privs`, same as `/ah` — correct) and
   `smp_social`'s aliases, which copy `privs = def.privs`
   (`smp_social/init.lua:99-116`), all appear in
   `core.registered_chatcommands`. The lint must check them too — that is
   where a `privs`-dropping override would hide.
5. **Wrapper-style overrides to keep an eye on:** `smp_sell/init.lua:546`,
   `smp_ah/init.lua:1421`/`:1440`, `smp_stats/init.lua:177` all override
   with `{func = …}` only, which is safe (rawset keeps `privs`,
   `builtin/common/chatcommands.lua:63-70`). A lint rule "an
   `override_chatcommand` whose redefinition table lacks `privs` must not
   target an admin command unless it passes `{func=…}` only" would catch
   the dangerous form (a full def without `privs` silently *removes* the
   privilege gate).
6. **Commands with no `privs` and no inline check are all genuinely
   player-facing** (49 of the 64 static registration sites — 50 commands
   at runtime, since the `/ah` alias loop registers two — with
   `/mute`, `/unmute` and `/ledger` the other no-`privs` three, and 12
   sites carrying a `privs`/`privilege` key): `/ah /auction /auctionhouse
   /bounty /bounties /bal /balance /money /pay /payto /paytoggle
   /paymenttoggle /baltop /moneytop /shards /shard /orders /order /shop
   /rtpqueue /sell /worth /sellhistory /settings /shardshop /api /stats
   /leaderboard /lb /leaderboards /rtp /tpa /tp /tpahere /tpaccept
   /tpadeny /tpdeny /tpacancel /tpauto /tpatoggle /tpaheretoggle /spawn
   /warp /world /back /return /homes /home /sethome /delhome`, plus the
   `smp_social` command sites (14 calls ≈ 21 commands; only `/msg` and
   `/r` declare `privs = { shout = true }`, `pm.lua:68`/`:83`;
   `smp_ranks` states `privs = {}` explicitly, `smp_ranks/init.lua:64`).
   `/settings` and `/api` were checked for hidden authority and are
   per-player only (`smp_settings/accessor.lua:32-51`,
   `smp_stats/api.lua:118-143`).

### Verification runs

- `luajit friedcake/dev-tests/test_engine_apis.lua` → `engine-API guard:
  passed=16 failed=0 / ALL OK` (no code changed, still green).
- `luajit friedcake/dev-tests/test_enderchest.lua` → `74 passed, 1
  failed`; the single failure is `T8 modpack.conf readable`, explained in
  the ender-chest table above (pre-existing baseline, harness path bug).
- `git status --porcelain` → only `fixes/security/S09-admin-social-misc.md`
  modified.
