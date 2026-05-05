# Test City testing log — 2026-05-05

This is the append-only operational log for the dolt write-amp investigation.
The incident report
`REPORT-2026-05-05-dolt-amp-investigation.md` is the forensic handoff; this
file records what test-city actually runs.

## Rules for this log

- Record each test before and after it runs.
- Include the gascity source, binary provenance, city template, exact runtime
  isolation shape, and artifact paths.
- Keep failed setup attempts. They are part of the reproducibility record.
- Do not edit Criopolis. Test roots stay under `/tmp/test-city.*`.
- Commit and push after each meaningful log update.

## Current infrastructure baseline

- test-city commit: `00b8f55b` (`nix prepare stock city`)
- default package: stock upstream Gas City `v1.0.0`
- stock source commit: `67c821c76f17226883e7153a324dadcfe80ec211`
- packaging note: the Nix package rewrites embedded `examples/*.sh`
  `#!/bin/sh` shebangs to bash before Go embedding, matching the known
  CriomOS packaging compatibility requirement.
- binary lanes: keep source-built and upstream-prebuilt tests as separate Nix
  apps. The prebuilt lane should fetch the release binary through a fixed-output
  derivation so both lanes stay fully wired through `nix run`.
- template: `templates/canonical-stock`
- live model usage: none; the mayor template is an inert shell process.

## 2026-05-05 23:30 CEST — prepare/tear-down smoke test

Purpose: verify the Nix app can create and remove an isolated city template
root without starting Gas City.

Commands:

```bash
nix run .
nix run .#tear-down -- /tmp/test-city.mgHPOz
```

Observed:

- `nix run .` built `gascity-1.0.0` and prepared `/tmp/test-city.mgHPOz`.
- Manifest recorded `state = "prepared"`, template `canonical-stock`,
  gascity version `1.0.0`, commit
  `67c821c76f17226883e7153a324dadcfe80ec211`.
- The copied template was writable after prepare.
- No `.gc` runtime directory was created.
- `nix run .#tear-down -- /tmp/test-city.mgHPOz` removed the root.

Result: infrastructure smoke PASS. No bug test has run yet.

## 2026-05-05 23:34-23:39 CEST — stock-v1.0.0 idle attempt 1

Purpose: start stock upstream Gas City `v1.0.0` from the source-built Nix
package, initialize `templates/canonical-stock`, and observe five minutes of
idle Dolt behavior.

Root:

```text
/tmp/test-city-idle-v1.m3q4ZC
```

Observed:

- The isolated supervisor started under the test root and stopped cleanly at
  the end of the run.
- `gc init --from` initialized and registered the city, but stderr recorded a
  `gc supervisor install` failure from `systemctl --user daemon-reload`. This
  is expected noise for a scratch environment unless the harness shims host
  service managers.
- The city did not become a valid dolt-amp reproduction because the mayor
  session never launched. Supervisor log repeatedly reported:
  `database not initialized: issue_prefix config is missing`.
- The preserved test root has `.beads/config.yaml` with both `issue_prefix:
  tcs` and `issue-prefix: tcs`, so the failure is not simply "config file was
  never written". It may be a bd CLI/server initialization mismatch or a
  readiness race.
- `gc --city ... session list --state all --json` returned `[]` throughout the
  run.
- Idle measurements were flat but not diagnostic because no session load was
  generated: `.beads` stayed about 466 KiB, `.gc` stayed about 527-532 KiB,
  event lines stayed at 1, and the isolated Dolt process hovered around 4-5%
  CPU.
- The ad-hoc process sampler was too broad and captured unrelated host process
  lines. Future scripts must filter process artifacts to the test root or
  runner-owned PIDs only.

Artifacts:

```text
/tmp/test-city-idle-v1.m3q4ZC/artifacts/
```

Result: setup FAIL, bug verdict INVALID. The next harness pass needs to remove
host service-manager noise, capture only test-root processes, and add an
explicit health gate for bd-backed session creation before counting a run as a
dolt-amp test.

## Next run — stock-v1.0.0 idle dolt amp

Planned shape:

- prepare a fresh `canonical-stock` root with a dedicated source-built binary
  runner, for example `nix run .#run-idle-stock-source`
- run `gc init --from` and the supervisor inside an isolated environment:
  `GC_HOME`, `XDG_RUNTIME_DIR`, `TMPDIR`, `DOLT_ROOT_PATH`, and
  `GIT_CONFIG_GLOBAL` all under the test root
- shim `systemctl` and `launchctl` inside the isolated `PATH`
- keep the supervisor local to that isolated `GC_HOME`
- require a non-empty session list or a successful session-create probe before
  the five-minute observation window begins
- observe for 5 minutes
- capture process, event, dolt-log, and disk-growth artifacts under the test
  root before teardown
- add a separate prebuilt-binary runner, for example
  `nix run .#run-idle-stock-prebuilt`, backed by a fixed-output derivation for
  the release asset
