#!/usr/bin/env bash
# RAM collector tests (fixture based).
# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "free -b (modern procps)"
parse_free_output "$(fixture free.txt)"
assert_eq 16777216000 "$RAM_TOTAL" "total"
assert_eq 10777216000 "$RAM_FREE" "available (not raw free)"
assert_eq 6000000000 "$RAM_USED" "used = total - available"

echo "free -b (legacy procps)"
parse_free_output "$(fixture free_legacy.txt)"
assert_eq 8254218240 "$RAM_TOTAL" "total"
assert_eq 5442666496 "$RAM_FREE" "available = free + buffers + cached"
assert_eq 2811551744 "$RAM_USED" "used"

echo "/proc/meminfo fallback"
parse_meminfo "$FIXTURES/meminfo.txt"
assert_eq 16777216000 "$RAM_TOTAL" "total (kB -> bytes)"
assert_eq 8388608000 "$RAM_FREE" "MemAvailable"

echo "vm_stat (macOS)"
parse_vm_stat_output "$(fixture vm_stat.txt)" 17179869184
assert_eq 17179869184 "$RAM_TOTAL" "total from hw.memsize"
assert_eq 5734400000 "$RAM_FREE" "free + inactive + speculative pages"
assert_eq 11445469184 "$RAM_USED" "used"

echo "invalid input"
assert_status 1 "garbage free output fails" parse_free_output "not a free output"
assert_status 1 "empty free output fails" parse_free_output ""
assert_status 1 "vm_stat without page size fails" parse_vm_stat_output "Pages free: 10." 1000
assert_status 1 "missing meminfo fails" parse_meminfo "$FIXTURES/does-not-exist"
assert_status 1 "zero total fails" ram_set 0 0
assert_status 1 "non-numeric total fails" ram_set abc 10
assert_status 1 "unknown OS fails" collect_memory unknown

echo "normalization"
ram_set 1000 2000
assert_eq 1000 "$RAM_FREE" "available is clamped to total"
assert_eq 0 "$RAM_USED" "used is never negative"

finish
