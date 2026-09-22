# Open Questions and Verification Checklist

Every `PROPOSED` value in the specification is a placeholder waiting for
evidence. This file is the consolidated list. Each question is owned by one
feature file (cross-listed where a second file references it); answers are
recorded there, not here.

How to answer a question: capture a screenshot or a short video on the
reference server, or confirm from an official source [S1]–[S28]. Then update
the owning feature file — replacing the `PROPOSED` tag with `OBSERVED` plus a
frame citation — and mark the question closed here. **Never downgrade an
`OBSERVED` requirement to a guess** (`README` rule 5).

Ids V-01 to V-27 come from v0.1 §16; several were closed by the video. V-28
onwards are new in v0.2.

## Status key

| Mark | Meaning |
|---|---|
| OPEN | No evidence yet |
| PARTIAL | Some evidence; the listed remainder is still unverified |
| CLOSED | Resolved by the frame corpus or a later source |

## The checklist

| Id | Question | Owner | Status |
|---|---|---|---|
| V-01 | Spawner menu layout, pages and buttons | f07 | OPEN |
| V-02 | Production rate per type and stack size; whether owners must be nearby | f07 | OPEN |
| V-03 | Blaze spawner output: rods or powder? Sources conflict | f07 | OPEN |
| V-04 | Do creeper spawners exist? | f07 | OPEN |
| V-05 | Spawner storage capacity and behaviour when full | f07 | OPEN |
| V-06 | Auction fees, duration, default slots; why does the API document a fourth sort (`last listed`) the observed menu lacks? | f03 | PARTIAL — sorts known |
| V-07 | Auction menu layout, filters and category tabs | f03 | CLOSED |
| V-08 | Quick Auction Sell mechanics | f03 | OPEN |
| V-09 | Order creation steps, escrow, cancellation, expiry and default slots | f04 | PARTIAL — flow known |
| V-10 | Quick Buy panel layout | f05 | OPEN |
| V-11 | Does `/sell` sell on close or on a button? | f02 | CLOSED — button mode observed [F0094] |
| V-12 | Combat tag duration, blocked commands and elytra rule | f10 | OPEN |
| V-13 | RTP cooldowns, ranges and region list | f08 | OPEN |
| V-14 | Teleport request expiry and warm-up | f08 | OPEN |
| V-15 | Current default number of homes | f09 | CLOSED (menu structure known; the count itself remains undocumented) |
| V-16 | Complete `/settings` list and categories | f12 | CLOSED — v0.1's list was wrong; seven categories observed |
| V-17 | `/findplayer` output format | f11 | OPEN |
| V-18 | Friends and follow semantics | f11 | OPEN |
| V-19 | Bounty minimum, stacking, refunds and anti-abuse rules | f10 | OPEN |
| V-20 | Exact enchantments on shard shop gear | f06 | OPEN |
| V-21 | Amethyst tool details: 3×3 orientation, leaf handling, shovel block list, timer display | f06 | OPEN |
| V-22 | Amethyst sell axe behaviour | f06 | OPEN |
| V-23 | `/stats` and leaderboard layouts | f14 | OPEN |
| V-24 | Do ranked players carry a chat prefix? No prefix on any observed line | f11 (f13) | OPEN — reopened by the video |
| V-25 | Spawn layout: lobbies, RTP zone and warps | f08 (f15 V-80) | OPEN |
| V-26 | Does the reference server have the rotating NPC trader (`/billford`) one clone includes [C2]? | f15 | OPEN |
| V-27 | Exact name of the shard balance command (`/shards` vs `/shard`) | f01 (f06) | OPEN |
| V-28 | What does the yellow warning triangle on prompt menus mean? | f03 | OPEN |
| V-29 | Cycle order of `ON` / `Friends/Followed` / `OFF` | f12 | OPEN |
| V-30 | Is the sign-edit substitution acceptable, or should price entry use an anvil-style rename? | f03 | OPEN (decision pending) |
| V-31 | Does home `Delete` show a confirmation step? | f09 | OPEN |
| V-32 | What does `Show More` open — a second tab page, or a list screen? | f09 | OPEN |
| V-33 | Is there a home teleport warm-up, and is it displayed? | f09 | OPEN |
| V-34 | What is the default home icon? | f09 | OPEN |
| V-35 | Is the `Choose Icon` list every registered item, or a curated subset? | f09 | OPEN |
| V-36 | Contents of Notifications, PvP, Visuals, Privacy, Scoreboard and General settings | f12 | OPEN |
| V-37 | Which settings are binary and which tri-state? | f12 | OPEN |
| V-38 | Is category 6 `Scoreboard` or `Social`? Four frames to one favour `Scoreboard` | f12 | PARTIAL |
| V-39 | Where do v0.1's clone-derived settings live in the observed categories? | f12 | OPEN |
| V-40 | Is there an auction purchase confirmation dialog? | f03 | OPEN |
| V-41 | Where are seller name and time remaining shown? | f03 | OPEN |
| V-42 | How are listings cancelled or reclaimed? | f03 | OPEN |
| V-43 | How does the buyer collect delivered items? | f04 | OPEN |
| V-44 | Is escrow shown anywhere? | f04 | OPEN |
| V-45 | Is delivering to one's own order actually blocked? | f04 | OPEN |
| V-46 | What does the worth on `Choose Item` hover represent? | f04 | OPEN |
| V-47 | Are partial deliveries paid immediately? | f04 | PARTIAL — `Delivering...` sequence suggests yes |
| V-48 | What distinguishes `/ignore` from `/block`? | f11 | OPEN |
| V-49 | Is the `/msg` refusal identical for an ignore and for a privacy setting? | f11 | OPEN |
| V-50 | Is there a friends menu, or is `/friend` chat-only? | f11 | OPEN |
| V-51 | Does `/bal` accept another player's name? | f01 | OPEN |
| V-52 | What are the `/pay` success and notification messages? | f01 | OPEN |
| V-53 | Is the scoreboard's lower-case money a third format? | f01 (f14) | OPEN |
| V-54 | What is the `Sell` confirm pane's tooltip? | f02 | OPEN |
| V-55 | Is there a sell receipt screen? | f02 | OPEN |
| V-56 | Is routing surfaced to the seller at all? | f02 | OPEN |
| V-57 | Does the `Sell` grid reject ineligible items on drop or on confirm? | f02 | OPEN |
| V-58 | Does Quick Buy buy across multiple listings to fill a quantity? | f05 | OPEN |
| V-59 | Is the 3× guard per purchase or per entry? | f05 | OPEN |
| V-60 | Shard shop layout | f06 | OPEN |
| V-61 | Are shards awarded while AFK? | f06 | OPEN |
| V-62 | Is the spawner diminishing-returns curve exponential as modelled? | f07 | OPEN |
| V-63 | Is there a visible `/rtp` warm-up countdown? | f08 | OPEN |
| V-64 | Does `/rtp` announce the arrival? | f08 | OPEN |
| V-65 | Does `/rtpqueue` still exist post-beta, and what are its matchmaking rules? | f08 | OPEN |
| V-66 | Does `/spawn` open a menu of named lobbies, and what are they called? | f08 | OPEN |
| V-67 | Does `/world` chain or hold exactly one entry? | f08 | OPEN |
| V-68 | Is the combat tag displayed, and where? | f10 | OPEN |
| V-69 | Does the server broadcast combat logs? | f10 | OPEN |
| V-70 | Are explosion kills attributed for bounties? | f10 | OPEN |
| V-71 | Does `/bounty` have a menu? | f10 | OPEN |
| V-72 | What are tier3's exact auction and order slot counts? | f13 | OPEN |
| V-73 | What does `/ranks` look like? | f13 | OPEN |
| V-74 | Do consecutive grants stack additively? | f13 | OPEN |
| V-75 | Is the Media tier purchasable or assigned? (Display text only) | f13 | OPEN |
| V-76 | What is `Voire` in the scoreboard title? | f14 | OPEN |
| V-77 | Does the scoreboard show anything besides money? | f14 | OPEN |
| V-78 | What does the `Scoreboard` settings category control? | f14 | OPEN |
| V-79 | Which `mcl_reason` fields identify the killer in `on_die`? (Engine task) | f14 | OPEN |
| V-80 | Spawn layout — cross-listed with V-25 | f15 | OPEN |
| V-81 | Actual entity caps and their Luanti equivalents | f15 | OPEN |
| V-82 | Is bedrock breaking currently enabled? | f15 | OPEN |
| V-83 | Exact contents of each crate's seven choices | f16 | OPEN |
| V-84 | Did crate opening animate? | f16 | OPEN |
| V-85 | Were team homes separate from personal home limits? | f16 | OPEN |
| V-86 | Duel arena layouts; did losers' items transfer? | f16 | OPEN |
| V-87 | Did the AFK zone kick players after a limit? | f16 | OPEN |

## Outstanding screenshot placeholders

Features without frame coverage carry `SS-nn` placeholders
(`shared/00-conventions.md §0.4`). Save the capture at
`screenshots/SS-nn-slug.png` and the link resolves.

| Id | What to capture | Owner | Answers |
|---|---|---|---|
| SS-08 | Quick Buy panel, including the price warning | f05 | V-10, V-58, V-59 |
| SS-09 | Shard shop | f06 | V-20, V-60 |
| SS-10 | Shard Pickaxe tooltip and timer | f06 | V-21 |
| SS-11 | Spawner menu | f07 | V-01, V-05 |
| SS-12 | Spawner stacking feedback | f07 | V-02 |
| SS-16 | Combat tag display | f10 | V-12, V-68 |
| SS-17 | Bounty list | f10 | V-19, V-71 |
| SS-19 | `/stats` menu | f14 | V-23 |
| SS-20 | Leaderboard menu | f14 | V-23 |
| SS-22 | Crate choice menu (historical — capture from an old video or clone) | f16 | V-83, V-84 |
| SS-24 | `/ranks` menu | f13 | V-73 |
| SS-30 | Team menu (historical — as SS-22) | f16 | V-85 |

v0.1 placeholders retired by the frame corpus (kept for archival reference):
SS-01 through SS-07, SS-13 through SS-15, SS-18, SS-21, SS-23, SS-25 through
SS-29 — each is now covered by cited frames or folded into a broader open
question above.
