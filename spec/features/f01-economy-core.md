# f01 — Economy Core

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_economy`, `smp_store`, `smp_admin` |
| Phase | P0 — everything else depends on this |
| Depends on | `smp_core` |
| Frame evidence | **4 frames** (`/pay`), 00:01:27–00:01:31, plus money strings throughout |
| Confidence | Medium. The currency format is well attested; `/pay` itself was typed but never completed on camera |

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/bal` | `/balance`, `/money` | `[player]` | Show a money balance | LIVE [S24] |
| `/pay` | — | `<player> <amount>` | Transfer money | **OBSERVED** [F0088–F0090] |
| `/payto` | — | `<player> <amount>` | Exact-name alias of `/pay`, for scripts; registered only while `economy.tab_complete` is true | PROPOSED |
| `/paytoggle` | `/paymenttoggle` | — | Toggle receiving payments | CLONE [C1] |
| `/baltop` | `/moneytop` | `[page]` | Money leaderboard (`f14`) | LIVE [S24] |
| `/shards` | `/shard` | — | Shard balance (`f06`) | CLONE [C1] |
| `/eco` | — | `give｜take｜set｜reset <player> <amount>` | Adjust money (admin) | CLONE [C1] |
| `/ledger` | — | `<player> [page]` | Audit trail (admin **or** moderator; the OR is enforced inside `func`, see §8) | PROPOSED |
| `/smp` | — | `reload｜test｜backend` | Reload configuration, run a mod's acceptance tests, show the storage backend (admin) | PROPOSED |

## 3. Observed UI

### 3.1 `/pay` [F0088, F0089, F0090]

Typed as `/pay aad5074`, with a **tab-completion dropdown listing player
names** (`aapieaapie`, `aaron2play`, `aalvaroofb`, `aae5`, `aad5074` …)
[F0089]. Completion is alphabetical and matches on prefix. The payment itself
is never completed on camera.

### 3.2 Money display

| Form | Where | Frames |
|---|---|---|
| `$700` | auction tooltip, no suffix, **no space** | F0108 |
| `$ 5.1K` | chat, suffixed, **with space** | F0055 |
| `$ 9K`, `$ 25K` | auction tooltips | F0124, F0115 |
| `$ 30K each`, `$ 182K each`, `$ 4M each`, `$ 1K each` | order tooltips | F0212, F0159, F0164, F0160 |
| `$ 10`, `$ 10 each` | `Review Order` | F0204 |
| `$ 189` | HUD after a sale | F0097 |
| `Voire $ 754k` / `Voire 723k` | scoreboard sidebar | F0287, F0055 |
| `$1` | `Confirm Listing` tooltip, no space | F0142 |
| `$30K` | delivery confirm tooltip, no space | F0222 |

The spacing is genuinely inconsistent in the source, and not randomly so:
**chat and tooltip *body* lines use `$ ` with a space; inline and
parenthesised amounts use `$` with none.** Both patterns are reproduced
(`shared §0.6`); do not normalise.

Suffixes are **upper case for money** (`$ 5.1K`, `$ 4M`) and **lower case for
quantities** (`2.1k/2.5k Delivered`). The scoreboard uses lower case for money
(`754k`) — a third convention, confined to the scoreboard (`f14`).

### 3.3 Observed chat messages

| String | Meaning | Frames |
|---|---|---|
| `You bought 1 Ender Chest for $ 5.1K` | purchase result | F0037, F0055 |
| `You delivered 1 Totem of Undying and received $30K` | delivery payout | F0227 |
| `You earned 1 Shard for playing the server` | shard award (`f06`) | F0037, F0055 |
| `This item was already bought` | lost race on a purchase | F0037 |

### 3.4 Not observed

`/bal`, `/baltop`, a completed `/pay`, payment notifications, any economy menu.

## 4. Behaviour

### 4.1 Currencies

| Property | Money | Shards |
|---|---|---|
| Role | Primary currency [S1] | Secondary, for premium items [S8] |
| Earned through | `/sell`, auction sales, order deliveries, bounty claims, `/pay` | 1 per 10 minutes of playtime [S8] |
| Spent on | Auction, orders, Quick Buy, bounties, `/pay` | Shard shop [S8] |
| Transferable | Yes, with `/pay` | No (`PROPOSED`) |
| Leaderboards | `money`, `sell`, `shop` [S23] | `shards` [S23] |

### 4.2 `/pay`

1. MUST reject self-payment, unknown recipients, recipients with payments
   disabled, and recipients who have blocked the payer.
2. Amounts below `economy.min_pay` (`PROPOSED` $0.01) are rejected.
3. The transfer follows `shared §2.3` and writes a debit and a credit ledger
   entry.
4. Both parties are notified; the recipient only if online with payment alerts
   on. Offline recipients see a summary on next join (`PROPOSED`).
5. Donut community documentation warns that sending money to low-playtime
   accounts can get both accounts wiped [S24]. Transfers above
   `economy.flag_threshold` (`PROPOSED` $1M) to accounts with less than
   `economy.flag_min_playtime` (`PROPOSED` 2 h) MUST be flagged for staff
   review. **Flagged, not blocked.**
6. Recipient tab completion is `OBSERVED` [F0089] and MUST be implemented
   (`core.register_chatcommand` with a completion-friendly parameter, or a
   client-side prefix match over online players).

### 4.3 Ledger

Append-only, monotonically increasing id, one entry per economic mutation.
Reason codes in `shared §2.6` R3. This is the audit substrate for every other
mod; no mod may move money without writing one.

### 4.4 Number formatting

A single shared formatter and parser in `smp_core`, used by every mod:

- `fmt_money(cents, style)` — `style` is `body` (`$ 5.1K`) or `inline` (`$1`).
- `fmt_qty(n)` — lower-case suffixes (`753k`, `1.3m`).
- `parse_amount(text)` — accepts `250k`, `1.5M`, `10`, `10.50`,
  case-insensitively; rejects negative, NaN and infinite values.

Storage is integer cents (`shared §0.7`).

## 5. Data schema

### 5.1 Player record (`smp_store`, table `players`)

```lua
{
  name = "Alice",
  first_join = 1758500000,
  money = 125000000,                  -- $1,250,000.00 in cents
  shards = 420,
  playtime = 86400,
  shards_for_playtime = 144,
  rank = { tier = "tier1", expires_at = 1761100000 },
  homes = { --[[ f09 ]] },
  stats = { --[[ f14 ]] },
  social = { --[[ f11 ]] },
  quickbuy = { --[[ f05 ]] },
  keys = { --[[ f16 ]] },
}
```

### 5.2 Ledger entry

```lua
{ id = 981234, time = 1758500200, type = "ah_sale", actor = "Bob",
  counterparty = "Alice", amount = 64000000, currency = "money",
  item_key = "mcl_core:diamond", qty = 64, ref = "ah:10452", flags = {} }
```

## 6. Algorithms

```lua
function smp_economy.pay(sender, target_name, amount)
  local from = sender:get_player_name()
  if from == target_name then return refuse("cannot pay yourself") end
  if not smp_store.player_exists(target_name) then return refuse("unknown player") end
  if smp_social.blocks(target_name, from) then return refuse_generic() end
  if not smp_settings.get_name(target_name, "eco.pay_accept") then return refuse_generic() end
  if amount < cfg.economy.min_pay then return refuse("amount too small") end
  if smp_economy.get(sender) < amount then return refuse("insufficient funds") end

  -- no yields from here (shared §2.3)
  smp_economy.take(sender, amount)
  smp_economy.give(target_name, amount)
  smp_store.ledger("pay", from, target_name, amount, {})

  if amount >= cfg.economy.flag_threshold
     and smp_store.playtime(target_name) < cfg.economy.flag_min_playtime then
    smp_admin.flag("large_transfer_to_new_account", from, target_name, amount)
  end
  notify_both(from, target_name, amount)
end
```

**As implemented** — the block above is pseudocode for the validation
*order*, not a call-for-call transcript. Where the shipped code differs, and
why:

| Pseudocode | Shipped (`smp_economy/init.lua`) | Why |
|---|---|---|
| `smp_settings.get_name(target, …)` | `smp_settings.get(target, …)` → `record.social.pay_accept` → default **on** | **F12-A** (`f12-settings.md:248`) renamed the accessor to `get`. f12 does not register `eco.pay_accept` yet, and its store lives in *player* meta, which an offline recipient has no handle for — so `record.social.pay_accept` stays the offline-authoritative fallback, with a one-time migration on join (E-22). Cross-feature ask: f12 §10. |
| `smp_economy.take(sender, amount)` / `smp_economy.give(target, amount)` | `smp_store.api.take_money` / `add_money` directly, with the two ledger rows each helper writes | **No clamp is allowed to leak supply**: `give` is capped at `economy.max_balance`, so routing `/pay` through it would silently drop part of a transfer that has already been debited. `/eco give｜set｜reset` and every other *credit* path do go through `smp_economy.give` (E-18). D7 mirror consequence recorded in §10. |
| `smp_admin.flag(kind, from, target, amount)` | `smp_admin.flag(kind, detail)` with `detail` formatted on this side | **D9** landed 2026-09-24 with the 2-argument signature (E-03/E-24). |
| `smp_store.ledger(...)` | `take_money` / `add_money` write the debit and the credit row each | shared §2.6 R3: one append-only entry per mutation; T5 asserts the delta is exactly two. |
| `amount < cfg.economy.min_pay` before the funds check | blocks → cooldown → amount → min_pay → recipient toggle → funds | shared §2.3: every validation runs before the first mutation, with no yield in between. R9's cooldown is validated (not armed) here. |

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `economy.min_pay` | $0.01 | PROPOSED |
| `economy.max_balance` | $10¹³ | CLONE [C1] |
| `economy.flag_threshold` | $1,000,000 | PROPOSED |
| `economy.flag_min_playtime` | 7,200 s | PROPOSED |
| `economy.tab_complete` | true | PROPOSED |
| `ledger.page_size` | 20 | PROPOSED |
| `store.flush_interval` | 10 s | PROPOSED |
| `store.backend` | `auto` | PROPOSED |
| `store.max_balance` | $10¹³ | PROPOSED |
| `store.ledger_page_size` | 20 | PROPOSED |

## 8. Mineclonia implementation

- Balances live in `smp_store` player records, not player meta: leaderboards
  must enumerate offline players (`shared §2.2`).
- The formatter and parser are the **only** sanctioned way to render or read an
  amount. A second implementation will drift from the observed spacing rules.
- `/eco` and `/ledger` require the `smp_admin` privilege;
  `/ledger` read-only also accepts `smp_moderator`.
- No mod may write `player_record.money` directly. Route every mutation through
  `smp_economy.take` / `give`, which write the ledger.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | `fmt_money` renders `$ 5.1K` in body style and `$1` in inline style |
| T2 | `fmt_qty` renders `753k` and `1.3m` in lower case |
| T3 | `parse_amount` accepts `250k`, `1.5M`, `10.50`; rejects `-1`, `nan`, `inf`, `1e400` |
| T4 | `/pay` to yourself, to an unknown player, or below `min_pay` is refused and moves nothing |
| T5 | A successful `/pay` writes exactly two ledger entries and conserves the total supply |
| T6 | A $2M transfer to a 10-minute-old account succeeds **and** raises a flag |
| T7 | `/pay` tab-completes online player names by prefix |
| T8 | Balances survive a restart; a crash mid-flush loses at most `store.flush_interval` |
| T9 | Money never becomes negative under concurrent operations |
| T10 | A balance of $10¹³ cannot be exceeded |

## 10. Findings, escalations and open questions

### 10.1 Escalations and dispositions from the conformance fixes

Every row of `fixes/f01-economy-core.md`, with its evidence and outcome.
Nothing outside the edit surface (`smp_economy`, `smp_items`, their tests,
`dev-tests/test_economy.lua`, `dev-tests/test_items.lua`, this file) was
modified.

| Id | Outcome | Evidence / target |
|---|---|---|
| E-01 | **CLOSED** (verified, not redone) | `smp_social.blocks` wired both directions in the validate phase, `smp_economy/init.lua:395-398`; generic refusal so X9's `/pay` leg does not reveal the block. Closed here so `fixes/f11-social.md` does not double-implement. |
| E-02 | **CLOSED** | `core.register_on_joinplayer` at `init.lua:858` surfaces `pending:<name>` rows accumulated in this mod's own mod storage at pay time; read-and-clear has no yield. Ledger-based alternatives were impossible (E-15 `counterparty` = `""`, E-16 pagination). |
| E-03 | **CLOSED** (D9 landed) | `smp_admin.flag("large_transfer_to_new_account", detail)` at `init.lua:435-436`; `detail` formatted on this side per D9's 2-arg signature. `core.log` kept as fallback when `smp_admin` is absent. |
| E-04 | **CLOSED** | 1 s per-sender cooldown validated before any mutate; armed only by a successful pay; clock = `core.get_gametime` (fallback `os.time`); hook `smp_economy._reset_pay_cooldown` at `init.lua:230`. Hardcoded — no new `core.settings` key (see §7). |
| E-05 | **ESCALATE → integrator** | Ledger reversal helper (shared §2.6 R11) lives in `smp_store`; no reversal code exists anywhere in the pack. Integrator-owned. |
| E-06 | **ESCALATE → integrator** | Pending marker on multi-record ledger ops (shared §2.6 R12) is `smp_store`-side. Consequence: T8's crash-mid-flush half is satisfied *a fortiori* by write-through, not by a real crash simulation. |
| E-07 | **CLOSED** | `/ledger` registered with **no** privs table; the OR is checked inside `func` (`init.lua:662-675`) and denial is the engine-verbatim `You don't have permission to run this command (missing privileges: @1).`. `/eco` stays `smp_admin`-only. §2 row updated. |
| E-08 | **CLOSED** | `/eco reset <player> <amount>` now parses the amount and sets the balance to it with reason `eco:reset:<admin>` (`init.lua:626-637`); missing/invalid input rejected, never accepted-and-ignored. |
| E-09 | **CLOSED** | `local function run_smp_core_tests` moved above the registration (`init.lua:728` vs call at `:819`), so the closure captures the local. The dispatcher now runs `test.lua` for **any** `smp_*` mod — that generalisation is `PROPOSED`, see §10.3. |
| E-10 | **CLOSED** | Prefix resolver kept (`resolve_player_name`) and proven by T7; the engine limitation is documented here and in the code comment. Luanti exposes no server-driven argument-completion API (`~/dev/luanti/doc/lua_api.md`), so the OBSERVED dropdown [F0089] is client-side online-name completion, which the server cannot drive. |
| E-11 | **CLOSED** | In-game test output and every player-facing string in this mod go through the translator; enforced by the string audit in `dev-tests/test_economy.lua` (0 failures). |
| E-12 | **ESCALATE → integrator** | `smp_store/init.lua:326` sends `"[smp_store] backend = " …` to chat untranslated. Integrator-owned. |
| E-13 | **CLOSED** | Terminal `.` stripped from every invented string in `smp_economy`/`smp_items`, descriptions included; catalogued and OBSERVED strings left byte-exact. Automated period scan in `dev-tests/test_economy.lua`. |
| E-14 | ✅ **RESOLVED** by integrator | `shards_for_playtime` column + migration present in `smp_store/backends/sqlite.lua`. Verified, no escalation filed. |
| E-15 | **ESCALATE → integrator** | Ledger `counterparty` still written `""` in `smp_store`. Also the reason E-02 cannot use ledger queries. |
| E-16 | ✅ **RESOLVED** by integrator | `ledger_for` filter-then-page in `smp_store/backends/mod_storage.lua`. Verified. |
| E-17 | **ESCALATE → integrator** | mod_storage `flush` is a no-op (write-through, no batching) — shared §2.2 dirty-flag batching unimplemented. Integrator-owned. |
| E-18 | **CLOSED** | `economy.max_balance` is enforced in this mod's credit paths: `smp_economy.give` clamps to `cfg.max_balance` and reports what it credited (`init.lua:104-135`), and `/eco give｜set｜reset` clamp (`init.lua:606-637`). `/pay` deliberately does **not** route through `give` (see §6) so no clamp can destroy supply already debited. **D7 mirror consequence recorded in `## Proposed shared changes`.** |
| E-19 | **ESCALATE → integrator** | `smp_core` event bus / config loader / widget helpers missing; `show_formspec`'s 4th argument bound to `_` (`smp_core/init.lua:204-205`). Integrator-owned. |
| E-20 | **CLOSED** | Reversible contents codec in `smp_items`: percent-encoded tokens `"C"<pct(meta "compressed")>` / `"S"<pct(serialized list)>` / `""`, bytes outside `[A-Za-z0-9.-]` encoded so no `|` can appear. `stack_from_key` rebuilds contents/wear/ench and returns nil only for legacy hash tokens and `named == 1`. M0/M1 literals byte-identical; `test_ah_keys.lua`'s six-field parse untouched. Preferred route (implement) taken over amending the shared wording — wording proposal still filed below. |
| E-21 | **ESCALATE → integrator** | `auto` backend never picks sqlite (`smp_store/init.lua:46-50` guards on a `package.loaded` entry nobody preloads). Integrator-owned. |
| E-22 | **CLOSED** | Read chain `smp_settings.get(name, "eco.pay_accept")` → `record.social.pay_accept` → default ON; writes mirror to both; one-time join migration via raw `smp_store` read (`init.lua:153-156`). Cross-feature ask in §10.2 (f12 must register the id). |
| E-23 | **CLOSED** | T5 counts ledger rows immediately before and after and asserts a delta of **exactly 2**, both `pay`, plus supply conservation. |
| E-24 | **CLOSED** (D9 landed) | T6 asserts the flag fires for $2M → a 10-minute account via `smp_admin.flags()` (kind, detail, +1 count), and does **not** fire below the threshold or above the playtime floor. Same asserts in `smp_economy/test.lua`. |
| E-25 | **CLOSED** | T7 in `dev-tests/test_economy.lua`: unique prefix, ambiguous refusal, exact-wins, case-insensitive. |
| E-26 | **CLOSED** | T8 re-instantiates the store driver over the same storage stub and re-reads balances + ledger. Crash-window rationale documented in the test: satisfied *a fortiori* by write-through, blocked on R12 (E-06) for a true simulation. |
| E-27 | **CLOSED** by integrator (D1 = A, P1) | `smp_quickbuy/buy.lua:87` verified period-free — matches the OBSERVED form. No change made here. **Live residue in other mods** noted in §10.2. |
| E-28 | **DEPENDS-BLOCKER** (B1-1, B4-1) | B1-1 (`core.register_on_globalstep` in `smp_store`) is integrator-owned; B4-1 deletes this suite's `register_globalstep` fake afterwards. The fake was kept as instructed, and this suite gained **no** stub of a name the engine lacks. The literal forbidden symbol is not written anywhere under `friedcake/`. |

### 10.2 Findings and cross-feature asks raised by the fixes

| # | Finding | Ask |
|---|---|---|
| F-1 | `optional_depends = smp_social` on `smp_economy` was **not** added: it creates the real load cycle economy → social → combat → stats → economy, which aborts server startup. Verified against the mod dependency graph. | Integrator: rule on the cycle (either `smp_social` must not depend on `smp_stats`, or the blocks check has to move behind a lazy call). Until then E-01 stays a guarded call-only wiring (`if smp_social and …`), which is already what ships. **RULED 2026-09-25: accepted as-is — no `optional_depends = smp_social` edge; the omission is deliberate and documented** (the guard is evaluated at command time, not load time, so load order cannot break it). |
| F-2 | `/smp test <mod>` now dispatches to **any** `smp_*` mod that ships a `test.lua`, not only `smp_core`. | Integrator: accept as `PROPOSED` behaviour for the `/smp` row in `spec/shared/05-command-reference.md`, or tell me to narrow it back to `smp_core`. **RULED 2026-09-25: accepted as PROPOSED; the `shared/05` `/smp` row now carries `reload｜test <mod>｜backend`.** |
| F-3 | `/payto` is kept and now declared in §2 (status `PROPOSED`). | Integrator: add the mirror row to `spec/shared/05-command-reference.md`, or rule it out of scope and I will drop the command. Open question: should it be gated on `economy.tab_complete` (as currently registered) or be unconditional? **RULED 2026-09-25: keep `/payto` (PROPOSED) with the `economy.tab_complete` gate exactly as registered; the `shared/05` mirror row was added by the integrator.** |
| F-4 | D7 mirror consequence of E-18: `shared/06` lists `economy.max_balance` (now genuinely enforced here) but still does **not** list the live `store.max_balance` cap in `smp_store`, and `shared/06:17` still says `economy.max_balance` is "read but dead". | See `## Proposed shared changes` — proposal only, never a hand-edit. |
| F-5 | E-22 needs f12 to register `eco.pay_accept` for the canonical accessor to be authoritative; f12 also renamed `get_name` → `get` (**F12-A**). | Cross-feature ask for `spec/features/f12-settings.md` §10: register `eco.pay_accept` (default ON) and confirm the offline-player-meta limitation, so the `record.social` fallback can eventually be retired. **Routed 2026-09-25: row `F12-8` added to `fixes/f12-settings.md` (f12 has already merged once, so this is a follow-up dispatch).** |
| F-6 | Period divergence in **other** mods' `Insufficient funds.` — `smp_bounty/init.lua:159`, `smp_quickbuy/buy.lua:70`, `smp_orders/routing.lua:104,133`. Their own tests assert the period, so they were not touched. The f01 copy is period-free (E-13). | Integrator: fold into D1's sweep of E-27 across f02/f03/f05, or file a new row. Same class as E-27. **Ruled 2026-09-25 and split three ways: `smp_quickbuy/buy.lua:70` fixed by the integrator (no brief owns quickbuy); `smp_orders/routing.lua:104,133` + `dev-tests/test_orders.lua:828` routed to new row **O9** in `fixes/f04-orders.md`; `smp_bounty/init.lua:159` + `dev-tests/test_bounty.lua:126` held for the integrator immediately after the running f10 branch merges (f10 cannot be reached mid-flight).** |
| F-7 | E-10: there is still no server-driven tab-completion API in Luanti, so the OBSERVED dropdown [F0089] can only ever be the client's own online-name completion. | Informational for the integrator; if the engine ever gains an argument-completion callback, revisit the resolver. |
| F-8 | E-01 closed on `main` before this branch (verified, both directions). | Informational: `fixes/f11-social.md` must not re-implement the blocks → payments wiring; it landed here. |

### 10.3 Open questions

| Id | Question |
|---|---|
| V-51 | Does `/bal` accept another player's name? |
| V-52 | What are the `/pay` success and notification messages? Never seen |
| V-53 | Is the scoreboard's lower-case money (`754k`) a third format, or the same formatter at a narrower width? |
| V-27 | Exact name of the shard balance command (`/shards` vs `/shard`) |

### 10.4 Security escalations from fix brief S01 (2026-09-27)

Brief: `fixes/security/S01-economy-core.md`. Fixed inside this feature's
edit surface (details in the brief's status section): **EC-2** (the leave
handler resolves the ObjectRef to a name before closing sessions),
**EC-3** (the offline-pending list is now a versioned aggregate capped at
50 distinct senders, join summary capped at 20 lines + one "and N
others" line), **EC-4 `/baltop` half** (60 s shared cache + 10 s
per-player cooldown enforced in `core.register_on_chatcommand`, so it
covers `smp_stats`' snapshot override too), **EC-5** (`/pay` pre-flights
the receiver's headroom against `min(economy.max_balance,
store.max_balance)` and refuses inside the validate phase), and
**EC-7** (in `smp_stats/api.lua`: keys minted from
`SecureRandom():next_bytes(20)`, fail closed).

The three findings below all target integrator-owned files
(`smp_store/**`, `smp_store/pg_proxy.py`) and are escalated here with
ready-to-apply patch text:

| Id | Target | Ask |
|---|---|---|
| S01/EC-1 | `smp_store/init.lua:267,292,335,354` | Sign/NaN/inf guards on the four money primitives (patch below) |
| S01/EC-4 (ledger half) | `smp_store/backends/mod_storage.lua:134-165` + `STORAGE.md` | Per-actor ledger index, or a production SQLite recommendation (patch below) |
| S01/EC-6 | `smp_store/pg_proxy.py` + `smp_store/backends/postgres.lua` | Shared-secret auth + content checks + per-thread connections (patch below) |

#### S01/EC-1 — store primitives trust their callers (→ smp_store)

`take_money(name, -500)`: `rec.money < -500` is false, so the balance
GAINS 500. With NaN every comparison is false and the NaN balance is
persisted. `add_shards`/`take_shards` have no sign check at all, and
`add_money`'s `if delta > cap / if delta <= 0` pair lets NaN through
(`NaN > cap` and `NaN <= 0` are both false) into `rec.money + delta`.
No current caller passes a bad value today — this is one missed check
from a money dupe. Patch (guards at the very top of each primitive):

```lua
-- smp_store/init.lua — top of take_money (line 292) and take_shards
-- (line 354; its parameter is named `n`, as in add_shards)
n = tonumber(n)
if not n or n ~= n or n <= 0 or n >= math.huge then
	return nil -- nil = nothing taken (documented contract)
end
n = math.floor(n)

-- smp_store/init.lua — top of add_money (line 267) and add_shards (line 335)
n = tonumber(n)
if not n or n ~= n or n <= 0 or n >= math.huge then
	return 0 -- 0 = nothing changed (documented contract)
end
n = math.floor(n)
```
(`take_money`/`add_money` name their parameter `cents`; use that name
there — the guard itself is identical.)

**Deviation from the brief's snippet (justified):** the brief returns
`nil` from all four. `add_money` documents `0` as "nothing changed"
(`init.lua:266`), and `smp_economy.give` passes `add_money`'s return
STRAIGHT THROUGH while documenting "0 = credited nothing"
(`init.lua:133-142`; `smp_economy/test.lua` asserts `give(...) == 0`) —
so the `add_*` pair answers `0` and only the `take_*` pair answers
`nil`, preserving every documented contract. The old
`if delta <= 0 then return 0 end` inside `add_money` stays as a second
line of defence after the guard.

#### S01/EC-4 (ledger half) — `ledger_for` is O(all rows) per page (→ smp_store)

`driver.ledger_for` walks every `ledger:` key and `read_json`s every
entry to filter by actor before paging
(`backends/mod_storage.lua:134-165`; the E-16 fix made it
filter-then-page, which corrected correctness but kept the O(N) parse).
`/ledger` is staff-only, so this is a DoS-amplification concern, not a
hot-path one — hence Low. Two acceptable dispositions, integrator picks:

1. **Per-actor index.** In `driver.append_ledger`, also append the new
   id to `ledger:idx:<actor>` (JSON array, monotonic, same write
   transaction as `ledger:<id>`). `driver.ledger_for` then reads only
   `ledger:idx:<actor>`, sorts (ids are monotonic, so append order is
   already newest-first for a single writer) and `read_json`s just the
   `size` rows of the requested page — O(page) instead of O(all).
2. **Docs only.** Add a "production" note to
   `friedcake/mods/smp_store/STORAGE.md`: mod_storage is for small
   servers; use `backend = sqlite` (or postgres) once the ledger passes
   a few thousand rows. The sqlite/postgres backends page with SQL.

#### S01/EC-6 — the Postgres proxy has no authentication (→ ops + smp_store)

`pg_proxy.py` accepts any POST on `127.0.0.1:8457`; `json.loads` ignores
Content-Type, so a browser on the host can `fetch` it as a CORS simple
request (no preflight) and set `money` to anything. Any local process can
do the same, and one psycopg2 connection is shared across
`ThreadingHTTPServer` threads (cross-thread cursor/transaction races).
Patch, proxy side (`pg_proxy.py`):

```python
import hmac  # plus: from threading import local as thread_local

TOKEN = os.environ.get("FRIEDCAKE_PG_TOKEN")
if not TOKEN:
    sys.exit("FRIEDCAKE_PG_TOKEN is required (shared secret for the Lua driver)")

MAX_BODY = 64 * 1024
_local = thread_local()

def db():
    # One connection per handler thread: the old module-global _conn was
    # shared across ThreadingHTTPServer threads.
    conn = getattr(_local, "conn", None)
    if conn is None or conn.closed:
        conn = psycopg2.connect(DSN)
        conn.autocommit = False
        _local.conn = conn
    return conn

# Handler.do_POST — validate BEFORE reading or parsing the body:
def do_POST(self):
    length = int(self.headers.get("Content-Length", 0))
    if length > MAX_BODY:
        self._respond(413, {"ok": False, "error": "body too large"}); return
    if not hmac.compare_digest(self.headers.get("X-Friedcake-Token", ""), TOKEN):
        self._respond(401, {"ok": False, "error": "bad token"}); return
    if (self.headers.get("Content-Type") or "").split(";")[0].strip() \
            != "application/json":
        self._respond(415, {"ok": False, "error": "content-type must be application/json"}); return
    ...  # existing body read + dispatch
```

Patch, Lua driver side (`backends/postgres.lua`, inside
`sync_request`):

```lua
local extra = { "Content-Type: application/json" }
local token = (cfg and cfg.postgres_token)
	or core.settings:get("store.postgres_token")
if token and token ~= "" then
	extra[#extra + 1] = "X-Friedcake-Token: " .. token
end
-- ... pass `extra_headers = extra` to http.fetch_async
```

Run the proxy with `FRIEDCAKE_PG_TOKEN=<random>` and set the same value
as `store.postgres_token` in `minetest.conf`. The new config key needs a
`shared/06` row — see `## Proposed shared changes`. `hmac.compare_digest`
also removes the (minor) timing side channel of a plain `==`.

#### Cross-feature notes from S01

| # | Note | Ask |
|---|---|---|
| X-S01-1 | `spec/features/f14-stats.md` F14-D5 still says `/api` issues `fcsmp_ .. sha1`; the key now comes from `SecureRandom():next_bytes(20)` hex-encoded (same `fcsmp_` + 40-hex form). | f14's owner/integrator: reword the F14-D5 row; observable behaviour (issue-once, re-show, revoke, re-issue) is unchanged, only the entropy source moved. |
| X-S01-2 | The `/baltop` cooldown lives in `core.register_on_chatcommand` in this mod precisely so it survives `smp_stats/init.lua`'s snapshot override: the engine runs chatcommand hooks BEFORE whichever `func` is registered, so both the economy func and the override's snapshot/fallback branches sit behind it. Proven for the hook ordering in `dev-tests/test_economy.lua` (EC-4 `dispatch`); the override's own branch is covered by construction, not by a second test. | Informational — if the override ever grows its OWN pre-func work (network, file IO), it must keep relying on this hook for rate limiting. |
| X-S01-3 | EC-5 makes `store.max_balance` a second live reader in this mod (`cfg.store_max_balance`, same key/fallback as `smp_store/init.lua:30`). | Strengthens F-4 / the `shared/06` proposal below: the key is now consumed by two mods, so the config mirror really should list it. |

## Proposed shared changes

Proposals only — `spec/shared/` is read-only for this agent.

| File | Current | Proposed |
|---|---|---|
| `spec/shared/02-architecture.md` §2.5 (`:95`) | the M2 `<contents>` field is described as a **hash** over the contents | describe it as a **reversible token** (percent-encoded `compressed` meta, or the empty key for the serialized list); `stack_from_key` rebuilds the stack. The one-way hash was retired by E-20; consumers that compared it opaquely are unaffected. |
| `spec/shared/06-config-reference.md` (`:10`, `:17`) | `economy.max_balance` marked read-but-dead; `store.max_balance` not listed although `smp_store` enforces it | `economy.max_balance` — now enforced by `smp_economy`'s credit paths (E-18); `store.max_balance` — listed as the store-level cap for direct `smp_store.api.add_money` callers. This is D7's mirror decision. |
| `spec/shared/05-command-reference.md` | no `/payto` row; `/smp` row predates the test dispatcher | add `/payto <player> <amount>` (alias of `/pay`, f01 `PROPOSED`); widen `/smp test` to `<mod>` where the mod ships a `test.lua` (f01 `PROPOSED`). |
| `spec/shared/06-config-reference.md` (S01/EC-6) | no `store.postgres_token` row | add `store.postgres_token` — shared secret sent as `X-Friedcake-Token` to `pg_proxy.py` (paired with the proxy's required `FRIEDCAKE_PG_TOKEN` env var); only meaningful when `store.backend = postgres`. |
