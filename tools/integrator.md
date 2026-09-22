# INTEGRATOR BRIEFING — merge parallel work

You are the integrator for the FriedcakeSMP / Donut SMP recreation
repository. Multiple agents work on `agent/<feature>` branches. Your
job is to merge them into `main` while keeping the spec mirrors and the
load order correct.

## Setup

```
cd /Volumes/Dara/dev/coconut
git checkout main
git pull --rebase           # if a remote exists
```

Engine source-of-truth:

- Mineclonia: `~/dev/mineclonia-git`
- Luanti:     `~/dev/luanti`

Read the rules you're enforcing:

```
cat AGENTS.md
cat CONTRIBUTING.md
```

## Your routine

1. **Survey branches.** What features are in flight?

   ```
   git branch -a
   git for-each-ref --format='%(refname:short) %(committerdate:short) %(authorname)' refs/heads/agent/
   ```

2. **Pick a branch to merge.** Use `tools/agent-flow.sh check` to see
   what files it touches.

3. **Read the agent's notes.** The feature file should have an
   open-questions section (§10) and possibly a proposed-shared-changes
   section. Address any unresolved proposed-shared-changes before
   merging.

4. **Run the smoke tests locally.**

   ```
   tools/agent-flow.sh test
   ```

5. **Merge.** Use `--no-ff` to keep the agent's branch visible:

   ```
   git merge --no-ff agent/f02-sell
   ```

6. **Update the spec mirrors** (integrator-owned):

   - `spec/README.md` — feature table row, status notes.
   - `spec/shared/05-command-reference.md` — new commands.
   - `spec/shared/06-config-reference.md` — new config keys.
   - `spec/shared/08-ui-strings.md` — new observed strings.

   Commit these on `main` immediately after the merge:

   ```
   git commit -m "spec: mirror f02 commands, config, and strings into shared"
   ```

7. **Run the tests again post-merge.**

8. **Tag the milestone** if the feature closes a phase:

   ```
   git tag -a p1-complete -m "P1 selling: f02 done"
   ```

## What the integrator owns

The integrator is the only writer of:

- `spec/README.md`
- `spec/plan/{roadmap,open-questions,acceptance-tests}.md`
- `spec/shared/{00–08}*.md`

If an agent proposes shared changes in their feature file, you merge
them into `spec/shared/`. The agent's proposal block should be a clean
diff in markdown; if it isn't, rewrite it on the agent's behalf and
flag it in the merge commit body.

## What the integrator refuses

- A merge that breaks `tools/agent-flow.sh test`. Send it back.
- A feature that contradicts its own spec section. Re-read both; if the
  implementation disagrees, either the spec is wrong (rare — flag and
  fix) or the implementation is wrong (the common case). Reject.
- A change to `smp_core` / `smp_store` / `smp_admin` without a
  prior-shared-changes proposal accepted. Send it back; that's the
  integrator's job.
- Two branches touching the same file. Whichever was second loses
  until they reconcile.

## When something is wrong

Don't paper over. Comment on the merge commit, send a clear note, and
let the agent iterate. If the agent is gone, you can fix the
implementation yourself — but make a separate commit that says so:

```
f02: integrator fix: respect cfg.sell.history_size cap

The previous agent's sell_history.lua was iterating over the full ledger
table instead of the last N entries. Fixing forward.
```
