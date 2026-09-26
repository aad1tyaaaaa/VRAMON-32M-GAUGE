# shellcheck shell=bash
# Numeric helpers, headroom calculation and memory state model.
# Percentages are handled internally as integer tenths (82.3% -> 823) so that
# no external process is needed for arithmetic or threshold comparisons.
# shellcheck disable=SC2034,SC2154

is_uint() {
    case "$1" in
        '' | *[!0-9]*) return 1 ;;
    esac
}

is_number() {
    local re='^[0-9]+(\.[0-9]+)?$'
    [[ $1 =~ $re ]]
}

# to_tenths "82.37" -> 823. Non-numeric or negative input yields 0.
to_tenths() {
    local value="$1" int frac

    int="${value%%.*}"
    if [ "$int" = "$value" ]; then
        frac=0
    else
        frac="${value#*.}"
        frac="${frac:0:1}"
    fi
    : "${int:=0}" "${frac:=0}"
    if ! is_uint "$int" || ! is_uint "$frac"; then
        echo 0
        return 0
    fi
    echo $((10#$int * 10 + 10#$frac))
}

# format_tenths 823 -> "82.3"
format_tenths() {
    printf '%d.%d' "$(($1 / 10))" "$(($1 % 10))"
}

# percent_tenths PART TOTAL -> rounded percentage in tenths, clamped to 0..1000.
percent_tenths() {
    local part="$1" total="$2" result

    if ! is_uint "$part" || ! is_uint "$total" || [ "$((10#$total))" -le 0 ]; then
        echo 0
        return 0
    fi
    result=$(((10#$part * 1000 + 10#$total / 2) / 10#$total))
    echo $((result > 1000 ? 1000 : result))
}

# percent PART TOTAL -> "63.2"
percent() {
    format_tenths "$(percent_tenths "$1" "$2")"
}

# state_for_tenths TENTHS -> green | yellow | red
state_for_tenths() {
    local warn critical
    warn=$(to_tenths "${VRAMON_WARN:-30}")
    critical=$(to_tenths "${VRAMON_CRITICAL:-10}")

    if [ "$1" -gt "$warn" ]; then
        echo "green"
    elif [ "$1" -ge "$critical" ]; then
        echo "yellow"
    else
        echo "red"
    fi
}

# memory_state PERCENT -> green | yellow | red
memory_state() {
    state_for_tenths "$(to_tenths "$1")"
}

# Derive headroom metrics and state from the collector variables.
metrics_calculate() {
    RAM_HEADROOM_T=$(percent_tenths "$RAM_FREE" "$RAM_TOTAL")
    RAM_HEADROOM=$(format_tenths "$RAM_HEADROOM_T")
    RAM_STATE=$(state_for_tenths "$RAM_HEADROOM_T")

    if [ "${VRAM_AVAILABLE:-0}" = "1" ]; then
        VRAM_HEADROOM_T=$(percent_tenths "$VRAM_FREE" "$VRAM_TOTAL")
        VRAM_HEADROOM=$(format_tenths "$VRAM_HEADROOM_T")
        VRAM_STATE=$(state_for_tenths "$VRAM_HEADROOM_T")
        OVERALL_HEADROOM_T=$((RAM_HEADROOM_T < VRAM_HEADROOM_T ? RAM_HEADROOM_T : VRAM_HEADROOM_T))
    else
        VRAM_HEADROOM_T=0
        VRAM_HEADROOM="0.0"
        VRAM_STATE="none"
        OVERALL_HEADROOM_T="$RAM_HEADROOM_T"
    fi

    OVERALL_HEADROOM=$(format_tenths "$OVERALL_HEADROOM_T")
    MEMORY_STATE=$(state_for_tenths "$OVERALL_HEADROOM_T")
}

# state_label STATE -> healthy | warning | critical
state_label() {
    case "$1" in
        green) echo "healthy" ;;
        yellow) echo "warning" ;;
        *) echo "critical" ;;
    esac
}
