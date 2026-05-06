# Dolt write-amp investigation — 2026-05-05 incident report

*Authored by Criopolis mayor (Claude) at the end of an extended debugging
session. Codex is the intended consumer — Claude is too slow for the
iterate-test-iterate loop this bug needs. The discipline gap that produced
this report is at the bottom; read the whole thing before patching anything.*

## TL;DR

Criopolis hit sustained dolt CPU pegging (98% sustained, multiple instances
across ~hours) and disk-bloat (3.1 GB on the `hq` bead-store database). Two
patches landed in the `LiGoldragon/gascity` fork on branch
`code-writer/cr-5drwd1`:

- `gascity 9114c814 (cr-5drwd1 spawn-cycling fix)` — pending-create
  admission throttle, fixes a separate but related bug.
- `gascity a720d067 (cr-vc7hcx clearWakeFailures no-op suppress)` —
  gates the `clearWakeFailures` reconciler call on
  `wake_attempts==0 && quarantined_until==""`.

Pin chain to deploy them: `LiGoldragon/gascity-nix d6009c3` →
`LiGoldragon/CriomOS-home df621c1`.

**The clearWakeFailures patch fixed the disk-bloat aspect** (events.jsonl
stopped growing, dolt store stayed at 1.2 MB instead of accumulating GBs).

**The clearWakeFailures patch did NOT fix the CPU pegging.** After deploying
the new binary on a fresh dolt store, dolt sustained 98% CPU with `nothing
to commit` warnings firing at ~0.7/sec. Mayor's diagnosis ("clearWakeFailures
is the load source") was at best partial; at worst it pointed at the wrong
mechanism entirely. The second-half of the bug is **unresolved**.

## Test-city follow-up — 2026-05-06

The controlled `test-city` harness now reproduces and separates two issues:

1. Stock source-built `v1.0.0` and the deployed `gascity-nix` pin do not pass
   setup with current `bd 1.0.3` because managed bd init leaves the SQL
   `config` table without `issue_prefix`. The YAML file has `issue_prefix`, but
   `bd create` reads SQL config and fails.
2. After the upstream `issue_prefix` SQL repair is cherry-picked onto the fork,
   the minimal always-on city reaches a valid five-minute idle window and
   reproduces Dolt write amplification: commits grow from 14 to 124 and events
   from 11 to 123. `bd-trace.log` identifies the repeating write as
   `bd update ... --set-metadata quarantined_until= --set-metadata wake_attempts=0`.

A second fork candidate at
`LiGoldragon/gascity 6462edf36cefa88bde03f19439173a3bc821a708` keeps the
`issue_prefix` repair and dirty-checks `clearWakeFailures`. In the same
five-minute harness, Dolt commits reach 14 after startup and remain 14 through
the final sample; events reach 12 and remain flat. See
`REPORT-2026-05-05-test-city-testing-log.md` for artifact roots and exact
sample series. The updated `LiGoldragon/gascity-nix` package pin at
`db668627ca3293c45778390ecf1b193c74607246` was also validated through the same
five-minute lane with the same flat commit/event result.

After `CriomOS-home` was moved to that `gascity-nix` pin and activated through
`lojix-cli`, the `gc` found on `PATH` reported
`6462edf36cefa88bde03f19439173a3bc821a708`. The PATH binary passed both:

- canonical five-minute idle test: commits reached 14 after startup and then
  stayed flat for 51 samples; events reached 12 and stayed flat for 46 samples.
- expanded ten-minute idle test: always-on `mayor` and `deacon`, two fixed pool
  workers, and cold on-demand `auditor`; commits reached 37 and stayed flat for
  104 samples; events reached 47 and stayed flat for 100 samples.

This evidence says the test-city reproduction no longer finds the dolt
write-amp bug in the deployed PATH binary. It does not by itself prove every
Criopolis production load shape is fixed; the next ramp target is active
on-demand wake behavior.

## What was observed

Pre-patch (Criopolis production city, supervisor on `gascity 76f46b45 = v1.0.0
+ codex model cherry-pick`):

- `dolt sql-server` PID at 93–307% CPU sustained over hours.
- `events.jsonl` growing at ~30 events/sec, 99% of which were `bead.updated`
  for the always-on session beads (`mayor`, `control-dispatcher`).
- `dolt.log` flooded with `error="nothing to commit"` warnings at 2/sec
  (~125/sec connection rate to dolt).
- `.beads/dolt/hq` grew to 3.1 GB over the day.
- Diff between consecutive `bead.updated` events for the same session bead:
  only `updated_at` changed; every other field — including
  `wake_attempts: "0"` and `quarantined_until: ""` — was byte-identical.
- Supervisor logs flooded with `assignedWorkBeads: 0 beads (rigStores=0)`
  at sub-second rate.

Post-patch (Criopolis production city, supervisor on
`gascity a720d067 = above + spawn-cycling + clearWakeFailures-suppress`,
fresh empty dolt store):

- `events.jsonl` did NOT grow during the steady-state window. So no actual
  `bead.updated` writes were committing.
- `.beads/dolt` stayed at 1.2 MB. So no commit history was accumulating.
- `dolt sql-server` was at 98% CPU sustained over the 2.5-min observation
  window.
- `dolt.log` was still emitting `error="nothing to commit"` warnings —
  ~50 in the last 60 lines, ~0.7/sec.
- Connection rate to dolt was elevated: connectionIDs incremented from
  ~10 to ~5300 in ~70 seconds (~75/sec), most resulting in
  `nothing to commit`.

Reading: the patch successfully prevented commits from succeeding (no event
emit, no history accumulation), but the CPU sink wasn't the successful
commits — it was something else that was ALSO firing. Each elevated
connection cost dolt connection setup + transaction begin + commit attempt
+ rejection + warning log, even when the commit was a no-op.

## What we patched and why we patched it

### Patch 1: cr-5drwd1 spawn-cycling fix

**Bug**: when an `on_demand` named_session has `poolDesired > 1` and a
routed bead, the supervisor reconciler creates new session beads every
~250–500 ms in a tight loop. Each tick: `poolDesired: <agent> = 2`,
`scaleCheck: <agent> = 2`, `assignedWorkBeads: 0`, fire another create.
Witnessed twice on Criopolis: 24+ `maintainer` sessions stacked in
`creating`/`stopped` state, then 47 `code-writer` sessions later in the
same day.

**Fix**: per-template in-flight admission throttle in the start path.
Pool-managed active/awake sessions AND `pending_create_claim=true` creates
now both count toward the desired total; in-flight creates suppress
additional new scale-check and min-fill admissions for that template.
Files touched in `cmd/gc/`: `pool_desired_state.go`,
`session_lifecycle_parallel.go`, `session_reconciler.go`.

**Status**: deployed in the fork. Whether the same fix already exists
upstream — see "What we should have checked first" below.

**Source-side caveat**: this fix gates on `pending_create_claim` and a
startup-timeout window. Race conditions or edge cases around the
`startup_timeout` boundary are plausible. Tests passed locally
(`TestComputePoolDesiredStates_InFlightCreate`,
`TestReconcileSessionBeads_PendingCreate`) but the broader
`go test ./cmd/gc` suite failed in the worktree with city-discovery
unrelated errors; full upstream regression suite was NOT run.

### Patch 2: cr-vc7hcx clearWakeFailures no-op suppress

**Diagnosis (incomplete)**: `clearWakeFailures` in
`cmd/gc/session_reconcile.go` was being called every tick on stable sessions,
unconditionally writing `wake_attempts="0"` and `quarantined_until=""`,
which on stable sessions are already empty/zero. This produced same-content
SQL UPDATE calls that bumped `updated_at` (because dolt-side it's a real
row write with a new timestamp), causing dolt to commit a new revision per
tick. Over hours, the commit history bloated to GBs.

**Fix**:

```go
func clearWakeFailures(session *beads.Bead, store beads.Store) {
    if sessionWakeFailuresAlreadyClear(*session) {
        return
    }
    // ... existing batch write
}

func sessionWakeFailuresAlreadyClear(session beads.Bead) bool {
    return (strings.TrimSpace(session.Metadata["wake_attempts"]) == "" ||
        strings.TrimSpace(session.Metadata["wake_attempts"]) == "0") &&
        session.Metadata["quarantined_until"] == ""
}
```

**Status**: deployed. Observed effect post-deploy: events.jsonl growth
stopped, dolt store stayed small. Disk-bloat aspect of the bug is fixed.

**What this patch did NOT fix**: dolt CPU pegging. Post-patch, dolt was
still at 98% sustained, with `nothing to commit` warnings still firing.
Whatever else is driving the CPU was never identified.

## What we don't know

This is the honest part. The patches were authored on the strength of
reading events.jsonl and inferring the SQL behind it. The actual dolt-side
load was never instrumented. So:

- We don't know whether dolt's CPU is going to **rejected commits**,
  **read queries** (reconciler tick reads), **bd-wrapper subprocess churn**
  (each `bd update` invocation is a separate process opening a new dolt
  connection), **auto-GC**, or **internal compaction**.
- We don't know whether the residual `nothing to commit` warnings come
  from another reconciler call site (~25 `SetMetadata*` call sites exist in
  `cmd/gc/session_reconcile.go` + `session_reconciler.go`; only one was
  patched), or from a different code path entirely (e.g., bd's own session
  bead wrapper layer, dolt's own background work).
- We don't know whether the bug reproduces in stock upstream `v1.0.0`
  WITHOUT our fork patches. We never ran a controlled comparison.
- We don't know whether the bug reproduces in upstream/main (which is ~389
  commits ahead of v1.0.0 with reconciler/session fixes — see "Upstream
  fixes we didn't check first" below).
- We don't know whether the bug is sensitive to Criopolis's specific
  pack.toml or city.toml — the test in production was always against the
  full live config, never minimal.

## Upstream fixes we didn't check first

Before authoring custom patches, mayor should have run `git log upstream/main`
to see if the bugs were already fixed. They weren't checked. After-the-fact,
several upstream PRs since `v1.0.0` look directly relevant:

- `b31fd6c5 fix: add respawn circuit breaker for named sessions (#563)` —
  may overlap with our spawn-cycling fix entirely.
- `7c892b94 fix(session): honor pending create start lease (#1702)` —
  pending-create lifecycle, same surface.
- `def74a27 fix(reconciler): use pending_create_started_at for staleCreatingState (#1586)`.
- `5a7dbddb fix: post-merge remediation for PR 1586 (#1703)`.
- `155029ce fix(reconciler): roll back stale pending-create beads in desired branch (#1533)`.
- `23b1e407 fix(controller): preserve cached demand correctness (#1646)`.
- `50b04c82 fix: keep assigned workflow sessions waking (#1704)`.

None of those commit messages explicitly mention "no-op metadata commit"
or "write amp", but several touch the exact reconciler write paths where
mayor's diagnosis pointed. **It's plausible upstream/main has already fixed
both bugs, and the right move is to pin Criopolis to upstream/main rather
than maintain a fork.** That's a hypothesis the test-city repo should
validate before more fork patches ship.

## What I would check if forced to find this

(Mayor / Claude can't physically run a debugger or hold a gun. Codex can.
Here is the diagnostic flow that should have been the FIRST step, not the
last.)

### Phase 1: Instrument the actual load (no patching)

Run a representative test city to steady-state with the bug exercised.
Capture, every 5 seconds for 5 minutes:

1. **`dolt sql -q "SHOW FULL PROCESSLIST"`** — what queries are actually
   running, who's running them, how long they've been running. If there's
   a tight read loop, this shows the SELECT. If it's connection churn,
   this shows lots of short connections.
2. **`lsof -p <dolt-pid>`** filtered to TCP — every open connection's
   peer process. Maps connections to bd-wrapper / supervisor / agent
   subprocesses.
3. **`/proc/<dolt-pid>/io`** — bytes-read, bytes-written. Differentiates
   read-heavy from write-heavy workload.
4. **`pgrep -af bd-wrapper | wc -l`** — bd-wrapper process count. Spikes
   suggest subprocess-per-call churn.
5. **`pidstat -p <dolt-pid> 1`** — kernel-side CPU vs sys vs iowait.
6. **`tail -f dolt.log`** filtered to non-`nothing-to-commit` — anything
   else dolt's saying.

### Phase 2: Bisect what's making the calls

Once load shape is known:

7. **`strace -p <dolt-pid> -e trace=connect,accept`** — origin processes
   for each new connection.
8. **`perf top -p <dolt-pid>`** — where CPU is actually being spent
   (parsing? GC? compaction? row reads?).
9. For each suspicious caller process, **`strace -p <pid> -e trace=connect`**
   to see when it opens dolt connections + what it queries (`-e
   trace=write` shows the SQL).

### Phase 3: Source bisect

10. With known queries firing N times per second, find the call site:
    `rg "<query-snippet>" cmd/ internal/`. Cross-check with the audited
    `SetMetadata*` call list in `session_reconcile.go` + `session_reconciler.go`.
11. Each call site that fires on stable sessions is a candidate for the
    same gate as `clearWakeFailures` (return early if no actual change).
12. Reproduce bug presence/absence at upstream/main HEAD. If absent,
    bisect upstream/main back to v1.0.0 to find which commit fixed it.

### Phase 4: Validate fix candidates

13. Apply the candidate fix in a fork branch.
14. Re-run the test city with the fixed binary.
15. Re-capture phase-1 diagnostics. Compare. PASS = CPU dropped to baseline,
    connection rate dropped, no warning spam. FAIL = back to phase 2.

The cost of phase 1 is small (<10 minutes of operator time + ~5 minutes
of test city runtime). The cost of skipping phase 1 is the ~6 hours of
this session.

## Where this goes from here

A new repo, `LiGoldragon/test-city`, has been created to do exactly this
work in a controlled, reproducible, isolated environment. It uses
`gascity-nix` as a flake input and supports per-template pin overrides
(stock `v1.0.0`, `upstream/main`, fork branches, fix candidates).

Inspiration is the orchestrator repo's
`tests/scripts/orchestrator-isolated-gc-test.sh` pattern: scratch dir under
`mktemp -d`, refusal to start under any production city path, full
supervisor + dolt teardown on exit. **Codex is the intended driver of
test-city** — Claude is too slow for the iterate-test-iterate loop.

First scenario for codex to run: spawn the canonical-stock template (gascity
v1.0.0 with no fork patches), watch dolt for 5 min idle, see if the amp
reproduces. If it does, the bug is upstream and we file the issue with a
clean reproducer. If it doesn't, the bug is specific to Criopolis's
configuration or our fork patches and we bisect. Keep the source-built
`v1.0.0` runner and the upstream-prebuilt `v1.0.0` runner separate; the
prebuilt lane should enter Nix as a fixed-output derivation so binary-provenance
comparisons still run with `nix run`.

Active run notes now live in
`REPORT-2026-05-05-test-city-testing-log.md`. Keep this incident report as
the forensic handoff; put every concrete test run, command shape, result, and
artifact path in the testing log so the investigation has a single append-only
operational record.

Current status from test-city on 2026-05-06: stock source-built `v1.0.0` is
blocked at setup by a bd compatibility regression. It pre-seeds
`.beads/metadata.json`, skips `bd init`, then silently runs
`bd config set issue_prefix`; current `bd 1.0.3` rejects that protected key, so
the Dolt SQL `config` table lacks `issue_prefix` and `bd create` fails. A
targeted SQL repair of only `issue_prefix = tcs` unblocked mayor session bead
creation in the scratch root. Pinned upstream-main Gas City
`4be4d44be6df85b1c8b7f20c4afcc98fc1713dcc` passes the same short harness and
writes `issue_prefix` into the SQL config table. The raw prebuilt `v1.0.0` lane
is wired through a Nix fixed-output derivation, but currently fails earlier on
Dolt start-lock acquisition. See the testing log for artifact paths and exact
commands.

After deploying the validated fork through `CriomOS-home`, the `gc` binary from
the activated user profile passed three isolated test-city lanes:

- canonical idle: one always-on mayor session, five-minute observation;
- expanded idle: always-on mayor/deacon plus a fixed two-session worker pool,
  ten-minute observation;
- expanded on-demand wake: the same expanded baseline plus `gc session wake
  auditor`, five-minute post-wake observation.

These runs did not reproduce the post-startup Dolt write-loop signature: Dolt
commits and Gas City events flattened after startup or wake convergence, working
changes stayed at zero, and session starts matched the expected session count.
This validates the fork for the currently modeled load shapes. It does not yet
prove production Criopolis load shapes, so test-city should keep adding
controller-action and lifecycle-churn scenarios before declaring the issue fully
burned down.

Cost discipline for test-city: `gpt-5.4-mini` + `model_reasoning_effort=low`,
short test windows, single-agent test cities unless a scenario specifically
needs more.

## What did we even do today (chronological summary, brief)

For codex's situational awareness, in case any prior fix-attempt has
relevance to ongoing investigation. Skip if just running fresh tests.

1. Mayor (Claude) hit cycling bug on `maintainer` agent (24+ creating sessions).
   Workaround: `suspended = true` on the agent + manual single-explicit
   `gc session new <template> --no-attach` spawning. **This silently
   disabled gascity's pool-managed idle-recovery (PR `d6639ed1`).**
2. Subsequent symptom: agents finish their work bead but don't exit.
   Manifestation of the side-effect of (1), but mayor diagnosed it as a
   harness bug ("Goal C") and chased it as a separate issue.
3. cr-xpkjfx: Criopolis-local mitigation — drain-ack added to 13 codex role
   prompts + `sleep_after_idle = "15m"` on 12 codex agents in pack.toml.
4. cr-l55mfh: gascity source change `gascity 992807e3 (sleep-default)` —
   default sleep policy changed from `legacy_off` to a sane default. This
   was the wrong fix, because the symptom was the workaround (1)
   side-effect, not a real harness bug. Patch is in fork branch
   `codex/cr-l55mfh-default-sleep` but NOT in the deployed `code-writer/cr-5drwd1` chain.
5. cr-5drwd1: gascity source change `gascity 9114c814 (cycling-fix)` —
   real source-level fix for the cycling bug (1).
6. cr-vc7hcx: gascity source change `gascity a720d067
   (clearWakeFailures-no-op-suppress)` — partial fix as documented above.
7. Pin chain `gascity-nix d6009c3` + `CriomOS-home df621c1` deploys (5)+(6)
   together, NOT (4).
8. Li ran `lojix-cli HomeOnly Build/Profile/Activate` after `git pull` of
   CriomOS-home (the local was 2 commits behind for the first attempt;
   second attempt landed correctly).
9. Mayor ran `gc supervisor install` to rotate the supervisor binary to
   the new build (`gbbnf94h92vx5wm2q2whd67h6hblc30y-...`, commit
   `a720d067`). Supervisor at `1391433` PID, running on new binary.
10. Li wiped `.beads/dolt` to `.beads/dolt.bloat-2026-05-05` (forensic
    backup, 3.1 GB preserved).
11. Li `gc start`-ed the city. Mayor measured at T+2.5 min: events flat,
    store small, dolt CPU 98%. Bug partially persisted.
12. Li shut the city back down. Mayor (Claude) was freed to free-standing,
    code-writer was in a free-standing codex harness for the patch authoring.

## Discipline gaps to canonize

To prevent the next round of "patch-first, verify-never":

1. **Always run `git log upstream/main` before authoring a fork patch.**
   Don't reinvent fixes that exist.
2. **Instrument actual load before diagnosing.** `events.jsonl` patterns
   are circumstantial; dolt processlist + connection rate + perf-top are
   primary evidence.
3. **Never harden a workaround into a permanent rule.** When a bug forces
   a workaround, file the root-cause bead AND keep the workaround scoped
   to the live session — don't bake it into pack.toml or prompts as
   though it were a feature.
4. **Run the test in a controlled environment, not on Criopolis.** Production
   city ≠ test bench. Hence the test-city repo.

These belong in `/home/li/Criopolis/_intake/operating-rules/` and
`_intake/li-canon.md` once the test-city repo confirms what's actually
happening.

---

*This report is a handoff. Codex: the test-city repo at
`github.com/LiGoldragon/test-city` is yours to extend. Phase 1 of the
diagnostic flow above is your most-useful first step.*
