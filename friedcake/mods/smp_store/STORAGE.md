# smp_store — Storage design

`smp_store` owns all persistent state in FriedcakeSMP: per-player records, the
append-only ledger, the auction house (later), orders (later), bounties
(later). The store API is backend-agnostic so a small server can run on
mod_storage, a mid-size one on SQLite, and the eventual large deployment on
PostgreSQL.

The choice is made at start-up and frozen until `/smp reload`.

## Driver contract

A backend must implement every operation in `smp_store.api`. The API is the
*only* thing feature mods touch. The Lua reference implementation lives in
`init.lua` (`smp_store.api = {...}`); each backend lives in its own
`backends/<name>.lua` and exposes the same table.

### Required operations

```
begin(), commit(), rollback()                  -- transaction (optional on mod_storage)

get_player(name): record | nil                 -- one record
upsert_player(record)                          -- insert or full replace
all_player_names(): list[str]                  -- includes offline (shared §2.2)
update_player_field(name, key, value)          -- atomic partial update

append_ledger(entry) -> id                     -- id is auto-assigned, monotonic
ledger_for(actor, page, size) -> {entries, total_pages}

create_index(name, columns)                    -- free-form per backend
migrate()                                      -- idempotent schema setup
close()                                        -- flush + close handles
```

### Records

Player records are flat Lua tables; nested fields (`rank`, `homes`, `stats`,
`social`, `quickbuy`, `keys`) are stored as JSON strings by mod_storage /
serialized blobs by SQLite / JSONB columns by Postgres. The Lua side always
sees them as Lua tables.

```lua
{
  name = "Alice",
  first_join = 1758500000,
  money = 125000000,        -- $1,250,000.00 in cents (integer)
  shards = 420,
  playtime = 86400,
  rank = { tier = "tier1", expires_at = 1761100000 },
  homes = {}, stats = {}, social = {},
  quickbuy = {}, keys = {},
}
```

### Ledger entries

```lua
{ id = ..., time = ..., type = "ah_sale", actor = "Bob",
  counterparty = "Alice", amount = 64000000, currency = "money",
  item_key = "mcl_core:diamond", qty = 64, ref = "ah:10452", flags = {} }
```

Reason codes are pinned in `spec/shared/02-architecture.md` §2.6 R3.

### Numeric types

- Money is **always** integer cents. Lua numbers are exact to 2^53; 10^15
  cents is comfortably under the limit.
- Shards are integers.
- Timestamps are `os.time()` seconds.

## Backends shipped today

### `mod_storage`

- One JSON document per player: key = player name, value = JSON record.
- Ledger: key `ledger:NNNNN` for entry N, written append-only.
- All operations in `core.get_mod_storage()`'s namespace.
- Pros: zero setup, works in any Minetest build.
- Cons: single-thread writes, no real index; leaderboards are O(N) at startup.

### `sqlite`

- One DB file at `<worlddir>/friedcake_store.sqlite`.
- Obtained via `core.request_insecure_environment()`.
- Schema is the same as Postgres will use. Each backend translates it to its
  dialect.
- Pros: real indices, transactions, single-node scale to millions of rows.
- Cons: requires `lsqlite3` in the engine and `smp_store` in
  `secure.trusted_mods`.

Schema (canonical form, all backends match):

```sql
CREATE TABLE IF NOT EXISTS players (
  name          TEXT PRIMARY KEY,
  first_join    INTEGER NOT NULL,
  money         INTEGER NOT NULL DEFAULT 0,
  shards        INTEGER NOT NULL DEFAULT 0,
  playtime      INTEGER NOT NULL DEFAULT 0,
  rank_json     TEXT NOT NULL DEFAULT '{}',
  homes_json    TEXT NOT NULL DEFAULT '{}',
  stats_json    TEXT NOT NULL DEFAULT '{}',
  social_json   TEXT NOT NULL DEFAULT '{}',
  quickbuy_json TEXT NOT NULL DEFAULT '{}',
  keys_json     TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS ledger (
  id           INTEGER PRIMARY KEY,
  time         INTEGER NOT NULL,
  type         TEXT NOT NULL,
  actor        TEXT NOT NULL,
  counterparty TEXT NOT NULL DEFAULT '',
  amount       INTEGER NOT NULL DEFAULT 0,
  currency     TEXT NOT NULL DEFAULT 'money',
  item_key     TEXT NOT NULL DEFAULT '',
  qty          INTEGER NOT NULL DEFAULT 0,
  ref          TEXT NOT NULL DEFAULT '',
  flags_json   TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS ledger_actor_time ON ledger(actor, time DESC);
CREATE INDEX IF NOT EXISTS ledger_time       ON ledger(time DESC);
```

### `postgres` (stub)

- API defined; refuses to load.
- The eventual driver goes over `core.request_http_api()` to a local
  `pgwire` proxy; direct TCP from the Lua sandbox is not available.
- The schema above is the source for both SQLite and Postgres, so adding the
  driver is a translation exercise, not a redesign.

## Selection

```
store.backend = auto       -- try sqlite -> mod_storage (default)
            | mod_storage
            | sqlite
            | postgres     -- fails until a real driver is wired in
```

`auto` is what operators should use. The chosen backend is logged once at
start-up and remembered in mod storage so `/smp reload` keeps the same
backend unless explicitly overridden.
