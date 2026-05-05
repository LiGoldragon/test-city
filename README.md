# test-city

Sandbox for reproducing and characterizing Gas City bugs in canonical, isolated
test cities — without touching Li's production city `Criopolis` and without
burning through Li's Anthropic subscription on diagnosis loops.

The motivation is concrete: 2026-05-05, Criopolis hit a dolt CPU + write-amp
incident. Mayor (Claude) authored two patches without first verifying their
diagnosis empirically. Patches landed; the symptom partially persisted; we
spent a day on speculation. The discipline that should have been applied is:
**reproduce in a controlled environment, instrument actual load, then patch.**

This repo is that controlled environment.

## Status

This repo currently provides the infrastructure for creating throwaway city
roots. The default `nix run` path prepares a minimal city template under
`/tmp` using a stock Gas City `v1.0.0` binary package, but it does not start
the city or run the dolt-amp scenario.

The full incident report — what was seen, what was tried, what's still
unknown, what an honest investigator would check next — is in this repo at
`REPORT-2026-05-05-dolt-amp-investigation.md`. Read it first.

## What this repo is for

1. Spin up canonical test cities pinned to specific gascity versions (stock
   `v1.0.0`, `upstream/main` HEAD, `LiGoldragon/gascity` fork branches, etc.).
2. Run them long enough to reproduce — or fail to reproduce — known bugs.
3. Capture diagnostic data (`dolt sql -q "SHOW PROCESSLIST"`, query mix,
   connection rate, on-disk growth, supervisor log patterns).
4. Validate fix candidates against the captured baseline before they touch
   Criopolis.

Each test city is ephemeral (`mktemp -d`-style scratch dir; tear-down on exit).
Crucially, NEVER under `~/Criopolis` or any path Li uses as a real city — that
boundary is enforced by the orchestrator's existing `assert_not_under_forbidden_city`
helper, which this repo borrows from.

## What this repo is NOT for

- Replacing the gascity test suite. Upstream's CI exists; if a bug is in their
  source, the fix lands upstream.
- Running production work. The cities here are throwaway.
- Editing Criopolis. Hard rule.

## Inputs

- `gascity-v1-0`: direct source input for `gastownhall/gascity` tag
  `v1.0.0`, commit `67c821c76f17226883e7153a324dadcfe80ec211`.
- `gascity-nix`: kept for later fork/current-pin comparison apps.
- `codex` is not used by the current minimal templates. Future live-agent
  scenarios must keep `gpt-5.4-mini` and `model_reasoning_effort=low` as the
  default.

## Usage

Prepare the default stock-v1.0.0 city template:

```bash
nix run
```

Prepare a named template:

```bash
nix run . -- canonical-stock
nix run . -- upstream-main
```

Tear down the root printed by `nix run`:

```bash
nix run .#tear-down -- /tmp/test-city.XXXXXX
```

The prepare step writes `test-city.json` at the test root. That manifest is the
structured handoff for later scenario runners.

## Inspiration: orchestrator's isolated-city pattern

The orchestrator repo (`github.com/LiGoldragon/orchestrator`) already worked
out how to spin up a real Gas City instance under test without contaminating
production. See:

- `tests/scripts/orchestrator-isolated-gc-test.sh` — full setup including
  scratch root under `mktemp -d`, supervisor seeding, codex shim or live mode,
  cleanup on exit.
- `tests/fixtures/deterministic-city.toml` — minimal city.toml that disables
  most cooldown orders (`beads-health`, `cross-rig-deps`, `dolt-gc-nudge`,
  `gate-sweep`, etc.) so the test runs without background-noise interference.
- `tests/scripts/orchestrator-live-gc-test.sh` — variant that connects to a
  real city for end-to-end validation.

That pattern is a starting point, **not a contract**. If codex finds a better
shape for THIS repo's needs, replace it. The orchestrator's design was built
for cascade dispatch testing; the dolt-amp investigation has different
requirements (long-running observation rather than short cascade chains;
heavy diagnostic capture; multiple gascity-version pinnings).

## Templates

- `templates/canonical-stock/` — minimal city config for the stock `v1.0.0`
  package exposed by this flake.
- `templates/upstream-main/` — same city shape reserved for an upstream-main
  package once that comparison app is wired.

Other variants codex can add:
- `templates/fork-codex-model/` — `LiGoldragon/gascity` rebased v1.0.0 with
  the codex model cherry-pick (commit `76f46b45`).
- `templates/fork-cycling-fix/` — the `code-writer/cr-5drwd1` branch with the
  spawn-cycling + `clearWakeFailures` patches (commit `a720d067`).
- `templates/upstream-cycling/` — upstream commits that already address the
  same surface (PR #563 respawn circuit breaker, PR #1702 pending-create
  start lease, etc.).

Each template carries a `city.toml`, `pack.toml`, and an inert always-on
`mayor` shell process. The mayor is a stable session bead for measuring idle
runtime behavior without spending model tokens.

## Cost discipline

- Default agent model: `gpt-5.4-mini` at `model_reasoning_effort=low`.
- Default test duration: 5 minutes for the dolt-amp reproduction.
- Tear down test root on exit unless `KEEP_TEST_ROOT=1`.
- Skip cooldown orders that produce noise in steady-state (orchestrator's
  `[orders] skip = [...]` pattern).
- Codex shim available for unit tests that don't need a live model.

## Next scenario

1. Pin canonical stock `v1.0.0`. Spin up minimal test city. Watch dolt for
   5 min. Capture: dolt CPU, dolt log warnings, events.jsonl growth, on-disk
   size. Does the amp pattern reproduce?
2. If yes: it's an upstream bug. File issue with reproducer.
3. If no: it's specific to Criopolis's pack.toml or environment. Bisect.

Then repeat with `upstream/main`, the fork branches, etc. — narrow to the
config or commit that actually triggers the bug.

## Workspace

- Workspace contract: see `~/git/lore/AGENTS.md` (Li's lore-standard rules).
- This repo: writable.
- `~/Criopolis/`: read-only. Never write here from a test city.
- `mktemp -d` test roots: writable; cleaned on exit.

## License

MIT (matches gascity + orchestrator).
