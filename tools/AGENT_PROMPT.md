# Agent prompts for FriedcakeSMP

This file holds the prompts to paste into a fresh agent session when you
want to bring a new agent online. Each prompt is a self-contained
briefing; copy the appropriate one, replace `<FEATURE>`, and paste.

Three flavours are provided:

| Prompt | Best for |
|---|---|
| `claim.md` | First-time agents or features with no existing code |
| `continue.md` | Picking up a partially-done feature from another agent |
| `integrator.md` | The human (or designated agent) merging parallel work |

## Quick start

Most of the time, you want `claim.md`. Open it, replace `<FEATURE>` with
the slug from `spec/features/fNN-*.md`, paste into the new agent's
session.

The agent will:

1. Read `AGENTS.md` and `CONTRIBUTING.md` (the rules).
2. Read `spec/features/<FEATURE>.md` (the work).
3. Cut `agent/<FEATURE>` and start implementing.
4. Run `tools/agent-flow.sh test` after every meaningful change.
5. Commit on the branch, never on `main`.

When the agent finishes, the integrator picks the branch up.
