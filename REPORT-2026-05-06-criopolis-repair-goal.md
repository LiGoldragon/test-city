# Active goal — Criopolis configuration and runtime repair

Created: 2026-05-06T08:00:48Z

## Objective

Audit `~/Criopolis` as the production Gas City city, fix misconfigured
configuration, prompts, orders, and supporting scripts, then start it with the
activated `gc` on `PATH` and loop until it runs smoothly.

## Authority and boundary

Li explicitly requested this pass on 2026-05-06 after the isolated `test-city`
validation passed. Earlier `test-city` work treated `~/Criopolis` as read-only;
that boundary is superseded for this goal only. The repair loop must still be
careful:

- inspect and record before editing;
- do not revert existing uncommitted Criopolis work unless it is directly
  identified as the misconfiguration being fixed;
- prefer small, reviewable edits;
- commit and push logical changes as they land;
- stop the city before edits that could race a running supervisor;
- start only after the current repair batch is internally consistent;
- if runtime testing shows bad behavior, stop, fix, restart, and repeat.

## Initial facts

- Activated `gc` on `PATH` reports Gas City commit
  `60732751665b4c70685f06a425febbe96eeb6286`.
- `test-city` has validated idle, on-demand wake, lifecycle churn, and repeated
  lifecycle stress against this binary without reproducing the Dolt write loop
  or wake-loss bugs.
- `~/Criopolis` already has a large dirty worktree before this pass. Existing
  changes include `city.toml`, `pack.toml`, many agent prompts, disabled orders,
  intake notes/reports, a local Gas City manual, and research/library/keel
  files. Treat those as pre-existing work until proven otherwise.

## Audit checklist

1. Read local Criopolis instructions and conventions.
2. Capture current VCS state and running supervisor/session state.
3. Validate `city.toml`, `pack.toml`, agent prompt templates, order files, and
   scripts against the local Gas City manual and currently activated `gc`.
4. Look specifically for production-risk misconfigurations:
   - accidentally disabled core agents or rigs;
   - stale workaround prompts that contradict the fixed Gas City lifecycle;
   - excessive pool sizes or on-demand settings that can churn;
   - order scripts that can loop or spam;
   - inconsistent sleep/drain instructions;
   - invalid or stale paths;
   - missing process names or commands needed for lifecycle control.
5. Fix the smallest coherent batch, then commit and push.
6. Start Criopolis and observe supervisor logs, session list, Dolt commits,
   event growth, warning count, and process CPU.
7. If anything misbehaves, stop the city, capture the artifact, patch, commit,
   push, and restart.

## Status Log

- 2026-05-06T08:00:48Z: Goal created. No Criopolis files changed yet.
- 2026-05-06T08:06Z: Read lore's workspace contract, lore's
  `INTENTION.md`, criome's `ARCHITECTURE.md`, and this repo's
  `AGENTS.md`. The explicit Criopolis repair request is the authority for
  this goal; existing uncommitted Criopolis work remains protected from
  accidental revert.
