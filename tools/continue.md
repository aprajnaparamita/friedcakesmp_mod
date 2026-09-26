# AGENT BRIEFING — continue a feature

You are an AI agent picking up work another agent started on the
FriedcakeSMP / Donut SMP recreation repository. The previous agent may
have left a branch in any state.

## Setup

```
cd /Volumes/Dara/dev/coconut
git status                   # what branch are we on?
git log --oneline -10        # recent history
git stash list               # any uncommitted work?
```

If you are not already on `agent/<FEATURE>`, switch to it:

```
tools/agent-flow.sh start <FEATURE>
```

Read the project rules before touching anything:

```
cat AGENTS.md
cat CONTRIBUTING.md
```

Engine source-of-truth (DO NOT trust stale SHA in the spec):

- Mineclonia: `~/dev/mineclonia-git`
- Luanti:     `~/dev/luanti`

## Your feature

```
FEATURE = <FEATURE>
SPEC    = spec/features/<FEATURE>.md
MODDIR  = friedcake/mods/smp_<feature-without-prefix>
BRANCH  = agent/<FEATURE>
```

Read `spec/features/<FEATURE>.md` end-to-end. Pay special attention to
the open-questions (§10) and the proposed-shared-changes sections — the
previous agent may have left requests there for the integrator.

## Assess what is there

Look at the current state of the mod:

```
ls -la friedcake/mods/smp_<feature>/
cat friedcake/mods/modpack.conf                       # is load_mod set?
git log agent/<FEATURE> --oneline               # what's been done
git diff main..agent/<FEATURE> --stat           # what's changed
```

Then run the smoke tests:

```
tools/agent-flow.sh test
```

If they pass: continue from where the previous agent left off. If they
fail: investigate before adding more code. Don't paper over a failing
test by commenting it out.

## Continue

Implement under `friedcake/mods/smp_<feature>/`. Use the shared helpers
from `smp_core` and `smp_store` — never roll your own. Money is integer
cents. Strings go through `S = core.get_translator(...)`. No yields
between validate and mutate.

After every meaningful change:

```
tools/agent-flow.sh test
```

## When you finish or hand off

The previous agent may have already opened a push; check before pushing
again:

```
git log origin/agent/<FEATURE>..HEAD 2>/dev/null   # local-only commits
```

If you're done, push your work:

```
git push origin agent/<FEATURE>
```

If you're handing off mid-feature, write a short note at the top of
your last commit body describing what's left:

```
f02: sell container complete; pending: shard-tax exemption, sell history paging

What's done:
- Detached inventory for sell container
- /sell hand and /sell all

What's left:
- /sellhistory with pagination
- amethyst exemption (sell.meta_exempt)
- One acceptance test still flaky on rapid reopen
```

## Hard rules (from AGENTS.md)

Same as `claim.md`. Plus:

- Do not rebase the previous agent's commits unless you have to. Their
  history is theirs; your additions are yours.
- Do not change the spec file's existing OBSERVED sections — only add
  to §10 (open questions) and propose-shared-changes.
- Do not undo previous agents' progress. If something is wrong, fix it
  forward.
