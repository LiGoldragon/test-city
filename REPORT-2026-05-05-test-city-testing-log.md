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
- runtime dependencies in the Nix shell: `bd version 1.0.3 (dev)`,
  `dolt version 1.86.2`
- packaging note: the Nix package rewrites embedded `examples/*.sh`
  `#!/bin/sh` shebangs to bash before Go embedding, matching the known
  CriomOS packaging compatibility requirement.
- source-built lane: `nix run .#run-idle-stock-source`
- upstream-prebuilt lane: `nix run .#run-idle-stock-prebuilt`
- upstream-main source lane:
  `nix run .#run-idle-upstream-main-source`
- upstream-main source commit:
  `4be4d44be6df85b1c8b7f20c4afcc98fc1713dcc`
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

## 2026-05-06 00:08 CEST — stock source lane with SQL config capture

Purpose: rerun stock upstream Gas City `v1.0.0` after adding direct Dolt SQL
`config` table capture to setup-failure diagnostics.

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
/tmp/test-city.8HFnM3
```

Observed:

- Result remained `setup-failed`: no sessions became visible.
- `dolt-config-table.server.stdout` and `dolt-config-table.local.stdout` both
  showed `types.custom` but no `issue_prefix`.
- `.beads/config.yaml` still contained `issue_prefix: tcs` and
  `issue-prefix: tcs`, so the YAML compatibility file is not the state read by
  `bd create`.
- `bd-trace.log` showed no `bd init` invocation during the failure window.
- Source inspection of `v1.0.0` found the compatibility problem:
  `gc-beads-bd.sh` takes a metadata fast path when `.beads/metadata.json`
  exists, skips `bd init`, then runs
  `bd config set issue_prefix "$prefix" 2>/dev/null || true`. Current
  `bd 1.0.3` rejects protected `issue_prefix` writes through `bd config set`,
  so the script silently leaves the SQL config table without `issue_prefix`.

Artifacts:

```text
/tmp/test-city.8HFnM3/artifacts/
```

Result: setup FAIL, bug verdict BLOCKER IDENTIFIED. Stock source-built
`v1.0.0` is incompatible with current `bd` for metadata-preseeded managed
Dolt scopes.

## 2026-05-06 00:09-00:10 CEST — issue_prefix repair probe

Purpose: prove the missing SQL `issue_prefix` row is sufficient to explain the
stock source-lane setup failure.

Root:

```text
/tmp/test-city.8HFnM3
```

Action:

- Inserted only `('issue_prefix', 'tcs')` into
  `/tmp/test-city.8HFnM3/initialized-city/.beads/dolt/hq` table `config`.
- Restarted the isolated supervisor path and ran `gc start` against the same
  scratch city.

Observed:

- `repair-check-issue-prefix.stdout` showed `issue_prefix | tcs`.
- After the repair, `bd create ... mayor ...` succeeded in
  `repair-bd-trace.log`; before the repair the same operation failed with
  `database not initialized: issue_prefix config is missing`.
- `repair-session-list.json` showed a created mayor session bead `tcs-3xw`.
- This was not counted as a valid dolt-amp run because the root was manually
  mutated and then stopped during cleanup; it was a targeted causality probe.

Result: PROBE PASS. Missing SQL `issue_prefix` is the immediate blocker for
stock `v1.0.0` setup with current `bd`.

## 2026-05-06 00:15-00:16 CEST — upstream-main source lane smoke

Purpose: compare the same isolated city shape against pinned upstream-main
Gas City, which includes the post-`v1.0.0` bd runtime config fix.

Command:

```bash
KEEP_TEST_ROOT=1 \
TEST_CITY_HEALTH_TIMEOUT_SECONDS=20 \
TEST_CITY_OBSERVATION_SECONDS=15 \
TEST_CITY_SAMPLE_INTERVAL_SECONDS=5 \
nix run .#run-idle-upstream-main-source
```

Root:

```text
/tmp/test-city.bHQkmc
```

Observed:

- Result was `observed`: the session health gate passed and the short
  observation window completed.
- `session-list.final.json` showed active mayor session `tum-zrd`.
- Direct SQL config check showed `issue_prefix | tum` and `types.custom` in the
  `hq` config table.
- `bd-trace.log` showed `bd create ... mayor ...` succeeded in about 885 ms.
- Short-window samples:
  - `event-samples.tsv`: event lines rose from 5 to 10, then stayed at 10.
  - `.beads` size rose from about 526 KiB to 595 KiB, then flattened over the
    remaining sample.
  - one Dolt listener was present on the managed test-root port.

Artifacts:

```text
/tmp/test-city.bHQkmc/artifacts/
```

Result: setup PASS, short observation PASS. This does not yet characterize the
original five-minute dolt write-amp bug, but it proves the pinned upstream-main
lane clears the `issue_prefix` setup blocker that invalidates stock `v1.0.0`.

## 2026-05-06 00:20-00:25 CEST — upstream-main five-minute idle observation

Purpose: run the first valid five-minute idle dolt-amp window after adding
direct Dolt SQL commit-count and processlist sampling.

Command:

```bash
KEEP_TEST_ROOT=1 \
TEST_CITY_HEALTH_TIMEOUT_SECONDS=30 \
TEST_CITY_OBSERVATION_SECONDS=300 \
TEST_CITY_SAMPLE_INTERVAL_SECONDS=10 \
nix run .#run-idle-upstream-main-source
```

Root:

```text
/tmp/test-city.qHzB2c
```

Observed:

- Result was `observed`: setup passed and the full observation window
  completed.
- `session-list.final.json` showed active mayor session `tum-2ir`.
- `dolt-metrics.tsv`:
  - first sample: commit count 8 at `2026-05-05T22:20:16Z`;
  - second sample: commit count 12 at `2026-05-05T22:20:26Z`;
  - final sample: commit count 12 at `2026-05-05T22:25:06Z`.
  - Stable-window commit delta after startup: 0.
- `event-samples.tsv`:
  - events rose from 5 to 10 during startup;
  - events remained 10 from the second sample through the final sample.
  - Stable-window event delta after startup: 0.
- `size-samples.tsv`:
  - `.beads` grew from 525,427 bytes to 618,720 bytes during startup, then to
    619,688 bytes by the final sample.
  - Stable-window `.beads` delta after startup: 968 bytes.
  - `.gc` grew from 517,787 bytes to 617,400 bytes; most of this is runtime
    log/artifact churn, not Dolt commits.
- `dolt-processlist.tsv` showed only the sampler's own `show processlist`
  query at each sample, not a growing connection set.
- Dolt process `%CPU` in `process-samples.tsv` decayed from 20.0% at the first
  sample to 2.8% at the final sample. Average over sampled lines was 6.04%.
- `dolt.log` contained startup/schema/idempotent `nothing to commit` warnings
  and one transient serialization failure. The failed `state=awake` update was
  retried successfully in `bd-trace.log`.

Artifacts:

```text
/tmp/test-city.qHzB2c/artifacts/
```

Result: upstream-main idle dolt-amp verdict PASS for this minimal always-on
city. It does not reproduce the Criopolis idle write amplification pattern.

## 2026-05-06 00:28 CEST — gascity-nix fork pin setup smoke

Purpose: test the currently deployed `gascity-nix` pin lineage under the same
minimal source-built lane. This is the `1.0.0-codex-2026-05-05` build from
Gas City commit `a720d067c0fcc9b77054222da5be6fac98091217`.

Command:

```bash
KEEP_TEST_ROOT=1 \
TEST_CITY_HEALTH_TIMEOUT_SECONDS=15 \
TEST_CITY_OBSERVATION_SECONDS=30 \
TEST_CITY_SAMPLE_INTERVAL_SECONDS=10 \
nix run .#run-idle-gascity-nix-source
```

Root:

```text
/tmp/test-city.8Zto9z
```

Observed:

- Result was `setup-failed`: no sessions became visible.
- Gas City binary:
  `/nix/store/gbbnf94h92vx5wm2q2whd67h6hblc30y-gascity-1.0.0-codex-2026-05-05/bin/gc`.
- `dolt-config-table.server.stdout` showed `types.custom` but no
  `issue_prefix`.
- `bd-config-get-issue-prefix.stdout` reported `issue_prefix (not set)`.
- `.beads/config.yaml` contained `issue_prefix: tcs` and `issue-prefix: tcs`.
- `bd create ... mayor ...` failed with
  `database not initialized: issue_prefix config is missing`.

Artifacts:

```text
/tmp/test-city.8Zto9z/artifacts/
```

Result: setup FAIL. The deployed fork pin has the same current-`bd`
compatibility blocker as stock `v1.0.0`; the post-`v1.0.0` upstream-main
`issue_prefix` SQL upsert fix is not present in this pin.

## Next run — patch fork or advance pin

Planned shape:

- Patch `LiGoldragon/gascity` or advance the fork pin so managed bd init writes
  `issue_prefix` into the SQL config table without using `bd config set`.
- After a fork fix exists, add a Nix lane for the fix candidate and rerun the
  source-built setup gate.
- Diagnose the prebuilt lane's Dolt start lock separately from the source lane;
  do not treat prebuilt failure as evidence about the dolt-amp bug yet.

## 2026-05-06 00:36-00:37 CEST — fork issue-prefix candidate smoke

Purpose: validate the first fork candidate that cherry-picks upstream's managed
bd runtime config repair onto the `rebase-v1.0.0` fork line.

Gas City source:

```text
LiGoldragon/gascity fix/bd-runtime-issue-prefix
89b035f0d5a767668f6878d5229a46096f3cb2da
```

Test-city lane:

```bash
nix run .#run-idle-gascity-issue-prefix-source
```

Root:

```text
/tmp/test-city.BQsJfb
```

Observed:

- Result was `observed`: setup passed and the short observation window
  completed.
- `session-list.final.json` showed active mayor session `tcs-7ov`.
- `dolt-metrics.tsv` showed `issue_prefix=tcs` at every sample.
- Commit count rose from 9 to 14 during startup and stayed at 14 over the
  30-second smoke window.

Artifacts:

```text
/tmp/test-city.BQsJfb/artifacts/
```

Result: setup PASS. This candidate clears the stock/gascity-nix
`issue_prefix` blocker, but this short smoke was not enough to validate the
five-minute dolt-amp behavior.

## 2026-05-06 00:38-00:43 CEST — fork issue-prefix five-minute idle observation

Purpose: run the same five-minute canonical-stock idle window against the
issue-prefix-only fork candidate.

Command:

```bash
KEEP_TEST_ROOT=1 \
TEST_CITY_HEALTH_TIMEOUT_SECONDS=90 \
TEST_CITY_OBSERVATION_SECONDS=300 \
TEST_CITY_SAMPLE_INTERVAL_SECONDS=10 \
nix run .#run-idle-gascity-issue-prefix-source
```

Root:

```text
/tmp/test-city.rkTpZP
```

Observed:

- Result was `observed`: setup passed and the full observation window
  completed.
- Final session was active mayor session `tcs-s42`.
- Direct SQL config table had `issue_prefix | tcs` and `types.custom`, so the
  setup blocker was gone.
- `dolt-metrics.tsv`:
  - first sample: commit count 9 at `2026-05-05T22:38:46Z`;
  - second sample: commit count 14 at `2026-05-05T22:38:57Z`;
  - final sample: commit count 124 at `2026-05-05T22:43:46Z`.
  - Stable-window commit delta after startup: +110.
- `event-samples.tsv`:
  - events rose from 5 to 11 during startup;
  - final sample: 123 events at `2026-05-05T22:43:46Z`.
  - Stable-window event delta after startup: +112.
- `bd-trace.log` showed the repeating writer:
  `bd update --json tcs-s42 --set-metadata quarantined_until= --set-metadata wake_attempts=0`
  approximately every few seconds.

Artifacts:

```text
/tmp/test-city.rkTpZP/artifacts/
```

Result: setup PASS, dolt-amp verdict FAIL. The missing `issue_prefix` was only
the setup blocker; the runtime write amplification still reproduced on the
fork when `clearWakeFailures` wrote already-clear metadata.

## 2026-05-06 00:52-00:57 CEST — fork dolt-amp fix five-minute idle observation

Purpose: validate the second fork candidate, which keeps the issue-prefix SQL
repair and adds a dirty check to `clearWakeFailures` so stable sessions do not
write already-clear `wake_attempts` / `quarantined_until` metadata.

Gas City source:

```text
LiGoldragon/gascity fix/bd-runtime-issue-prefix
6462edf36cefa88bde03f19439173a3bc821a708
```

Test-city lane:

```bash
nix run .#run-idle-gascity-dolt-amp-source
```

Command:

```bash
KEEP_TEST_ROOT=1 \
TEST_CITY_HEALTH_TIMEOUT_SECONDS=90 \
TEST_CITY_OBSERVATION_SECONDS=300 \
TEST_CITY_SAMPLE_INTERVAL_SECONDS=10 \
nix run .#run-idle-gascity-dolt-amp-source
```

Root:

```text
/tmp/test-city.lQ8bZD
```

Observed:

- Result was `observed`: setup passed and the full observation window
  completed.
- Final session was active mayor session `tcs-1bx`.
- Direct SQL config table had `issue_prefix | tcs` and `types.custom`.
- `dolt-metrics.tsv`:
  - first sample: commit count 9 at `2026-05-05T22:52:37Z`;
  - second sample: commit count 14 at `2026-05-05T22:52:48Z`;
  - final sample: commit count 14 at `2026-05-05T22:57:36Z`.
  - Stable-window commit delta after startup: 0.
- `event-samples.tsv`:
  - events rose from 5 to 11 during startup;
  - events rose once more to 12 at `2026-05-05T22:53:20Z`;
  - final sample remained 12.
  - Stable-window event delta after startup: +1, then flat for the rest of the
    observation.
- `dolt-processlist.tsv` and `connection-samples.tsv` showed no growing
  connection set. The visible steady-state connections were the sampler's
  `show processlist` query and short read-only bd polling.
- Dolt process `%CPU` in `process-samples.tsv` decayed from 23.7% at the first
  sample to 3.1% at the final sample. Average over sampled lines was 6.61%.
- `bd-trace.log` still showed read traffic (`bd list`, `bd ready`,
  `bd show mayor` failures), but the repeating `bd update ... wake_attempts=0`
  writer was gone during the observation. Only the expected shutdown writes
  appeared after the runner stopped the supervisor.

Artifacts:

```text
/tmp/test-city.lQ8bZD/artifacts/
```

Result: setup PASS, dolt-amp verdict PASS for this minimal always-on city. The
controlled reproduction confirms the runtime commit/event growth in this
harness comes from the stable-session `clearWakeFailures` no-op metadata write.
