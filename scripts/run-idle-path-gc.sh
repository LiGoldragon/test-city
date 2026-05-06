#!/usr/bin/env bash
set -euo pipefail

source_root="${TEST_CITY_SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"

gc_binary="$(command -v gc || true)"
if [ -z "$gc_binary" ]; then
  printf 'run-idle-path-gc: gc was not found on PATH\n' >&2
  exit 1
fi

gc_version_long="$(gc version --long 2>/dev/null || gc version 2>/dev/null || true)"
gc_commit="$(
  printf '%s\n' "$gc_version_long" \
    | sed -nE 's/.*commit: ([0-9a-f]+).*/\1/p' \
    | head -n 1
)"

export TEST_CITY_BINARY_LANE="${TEST_CITY_BINARY_LANE:-path-gc}"
export TEST_CITY_GASCITY_RELEASE="${TEST_CITY_GASCITY_RELEASE:-path-gc}"
export TEST_CITY_GASCITY_COMMIT="${TEST_CITY_GASCITY_COMMIT:-${gc_commit:-unknown}}"
export TEST_CITY_TEMPLATE="${TEST_CITY_TEMPLATE:-canonical-stock}"

exec bash "$source_root/scripts/run-idle-dolt-amp.sh" "$@"
