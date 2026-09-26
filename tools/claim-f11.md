# AGENT BRIEFING — f11 Social and Communication

You are an AI agent picking up **f11 (Social and Communication)** in
the FriedcakeSMP / Donut SMP recreation repository at
`/Volumes/Dara/dev/coconut/`.

This is one mod — `smp_social` — but it is **load-bearing**: public
chat, private messages, ignore/block, friends/follows, `/findplayer`,
`/kill`, `/nightvision` and a dozen informational commands. Four of
the seven observed chat settings in f12 resolve against the
friend/follow graph you build, so this mod is a dependency of the
settings screen even though f12 is P7 too.

## Setup

```
cd /Volumes/Dara/dev/coconut
git status                 # confirm you're on a clean agent branch
cat AGENTS.md              # the rules (read first)
cat CONTRIBUTING.md        # the workflow (read second)
cat tools/claim.md         # the generic claim briefing — read the
                           # "Parallel agents share ONE worktree" warning
```

Engine source-of-truth (DO NOT trust the stale SHA in the spec):

- Mineclonia: `~/dev/mineclonia-git`
- Luanti:     `~/dev/luanti`

## Your feature

```
FEATURE = f11-social
SPEC    = spec/features/f11-social.md
MODDIR  = friedcake/mods/smp_social
BRANCH  = agent/f11-social
```

Read `spec/features/f11-social.md` end-to-end. Then read:

- `spec/plan/acceptance-tests.md` — the f11 row, T1–T10, is your merge
  gate.
- `spec/shared/03-mineclonia-api.md §3.1` — `core.register_on_chat_message`,
  `core.override_chatcommand`, `core.register_on_chatcommand`,
  `mcl_potions.give_effect_by_level` / `clear_effect`,
  `mcl_worlds.pos_to_dimension`.
- `spec/features/f12-settings.md §3.3` — the seven chat settings you
  read. f12 is a stub; see the bridge section below.
- `spec/features/f08-teleport.md §4.4` — teleport requests must respect
  ignore/block; f08 stubbed `smp_social.blocks`.
- `spec/features/f10-combat.md §4.4` — bounty anti-abuse uses the same
  block graph.

## The critical integration point (read this first)

**f08 and f10 have already stubbed `smp_social.blocks(a, b)` with
`TODO(f11)`.** f08's `/rtpqueue` never pairs mutually-blocking players;
f10's bounty anti-abuse may check blocks too. You are the real
implementation of a contract two agents depend on.

Before you start, grep to see exactly what they assumed:

```
grep -rn "smp_social\.\|\.blocks(\|\.ignores(" friedcake/mods/ | grep -v "mods/smp_social/"
```

Match whatever signature they assumed. Your public surface is at least:

- `smp_social.blocks(name, other) -> bool`
- `smp_social.ignores(name, other) -> bool`
- `smp_social.is_friend_or_followed(name, other) -> bool`
- `smp_social.send_pm(sender, target_name, message)`

If one of them assumed something you can't honour, file a
`## Proposed shared changes` block in `f11-social.md §10` and stop.

## Three things to know up front

1. **Two OBSERVED strings, one of them the best-attested in the whole
   corpus:**

   - `This user only accepts messages from friends or followed players`
     — seen across **ten frames** [F0276–F0285]. This is the refusal
     the sender sees. Reproduce word-for-word. T3, T5 test it.
   - `This command does not exist` — the unknown-command response
     [F0055]. Override Luanti's `Invalid command: <name>`. T8.

2. **The generic refusal rule.** §4.2, §6. When the recipient has
   ignored/blocked the sender, return **the same** message as the
   `FRIENDS_FOLLOWED` privacy refusal. Revealing "you have been
   ignored" is itself information, and the observed server gives a
   single generic refusal. The ignore branch and the privacy branch
   MUST be indistinguishable. T5 tests exactly this.

3. **No rank prefix. v0.1 is wrong.** §3.1. The observed format is
   `<Name> message` — angle brackets, name, space, message. **No
   `[Rank]` prefix appears on any of ~30 observed lines.** The prefix
   question stays open (V-24), so `chat.rank_prefix` defaults to
   `false` and the format is `<@1> @2`. Do not resurrect v0.1's
   `[Rank] Name: message`. T1 tests this.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start f11-social
   ```

2. Skeleton:

   ```
   friedcake/mods/smp_social/
   ├── mod.conf         # name=smp_social, depends on smp_core smp_store
   ├── init.lua         # command registrations, chat hooks
   ├── chat.lua         # public chat format + per-recipient delivery
   ├── pm.lua           # /msg /r, the generic refusal
   ├── ignore.lua       # /ignore /block; ignore+block graphs
   ├── friends.lua      # /friend follows; derived friends; notifications
   ├── findplayer.lua   # /findplayer — coarse only
   ├── kill.lua         # /kill with confirmation + combat-tag credit
   ├── nightvision.lua  # /nightvision via mcl_potions
   ├── info.lua         # /help /rules /discord /media /link /buy /website /ranks /medal
   ├── misc.lua         # /ping /list /report /helpop
   ├── bridges.lua      # f12 settings + f13 rank stubs with TODO(f12)/TODO(f13)
   └── test.lua         # /smp test smp_social
   friedcake/dev-tests/test_social.lua    # standalone smoke tests
   ```

   Add `load_mod = smp_social` to `friedcake/mods/modpack.conf` below the
   existing entries.

3. Implement in this order (so each step is testable):

   1. **Bridges** (`bridges.lua`). Stub `smp_settings.get(player, key)`
      (f12) and the rank-prefix lookup (f13) with `TODO(f12)` /
      `TODO(f13)` returning permissive defaults. f12's real values
      will land later; your stub defines the contract shape.
   2. **Chat** (`chat.lua`). §4.1. `core.register_on_chat_message`
      returning true, then `core.chat_send_player` per eligible
      recipient. Format `<@1> @2`, no prefix. Filter per recipient
      (public-chat OFF, ignored senders). Anti-spam 1/s + duplicate
      filter. T1, T2.
   3. **PM** (`pm.lua`). §4.2. `core.override_chatcommand("msg", ...)`
      and `/r`. The generic refusal. T3, T4, T5.
   4. **Ignore/block** (`ignore.lua`). §4.3. `/ignore`, `/block`.
      Ignore covers messages AND teleport requests (the narration is
      the only evidence and it says both). T6.
   5. **Friends** (`friends.lua`). §4.4. `/friend` subcommands,
      one-way follows, derived friendship (mutual follows),
      `social.max_follows` (200), join/leave notifications. T10.
   6. **Findplayer** (`findplayer.lua`). §4.5. Coarse only:
      `Offline`, `Spawn`, or `<Dimension> – <Region>` via
      `mcl_worlds.pos_to_dimension`. Never exact coordinates. T9.
   7. **Kill** (`kill.lua`). §4.6. `/kill` with confirmation; if
      tagged, credit the last attacker (f10). T7 (bounty path) is
      f10's, but your `/kill` hook enables it.
   8. **Nightvision** (`nightvision.lua`). §4.6.
      `mcl_potions.give_effect_by_level("night_vision", player, 1, …)`
      / `clear_effect`, persisted and re-applied on join/respawn.
   9. **Info** (`info.lua`). §4.6. `/help`, `/rules`, `/discord`,
      `/media`, `/link`, `/buy`, `/website`, `/ranks`, `/medal` —
      read-only formspec fields holding the text/URL (Luanti can't
      open URLs).
   10. **Misc** (`misc.lua`). `/ping`, `/list`, `/report`, `/helpop`.
   11. **Unknown-command override** (`init.lua`). §4.7.
       `This command does not exist`. T8.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Player records | `smp_store.api.{get_player,upsert_player}` |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Chat hook | `core.register_on_chat_message` |
   | Command override | `core.override_chatcommand`, `core.register_on_chatcommand` |
   | Chat delivery | `core.chat_send_player`, `core.chat_send_all` |
   | Effects | `mcl_potions.give_effect_by_level`, `clear_effect` |
   | Dimension | `mcl_worlds.pos_to_dimension(pos)` |

5. Strings MUST go through `S`. The verbatim strings f11 owns:

   - `This user only accepts messages from friends or followed players`
     (OBSERVED, 10 frames)
   - `This command does not exist` (OBSERVED)
   - `Click to send @1 a teleport request` (OBSERVED, substituted as a
     hint line — see `shared/04-ui-kit.md §4.8`)

   `PROPOSED — no frame evidence` strings live in your feature file §3:

   - `That player is not online`, `This user is not accepting private
     messages`, and any informational command text.

6. Money is integer cents (only `/bounty`-adjacent paths touch it; use
   the shared formatter if you render any).

7. **No yields between validate and mutate** (`shared §2.3`).
   Specifically: the per-recipient delivery loop in chat must not
   `core.after` mid-loop, or a recipient list that changes under you
   delivers to the wrong set.

8. **Clickable chat has no Luanti equivalent.** §3.3. Emit the hint as
   a *second chat line*, not a decoration. Never fake hover/click
   events.

9. After every meaningful change, run:

   ```
   tools/agent-flow.sh test
   ```

   These cover `smp_core`, `smp_store`, `smp_economy`. Add
   `friedcake/dev-tests/test_social.lua` covering T1 (format), T3/T5
   (generic refusal), T8 (unknown command), T9 (coarse findplayer),
   T10 (mutual follows). Plus `friedcake/mods/smp_social/test.lua`.

10. Commit on the branch, never on main. **Stage only your own paths**:

    ```
    git add friedcake/mods/smp_social/ friedcake/dev-tests/test_social.lua
    git commit -m "f11: public chat format and the generic /msg refusal"
    ```

    Never `git add -A`. Format:

    ```
    f11: <imperative summary>

    <body>
    ```

    Examples:

    - `f11: public chat <Name> message with per-recipient delivery`
    - `f11: /msg override with the generic friends-or-followed refusal`
    - `f11: ignore and block graphs over the player record`
    - `f11: derived friends, follows, and join/leave notices`
    - `f11: coarse /findplayer via pos_to_dimension`

11. When T1–T10 pass, push:

    ```
    git push origin agent/f11-social
    ```

    The integrator merges into main.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section (§10).
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on `agent/f11-social`, stop and notify
  the integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## What to write up at the end

In your feature file's §10, leave a short note covering:

- Every `PROPOSED` decision you made (ignore vs block split, `/msg`
  OFF refusal text, `/findplayer` region granularity, friends menu).
- The exact signature of `smp_social.blocks` / `smp_social.ignores` /
  `is_friend_or_followed` — f08 and f10 are stubbing them.
- The `smp_settings.get` contract shape you assumed (f12).
- Any unresolved V-NN questions you made a `PROPOSED` decision on.

## When you get stuck

- f12 hasn't landed `smp_settings.get`: stub with `TODO(f12)` returning
  permissive defaults. Don't block — the whole f12/f13 chain is P7.
- f13 hasn't landed rank prefixes: `chat.rank_prefix` is `false`
  anyway (no prefix observed). Ship with it off.
- f08/f10 assumed a different `blocks` signature: match theirs if
  possible; if not, file `## Proposed shared changes` and stop.
- The `/ignore` result was never shown on camera: the narration is the
  only evidence. Implement "ignore covers messages and teleport
  requests" and mark the rest `PROPOSED`.
- `/findplayer` region granularity is unobserved: pick coarse buckets,
  mark `PROPOSED`, never return exact coordinates.
