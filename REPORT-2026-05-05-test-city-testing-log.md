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
  CriomOS packaging compatibility requirement. If the idle bug is ambiguous,
  add a raw-prebuilt comparison after the first controlled run.
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

## Next run — stock-v1.0.0 idle dolt amp

Planned shape:

- prepare a fresh `canonical-stock` root with `nix run .`
- run `gc init --from` and `gc start` inside an isolated environment:
  `GC_HOME`, `XDG_RUNTIME_DIR`, `TMPDIR`, `DOLT_ROOT_PATH`, and
  `GIT_CONFIG_GLOBAL` all under the test root
- keep the supervisor local to that isolated `GC_HOME`
- observe for 5 minutes
- capture process, event, dolt-log, and disk-growth artifacts under the test
  root before teardown
