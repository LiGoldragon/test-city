#!/usr/bin/env bash
set -euo pipefail

source_root="${TEST_CITY_SOURCE_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

export TEST_CITY_TEMPLATE="${TEST_CITY_TEMPLATE:-expanded-inert}"
export TEST_CITY_EXPECT_ACTIVE_SESSIONS="${TEST_CITY_EXPECT_ACTIVE_SESSIONS:-4}"
export TEST_CITY_AFTER_HEALTH_SCRIPT="${TEST_CITY_AFTER_HEALTH_SCRIPT:-checks/lifecycle-churn.sh}"
export TEST_CITY_OBSERVATION_SECONDS="${TEST_CITY_OBSERVATION_SECONDS:-600}"
export TEST_CITY_HEALTH_TIMEOUT_SECONDS="${TEST_CITY_HEALTH_TIMEOUT_SECONDS:-120}"
export TEST_CITY_SAMPLE_INTERVAL_SECONDS="${TEST_CITY_SAMPLE_INTERVAL_SECONDS:-5}"

exec bash "$source_root/scripts/run-idle-path-gc.sh" "$@"
