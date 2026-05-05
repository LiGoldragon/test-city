#!/usr/bin/env bash
set -euo pipefail

city_path="${GC_CITY_PATH:-${GC_CITY:-}}"
if [ -n "$city_path" ]; then
  mkdir -p "$city_path/test-artifacts"
  printf '%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${GC_AGENT:-mayor}" \
    >>"$city_path/test-artifacts/mayor-starts.tsv"
fi

exec tail -f /dev/null
