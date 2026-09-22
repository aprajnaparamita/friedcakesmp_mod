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
| `sell.multiplier` | 1.0 (Donut used a temporary 3.0 [S2]) | PROPOSED | f02 |
| `sell.mode` | `button` | **OBSERVED** [F0094] | f02 |
| `sell.history_size` | 100 | PROPOSED | f02 |
| `sell.meta_exempt` | amethyst items | PROPOSED | f02 |
| `ah.slots` | `{default = 9, tier1 = 45, tier2 = 90, tier3 = 90}` | LIVE [S17]; default and tier3 PROPOSED | f03 |
| `ah.listing_duration` | 172,800 s | PROPOSED | f03 |
| `ah.listing_fee_pct`, `ah.sale_tax_pct` | 0, 0 | PROPOSED | f03 |
| `ah.min_price`, `ah.max_price` | $1, $10¹² | PROPOSED | f03 |
| `ah.page_size` | 45 | PROPOSED | f03 |
| `ah.sorts` | `{lowest_price, highest_price, recently_listed}` | **OBSERVED** [F0118] | f03 |
| `ah.history` | 100 per page, 10 pages | LIVE [S23] | f03 |
| `orders.slots` | `{default = 9, tier1 = 45, tier2 = 90, tier3 = 90}` | LIVE [S17]; default and tier3 PROPOSED | f04 |
| `orders.duration` | 604,800 s | PROPOSED | f04 |
| `orders.blacklist` | amethyst items | LIVE [S9] | f04 |
| `orders.sorts` | `{most_per_item, most_paid, recently_listed}` | **OBSERVED** [F0180] | f04 |
| `orders.default_amount` | 1 | **OBSERVED** [F0199] | f04 |
| `quickbuy.price_guard` | 3.0 | LIVE [S7] | f05 |
| `quickbuy.max_entries` | 45 | PROPOSED | f05 |
| `shards.interval` | 600 s | LIVE [S8] | f06 |
| `shards.require_activity` | false | PROPOSED | f06 |
| `amethyst.lifetime` | 86,400 s | LIVE [S9] | f06 |
| `amethyst.felling_limit` | 512 | PROPOSED | f06 |
| `amethyst.sweep_interval` | 300 s | PROPOSED | f06 |
| `spawners.r` | 6 kills per minute | PROPOSED | f07 |
| `spawners.C.skeleton` | 1505.35 | LIVE [S24] | f07 |
| `spawners.timer_interval` | 60 s | PROPOSED | f07 |
| `spawners.accrual_mode` | `active_only` | PROPOSED | f07 |
| `spawners.stack_mode` | `all` | LIVE [S24] | f07 |
| `spawners.storage.per_spawner` | 2,880 | PROPOSED | f07 |
| `spawners.storage.hard_cap` | 2,147,483,647 | PROPOSED | f07 |
| `spawners.xp.per_spawner_cap` | 2,000 | PROPOSED | f07 |
| `spawners.require_silk_touch` | true | CLONE [C3] | f07 |
| `spawners.sneak_break_max` | 64 | CLONE [C3] | f07 |
| `spawners.open_requires_access` | false | PROPOSED | f07 |
| `spawners.blast_immune` | true | PROPOSED | f07 |
| `spawners.convert_natural` | false | PROPOSED | f07 |
| `spawners.acquisition` | `{shard_shop = false, crates = false, natural = false, admin = true}` | LIVE [S10] | f07 |
| `tp.warmup` | 5 s | CLONE [C7] | f08 |
| `tp.cancel_move_distance` | 1 node | PROPOSED | f08 |
| `tp.confirm_menu` | true | CLONE [C1] | f08 |
| `rtp.cooldown` | `{default = 60, tier1 = 30}` s | PROPOSED | f08 |
| `rtp.min_radius`, `rtp.max_radius` | 500; the border minus 500 | PROPOSED | f08 |
| `rtp.scan.overworld` | y from −32 to 256 | PROPOSED | f08 |
| `rtp.scan.nether` | `mg_nether_min` to below `mg_bedrock_nether_top_max` | PROPOSED | f08 |
| `rtp.scan.end` | `mg_end_min` to `mg_end_min + 128` | PROPOSED | f08 |
| `rtp.max_attempts` | 10 | PROPOSED | f08 |
| `rtp.menu_enabled` | false (menu removed 15 June 2026) | LIVE [S14] | f08 |
| `rtp.zone_delay` | 3 s | PROPOSED | f08 |
| `rtpqueue.timeout` | 300 s | PROPOSED | f08 |
| `rtpqueue.separation` | 16 to 32 nodes | PROPOSED | f08 |
| `tpa.expiry` | 60 s | PROPOSED | f08 |
| `homes.slots` | `{default = 2, tier1 = 9, tier2 = 27, tier3 = 90}` | LIVE [S17]; default LEGACY [S25] | f09 |
| `homes.name_max` | 32 | PROPOSED | f09 |
| `homes.tabs_before_more` | 3 | **OBSERVED** [F0061] | f09 |
| `homes.default_icon` | bed | **OBSERVED** [F0066] | f09 |
| `combat.tag_seconds` | 20 | PROPOSED | f10 |
| `combat.blocked_commands` | list in f10 | LIVE [S7][S27] and PROPOSED | f10 |
| `combat.disable_elytra` | false | PROPOSED | f10 |
| `combat.keep_pearls_on_death` | false | LIVE [S20] | f10 |
| `bounty.min_amount` | $1,000 | PROPOSED | f10 |
| `bounty.pair_cooldown` | 3,600 s | PROPOSED | f10 |
| `chat.format` | `<@1> @2` | **OBSERVED** [F0269] | f11 |
| `chat.rate_limit` | 1 per second | PROPOSED | f11 |
| `settings.categories` | `{chat, notifications, pvp, visuals, privacy, scoreboard, general}` | **OBSERVED** [F0237] | f12 |
| `leaderboards.refresh`, `leaderboards.size` | 300 s, 100 | PROPOSED | f14 |
| `scoreboard.enabled` | true | **OBSERVED** [F0287] | f14 |
| `store.flush_interval` | 10 s | PROPOSED | shared §2.2 |
| `world.spawn_protect_radius` | 128 | PROPOSED | f15 |
| `legacy.keyall_interval` | 3,600 s | LEGACY [S11] | f16 |
| `legacy.afk_shards_per_min` | 1 | LEGACY [S8] | f16 |
| `legacy.team_max_members` | 50 | LEGACY [S12] | f16 |
| `legacy.kill_shards` | 10 | LEGACY [S8] | f16 |
