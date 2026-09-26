# shellcheck shell=bash
# Renderers: full, compact, tmux and JSON. They only read normalized metrics
# (see metrics.sh) and never care which collector produced them.
# shellcheck disable=SC2154

# renderer_init USE_COLOR
renderer_init() {
    if [ "${1:-0}" = "1" ]; then
        RESET=$'\033[0m'
        BOLD=$'\033[1m'
        GREEN=$'\033[32m'
        YELLOW=$'\033[33m'
        RED=$'\033[31m'
        CYAN=$'\033[36m'
    else
        RESET='' BOLD='' GREEN='' YELLOW='' RED='' CYAN=''
    fi
}

# state_color STATE
state_color() {
    case "$1" in
        green) printf '%s' "$GREEN" ;;
        yellow) printf '%s' "$YELLOW" ;;
        red) printf '%s' "$RED" ;;
    esac
}

# memory_color PERCENT
memory_color() {
    state_color "$(memory_state "$1")"
}

# repeat_char COUNT CHAR
repeat_char() {
    local s
    [ "$1" -gt 0 ] || return 0
    printf -v s '%*s' "$1" ''
    printf '%s' "${s// /$2}"
}

# _bar TENTHS WIDTH FILL_CHAR EMPTY_CHAR
_bar() {
    local width="$2" filled
    filled=$(($1 * width / 1000))
    filled=$((filled < 0 ? 0 : filled))
    filled=$((filled > width ? width : filled))
    repeat_char "$filled" "$3"
    repeat_char "$((width - filled))" "$4"
}

# render_bar PERCENT [WIDTH]
render_bar() {
    printf '[%s]' "$(_bar "$(to_tenths "$1")" "${2:-20}" '█' '░')"
}

# render_compact_bar PERCENT [WIDTH]
render_compact_bar() {
    _bar "$(to_tenths "$1")" "${2:-10}" '▰' '▱'
}

# format_bytes BYTES -> "15.6 GiB" / "512.0 MiB"
format_bytes() {
    local bytes="$1" t
    if [ "$bytes" -ge 1073741824 ]; then
        t=$(((bytes * 10 + 536870912) / 1073741824))
        printf '%d.%d GiB' "$((t / 10))" "$((t % 10))"
    else
        t=$(((bytes * 10 + 524288) / 1048576))
        printf '%d.%d MiB' "$((t / 10))" "$((t % 10))"
    fi
}

# Rounded integer percentage from tenths.
_round_pct() {
    echo $((($1 + 5) / 10))
}

_gauge_width() {
    echo "${VRAMON_WIDTH:-20}"
}

# _render_memory_line LABEL TENTHS STATE FREE TOTAL
_render_memory_line() {
    local pct
    pct=$(format_tenths "$2")
    printf '%-4s %s%s%s %5s%% free  (%s of %s)\n' \
        "$1" "$(state_color "$3")" "$(render_bar "$pct" "$(_gauge_width)")" "$RESET" \
        "$pct" "$(format_bytes "$4")" "$(format_bytes "$5")"
}

render_full() {
    printf '%sVRAMON-32M-GAUGE%s\n' "$BOLD" "$RESET"
    printf 'Visual Resource Monitoring for RAM & VRAM\n\n'

    _render_memory_line "RAM" "$RAM_HEADROOM_T" "$RAM_STATE" "$RAM_FREE" "$RAM_TOTAL"
    if [ "$VRAM_AVAILABLE" = "1" ]; then
        _render_memory_line "VRAM" "$VRAM_HEADROOM_T" "$VRAM_STATE" "$VRAM_FREE" "$VRAM_TOTAL"
    else
        printf 'VRAM N/A\n'
    fi

    if [ "$GPU_AVAILABLE" = "1" ]; then
        printf 'GPU  %s%s%s %4s%% used\n' \
            "$CYAN" "$(render_bar "$GPU_UTIL" "$(_gauge_width)")" "$RESET" "$GPU_UTIL"
    else
        printf 'GPU  unavailable\n'
    fi

    local label
    case "$MEMORY_STATE" in
        green) label="HEALTHY" ;;
        yellow) label="WARNING" ;;
        *) label="CRITICAL" ;;
    esac
    printf '\nSTATUS: %s%s%s\n' "$(state_color "$MEMORY_STATE")" "$label" "$RESET"
}

render_compact() {
    local width
    width=$(($(_gauge_width) / 2))
    width=$((width < 1 ? 1 : width))

    printf '%-4s %s%s%s %3d%%\n' "RAM" "$(state_color "$RAM_STATE")" \
        "$(render_compact_bar "$RAM_HEADROOM" "$width")" "$RESET" "$(_round_pct "$RAM_HEADROOM_T")"
    if [ "$VRAM_AVAILABLE" = "1" ]; then
        printf '%-4s %s%s%s %3d%%\n' "VRAM" "$(state_color "$VRAM_STATE")" \
            "$(render_compact_bar "$VRAM_HEADROOM" "$width")" "$RESET" "$(_round_pct "$VRAM_HEADROOM_T")"
    else
        printf 'VRAM N/A\n'
    fi
}

# Single line, plain text, no ANSI sequences: safe for tmux status bars.
render_tmux() {
    if [ "$VRAM_AVAILABLE" = "1" ]; then
        printf 'RAM %d%% | VRAM %d%%\n' "$(_round_pct "$RAM_HEADROOM_T")" "$(_round_pct "$VRAM_HEADROOM_T")"
    else
        printf 'RAM %d%%\n' "$(_round_pct "$RAM_HEADROOM_T")"
    fi
}

render_json() {
    local vram gpu

    if [ "$VRAM_AVAILABLE" = "1" ]; then
        vram=$(printf '{"available":true,"total":%s,"used":%s,"free":%s,"headroom_percent":%s}' \
            "$VRAM_TOTAL" "$VRAM_USED" "$VRAM_FREE" "$VRAM_HEADROOM")
    else
        vram='{"available":false,"total":null,"used":null,"free":null,"headroom_percent":null}'
    fi

    if [ "$GPU_AVAILABLE" = "1" ]; then
        gpu=$(printf '{"available":true,"backend":"%s","utilization_percent":%s}' "$GPU_BACKEND" "$GPU_UTIL")
    else
        gpu=$(printf '{"available":false,"backend":"%s","utilization_percent":null}' "$GPU_BACKEND")
    fi

    printf '{"ram":{"total":%s,"used":%s,"available":%s,"headroom_percent":%s},"vram":%s,"gpu":%s,"overall_headroom_percent":%s,"status":"%s"}\n' \
        "$RAM_TOTAL" "$RAM_USED" "$RAM_FREE" "$RAM_HEADROOM" "$vram" "$gpu" \
        "$OVERALL_HEADROOM" "$(state_label "$MEMORY_STATE")"
}
