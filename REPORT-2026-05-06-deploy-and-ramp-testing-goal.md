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

1. Point `CriomOS-home` at `gascity-nix db668627...`.
2. Activate the CriomOS profile with `lojix-cli`.
3. Confirm `gc version --long` from `PATH` reports
   `6462edf36cefa88bde03f19439173a3bc821a708`.
4. Run the test-city harness using the `gc` from `PATH`.
5. If no bug appears, add richer named-session, pool, and maintenance scenarios
   and compare artifacts against the expected behavior implied by Gas City docs,
   config comments, and source comments.

## Commit discipline

Each report, harness, package, and deployment-repo change is committed and
pushed before moving to the next logical step.
