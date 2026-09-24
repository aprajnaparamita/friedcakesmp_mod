# f11 — Social and Communication

## 1. Status and ownership

| Field | Value |
|---|---|
| Mod | `smp_social` |
| Phase | P7 |
| Depends on | `f12-settings` (privacy values), `f13-ranks` (chat prefix) |
| Frame evidence | **23 frames**, 00:04:27–00:05:04 |
| Confidence | **High for chat format and `/msg` refusals**; `/ignore` was typed but its result was never shown |

## 2. Commands

| Command | Aliases | Arguments | Behaviour | Status |
|---|---|---|---|---|
| `/msg` | `/message`, `/tell`, `/w`, `/whisper`, `/pm` | `<player> <message>` | Private message | **OBSERVED** [F0271, F0280] |
| `/r` | `/reply` | `<message>` | Reply to the last private message | CLONE [C1] |
| `/ignore` | — | `<player>` | Ignore a player | **OBSERVED** [F0282, F0283, F0287] |
| `/block` | — | `<player>` | Block a player | LIVE [S24] |
| `/friend` | `/friends` | `[list, friends, followers, following, search, addsearch]` | Follow and friends system | LIVE [S24] |
| `/findplayer` | `/fp` | `<player>` | Coarse location of a player | LIVE [S23][S24] |
| `/nightvision` | `/nv` | — | Toggle night vision | LIVE [S28] |
| `/kill` | — | — | Drop items and respawn, after confirmation | LIVE [S24] |
| `/help`, `/rules` | — | — | Information screens | LIVE [S24] |
| `/discord`, `/media`, `/link`, `/buy`, `/website`, `/ranks`, `/medal` | `/store` | — | Informational links | LIVE [S24][S2] |
| `/ping`, `/list` | `/who`, `/online` | — | Latency; online players | CLONE [C1] |
| `/report`, `/helpop` | `/ac` | `<player> <reason>`; `<message>` | Staff contact | CLONE [C1] |

Tab completion offers player names after `/msg`, `/pay` and `/ignore`
[F0089, F0282, F0287].

## 3. Observed UI

Social features are chat-based; no menu was opened in this segment.

### 3.1 Public chat format [F0269, F0282, F0283]

```
<FoxBuddy2> ah
<IlyKavtaradze> tp for free diamonds
<robieto_faze> TPA FOR TEAM OR 1V1
<5Gdryed> ah fence
<loldarr> rating bases and neth ingot each and dragon head for very good base
<Gucio1125> tp for /duell but only diamond or netherite
<gamer_pao> chat please pay me some money
<tochgras> tpa to gamble!! Please have VC
```

Format: `<@1> @2` — angle brackets, name, space, message. Long messages wrap
without re-indenting.

> **Contradiction with v0.1.** §8.1 specified `[Rank] Name: message`. **No rank
> prefix appears on any of the ~30 observed chat lines**, and the separator is
> angle brackets, not a colon. Either ranked players carry no chat prefix, or
> none spoke during the recording. The observed format is specified below; the
> prefix question stays open (V-24).

### 3.2 `/msg` and the privacy refusal [F0271, F0276–F0285]

The player types `/msg aad5074 hi` [F0271, F0285] and the server answers:

```
This user only accepts messages from friends or followed players
```

Seen across ten frames — one of the best-attested strings in the corpus. It is
the enforcement of `Private Messages: Friends/Followed` (`f12 §3.3`), and it
sets the standard for refusals: **state the reason, not just the failure.**

### 3.3 Clickable teleport affordance [F0270–F0274, F0284, F0288, F0290]

Hovering a player's name in chat shows:

```
Click to send NearHat2738 a teleport request
```

**Luanti chat is not clickable.** Substitution (decided in
`shared/03-mineclonia-api.md §3.3`): emit the same sentence as a plain hint
line, and give the recipient an Accept/Deny formspec (`tp.confirm_menu`,
`f08`). Do not fake clickable text.

### 3.4 `/ignore` [F0282, F0283, F0287]

`/ignore <player>` is typed with name completion. **The result was never
shown** — the recording cuts away. The speaker describes the effect: "to ignore
someone. That means they won't be able to send you messages or teleport
[requests]".

That narration is the only evidence for what `/ignore` does, and it says ignore
covers **both messages and teleport requests** — which collapses the
ignore/block distinction v0.1 proposed. See §4.3.

### 3.5 Not observed

`/block`, friends and follows, `/findplayer` output, `/nightvision`, `/kill`,
any social menu, and the confirmation for any of them.

## 4. Behaviour

### 4.1 Public chat

1. Format is `<@1> @2` (`OBSERVED`). A rank prefix, if any, is
   `PROPOSED` and disabled by default until V-24 resolves.
2. Registered with `core.register_on_chat_message`, returning true and
   delivering the formatted line to every recipient whose `chat.public` is not
   `OFF` and who does not ignore the sender.
3. Mutes are enforced here.
4. Anti-spam: at most one message per second, plus a duplicate filter
   (`PROPOSED`).

### 4.2 Private messages

1. `/msg` and `/r` replace the built-ins through
   `core.override_chatcommand("msg", ...)`.
2. Delivery respects the recipient's `chat.private_messages`
   (`f12`):

   | Value | Behaviour |
   |---|---|
   | `ON` | Delivered |
   | `FRIENDS_FOLLOWED` | Delivered only if the sender is a friend of, or followed by, the recipient. Otherwise the sender receives exactly `This user only accepts messages from friends or followed players` (`OBSERVED`) |
   | `OFF` | Refused. Message `PROPOSED`, in the same style |

3. The refusal goes to the **sender**; the recipient is not notified.
4. Ignore and block lists are checked before the setting.

### 4.3 Ignore and block

Donut SMP offers both [S24] without documenting the difference. The narration
[F0287] says ignore blocks messages **and** teleport requests, which is more
than v0.1 assumed.

| Effect | `/ignore` | `/block` |
|---|:---:|:---:|
| Hide the player's public chat | yes (`PROPOSED`) | yes (`PROPOSED`) |
| Refuse their private messages | **yes** (`OBSERVED`, narration) | yes (`PROPOSED`) |
| Refuse their teleport requests | **yes** (`OBSERVED`, narration) | yes (`PROPOSED`) |
| Refuse their payments | no (`PROPOSED`) | yes (`PROPOSED`) |
| Refuse their follows | no (`PROPOSED`) | yes (`PROPOSED`) |
| Exclude from RTP-queue pairing | no (`PROPOSED`) | yes (`PROPOSED`) |

With ignore covering messages and teleports, the remaining distinction is
economic and social contact. Whether the reference server draws it there is
unknown (V-48).

### 4.4 Friends and follows

Built on follows: `/friend followers`, `/friend following`,
`/friend addsearch`, `/friend search`, `/friend list` [S24]. `PROPOSED`
semantics: following is one-way; mutual follows are friends; friends get join
and leave notices; at most 200 follows.

**This system is load-bearing**, not a side feature: four of the seven observed
chat settings resolve against it (`f12 §3.3`). Build it before, or with,
`f12`.

### 4.5 `/findplayer`

Returns location, rank and username, as the official lookup endpoint exposes
[S23][S24]. On a raiding server exact coordinates would expose bases, so the
location MUST be coarse (`PROPOSED`): `Offline`, `Spawn`, or
`<Dimension> – <Region>`, using `mcl_worlds.pos_to_dimension` [M1].

### 4.6 `/kill`, `/nightvision`, informational commands

- `/kill` drops items and respawns [S24] after a confirmation dialog [C1]. If
  the player is tagged, the death is credited to the last attacker
  (`PROPOSED`), so `/kill` cannot deny a kill or a bounty.
- `/nightvision` toggles `mcl_potions.give_effect_by_level("night_vision",
  player, 1, duration)` and `clear_effect` [M1]. Persists; re-applied on join
  and respawn. The recording shows a `Night Vision II` HUD effect throughout
  [F0122, F0142] — a client-rendered effect indicator, not server UI.
- `/help`, `/rules`, `/discord`, `/media`, `/link`, `/buy`, `/website`,
  `/ranks`, `/medal` display configured text. Luanti cannot open URLs, so links
  go in a read-only formspec field the player can copy from.

### 4.7 Unknown commands

An unrecognised command answers exactly `This command does not exist`
[F0055] (`OBSERVED`). Override Luanti's `Invalid command: <name>`.

### 4.8 Voice chat (`N/A`)

Donut SMP runs proximity voice chat through Simple Voice Chat [S21]; Luanti has
no equivalent. Players reference it in chat ("tpa to gamble!! Please have VC"
[F0283]), so expect it to be asked for.

## 5. Data schema

In the player record (`f01 §5`):

```lua
social = {
  following = { "Bob", "Carol" },     -- one-way follows
  ignored   = { "Dave" },
  blocked   = { "Eve" },
  last_pm   = "Bob",                  -- for /r; not persisted
}
```

Friendship is derived, not stored: A and B are friends iff each follows the
other.

## 6. Algorithms

```lua
function smp_social.send_pm(sender, target_name, message)
  local target = core.get_player_by_name(target_name)
  if not target then return chat(sender, S("That player is not online")) end

  if smp_social.ignores(target_name, sender:get_player_name())
     or smp_social.blocks(target_name, sender:get_player_name()) then
    return chat(sender, S("This user only accepts messages from friends or followed players"))
  end                                  -- generic: never reveal an ignore

  local pref = smp_settings.get(target, "chat.private_messages")
  if pref == "OFF" then
    return chat(sender, S("This user is not accepting private messages"))
  elseif pref == "FRIENDS_FOLLOWED"
     and not smp_social.is_friend_or_followed(target_name, sender:get_player_name()) then
    return chat(sender, S("This user only accepts messages from friends or followed players"))
  end
  deliver_pm(sender, target, message)
end
```

The ignore branch deliberately returns the **same** message as the privacy
branch: revealing that you have been ignored is itself information, and the
observed server gives a single generic refusal.

## 7. Configuration

| Key | Default | Status |
|---|---|---|
| `chat.format` | `<@1> @2` | **OBSERVED** [F0269] |
| `chat.rank_prefix` | false | PROPOSED (no prefix observed; see V-24) |
| `chat.rate_limit` | 1 per second | PROPOSED |
| `chat.duplicate_filter` | true | PROPOSED |
| `social.max_follows` | 200 | PROPOSED |
| `social.friend_notify` | true | PROPOSED |
| `social.tpa_hint` | true | **OBSERVED** in substituted form [F0270] |
| `findplayer.spawn_radius` | 512 | PROPOSED (T9 — the `Spawn` bucket) |
| `findplayer.region_band` | 2048 | PROPOSED (T9 — compass-sector size) |
| `info.help` | `""` | PROPOSED (empty falls back to the generated command list — `/help` is never empty, `info.lua:120`) |
| `info.rules`, `info.ranks` | `""` | PROPOSED (empty answers `This text is not configured` — `info.ranks` has no `link = true`, `info.lua:162-167`) |
| `info.discord`, `info.media`, `info.link`, `info.store`, `info.website`, `info.medal` | `""` | PROPOSED (empty answers `This link is not configured`, `info.lua:67-69`) |

## 8. Mineclonia implementation

- Chat: `core.register_on_chat_message` returning true, then
  `core.chat_send_player` per eligible recipient. Filter per recipient — the
  observed settings are per-player, so there is no single broadcast.
- `/msg`: `core.override_chatcommand("msg", ...)`.
- The teleport hint is a second chat line after the message, not a decoration
  on it. Luanti has no hover or click events in chat.
- Informational commands: a formspec with a read-only
  `field[]`/`textarea[]` holding the URL, selectable for copying.
- `core.register_on_chatcommand` returns the observed
  `This command does not exist` for unknown commands.

## 9. Acceptance tests

| Id | Test |
|---|---|
| T1 | Public chat renders exactly `<Name> message` with no prefix while `chat.rank_prefix` is false |
| T2 | A recipient with `Public Chat: OFF` receives no public lines; everyone else does |
| T3 | `/msg` to a `FRIENDS_FOLLOWED` stranger returns exactly `This user only accepts messages from friends or followed players` and delivers nothing |
| T4 | `/msg` to a friend of a `FRIENDS_FOLLOWED` recipient is delivered |
| T5 | `/msg` to someone who has ignored you returns the **same** refusal, not a distinguishable one |
| T6 | `/ignore <player>` suppresses that player's public chat, private messages and teleport requests |
| T7 | A public message is followed by the teleport hint line naming the sender |
| T8 | An unknown command returns exactly `This command does not exist` |
| T9 | `/findplayer` never returns exact coordinates |
| T10 | Mutual follows register as friends in both directions; a one-way follow does not |

## 10. Open questions

| Id | Question |
|---|---|
| V-17 | `/findplayer` output format — unobserved. Implemented as three `<Field>: <Value>` lines (`Name`, `Rank`, `Location`) with the coarse locations `Offline`, `Spawn`, `<Dimension> – <Region>`; see §10.1 |
| V-18 | Friends and follow semantics — unobserved, yet four chat settings depend on them |
| V-24 | **Reopened.** No rank prefix appears in any observed chat line, contradicting v0.1's `[Rank] Name: message`. Do ranked players carry a prefix? |
| V-48 | What distinguishes `/ignore` from `/block`, given the narration says ignore already covers messages and teleports? |
| V-49 | Is the `/msg` refusal identical for an ignore and for a privacy setting? Specified as identical; unverified — implemented as one shared literal |
| V-50 | Is there a friends menu, or is `/friend` chat-only? |
| V-88 | Delivered private-message format — unobserved. The corpus shows only the refusal, never a delivered `/msg`; implemented as `@1 whispers to you: @2` / `You whisper to @1: @2` (PROPOSED) |
| V-89 | Join/leave notices: filtered viewer-side (consistent with `Public Chat` in T2), and the engine's own `join_msg`/`leave_msg` cannot be filtered per viewer. Recommend the operator sets both to empty; not yet mirrored anywhere |

### 10.1 Implementation notes (f11 agent)

**Public surface — the contract f08 and f10 stubbed:**

```lua
smp_social.ignores(a, b)                -- true iff a has b on their ignore list
smp_social.is_blocked(a, b)             -- true iff a has b on their block list (strict)
smp_social.blocks(a, b)                 -- is_blocked(a,b) OR ignores(a,b)
smp_social.follows(a, b)                -- a follows b (case-insensitive)
smp_social.is_friend(a, b)              -- mutual follows
smp_social.is_friend_or_followed(a, b)  -- b is a friend of a, or a follows b
smp_social.send_pm(sender, target_name, message) -> true | chats a refusal
smp_social.get_setting(player_or_name, key)      -- f12 bridge
smp_social.format_chat(sender, message)          -- `<@1> @2`, T1
smp_social.generic_refusal()                     -- the one OBSERVED refusal literal
```

`blocks()` deliberately folds ignore in: f08 gates `/tpa` on `blocks`
alone (`smp_tp.bridge.blocks`) and the narration says ignore covers
teleport requests [F0287], so folding is what makes T6 hold. One
consequence: mutually-ignoring players are also excluded from
`/rtpqueue` pairing, which the PROPOSED row of §4.3 said they would not
be — acceptable while V-48 is open. If f08 later calls both `ignores`
and `blocks`, `blocks()` can become strict.

`is_friend_or_followed(a, b)` follows §4.2 literally: access requires
the *recipient's* edge (`a` follows `b`). A one-way `b` follows `a`
(fan traffic) does NOT grant access — PROPOSED reading of the §4.2
sentence.

**Bridge contracts assumed:**

- f12 `smp_settings.get(player_or_name, id) -> value | nil` — verified
  against the f12 stub in the shared worktree (`smp_settings/
  accessor.lua`); the legacy `smp_settings.get_name(name, id)` (the
  shape f08's bridge assumed) is tried as a fallback. Unknown ids, or
  `smp_settings` absent entirely, fall through to the permissive
  default `ON` — that path carries `TODO(f12)`.
- f13 `smp_ranks.chat_prefix(name) -> string` and `smp_ranks.tier(name)
  -> string` — verified against the f13 stub (`smp_ranks/perk.lua`,
  which explicitly expects smp_social to call `chat_prefix`); the prefix
  is only consulted when `chat.rank_prefix` is true, which it is not
  (V-24). Path carries `TODO(f13)` until the config key is meaningfully
  non-empty.
- Moderation `smp_admin.is_muted(name) -> bool` (`TODO(admin)`); no mute
  exists yet, so the bridge answers false.

**PROPOSED decisions made while implementing (none contradict an
OBSERVED string):**

1. Anti-spam strings: `You are sending messages too quickly`,
   `Do not repeat yourself`, `You are muted` (§4.1.3 says mutes are
   enforced here; no mute exists yet).
2. `/msg` refusal for `chat.private_messages = OFF`:
   `This user is not accepting private messages` — same house style as
   the §6 algorithm, deliberately distinct from the generic refusal.
3. Delivered PM format (V-88) and `/r` reply: `You have no one to reply to`.
4. Ignore/block split (§4.3, V-48): implemented as specified, except
   `blocks()` folds ignore so teleport requests are covered (see above).
   Payments (`/pay`) and follow edges are block-only; `/rtpqueue`
   exclusion follows `blocks()` and therefore covers ignore too.
5. `/findplayer` (V-17): three lines `Name/Rank/Location`; regions are
   nine compass buckets (`Center`, `North`, …) quantised to
   `findplayer.region_band` around world spawn, plus a `Spawn` bucket of
   `findplayer.spawn_radius`. No digits ever appear in a location (T9).
6. Friends (V-18, V-50): chat-only, no menu; `add`/`remove` (and
   `follow`/`unfollow`) are PROPOSED aliases for `addsearch`/`remove`;
   follower lists require an O(All records) scan at command time only;
   mutual-follow formation notifies both players
   (`You are now friends with @1`).
7. Join/leave notices (V-89): viewer-side filter
   (`ON → all`, `FRIENDS_FOLLOWED → players the viewer follows`,
   `OFF → none`), strings `@1 joined the game` / `@1 left the game`,
   gated by `social.friend_notify`.
8. `/kill`: confirmation prompt (Cancel red left, `Kill` right);
   `set_hp(0)` only — the kill credit flows through f10's
   `register_on_dieplayer` (`last_attacker`), so nothing is credited
   twice.
9. `/nightvision`: level 1 with `INF` duration per §4.6 even though the
   recording's HUD says `Night Vision II` [F0122] — the HUD effect was
   not produced by this command and the algorithm in §4.6 is explicit.
10. `/help` is overridden by the information screen but `/help <command>`
    delegates to the builtin handler; `/ranks` is only registered if
    f13 has not registered it first; Mineclonia's `mcl_commands`
    re-registers `/kill` and `/list`, so every smp_social command is
    re-asserted in `core.register_on_mods_loaded`.
11. Fallback strings for unset `info.*` keys: `This link is not
    configured` / `This text is not configured`.
12. `/ping` reads `core.get_player_information().avg_rtt` (seconds, per
    the lua_api.md example values) and reports whole milliseconds;
    `Players online (@1): @2` for `/list`; staff lines `@1 reported
    @2: @3` and `HelpOp from @1: @2`, reporter confirmation `Your
    report was sent to staff`.
13. Tab completion after `/msg`, `/pay`, `/ignore` [F0089, F0282,
    F0287] has no Luanti equivalent — the server cannot drive client
    tab-completion — so command params are surfaced through `/help`
    instead.
14. `/smp test smp_social` needs the generic test loader f04 also asked
    for; `mods/smp_social/test.lua` returns the standard results table
    and currently runs only through `friedcake/dev-tests/test_social.lua`.

## Proposed shared changes

For the integrator — nothing here blocks T1–T10:

1. `shared/06-config-reference.md` (integrator mirror): add the f11 §7
   rows `findplayer.spawn_radius`, `findplayer.region_band` and the
   `info.*` keys as PROPOSED.
2. `f01-economy-core` / `smp_economy`: cross-cutting X9 expects `/pay`
   to refuse a blocked sender. `smp_economy` does not consult
   `smp_social.blocks`; propose `/pay` calls
   `smp_social.blocks(target, sender)` and answers with the same
   generic refusal style. Not implementable here (smp_economy is
   f01-owned).
3. `f08-teleport`: `smp_tp._is_friend_or_followed` still returns false
   with `TODO(f11)`; it should delegate to
   `smp_social.is_friend_or_followed(a, b)` now that it exists.
4. Operator note for V-89: set the engine's `join_msg` and `leave_msg`
   to empty so the Friends/Followed-filtered notices are the only
   join/leave lines.
