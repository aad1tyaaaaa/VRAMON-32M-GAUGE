#!/usr/bin/env bash
# Configuration parsing, precedence and validation tests.
# shellcheck disable=SC2016,SC2030,SC2031,SC2317
# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "config file parsing"
cat >"$TMP_DIR/config" <<'EOF'
# comment line
VRAMON_INTERVAL=5
  VRAMON_WIDTH="30"
export VRAMON_WARN='40'
VRAMON_CRITICAL=15   # trailing comment

VRAMON_UNKNOWN=1
EOF
config_defaults
config_parse_file "$TMP_DIR/config" 2>/dev/null
assert_eq 5 "$VRAMON_INTERVAL" "plain value"
assert_eq 30 "$VRAMON_WIDTH" "double-quoted value, leading whitespace"
assert_eq 40 "$VRAMON_WARN" "export prefix, single-quoted value"
assert_eq 15 "$VRAMON_CRITICAL" "trailing comment stripped"
assert_eq 1 "$VRAMON_COLOR" "unset keys keep defaults"

echo "no code execution"
marker="$TMP_DIR/pwned"
printf 'VRAMON_WIDTH=$(touch %s)\n' "$marker" >"$TMP_DIR/evil"
config_parse_file "$TMP_DIR/evil"
assert_eq 0 "$([ -e "$marker" ] && echo 1 || echo 0)" "command substitution is not executed"
printf 'touch %s\n' "$marker" >"$TMP_DIR/malformed"
assert_status 4 "non-assignment line is rejected" config_parse_file "$TMP_DIR/malformed"
assert_eq 0 "$([ -e "$marker" ] && echo 1 || echo 0)" "rejected line is not executed"
assert_status 0 "missing config file is ignored" config_parse_file "$TMP_DIR/missing"

echo "precedence"
printf 'VRAMON_WIDTH=25\nVRAMON_WARN=35\n' >"$TMP_DIR/global"
printf 'VRAMON_WIDTH=15\n' >"$TMP_DIR/project"
(
    unset VRAMON_WIDTH VRAMON_WARN VRAMON_INTERVAL VRAMON_CRITICAL VRAMON_COLOR
    export VRAMON_CONFIG="$TMP_DIR/global" VRAMON_PROJECT_CONFIG="$TMP_DIR/project"
    config_load
    printf '%s %s\n' "$VRAMON_WIDTH" "$VRAMON_WARN"
) >"$TMP_DIR/out1"
assert_eq "15 35" "$(cat "$TMP_DIR/out1")" "project config overrides global config"
(
    unset VRAMON_WARN VRAMON_INTERVAL VRAMON_CRITICAL VRAMON_COLOR
    export VRAMON_CONFIG="$TMP_DIR/global" VRAMON_PROJECT_CONFIG="$TMP_DIR/project" VRAMON_WIDTH=42
    config_load
    printf '%s\n' "$VRAMON_WIDTH"
) >"$TMP_DIR/out2"
assert_eq 42 "$(cat "$TMP_DIR/out2")" "environment overrides config files"

echo "validation"
validate_with() {
    config_defaults
    printf -v "$1" '%s' "$2"
    config_validate
}
assert_status 0 "defaults are valid" validate_with VRAMON_WIDTH 20
assert_status 4 "width 0 rejected" validate_with VRAMON_WIDTH 0
assert_status 4 "width abc rejected" validate_with VRAMON_WIDTH abc
assert_status 4 "width above maximum rejected" validate_with VRAMON_WIDTH 999
assert_status 0 "fractional interval accepted" validate_with VRAMON_INTERVAL 0.5
assert_status 4 "zero interval rejected" validate_with VRAMON_INTERVAL 0
assert_status 4 "negative interval rejected" validate_with VRAMON_INTERVAL -1
assert_status 4 "warn above 100 rejected" validate_with VRAMON_WARN 101
assert_status 4 "critical above warn rejected" validate_with VRAMON_CRITICAL 50
assert_status 4 "color must be 0 or 1" validate_with VRAMON_COLOR yes
config_defaults

finish
