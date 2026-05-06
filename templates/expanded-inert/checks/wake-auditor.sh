#!/usr/bin/env bash
set -euo pipefail

city="${TEST_CITY_INITIALIZED_CITY:?}"
artifacts="${TEST_CITY_ARTIFACTS_DIR:?}"
deadline=$((SECONDS + 90))

gc --city "$city" session wake auditor \
  >"$artifacts/wake-auditor.stdout" \
  2>"$artifacts/wake-auditor.stderr"

until gc --city "$city" session list --state all --json \
  >"$artifacts/session-list.after-wake.json" \
  2>"$artifacts/session-list.after-wake.stderr" \
  && jq -e '
    [.[] | select(
      (.Alias // .alias // "") == "auditor"
      and (.Template // .template // "") == "auditor"
      and (.State // .state // "") == "active"
      and (((.Closed // .closed // false) | not))
    )] | length == 1
  ' "$artifacts/session-list.after-wake.json" >/dev/null; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    printf 'wake-auditor: auditor did not become active before deadline\n' >&2
    exit 1
  fi
  sleep 1
done

printf 'wake-auditor: auditor active\n'
