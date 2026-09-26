# shellcheck shell=bash
# Shared test helpers. Tests never need a GPU, root access or network.
# shellcheck disable=SC2034

set -Eeuo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$TESTS_DIR/.." && pwd)
FIXTURES="$TESTS_DIR/fixtures"
PASS=0
FAIL=0

# shellcheck source=../lib/platform.sh
source "$ROOT_DIR/lib/platform.sh"
# shellcheck source=../lib/memory.sh
source "$ROOT_DIR/lib/memory.sh"
# shellcheck source=../lib/gpu.sh
source "$ROOT_DIR/lib/gpu.sh"
# shellcheck source=../lib/metrics.sh
source "$ROOT_DIR/lib/metrics.sh"
# shellcheck source=../lib/renderer.sh
source "$ROOT_DIR/lib/renderer.sh"
# shellcheck source=../lib/config.sh
source "$ROOT_DIR/lib/config.sh"

config_defaults
renderer_init 0
gpu_reset

fixture() {
    cat "$FIXTURES/$1"
}

# assert_eq EXPECTED ACTUAL DESCRIPTION
assert_eq() {
    if [ "$1" = "$2" ]; then
        PASS=$((PASS + 1))
        printf '  ok    %s\n' "$3"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$3" "$1" "$2"
    fi
}

# assert_contains HAYSTACK NEEDLE DESCRIPTION
assert_contains() {
    case "$1" in
        *"$2"*) assert_eq "$2" "$2" "$3" ;;
        *) assert_eq "*$2*" "$1" "$3" ;;
    esac
}

# assert_status EXPECTED_CODE DESCRIPTION COMMAND...
assert_status() {
    local expected="$1" description="$2" code=0
    shift 2
    "$@" >/dev/null 2>&1 || code=$?
    assert_eq "$expected" "$code" "$description"
}

finish() {
    printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
}
