# AGENT BRIEFING — claim a feature

You are an AI agent working in the FriedcakeSMP / Donut SMP recreation
repository. Your job is to implement one feature end-to-end so the
integrator can merge it.

## ⚠ Parallel agents share ONE worktree

Every agent works in the **same clone** — there is a single working tree,
not one checkout per agent. This has already caused real breakage (f05 was
checked out from under its agent mid-task). Two consequences to internalise:

1. **`tools/agent-flow.sh start` switches the shared checkout.** It runs
   `git checkout main` then `git checkout -b agent/<feature>`, which moves
   the whole worktree — including any *uncommitted* work another agent left
   in it. Your branch can be swapped away under you, and theirs under them.
2. **Uncommitted files belong to whoever put them there, not to you.** The
   worktree will carry other agents' untracked/modified files at any moment.
   Never `git add -A` or `git commit -a`; stage only your own paths.

Rules to stay safe:

- **Commit early and often** — committed work survives anyone else's `start`.
- Before running `start`, run `git status` and make sure nothing you care
  about is uncommitted.
- Stage explicitly: `git add friedcake/mods/smp_<yours>/ <your other paths>`,
  never `git add -A`.
- If you return to find your branch gone, your commits are intact — find them
  with `git reflog` / `git log --all`, recreate the branch, keep going.
- If the integrator offers `git worktree add`, use it for real isolation.

## Setup

```
cd /Volumes/Dara/dev/coconut
git status                 # must be on main, clean
cat AGENTS.md              # read this first — the rules
cat CONTRIBUTING.md        # read this second — the workflow
```

Engine source-of-truth (DO NOT trust stale SHA in the spec):

- Mineclonia: `~/dev/mineclonia-git`
- Luanti:     `~/dev/luanti`

## Your feature

```
FEATURE = <FEATURE>          # e.g. f02-sell
SPEC    = spec/features/<FEATURE>.md
MODDIR  = friedcake/mods/smp_<feature-without-prefix>
BRANCH  = agent/<FEATURE>
```

Read `spec/features/<FEATURE>.md` end-to-end before writing any code. The
acceptance tests in `spec/plan/acceptance-tests.md` are your merge gate —
you are not done until they pass.

## Workflow

1. Claim the branch:

   ```
   tools/agent-flow.sh start <FEATURE>
   ```

2. Implement under `friedcake/mods/smp_<feature>/`. The skeleton you'll
   usually want:

   ```
   friedcake/mods/smp_<feature>/
   ├── mod.conf         # name, depends on earlier smp_* mods
   ├── init.lua         # commands, event handlers, menu formspecs
   └── test.lua         # returns {passed, failed, lines} for /smp test
   ```

3. Add `load_mod = smp_<feature>` to `friedcake/modpack.conf` **below** the
   existing entries.

4. Use the shared helpers — never roll your own:

   | Need | Use |
   |---|---|
   | Money formatting | `smp_core.fmt_money(cents, style)` |
   | Quantity formatting | `smp_core.fmt_qty(n)` |
   | Amount parsing | `smp_core.parse_amount(text)` |
   | Player records | `smp_store.api.{get_player,ensure_player,upsert_player}` |
   | Money mutation | `smp_store.api.{add_money,take_money,set_money}` |
   | Ledger | automatic when you call the money helpers |
   | Translation | `S = core.get_translator(core.get_current_modname())` |
   | Menu sessions | `smp_core.{open_session,get_session,close_session}` |

5. Strings MUST go through `S`. The verbatim catalogue is in
   `spec/shared/08-ui-strings.md`. Reproduce observed strings exactly,
   including their irregularities (the spec is explicit about this).

6. Money is integer cents. Never float.

7. No yields between validate and mutate. (See
   `spec/shared/02-architecture.md §2.3`.)

8. After every meaningful change, run the smoke tests:

   ```
   tools/agent-flow.sh test
   ```

   They cover `smp_core`, `smp_store`, and `smp_economy`. Add a
   `friedcake/dev-tests/test_<feature>.lua` if your feature has new
   surface area, and a `friedcake/mods/smp_<feature>/test.lua` for the
   in-game tests.

9. Commit on the branch, never on main. Format:

   ```
   <feature-id>: <imperative summary>

   <body explaining the why, what, and how>
   ```

   Examples:

   - `f02: shulker-aware sell container and history`
   - `smp_sell: M1 matching for enchanted books and tipped arrows`

10. When the feature is complete and tests pass, push the branch:

    ```
    git push origin agent/<FEATURE>
    ```

    If there's no remote, just leave the branch on the integrator's
    machine. Do not merge into main yourself.

## Hard rules (from AGENTS.md)

- Do not edit `spec/shared/`, `spec/plan/`, or `spec/README.md`. Propose
  changes in your feature file's open-questions section.
- Do not edit `smp_core`, `smp_store`, or `smp_admin` unless the
  integrator has explicitly asked. Propose in your feature file.
- Do not push to `main`. Branch first.
- If another agent is already on your feature file, stop and notify the
  integrator.
- If a spec is unclear, add an entry to §10 of your feature file. Do
  not silently rewrite OBSERVED behaviour.

## When you get stuck

- The spec contradicts itself: pick the OBSERVED reading and note the
  conflict in your feature file §10.
- You need a shared helper that doesn't exist: write a
  `## Proposed shared changes` block at the bottom of your feature file
  listing exactly what you need. Stop there; the integrator adds it.
- Tests fail in a way you can't explain: ask the integrator. Do not
  loosen the assertions to make them pass.
