# Template: canonical-stock

Stock upstream Gas City `v1.0.0` (tag `v1.0.0`, commit `67c821c76f17226883e7153a324dadcfe80ec211`). No fork
patches. No codex model cherry-pick. The "what ships out of the box behaves
like this" baseline.

## Purpose

If a bug reproduces here, it's an upstream bug — file an issue against
`gastownhall/gascity` and proceed with the upstream-main template too. If a
bug does NOT reproduce here but DOES reproduce on Criopolis, the difference is
in our fork or in our city configuration.

## Pin

The repo flake exposes a direct stock package from
`github:gastownhall/gascity/v1.0.0`. The default app uses that package and
copies this template into a temporary test root.

## Minimum config

`city.toml` and `pack.toml` define one always-on shell mayor. There is no
Codex-backed agent in this template yet; the first idle dolt-amp scenario does
not need model calls.

## Reproduction targets (initial scenarios codex should run)

1. **Idle dolt-amp**: spawn this city, do nothing, watch dolt CPU + write
   rate for 5 min. Pre-fix Criopolis showed ~30 events/sec on stable session
   beads. Does it reproduce here?
2. **One-bead routed**: sling one trivial bead to `tester`. Does the spawn
   succeed? Does dolt amp during the spawn? After the spawn drains?
3. **Stable-session lifecycle**: leave `mayor` always-on for 10 min idle.
   Watch `dolt sql -q "SELECT COUNT(*) FROM dolt_log"` growth. Pre-fix
   Criopolis saw thousands of commits/min on the always-on session bead.
   Does it reproduce here?
