# Fix brief — f12 Player settings

| Field | Value |
|---|---|
| Feature spec (read-only) | `spec/features/f12-settings.md` |
| Target mod(s) | `smp_settings` |
| Audit source | `SPEC-CONFORMANCE-REPORT.md` §4 — f12 |
| Verdict at audit | **MOSTLY COMPLETE (4 gaps)** · ~26 OK · T1–T8 green; T9 absent |
| Branch | `agent/f12-settings-fixes` |
| Depends on | **D3** and **D7** (`01-integrator-decisions.md`); `fixes/f11-social.md` (T9 harness); `00-P0-blockers` (in-game verification only) |

---

## Mission

`f12` is one of the healthiest mods in the pack — T1–T8 are strongly covered
by a 517-line dev-test including a simulated restart and forged-id tests — but
four audit gaps remain: the observed **yellow warning triangle is not drawn on
either screen**, the documented `settings.categories` config key is dead, the
§4.7 "most permissive" defaults prose contradicts the implemented
`FRIENDS_FOLLOWED` defaults (both spec self-conflicts routed to **D3**), and
**T9 has never run** because f11 shipped no harness. Fixed means: the triangle
renders in both menu renders with a test asserting it, both D3 rows are written
up so the integrator's ruling has a place to land, hygiene drift (terminal full
stop, duplicate local) is gone, and T9 is delivered through the f11 harness —
without moving a single observed pixel of the first-open screen.

## Read this first (in order)

1. `AGENTS.md` — hard rules 1–8.
2. `spec/features/f12-settings.md` — §3.1/§3.2 (the observed layouts with the
   triangle), §4.7, §7, §9 (T1–T9), §10 (F12-B, F12-C, F12-D — the
   self-documented conflicts you must not "fix" unilaterally), and the
   `## Proposed shared changes` block (your §324-329 proposal for
   `settings.cycle_order` already exists — reference it, don't duplicate it).
3. `spec/shared/02-architecture.md`, `04-ui-kit.md` (§4.5 label/glyph rules,
   `:53-56` the triangle paragraph and V-28), `05-command-reference.md`
   (`/settings` row), `06-config-reference.md:76` (`settings.categories`),
   `08-ui-strings.md` (READ ONLY).
4. `spec/plan/acceptance-tests.md:26` — f12's T1–T9 row is the merge gate.
5. `SPEC-CONFORMANCE-REPORT.md` §4 f12 (lines 625–654).
6. `friedcake/mods/smp_settings/` (`accessor.lua`, `chat.lua`, `formspec.lua`,
   `init.lua`, `registry.lua`, `store.lua`, `test.lua`) +
   `friedcake/dev-tests/test_settings.lua` (517 lines).

## Issues to fix

| ID | Spec ref | Problem | Evidence (file:line) | Required fix | Class |
|---|---|---|---|---|---|
| F12-1 | §3.1 / §3.2 | **Yellow warning triangle MISSING** — the observed layout draws `Settings ⚠` and `Settings - Chat ⚠`; both renders emit plain labels | `smp_settings/formspec.lua:63-68` (category menu `parts` block, title label only) and `:109-114` (category screen, same); grep `⚠\|triangle` across `smp_settings/` → **none** | **Default action: implement it.** Append the glyph to the right of the title in **both** renders, using the correct UTF-8 bytes for U+26A0: `"\226\154\160"` — the same correct sequence the pack already uses (`smp_tp/homes.lua:72`: `TRIANGLE = "\226\154\160"`). **Do NOT copy `smp_tp/formspec.lua:35`'s broken `"\241"`** (a truncated 1-byte fragment of the 3-byte sequence — renders as garbage). Meaning is open question V-28 (`shared/04:53-56`) but §0.5 rule 2 makes the observed layout normative: draw it even though its meaning is unestablished. Add a test asserting the triangle element exists in **both** the category-menu and the `Settings - Chat` renders | **IN-SCOPE** (only if you judge the glyph's exact form genuinely unverifiable, this becomes **DECISION → ESCALATE V-28 / new D-ID**; do not silently skip) |
| F12-2 | §7 / `shared/06:76` | `settings.categories` configurable — **DIVERGENT**: never read. Only config read is `settings.cycle_order`; the seven categories are hard-registered | `smp_settings/init.lua:39-45` (the sole `cfg` entry), `chat.lua:18-21` (chat registered in code) and `init.lua:88-101` (the six others registered from the `CATEGORIES` table); grep `settings\.categories` in `smp_settings/` → only the internal registry field `smp_settings.categories`, never a `core.settings:get` | Spec self-documents this as deliberate (**F12-C**, `f12-settings.md:250`) — **ESCALATE → D3** (integrator either corrects §7/`shared/06` or asks for the key to be read). **Do not hand-edit the mirror.** Optional IN-SCOPE improvement while waiting: accept the key as an *ordering/filter* input with the current registration as default (parse, apply, fall back to registration order) — **only** if it cannot change the observed category order T1 asserts | **ESCALATE → D3** (+ optional IN-SCOPE ordering input) |
| F12-3 | §4.7 | Defaults DIVERGENT — four rows default `FRIENDS_FOLLOWED` where §4.7's prose says "most permissive" | `smp_settings/chat.lua:41` (`private_messages`), `:62` (`death_messages`), `:69` (`advancements`), `:76` (`join_leave`) all `default = "FRIENDS_FOLLOWED"`; conflict self-documented at `f12-settings.md:249` (F12-B); §5's stored schema (`f12:149-158`) supports the code | **Code must NOT change** — reverting breaks the observed first-open screen [F0242] and §0.5 fidelity (D3's option B is explicitly "not viable for F12-B"). Your job: make the doc say **which side wins once D3 rules** — i.e. draft the §4.7 amendment text (or the "code is right, prose is wrong" note) in your §10/escalation entry so the ruling lands as a one-line edit, and keep T1's observed-value assertions (`Public Chat: ON`, `Private Messages: Friends/Followed`, …) exactly as they are | **ESCALATE → D3** (doc-side only; no code change) |
| F12-4 | §9 T9 | T9 MISSING — the `FRIENDS_FOLLOWED` stranger-`/msg` refusal leg is untested; f11 has no harness | code path exists: `smp_social/pm.lua:45-51` (the `FRIENDS_FOLLOWED` branch calling `generic_refusal()`); `dev-tests/` has no `test_social*.lua`; `dev-tests/test_settings.lua:5` says "T9 is f11's stranger-/msg test, not ours" | After `fixes/f11-social.md` lands `friedcake/dev-tests/test_social.lua`, add the T9 leg **there** (assert recipient's `chat.private_messages = FRIENDS_FOLLOWED`, sender is a stranger, `/msg` returns exactly `This user only accepts messages from friends or followed players`, nothing delivered). **Cross-reference — do not build a second harness.** If your brief runs first, file the dependency and stop; the row closes only when f11's file exists | **DEPENDS (f11 brief — `fixes/f11-social.md` → `dev-tests/test_social.lua`)** |
| F12-5 | shared §0.5.4 (command descriptions: sentence case, no terminal full stop) | `/settings` description has a terminal full stop | `smp_settings/init.lua:220`: `description = S("Open the settings menu.")` | Remove the full stop → `S("Open the settings menu")`; update the in-mod/dev-test expectation if it asserts the old string | **IN-SCOPE** |
| F12-6 | hygiene | Duplicate `local fs = smp_settings.fs` — shadowed local | `smp_settings/init.lua:82` and `:103` (same assignment twice) | Remove one (keep the later or the earlier — behaviour identical; no functional change) | **IN-SCOPE** |
| F12-7 | §7 vs `shared/06` | `settings.cycle_order` is declared in f12 §7 but **absent from the mirror** | `f12-settings.md:206` declares it; grep `settings.cycle_order` in `spec/shared/06-config-reference.md` → **zero** (the mirror only carries `settings.categories` at `:76`); code reads it at `init.lua:43-44` | The mirror-addition proposal already exists at `f12-settings.md:324-329` — **ESCALATE → D7** (config mirror reconciliation, `01-integrator-decisions.md`). Do not hand-edit `shared/06`; reference the existing proposal in your §10 entry instead of writing a second one | **ESCALATE → D7** |

## Acceptance criteria

1. Both menu renders contain the U+26A0 triangle (`\226\154\160`) to the right
   of the title; a test asserts the element in the category-menu render **and**
   in the `Settings - Chat` render (F12-1). The bytes match
   `smp_tp/homes.lua:72`'s sequence, not `smp_tp/formspec.lua:35`.
2. F12-2 and F12-3 each carry a §10 escalation entry naming **D3**, written so
   the ruling drops into the spec as a single edit; if you implement the
   optional ordering input, T1's observed order still passes byte-for-byte.
3. F12-7 escalation entry names **D7** and points at `f12-settings.md:324-329`.
4. T9 exists in `dev-tests/test_social.lua` (f11's file) and passes; or, if f11
   has not landed, the dependency is recorded and no duplicate harness exists
   (F12-4).
5. `/settings` description has no terminal full stop; only one
   `local fs = smp_settings.fs` remains in `init.lua` (F12-5, F12-6).
6. `luajit friedcake/dev-tests/test_settings.lua` still exits **0** with
   T1–T8 and the new triangle assertions green.

## Tests

- **Extend:** `friedcake/dev-tests/test_settings.lua` — add triangle
  assertions (element present in both renders; assert the exact UTF-8 byte
  sequence, not a mojibake single byte), plus the F12-5 description-string
  assertion if the suite checks it.
- **Extend:** `friedcake/mods/smp_settings/test.lua` — same cases in-mod.
- **Cross-file:** f12's T9 lands in `friedcake/dev-tests/test_social.lua`
  per `fixes/f11-social.md` — do not create `test_f12_t9.lua` or any second
  harness.
- Exact commands (must exit 0):

```sh
luajit friedcake/dev-tests/test_settings.lua   # exit 0 — T1–T8 + triangle
luajit friedcake/dev-tests/test_social.lua      # exit 0 — T9 leg (after f11 brief lands)
```

## Constraints

- **No edits** to `spec/shared/`, `spec/plan/`, `spec/README.md` — the
  `settings.categories`/`settings.cycle_order` mirror questions go through D3
  and D7 (`## Proposed shared changes` / §10 of your own feature file).
- **No edits** to `smp_core`, `smp_store`, `smp_admin` (AGENTS rule 4), and no
  touching other features' mods — in particular **`smp_social` is f11's**
  (T9 lives in their harness, F12-4).
- One agent per feature file — you own `spec/features/f12-settings.md` §10 for
  these entries; do not edit `f11-social.md` (record the dependency in **your**
  §10 and in this branch's notes; the f11 brief's T9 row already points back).
- Money integer cents via `smp_core.fmt_money`; all player-facing strings
  through `core.get_translator`; no yields between validate and mutate.
- **Never change the code side of F12-2/F12-3** (categories registration, the
  four `FRIENDS_FOLLOWED` defaults) — they reproduce the observed screen; D3
  rules on the **doc** side. Never downgrade an `OBSERVED` requirement.
- **Preserve (character-exact / behaviour-exact):**
  - `/settings`; the translucent dark prompt menu;
  - **seven categories in the observed order** with verbatim titles
    `Chat, Notifications, PvP, Visuals, Privacy, Scoreboard, General`, and
    `General` centred beneath;
  - tooltip `Open @1 settings`; subtitle exactly
    `Choose a category to change your @1 settings` with `server.name`
    (default `Donut SMP`);
  - hovered-button purple `#7B2FBE` (PROPOSED hue, documented §10) —
    `formspec.lua:27`;
  - `Settings - Chat` with **space-hyphen-space**;
  - seven toggles in observed order, `<Name>: <Value>` labels, observed
    fresh-profile values (`Public Chat: ON`,
    `Private Messages: Friends/Followed`, …);
  - `Click to toggle`; `Back`; in-place redraw on toggle; tri-state display
    `Friends/Followed` enforced downstream by f11;
  - §5 string-valued keys character-exact (`ON`/`OFF`/`FRIENDS_FOLLOWED` as
    strings); §6 toggle algorithm incl. the untrusted-id guard;
  - `ON → FRIENDS_FOLLOWED → OFF` cycle; store-only separation of concerns;
    JSON in `smp:settings` with unknown keys preserved;
  - T1–T8 (517-line dev-test) all still green.
- Config keys must match `shared/06` — propose mirror changes (D7), never
  hand-edit; verbatim UI strings character-exact.

## Out of scope

- Contents of the six unopened categories (V-36/V-39 candidates) — do not
  register candidate settings while fixing these gaps.
- F12-A accessor normalisation (`get_name` → `get` at f01/f08 call sites) —
  integrator/consumer-side, already recorded.
- Offline `get`/`set` limitations — §10-noted, unchanged.
- Building a second T9 harness or editing `smp_social`/`smp_economy`.
- The V-28 meaning of the triangle — you draw it; its semantics stay open.

## Definition of done

1. Every issue ID F12-1 … F12-7 is **fixed** (with file:line evidence) or
   **escalated with reason + decision ID** (F12-2/F12-3 → D3, F12-4 → f11
   brief dependency, F12-7 → D7) — no ID dropped, no status softened.
2. `luajit friedcake/dev-tests/test_settings.lua` exits 0 (T1–T8 + triangle
   assertions); T9 green in `dev-tests/test_social.lua` once f11 lands; in-mod
   `test.lua` updated.
3. `git checkout -b agent/f12-settings-fixes` from `main`; commit message
   references `SPEC-CONFORMANCE-REPORT.md §4 f12`; push the **branch**, never
   `main`.
4. Issue ID → evidence mapping in the branch description (F12-1 triangle test
   name, F12-2/3/7 §10 entries naming D3/D3/D7, F12-4 cross-reference,
   F12-5/6 diff lines).
