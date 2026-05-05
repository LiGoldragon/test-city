#!/usr/bin/env bash
set -euo pipefail

test_root="${1:-${TEST_CITY_ROOT:-}}"
if [ -z "$test_root" ]; then
  printf 'tear-down-test-city: pass a test root path or set TEST_CITY_ROOT\n' >&2
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
        printf 'tear-down-test-city: refusing to remove %s under production city: %s\n' "$label" "$path_real" >&2
        exit 1
        ;;
    esac
  done
  IFS="$old_ifs"
}

if [ ! -d "$test_root" ]; then
  printf 'tear-down-test-city: not a directory: %s\n' "$test_root" >&2
  exit 1
fi

assert_not_under_forbidden_city "test root" "$test_root"

if [ ! -f "$test_root/.test-city-root" ]; then
  printf 'tear-down-test-city: missing sentinel .test-city-root under %s\n' "$test_root" >&2
  exit 1
fi

chmod -R u+rwX "$test_root" 2>/dev/null || true
rm -rf "$test_root"
printf 'Removed test city root: %s\n' "$test_root"
