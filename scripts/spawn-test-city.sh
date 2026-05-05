#!/usr/bin/env bash
# Skeleton spawn-test-city script. Mayor (Claude) authored as a starting
# point; codex is expected to extend this with real diagnostic capture +
# scenario logic. The orchestrator's `tests/scripts/orchestrator-isolated-gc-test.sh`
# is a more polished reference for the same shape.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# ---------------------------------------------------------------------------
# Args + env
# ---------------------------------------------------------------------------

template="${1:-canonical-stock}"
template_dir="$repo_root/templates/$template"

if [ ! -d "$template_dir" ]; then
  printf 'spawn-test-city: unknown template %s (under %s)\n' \
    "$template" "$repo_root/templates" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Workspace boundary — refuse to start inside a real city
# ---------------------------------------------------------------------------

canonical_path() {
  python3 - "$1" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
}

real_home="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"

assert_not_under_forbidden_city() {
  local label="$1"
  local path="$2"
  local path_real
  path_real="$(canonical_path "$path")"

  local forbidden_roots
  forbidden_roots="${TEST_CITY_FORBIDDEN_ROOTS:-${GC_CITY_PATH:-}:${GC_CITY:-}:$real_home/Criopolis:/home/li/Criopolis}"

  local IFS=':'
  for forbidden_root in $forbidden_roots; do
    [ -n "$forbidden_root" ] || continue
    local forbidden_real
    forbidden_real="$(canonical_path "$forbidden_root")"
    case "$path_real" in
      "$forbidden_real" | "$forbidden_real"/*)
        printf 'spawn-test-city: refusing %s under production city: %s\n' \
          "$label" "$path_real" >&2
        exit 1
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Test root
# ---------------------------------------------------------------------------

if [ -n "${TEST_CITY_ROOT:-}" ]; then
  test_root="$TEST_CITY_ROOT"
  if [ -e "$test_root" ] && [ -n "$(find "$test_root" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    printf 'spawn-test-city: TEST_CITY_ROOT is not empty: %s\n' "$test_root" >&2
    exit 1
  fi
  mkdir -p "$test_root"
else
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/test-city.XXXXXX")"
fi

assert_not_under_forbidden_city "test root" "$test_root"
city_dir="$test_root/city"
mkdir -p "$city_dir"

printf 'spawn-test-city: template=%s root=%s\n' "$template" "$test_root"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

cleanup() {
  set +e
  if [ "${KEEP_TEST_ROOT:-}" = "1" ]; then
    printf 'spawn-test-city: kept test root %s\n' "$test_root" >&2
    return
  fi
  # NOTE: codex should add `gc supervisor stop --wait` + supervisor PID kill
  # here once the harness actually starts a supervisor. Today this is a
  # filesystem-only cleanup.
  rm -rf "$test_root"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Stub: copy template city + pack toml into the city dir
# ---------------------------------------------------------------------------

if [ -f "$template_dir/city.toml" ]; then
  cp "$template_dir/city.toml" "$city_dir/city.toml"
fi
if [ -f "$template_dir/pack.toml" ]; then
  cp "$template_dir/pack.toml" "$city_dir/pack.toml"
fi

# ---------------------------------------------------------------------------
# TODO (codex)
# ---------------------------------------------------------------------------

# 1. Run `gc init` in $city_dir if needed (or rely on copied configs).
# 2. Start the supervisor for this isolated city — see how the orchestrator
#    repo seeds supervisor.toml + GC_HOME, and how it kills the supervisor
#    in cleanup.
# 3. `gc start` the test city.
# 4. Wait for mayor + control-dispatcher (or whatever always-on agents are
#    declared) to reach state=active.
# 5. Capture the diagnostic baseline:
#    - `du -sh "$city_dir/.beads/dolt"`
#    - `wc -l "$city_dir/.gc/events.jsonl"`
#    - sample `dolt sql -q "SHOW PROCESSLIST"` every N seconds for the test
#      window
#    - sample top dolt CPU
#    - capture supervisor logs filtered to non-noise
# 6. Run scenario-specific actions (sling beads, etc.).
# 7. Capture the post-window diagnostic and emit a structured report
#    (JSON or TSV) under $city_dir/test-report/.
# 8. Optionally: `cp $city_dir/test-report/* $repo_root/last-report/` for
#    quick inspection.

printf 'spawn-test-city: scaffold reached the TODO marker — codex to fill in\n' >&2
printf 'spawn-test-city: city_dir=%s\n' "$city_dir"

# Placeholder exit so the scaffold can be invoked without doing harm.
exit 0
