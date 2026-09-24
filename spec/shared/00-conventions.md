# 0. Conventions

Read by every implementer. Owned by the integrator.

## 0.1 Requirement keywords

MUST, SHOULD and MAY are used as defined in RFC 2119.

## 0.2 Evidence tags

Every requirement carries a tag so implementers can tell observation from
inference. The tags are ordered: prefer the strongest available.

| Tag | Meaning | Strength |
|---|---|---|
| `OBSERVED` | Directly visible in the source video. Cited with a frame id. The verbatim string or layout is a **requirement**, not a suggestion. | 1 (strongest) |
| `LIVE` | Documented as current Donut SMP behaviour (September 2026) in a wiki, the official API or a community reference. Not seen on screen. | 2 |
| `LEGACY` | Documented Donut SMP behaviour that has since been removed. Specified as an optional module; the legacy modules are permanently descoped (D8, 2026-09-24) and will never be built. | 3 |
| `CLONE` | Not documented for Donut SMP. Taken from Donut-style clone plugins. Plausible, not authoritative. | 4 |
| `PROPOSED` | A default or design decision introduced by this specification. Replace with a measured value where possible. | 5 (weakest) |
| `N/A` | No practical Luanti equivalent. Listed for completeness. | — |

Rules:

1. **`OBSERVED` beats everything.** Where an observation contradicts a
   documented or clone-derived claim, the observation wins and the
   contradiction MUST be recorded, not deleted. v0.1 carried several claims the
   video disproves; see `plan/open-questions.md`.
2. Where a feature is only partly evidenced, the evidenced part carries its tag
   and the remainder is `PROPOSED`.
3. A file with no `OBSERVED` requirements is unverified against the live
   server. Say so in its section 1 rather than letting the reader assume
   otherwise.

## 0.3 Citation formats

| Form | Means | Example |
|---|---|---|
| `[F0242]` | Video frame 242, file `frames/frame_0242.jpg` | Settings - Chat toggle list |
| `[F0242 @ 00:04:01]` | The same, with its timestamp, when timing matters | — |
| `[S5]`, `[C1]`, `[M1]`, `[T1]`, `[V1]` | Source list in `07-sources.md`. `S` Donut SMP, `C` clone plugin, `M` Mineclonia source, `T` tool, `V` video | — |

Frame images are on disk. From a feature file, link them as
`../../frames/frame_0242.jpg`.

### 0.3.1 Reliability of frame citations

Frame descriptions were produced by a vision-language model
(Qwen2.5-VL-72B-Instruct) reading 1920×1080 frames, not by a human
transcriber. Consequences implementers MUST respect:

- **Heavily pixelated text is sometimes misread.** `Server Hotbar Messages`
  was read once as `Server nowar messages` [F0242]; `Scoreboard` was read once
  as `Social` [F0240]. Where frames disagree, this specification takes the
  majority reading and records the conflict.
- **A string seen in one frame only is weaker than one seen in several.**
  Single-frame strings are marked "single frame" where it matters.
- **Positions are approximate.** "Top-left of the menu grid" is reliable;
  exact pixel offsets are not, and none are specified here.
- **Absence is not evidence.** A control not described may still exist. Never
  write "there is no X" on frame evidence alone.

## 0.4 Screenshots

Cited frames resolve to real images in `frames/`. Features with no frame
coverage carry `SS-nn` placeholders in the form
`![SS-nn: caption](../../screenshots/SS-nn-slug.png)`; save an image at that
path and the link resolves. The outstanding list is in
`plan/open-questions.md`.

## 0.5 UI fidelity and naming

**This specification is a verbatim clone of the observed interface.**

1. Menu titles, button labels, tooltips and server messages MUST reproduce the
   observed strings exactly, including capitalisation, spacing and punctuation
   — `Settings - Chat`, `Orders -> Deliver Items`, `Click to toggle`,
   `Choose Item (1 results)`. The grammatical oddity in `(1 results)` is
   reproduced, not corrected.
2. Observed layout — element order, grouping, which control sits in which
   corner, what a click opens — MUST be reproduced.
3. **The one exception is server identity.** Strings naming the reference
   server are configurable. `Choose a category to change your Donut SMP
   settings` [F0236] becomes
   `Choose a category to change your @1 settings` with the server name
   substituted. No other string is genericised.
4. Where a string is unobserved, invent one in the observed house style:
   sentence case, no terminal full stop, `Click to <verb>` for affordance
   hints, `<Noun>: <Value>` for toggles.

> **Change from v0.1.** §0.5 of the previous version read: *"the target server
> should use its own branding: this specification covers mechanics only."*
> That position is reversed. The project goal is to recreate the interface, and
> 141 frames of interface evidence are now available. Mechanics alone would
> discard most of it.

Mod names use the working prefix `smp_` (for example `smp_spawners`). Rank
tiers are `tier1` to `tier3` in configuration; Donut SMP rank names (Donut+,
Donut++, Donut+++) appear only when describing the reference server.
Itemstrings are Mineclonia's (for example `mcl_mobitems:bone`).

### 0.5.1 Item identifiers in the interface

Observed tooltips end with the Minecraft itemstring and a component count:

```
Ender Pearl
$700
minecraft:ender_pearl
15 component(s)
```

`minecraft:ender_pearl` MUST become the Mineclonia itemstring
(`mcl_throwing:ender_pearl`). `15 component(s)` is a Java data-component count
with no Luanti meaning and MUST be omitted — it is the one observed tooltip
line that is dropped rather than translated. Everything above it is kept.

## 0.6 Units and formatting

- Money is displayed with a `$` prefix and compact suffixes K (10³), M (10⁶),
  B (10⁹) and T (10¹²). Observed forms: `$700`, `$ 5.1K`, `$ 9K`, `$ 25K`,
  `$ 30K each`, `$ 182K each`, `$ 4M each`, `$ 754k` [F0108, F0055, F0124,
  F0115, F0212, F0159, F0164, F0287].
- **Observed spacing is inconsistent**: `$700` with no space [F0108] and
  `$ 30K` with a space [F0212] both appear. The suffixed form uses a space and
  the bare form does not. Implementations MUST follow that rule and MUST NOT
  normalise it away.
- Quantities use the same suffixes in lower case: `2.1k/2.5k Delivered`
  [F0159], `753k/1.3m Delivered` [F0160], `167k/200k Delivered` [F0212],
  `300K requested` [F0219]. Case is inconsistent in the source; use lower case
  for quantities and upper case for money.
- Every numeric input MUST accept the same suffixes case-insensitively
  (`250k`, `1.5m`).
- Durations are in seconds unless stated otherwise.
- "Stack" means a Luanti ItemStack. "Spawner stack" means the number of
  spawners merged into one node.

## 0.7 Numeric representation

Money is stored as integer cents in Lua numbers, exact to 2⁵³. The maximum
balance is 10¹³ dollars (10¹⁵ cents), following clone defaults [C1]. Inputs
MUST reject negative, NaN and infinite values. Fees round down in the payer's
favour.

## 0.8 Localization

Donut SMP added translations in 30 languages in a July 2026 beta, selected from
the player's client language [S22]. Luanti translates server strings through
`core.get_translator(textdomain)`. Every player-facing string MUST use it, and
MUST be listed in `08-ui-strings.md`.
