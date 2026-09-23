# FriedcakeSMP — Manual Test Guide

End-to-end verification of the merged mod set, for a human session. The
headless checks in §1 are fast and must pass before anything else; the
feature walkthroughs in §3 then exercise the pack in-game with **two
accounts** (two client instances on one machine, or a client on each of two
machines).

| Section | What it covers |
|---|---|
| [0. One-time setup](#0-one-time-setup) | Engine, game, modpack install, world, configuration, staff privileges |
| [1. Automated checks](#1-automated-checks) | Headless dev tests and the in-game acceptance tests |
| [2. How to read the expectations](#2-how-to-read-the-expectations) | Money units, formatter styles, verbatim strings |
| [3. Feature walkthrough](#3-feature-walkthrough) | f01–f15, one subsection per feature area |
| [4. Checklist](#4-checklist) | Sign-off list |
| [5. Reporting a failure](#5-reporting-a-failure) | Where a failure goes and how to file it |

---

## 0. One-time setup

### 0.1 Boot status

**The P0 boot blockers are fixed** (2026-09-23). The audit found two classes
of nonexistent-engine-API call (`core.register_on_globalstep`,
`core.modpath`) that would have aborted mod loading, plus f09 homes being
unwired; all three were corrected, and the dev-test harnesses now stub the
correct API names so the bug cannot silently return. If a world still fails
to start, check the server log for `[smp_*]` load errors and file it as a
new defect (see §5) rather than assuming the old blocker. Current merge and
remediation state is in `INTEGRATION.md` and
`SPEC-CONFORMANCE-REPORT.md` §"Remediation applied".

### 0.2 Engine, game and user directory

| Component | Location |
|---|---|
| Luanti engine (5.17.0) | `~/dev/luanti` — binary at `~/dev/luanti/bin/luanti` |
| Mineclonia game | `~/dev/mineclonia-git` — linked into the engine as `~/dev/luanti/games/mineclonia` |
| Engine user directory (macOS) | `~/Library/Application Support/minetest` — holds `worlds/`, `minetest.conf` and any mods installed for the user |

Sanity check:

```sh
~/dev/luanti/bin/luanti --gameid list
# devtest, mineclone2, mineclonia, minetest
```

### 0.3 Install the modpack

Choose one of the three options; **A is recommended for a test session**
because it touches nothing outside the test world.

**A — world-local (recommended).** Mods placed in a world's `worldmods/`
directory are always enabled, and a directory containing `modpack.conf` is
expanded automatically — no `enable_modpack` key exists in the engine and
none is required.

```sh
ln -s /path/to/coconut/friedcake "<world path>/worldmods/friedcake"
```

**B — game-wide.** Loads the pack into every Mineclonia world:

```sh
ln -s /path/to/coconut/friedcake ~/dev/mineclonia-git/mods/friedcake
```

**C — user install.** Copy `friedcake/` into
`~/Library/Application Support/minetest/mods/` and enable each mod in the
world configuration screen; the world configuration writes
`load_mod_<modname> = true` into that world's `world.mt`.

### 0.4 Create a test world

From the main menu: **Create World** → game *Mineclonia* → name it
`friedcake-test`. A dedicated world keeps the run reproducible; the existing
Mineclonia worlds on this machine (`2b2t Museum TEST`, `9b9t clone`) carry
third-party world mods of their own.

The engine's world rules (spawn protection, soft border, accounts per IP,
anticheat) are documented in `friedcake/minetest.conf.example`; the mapping
from each reference-server rule to its engine setting is explained in
`friedcake/WORLD_RULES.md`.

### 0.5 Server configuration

Add to the server's `minetest.conf` (or the world's), at minimum:

```
secure.trusted_mods = smp_store
server.name = FriedcakeSMP
```

Notes:

- `secure.trusted_mods` is only needed for the SQLite/Postgres storage
  backend. The default `store.backend = auto` falls back to `mod_storage`,
  so an unconfigured world runs without it.
- `secure.http_mods = smp_store` is only needed once the Postgres backend
  ships; it is deliberately commented out in `friedcake/minetest.conf.example`.
- `server.name` is the pack's own display-name key (settings menu subtitle,
  scoreboard title). The engine's own key is `server_name` — the two are not
  aliased.
- Copy any further keys from `friedcake/minetest.conf.example` as required by
  the world-rule checks in §3.13.

### 0.6 Staff privileges

The admin-side commands (`/eco`, `/ledger`, `/rank`, `/smp test …`) need the
`smp_admin` privilege:

```
/grant <name> all
```

Run it from a second client or from the server console.

---

## 1. Automated checks

### 1.1 Headless dev tests (no server required)

From the repository root:

```sh
tools/agent-flow.sh test
```

Expected: `[agent-flow] all dev-tests green` — 20 suites, each printing
`ALL OK` and exiting 0. A single suite runs the same way:

```sh
luajit friedcake/dev-tests/test_ah.lua
```

Coverage per suite is listed in `friedcake/dev-tests/README.md`.

### 1.2 In-game acceptance tests

`/smp test <target>` (privilege `smp_admin`). Targets wired to the
dispatcher today:

| Target | Aliases | Covers |
|---|---|---|
| `smp_core` | empty target also works | formatter, parser, menu sessions, f01 T1–T3, store smoke |
| `smp_ah` | `ah`, `f03` | auction house T1–T10 |
| `smp_sell` | `sell`, `f02` | selling suite |
| `smp_quickbuy` | `quickbuy` | Quick Buy suite, including the 3× price guard |

Each prints `Passed: N` / `Failed: 0`.

Every other mod ships `mods/<mod>/test.lua` but is **not** registered with
the dispatcher yet; `/smp test smp_<mod>` answers
`Unknown test target: …` until the integrator adds the generic test
registry. Run those suites headlessly in the meantime (§1.1).

---

## 2. How to read the expectations

- **Amounts you type are dollars, not cents.** `smp_core.parse_amount`
  accepts `10`, `10.50`, `250k`, `1.5M` (case-insensitive) and converts to
  cents; storage is always cents. `/eco give alice 10k` therefore grants
  **$10,000**, and `/pay bob 1000` moves **$1,000**.
- **Two money renderings** (shared §0.6):
  - *inline*, no space — `$700`, `$5.1K` — used inside auction and orders
    result lines (`You listed … for $100`).
  - *body*, with a space — `$ 700`, `$ 5.1K` — used by economy chat lines
    (`/bal`, `/eco`, `/ledger`, `/baltop`, `/bounty`).
- **Money suffixes are upper-case** (`K`, `M`, `B`, `T`); plain quantities
  use lower-case (`753k`, `1.3m`) via `smp_core.fmt_qty` — the scoreboard
  and `/shards` use that form.
- **Strings in `backticks` are verbatim**, punctuation included:
  `Cancel!`, `Auction > Your Items`, `Orders -> Deliver Items`,
  `Choose Item (1 results)`. Do not "correct" them — an exact match is the
  expected result.
- Walkthrough examples use `alice` (staff) and `bob`.

---

## 3. Feature walkthrough

Two accounts make the paired checks (pay, buy, teleport request, bounty)
possible; single-player checks can be run first.

### 3.1 Economy (f01) — `smp_economy`

| Command | Expected |
|---|---|
| `/bal` | `Your balance: $ 0` on a fresh account |
| `/eco give alice 10k` | `Gave $ 10K to alice (capped $ 10K).` — alice's `/bal` now reads `$ 10K` |
| `/pay bob 1000` | alice: `You paid bob $ 1K.`; bob: `You received $ 1K from alice.` — balances move by $1,000 |
| `/pay alice 100` | refused — `You cannot pay yourself.` |
| `/pay nobody 100` | refused — `Player nobody does not exist.` |
| `/paytoggle` | `You now accept payments.` / `You no longer accept payments.`; `/pay` to a toggled-off recipient is refused with `bob is not accepting payments.` |
| `/baltop` | header `--- Money Top (page 1/1) ---`, then rows `1. alice — $ 10K` |
| `/ledger alice` | audit lines `#<id>  <date>  <type>  <amount>  <ref>` |

Formatter spot-check (§2): `/bal` and `/ledger` use the body style
(`$ 10K`), auction result lines use the inline style (`$100`), and plain
quantities stay lower-case (`753k`).

### 3.2 Auction house (f03) — `smp_ah`

Run this before §3.3 — Quick Buy reads live listings from the auction house.

| Action | Expected |
|---|---|
| `/ah` | `Auction (Page 1)` container menu |
| hold an item, `/ah sell 100` | `You listed 1 <item> for $100` |
| `/ah` → click the sign | `Search Auction` prompt; `diamon` filters to diamonds |
| click the hopper | `Filter` tooltip lists `Lowest Price`, `Highest Price`, `Recently Listed`; the active one is highlighted and each click advances |
| `/ah` → click the chest | `Auction > Your Items` (single `>`, not `->`) |
| bob buys an alice listing | bob: `You bought 1 <item> for $ <price>`; alice: `You sold 1 <item> and received $<net>` |
| buy a listing that is already sold | `This item was already bought` |

### 3.3 Quick Buy (f05) — `smp_quickbuy`

| Action | Expected |
|---|---|
| `/shop` | `Quick Buy (Page 1)` menu |
| add an entry for an item with live `/ah` listings | shows the live lowest price (never cached across redraws) |
| buy at ≤ 3× the shown price | completes with no re-confirm screen |
| buy when the live price has jumped > 3× | warning screen (with `Cancel!`); the purchase only completes after re-confirm |

Historical note: this path used to return no listings at all. A live price
plus a completed purchase confirms the fix; it is also covered by
`dev-tests/test_quickbuy.lua` and `INTEGRATION.md` §1.

### 3.4 Orders (f04) — `smp_orders`

| Action | Expected |
|---|---|
| `/orders` | `Orders (Page 1)` container menu |
| create an order: `Your Orders` → empty slot → `Choose Item` → search → `How many?` → `Price per item?` → `Review Order` → `Create Order` | four wizard steps; `Choose Item (1 results)` keeps the ungrammatical plural; `Cancel!` keeps the exclamation mark |
| place a matching cheaper listing on `/ah` | the open order absorbs it (routing) |
| deliver: click an open order → `Orders -> Deliver Items` → drop items → `Confirm Delivery` | action bar `Delivering...`, then `You delivered 1 <item> and received $<amount>` |

Note on plurals — all three forms are correct as observed and must not be
harmonised: order tooltip `Netherite Helmets` (plural), delivery chat
`You delivered 1 Totem of Undying` (singular), confirm form
`You're delivering 1 Totems of Undying` (plural).

### 3.5 Selling (f02) — `smp_sell`

| Action | Expected |
|---|---|
| `/sell` | `Sell` container menu with the green confirm pane (bottom-right), labelled `Click to sell items` |
| drop items, click the green pane | items sold, receipt lines in chat |
| `/sell hand` | sells the held stack |
| `/sell all` | sells the whole inventory |
| `/worth mcl_core:diamond` | `Diamond: $ <price> each` (body style); an unpriced item answers `<name> has no server price` |
| `/sellhistory` | paged list of past sales |

### 3.6 Spawners (f07) — `smp_spawners`

| Action | Expected |
|---|---|
| `/spawner give alice skeleton 1` | `Gave alice 1 Skeleton Spawner`; the item lands in the inventory (or on the ground if it is full) |
| place it, right-click | menu header `Skeleton Spawner x1`, stored output and capacity shown |
| wait ≥ 60 s, reopen | stored output has increased. The node timer defaults to `spawners.timer_interval = 60`; a single skeleton spawner starts at `r = 6` virtual kills per minute and the rate rises with the number of spawners towards the published 1,505.35/min asymptote (f07 §4.3) |
| dig with a normal pick | refused — `Silk Touch is required to dig a spawner`; the node survives |
| `Sell all` in the menu | sells the stored output and shows a receipt |

No mob entities are created at any point — spawner output is virtual. Watch
the entity count while testing.

### 3.7 Teleport and homes (f08 + f09) — `smp_tp`

| Action | Expected |
|---|---|
| `/rtp` | warm-up (action bar), then a random safe location; default cooldown `rtp.cooldown_default = 60` s, 30 s for tier1 |
| move during warm-up | `Teleport cancelled` |
| `/sethome` | `Home set` |
| `/homes` | `Homes` tab row; click a tab → `Teleport`, `Change Icon`, `Rename`, `Delete` (Delete red) |
| `/homes nope` | `Home does not exist` |
| delete a home | `Home deleted` |
| `/tpa bob` | bob receives an `Accept` / `Deny` prompt |
| `/world` | returns to the pre-teleport position (once) |

f09 homes is wired into `smp_tp` and loads with the teleport framework.

### 3.8 Combat and bounty (f10) — `smp_combat` / `smp_bounty`

| Action | Expected |
|---|---|
| bob punches alice | both receive a combat tag with an action-bar countdown (default 20 s, refreshed per hit) |
| tagged player runs `/rtp` | refused — `You cannot use /rtp during combat.` |
| tagged player runs `/sell` | **allowed** — so are `/msg`, `/ah` and `/bounty` |
| other blocked while tagged | `/rtpqueue`, `/tpa`, `/tp`, `/tpahere`, `/tpaccept`, `/homes`, `/home`, `/spawn`, `/warp`, `/world`, `/shop` |
| tagged player disconnects | inventory drops at the logout spot; chat broadcast `alice has logged out during combat.` |
| `/bounty alice` | `<name>'s bounty: $ <amount>`, or `<name> has no bounty.` |
| `/bounty add alice 5000` | `You added $ 5K to alice's bounty. New total: $ 5K.` — **$5,000** is escrowed (default minimum is `$ 1K`) |
| bob kills alice | server-wide `bob claimed the $ 5K bounty on alice.` |

### 3.9 Social (f11) — `smp_social`

| Action | Expected |
|---|---|
| chat | `<Name> message` — angle brackets, **no rank prefix** |
| `/msg bob hi` | private message line |
| `/ignore bob` | `You are now ignoring bob`; bob's chat and teleports to you are refused |
| `/msg <stranger>` (privacy set to Friends/Followed) | `This user only accepts messages from friends or followed players` |
| `/findplayer alice` | three lines — `Name: …`, `Rank: …`, `Location: …`. Location is only `Offline`, `Spawn`, or `<Dimension> – <Region>` with a coarse region (`Center`, `North`, `South`, `East`, `West`, `North-East`, …, en dash); **never exact coordinates** |
| typo a command | `This command does not exist` |

### 3.10 Settings (f12) — `smp_settings`

| Action | Expected |
|---|---|
| `/settings` | seven categories, in order: Chat, Notifications, PvP, Visuals, Privacy, Scoreboard, General |
| click `Chat` | `Settings - Chat` (space-hyphen-space) |
| click `Public Chat: ON` | flips in place to `OFF` (binary setting: ON → OFF) |
| click a tri-state row | cycles `ON → FRIENDS_FOLLOWED → OFF` |

### 3.11 Ranks (f13) — `smp_ranks`

| Action | Expected |
|---|---|
| `/ranks` | perk table plus the configured store text |
| `/rank set bob tier1 30` | `Granted <label> to bob for 30 days` |
| bob's `/homes` limit | rises from 2 to 9 (slots: default 2, tier1 9, tier2 27, tier3 90) |
| `/rank clear bob` | `Cleared bob's rank` — limits revert |

### 3.12 Statistics and scoreboard (f14) — `smp_stats`

| Action | Expected |
|---|---|
| `/stats` | `Stats` (or `Stats - <name>` for another player) with rows: Broken Blocks, Placed Blocks, Kills, Deaths, Mob Kills, Money, Shards, Playtime, Money from Selling, Spent in Shop |
| `/leaderboard money` | `<Category> (Page 1)` board; valid keys are `brokenblocks`, `deaths`, `kills`, `mobskilled`, `money`, `placedblocks`, `playtime`, `sell`, `shards`, `shop` |
| look bottom-right | the scoreboard shows your balance with a **lower-case** suffix (`723k`), not the `$ 5.1K` money style |

### 3.13 World rules (f15) — `smp_world` (no commands)

Requires the relevant keys from `friedcake/minetest.conf.example`
(`world.spawn_protect_radius`, `world.soft_border`, `world.border_margin`,
`world.max_accounts_per_ip`).

| Action | Expected |
|---|---|
| dig inside the spawn radius | refused (protected) |
| dig outside it | succeeds |
| walk past the soft border | pushed back + `You have reached the world border.` |
| six accounts from one IP | the fifth joins normally; the sixth raises a staff flag and is **not** blocked |

---

## 4. Checklist

- [ ] `tools/agent-flow.sh test` → `all dev-tests green` (20 suites)
- [ ] The pack boots: no `[smp_*]` load errors in the server log
- [ ] `/smp test smp_core`, `smp_ah`, `smp_sell`, `smp_quickbuy` → `Failed: 0`
- [ ] Money formatter: body vs. inline spacing and upper-case money /
      lower-case quantity suffixes
- [ ] `/ah` → `/shop` live price works end-to-end (§3.2 → §3.3)
- [ ] `/pay` self/unknown refusals and `/paytoggle`
- [ ] Orders wizard, delivery, and the verbatim plural/singular strings
- [ ] Combat tag blocks `/rtp` but not `/sell`
- [ ] `/findplayer` never leaks coordinates
- [ ] Chat has no rank prefix
- [ ] Scoreboard shows lower-case money
- [ ] Spawn protection, soft border, accounts-per-IP flag
- [ ] Spawners create zero entities

---

## 5. Reporting a failure

1. Re-run the headless suites first — they are the narrowest signal
   (`tools/agent-flow.sh test`).
2. Check the server log for `[smp_*]` load errors; a mod that failed to load
   prints `error`.
3. Record the feature area, the exact command or click path, and
   expected-versus-actual, then file it against the matching
   `spec/features/fNN-*.md` §10 (open questions).
4. Known, non-blocking items are tracked in `INTEGRATION.md`; the
   `fixes/` directory holds one brief per gap found by
   `SPEC-CONFORMANCE-REPORT.md`.
