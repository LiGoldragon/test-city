# Active goal — deploy validated Gas City and ramp testing

## Current objective

Use the validated `LiGoldragon/gascity-nix` pin in the live CriomOS home
profile, then test the `gc` binary from `PATH` rather than only the direct
test-city Nix lanes.

## Validated input

```text
LiGoldragon/gascity-nix
db668627ca3293c45778390ecf1b193c74607246

LiGoldragon/gascity
6462edf36cefa88bde03f19439173a3bc821a708
```

The packaged lane already passed the minimal always-on idle test:

```text
/tmp/test-city.6IBO5c
commits: 14 after startup, 14 final
events: 12 after startup, 12 final
```

## Next steps

1. Done: `CriomOS-home` now points at `gascity-nix db668627...`.
2. Done: the CriomOS home profile was activated with `lojix-cli`.
3. Done: `gc version --long` from `PATH` reports
   `6462edf36cefa88bde03f19439173a3bc821a708`.
4. Done: `run-idle-path-gc` passed the canonical five-minute idle test using
   `/home/li/.nix-profile/bin/gc`.
5. Done: `run-idle-path-gc-expanded` passed a ten-minute expanded idle test
   with always-on named sessions plus a fixed two-slot pool.
6. Next: add an active on-demand wake scenario so testing covers more than
   passive startup and idle convergence.

## Current evidence

`CriomOS-home` commit `78a0bed8` pins the fixed `gascity-nix` package and was
pushed before activation. `lojix-cli` activation completed successfully; the
activation log is `/tmp/lojix-home-activate-20260506T030934.log`.

PATH `gc` canonical idle run:

```text
/tmp/test-city.912f6H
template: canonical-stock
commits: 9 -> 13 -> 14, then 14 for 51 samples
events: 5 -> 10 -> 11 -> 12, then 12 for 46 samples
Dolt CPU: 23.4% first, 3.6% final, 6.89% average
```

PATH `gc` expanded idle run:

```text
/tmp/test-city.8w1xfH
template: expanded-inert
sessions: mayor, deacon, worker-1, worker-2 active
on-demand auditor: absent, as expected
commits: 33 -> 37, then 37 for 104 samples
events: 39 -> 43 -> 47, then 47 for 100 samples
Dolt CPU: 25.2% first, 7.4% final, 10.31% average
```

## Commit discipline

Each report, harness, package, and deployment-repo change is committed and
pushed before moving to the next logical step.
