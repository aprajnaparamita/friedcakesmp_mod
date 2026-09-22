# dev-tests — standalone smoke tests

These scripts let us exercise the FriedcakeSMP code paths without spinning
up a Luanti server. They stub the engine (`core.*`) just enough for the
mods to load and call into the store / formatter / economy commands.

They are not unit tests shipped to players. They are developer tools that
run with the system Lua / LuaJIT. Parallel agents working on later phases
should add their own scripts here following the same pattern.

## Run

```
luajit dev-tests/test_fmt.lua     # formatter, parser, session API
luajit dev-tests/test_store.lua   # mod_storage backend contract
luajit dev-tests/test_economy.lua # /pay /bal /ledger /eco paths
```

Each script prints `ALL OK` on success and exits with code 0. Failures
throw with a clear message and a non-zero exit code.

## What they cover

| File | Spec test ids |
|---|---|
| `test_fmt.lua` | f01 §9 T1, T2, T3, plus the menu session open/get/close cycle |
| `test_store.lua` | smp_store API contract: upsert, all_player_names, ledger monotonic, ledger_for, flush, close |
| `test_economy.lua` | f01 §9 T4, T5, T6, T9, T10 |

Together with `/smp test` (in-game) they cover the entire f01 acceptance
matrix.

## Caveats

- `test_store.lua` and `test_economy.lua` stub `core.write_json` /
  `core.parse_json` with a minimal encoder/decoder. The real engine uses
  `core.write_json` which calls into Luanti's JSON module.
- The SQLite backend cannot be smoke-tested without `lsqlite3` on the
  test host. Use `mod_storage` for the dev tests.
- Float precision matters at the cap: $10^13 dollars = 10^15 cents, which
  is exactly 2^50 — well within the 2^53 mantissa, but be careful with
  arithmetic that lands on the boundary.
