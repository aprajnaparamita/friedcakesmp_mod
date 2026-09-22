# FriedcakeSMP — Manual Test Guide

For the human session that verifies the merged mod set end-to-end. The
automated checks below are fast and should pass first; then work through the
feature walkthroughs with two players (two client windows, or one client and
`/grant` for staff commands).

---

## 0. One-time setup

The engine and game already live locally:

- **Luanti engine:** `~/dev/luanti` (5.17.0)
- **Mineclonia game:** `~/dev/mineclonia-git`

1. Point a world at the modpack. Either:
   - symlink/copy `friedcake/` into `~/dev/mineclonia-git/mods/friedcake`, or
   - add the repo to a world's `worldmods/` and set `enable_modpack = true`.
2. In `minetest.conf` (or the world's `minetest.conf`), set:

   ```
   secure.trusted_mods = smp_store
   secure.http_mods = smp_store
   name = YourServerName
   ```

   (`secure.trusted_mods` is only needed for the SQLite store backend; the
   default `store.backend = auto` falls back to `mod_storage` if SQLite is
   unavailable, so a plain world works with no special config.)
3. Create a world with the Mineclonia game, enable the `friedcake` modpack.
4. Grant yourself staff for the admin-only checks:

   ```
   /grant <name> all
   ```

---

## 1. Automated checks first

### 1.1 Headless dev-tests (no server)

```
cd /Volumes/Dara/dev/coconut
tools/agent-flow.sh test
```

Expected: `all dev-tests green` (20 scripts, each prints ALL OK).

### 1.2 In-game acceptance tests

The `/smp test <feature>` dispatcher is wired for these mods:

```
/smp test smp_core
/smp test smp_economy
/smp test smp_ah
/smp test smp_quickbuy
/smp test smp_sell
/smp test smp_shardshop
```

Each prints a passed/failed count. All should be `0 failed`.

---

## 2. Feature walkthrough (two players helps)

Set up two accounts, e.g. `alice` and `bob`. Give `alice` staff for the admin
commands.

### 2.1 Economy (f01) — `smp_economy`

| Command | Expected |
|---|---|
| `/bal` | `Your balance: $ 0` (or current) |
| `/eco give alice 1000000` | `Gave $ 10K to alice` — balance now `$ 10K` |
| `/pay bob 1000` | both get a chat line; balances move by $10 |
| `/pay alice 100` | refused — `You cannot pay yourself` |
| `/pay nobody 100` | refused — `Player … does not exist` |
| `/paytoggle` | toggles; `/pay` to a toggled-off recipient is refused |
| `/baltop` | leaderboard list, `alice` at top after the grant |
| `/ledger alice` | audit lines (`#id … type … amount … ref`) |

**Check the formatter** (f01 §3.2, the spacing rule):
- bare amounts have no space (`$700`); suffixed body lines have a space
  (`$ 5.1K`); suffixed amounts upper-case `K/M/B/T`; quantities lower-case.

### 2.2 Auction house (f03) — `smp_ah`

| Action | Expected |
|---|---|
| `/ah` | `Auction (Page 1)` container menu |
| hold an item, `/ah sell 100` | `You listed … for $1` |
| `/ah` → click the sign | `Search Auction`; `diamon` filters to diamond |
| click the hopper | `Filter` cycles `Lowest Price → Highest Price → Recently Listed` |
| `/ah` → chest | `Auction > Your Items` (note `>`, not `->`) |
| list an item, click it as bob | buys it; `You bought 1 … for $ …` |
| buy an already-bought item | `This item was already bought` (race) |

**This is the feature I just fixed.** `/shop` (below) depends on it.

### 2.3 Quick Buy (f05) — `smp_quickbuy`

| Action | Expected |
|---|---|
| `/shop` | `Quick Buy (Page 1)` menu |
| add an entry for an item that has listings on `/ah` | shows the live lowest price |
| buy it within 3× the shown price | completes, no re-confirm |
| buy it when the live price jumped > 3× | warning screen, requires re-confirm |

**This was broken before the fix (couldn't find listings).** If `/shop` shows
a live price and buys successfully, the fix works.

### 2.4 Orders (f04) — `smp_orders`

| Action | Expected |
|---|---|
| `/orders` | `Orders (Page 1)` container menu |
| create an order: `Your Orders` → empty slot → `Choose Item` → search → `How many?` → `Price per item?` → `Review Order` → `Create Order` | four wizard steps; `Choose Item (1 results)` note the ungrammatical plural; `Cancel!` has the exclamation mark |
| place a matching cheaper listing on `/ah` | the new order absorbs it (route) |
| deliver items: click an open order → `Orders -> Deliver Items` → drop items → `Confirm Delivery` | `Delivering...` action bar, then `You delivered 1 … and received $30K` |

**Watch the plural/singular inconsistency:** order tooltip `Netherite Helmets`
(plural), delivery chat `You delivered 1 Totem of Undying` (singular), but the
confirm form `You're delivering 1 Totems of Undying` (plural). All three are
correct as-is.

### 2.5 Selling (f02) — `smp_sell`

| Action | Expected |
|---|---|
| `/sell` | `Sell` container menu with a green confirm pane (bottom-right) |
| drop items, click the green pane | items sold, chat result |
| `/sell hand` | sells held stack |
| `/sell all` | sells the whole inventory |
| `/worth mcl_core:diamond` | base price line |

### 2.6 Spawners (f07) — `smp_spawners`

| Action | Expected |
|---|---|
| `/spawner give alice skeleton 1` | a `Skeleton Spawner x1` item |
| place it, right-click | spawner menu `Skeleton Spawner x1`, stored count grows |
| wait 60 s, reopen | stored bones increased (1 virtual kill/min per spawner) |
| dig with a normal pick | refused (needs Silk Touch) |
| `Sell all` in the menu | sells stored output |

### 2.7 Teleport + homes (f08 + f09) — `smp_tp`

| Action | Expected |
|---|---|
| `/rtp` | no menu; warm-up then a random safe location |
| move during warm-up | cancelled |
| `/sethome` | `Home set` |
| `/homes` | `Homes` tab row; click a tab → `Teleport / Change Icon / Rename / Delete` |
| `/homes nope` | `Home does not exist` |
| delete a home | `Home deleted` (note: `Delete` hovers red) |
| `/tpa bob` | bob gets an Accept/Deny prompt |
| `/world` | returns to pre-teleport position (once) |

### 2.8 Combat + bounty (f10) — `smp_combat` / `smp_bounty`

| Action | Expected |
|---|---|
| bob punches alice | both get a combat tag (action-bar countdown) |
| tagged player runs `/rtp` | refused — `You cannot use /rtp during combat` |
| tagged player runs `/sell` | **allowed** |
| tagged player disconnects | items drop at the logout spot (combat log) |
| `/bounty alice` | bounty list |
| `/bounty add alice 5000` | escrows $50 |
| bob kills alice | bob claims the bounty, broadcast |

### 2.9 Social (f11) — `smp_social`

| Action | Expected |
|---|---|
| chat | `<Name> message` (angle brackets, **no rank prefix**) |
| `/msg bob hi` | private message |
| `/ignore bob` | bob's chat and teleports to you are refused |
| `/msg <stranger with Friends/Followed>` | `This user only accepts messages from friends or followed players` |
| `/findplayer alice` | coarse only (`Offline` / `Spawn` / `<Dimension> – <Region>`) — never exact coords |
| typo a command | `This command does not exist` |

### 2.10 Settings (f12) — `smp_settings`

| Action | Expected |
|---|---|
| `/settings` | seven categories: Chat, Notifications, PvP, Visuals, Privacy, Scoreboard, General |
| click `Chat` | `Settings - Chat` (space-hyphen-space) |
| click `Public Chat: ON` | toggles to `OFF` in place |
| tri-state setting | cycles ON → Friends/Followed → OFF |

### 2.11 Ranks (f13) — `smp_ranks`

| Action | Expected |
|---|---|
| `/ranks` | perk table |
| `/rank set bob tier1 30` | bob is tier1 for 30 days |
| bob's `/homes` limit | rises from 2 to 9 |
| `/rank clear bob` | reverts |

### 2.12 Stats + scoreboard (f14) — `smp_stats`

| Action | Expected |
|---|---|
| `/stats` | fields: broken/placed, kills/deaths, mobs, money, shards, sell/shop |
| `/leaderboard money` | money leaderboard |
| look bottom-right | scoreboard shows your balance with a **lower-case** suffix (`723k`, `754k`) — not `$ 5.1K` |

### 2.13 World rules (f15) — `smp_world` (no commands)

| Action | Expected |
|---|---|
| dig inside spawn radius | refused (protected) |
| dig outside | succeeds |
| walk past the soft border | pushed back + `You have reached the world border` |
| six accounts from one IP | fifth joins fine; sixth logs a staff flag but is **not** blocked |

---

## 3. Checklist summary

- [ ] `tools/agent-flow.sh test` → all green
- [ ] `/smp test smp_core` … `smp_shardshop` → 0 failed each
- [ ] formatter spacing (bare vs suffixed vs lower-case) correct
- [ ] `/ah` → `/shop` live price works (**the fix**)
- [ ] `/pay` self/unknown refusal, `/paytoggle`
- [ ] orders wizard + delivery + plural/singular strings
- [ ] combat tag blocks `/rtp` but not `/sell`
- [ ] `/findplayer` never leaks coordinates
- [ ] chat has no rank prefix
- [ ] scoreboard shows lower-case money
- [ ] spawn protection + soft border
- [ ] zero mobs spawn from spawners (watch for entities)

---

## 4. If something fails

1. Re-run the headless tests first — they're the narrowest signal.
2. Check the server log for `[smp_*]` load errors (a mod that failed to load
   prints `error`).
3. Note which feature, the exact command, and the expected-vs-actual, and file
   it against the relevant `spec/features/fNN-*.md` §10 (open questions).
4. The known non-blocking items are recorded in `INTEGRATION.md` — a failed
   `/shop` live price was the one real hole, and it is now fixed and covered
   by dev-test `X-h`.
