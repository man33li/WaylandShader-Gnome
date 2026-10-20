# Waterfall: Odin refactor of the GNOME backend

Branch `ODIN-refactor`, forked from `gnome-backend` at `b223c1a`. Phases run strictly in order; a phase starts only when the previous phase's exit artifact exists and its gate is recorded in `GATES.md`. Changes to an earlier phase's artifact after its gate require a new gate entry.

The feature set is fixed by the original C++ project (README.md, docs/GNOME.md, gnome/, src/). This refactor adds no features.

| # | Phase | Owner (model) | Exit artifact | Gate |
|---|---|---|---|---|
| 1 | Requirements | scouts: haiku 5.5 (codebase), gpt-6-luna (external research) → main planner | `01-requirements/research/*.md`, `01-requirements/requirements.md` | every original feature listed with a source reference and an acceptance test |
| 2 | Design | adversarial planners sol 6.1 (`plan-A`) and opus 5.5 (`plan-B`); main planner opus 5.5 picks exactly one | `02-design/plan-A.md`, `02-design/plan-B.md`, `02-design/decision.md`, `02-design/design.md` | decision names the chosen plan and the rejected plan's failure points |
| 3 | Implementation | builder Astra 6; subagents: ui sonnet 5.5, ux sonnet 5.5, code sol 6.1, security sol 6.1 | Odin sources, build files and tests; `03-implementation/build-log.md` | builds, and the tests named in `requirements.md` run |
| 4 | Verification | adversarial reviewers sol 6.1 (`review-A`) and opus 5.5 (`review-B`); main reviewer sol 6.1 sides with exactly one | `04-verification/review-A.md`, `review-B.md`, `acceptance.md` | accepted only on passing tests; rejection returns to phase 3, at most 2 rework rounds |
| 5 | Maintenance | main agent | `05-maintenance/handoff.md` | open items, environment limits, next steps |

Model IDs: `anthropic/claude-haiku-5-5`, `openai-codex/gpt-6-luna` (no `luna 6.1` exists in the catalog), `anthropic/claude-opus-5-5`, `openai-codex/gpt-6-astra`, `anthropic/claude-sonnet-5-5`, `openai-codex/gpt-6.1-sol`.
