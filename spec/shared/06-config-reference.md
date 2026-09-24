# 6. Consolidated Configuration Reference

**Integrator-maintained mirror.** Keys are declared in feature files
(section 7). Do not hand-edit this table; change your feature file and flag it.

| Key | Default | Status | Spec |
|---|---|---|---|
| `server.name` | `Donut SMP` | **OBSERVED** [F0236] | shared §0.5 |
| `economy.min_pay` | $0.01 | PROPOSED | f01 |
| `economy.max_balance` | $10¹³ | CLONE [C1] | f01 |
| `economy.flag_threshold` | $1,000,000 | PROPOSED | f01 |
| `economy.flag_min_playtime` | 7,200 s | PROPOSED | f01 |
| `economy.tab_complete` | true | PROPOSED | f01 |
| `ledger.page_size` | 20 | PROPOSED | f01 |
| `store.backend` | `auto` | PROPOSED | shared §2.2 |
| `store.flush_interval` | 10 s | PROPOSED | shared §2.2 |
| `store.max_balance` | $10¹³ — effective cap (cross-note: `economy.max_balance`, f01, is read but dead pending E-18) | PROPOSED | shared §2.2 |
| `store.ledger_page_size` | 20 | PROPOSED | shared §2.2 |
| `sell.multiplier` | 1.0 (Donut used a temporary 3.0 [S2]) | PROPOSED | f02 |
| `sell.mode` | `button` | **OBSERVED** [F0094] | f02 |
| `sell.history_size` | 100 | PROPOSED | f02 |
| `sell.history_page_size` | 5 | PROPOSED | f02 |
| `sell.receipt_max_lines` | 8 | PROPOSED | f02 |
| `sell.meta_exempt` | amethyst items | PROPOSED | f02 |
| `sell.base_prices` | reloadable table | LIVE [S2] | f02 |
| `ah.slots.*`, `ah.slots_default`, `ah.slots_tier1`, `ah.slots_tier2`, `ah.slots_tier3` | `default` 9, `tier1` 45, `tier2` 90, `tier3` 90 — dotted scalar is the primary spelling; the underscore form (`ah.slots_default`-style) is an accepted alias (f04 O3) | LIVE [S17]; default and tier3 PROPOSED | f03 |
| `ah.listing_duration` | 172,800 s | PROPOSED | f03 |
| `ah.listing_fee_pct`, `ah.sale_tax_pct` | 0, 0 | PROPOSED | f03 |
| `ah.min_price`, `ah.max_price` | $1, $10¹² | PROPOSED | f03 |
| `ah.page_size` | 45 | PROPOSED | f03 |
| `ah.reclaim_days` | 30 d | PROPOSED | f03 |
| `ah.insert_slots` | 5 | PROPOSED | f03 |
| `ah.rate_limit` | 1 | PROPOSED | f03 |
| `ah.sweep_interval` | 60 s | PROPOSED | f03 |
| `ah.sweep_budget` | 200 | PROPOSED | f03 |
| `ah.sorts` | `{lowest_price, highest_price, recently_listed}` | **OBSERVED** [F0118] | f03 |
| `ah.history` | 100 per page, 10 pages | LIVE [S23]; pending:f03 | f03 |
| `ah.history_page`, `ah.history_pages` | 100, 10 | PROPOSED | f03 |
| `orders.slots.*`, `orders.slots_default`, `orders.slots_tier1`, `orders.slots_tier2`, `orders.slots_tier3` | `default` 9, `tier1` 45, `tier2` 90, `tier3` 90 — dotted scalar is the primary spelling; the underscore form (`orders.slots_default`-style) is an accepted alias (f04 O3) | LIVE [S17]; default and tier3 PROPOSED | f04 |
| `orders.duration` | 604,800 s | PROPOSED | f04 |
| `orders.blacklist` | amethyst items | LIVE [S9] | f04 |
| `orders.sorts` | `{most_per_item, most_paid, recently_listed}` | **OBSERVED** [F0180] | f04 |
| `orders.default_amount` | 1 | **OBSERVED** [F0199] | f04 |
| `orders.allow_self_delivery` | false | PROPOSED | f04 |
| `orders.page_size` | 45 | PROPOSED | f04 |
| `orders.min_price` | $1 | PROPOSED | f04 |
| `orders.flush_interval` | 10 s | PROPOSED | f04 |
| `orders.expire_check_interval` | 60 s | PROPOSED | f04 |
| `quickbuy.price_guard` | 3.0 | LIVE [S7] | f05 |
| `quickbuy.max_entries` | 45 | PROPOSED | f05 |
| `quickbuy.page_size` | 45 | PROPOSED | f05 |
| `shards.interval` | 600 s | LIVE [S8] | f06 |
| `shards.require_activity` | false — inert (V-61 closed, D8 2026-09-24); still read, never enabled | PROPOSED | f06 |
| `shards.transferable` | false | PROPOSED | f06 |
| `shards.flush_interval` | 30 s | PROPOSED | f06 |
| `amethyst.lifetime` | 86,400 s | LIVE [S9] | f06 |
| `amethyst.felling_limit` | 512 | PROPOSED | f06 |
| `amethyst.sweep_interval` | 300 s | PROPOSED | f06 |
| `amethyst.haste_level` | 2 | PROPOSED | f06 |
| `amethyst.haste_duration` | 86,400 s | PROPOSED | f06 |
| `shardshop.offers` | table above | LIVE [S8] | f06 |
| `spawners.r` | 6 kills per minute | PROPOSED | f07 |
| `spawners.C.skeleton` | 1505.35 | LIVE [S24] | f07 |
| `spawners.C` | per-type compound list (`<type>=<C>`, e.g. `skeleton=1505.35`; defaults in `types.lua`) | PROPOSED | f07 |
| `spawners.timer_interval` | 60 s | PROPOSED | f07 |
| `spawners.accrual_mode` | `active_only` | PROPOSED | f07 |
| `spawners.offline_cap_hours` | 24 | PROPOSED | f07 |
| `spawners.stack_mode` | `all` | LIVE [S24] | f07 |
| `spawners.storage.per_spawner` | 2,880 | PROPOSED | f07 |
| `spawners.storage.hard_cap` | 2,147,483,647 | PROPOSED | f07 |
| `spawners.xp.per_spawner_cap` | 2,000 | PROPOSED | f07 |
| `spawners.require_silk_touch` | true | CLONE [C3] | f07 |
| `spawners.sneak_break_max` | 64 | CLONE [C3] | f07 |
| `spawners.open_requires_access` | false | PROPOSED | f07 |
| `spawners.blast_immune` | true | PROPOSED | f07 |
| `spawners.convert_natural` | false | PROPOSED | f07 |
| `spawners.hopper_extraction` | false | PROPOSED | f07 |
| `spawners.enable_creeper` | true | PROPOSED | f07 |
| `spawners.acquisition` | `{shard_shop = false, crates = false, natural = false, admin = true}` | LIVE [S10] | f07 |
| `spawners.acquisition.shard_shop`, `spawners.acquisition.crates`, `spawners.acquisition.natural`, `spawners.acquisition.admin` | false, false, false, true | LIVE [S10] | f07 |
| `smp_tp.tp.warmup` | 5 s | CLONE [C7] | f08 |
| `smp_tp.tp.cancel_move_distance` | 1 node | PROPOSED | f08 |
| `smp_tp.tp.confirm_menu` | true | CLONE [C1] | f08 |
| `smp_tp.tp.back_enabled` | false | PROPOSED | f08 |
| `rtp.cooldown_default`, `rtp.cooldown_tier1`, `rtp.cooldown_tier2`, `rtp.cooldown_tier3`, `rtp.cooldown_media` | `{default = 60, tier1 = 30}` s | PROPOSED | f08 |
| `smp_tp.rtp.min_radius`, `smp_tp.rtp.max_radius` | 500; the border minus 500 | PROPOSED | f08 |
| `smp_tp.rtp.scan.overworld` | y from −32 to 256 | PROPOSED | f08 |
| `smp_tp.rtp.scan.nether` | `mg_nether_min` to below `mg_bedrock_nether_top_max` | PROPOSED | f08 |
| `smp_tp.rtp.scan.end` | `mg_end_min` to `mg_end_min + 128` | PROPOSED | f08 |
| `smp_tp.rtp.max_attempts` | 10 | PROPOSED | f08 |
| `smp_tp.rtp.menu_enabled` | false (menu removed 15 June 2026) | LIVE [S14] | f08 |
| `smp_tp.rtp.zone_delay` | 3 s | PROPOSED | f08 |
| `smp_tp.rtp.regions` | `{}` | PROPOSED | f08 |
| `smp_tp.rtpqueue.timeout` | 300 s | PROPOSED | f08 |
| `smp_tp.rtpqueue.min_separation` | 16 nodes | PROPOSED | f08 |
| `smp_tp.rtpqueue.max_separation` | 32 nodes | PROPOSED | f08 |
| `smp_tp.tpa.expiry` | 60 s | PROPOSED | f08 |
| `homes.slots_default`, `homes.slots_tier1`, `homes.slots_tier2`, `homes.slots_tier3` | `{default = 2, tier1 = 9, tier2 = 27, tier3 = 90}` | LIVE [S17]; default LEGACY [S25] | f09 |
| `smp_tp.homes.name_max` | 32 | PROPOSED | f09 |
| `smp_tp.homes.tabs_before_more` | 3 | **OBSERVED** [F0061] | f09 |
| `smp_tp.homes.default_icon` | bed | **OBSERVED** [F0066] | f09 |
| `smp_tp.homes.delete_confirm` | true | PROPOSED | f09 |
| `combat.tag_seconds` | 20 | PROPOSED | f10 |
| `combat.blocked_commands` | list in f10 | LIVE [S7][S27] and PROPOSED | f10 |
| `combat.disable_elytra` | false | PROPOSED | f10 |
| `combat.keep_pearls_on_death` | false | LIVE [S20] | f10 |
| `combat.log_broadcast` | true | PROPOSED | f10 |
| `combat.explosion_window` | 10 s | PROPOSED | f10 |
| `combat.explosion_radius` | 12 nodes | PROPOSED | f10 |
| `bounty.min_amount` | $1,000 | PROPOSED | f10 |
| `bounty.pair_cooldown` | 3,600 s | PROPOSED | f10 |
| `chat.format` | `<@1> @2` | **OBSERVED** [F0269] | f11 |
| `chat.rank_prefix` | false | PROPOSED | f11 |
| `chat.rate_limit` | 1 per second | PROPOSED | f11 |
| `chat.duplicate_filter` | true | PROPOSED | f11 |
| `social.max_follows` | 200 | PROPOSED | f11 |
| `social.friend_notify` | true | PROPOSED | f11 |
| `social.tpa_hint` | true | **OBSERVED** in substituted form [F0270] | f11 |
| `findplayer.spawn_radius` | 512 | PROPOSED | f11 |
| `findplayer.region_band` | 2048 | PROPOSED | f11 |
| `info.help`, `info.rules`, `info.discord`, `info.media`, `info.link`, `info.store`, `info.website`, `info.ranks`, `info.medal` | `""` (unset; the screen shows `This text is not configured`) | PROPOSED | f11 |
| `settings.cycle_order` | `{ON, FRIENDS_FOLLOWED, OFF}` | PROPOSED | f12 |
<!-- struck: D3, 2026-09-24 — structure registered in code, not a config key -->
| `ranks.grant_days` | 30 | LIVE [S17] | f13 |
| `ranks.chat_prefix` | `""` (no prefix) | **OBSERVED** by absence [F0269] — see V-24 | f13 |
| `ranks.expiry_check_interval` | 3,600 s | PROPOSED | f13 |
| `ranks.store_text` | configurable store URL and blurb | PROPOSED | f13 |
| `leaderboards.refresh`, `leaderboards.size` | 300 s, 100 | PROPOSED | f14 |
| `scoreboard.enabled` | true | **OBSERVED** [F0287] | f14 |
| `scoreboard.title` | `server.name` | PROPOSED (observed title `Voire` unexplained, V-76) | f14 |
| `stats.persist_interval` | 60 s | PROPOSED | f14 |
| `api.mode` | `snapshot` (`off`, `snapshot`, `push`) | PROPOSED | f14 |
| `world.spawn_protect_radius` | 128 | PROPOSED | f15 |
| `world.soft_border` | true | PROPOSED | f15 |
| `world.border_margin` | 16 nodes inside `mapgen_limit` | PROPOSED | f15 |
| `world.max_accounts_per_ip` | 5 (flag only) | LIVE [S18]; enforcement PROPOSED | f15 |
| `world.staff_name_filter` | comma-separated Lua patterns — built-in default list; `""` disables | PROPOSED (added by f15) | f15 |
| `world.staff_name_action` | `flag` (`kick` and `off` supported; unknown values degrade to `flag`) | PROPOSED (added by f15) | f15 |
| `world.entity_caps` | `{}` (per-type, sized for Luanti) | PROPOSED — inert pending `V-81` | f15 |
| `world.bedrock_breakable` | false | PROPOSED — inert pending `V-82` | f15 |
<!-- struck: D8, 2026-09-24 — f16 descoped permanently -->
<!-- struck: D8, 2026-09-24 — f16 descoped permanently -->
<!-- struck: D8, 2026-09-24 — f16 descoped permanently -->
<!-- struck: D8, 2026-09-24 — f16 descoped permanently -->
