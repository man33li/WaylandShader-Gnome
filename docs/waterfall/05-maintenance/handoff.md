# Handoff: Odin refactor of the GNOME backend

State at the end of phase 4 round 3: **not accepted**, one open finding, rework limit (2 rounds) exhausted. See `../GATES.md`.

## Open decision (user)

R3-1 (`../04-verification/acceptance.md` Round 3, `review-B.md` Round 3): the C++/Qt baseline strips one leading U+FEFF when it converts JSON strings and C-string arguments to text; the Odin port keeps it. This only matters for strings that actually start with an invisible U+FEFF; normal connector IDs, parameter names and saved paths never do. Choose one:

1. Authorize rework round 3: strip one leading U+FEFF in the JSON string extraction and C-string `text()` conversion, while keeping raw-key lookup unchanged; add the baseline-pinned regression described in acceptance.md Round 3; then a final review.
2. Record R3-1 as accepted deviation D3 in `../02-design/decision.md` and mark phase 4 accepted.

Also pending your confirmation: deviations D1 and D2 (`../02-design/decision.md`), provisionally accepted by the main agent.

## Deferred manual tests (agents cannot perform them)

T-ISO-RENDER (visual check in a disposable Shell; its private devkit viewer lacked PipeWire), the T-GUI visual and accessibility checklist, T-SAFETY and T-DOCS sign-off, and T-HW (physical displays, only after acceptance). Commands are in `../01-requirements/requirements.md`.

## Do not

Install the package or enable the extension in the live session before acceptance. A native-module change needs a fresh GNOME login, never a compositor restart.

## Environment

- Baseline C++ worktree `/tmp/ws-baseline` at `b223c1a`. It is used by the baseline-differential tests; recreate it with `git worktree add --detach /tmp/ws-baseline b223c1a` if `/tmp` was cleared.
- Role agents live in `.omp/agents/` (model and effort are pinned per role). This clone is used from `/home/knd/AI/dodForPonytail`, whose `.omp/agents` is a symlink to them.
- Last tested package: `/nix/store/zsiwskpgiapg0f6b9y54hq3vl52fhg66-waylandshader-gnome-0.1.0`.
