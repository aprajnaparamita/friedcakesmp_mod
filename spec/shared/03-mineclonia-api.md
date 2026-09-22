# 3. Verified Luanti and Mineclonia Interfaces

All Mineclonia entries were verified in the source at commit `5bdce566`
(21 September 2026) [M1]. Anything not in this file has not been verified —
check it before depending on it, and add it here through the integrator.

## 3.1 Interfaces this specification depends on

| Interface | Use |
|---|---|
| `mcl_enchanting.get_enchantments(stack)`, `set_enchantments`, `has_enchantment(stack, id)`, `get_enchantment`, `enchant(stack, id, level)`. Stored as a serialized table in item meta key `mcl_enchanting:enchantments` | Item matching, order enchantment display, shard-shop gear, Silk Touch checks (id `silk_touch`) |
| `mcl_worlds.pos_to_dimension(pos)`; Y bands `mcl_vars.mg_overworld_min/max`, `mg_nether_min/max`, `mg_end_min/max`, `mg_bedrock_nether_top_max` | RTP dimensions, `/findplayer` |
| `mcl_experience.add_xp(player, xp)`, `mcl_experience.throw_xp(pos, xp)` | Spawner XP collection |
| `mcl_title.set(player, type, {text = ..., color = ..., stay = ...})` | Action-bar countdowns, the observed `Delivering...` indicator [F0226] |
| `mcl_formspec.get_itemslot_bg_v4(x, y, w, h, size, texture)` | Slot backgrounds in menus |
| `mcl_death_drop.register_dropped_list(inv, listname, drop)`; registered lists `main`, `craft`, `armor`, `offhand`; setting `mcl_keepInventory` | Combat-log drops |
| `mcl_potions.give_effect_by_level(name, object, level, duration, no_particles)`, `clear_effect`, `has_effect`; effect ids `haste`, `night_vision` | Haste potion, `/nightvision` |
| `mcl_spawn.get_world_spawn_pos(obj)`, `mcl_spawn.get_player_spawn_pos(player)` | Spawn, respawn after combat log |
| Mob entity callback `on_die(self, pos, mcl_reason)`, called by `mcl_mobs` on death | Mob-kill statistics |
| Arrow entity field `_shooter` (ObjectRef of the shooter) | Projectile combat attribution |
| Shulker item contents in item meta under `compressed` (base64 of zstd) or the empty key `""` (serialized list); shulkers cannot hold shulkers | Selling from shulkers, auction previews |
| Present: `mcl_tools:mace`, enchantments `density` and `wind_burst`, end crystals (`mcl_end`), respawn anchors (`mcl_beds`). **Absent: spears** | Shard shop mapping, PvP notes |

## 3.2 Full mapping table

| Need | Luanti engine API | Mineclonia API [M1] | Notes |
|---|---|---|---|
| Commands | `core.register_chatcommand`, `core.override_chatcommand`, `core.unregister_chatcommand`, `core.register_on_chatcommand` | none | The last one blocks commands during combat |
| Menus | `core.show_formspec`, `core.close_formspec`, `core.register_on_player_receive_fields` | `mcl_formspec.get_itemslot_bg_v4` | `formspec_version[6]` or later |
| Drag-and-drop | `core.create_detached_inventory(name, callbacks, player_name)` | none | Owner-only callbacks |
| Persistence | `core.get_mod_storage`, `player:get_meta()`, `core.get_meta(pos)`, `core.write_json`, `core.parse_json`, `core.serialize`, `core.deserialize`, `core.safe_file_write`, `core.register_on_shutdown` | none | |
| SQLite | `core.request_insecure_environment` (mod in `secure.trusted_mods`) | none | Requires `lsqlite3` on the host |
| HTTP export | `core.request_http_api` (mod in `secure.http_mods`) | none | Outbound requests only |
| Timers | `core.register_globalstep`, `core.after`, `core.get_node_timer(pos)` | none | |
| World access | `core.emerge_area`, `core.get_voxel_manip`, `core.get_node_or_nil`, `core.node_dig`, `core.is_protected` | `mcl_worlds.pos_to_dimension`, `mcl_vars.mg_*` bands | |
| Player events | `core.register_on_joinplayer`, `core.register_on_leaveplayer`, `core.register_on_dieplayer`, `core.register_on_respawnplayer`, `core.register_on_punchplayer`, `core.register_on_player_hpchange` | `mcl_spawn.get_player_spawn_pos`, `mcl_spawn.get_world_spawn_pos` | |
| Block statistics | `core.register_on_dignode`, `core.register_on_placenode` | none | |
| Mob kills | `core.register_on_mods_loaded`, `core.registered_entities` | Entity callback `on_die(self, pos, mcl_reason)` | Wrap every `mobs_mc:*` definition |
| Projectile attribution | none | Arrow entity field `_shooter` | |
| XP | none | `mcl_experience.add_xp`, `mcl_experience.throw_xp` | |
| Enchantments | none | `mcl_enchanting.get_enchantments`, `set_enchantments`, `has_enchantment`, `enchant` | Id `silk_touch` for spawner mining |
| Effects | none | `mcl_potions.give_effect_by_level`, `clear_effect`, `has_effect` | Ids `haste`, `night_vision` |
| Death drops | none | `mcl_death_drop.registered_dropped_lists`; setting `mcl_keepInventory` | |
| Titles, action bar and HUD | `player:hud_add`, `player:hud_change` | `mcl_title.set` | Action bar carries `Delivering...` [F0226] and combat countdowns |
| Shulker contents | `ItemStack:get_meta()`, `core.compress`, `core.decompress`, `core.encode_base64`, `core.decode_base64` | Item meta `compressed` (zstd) or `""` | |
| Translation | `core.get_translator` | none | |
| Accounts and network | `core.get_player_ip`, `core.get_player_information(name)` (field `avg_rtt`) | none | `/ping`, accounts per IP |
| Privileges | `core.register_privilege`, `core.check_player_privs` | none | `smp_admin`, `smp_moderator` |

## 3.3 Java idioms with no Luanti equivalent

The reference server is a Java plugin suite and uses Java-client affordances
that Luanti does not have. Each needs a decided substitution, and each is
specified once here so feature files agree.

| Java idiom | Where observed | Luanti substitution | Decided in |
|---|---|---|---|
| **Sign-edit screen as a text prompt.** Listing a item for auction opens `Edit Sign Message` with the placeholder `Type price` and a `Done` button | [F0139, F0140, F0141] | A formspec `field[]` with the same prompt text and a `Done` button. Two-step confirm preserved | `04-ui-kit.md §4.6`, `f03` |
| **Clickable chat text.** Hovering a player name offers `Click to send NearHat2738 a teleport request` | [F0270, F0284, F0288] | Luanti chat is not clickable. A `/tpa <player>` hint line plus an Accept/Deny formspec | `04-ui-kit.md §4.8`, `f11` |
| **Item-as-button.** Controls are inventory slots holding a decorative item whose tooltip names the action (an oak sign is `Search`, a hopper is `Filter`, a chest is `Your Items`, a lime pane is `Confirm`) | [F0111, F0118, F0126, F0222] | `item_image_button[]` with the same tooltip text and an equivalent Mineclonia item | `04-ui-kit.md §4.3` |
| **`N component(s)` tooltip line.** A Java data-component count | [F0108 and most tooltips] | Omitted. No Luanti meaning | `00-conventions.md §0.5.1` |
| **Client-side HUD** (coordinates, biome, FPS, `[Sprinting (Toggled)]`, `LUNAR CLIENT`) | [F0055, F0124, F0247] | Not reimplemented — these are Lunar Client features, not server features | `01-overview.md §1.2` |
| **Scoreboard sidebar** showing `Voire` and `$ 754k` | [F0287] | `player:hud_add` with `hud_elem_type = "text"`, or a formspec-free HUD group | `f14` |

`Edit Sign Message` is the one substitution that changes an interaction rather
than a rendering, so it is called out again in `f03` and in
`plan/open-questions.md`.
