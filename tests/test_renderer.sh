#!/usr/bin/env bash
# Renderer tests.
# shellcheck disable=SC2034
# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "render_bar"
assert_eq "[████████████████████]" "$(render_bar 100 20)" "100%"
assert_eq "[██████████░░░░░░░░░░]" "$(render_bar 50 20)" "50%"
assert_eq "[░░░░░░░░░░░░░░░░░░░░]" "$(render_bar 0 20)" "0%"
assert_eq "[████████████████████]" "$(render_bar 150 20)" "over 100% is clamped"
assert_eq "[░░░░░░░░░░░░░░░░░░░░]" "$(render_bar -5 20)" "negative is clamped"
assert_eq "[█████░░░░░]" "$(render_bar 50 10)" "custom width"
assert_eq "[████████████████░░░░]" "$(render_bar 82.3 20)" "fractional percentage"
assert_eq "▰▰▰▰▰▰▰▱▱▱" "$(render_compact_bar 72 10)" "compact bar"

echo "format_bytes"
assert_eq "16.0 GiB" "$(format_bytes 17179869184)" "GiB"
assert_eq "512.0 MiB" "$(format_bytes 536870912)" "MiB"

echo "colors"
renderer_init 1
assert_eq "$GREEN" "$(memory_color 50)" "GREEN above warn"
assert_eq "$YELLOW" "$(memory_color 30)" "YELLOW at warn boundary"
assert_eq "$RED" "$(memory_color 9.9)" "RED below critical"
renderer_init 0
assert_eq "" "$(memory_color 50)" "no color when disabled"

# Sample metrics: RAM 81.4% free, VRAM 56.2% free, GPU 37% used.
RAM_TOTAL=17179869184 RAM_USED=3195455668 RAM_FREE=13984413516
gpu_reset
GPU_BACKEND=nvidia
gpu_set 8589934592 3762290278 4827644314 37
metrics_calculate

echo "tmux"
tmux_out=$(render_tmux)
assert_eq "RAM 81% | VRAM 56%" "$tmux_out" "tmux line"
assert_eq 1 "$(printf '%s\n' "$tmux_out" | wc -l | tr -d ' ')" "exactly one line"
esc=$'\033'
case "$tmux_out" in *"$esc"*) has_esc=1 ;; *) has_esc=0 ;; esac
assert_eq 0 "$has_esc" "no ANSI sequences"

echo "json"
assert_eq '{"ram":{"total":17179869184,"used":3195455668,"available":13984413516,"headroom_percent":81.4},"vram":{"available":true,"total":8589934592,"used":3762290278,"free":4827644314,"headroom_percent":56.2},"gpu":{"available":true,"backend":"nvidia","utilization_percent":37},"overall_headroom_percent":56.2,"status":"healthy"}' \
    "$(render_json)" "full JSON document"

echo "full"
full_out=$(render_full)
assert_contains "$full_out" "RAM  [████████████████░░░░]  81.4% free" "RAM line"
assert_contains "$full_out" "VRAM [███████████░░░░░░░░░]  56.2% free" "VRAM line"
assert_contains "$full_out" "GPU  [███████░░░░░░░░░░░░░]   37% used" "GPU line"
assert_contains "$full_out" "STATUS: HEALTHY" "status"

echo "compact"
compact_out=$(render_compact)
assert_contains "$compact_out" "RAM  ▰▰▰▰▰▰▰▰▱▱  81%" "RAM compact line"
assert_contains "$compact_out" "VRAM ▰▰▰▰▰▱▱▱▱▱  56%" "VRAM compact line"

echo "RAM-only"
gpu_reset
metrics_calculate
assert_eq "RAM 81%" "$(render_tmux)" "tmux without VRAM"
assert_contains "$(render_full)" "VRAM N/A" "full without VRAM"
assert_contains "$(render_full)" "GPU  unavailable" "GPU unavailable"
assert_contains "$(render_json)" '"vram":{"available":false,"total":null' "JSON without VRAM"

finish
