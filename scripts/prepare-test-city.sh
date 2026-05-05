#!/usr/bin/env bash
set -euo pipefail

source_root="${TEST_CITY_SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
template="${1:-${TEST_CITY_TEMPLATE:-canonical-stock}}"
template_dir="$source_root/templates/$template"

if [ ! -d "$template_dir" ]; then
  printf 'prepare-test-city: unknown template %s under %s\n' "$template" "$source_root/templates" >&2
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
        printf 'prepare-test-city: refusing %s under production city: %s\n' "$label" "$path_real" >&2
        exit 1
        ;;
    esac
  done
  IFS="$old_ifs"
}

if [ -n "${TEST_CITY_ROOT:-}" ]; then
  test_root="$TEST_CITY_ROOT"
  if [ -e "$test_root" ] && [ -n "$(find "$test_root" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    printf 'prepare-test-city: TEST_CITY_ROOT is not empty: %s\n' "$test_root" >&2
    exit 1
  fi
  mkdir -p "$test_root"
else
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/test-city.XXXXXX")"
fi

assert_not_under_forbidden_city "test root" "$test_root"
city_dir="$test_root/city"
assert_not_under_forbidden_city "test city" "$city_dir"

mkdir -p "$city_dir"
cp -R "$template_dir"/. "$city_dir"/
chmod -R u+rwX "$city_dir"

created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
gc_binary="$(command -v gc || true)"
gc_version=""
if [ -n "$gc_binary" ]; then
  gc_version="$(gc version 2>/dev/null | head -n 1 || true)"
fi

manifest_path="$test_root/test-city.json"
jq -n \
  --arg created_at "$created_at" \
  --arg template "$template" \
  --arg test_root "$(canonical_path "$test_root")" \
  --arg city_dir "$(canonical_path "$city_dir")" \
  --arg source_root "$(canonical_path "$source_root")" \
  --arg gascity_release "${TEST_CITY_GASCITY_RELEASE:-unknown}" \
  --arg gascity_commit "${TEST_CITY_GASCITY_COMMIT:-unknown}" \
  --arg gc_binary "$gc_binary" \
  --arg gc_version "$gc_version" \
  '{
    created_at: $created_at,
    template: $template,
    test_root: $test_root,
    city_dir: $city_dir,
    source_root: $source_root,
    gascity: {
      release: $gascity_release,
      commit: $gascity_commit,
      binary: $gc_binary,
      version: $gc_version
    },
    state: "prepared",
    next: {
      initialize_city: ("gc init --from " + ($city_dir | @sh) + " " + (($test_root + "/initialized-city") | @sh)),
      tear_down: ("nix run .#tear-down -- " + ($test_root | @sh))
    }
  }' >"$manifest_path"

printf 'test-city\n' >"$test_root/.test-city-root"

printf 'Prepared test city root: %s\n' "$test_root"
printf 'City template copy: %s\n' "$city_dir"
printf 'Manifest: %s\n' "$manifest_path"
printf 'Tear down: nix run .#tear-down -- %q\n' "$test_root"
