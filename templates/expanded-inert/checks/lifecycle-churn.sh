#!/usr/bin/env bash
set -euo pipefail

city="${TEST_CITY_INITIALIZED_CITY:?TEST_CITY_INITIALIZED_CITY is required}"
artifacts="${TEST_CITY_ARTIFACTS_DIR:?TEST_CITY_ARTIFACTS_DIR is required}"
session_starts="$city/test-artifacts/session-starts.tsv"
log="$artifacts/lifecycle-churn.tsv"

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

snapshot_sessions baseline
run_gc wake-auditor-initial session wake auditor
wait_alias_state auditor auditor active auditor-initial-active
auditor_initial_id="$(active_session_id auditor auditor auditor-initial-id)"
record "auditor-initial-id" "$auditor_initial_id"

run_gc suspend-auditor session suspend auditor
wait_alias_state auditor auditor suspended auditor-suspended

run_gc wake-auditor-after-suspend session wake auditor
wait_alias_state auditor auditor active auditor-after-suspend-active
auditor_after_suspend_id="$(active_session_id auditor auditor auditor-after-suspend-id)"
assert_equal "auditor-suspend-wake-preserves-id" "$auditor_initial_id" "$auditor_after_suspend_id"

run_gc close-auditor session close auditor
wait_no_nonclosed_alias auditor auditor auditor-closed

run_gc wake-auditor-after-close session wake auditor
wait_alias_state auditor auditor active auditor-after-close-active
auditor_after_close_id="$(active_session_id auditor auditor auditor-after-close-id)"
assert_not_equal "auditor-close-wake-replaces-id" "$auditor_initial_id" "$auditor_after_close_id"

worker_1_starts_before="$(count_starts_for_alias worker-1)"
run_gc kill-worker-1 session kill worker-1
wait_worker_restart worker-1 "$worker_1_starts_before"
wait_alias_state worker-1 worker active worker-1-after-kill-active

total_starts="$(wc -l <"$session_starts")"
assert_equal "session-start-count-after-churn" "8" "$total_starts"
snapshot_sessions final
record "lifecycle-churn" "complete"
printf 'lifecycle-churn: complete\n'
