# Active goal — deploy validated Gas City and ramp testing

## Current objective

Keep the live CriomOS home profile on the currently validated Gas City fork
pin, then continue ramp testing the `gc` binary from `PATH` against isolated
test-city roots.

## Validated input

```text
LiGoldragon/gascity-nix
3aa2e01c480ccd042c321802095bc7d599763579

LiGoldragon/gascity
60732751665b4c70685f06a425febbe96eeb6286
```

This is no longer just the original Dolt write-amp fix. The currently deployed
pin also includes the lifecycle wake fixes found by the churn scenario:

- explicit wake requests for dormant sessions;
- active/awake wake requests when user-hold blocker metadata is already present;
- stale drain-completion writes do not overwrite an already visible create claim;
- stale drain-finalization writes do not clear a create claim if they land after
  an explicit wake.

The packaged and PATH lanes already passed the minimal always-on idle tests:

```text
/tmp/test-city.6IBO5c
commits: 14 after startup, 14 final
events: 12 after startup, 12 final

/tmp/test-city.912f6H
commits: 14 after startup, 14 final
events: 12 after startup, 12 final
```

## Next steps

1. Done: `CriomOS-home` now points at `gascity-nix 3aa2e01...`.
2. Done: the CriomOS home profile was activated with `lojix-cli`.
3. Done: `gc version --long` from `PATH` reports
   `60732751665b4c70685f06a425febbe96eeb6286`.
4. Done: `run-idle-path-gc` passed the canonical five-minute idle test using
   `/home/li/.nix-profile/bin/gc`.
5. Done: `run-idle-path-gc-expanded` passed a ten-minute expanded idle test
   with always-on named sessions plus a fixed two-slot pool.
6. Done: `run-idle-path-gc-on-demand` passed a five-minute post-wake test
   after materializing the expanded template's on-demand `auditor` session.
7. Done: `run-idle-path-gc-lifecycle-churn` passed a ten-minute post-churn
   observation after suspend/wake, close/wake, and pool-worker kill/restart.
8. Next: increase breadth with longer or more varied PATH scenarios only after
   committing the current reports.

## Current evidence

`CriomOS-home` commit `ce1f1e3` pins the fixed `gascity-nix` package and was
pushed before activation. `lojix-cli` activation completed successfully; the
activation log is `/tmp/lojix-home-activate-20260506T030900Z.log`.

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

PATH `gc` on-demand wake run:

```text
/tmp/test-city.zDKiIL
template: expanded-inert
action: checks/wake-auditor.sh
sessions: auditor, mayor, deacon, worker-1, worker-2 active
session starts: exactly 5
commits: 45 -> 46, then 46 for 52 samples
events: 53 -> 54 -> 59, then 59 for 50 samples
Dolt CPU: 27.2% first, 10.5% final, 14.97% average
```

PATH `gc` lifecycle churn run:

```text
/tmp/test-city.hAIXrY
template: expanded-inert
action: checks/lifecycle-churn.sh
suspend/wake: auditor bead tei-cr7 preserved
close/wake: auditor bead replaced tei-cr7 -> tei-dl9
worker restart: worker-1 start count 1 -> 2
session starts: exactly 8
commits: 75 -> 76, then 76 for 103 samples
events: 99 -> 105, then 105 for the remaining samples
Dolt CPU: 28.8% first, 10.9% final, 15.53% average
```

## Commit discipline

Each report, harness, package, and deployment-repo change is committed and
pushed before moving to the next logical step.
