# shellcheck shell=bash
# System RAM collectors. Each collector sets RAM_TOTAL, RAM_USED and RAM_FREE
# (bytes, where RAM_FREE is *available* memory) and returns non-zero on failure.
# shellcheck disable=SC2034

# Validate and store normalized RAM values: ram_set TOTAL AVAILABLE
ram_set() {
    local total="$1" available="$2"

    if ! is_uint "$total" || ! is_uint "$available"; then
        return 1
    fi
    total=$((10#$total))
    available=$((10#$available))
    if [ "$total" -le 0 ]; then
        return 1
    fi
    if [ "$available" -gt "$total" ]; then
        available="$total"
    fi

    RAM_TOTAL="$total"
    RAM_FREE="$available"
    RAM_USED=$((total - available))
}

# Parse the output of `free -b`. Supports both the modern layout (with an
# "available" column) and the legacy procps layout (buffers/cached columns).
parse_free_output() {
    local line total available

    line=$(awk '
        NR == 1 && !/^Mem:/ {
            for (i = 1; i <= NF; i++) col[$i] = i + 1
            next
        }
        /^Mem:/ {
            total = $2
            if ("available" in col) {
                avail = $(col["available"])
            } else {
                avail = $4
                if ("buffers" in col) avail += $(col["buffers"])
                if ("cached" in col) avail += $(col["cached"])
            }
            printf "%.0f %.0f\n", total, avail
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' <<<"$1") || return 1

    read -r total available <<<"$line"
    ram_set "$total" "$available"
}

# Parse a /proc/meminfo style file (values in kB).
parse_meminfo() {
    local file="$1" key value total="" avail="" free=0 buffers=0 cached=0

    [ -r "$file" ] || return 1
    while read -r key value _; do
        case "$key" in
            MemTotal:) total="$value" ;;
            MemAvailable:) avail="$value" ;;
            MemFree:) free="$value" ;;
            Buffers:) buffers="$value" ;;
            Cached:) cached="$value" ;;
        esac
    done <"$file"

    if ! is_uint "$total" || ! is_uint "$free" || ! is_uint "$buffers" || ! is_uint "$cached"; then
        return 1
    fi
    if [ -z "$avail" ]; then
        avail=$((free + buffers + cached))
    fi
    is_uint "$avail" || return 1
    ram_set "$((total * 1024))" "$((avail * 1024))"
}

linux_memory() {
    local out

    if command -v free >/dev/null 2>&1 && out=$(free -b 2>/dev/null) && parse_free_output "$out"; then
        return 0
    fi
    parse_meminfo /proc/meminfo
}

# Parse `vm_stat` output given the total physical memory in bytes.
# Available memory is approximated as free + inactive + speculative pages.
parse_vm_stat_output() {
    local available

    available=$(awk '
        /page size of/ {
            for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) page = $i
        }
        /^Pages free:/        { free = $NF + 0 }
        /^Pages inactive:/    { inactive = $NF + 0 }
        /^Pages speculative:/ { speculative = $NF + 0 }
        END {
            if (page <= 0) exit 1
            printf "%.0f\n", (free + inactive + speculative) * page
        }
    ' <<<"$1") || return 1

    ram_set "$2" "$available"
}

macos_memory() {
    local total out

    total=$(sysctl -n hw.memsize 2>/dev/null) || return 1
    out=$(vm_stat 2>/dev/null) || return 1
    parse_vm_stat_output "$out" "$total"
}

# collect_memory OS
collect_memory() {
    case "$1" in
        linux) linux_memory ;;
        macos) macos_memory ;;
        *) return 1 ;;
    esac
}
