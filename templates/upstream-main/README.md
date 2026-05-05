# Template: upstream-main

Gas City at `gastownhall/gascity` `main` HEAD. As of 2026-05-05 that's
`2a363e3b`, ~389 commits ahead of `v1.0.0`, including (at least) these
post-1.0.0 fixes that touch the same surface as Criopolis's dolt-amp bug:

- `b31fd6c5 fix: add respawn circuit breaker for named sessions (#563)` —
  may directly address the spawn-cycling pattern Criopolis hit.
- `7c892b94 fix(session): honor pending create start lease (#1702)` —
  pending-create lifecycle.
- `def74a27 fix(reconciler): use pending_create_started_at for staleCreatingState (#1586)`
- `5a7dbddb fix: post-merge remediation for PR 1586 (#1703)`
- `155029ce fix(reconciler): roll back stale pending-create beads in desired branch (#1533)`
- `23b1e407 fix(controller): preserve cached demand correctness (#1646)`
- `50b04c82 fix: keep assigned workflow sessions waking (#1704)`

## Purpose

Test whether running upstream/main HEAD eliminates the bugs that motivated
Criopolis's fork patches (cycling fix `9114c814` and `clearWakeFailures`
suppress `a720d067`). If yes, the fork patches are obsolete; pin Criopolis
to upstream/main (or wait for v1.0.1).

## Pin

Same shape as the `canonical-stock` template, but with `gascity-nix`
overridden to a `nix-fetch` of `github:gastownhall/gascity` at the chosen
upstream/main commit.

Codex: pick the upstream commit explicitly (don't use `branch=main` — that
floats and breaks reproducibility). Document the chosen commit + date in
this README.

## Reproduction targets

Same scenarios as `canonical-stock`. Compare:

| Scenario | canonical-stock | upstream-main | Criopolis (pre-patch) | Criopolis (post-patch) |
|---|---|---|---|---|
| Idle dolt amp | TBD | TBD | ~30 events/sec | ~0.7 events/sec |
| One-bead spawn cycling | TBD | TBD | 24+ creating sessions | (fixed by `9114c814`) |
| 10-min stable-session bloat | TBD | TBD | grew dolt to 3.1 GB | (fixed by `a720d067`) |

Filling in the upstream-main column is the immediate-value task this repo
exists for.
