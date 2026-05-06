# Maybe later — current upstream HEAD testing

This work is intentionally shelved while deployment validation takes priority.

## Candidate

On 2026-05-06, upstream `gastownhall/gascity` `origin/main` pointed at:

```text
8f97cac08e0cc64e5a2f7bf500a4c82154f3e337
Merge pull request #1673 from sjarmak/fix/jsonl-export-spike-runaway
fix(maintenance): jsonl-export spike detection runaway (#1547)
```

The commit message looked stable enough to test directly; no walk-back was
needed at that moment.

## Shelved work

The interrupted direction was to add a separate `test-city` lane named:

```text
run-idle-gascity-current-head-source
```

That lane would pin the exact upstream commit above, reuse
`templates/canonical-stock`, and run the same idle Dolt metrics harness used
for stock `v1.0.0`, upstream-main, the fork candidates, and `gascity-nix`.

## Reason to resume later

Current upstream `main` already carries the upstream-shaped
`clearWakeFailures` dirty check, so this lane would answer a broader question:
whether current upstream behavior still matches the validated fork/package
behavior under progressively richer test cities.

## Resume shape

1. Add a pinned flake input for the exact upstream commit under a new lane name.
2. Keep the existing candidate lanes untouched for comparison.
3. Run the canonical five-minute idle test first.
4. If flat, expand to richer city templates instead of replacing the baseline.
