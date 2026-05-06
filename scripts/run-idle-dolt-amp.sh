#!/usr/bin/env bash
set -euo pipefail

source_root="${TEST_CITY_SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
template="${1:-${TEST_CITY_TEMPLATE:-canonical-stock}}"
binary_lane="${TEST_CITY_BINARY_LANE:-unknown}"
observation_seconds="${TEST_CITY_OBSERVATION_SECONDS:-300}"
health_timeout_seconds="${TEST_CITY_HEALTH_TIMEOUT_SECONDS:-60}"
sample_interval_seconds="${TEST_CITY_SAMPLE_INTERVAL_SECONDS:-5}"
city_name="${TEST_CITY_CITY_NAME:-test-$template}"
expected_active_sessions="${TEST_CITY_EXPECT_ACTIVE_SESSIONS:-0}"
after_health_script="${TEST_CITY_AFTER_HEALTH_SCRIPT:-}"

case "$observation_seconds:$health_timeout_seconds:$sample_interval_seconds:$expected_active_sessions" in
  *[!0-9:]* | *::* | :* | *:)
    printf 'run-idle-dolt-amp: timing values and expected session count must be integers\n' >&2
    exit 1
    ;;
esac
if [ "$observation_seconds" -lt 1 ] || [ "$health_timeout_seconds" -lt 1 ] || [ "$sample_interval_seconds" -lt 1 ]; then
  printf 'run-idle-dolt-amp: timing values must be positive integers\n' >&2
  exit 1
fi

canonical_path() {
  realpath -m "$1"
}

platform_home="$(
  getent passwd "$(id -u)" 2>/dev/null | awk -F: '{print $6}' || true
)"
real_home="${HOME:-$platform_home}"
if [ -n "$platform_home" ] && [ "$real_home" != "$platform_home" ]; then
  real_home="$platform_home"
fi

assert_not_under_forbidden_city() {
  local label="$1"
  local path="$2"
  local path_real
  path_real="$(canonical_path "$path")"

  local forbidden_roots
  forbidden_roots="${TEST_CITY_FORBIDDEN_ROOTS:-}:${ORCHESTRATOR_FORBIDDEN_CITY_ROOTS:-}:${GC_CITY_PATH:-}:${GC_CITY:-}:$real_home/Criopolis:/home/li/Criopolis"

  local old_ifs="$IFS"
  IFS=':'
  for forbidden_root in $forbidden_roots; do
    [ -n "$forbidden_root" ] || continue
    local forbidden_real
    forbidden_real="$(canonical_path "$forbidden_root")"
    case "$path_real" in
      "$forbidden_real" | "$forbidden_real"/*)
        printf 'run-idle-dolt-amp: refusing %s under production city: %s\n' "$label" "$path_real" >&2
        exit 1
        ;;
    esac
  done
  IFS="$old_ifs"
}

if [ -n "${TEST_CITY_ROOT:-}" ]; then
  test_root="$TEST_CITY_ROOT"
  if [ -e "$test_root" ] && [ -n "$(find "$test_root" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    printf 'run-idle-dolt-amp: TEST_CITY_ROOT is not empty: %s\n' "$test_root" >&2
    exit 1
  fi
else
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/test-city.XXXXXX")"
fi
export TEST_CITY_ROOT="$test_root"

assert_not_under_forbidden_city "test root" "$test_root"

prepare_stdout="$(mktemp "${TMPDIR:-/tmp}/test-city-prepare.stdout.XXXXXX")"
prepare_stderr="$(mktemp "${TMPDIR:-/tmp}/test-city-prepare.stderr.XXXXXX")"
if ! TEST_CITY_ROOT="$test_root" TEST_CITY_TEMPLATE="$template" TEST_CITY_SOURCE_ROOT="$source_root" \
  bash "$source_root/scripts/prepare-test-city.sh" "$template" >"$prepare_stdout" 2>"$prepare_stderr"; then
  cat "$prepare_stdout" >&2 || true
  cat "$prepare_stderr" >&2 || true
  rm -f "$prepare_stdout" "$prepare_stderr"
  exit 1
fi

mkdir -p "$test_root"
cp "$prepare_stdout" "$test_root/prepare.stdout"
cp "$prepare_stderr" "$test_root/prepare.stderr"
rm -f "$prepare_stdout" "$prepare_stderr"

gc_home="$test_root/gc-home"
runtime_dir="$test_root/runtime"
temporary_dir="$test_root/tmp"
bin_dir="$test_root/bin"
artifacts_dir="$test_root/artifacts"
prepared_city="$test_root/city"
initialized_city="$test_root/initialized-city"
git_config_global="$gc_home/gitconfig"
supervisor_pid=""
result_written=0
start_time="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

assert_not_under_forbidden_city "prepared city" "$prepared_city"
assert_not_under_forbidden_city "initialized city" "$initialized_city"

mkdir -p "$gc_home" "$runtime_dir" "$temporary_dir" "$bin_dir" "$artifacts_dir"

run_isolated() {
  env -i \
    PATH="$bin_dir:$PATH" \
    HOME="$real_home" \
    USER="${USER:-nixbld}" \
    LOGNAME="${LOGNAME:-nixbld}" \
    SHELL="${SHELL:-/bin/sh}" \
    LANG="${LANG:-C.UTF-8}" \
    TMPDIR="$temporary_dir" \
    GC_HOME="$gc_home" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    DOLT_ROOT_PATH="$gc_home" \
    GIT_CONFIG_GLOBAL="$git_config_global" \
    GC_BD_TRACE="$artifacts_dir/bd-trace.log" \
    GC_LSOF_TIMEOUT_SECONDS=1 \
    BEADS_DOLT_AUTO_START=0 \
    "$@"
}

write_result() {
  local status="$1"
  local reason="${2:-}"
  local ended_at
  ended_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  result_written=1
  jq -n \
    --arg status "$status" \
    --arg reason "$reason" \
    --arg started_at "$start_time" \
    --arg ended_at "$ended_at" \
    --arg template "$template" \
    --arg binary_lane "$binary_lane" \
    --arg test_root "$(canonical_path "$test_root")" \
    --arg prepared_city "$(canonical_path "$prepared_city")" \
    --arg initialized_city "$(canonical_path "$initialized_city")" \
    --arg gc_binary "$(command -v gc || true)" \
    --arg gc_version "$(gc version 2>/dev/null | head -n 1 || true)" \
    --arg after_health_script "$after_health_script" \
    --argjson observation_seconds "$observation_seconds" \
    --argjson health_timeout_seconds "$health_timeout_seconds" \
    --argjson sample_interval_seconds "$sample_interval_seconds" \
    --argjson expected_active_sessions "$expected_active_sessions" \
    '{
      status: $status,
      reason: $reason,
      started_at: $started_at,
      ended_at: $ended_at,
      template: $template,
      binary_lane: $binary_lane,
      test_root: $test_root,
      prepared_city: $prepared_city,
      initialized_city: $initialized_city,
      gascity: {
        binary: $gc_binary,
        version: $gc_version
      },
      action: {
        after_health_script: $after_health_script
      },
      timing: {
        observation_seconds: $observation_seconds,
        health_timeout_seconds: $health_timeout_seconds,
        sample_interval_seconds: $sample_interval_seconds,
        expected_active_sessions: $expected_active_sessions
      }
    }' >"$artifacts_dir/result.json"
}

cleanup() {
  local status=$?
  set +e
  if [ -n "$supervisor_pid" ]; then
    run_isolated gc supervisor stop --wait >"$test_root/supervisor-stop.stdout" 2>"$test_root/supervisor-stop.stderr"
    wait "$supervisor_pid" >/dev/null 2>&1
  fi
  stop_test_root_processes >>"$test_root/cleanup-processes.log" 2>&1
  if [ "$result_written" -eq 0 ]; then
    if [ "$status" -eq 0 ]; then
      write_result "completed" "script exited without explicit result"
    else
      write_result "setup-failed" "script exited with status $status"
    fi
  fi
  if [ "${KEEP_TEST_ROOT:-0}" = "1" ]; then
    printf 'run-idle-dolt-amp: kept test root %s\n' "$test_root" >&2
  else
    chmod -R u+rwX "$test_root" 2>/dev/null || true
    rm -rf "$test_root"
  fi
  exit "$status"
}
trap cleanup EXIT

stop_test_root_processes() {
  local pids
  mapfile -t pids < <(
    ps -eo pid=,args= \
      | awk -v root="$test_root" '$1 != "" && index($0, root) > 0 {print $1}' \
      | sort -u
  )
  if [ "${#pids[@]}" -eq 0 ]; then
    return 0
  fi

  printf 'stopping test-root processes: %s\n' "${pids[*]}"
  kill "${pids[@]}" 2>/dev/null || true
  sleep 1

  mapfile -t pids < <(
    ps -eo pid=,args= \
      | awk -v root="$test_root" '$1 != "" && index($0, root) > 0 {print $1}' \
      | sort -u
  )
  if [ "${#pids[@]}" -gt 0 ]; then
    printf 'force-stopping test-root processes: %s\n' "${pids[*]}"
    kill -9 "${pids[@]}" 2>/dev/null || true
  fi
}

fail_setup() {
  local reason="$1"
  printf 'run-idle-dolt-amp: setup failed: %s\n' "$reason" >&2
  write_result "setup-failed" "$reason"
  exit 1
}

install_host_command_shims() {
  local sh_path
  sh_path="$(command -v sh)"
  for command_name in systemctl launchctl; do
    {
      printf '#!%s\n' "$sh_path"
      printf 'exit 0\n'
    } >"$bin_dir/$command_name"
    chmod +x "$bin_dir/$command_name"
  done
}

seed_dolt_identity() {
  mkdir -p "$gc_home/.dolt"
  touch "$git_config_global"
  git config --file "$git_config_global" user.name gc-test
  git config --file "$git_config_global" user.email gc-test@test.local
  git config --file "$git_config_global" beads.role maintainer
  printf '{"user.name":"gc-test","user.email":"gc-test@test.local"}\n' >"$gc_home/.dolt/config_global.json"
}

seed_supervisor_config() {
  local port
  port="$(shuf -i 24000-42000 -n 1)"
  cat >"$gc_home/supervisor.toml" <<EOF
[supervisor]
bind = "127.0.0.1"
port = $port
EOF
  printf 'SUPERVISOR_PORT=%s\n' "$port" >"$test_root/run-isolated.env"
}

wait_for_supervisor() {
  local deadline=$((SECONDS + 30))
  until run_isolated gc supervisor status >"$test_root/supervisor-status.stdout" 2>"$test_root/supervisor-status.stderr" \
    && grep -qi 'running' "$test_root/supervisor-status.stdout"; do
    if ! kill -0 "$supervisor_pid" 2>/dev/null; then
      sed -n '1,220p' "$test_root/supervisor.log" >&2 || true
      return 1
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      sed -n '1,120p' "$test_root/supervisor-status.stdout" >&2 || true
      sed -n '1,120p' "$test_root/supervisor-status.stderr" >&2 || true
      sed -n '1,220p' "$test_root/supervisor.log" >&2 || true
      return 1
    fi
    sleep 0.2
  done
}

capture_setup_diagnostics() {
  cp "$initialized_city/.beads/config.yaml" "$artifacts_dir/beads-config.yaml" 2>/dev/null || true
  cp "$initialized_city/.beads/metadata.json" "$artifacts_dir/beads-metadata.json" 2>/dev/null || true
  run_isolated gc --city "$initialized_city" bd config list \
    >"$artifacts_dir/bd-config-list.stdout" 2>"$artifacts_dir/bd-config-list.stderr" || true
  run_isolated gc --city "$initialized_city" bd config get issue_prefix \
    >"$artifacts_dir/bd-config-get-issue-prefix.stdout" 2>"$artifacts_dir/bd-config-get-issue-prefix.stderr" || true
  capture_dolt_config_table
}

capture_dolt_config_table() {
  local metadata_path="$initialized_city/.beads/metadata.json"
  local dolt_database="hq"
  local state_path="$initialized_city/.gc/runtime/packs/dolt/dolt-provider-state.json"
  local dolt_port=""

  if [ -f "$metadata_path" ]; then
    dolt_database="$(jq -r '.dolt_database // "hq"' "$metadata_path" 2>/dev/null || printf 'hq')"
  fi
  if [ -f "$state_path" ]; then
    dolt_port="$(jq -r '.port // empty' "$state_path" 2>/dev/null || true)"
  fi

  if [ -n "$dolt_port" ]; then
    dolt --host 127.0.0.1 --port "$dolt_port" --user root --password "" --no-tls \
      sql -q "use \`$dolt_database\`; select * from config order by 1" \
      >"$artifacts_dir/dolt-config-table.server.stdout" \
      2>"$artifacts_dir/dolt-config-table.server.stderr" || true
  fi

  if [ -d "$initialized_city/.beads/dolt/$dolt_database" ]; then
    (
      cd "$initialized_city/.beads/dolt/$dolt_database"
      dolt sql -q "select * from config order by 1"
    ) >"$artifacts_dir/dolt-config-table.local.stdout" \
      2>"$artifacts_dir/dolt-config-table.local.stderr" || true
  fi
}

wait_for_session_health() {
  local deadline=$((SECONDS + health_timeout_seconds))
  local session_path="$artifacts_dir/session-list.health.json"
  local session_stderr="$artifacts_dir/session-list.health.stderr"
  until run_isolated gc --city "$initialized_city" session list --state all --json >"$session_path" 2>"$session_stderr" \
    && jq -e --argjson expected "$expected_active_sessions" '
      type == "array" and (
        if $expected > 0 then
          ([.[] | select(((.State // .state // "") == "active") and (((.Closed // .closed // false) | not))) ] | length) >= $expected
        else
          length > 0
        end
      )
    ' "$session_path" >/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      return 1
    fi
    sleep 1
  done
}

run_after_health_script() {
  [ -n "$after_health_script" ] || return 0

  local script_path="$after_health_script"
  if [ "${script_path#/}" = "$script_path" ]; then
    if [ -f "$initialized_city/$script_path" ]; then
      script_path="$initialized_city/$script_path"
    else
      script_path="$source_root/$script_path"
    fi
  fi
  if [ ! -f "$script_path" ]; then
    printf 'run-idle-dolt-amp: after-health script not found: %s\n' "$script_path" >&2
    return 1
  fi

  run_isolated env \
    TEST_CITY_ROOT="$test_root" \
    TEST_CITY_INITIALIZED_CITY="$initialized_city" \
    TEST_CITY_ARTIFACTS_DIR="$artifacts_dir" \
    TEST_CITY_AFTER_HEALTH_SCRIPT="$script_path" \
    bash "$script_path" \
    >"$artifacts_dir/after-health.stdout" \
    2>"$artifacts_dir/after-health.stderr"
}

read_dolt_port() {
  local state_file="$initialized_city/.gc/runtime/packs/dolt/dolt-provider-state.json"
  [ -f "$state_file" ] || return 0
  jq -r '.port // empty' "$state_file" 2>/dev/null || true
}

read_dolt_database() {
  local metadata_file="$initialized_city/.beads/metadata.json"
  if [ -f "$metadata_file" ]; then
    jq -r '.dolt_database // "hq"' "$metadata_file" 2>/dev/null || printf 'hq'
    return 0
  fi
  printf 'hq'
}

valid_dolt_database_name() {
  case "$1" in
    "" | *[!A-Za-z0-9_-]*)
      return 1
      ;;
  esac
}

query_dolt_csv_value() {
  local port="$1"
  local database="$2"
  local query="$3"
  dolt --host 127.0.0.1 --port "$port" --user root --password "" --no-tls \
    sql -r csv -q "use \`$database\`; $query" 2>/dev/null \
    | awk 'NR == 2 {print; exit}'
}

sample_dolt_sql() {
  local timestamp="$1"
  local port="$2"
  local database
  local commit_count=""
  local working_changes=""
  local issue_prefix=""
  local processlist_tmp="$artifacts_dir/dolt-processlist.current.csv"

  database="$(read_dolt_database)"
  valid_dolt_database_name "$database" || return 0

  commit_count="$(query_dolt_csv_value "$port" "$database" "select count(*) as commit_count from dolt_log" || true)"
  working_changes="$(query_dolt_csv_value "$port" "$database" "select count(*) as working_changes from dolt_status" || true)"
  issue_prefix="$(query_dolt_csv_value "$port" "$database" "select value from config where \`key\` = 'issue_prefix'" || true)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$timestamp" "$port" "$database" "$commit_count" "$working_changes" "$issue_prefix" \
    >>"$artifacts_dir/dolt-metrics.tsv"

  if dolt --host 127.0.0.1 --port "$port" --user root --password "" --no-tls \
    sql -r csv -q "show processlist" >"$processlist_tmp" 2>>"$artifacts_dir/dolt-processlist.stderr"; then
    awk -v ts="$timestamp" -v port="$port" 'NR > 1 {print ts "\t" port "\t" $0}' "$processlist_tmp" \
      >>"$artifacts_dir/dolt-processlist.tsv"
  fi
}

sample_once() {
  local timestamp="$1"
  local event_lines=0
  local warning_count=0
  local dolt_port=""
  local session_tmp="$artifacts_dir/session-current.json"

  ps -eo pid=,ppid=,pcpu=,pmem=,etime=,args= \
    | awk -v ts="$timestamp" -v root="$test_root" -v supervisor="$supervisor_pid" \
      '$1 == supervisor || index($0, root) > 0 {print ts "\t" $0}' >>"$artifacts_dir/process-samples.tsv"

  if [ -f "$initialized_city/.gc/events.jsonl" ]; then
    event_lines="$(wc -l <"$initialized_city/.gc/events.jsonl" | tr -d ' ')"
  fi
  if [ -d "$initialized_city" ]; then
    warning_count="$(
      find "$initialized_city" -type f -name 'dolt.log' -print0 2>/dev/null \
        | xargs -0 grep -h 'nothing to commit' 2>/dev/null \
        | wc -l \
        | tr -d ' '
    )"
  fi
  printf '%s\t%s\t%s\n' "$timestamp" "$event_lines" "$warning_count" >>"$artifacts_dir/event-samples.tsv"

  for path in "$initialized_city/.beads" "$initialized_city/.gc" "$gc_home"; do
    if [ -e "$path" ]; then
      bytes="$(du -sb "$path" 2>/dev/null | awk '{print $1}')"
      printf '%s\t%s\t%s\n' "$timestamp" "$path" "$bytes" >>"$artifacts_dir/size-samples.tsv"
    fi
  done

  dolt_port="$(read_dolt_port)"
  if [ -n "$dolt_port" ]; then
    lsof -nP -iTCP:"$dolt_port" 2>/dev/null \
      | awk -v ts="$timestamp" -v port="$dolt_port" 'NR > 1 {print ts "\t" port "\t" $0}' \
      >>"$artifacts_dir/connection-samples.tsv" || true
    sample_dolt_sql "$timestamp" "$dolt_port"
  fi

  if run_isolated gc --city "$initialized_city" session list --state all --json >"$session_tmp" 2>>"$artifacts_dir/session-samples.stderr"; then
    jq -c --arg timestamp "$timestamp" '{timestamp: $timestamp, sessions: .}' "$session_tmp" \
      >>"$artifacts_dir/session-samples.jsonl" || true
  fi
}

write_headers() {
  printf 'timestamp\tpid\tppid\tpcpu\tpmem\tetime\targs\n' >"$artifacts_dir/process-samples.tsv"
  printf 'timestamp\tevents_lines\tdolt_log_warnings\n' >"$artifacts_dir/event-samples.tsv"
  printf 'timestamp\tpath\tbytes\n' >"$artifacts_dir/size-samples.tsv"
  printf 'timestamp\tport\tlsof_line\n' >"$artifacts_dir/connection-samples.tsv"
  printf 'timestamp\tport\tdatabase\tcommit_count\tworking_changes\tissue_prefix\n' >"$artifacts_dir/dolt-metrics.tsv"
  printf 'timestamp\tport\tprocesslist_csv_line\n' >"$artifacts_dir/dolt-processlist.tsv"
  : >"$artifacts_dir/dolt-processlist.stderr"
  : >"$artifacts_dir/session-samples.jsonl"
  : >"$artifacts_dir/session-samples.stderr"
}

install_host_command_shims
seed_dolt_identity
seed_supervisor_config

{
  printf 'TEST_CITY_ROOT=%s\n' "$test_root"
  printf 'TEST_CITY_TEMPLATE=%s\n' "$template"
  printf 'TEST_CITY_BINARY_LANE=%s\n' "$binary_lane"
  printf 'TEST_CITY_EXPECT_ACTIVE_SESSIONS=%s\n' "$expected_active_sessions"
  printf 'TEST_CITY_AFTER_HEALTH_SCRIPT=%s\n' "$after_health_script"
  printf 'GC_HOME=%s\n' "$gc_home"
  printf 'XDG_RUNTIME_DIR=%s\n' "$runtime_dir"
  printf 'TMPDIR=%s\n' "$temporary_dir"
  printf 'HOME=%s\n' "$real_home"
  printf 'DOLT_ROOT_PATH=%s\n' "$gc_home"
  printf 'GIT_CONFIG_GLOBAL=%s\n' "$git_config_global"
} >>"$test_root/run-isolated.env"

(run_isolated gc supervisor run) >"$test_root/supervisor.log" 2>&1 &
supervisor_pid="$!"
wait_for_supervisor || fail_setup "isolated supervisor did not become ready"

if ! run_isolated gc init --from "$prepared_city" --name "$city_name" "$initialized_city" \
  >"$test_root/gc-init.stdout" 2>"$test_root/gc-init.stderr"; then
  capture_setup_diagnostics
  fail_setup "gc init failed"
fi

run_isolated gc --city "$initialized_city" session list --state all --json \
  >"$artifacts_dir/session-list.initial.json" 2>"$artifacts_dir/session-list.initial.stderr" || true

if ! wait_for_session_health; then
  capture_setup_diagnostics
  fail_setup "session health gate failed: no sessions became visible"
fi

if ! run_after_health_script; then
  capture_setup_diagnostics
  fail_setup "after-health script failed"
fi

write_headers
end_time=$((SECONDS + observation_seconds))
while [ "$SECONDS" -le "$end_time" ]; do
  sample_once "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if [ "$SECONDS" -ge "$end_time" ]; then
    break
  fi
  sleep "$sample_interval_seconds"
done

run_isolated gc --city "$initialized_city" session list --state all --json \
  >"$artifacts_dir/session-list.final.json" 2>"$artifacts_dir/session-list.final.stderr" || true
capture_dolt_config_table
find "$initialized_city" -maxdepth 6 -type f | sort >"$artifacts_dir/initialized-files.txt"

write_result "observed" "observation completed"
printf 'run-idle-dolt-amp: completed test root: %s\n' "$test_root"
