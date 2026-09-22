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
| V-17 | `/findplayer` output format — unobserved |
| V-18 | Friends and follow semantics — unobserved, yet four chat settings depend on them |
| V-24 | **Reopened.** No rank prefix appears in any observed chat line, contradicting v0.1's `[Rank] Name: message`. Do ranked players carry a prefix? |
| V-48 | What distinguishes `/ignore` from `/block`, given the narration says ignore already covers messages and teleports? |
| V-49 | Is the `/msg` refusal identical for an ignore and for a privacy setting? Specified as identical; unverified |
| V-50 | Is there a friends menu, or is `/friend` chat-only? |
