# Execution prompts — rulings D1–D11

Five standalone prompts produced from
[`../01-integrator-decisions.md`](../01-integrator-decisions.md) § *Rulings —
2026-09-24*. Master work breakdown, conflict matrix and open items:
[`../REQUIREMENTS.md`](../REQUIREMENTS.md). Each prompt is self-contained —
hand the file verbatim to an agent (fresh session works too).

**Every unit:** branches from the then-current tip of
`agent/integrator-decisions`, pushes its own branch, never `main`, never
touches `fixes/`, runs the full `dev-tests` suite green before finishing.

| Wave | Run | Prompt | Branch | Depends on |
|---|---|---|---|---|
| 1 (parallel) | P1 | [`p1-spec-rulings.md`](p1-spec-rulings.md) | `agent/rulings-spec-text` | — |
| 1 (parallel) | P3 | [`p3-f16-descope.md`](p3-f16-descope.md) | `agent/rulings-f16-descope` | — |
| 1 (parallel) | P4 | [`p4-admin-apis.md`](p4-admin-apis.md) | `agent/rulings-admin-apis` | — |
| 2 | P2 | [`p2-config-mirror.md`](p2-config-mirror.md) | `agent/rulings-config-mirror` | P1 + P3 merged (its guard compares §7 tables P1/P3 edit) |
| 3 | P5 | [`p5-integration-harness.md`](p5-integration-harness.md) | `agent/rulings-integration-test` | P2 + P4 merged (seams include `smp_admin.*`; shares `acceptance-tests.md` with P3) |

After P1–P5: the feature briefs in [`../README.md`](../README.md) are
unblocked and are themselves handable prompts (run in the README's suggested
order, parallel-safe: one agent per feature file). `f16` is cancelled (D8).
`f08`/`f09`/`f10` have **no brief file yet** — see `../STATUS.md`.
