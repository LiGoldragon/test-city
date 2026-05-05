#!/usr/bin/env bash
set -euo pipefail

source_root="${TEST_CITY_SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
export TEST_CITY_BINARY_LANE="${TEST_CITY_BINARY_LANE:-source-built}"

exec bash "$source_root/scripts/run-idle-dolt-amp.sh" "$@"
