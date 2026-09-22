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
| `/paytoggle` | `/paymenttoggle` | — | Toggle receiving payments | CLONE [C1] |
| `/baltop` | `/moneytop` | `[page]` | Money leaderboard (`f14`) | LIVE [S24] |
| `/shards` | `/shard` | — | Shard balance (`f06`) | CLONE [C1] |
| `/eco` | — | `give｜take｜set｜reset <player> <amount>` | Adjust money (admin) | CLONE [C1] |
| `/ledger` | — | `<player> [page]` | Audit trail (admin) | PROPOSED |
| `/smp` | — | `reload` | Reload configuration (admin) | PROPOSED |

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

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `economy.min_pay` | $0.01 | PROPOSED |
| `economy.max_balance` | $10¹³ | CLONE [C1] |
| `economy.flag_threshold` | $1,000,000 | PROPOSED |
| `economy.flag_min_playtime` | 7,200 s | PROPOSED |
| `store.flush_interval` | 10 s | PROPOSED |

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

## 10. Open questions

| Id | Question |
|---|---|
| V-51 | Does `/bal` accept another player's name? |
| V-52 | What are the `/pay` success and notification messages? Never seen |
| V-53 | Is the scoreboard's lower-case money (`754k`) a third format, or the same formatter at a narrower width? |
| V-27 | Exact name of the shard balance command (`/shards` vs `/shard`) |
