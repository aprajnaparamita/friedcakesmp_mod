# 5. Command Reference

**Integrator-maintained mirror.** Commands are declared in feature files
(section 2). Do not hand-edit this table; change your feature file and flag it.

Luanti's built-in `/msg` is replaced with `core.override_chatcommand`; the
built-in `/teleport` is left to staff, and `/tp` is registered separately as a
request alias (`f08`). Commands blocked during combat are listed in `f10`.

## 5.1 Economy

| Command | Aliases | Arguments | Behaviour | Status | Spec |
|---|---|---|---|---|---|
| `/bal` | `/balance`, `/money` | `[player]` | Show a money balance (another player's balance is `PROPOSED`) | LIVE [S24] | f01 |
| `/pay` | — | `<player> <amount>` | Transfer money. Tab-completes player names [F0089] | **OBSERVED** [F0088–F0090] | f01 |
| `/paytoggle` | `/paymenttoggle` | — | Toggle receiving payments | CLONE [C1] | f01 |
| `/baltop` | `/moneytop` | `[page]` | Money leaderboard | LIVE [S24] | f14 |
| `/sell` | — | — | Open the `Sell` container | **OBSERVED** [F0092–F0096] | f02 |
| `/sell hand`, `/sell all` | — | — | Sell the held stack or the whole inventory | CLONE [C1] | f02 |
| `/sellhistory` | — | `[page]` | Past server sales | LIVE [S3] | f02 |
| `/worth` | — | `[item]` | Show a base price | CLONE [C1] | f02 |
| `/ah` | `/auction`, `/auctionhouse` | `[search]` | Open or search the auction house | **OBSERVED** [F0105–F0129] | f03 |
| `/ah sell` | `/auction sell` | `<price>` | List the held stack. **The observed listing path is the `Auction > Your Items` menu, not this command** | LIVE [S5] | f03 |
| `/orders` | — | — | Open the orders board | **OBSERVED** [F0155–F0158] | f04 |
| `/order` | — | `[search]` | Search orders | LIVE [S6] | f04 |
| `/shop` | — | — | Quick Buy | LIVE [S7] | f05 |
| `/shards` | `/shard` | — | Shard balance | CLONE [C1] | f06 |
| `/bounty` | `/bounties` | `[player]` | Bounty list, or one player's bounty | LIVE [S24] | f10 |
| `/bounty add` | — | `<player> <amount>` | Place or raise a bounty | LIVE [S24] | f10 |

## 5.2 Teleportation

| Command | Aliases | Arguments | Behaviour | Status | Spec |
|---|---|---|---|---|---|
| `/rtp` | — | `[dimension or region]` | Random teleport | **OBSERVED** [F0037] | f08 |
| `/rtpqueue` | — | — | Join or leave the paired random-teleport queue | LIVE, beta [S15] | f08 |
| `/tpa` | `/tp` | `<player>` | Ask to teleport to a player | LIVE [S26] | f08 |
| `/tpahere` | — | `<player>` | Ask a player to teleport to you | LIVE [S26] | f08 |
| `/tpaccept` | — | `<player>` | Accept a request (argument-free form is `PROPOSED`) | LIVE [S26] | f08 |
| `/tpadeny` | `/tpdeny` | `<player>` | Deny a request | LIVE [S26]; alias CLONE [C1] | f08 |
| `/tpacancel` | — | `[player]` | Cancel an outgoing request | LIVE [S26] | f08 |
| `/tpauto` | — | — | Toggle automatic acceptance | LIVE [S26] | f08 |
| `/tpatoggle`, `/tpaheretoggle` | — | — | Toggle receiving each request type | CLONE [C1] | f08 |
| `/homes` | `/home` | `[id]` | Homes menu, or teleport to a home | **OBSERVED** [F0055, F0061] | f09 |
| `/sethome` | — | `[name]` | Save the current position as a home | **OBSERVED** [F0055] | f09 |
| `/delhome` | — | `<id>` | Delete a home | LIVE [S24] | f09 |
| `/spawn` | — | `[lobby]` | Spawn-lobby menu, or a named lobby | LIVE [S26] | f08 |
| `/warp` | — | `<location>` | Teleport to a spawn utility location | LIVE [S26] | f08 |
| `/world` | — | — | Return to the position before the last teleport command | LIVE [S26] | f08 |
| `/back` | `/return` | — | Previous location; disabled by default | CLONE [C1] | f08 |

> **Observed spelling.** The player types `/homes` [F0055], and the menu that
> opens is titled `Homes` [F0061]. v0.1 listed `/home` as primary with `/homes`
> as the alias. Both exist; the plural is the observed primary.

## 5.3 Social, information and utility

| Command | Aliases | Arguments | Behaviour | Status | Spec |
|---|---|---|---|---|---|
| `/msg` | `/message`, `/tell`, `/w`, `/whisper`, `/pm` | `<player> <message>` | Private message | **OBSERVED** [F0271, F0280] | f11 |
| `/r` | `/reply` | `<message>` | Reply to the last private message | CLONE [C1] | f11 |
| `/ignore` | — | `<player>` | Ignore a player | **OBSERVED** [F0282, F0283, F0287] | f11 |
| `/block` | — | `<player>` | Block a player | LIVE [S24] | f11 |
| `/friend` | `/friends` | `[list, friends, followers, following, search, addsearch]` | Follow and friends system | LIVE [S24] | f11 |
| `/findplayer` | `/fp` | `<player>` | Coarse location of a player | LIVE [S23][S24] | f11 |
| `/stats` | — | `[player]` | Statistics menu | LIVE [S23] | f14 |
| `/leaderboard` | `/lb`, `/leaderboards` | `[category]` | Leaderboards | LIVE [S24] | f14 |
| `/settings` | — | — | Settings menu | **OBSERVED** [F0234–F0236] | f12 |
| `/nightvision` | `/nv` | — | Toggle night vision | LIVE [S28] | f11 |
| `/kill` | — | — | Drop items and respawn, after confirmation | LIVE [S24]; confirmation CLONE [C1] | f11 |
| `/help`, `/rules` | — | — | Information screens | LIVE [S24] | f11 |
| `/discord`, `/media`, `/link`, `/buy`, `/website`, `/ranks`, `/medal` | `/store` (for `/buy`) | — | Informational and external links | LIVE [S24][S2] | f11, f13 |
| `/api` | — | `[delete]` | Issue or revoke a personal API key | LIVE [S23][S24] | f14 |
| `/ping`, `/list` | `/who`, `/online` (for `/list`) | — | Latency; online players | CLONE [C1] | f11 |
| `/report`, `/helpop` | `/ac` (for `/helpop`) | `<player> <reason>`; `<message>` | Reports and messages to staff | CLONE [C1] | f11 |

## 5.4 Legacy (optional modules)

| Command | Aliases | Arguments | Behaviour | Status | Spec |
|---|---|---|---|---|---|
| `/afk` | — | — | Teleport to the AFK zone | LEGACY [S24][S8] | f16 |
| `/team` | — | subcommands in f16 | Teams | LEGACY [S12] | f16 |
| `/duel` | — | `<player>`; `draw <player>` | Duels | LEGACY [S13] | f16 |
| `/warp crates`, `/crates` | — | — | Crates | LEGACY [S11][S25]; `/crates` CLONE [C1] | f16 |

## 5.5 Administration

All entries are `PROPOSED` except `/eco`, which follows a clone [C1].

| Command | Arguments | Purpose | Spec |
|---|---|---|---|
| `/eco` | `give`, `take`, `set` or `reset` `<player> <amount>` | Adjust money | f01 |
| `/shardsadmin` | `give`, `take` or `set` `<player> <amount>` | Adjust shards | f06 |
| `/rank` | `set <player> <tier> <days>`; `clear <player>` | Grant or clear tiers | f13 |
| `/spawner` | `give <player> <type> [count]` | Issue spawner items | f07 |
| `/ahadmin`, `/orderadmin` | `remove <id>` | Remove a listing or order, with refund | f03, f04 |
| `/bountyadmin` | `clear <player>` | Remove a bounty, with refund | f10 |
| `/combat` | `untag <player>` | Clear a combat tag | f10 |
| `/ledger` | `<player> [page]` | Audit trail | f01 |
| `/smp` | `reload` | Reload configuration | f01 |
| `/mute` | `<player> [seconds]` | Mute a player (moderation); omitted duration = permanent | f11 |
| `/unmute` | `<player>` | Clear a mute | f11 |

Privileges `smp_admin` (all administration) and `smp_moderator` (read-only
audit, mutes) are registered with `core.register_privilege`.

## 5.6 Unknown-command response

The reference server answers an unrecognised command with
`This command does not exist` [F0055]. Luanti's default is
`Invalid command: <name>`. Override it to match (`f11`).

A malformed command produces the vanilla client parser error
`Unknown or incomplete command. See below for error at position 1: /<--[HERE]`
[F0055] — that string is generated **client-side by Minecraft** and has no
server equivalent. Do not reproduce it.
