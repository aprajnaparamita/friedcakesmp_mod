# S01 — Economy core: store primitives, sessions, offline pay, DoS, ops

**Target mods:** `smp_core`, `smp_store`, `smp_economy`
**Branch:** `agent/sec-s01-core` · **Audited at:** `85e4a5d`

> ⚠ `smp_core` and `smp_store` are **integrator-owned** (AGENTS.md rule 4).
> Every row marked **ESCALATE** is a proposal for the integrator. A feature
> agent records it in `spec/features/f01-economy-core.md §10` and does not
> edit those mods. `smp_economy` rows can be fixed directly.

## Findings

| ID | Sev | Status | Where | Owner | One line |
|---|---|---|---|---|---|
| EC-1 | Low (hardening) | CONFIRMED | `smp_store/init.lua:292-372` | ESCALATE | `take_money`, `add_shards` and `take_shards` accept negative or NaN amounts, so a negative `take` mints money |
| EC-2 | Medium | CONFIRMED | `smp_economy/init.lua:857-859` | smp_economy | `on_leaveplayer` receives an ObjectRef but calls `close_all_sessions(player_name)`, so sessions are never cleared |
| EC-3 | Medium | CONFIRMED | `smp_economy/init.lua:247-257` | smp_economy | 1-cent `/pay` spam to an offline player grows their pending list without bound (O(n²) rewrites, huge join message) |
| EC-4 | Medium | CONFIRMED | `smp_economy/init.lua:512-545`, `mod_storage.lua:134-165` | smp_economy / ESCALATE | `/baltop` loads every player record and `/ledger` parses every ledger row, per call |
| EC-5 | Low | CONFIRMED | `smp_economy/init.lua:426-427` | smp_economy | `/pay` debits in full but the credit is clamped at the cap, so the overflow is destroyed |
| EC-6 | Low | CONFIRMED | `smp_store/pg_proxy.py` | ESCALATE | The Postgres proxy has no authentication, and a browser on the host can POST to it (CSRF) |
| EC-7 | Low | CONFIRMED | `smp_stats/api.lua:31-34` | smp_stats | API keys come from `math.random` + time. Use `SecureRandom` |

---

### EC-1 — Store primitives trust their callers (ESCALATE)

`smp_store.api.take_money(name, -500)`: `rec.money < -500` is false, so
`rec.money = rec.money + 500`. With NaN, the comparison is false and the
balance becomes **NaN**, which is then persisted. `add_shards` and
`take_shards` have no sign check at all. **No current caller passes a
negative** (each caller validates: `smp_economy.take`, `parse_amount`,
`pct_of`, and the order and bounty minimums). This is one missed check away
from a money dupe.

**Proposal.** At the top of each primitive:
```lua
cents = tonumber(cents)
if not cents or cents ~= cents or cents <= 0 or cents >= math.huge then return nil end
cents = math.floor(cents)
```
`add_money` already returns 0 for `delta <= 0`. Add the NaN guard there
too.

### EC-2 — Leave handler never clears sessions

`core.register_on_leaveplayer(function(player_name) smp_core.close_all_sessions(player_name) end)`.
The argument is an **ObjectRef**, so the call indexes `_sessions[ObjectRef]`
and nothing happens. Several mods rely on this cleanup, and the AH comment
at `smp_ah/init.lua:377` even documents it. Stale sessions survive a relog.
For example, a modified client can send `confirm` to the Quick Buy warning
screen from an old session and bypass the 3× price guard
(`smp_quickbuy/init.lua:294-307`). The same mistake appears in
`smp_shardshop/init.lua:178` (S05 SH-1).

**Fix.** `local name = player:get_player_name()`. **Test:** open a session,
fire leave with an ObjectRef stub, and assert that `smp_core._sessions[name]`
is nil.

### EC-3 — Unbounded offline-payment queue

`add_pending` appends `{from, amount}` and rewrites the whole JSON list on
every `/pay` to an offline player. `min_pay` is 1 cent and the cooldown is
1 s per sender. With k alts, that is k entries per second, forever. Each
append costs O(n), and the join handler prints every line.

**Fix.** Aggregate per sender (`list[from] = (list[from] or 0) + cents`),
cap the distinct senders (for example 50, with an "and N others" line), and
cap the join summary.

### EC-4 — O(N) commands on the hot path

- `/baltop` (`page_baltop`) calls `get_player` for every name in the
  store and sorts, on every call, from any player. With the Postgres
  backend each `get_player` is a **blocking HTTP round-trip on the main
  thread** (`backends/postgres.lua:32-48`).
- `/ledger` (staff only) on mod_storage reads and parses every ledger row
  per page.

**Fix.** Serve `/baltop` from `smp_stats`' cached boards (already rebuilt
periodically), or cache the sorted table for 60 s, and add a per-player
cooldown. ESCALATE: per-actor ledger indexes in the mod_storage driver, or
recommend SQLite for production in `STORAGE.md`.

### EC-5 — `/pay` into a capped balance

`take_money(sender, cents)` then `add_money(target, cents)`. The second
call clamps to `store.max_balance` and returns the applied delta, which is
ignored. Validate first: `if smp_economy.get(target) + cents > cfg.max_balance then refuse`.

### EC-6 — Postgres proxy (ESCALATE, ops)

`pg_proxy.py` accepts any POST on `127.0.0.1:8457` with no token.
`json.loads` ignores Content-Type, so a web page open in a browser on the
server host can `fetch('http://127.0.0.1:8457/update_player_field', {method:'POST', body:'{"name":"x","key":"money","value":1e15}'})`
as a CORS "simple request", with no preflight. Any local user or process can
do the same. One psycopg2 connection is also shared across
`ThreadingHTTPServer` threads.

**Proposal.** Require a shared secret header (`X-Friedcake-Token`, read
from an env var and from `store.postgres_token` on the Lua side), reject
any `Content-Type` other than `application/json`, cap `Content-Length`,
and use one connection per thread or a pool.

### EC-7 — Predictable API keys

`core.sha1(us_time .. name .. math.random() .. os.clock())`. Replace it
with `SecureRandom():next_bytes(20)`, hex-encoded (engine:
`src/script/lua_api/l_noise.cpp` `LuaSecureRandom`). If `SecureRandom()`
returns nil, fail closed.

## Verified OK

- `parse_amount` rejects negatives, NaN, inf and > 10¹⁵. It accepts
  `0`, and every caller enforces its own minimum (min_pay, min_price, bounty
  min).
- `/pay` validates block, rate limit, amount, recipient toggle and funds
  before mutating, with no yields.
- `/eco` and `/smp` are `smp_admin`. `/ledger` does an explicit OR check of
  admin or moderator.
- Formatters handle NaN and inf without throwing.
