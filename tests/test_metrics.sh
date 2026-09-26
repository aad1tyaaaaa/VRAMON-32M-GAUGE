#!/usr/bin/env bash
# Metric calculation, state model and GPU parser tests (fixture based).
# shellcheck disable=SC2034
# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "percent"
assert_eq 63.2 "$(percent 5180 8192)" "5180/8192 MiB"
assert_eq 50.0 "$(percent 8589934592 17179869184)" "half"
assert_eq 100.0 "$(percent 10 10)" "full"
assert_eq 0.0 "$(percent 0 10)" "empty"
assert_eq 0.0 "$(percent 5 0)" "zero total does not divide by zero"
assert_eq 100.0 "$(percent 20 10)" "clamped to 100"

echo "to_tenths"
assert_eq 823 "$(to_tenths 82.3)" "82.3"
assert_eq 300 "$(to_tenths 30)" "30"
assert_eq 99 "$(to_tenths 9.99)" "9.99 truncates"
assert_eq 0 "$(to_tenths -5)" "negative -> 0"

echo "state model (defaults: warn=30 critical=10)"
assert_eq green "$(memory_state 100)" "100% -> GREEN"
assert_eq green "$(memory_state 50)" "50% -> GREEN"
assert_eq green "$(memory_state 30.1)" "30.1% -> GREEN"
assert_eq yellow "$(memory_state 30)" "30% -> YELLOW"
assert_eq yellow "$(memory_state 10)" "10% -> YELLOW"
assert_eq red "$(memory_state 9.9)" "9.9% -> RED"
assert_eq red "$(memory_state 0)" "0% -> RED"

echo "configurable thresholds"
VRAMON_WARN=50 VRAMON_CRITICAL=20
assert_eq green "$(memory_state 50.1)" "50.1% -> GREEN"
assert_eq yellow "$(memory_state 40)" "40% -> YELLOW"
assert_eq red "$(memory_state 19.9)" "19.9% -> RED"
config_defaults

echo "nvidia-smi parser"
parse_nvidia_output "$(fixture nvidia.txt)"
assert_eq 1 "$VRAM_AVAILABLE" "VRAM available"
assert_eq 8589934592 "$VRAM_TOTAL" "total 8192 MiB"
assert_eq 3158310912 "$VRAM_USED" "used 3012 MiB"
assert_eq 5431623680 "$VRAM_FREE" "free 5180 MiB"
assert_eq 42 "$GPU_UTIL" "utilization 42%"
assert_eq 63.2 "$(percent "$VRAM_FREE" "$VRAM_TOTAL")" "VRAM headroom 63.2%"

gpu_reset
parse_nvidia_output "$(fixture nvidia_multi.txt)"
assert_eq 34359738368 "$VRAM_TOTAL" "multi-GPU total is summed"
assert_eq 30127685632 "$VRAM_FREE" "multi-GPU free is summed"
assert_eq 26 "$GPU_UTIL" "multi-GPU utilization is averaged"

gpu_reset
parse_nvidia_output "8192, 3012, 5180, [N/A]"
assert_eq 1 "$VRAM_AVAILABLE" "VRAM still available when utilization is N/A"
assert_eq 0 "$GPU_AVAILABLE" "utilization N/A -> GPU util unavailable"

gpu_reset
assert_status 1 "nvidia-smi error text fails" \
    parse_nvidia_output "NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver."
assert_status 1 "unknown backend fails" collect_gpu none

echo "rocm-smi parser"
gpu_reset
parse_rocm_output "$(fixture rocm.txt)"
assert_eq 17163091968 "$VRAM_TOTAL" "total"
assert_eq 4290772992 "$VRAM_USED" "used"
assert_eq 12872318976 "$VRAM_FREE" "free = total - used"
assert_eq 37 "$GPU_UTIL" "utilization"
assert_eq 75.0 "$(percent "$VRAM_FREE" "$VRAM_TOTAL")" "headroom"
assert_status 1 "rocm-smi without memory info fails" parse_rocm_output "GPU[0] : GPU use (%): 5"

echo "metrics_calculate"
RAM_TOTAL=17179869184 RAM_FREE=8589934592 RAM_USED=8589934592
gpu_reset
gpu_set 8589934592 6442450944 2147483648 42
metrics_calculate
assert_eq 50.0 "$RAM_HEADROOM" "RAM headroom"
assert_eq 25.0 "$VRAM_HEADROOM" "VRAM headroom"
assert_eq 25.0 "$OVERALL_HEADROOM" "overall = min(RAM, VRAM)"
assert_eq yellow "$MEMORY_STATE" "state from overall headroom"

gpu_reset
metrics_calculate
assert_eq 50.0 "$OVERALL_HEADROOM" "overall = RAM when VRAM unavailable"
assert_eq green "$MEMORY_STATE" "RAM-only state"

finish
