# 7. Sources

Web sources retrieved in September 2026. Donut SMP pages change often; each
entry states what it supports.

## 7.1 Video frame corpus (primary evidence, new in v0.2)

| Field | Value |
|---|---|
| Source | "How to get Started on the Donut SMP for Beginners - Updated Commands", YouTube id `k-YgSy19y7I` |
| Duration | 5:05 |
| Extraction | 1 fps, 1920×1080, 141 frames retained of 305 |
| Description model | `Qwen/Qwen2.5-VL-72B-Instruct` via vLLM, 2026-09-22 |
| Frames | `frames/frame_NNNN.jpg` |
| Descriptions | `frame_descriptions_vlm.{md,csv,json}` |
| Subtitles | `topics.md`, `*.en.srt`, `*.en-orig.srt` |
| Client shown | Lunar Client, `Version 1.21.11 (v2.22.23-2630)` |

Cited as `[F0242]`. Reliability caveats are normative and are in
`00-conventions.md §0.3.1` — read them before relying on a single-frame string.

### Segment map

| Segment | Time | Frames | Spec file |
|---|---|---:|---|
| Intro, joining the server | 00:00:00 | — | — |
| `/rtp` | 00:00:21 | 1 | f08 |
| `/sethome` + `/homes` | 00:00:43 | 12 | f09 |
| `/pay` | 00:01:27 | 4 | f01 |
| `/sell` | 00:01:31 | 7 | f02 |
| `/ah` browse and search | 00:01:47 | 15 | f03 |
| `/ah` listing your own items | 00:02:07 | 13 | f03 |
| `/orders` fulfilling | 00:02:34 | 16 | f04 |
| `/orders` creating | 00:03:04 | 31 | f04 |
| `/settings` | 00:03:51 | 19 | f12 |
| `/msg` + `/ignore` | 00:04:27 | 23 | f11 |
| Outro | 00:05:04 | — | — |

## 7.2 Donut SMP, official and community

- [S1] DonutSMP Wiki, "About DonutSMP": server type, gameplay, regions, seasons, planned border. https://donutsmp.wiki/about-donutsmp
- [S2] DonutSMP Wiki, "Big June Update" (9 to 29 June 2026). https://donutsmp.wiki/big-june-update
- [S3] DonutSMP Wiki, "Selling". https://donutsmp.wiki/selling
- [S4] DonutSMP Wiki, "Sell Routing". https://donutsmp.wiki/sell-routing
- [S5] DonutSMP Wiki, "Auction House". https://donutsmp.wiki/auction-house
- [S6] DonutSMP Wiki, "Orders". https://donutsmp.wiki/orders
- [S7] DonutSMP Wiki, "Quick Buy" and "Shop Command". https://donutsmp.wiki/quick-buy and https://donutsmp.wiki/shop-command
- [S8] DonutSMP Wiki, "Shards". https://donutsmp.wiki/shards
- [S9] DonutSMP Wiki, "Amethyst Items". https://donutsmp.wiki/amethyst-items
- [S10] DonutSMP Wiki, "Spawners". https://donutsmp.wiki/spawners
- [S11] DonutSMP Wiki, "Crates" (archived). https://donutsmp.wiki/crates
- [S12] DonutSMP Wiki, "Teams" (removed). https://donutsmp.wiki/teams
- [S13] DonutSMP Wiki, "Duels" (removed). https://donutsmp.wiki/duels
- [S14] DonutSMP Wiki, "Random Teleportation". https://donutsmp.wiki/random-teleportation
- [S15] DonutSMP Wiki, "RTP Queue". https://donutsmp.wiki/rtp-queue
- [S16] DonutSMP Wiki, "Home Commands". https://donutsmp.wiki/home-commands
- [S17] DonutSMP Wiki, "Donut+ Membership". https://donutsmp.wiki/donut-membership
- [S18] DonutSMP Wiki, "Server Rules". https://donutsmp.wiki/server-rules
- [S19] DonutSMP Wiki, "PvP". https://donutsmp.wiki/pvp
- [S20] DonutSMP Wiki, "Settings". https://donutsmp.wiki/settings
- [S21] DonutSMP Wiki, category "Mechanics". https://donutsmp.wiki/category/mechanics
- [S22] DonutSMP Wiki, category "Events". https://donutsmp.wiki/category/events
- [S23] DonutSMP Public API definition (Swagger 2.0). https://api.donutsmp.net/doc.json
- [S24] Donut Today wiki: command list, spawner guide, getting-started tips. Read through search-engine excerpts; the site blocks automated fetching. https://donut.today/wiki/commands
- [S25] Earlier Fandom wikis: commands, default homes, RTP menu, crates warp, spawner types. https://donutsmpmc.fandom.com/wiki/Commands
- [S26] Third-party teleport guides citing the Donutpedia command reference. https://www.cloudspress.com/how-to-tp-in-donut-smp/
- [S27] DonutSMP Wiki, former "Random Teleport (/rtp)" page. Read through a search-engine excerpt; now HTTP 404. https://donutsmp.wiki/rtp
- [S28] Community short videos demonstrating `/nightvision` and `/nv`. https://www.tiktok.com/discover/tutorial-on-how-to-use-the-command-on-donut-smp

## 7.3 Clone plugins (not authoritative for Donut SMP)

- [C1] DonutSMPCore documentation. https://opmasterleo.github.io/DonutSMPCore/
- [C2] UltimateDonutSMP wiki. https://github.com/BeestoXd/UltimateDonutSMP/wiki
- [C3] DonutSpawner (DonutSMP-Remake). https://github.com/DonutSMP-Remake/DonutSpawner
- [C4] RTPQueuePro. https://modrinth.com/mod/rtpqueuepro
- [C5] DonutShop. https://modrinth.com/plugin/donutshop
- [C6] zBounty (DonutBounty). https://builtbybit.com/resources/zbounty.83070/
- [C7] DonutSMP-RTP. https://modrinth.com/mod/donutsmp-rtp
- [C8] PlainBase teleport module (RTP blacklist). https://github.com/j-gaertig/PlainBase/wiki/Module-Teleport

## 7.4 Engine and game

- [M1] Mineclonia source, GitHub mirror at commit `5bdce566` (21 September 2026). https://github.com/mineclonia-mirror/mineclonia

## 7.5 Tools and videos

- [T1] DonutStats (independent statistics and price tools). https://donutstats.net/ and https://www.donutstats.net/prices/calculator
- [V1] Official Big June Update showcase video [S2]. https://www.youtube-nocookie.com/embed/UXSZmPyCw00
- [V2] Official demonstration of the `/sell` changes [S2]. https://www.youtube.com/watch?v=zVahADWQxI8
- [V3] **The frame corpus source** (§7.1). https://www.youtube.com/watch?v=k-YgSy19y7I
