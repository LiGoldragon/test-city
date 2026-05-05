# Agent instructions — test-city

You **MUST** read AGENTS.md at `github:ligoldragon/lore` first — Li's
workspace contract.

## Repo role

This repo spins up ephemeral, canonical Gas City instances in scratch
directories to reproduce, characterize, and validate fixes for Gas City
bugs — without touching `~/Criopolis/` (Li's production city) and without
burning tokens on speculative patches.

The driver is **codex** (free-standing or pool-managed). Claude is too
slow for the iterate-test-iterate loop this repo's tests need.

## What you own

- Spawn / tear-down scripts under `scripts/`.
- City templates under `templates/<name>/` — each a minimal `pack.toml`
  + `city.toml` + any helper scripts.
- Diagnostic capture helpers (dolt processlist samplers, connection-rate
  meters, on-disk-growth watchers, supervisor log filterers).
- Bisection + comparison scripts when you need to narrow which gascity
  commit / config field triggers a bug.

## What you don't own

- Mayor / Criopolis decisions. If a test confirms a fix, surface to mayor
  via mail; mayor decides Criopolis deployment.
- Upstream gascity source. Patches go to `LiGoldragon/gascity` (a fork)
  and upstream PRs to `gastownhall/gascity`. This repo only orchestrates
  the test runs.
- The orchestrator daemon. Borrow its isolated-test pattern; don't copy
  its source here.

## Workspace boundary (hard rule)

- `~/Criopolis/` is **read-only**. Refuse to write there.
- Test roots live under `mktemp -d` (default `/tmp/test-city.XXXXXX`).
- Anything in this repo's working tree is writable (commit + push as
  usual).
- Reuse the orchestrator's `assert_not_under_forbidden_city` helper
  pattern: refuse to start a test city if its path is `~/Criopolis` or
  any path in `$ORCHESTRATOR_FORBIDDEN_CITY_ROOTS` /
  `$GC_CITY_PATH` / `$GC_CITY`.

## Cost discipline

This repo runs against Li's actual Anthropic / OpenAI subscriptions.
Default to:

- `gpt-5.4-mini` model.
- `model_reasoning_effort=low`.
- Short test windows (5 min default for the dolt-amp reproduction).
- Minimal pack.toml: ≤2 codex agents per test city unless a scenario
  specifically needs more.
- Tear down test root on exit unless `KEEP_TEST_ROOT=1` for forensic.

## Style

- Bash scripts use `set -euo pipefail`.
- Single source of truth for "where is the test root" — env var, not
  scattered globals.
- Each test scenario produces a structured artifact (JSON or TSV) that
  can be diffed across runs.
- Lore-standard naming (full English words, no abbreviations).

## Process

- Commit per logical change.
- Push immediately after every commit.
- Co-author commits with:
  `Co-Authored-By: Codex CLI <noreply@anthropic.com>`.

## First scenario (priority)

Reproduce the dolt write-amp pattern Criopolis hit on 2026-05-05.

Full incident report at:
`github.com/LiGoldragon/gascity-nix/REPORT-2026-05-05-dolt-amp-investigation.md`.

Read it. The discipline gap that made the report necessary — patch first,
verify never — is exactly what this repo exists to prevent. So before
any new patch goes to gascity, this repo must reproduce the bug, capture
load characteristics, and validate the patch under those captured loads.

Inspiration (NOT contract): orchestrator's
`tests/scripts/orchestrator-isolated-gc-test.sh` and
`tests/fixtures/deterministic-city.toml` show one way to spin up a real
isolated city. Borrow what's useful; replace what isn't.
