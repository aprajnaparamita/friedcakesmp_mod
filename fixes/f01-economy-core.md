# Fix brief — f01 Economy core

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f01-economy-core.md` |
| Target mod(s) | `smp_economy`, `smp_items` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f01 (lines 209–248) |
| Verdict at audit | **PARTIAL (~14 gaps)** · ~30 rows OK · tests: T1–T4, T9, T10 green; T5/T6 weak; T7/T8 absent (report §5, line 793) |
| Branch | `agent/f01-economy-fixes` |
| Depends on | `00-P0-blockers.md` (B1-1, B4-1 — the pack does not boot); `01-integrator-decisions.md` **D1, D7, D9** — **ruled 2026-09-24: D1 = A (race string period-free; f05/`buy.lua` fixed by P1), D7 = A (mirror by P2), D9 = A (`smp_admin.flag` built by P4 — your `/pay` wiring at `smp_economy/init.lua:234-236` is still your row; E-09 verify here)** — **P4 landed 2026-09-24: signature is `flag(kind, detail)` (2 args); `f01:166`'s 4-arg pseudocode must format `detail` itself. D10 = A (mute trio built by P4 — no economy consumer wired, unchanged)** |

---

## Mission

The economy's core paths (`/pay`, `/bal`, `/eco`, `/ledger`, integer cents, no
yields) are sound, but the audit found 21 exception rows: `/pay` ignores
`smp_social.blocks` and has no rate limit, offline recipients never see their
payment summary, `/smp test` crashes on a global-vs-local bug, `/ledger` uses
the wrong privilege semantics, `economy.max_balance` is a dead key, the M2
shulker codec is one-way, and a dozen defects sit in integrator-owned
`smp_core`/`smp_store`/`smp_admin`. "Fixed" means every IN-SCOPE row
implemented and proven by dev-tests plus the in-mod `test.lua`, every ESCALATE
row recorded in §10 of your feature file with its D-ID/target, and T1–T10 all
green. Player/operator consequence today: a blocked player can still be paid
(privacy leak — acceptance X9's `/pay` leg), a $2M transfer to a 10-minute-old
account leaves no flag trail, sqlite silently drops `shards_for_playtime`
(f06 consumes it), and shulker contents cannot be reconstructed from an M2 key.

## Read this first (in order)

1. `AGENTS.md` — hard rules 1–8.
2. `spec/features/f01-economy-core.md` — especially §2 (commands), §4.2
   (pay rules, lines 83–99), §5 (schema), §6 (pseudocode), §7 (config),
   §8:188–191 (privs), §9 (T1–T10), §10 (open questions).
3. `spec/shared/02-architecture.md` (§2.2 dirty flags line 36, §2.3
   validate→mutate lines 56–67, §2.5 item keys lines 87–105, §2.6 R9/R10/R11/R12
   lines 128–131), `04-ui-kit.md` (§4.9 formspec preamble, `:287`), `05-command-reference.md`,
   `06-config-reference.md` (lines 9–12), `08-ui-strings.md` — **READ ONLY**.
4. `spec/plan/acceptance-tests.md` — your rows are the merge gate: the
   `f01-economy-core` row (line 15, T1–T10) and **X9** (line 48, the `/pay`
   privacy-cascade leg).
5. `SPEC-CONFORMANCE-REPORT.md` §4 f01 (lines 209–248), plus §3.3 line 173
   (weak-test inventory) and §4 f11 line 588 (the same blocks gap seen from
   f11's side).
6. The target mod source (`friedcake/mods/smp_economy/`,
   `friedcake/mods/smp_items/`) + `friedcake/dev-tests/test_economy.lua`,
   `test_fmt.lua`, `test_store.lua`, `test_ah_keys.lua` (M2 key structure),
   `friedcake/mods/smp_economy/test.lua`. `smp_items` has **no** `test.lua`
   yet — AGENTS step 7 requires you to add one.

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| E-01 | f01 §4.2.1 (`:85-86`), §6 (`:154`) | `/pay` never consults `smp_social.blocks` — a recipient who blocked the payer can still be paid | handler `smp_economy/init.lua:183-233`; zero `smp_social` refs in the mod (grep-confirmed); the check exists at `smp_social/graph.lua:112` | Wire `smp_social.blocks(target, sender)` into the validate phase (before any mutate), answering with f11's generic refusal that reveals nothing; declare the dependency in `smp_economy/mod.conf` (call only — do not edit `smp_social`). This closes f11's block→payments gap (report line 588) and the X9 `/pay` leg (`spec/plan/acceptance-tests.md:48`) — announce the wiring so `fixes/f11-social.md` does not double-implement it; the implementation lands here because the handler is yours | IN-SCOPE |
| E-02 | f01 §4.2.4 (`:90-91`) | Offline pay summary on join MISSING — no join handler anywhere in `smp_economy` | grep `register_on_joinplayer` in `smp_economy/` → 0 matches | Add `core.register_on_joinplayer` that surfaces payments received while offline (PROPOSED behaviour). Suggested in-scope mechanism: accumulate pending entries in `smp_economy`'s own mod storage at pay time when the target is offline; the join handler reads, displays and clears with no yield between read and clear. Do **not** build it on `smp_store` ledger queries — `counterparty` is always `""` (E-15) and `ledger_for` pagination is buggy (E-16). Invented summary string in house style, no terminal period (E-13) | IN-SCOPE |
| E-03 | f01 §4.2.5 (`:92-96`), §6 (`:164-167`), shared §2.6 R10 | Transfer flag only calls `core.log("warning")`; `smp_admin` (26 LOC of priv registration) has no `flag` API | `smp_economy/init.lua:220-224` | **ESCALATE → D9** (`fixes/01-integrator-decisions.md:49`): record in §10 of `spec/features/f01-economy-core.md`, keep the log call unchanged until D9 lands, then wire `smp_admin.flag("large_transfer_to_new_account", …)` exactly as §6 specifies | ESCALATE (D9) |
| E-04 | shared §2.6 R9 (`spec/shared/02-architecture.md:128`) | `/pay` has no rate limit (PROPOSED one per second) | grep `cooldown\|rate` in `smp_economy/init.lua` → 0 matches | Per-player `/pay` cooldown (~1 s) checked in the validate phase before any mutate; refusal string invented in house style (no terminal period); no yields | IN-SCOPE |
| E-05 | shared §2.6 R11 (`02-architecture.md:130`) | Ledger reversal helper MISSING | grep `revers\|undo` across `smp_store/` + `smp_economy/` → 0 matches | The ledger lives in `smp_store` → **ESCALATE (integrator-owned)**; §10 entry pointing at `01-integrator-decisions.md` | ESCALATE (integrator) |
| E-06 | shared §2.6 R12 (`02-architecture.md:131`) | Pending marker on multi-record ledger operations MISSING | no pending-marker code anywhere in `smp_store` (grep) | `smp_store`-side → **ESCALATE (integrator-owned)**; §10 entry | ESCALATE (integrator) |
| E-07 | f01 §8:188-189 | `/ledger` privs table uses Luanti AND semantics; spec requires admin **OR** moderator | `smp_economy/init.lua:415` (`privs = { smp_moderator = true, smp_admin = true }`) | Enforce OR inside `func` via `core.get_player_privs` — register without the AND-table (or with the weaker priv) and check `smp_admin or smp_moderator` explicitly, returning the standard denial for neither. `/eco` stays `smp_admin`-only per `f01:188` | IN-SCOPE |
| E-08 | f01 §2 (`:22`) | `/eco reset <player> <amount>` silently ignores `<amount>` — always zeroes | `smp_economy/init.lua:400-402` (`set_money(target, 0, …)`) | Consume `<amount>` per §2's shared `<player> <amount>` signature: parse via `smp_core.parse_amount`, set the balance to it (ledger reason `eco:reset:<admin>`), reject missing/invalid input. If zeroing is ruled the true intent instead, then reject the extra argument and correct the §2 params row in your own feature file, opening a §10 question — never accept-and-ignore an argument | IN-SCOPE |
| E-09 | f01 §2 (`:24`, `/smp` row) | `/smp test` runtime nil-call: the command closure resolves `run_smp_core_tests` as a **global** because the `local` is declared after the registration | call at `init.lua:459` vs `local function` at `init.lua:475` | Forward-declare or move `run_smp_core_tests` above `core.register_chatcommand("smp", …)` so the closure captures the local; `/smp test` must run without `attempt to call a nil value` | IN-SCOPE |
| E-10 | f01 §4.2.6 (`:97-99`); report ref §2 | `/pay` tab completion is a server-side prefix resolve only — no full completion integration | `init.lua:155-179` (`resolve_player_name`); engine truth: Luanti exposes no server-driven argument-completion API (report §4 f11 closing note, "Tab completion … N/A") | Keep the resolver and prove it with T7; document the engine limitation in the code comment and §10 — the OBSERVED dropdown (f01 §3.1) comes from the client's own online-name prefix completion, which the server cannot drive. Improve only against a real engine API; verify against `~/dev/luanti/doc/lua_api.md` first | IN-SCOPE |
| E-11 | f01 §3.2 / shared §0.5 | Raw untranslated player-facing strings (in-game test output) | `init.lua:502-510` (`lines[…] = "T9 take_money …"` with no `S()`) | Wrap every player-visible string in this mod's `core.get_translator` handle | IN-SCOPE |
| E-12 | f01 §3.2 / shared §0.5 | Raw untranslated chat string in `smp_store` | `smp_store/init.lua:326` (`"[smp_store] backend = " …` sent to chat) | `smp_store` is integrator-owned → **ESCALATE**; §10 entry | ESCALATE (integrator) |
| E-13 | f01 §3.2 / shared §0.5.4 (`spec/shared/00-conventions.md:88`) | Invented strings carry terminal full stops; house style forbids them | `init.lua:197` `You cannot pay yourself.`, `:212` `Insufficient funds.`, `:226` `You paid @1 @2.`, `:455` `FriedcakeSMP configuration reloaded.`, plus invented command descriptions e.g. `:99`, `:185`, `:414` — none of these appear in `spec/shared/08-ui-strings.md` (grep) | Strip the terminal `.` from invented (non-catalogued) strings in `smp_economy` and `smp_items`, descriptions included. Any string that IS in `shared/08-ui-strings.md` stays character-exact; the OBSERVED §3.3 strings keep their exact observed form (period-free) | IN-SCOPE |
| E-14 | f01 §5.1 (`:129`) | `shards_for_playtime` absent from `ensure_player` and the sqlite schema → dropped on sqlite upsert; f06 relies on atomic persistence of this field (report f06 Confirmed OK) | `smp_store/backends/sqlite.lua:192-219` (column list and binds omit it) | `smp_store` → **ESCALATE (integrator-owned)**; §10 entry noting the f06 data-loss consequence | ESCALATE (integrator) |
| E-15 | f01 §5.2 (`:143`) | Ledger `counterparty` always written `""`; the information lives in `ref` instead | `smp_store/init.lua:222,244,266,286,306` | **ESCALATE (integrator-owned `smp_store`)**; §10 entry (it also constrains E-02's mechanism) | ESCALATE (integrator) |
| E-16 | f01 §5 / report §4 | mod_storage `ledger_for` paginates by the **global** id index under an actor filter → duplicates/omissions from page ≥ 2 — **data-correctness, high severity** | `smp_store/backends/mod_storage.lua:149-156` | **ESCALATE (integrator-owned)**; §10 entry | ESCALATE (integrator) |
| E-17 | shared §2.2 (`02-architecture.md:36`) | Dirty-flag batching: mod_storage `flush` is a no-op (write-through, no batching) | `smp_store/backends/mod_storage.lua:161-162` | **ESCALATE (integrator-owned)**; §10 entry | ESCALATE (integrator) |
| E-18 | f01 §7 (`:177`) / `spec/shared/06-config-reference.md:10` | `economy.max_balance` read but dead — the enforced cap comes from `store.max_balance` (`smp_store/init.lua:23,33,212`), which the mirror does not list at all | reads at `smp_economy/init.lua:31` and `:43` | Decide and fix **in `smp_economy`**: either enforce `economy.max_balance` in this mod's give/set paths (T10 stays green; note other mods call `smp_store.api.add_money` directly, so the store cap still exists and needs reconciling) or delete the dead reads as a deliberate single-source choice. Either way record the **mirror consequence for D7** (`01-integrator-decisions.md:47`: mirrored `economy.max_balance` dead vs unlisted live `store.max_balance`) in §10 / `## Proposed shared changes` — never hand-edit `shared/06` | IN-SCOPE |
| E-19 | report ref §7; `shared/04-ui-kit.md` §4.9 | smp_core event bus / config loader / widget helpers MISSING; `show_formspec`'s preamble argument accepted and ignored | `smp_core/init.lua:204-205` (4th parameter bound to `_`) | `smp_core` is integrator-owned → **ESCALATE**; §10 entry | ESCALATE (integrator) |
| E-20 | report ref "§4 (M2)"; shared §2.5 (`02-architecture.md:95,105`), `03-mineclonia-api.md:21`, module table `02-architecture.md:9` ("shulker content codec") | Shulker codec is a one-way 64-bit hash — an M2 key cannot reconstruct contents; `stack_from_key` returns nil for M2 | `smp_items/init.lua:100-107` (`hash_str(k .. "=" .. v)`), nil-for-M2 at `:248`; `CONTENTS_KEYS = { "compressed", "" }` at `:43` | **IN-SCOPE (`smp_items` is your mod): implement the reversible codec** — make the M2 `<contents>` field a reversible token over Mineclonia's storage (meta `compressed` = base64 of zstd, or the empty key `""` = serialized list) so `stack_from_key` rebuilds M2 stacks. Constraints: the token must not contain a pipe character (the M2 key's six fields are pipe-separated and parsed at `dev-tests/test_ah_keys.lua:153,167`); M0/M1 keys stay byte-identical; other consumers compare contents opaquely. The report calls the hash "a simplification, not an extension" (§4 closing) — preferred route is implement; the alternative (amend the shared "hash" wording at `02-architecture.md:95`) is spec-side → propose-only under `## Proposed shared changes`, never a hand-edit | IN-SCOPE |
| E-21 | report ref "backend" | `auto` backend heuristic never picks sqlite | `smp_store/init.lua:46-50` (guards on `package.loaded["lsqlite3"]`, which is never preloaded) | **ESCALATE (integrator-owned)**; §10 entry | ESCALATE (integrator) |
| E-22 | f01 §6 (`:155`) | `pay_accept` stored inside `record.social`, not the f12-owned setting path §6 names | `init.lua:71-86` (`pay_accept_on`/`set_pay_accept` over `r.social`); validation call at `:206` | Route reads/writes through f12's canonical accessor `smp_settings.get/set(name, "eco.pay_accept")` — §6's `get_name` is a stale name, normalise it in your own file citing **F12-A** (`f12-settings.md:248`) — **but keep `record.social.pay_accept` as the offline-authoritative fallback plus a one-time migration**: f12 stores in player meta, so `get` on an offline name returns the default/nil and `set` on an unregistered id returns false (`f12-settings.md:292,304-306`). A naive swap would make `/pay` ignore an offline recipient's explicit OFF, or refuse by default. Registering `eco.pay_accept` belongs to f12's registry — if you conclude registration is required for full §6 conformance, raise it in §10 as a cross-feature ask (and `fixes/f12-settings.md`); do not edit `smp_settings` | IN-SCOPE |
| E-23 | f01 §9 T5 (`:201`) | T5 asserts `>= 2` ledger rows instead of the exact two | `smp_economy/test.lua:75-77` (`ok(#alice_ledger >= 2, …)`; the comment at `:76` even documents the extra rows) | Count ledger rows immediately before and after the `/pay` and assert the delta is **exactly 2** (one debit, one credit, both `pay`), plus supply conservation | IN-SCOPE |
| E-24 | f01 §9 T6 (`:202`) | Flag path unasserted — only transfer success is asserted; no flag is observable because no flag API exists | `smp_economy/test.lua:87`, `dev-tests/test_economy.lua:302` (success-only asserts) | **ESCALATE → D9**: record BLOCKED(D9) in §10 and in a test comment; the success half stays asserted. Once D9 lands, assert the flag fires for $2M → a 10-minute account and does not fire below the threshold or above the playtime floor | ESCALATE (D9) |
| E-25 | f01 §9 T7 (`:203`) | No test for `/pay` prefix completion | grep `T7` in `dev-tests/test_economy.lua` → 0 matches | Write T7: a unique prefix resolves to the full name, an ambiguous prefix is refused, an exact name wins, matching is case-insensitive — driven through `/pay`'s param resolution (`init.lua:192`) | IN-SCOPE |
| E-26 | f01 §9 T8 (`:204`) | No balance-persistence / restart test | grep `T8` in `dev-tests/test_economy.lua` → 0 matches | Write T8: balances and ledger survive a simulated restart (re-instantiate the store driver over the same storage stub and re-read). Document in the test that the crash-mid-flush half ("loses at most `store.flush_interval`") is currently satisfied *a fortiori* by write-through; a true crash simulation is blocked on R12 (E-06) | IN-SCOPE |
| E-27 | f01 §3.3 (`:65`, OBSERVED, period-free) | `smp_quickbuy` renders the race string with a trailing period — two mods disagree in production | `smp_quickbuy/buy.lua:87` (`S("This item was already bought.")`) vs the OBSERVED period-free form (`shared/08-ui-strings.md:148`; `smp_ah` is correct) | **ESCALATE → D1** (`fixes/01-integrator-decisions.md:41`) — `smp_quickbuy` is f05's mod, outside your edit surface. Record in §10; change nothing outside `smp_economy`/`smp_items` | ESCALATE (D1) |
| E-28 | precondition (report §2, `00-P0-blockers.md` B1-1/B4-1) | The pack does not boot: `smp_store` calls `core.register_on_globalstep`, and f01's own harness hides it behind a fake — green suites give false assurance until 00 lands | `smp_store/init.lua:351` (B1-1); fake at `dev-tests/test_economy.lua:207` (B4-1) | Both sites belong to `00-P0-blockers.md`: B1-1 is integrator-owned `smp_store`, B4-1 deletes the fake **after** B1. Do not fix here; note the dependency in §10 if you are not the integrator. Your suite must never gain new stubs of names the engine lacks | DEPENDS-BLOCKER (B1-1, B4-1) |

### Notes on the trickiest rows

- **E-01** ordering: blocks check belongs with the other validations, before the
  first mutation (shared §2.3 — no yields between validate and mutate). The
  refusal must be f11's *generic* message: X9 forbids revealing the block.
- **E-02** has no `last_seen` field in the schema (f01 §5.1) — that is why the
  suggested mechanism is `smp_economy`-local pending storage rather than a
  ledger scan. Anything requiring a new `smp_store` field is ESCALATE.
- **E-08** is CLONE-status behaviour (`/eco` row): there is no observed
  evidence either way, so a §10 question is cheap — silently ignoring an
  argument is not acceptable in either direction.
- **E-18** choose one enforcement point and prove it with a test that changes
  `economy.max_balance` and observes the cap; leave the reconciliation ruling
  itself to D7.
- **E-22** the fallback chain must be: settings value if readable →
  `record.social` value → default **on**. Default-on is the current,
  spec-consistent fallback (`pay_accept_on` at `init.lua:71-79`).

## Acceptance criteria

1. [E-01] `/pay` from A to B when B has blocked A returns the generic refusal,
   moves no money, and writes no ledger rows (X9 `/pay` leg demonstrable).
2. [E-02] A payment to an offline recipient is shown as a summary line when
   that recipient next joins; read-and-clear happens with no yield between.
3. [E-04] A second `/pay` from the same sender within one second is refused
   with no ledger row; the first succeeds.
4. [E-07] `/ledger` succeeds for a moderator-only holder and for an admin
   holder, is denied to a player with neither; `/eco` remains admin-only.
5. [E-08] `/eco reset bob 12.34` leaves bob at 1234 cents (not 0) with a
   ledger reason; a missing or invalid amount is rejected — never ignored.
6. [E-09] `/smp test` runs to completion with no `attempt to call a nil value`.
7. [E-10, E-25] T7 green: unique-prefix / ambiguous / exact / case-insensitive
   cases pass; the engine limitation is documented in the §10 table and the
   code comment.
8. [E-11, E-13] `init.lua:502-510` strings all pass through the translator;
   a grep over `smp_economy` and `smp_items` shows no invented string ending
   in `.` unless it is catalogued in `shared/08-ui-strings.md` (spot-check the
   lines named in E-13).
9. [E-18] `economy.max_balance` is either enforced (test proves the key moves
   the cap) or the dead reads are removed — either way the D7 mirror
   consequence is recorded in §10 / `## Proposed shared changes`, and T10 stays
   green.
10. [E-20] M2 round-trip green: a shulker with contents → `key(stack,"M2")` →
    `stack_from_key` rebuilds a stack with identical contents; both the
    `compressed` and the empty-key storage forms round-trip; the M2 key still
    parses into its six fields per `test_ah_keys.lua:167`, with a token that
    contains no pipe character; M0/M1 keys are byte-identical to today.
11. [E-22] The recipient toggle works for online *and* offline targets: an
    explicit OFF still refuses payment, ON still pays, and an
    unregistered/nil settings value never flips the default-on fallback;
    `/paytoggle` round-trips.
12. [E-23] T5 asserts a ledger delta of exactly two plus supply conservation.
13. [E-26] T8 green: balances persist across the simulated restart, with the
    crash-window rationale in the test comment.
14. [E-03, E-05, E-06, E-12, E-14, E-15, E-16, E-17, E-19, E-21, E-24, E-27,
    E-28] each has an entry in §10 of `spec/features/f01-economy-core.md`
    naming its D-ID / B-ID / target brief, and no file outside your edit
    surface was modified.

## Tests

- Extend `friedcake/dev-tests/test_economy.lua` (add a `register_on_joinplayer`
  hook to the core stub first — the stub at `:203-210` does not have one;
  pattern: `dev-tests/test_ranks.lua`'s `join_handlers`):
  - T7 prefix-resolution cases (E-25);
  - T8 restart persistence (E-26);
  - R9 `/pay` cooldown case (E-04) — within-window refused, outside-window ok;
  - `/ledger` OR-privs cases (E-07): stub privilege lookups, assert all three
    holder combinations;
  - `/eco reset <amount>` (E-08);
  - blocks wiring (E-01) with `smp_social` stubbed **as a real API**
    (`blocks(a,b)` exists — only stub the counterpart mod, never a
    nonexistent engine name);
  - offline-join summary (E-02) by driving the registered join handler.
- Extend `friedcake/mods/smp_economy/test.lua`: T5 exact-delta assertion
  (E-23); keep T6's success assert and add a `BLOCKED(D9)` marker comment for
  the flag half (E-24).
- **Create** `friedcake/mods/smp_items/test.lua` (AGENTS step 7 — currently
  absent) with the M2 codec round-trip and M0/M1 invariants (E-20).
- **Create** `friedcake/dev-tests/test_items.lua` — a headless driver for
  `smp_items` under a `core` stub (copy the stub pattern from
  `test_economy.lua`). Do **not** put M2 cases into another feature's suite;
  `test_ah_keys.lua` (f03) and `test_sell.lua` (f02) stay untouched.
- Exact commands, all of which must exit 0:

  ```
  luajit friedcake/dev-tests/test_economy.lua
  luajit friedcake/dev-tests/test_items.lua
  luajit friedcake/dev-tests/test_fmt.lua
  luajit friedcake/dev-tests/test_store.lua
  luajit friedcake/dev-tests/test_ah_keys.lua
  ```

  The last two are no-touch regression runs: `test_fmt`/`test_store` must stay
  green, `test_ah_keys` must still parse the M2 structure (its six-field
  assertion at `:167` is the compatibility gate for E-20).

## Constraints

Standing rules (from `AGENTS.md`, repeated in every brief):

- **No edits to `spec/shared/`, `spec/plan/`, `spec/README.md`.** All shared
  files above are READ ONLY; proposed mirror/spec changes go in your feature
  file under `## Proposed shared changes` or §10.
- **No edits to `smp_core`, `smp_store`, `smp_admin`** — every such site is an
  ESCALATE row above (E-05, E-06, E-12, E-14, E-15, E-16, E-17, E-19, E-21,
  plus D9 for E-03/E-24).
- **One agent per feature file.** Your edit surface: `smp_economy`,
  `smp_items`, their test files, `friedcake/dev-tests/test_economy.lua` (+ new
  `test_items.lua`), and your own `spec/features/f01-economy-core.md`. Do not
  touch `smp_quickbuy` (E-27 → D1), `smp_social` (E-01 wiring is call-only),
  or any other feature's mod. Cross-mod seams are propose-only via your
  feature file's `## Proposed shared changes` / §10.
- Your own feature file `f01-economy-core.md` is yours to update for: §10
  escalation entries, declaring `/payto` in §2 if kept, the F12-A
  `get_name` → `get` rename in §6, and `## Proposed shared changes` — **never
  rewrite or downgrade an OBSERVED row.**
- **Money is integer cents**, always rendered via `smp_core.fmt_money` (both
  observed spacings, shared §0.6 — do not normalise).
- **All player-facing strings through `core.get_translator`** (E-11, E-13).
- **No yields between validate and mutate** in any economic operation
  (shared §2.3) — applies to E-01, E-02, E-04.
- **Verbatim UI strings character-exact** — anything in
  `shared/08-ui-strings.md`, and the OBSERVED §3.3 strings, byte-for-byte.
- **Config keys must match `shared/06`** — propose mirror changes, never
  hand-edit (E-18 → D7).
- **Never downgrade an OBSERVED requirement.**
- Do not delete the harness fakes listed in `00-P0-blockers.md` B4-1
  (E-28) — that cleanup belongs to brief 00, after B1.

## Out of scope

- Everything in the report's **Confirmed OK** list — preserve it: `/pay`,
  `/bal` + aliases, `/baltop`, `/shards`, integer cents throughout, no yields
  on the pay path, `fmt_money` on every money display, economy caps via store,
  `smp_items` M0/M1, the period-free race string in `smp_ah`, and T1–T4/T9/T10.
- In-game boot verification — blocked on `00-P0-blockers.md`; state that
  explicitly in your report if no real server can be run.
- D11 (integration-test seam policy) and any harness redesign beyond the
  fakes you are told not to touch.
- D2 (f02 receipt screen), f16 legacy, f09/f08 items, f03/f04 behaviour —
  other briefs.
- Behavioural changes to `smp_ah`, `smp_quickbuy`, `smp_orders`, `smp_tp`,
  `smp_social`, `smp_settings`.

## Beyond spec to keep

- `/payto` (`init.lua:244`) — scripting-friendly exact-name alias; if you keep
  it, **declare it in §2 of `spec/features/f01-economy-core.md`** so it stops
  being an undeclared addition.
- Prefix-resolution completion (`init.lua:155-179`) — keep (E-10), document
  the engine limitation rather than deleting it.
- The hash-based stack signature is *not* kept: it is the simplification E-20
  replaces.

## Definition of done

1. Every issue ID above is either fixed, or escalated with a reason recorded
   in §10 of `spec/features/f01-economy-core.md` naming its D-ID/B-ID/target.
2. All five dev-test commands in Tests exit 0 (paste the output into the
   branch description).
3. In-mod test files updated: `smp_economy/test.lua` extended (T5 exact-two,
   T6 marker), `smp_items/test.lua` created with the M2 round-trip.
4. `git checkout -b agent/f01-economy-fixes` from `main`; commit with a
   message referencing `SPEC-CONFORMANCE-REPORT.md §4 f01`; push the
   **branch**, never `main`.
5. Report back with a mapping table: issue ID → evidence (`file:line`) →
   outcome (fixed | escalated + target).
