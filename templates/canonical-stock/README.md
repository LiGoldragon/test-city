# Template: canonical-stock

Stock upstream Gas City `v1.0.0` (tag `v1.0.0`, commit `67c821c7`). No fork
patches. No codex model cherry-pick. The "what ships out of the box behaves
like this" baseline.

## Purpose

If a bug reproduces here, it's an upstream bug — file an issue against
`gastownhall/gascity` and proceed with the upstream-main template too. If a
bug does NOT reproduce here but DOES reproduce on Criopolis, the difference is
in our fork or in our city configuration.

## Pin

To use this template, override the `gascity-nix` flake input at runtime to
point at a gascity-nix commit whose `flake.nix` has `rev = "67c821c7..."`.

If gascity-nix doesn't have a stock-v1.0.0 pin yet, add a branch pinned there
in the gascity-nix repo first. Or use `nix run` with a `--override-input` flag
that reaches stock v1.0.0 directly via `github:gastownhall/gascity/v1.0.0` as
a temporary src.

Codex: choose whichever is cleanest; document the pin shape in this README so
the choice is reproducible.

## Minimum config

`city.toml` and `pack.toml` in this directory should be the SMALLEST viable
city that runs `gc start` cleanly with one always-on mayor stub and one
on-demand codex agent. Avoid anything that could be a confounder — extra
agents, custom orders, custom formulas. Codex authors these.

Config knobs that should be present (cost discipline):

```toml
# pack.toml
[[agent]]
name = "mayor"
mode = "always"
process_names = ["bash", "sh"]
# Shell-only mayor stub (NOT claude). Just a placeholder so the always-on
# session bead exists and the reconciler has work to do. This is not for
# real prompt-driven mayoring; it's for amp reproduction only.
start_command = "tail -f /dev/null"

[[agent]]
name = "tester"
mode = "on_demand"
provider = "codex"
process_names = ["codex", "codex-raw"]
# Default cost-disciplined model
start_command_args = ["--model", "gpt-5.4-mini", "-c", "model_reasoning_effort=low"]
```

```toml
# city.toml
name = "test-canonical-stock"
[session]
startup_timeout = "300s"
```

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
