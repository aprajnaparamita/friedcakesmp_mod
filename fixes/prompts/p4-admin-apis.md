# Agent prompt — P4: D9 + D10 — `smp_admin` flag and mute APIs

| Field | Value |
|---|---|
| Feature spec | no feature file — `smp_admin` is integrator-owned; command rows in `spec/shared/05-command-reference.md §5.5` |
| Target | `friedcake/mods/smp_admin/`, `friedcake/dev-tests/test_admin.lua` |
| Audit source | `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D9 + D10 (both = Option A) |
| Verdict at audit | high — f01 §4.2.5 flags and f11 §4.1.3 mutes have no producer; two briefs blocked |
| Branch | `agent/rulings-admin-apis` (base: `agent/integrator-decisions`) |
| Wave | 1 — runs in parallel with P1 and P3 |

## Mission

The spec requires two moderation primitives that nothing in the pack can
produce: **transfer flags** (f01 §4.2.5 — "flagged for staff review. Flagged,
not blocked") and **mutes** (f11 §4.1.3 — the chat callback enforces mutes but
`smp_social/bridges.lua:97-104` probes `smp_admin.is_muted`, finds nothing,
and always answers false). D9=A and D10=A: build both APIs in `smp_admin` with
tests. The *consumers* (`/pay` flag call, social's honesty cleanup) stay with
their feature briefs — you provide the capability, they wire it.

`smp_admin` is currently 26 lines of privilege registration. Keep that
character: small, dependency-free, no yields, everything through
`core.get_translator`.

## Read this first (in order)

1. `AGENTS.md` — rules 1–8; rule 4 names `smp_admin` integrator-owned, and
   **this prompt is the integrator's explicit ask** (D9/D10 rulings).
2. `fixes/01-integrator-decisions.md` § *Rulings — 2026-09-24*, D9/D10 rows.
3. `spec/features/f01-economy-core.md` §4.2.5 (flag semantics) and
   `spec/features/f11-social.md` §4.1.3 (mute enforcement contract).
4. `spec/shared/05-command-reference.md` §5.5 (where admin commands and the
   `smp_moderator` privilege live — the blurb already says "read-only audit,
   mutes").
5. Existing patterns: `friedcake/mods/smp_admin/init.lua` (26 lines),
   `friedcake/dev-tests/test_store.lua` (fake-`core` + mod-storage harness
   style), `friedcake/mods/smp_ranks/test.lua` (in-mod test file shape).

## Requirements

**R1 — D9: `smp_admin.flag(kind, detail)`.**
- Signature: `smp_admin.flag(kind, detail) -> id` — `kind` a short
  snake_case string (e.g. `large_transfer_to_new_account`), `detail` a
  preformatted string (the caller formats money; you do no money math).
- Behaviour, in one non-yielding call:
  1. Append `{t = os.time(), kind = kind, detail = detail}` to a ring buffer
     persisted in `smp_admin`'s mod storage (cap 500 entries, drop oldest).
  2. `core.log("warning", "[smp_admin] flag " .. kind .. " " .. detail)`.
  3. Notify every **online** player holding `smp_admin` **or** `smp_moderator`
     via `core.chat_send_player`, with a translated string (no players online
     is fine — the persistent buffer is the record of truth).
- All player-facing text through `core.get_translator`. No yields anywhere
  (this sits in f01's transfer path later — §2.3 discipline applies to the
  call site, but the API itself must stay synchronous and cheap).
- Accessor for tests/future UI: `smp_admin.flags() -> array` (oldest-first
  copy).

**R2 — D10: mute trio.**
- `smp_admin.mute(name, seconds)` — `seconds` nil or `0` = permanent;
  persists `{expires_at = os.time()+seconds, or 0}` under the player name in
  mod storage. Returns `true`.
- `smp_admin.unmute(name)` — clears the entry; returns `true` if one existed.
- `smp_admin.is_muted(name) -> boolean, remaining_seconds?` — must:
  work for **offline** names (storage-backed), survive restart, apply lazy
  expiry (an expired entry reads as not-muted and is cleaned up on read),
  and never throw (the `smp_social` bridge `pcall`s you, but stay clean
  anyway). `remaining_seconds` only when muted with a finite duration.
- Contract check: `smp_social/bridges.lua:97-104` calls
  `smp_admin.is_muted(name)` expecting a plain truthy/boolean — your return
  satisfies it as written. **Do not edit `smp_social`.**

**R3 — D10: commands.**
- `core.register_chatcommand("mute", { params = "<player> [seconds]", … })`
  and `"unmute" { params = "<player>" }`.
- Privilege check: allow if the caller has `smp_moderator` **or**
  `smp_admin` (Luanti has no privilege hierarchy — check both explicitly).
- `/mute <player> [seconds]` — omitted duration = permanent; non-numeric or
  negative duration → translated usage message, no state change. Works on
  offline names. Reply messages: target, duration (or `permanent`), via
  translator.
- `/unmute <player>` — translated "not muted" response when there was no
  entry.
- Register both rows in `spec/shared/05-command-reference.md` §5.5's table
  (`| /mute | <player> [seconds] | Mute a player (moderation) | f11 |` style;
  spec column `f11` since §4.1.3 is the enforcement contract, or
  `shared §5.5` — match the table's existing convention). Keep the §5.5
  "audit, mutes" privilege blurb accurate.

**R4 — tests.**
- New `friedcake/dev-tests/test_admin.lua` (standalone `luajit`, fake-`core`
  style after `test_store.lua` — you need: `get_mod_storage` fake,
  `get_translator` identity, `log` capture, `register_privilege`,
  `register_chatcommand` capture, `get_connected_players`,
  `get_player_privs`, `chat_send_player` capture). Required cases:
  1. flag appends, returns id, persists across a simulated reload;
  2. flag ring cap evicts oldest (create 501);
  3. flag logs a warning and notifies exactly the online staff;
  4. flag does **not** notify offline or unprivileged players;
  5. mute → `is_muted` true, with remaining seconds;
  6. permanent mute (no seconds) → true with no expiry;
  7. expiry: stub time (save/restore `os.time` around the case) — future
     expiry reads true, past expiry reads false and the entry is cleaned;
  8. unmute clears; second unmute is a safe no-op;
  9. `/mute` parses `90`, `permanent`/omitted, rejects `abc` with usage,
     requires priv (player without either priv gets the deny message);
  10. `/unmute` requires priv and reports "not muted" correctly.
  No `os.sleep` anywhere — inject time.
- New `friedcake/mods/smp_admin/test.lua` — in-mod file matching
  `smp_ranks/test.lua`'s shape (`{passed, failed, lines}` results, same case
  names T1…T10) covering the API halves.
- `modpack.conf`: verify `load_mod = smp_admin` already present
  (`modpack.conf:11`) — **no modpack.conf edit expected**; if you think one is
  needed, stop and escalate instead.

## Out of scope (hard)

- `spec/features/f01-*` and `spec/features/f11-*` — unchanged by design (D9/D10
  = build the API, not amend the spec).
- `friedcake/mods/smp_economy/` — the `/pay` flag call at
  `smp_economy/init.lua:234-236` is the **f01 brief's** consumer row.
- `friedcake/mods/smp_social/` — the bridge works as written; the F11-5
  honesty/TODO cleanup is the **f11 brief's** row.
- `spec/shared/06-config-reference.md`, `spec/plan/**`, other features' §7
  tables, `fixes/**`.

## Tests

- `luajit friedcake/dev-tests/test_admin.lua` → exit 0 with all ten cases.
- Full suite green: every `friedcake/dev-tests/test_*.lua` exits 0 (this adds
  the 23rd–24th test files; re-derive the count from the directory).
- Post-condition greps:
  - `grep -n 'function smp_admin.flag' friedcake/mods/smp_admin/*.lua` → 1
  - `grep -n 'function smp_admin.is_muted' friedcake/mods/smp_admin/*.lua` → 1
  - `grep -rn 'TODO(admin)' friedcake/mods/smp_social/bridges.lua` → still
    there (not yours to remove)
  - `grep -n '/mute' spec/shared/05-command-reference.md` → rows present

## Constraints

- Money integer cents (you handle none, but `detail` strings come from f01 —
  don't reformat them); all strings through `core.get_translator`; no yields
  in anything you add; storage only via `core.get_mod_storage`.
- Files you may write: `friedcake/mods/smp_admin/**`,
  `friedcake/dev-tests/test_admin.lua`,
  `spec/shared/05-command-reference.md` (§5.5 table rows only — P3 annotates
  legacy rows elsewhere in the file in parallel; keep your edit a
  line-disjoint insert). Everything else → ESCALATE + stop.

## Definition of done

1. R1–R4 complete; `test_admin.lua` and the full suite green; in-mod
   `test.lua` present.
2. Commit with `D9 D10` in the message; push `agent/rulings-admin-apis`,
   never `main`.
3. Reply with: API signatures as landed, the ten test case names, the §5.5
   rows added, and confirmation that economy/social/spec-feature files were
   untouched.
