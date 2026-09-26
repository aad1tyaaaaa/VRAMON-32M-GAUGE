#!/usr/bin/env bash
# End-to-end CLI tests using stub system commands on an isolated PATH.
# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
STUB_DIR="$TMP_DIR/stubs"
WORK_DIR="$TMP_DIR/work"
mkdir -p "$STUB_DIR" "$WORK_DIR" "$TMP_DIR/home"

# stub NAME BODY
stub() {
    printf '#!%s\n%s\n' "$BASH" "$2" >"$STUB_DIR/$1"
    chmod +x "$STUB_DIR/$1"
}

# Wrap real tools by absolute path so nothing else from the host PATH leaks in.
stub awk "exec '$(command -v awk)' \"\$@\""
stub cat "exec '$(command -v cat)' \"\$@\""

use_linux() {
    rm -f "$STUB_DIR"/{uname,free,nvidia-smi,rocm-smi,sysctl,vm_stat}
    stub uname 'echo Linux'
    stub free "cat '$FIXTURES/free.txt'"
}

# vramon ARGS... -> runs bin/vramon with a clean environment
vramon() {
    (cd "$WORK_DIR" && env -i PATH="$STUB_DIR" HOME="$TMP_DIR/home" ${EXTRA_ENV:+"$EXTRA_ENV"} \
        "$BASH" "$ROOT_DIR/bin/vramon" "$@")
}

use_linux

echo "basic CLI"
assert_eq "VRAMON-32M-GAUGE v1.0.0" "$(vramon --version)" "--version"
assert_contains "$(vramon --help)" "Usage: vramon" "--help"
assert_status 2 "unknown option exits 2" vramon --bogus
assert_status 2 "invalid --width exits 2" vramon --width abc
assert_status 2 "missing --interval value exits 2" vramon --interval
assert_status 2 "invalid --interval= exits 2" vramon --interval=0

echo "Linux RAM-only"
assert_eq "RAM 64%" "$(vramon --tmux)" "tmux output without GPU"
out=$(vramon)
assert_contains "$out" "RAM  [████████████░░░░░░░░]  64.2% free" "default full output"
assert_contains "$out" "VRAM N/A" "VRAM gracefully unavailable"
assert_contains "$(vramon --once --width 10)" "RAM  [██████░░░░]" "--width"
assert_contains "$(vramon --width=10)" "RAM  [██████░░░░]" "--width=N"
assert_contains "$(vramon --json)" '"overall_headroom_percent":64.2,"status":"healthy"' "JSON output"
assert_contains "$(vramon --compact)" "RAM  ▰▰▰▰▰▰▱▱▱▱  64%" "compact output"

echo "Linux + NVIDIA"
stub nvidia-smi "cat '$FIXTURES/nvidia.txt'"
assert_eq "RAM 64% | VRAM 63%" "$(vramon --tmux)" "tmux output with VRAM"
assert_contains "$(vramon)" "GPU  [████████░░░░░░░░░░░░]   42% used" "GPU utilization line"
assert_contains "$(vramon --json)" '"gpu":{"available":true,"backend":"nvidia","utilization_percent":42}' "JSON GPU"

stub nvidia-smi 'echo "NVIDIA-SMI has failed" >&2; exit 9'
assert_eq "RAM 64%" "$(vramon --tmux)" "failing nvidia-smi degrades to RAM-only"
assert_status 0 "failing nvidia-smi is not fatal" vramon

echo "Linux + AMD"
rm -f "$STUB_DIR/nvidia-smi"
stub rocm-smi "cat '$FIXTURES/rocm.txt'"
assert_eq "RAM 64% | VRAM 75%" "$(vramon --tmux)" "rocm-smi VRAM"

echo "macOS"
rm -f "$STUB_DIR"/{uname,free,rocm-smi}
stub uname 'echo Darwin'
stub sysctl 'echo 17179869184'
stub vm_stat "cat '$FIXTURES/vm_stat.txt'"
assert_eq "RAM 33%" "$(vramon --tmux)" "vm_stat based RAM"
stub sysctl 'exit 1'
assert_status 5 "collector failure exits 5" vramon

echo "unsupported platform"
stub uname 'echo SunOS'
assert_status 3 "unsupported OS exits 3" vramon

echo "configuration"
use_linux
mkdir -p "$TMP_DIR/home/.config/vramon"
printf 'VRAMON_WIDTH=10\n' >"$TMP_DIR/home/.config/vramon/config"
assert_contains "$(vramon)" "RAM  [██████░░░░]" "global config file"
printf 'VRAMON_WIDTH=4\n' >"$WORK_DIR/.vramonrc"
assert_contains "$(vramon)" "RAM  [██░░]" "project .vramonrc overrides global"
EXTRA_ENV="VRAMON_WIDTH=6"
assert_contains "$(vramon)" "RAM  [███░░░]" "environment overrides config files"
assert_contains "$(vramon --width 8)" "RAM  [█████░░░]" "CLI overrides environment"
EXTRA_ENV="VRAMON_WIDTH=abc"
assert_status 4 "invalid environment value exits 4" vramon
EXTRA_ENV=""
printf 'rm -rf /\n' >"$WORK_DIR/.vramonrc"
assert_status 4 "malformed config exits 4" vramon
rm -f "$WORK_DIR/.vramonrc"

finish
