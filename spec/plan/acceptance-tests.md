# Acceptance Test Matrix

The authoritative tests live in section 9 of each feature file. This matrix is
the index: what each file's tests prove, and the cross-cutting tests no single
feature owns. A phase from `roadmap.md` is done when every test it touches
passes.

Test ids are per-file (`f03` T4 is not `f04` T4). Integration tests below are
numbered X1… and belong to the whole mod set.

## Per-feature index

| File | Tests | What they prove, in one line |
|---|---:|---|
| f01-economy-core | T1–T10 | Money formatting matches both observed spacings; suffix parsing; `/pay` refusals; ledger conservation; transfer flagging; balance caps |
| f02-sell | T1–T10 | Observed `Sell` container; button-mode confirm; eligibility and M0 matching; shulker contents sold and box returned; order routing pays the better price; no item loss on close/disconnect/full inventory |
| f03-auction | T1–T10 | Observed board, search, filter and `Your Items` tree; listing flow via `Insert Item` → `Edit Sign Message` → `Confirm Listing`; version-checked purchase races; routing into orders |
| f04-orders | T1–T14 | Observed board, creation flow (`Choose Item` → `How many?` → `Price per item?` → `Review Order`), delivery flow and `Delivering...`/payment sequence; escrow; enchantment-exact matching; collection and cancellation |
| f05-quickbuy | T1–T7 | Live price display; the 3× price guard; exact enchantment matching; combat refusal; no partial charge on a raced listing |
| f06-shards | T1–T9 | The verbatim award message; 600 s playtime award; shard shop debit and delivery; amethyst timers expire; drill/axe/shovel respect protection |
| f07-spawners | T1–T10 | Zero entities; output within 1 % of the model; stacking; Silk Touch gating; storage caps pause production; lazy accrual correctness |
| f08-teleport | T1–T13 | `/rtp` has no menu; 1,000 safe landings per dimension; warm-up cancels on movement/damage/tag; request lifecycle and generic refusals; `/world`; queue never pairs mutual blocks |
| f09-homes | T1–T9 | Verbatim home messages; tab-row structure; rename keeps id; `Show More`; icon persistence; `/findplayer` never leaks a home |
| f10-combat | T1–T12 | Tag on melee/arrow; blocked-command enforcement; `/sell` and `/msg` allowed; combat-log drops all four lists and credits the kill; bounty escrow, stacking, anti-abuse, admin refund |
| f11-social | T1–T10 | Observed `<Name> message` chat format; `/msg` delivery and the verbatim privacy refusal; ignore/block effects; three-valued privacy enforcement; unknown-command response |
| f12-settings | T1–T9 | Seven categories; observed Chat toggles; toggle cycles and redraws; tri-state values; persistence; forged-field safety |
| f13-ranks | T1–T8 | Perk API limits; lazy expiry; grant stacking; grandfathering after expiry; no default chat prefix; offline grants |
| f14-stats | T1–T11 | Every counter increments exactly; scoreboard shows live balance in lower-case suffix style; ten leaderboard categories; rebuild under 50 ms at 10,000 records; offline players included |
| f15-world-rules | T1–T7 | Spawn protection via `core.is_protected`; no PvP tag inside it; soft border; `/rtp` respects both; account-per-IP flag; no seed exposure; zero ABMs |
| f16-legacy | ~~T1–T11~~ | **Descoped (D8, 2026-09-24)** — f16 will never be built |

## Cross-cutting integration tests

These are the failure modes that ended the reference server's first season
[S1]. They are owned by no feature file; run them against the assembled mod
set at every phase boundary.

| Id | Test | Covers |
|---|---|---|
| X1 | **Duplication drill.** Put a valuable stack through every menu path (sell, auction list, order delivery, Quick Buy, spawner take) and force-quit the client mid-operation. No path may duplicate or destroy the stack | R4–R6, §2.3 |
| X2 | **Race drill.** Two clients confirm the same auction purchase and the same order delivery concurrently. Exactly one succeeds; the loser gets `This item was already bought` | R4, f03 §6, f04 §6 |
| X3 | **Escrow conservation.** Create, partially fill, and cancel orders and bounties; at every step, total money supply changes only by documented sinks | R2, R3 |
| X4 | **Ledger completeness.** For a scripted day of mixed operations, every balance change has exactly one ledger entry with a valid reason code, and `/ledger <player>` reconstructs each player's history | R3, R11 |
| X5 | **Combat logout.** Tag a player, disconnect them, verify drops, kill credit, bounty payout and spawn-respawn on rejoin in one scenario | f10 §4.3 |
| X6 | **Restart integrity.** `kill -9` the server between a debit and its flush; on restart the pending marker resolves and at most `store.flush_interval` of data is lost | R12 |
| X7 | **Performance budget.** With 100 synthetic players, 10,000 player records, 1,000 auction listings and 500 spawner nodes: no globalstep exceeds budget, menu opens render one page, leaderboard rebuild under 50 ms | §2.7, f14 T8 |
| X8 | **String fidelity.** Snapshot-compare every menu title, button, tooltip and chat message in `shared/08-ui-strings.md` against the rendered formspecs and chat output | §0.5 |
| X9 | **Privacy cascade.** A blocks B: B's `/msg`, `/pay`, `/tpa` and `/rtpqueue` pairing all refuse, each with a generic message that reveals nothing | f11, f01, f08 |
| X10 | **Protection cascade.** Inside the spawn radius: no digging, no PvP tag, no amethyst drill damage, no `/rtp` landing, no bounty payout | f15, f10, f06, f08 |

### Seam policy (D11)

Cross-mod **seam existence** and **load order** are covered headlessly by
`dev-tests/test_integration.lua` (D11, 2026-09-24), run with the rest of the
suite at every phase boundary: it dofiles every `load_mod`-enabled mod in
engine-faithful dependency order against the recorded
`engine_api_surface.txt`, and fails on any load error, unknown global, or
missing cross-mod seam. The X1–X10 drills remain the in-game behavioural
layer (stub-free seam *behaviour* still needs a live server).

## Evidence gaps that block tests

Some tests cannot be finalised until an open question closes
(`open-questions.md`). The blockers:

| Blocked test | Waiting on |
|---|---|
| f07 T3 (output within 1 %) | V-02, V-62 — production rates are uncalibrated |
| f03 fee/tax tests | V-06 — fees undocumented |
| f06 T6 (shop prices) | V-20, V-60 — catalogue unverified |
| f10 T1 (tag duration) | V-12 — duration undocumented |
| f08 T6 (cooldown values) | V-13 — cooldowns undocumented |

Until these close, the tests run against the configured `PROPOSED` defaults
and pass by construction; their purpose in the interim is regression detection,
not fidelity proof.
