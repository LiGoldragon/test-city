#!/usr/bin/env bash
set -euo pipefail

city="${TEST_CITY_INITIALIZED_CITY:?TEST_CITY_INITIALIZED_CITY is required}"
artifacts="${TEST_CITY_ARTIFACTS_DIR:?TEST_CITY_ARTIFACTS_DIR is required}"
session_starts="$city/test-artifacts/session-starts.tsv"
log="$artifacts/lifecycle-churn.tsv"

toml_name_from() {
  local file="$1"
  awk -F ' *= *' '
    $1 == "name" {
      gsub(/"/, "", $2)
      print $2
      exit
    }
  ' "$file"
}

workspace_name="${TEST_CITY_TMUX_SOCKET:-$(toml_name_from "$city/city.toml")}"
if [ -z "$workspace_name" ]; then
  workspace_name="$(toml_name_from "$city/pack.toml")"
fi
if [ -z "$workspace_name" ]; then
  printf 'lifecycle-churn: could not resolve tmux socket name\n' >&2
  exit 1
fi

printf 'timestamp\taction\tdetail\n' >"$log"

record() {
  local action="$1"
  local detail="$2"
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$action" "$detail" >>"$log"
}

session_json_path() {
  local label="$1"
  printf '%s/session-list.lifecycle-%s.json' "$artifacts" "$label"
}

snapshot_sessions() {
  local label="$1"
  gc --city "$city" session list --state all --json \
    >"$(session_json_path "$label")" \
    2>"$artifacts/session-list.lifecycle-${label}.stderr"
}

wait_alias_state() {
  local alias="$1"
  local template="$2"
  local state="$3"
  local label="$4"
  local deadline=$((SECONDS + 120))
  local json
  json="$(session_json_path "$label")"

  until snapshot_sessions "$label" \
    && jq -e \
      --arg alias "$alias" \
      --arg template "$template" \
      --arg state "$state" \
      '[.[] | select(
        ((.Alias // .alias // "") == $alias) and
        ((.Template // .template // "") == $template) and
        ((.State // .state // "") == $state) and
        (((.Closed // .closed // false) | not))
      )] | length == 1' \
      "$json" >/dev/null
  do
    if [ "$SECONDS" -ge "$deadline" ]; then
      record "wait-$label" "timeout waiting for $alias/$template state $state"
      jq -r '.[] | [.ID, .Alias, .Template, .State, .Closed] | @tsv' "$json" >&2 || true
      return 1
    fi
    sleep 1
  done

  record "wait-$label" "$alias/$template state $state"
}

wait_no_nonclosed_alias() {
  local alias="$1"
  local template="$2"
  local label="$3"
  local deadline=$((SECONDS + 120))
  local json
  json="$(session_json_path "$label")"

  until snapshot_sessions "$label" \
    && jq -e \
      --arg alias "$alias" \
      --arg template "$template" \
      '[.[] | select(
        ((.Alias // .alias // "") == $alias) and
        ((.Template // .template // "") == $template) and
        (((.Closed // .closed // false) | not))
      )] | length == 0' \
      "$json" >/dev/null
  do
    if [ "$SECONDS" -ge "$deadline" ]; then
      record "wait-$label" "timeout waiting for no non-closed $alias/$template"
      jq -r '.[] | [.ID, .Alias, .Template, .State, .Closed] | @tsv' "$json" >&2 || true
      return 1
    fi
    sleep 1
  done

  record "wait-$label" "no non-closed $alias/$template"
}

active_session_id() {
  local alias="$1"
  local template="$2"
  local label="$3"
  local json
  json="$(session_json_path "$label")"

  snapshot_sessions "$label"
  jq -r \
    --arg alias "$alias" \
    --arg template "$template" \
    '.[] | select(
      ((.Alias // .alias // "") == $alias) and
      ((.Template // .template // "") == $template) and
      ((.State // .state // "") == "active") and
      (((.Closed // .closed // false) | not))
    ) | (.ID // .id)' \
    "$json" | head -n 1
}

count_starts_for_alias() {
  local alias="$1"
  awk -F '\t' -v alias="$alias" '$2 == alias { count++ } END { print count + 0 }' "$session_starts"
}

run_gc() {
  local label="$1"
  shift

  record "$label" "start: gc $*"
  if gc --city "$city" "$@" \
    >"$artifacts/lifecycle-${label}.stdout" \
    2>"$artifacts/lifecycle-${label}.stderr"
  then
    record "$label" "ok"
  else
    record "$label" "failed"
    sed -n '1,80p' "$artifacts/lifecycle-${label}.stderr" >&2 || true
    return 1
  fi
}

assert_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [ "$expected" != "$actual" ]; then
    record "$label" "expected $expected, got $actual"
    printf '%s: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
    return 1
  fi

  record "$label" "ok: $actual"
}

assert_not_equal() {
  local label="$1"
  local left="$2"
  local right="$3"

  if [ "$left" = "$right" ]; then
    record "$label" "unexpected equal value $left"
    printf '%s: unexpected equal value %s\n' "$label" "$left" >&2
    return 1
  fi

  record "$label" "ok: $left != $right"
}

wait_worker_restart() {
  local alias="$1"
  local before="$2"
  local deadline=$((SECONDS + 120))
  local current

  until current="$(count_starts_for_alias "$alias")" && [ "$current" -gt "$before" ]; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      record "wait-${alias}-restart" "timeout; before=$before current=$current"
      return 1
    fi
    sleep 1
  done

  record "wait-${alias}-restart" "before=$before current=$current"
}

wait_tmux_session_absent() {
  local session_name="$1"
  local label="$2"
  local deadline=$((SECONDS + 120))

  while tmux -L "$workspace_name" has-session -t "$session_name" >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      record "wait-$label" "timeout waiting for tmux session $session_name to stop"
      tmux -L "$workspace_name" list-sessions >&2 || true
      return 1
    fi
    sleep 1
  done

  record "wait-$label" "tmux session $session_name absent"
}

wait_tmux_session_present() {
  local session_name="$1"
  local label="$2"
  local deadline=$((SECONDS + 120))

  until tmux -L "$workspace_name" has-session -t "$session_name" >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      record "wait-$label" "timeout waiting for tmux session $session_name to start"
      tmux -L "$workspace_name" list-sessions >&2 || true
      return 1
    fi
    sleep 1
  done

  record "wait-$label" "tmux session $session_name present"
}

cycles="${TEST_CITY_LIFECYCLE_CHURN_CYCLES:-1}"
worker_kills="${TEST_CITY_LIFECYCLE_CHURN_WORKER_KILLS:-$cycles}"
case "$cycles:$worker_kills" in
  *[!0-9:]* | *::* | :* | *:)
    printf 'lifecycle-churn: cycle counts must be non-negative integers\n' >&2
    exit 1
    ;;
esac
if [ "$cycles" -lt 1 ]; then
  printf 'lifecycle-churn: TEST_CITY_LIFECYCLE_CHURN_CYCLES must be at least 1\n' >&2
  exit 1
fi
if [ "$worker_kills" -gt "$cycles" ]; then
  printf 'lifecycle-churn: TEST_CITY_LIFECYCLE_CHURN_WORKER_KILLS cannot exceed cycles\n' >&2
  exit 1
fi

snapshot_sessions baseline
run_gc wake-auditor-initial session wake auditor
wait_alias_state auditor auditor active auditor-initial-active
wait_tmux_session_present auditor auditor-initial-runtime-started
auditor_current_id="$(active_session_id auditor auditor auditor-initial-id)"
record "auditor-initial-id" "$auditor_current_id"

cycle=1
while [ "$cycle" -le "$cycles" ]; do
  prefix="cycle-${cycle}"

  run_gc "${prefix}-suspend-auditor" session suspend auditor
  wait_alias_state auditor auditor suspended "${prefix}-auditor-suspended"
  wait_tmux_session_absent auditor "${prefix}-auditor-suspended-runtime-stopped"

  run_gc "${prefix}-wake-auditor-after-suspend" session wake auditor
  wait_alias_state auditor auditor active "${prefix}-auditor-after-suspend-active"
  wait_tmux_session_present auditor "${prefix}-auditor-after-suspend-runtime-started"
  auditor_after_suspend_id="$(active_session_id auditor auditor "${prefix}-auditor-after-suspend-id")"
  assert_equal "${prefix}-auditor-suspend-wake-preserves-id" "$auditor_current_id" "$auditor_after_suspend_id"

  run_gc "${prefix}-close-auditor" session close auditor
  wait_no_nonclosed_alias auditor auditor "${prefix}-auditor-closed"
  wait_tmux_session_absent auditor "${prefix}-auditor-closed-runtime-stopped"

  run_gc "${prefix}-wake-auditor-after-close" session wake auditor
  wait_alias_state auditor auditor active "${prefix}-auditor-after-close-active"
  wait_tmux_session_present auditor "${prefix}-auditor-after-close-runtime-started"
  auditor_after_close_id="$(active_session_id auditor auditor "${prefix}-auditor-after-close-id")"
  assert_not_equal "${prefix}-auditor-close-wake-replaces-id" "$auditor_current_id" "$auditor_after_close_id"
  auditor_current_id="$auditor_after_close_id"

  if [ "$cycle" -le "$worker_kills" ]; then
    worker_alias="worker-$(( ((cycle - 1) % 2) + 1 ))"
    worker_starts_before="$(count_starts_for_alias "$worker_alias")"
    run_gc "${prefix}-kill-${worker_alias}" session kill "$worker_alias"
    wait_worker_restart "$worker_alias" "$worker_starts_before"
    wait_alias_state "$worker_alias" worker active "${prefix}-${worker_alias}-after-kill-active"
  fi

  cycle=$((cycle + 1))
done

expected_starts=$((4 + 1 + (cycles * 2) + worker_kills))
total_starts="$(wc -l <"$session_starts")"
assert_equal "session-start-count-after-churn" "$expected_starts" "$total_starts"
snapshot_sessions final
record "lifecycle-churn" "complete cycles=$cycles worker_kills=$worker_kills"
printf 'lifecycle-churn: complete\n'
