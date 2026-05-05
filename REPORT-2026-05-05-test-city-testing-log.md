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

- test-city commit: `d35d6528` (`add idle dolt amp runners`)
- default package: stock upstream Gas City `v1.0.0`
- stock source commit: `67c821c76f17226883e7153a324dadcfe80ec211`
- packaging note: the Nix package rewrites embedded `examples/*.sh`
  `#!/bin/sh` shebangs to bash before Go embedding, matching the known
  CriomOS packaging compatibility requirement.
- source-built lane: `nix run .#run-idle-stock-source`
- upstream-prebuilt lane: `nix run .#run-idle-stock-prebuilt`
- prebuilt fixed-output asset:
  `gascity_1.0.0_linux_amd64.tar.gz`,
  `sha256-zEXmvlTGuwD+aRWCn4vquyWlhbYEpHhGhFqnuacDcNM=`
- runner scripts: `scripts/run-idle-stock-source.sh` and
  `scripts/run-idle-stock-prebuilt.sh` call the shared
  `scripts/run-idle-dolt-amp.sh` harness.
- isolation: `GC_HOME`, `XDG_RUNTIME_DIR`, `TMPDIR`, `DOLT_ROOT_PATH`, and
  `GIT_CONFIG_GLOBAL` live under the test root; `HOME` remains the real user
  home because Gas City rejects platform-supervisor operations when `HOME` is
  rewritten.
- cleanup: the runner asks the isolated supervisor to stop, then terminates any
  remaining process whose command line contains the test root.
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

## 2026-05-05 23:51 CEST — runner validation note

The first scripted source-lane smoke used a fully synthetic `HOME` and failed
`gc init` because Gas City requires the real user home for platform-supervisor
operations. That was a harness bug, not a Gas City result. The runner now keeps
`HOME=/home/li` and isolates state through `GC_HOME` and the other test-root
environment variables. The failed root `/tmp/test-city.dOxee5` was removed
after stopping its leftover test-root Dolt process.

## 2026-05-05 23:52 CEST — stock source lane scripted smoke

Purpose: validate the dedicated source-built runner and confirm whether stock
`v1.0.0` can pass the session health gate before any dolt-amp observation.

Command:

```bash
KEEP_TEST_ROOT=1 \
TEST_CITY_HEALTH_TIMEOUT_SECONDS=10 \
TEST_CITY_OBSERVATION_SECONDS=15 \
TEST_CITY_SAMPLE_INTERVAL_SECONDS=5 \
nix run .#run-idle-stock-source
```

Root:

```text
/tmp/test-city.7H4KI7
```

Observed:

- `gc init --from` exited cleanly with no stderr.
- The runner reached the session health gate, but `gc --city ... session list
  --state all --json` stayed `[]`.
- Supervisor log showed the same session-creation failure as the ad-hoc run:
  `database not initialized: issue_prefix config is missing`.
- `.beads/config.yaml` contained `issue_prefix: tcs` and `issue-prefix: tcs`.
- `gc --city ... bd config get issue_prefix` reported `issue_prefix (not set)`.
- `gc --city ... bd config list` showed normal bd config rows but no
  `issue_prefix`.
- `bd-trace.log` shows `bd create ... mayor ...` failing in about 650 ms; list
  calls otherwise returned normally.

Artifacts:

```text
/tmp/test-city.7H4KI7/artifacts/
```

Result: setup FAIL, bug verdict INVALID. Source-built stock `v1.0.0` can
initialize the on-disk city files, but it does not create a bd-visible
`issue_prefix`, so no sessions launch and no dolt-amp observation window is
valid yet.

## 2026-05-05 23:52-23:53 CEST — stock prebuilt lane scripted smoke

Purpose: compare the upstream release binary against the source-built Nix
package while keeping the binary in Nix as a fixed-output derivation.

Command:

```bash
KEEP_TEST_ROOT=1 \
TEST_CITY_HEALTH_TIMEOUT_SECONDS=10 \
TEST_CITY_OBSERVATION_SECONDS=15 \
TEST_CITY_SAMPLE_INTERVAL_SECONDS=5 \
nix run .#run-idle-stock-prebuilt
```

Root:

```text
/tmp/test-city.jJeS5A
```

Observed:

- The prebuilt `gc version` is `1.0.0`.
- `gc init --from` created the city files but failed before registration.
- `gc-init.stderr` reported:
  `bead store: exec beads start: could not acquire dolt start lock`.
- The runtime pack directory contained a zero-byte `dolt.lock`, but no
  `dolt.log`, `dolt-config.yaml`, or provider state file.
- `.beads/config.yaml` still contained `issue_prefix: tcs` and
  `issue-prefix: tcs`.
- `gc --city ... bd config list` could not connect because the Dolt server never
  started.

Artifacts:

```text
/tmp/test-city.jJeS5A/artifacts/
```

Result: setup FAIL, bug verdict INVALID. The raw upstream prebuilt binary does
not currently reach the same setup point as the source-built Nix package. That
means the prebuilt lane is useful, but it first needs its own start-lock
diagnosis before it can isolate "Nix source build changed behavior" from the
dolt-amp bug.

## Next run — unblock stock-v1.0.0 setup

Planned shape:

- Determine whether stock `v1.0.0` is expected to write `issue_prefix` into the
  bd database config table during `gc init`, or whether it only writes the
  compatibility `.beads/config.yaml` file.
- If stock `v1.0.0` cannot create sessions with current bd, record that as a
  separate setup regression and add a clearly named compatibility scenario
  before attempting dolt-amp reproduction.
- Diagnose the prebuilt lane's Dolt start lock separately from the source lane;
  do not treat prebuilt failure as evidence about the dolt-amp bug yet.
- Only run the five-minute dolt-amp observation after the runner health gate
  sees at least one session bead.
