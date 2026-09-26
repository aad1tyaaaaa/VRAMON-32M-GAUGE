# shellcheck shell=bash
# GPU collectors. On success they set VRAM_AVAILABLE=1, VRAM_TOTAL, VRAM_USED,
# VRAM_FREE (bytes), GPU_AVAILABLE and GPU_UTIL (percent). Memory is summed and
# utilization averaged across all detected GPUs. Failure is never fatal.
# shellcheck disable=SC2034

gpu_reset() {
    GPU_BACKEND="none"
    VRAM_AVAILABLE=0
    VRAM_TOTAL=0
    VRAM_USED=0
    VRAM_FREE=0
    GPU_AVAILABLE=0
    GPU_UTIL=0
}

# gpu_set TOTAL USED FREE UTIL   (bytes; UTIL is "-" when unknown)
gpu_set() {
    local total="$1" used="$2" free="$3" util="$4"

    if ! is_uint "$total" || ! is_uint "$used" || ! is_uint "$free" || [ "$total" -le 0 ]; then
        return 1
    fi
    if [ "$free" -gt "$total" ]; then
        free="$total"
    fi

    VRAM_AVAILABLE=1
    VRAM_TOTAL="$total"
    VRAM_USED="$used"
    VRAM_FREE="$free"

    if is_uint "$util"; then
        GPU_AVAILABLE=1
        GPU_UTIL=$((10#$util > 100 ? 100 : 10#$util))
    else
        GPU_AVAILABLE=0
        GPU_UTIL=0
    fi
}

# Parse `nvidia-smi --query-gpu=memory.total,memory.used,memory.free,utilization.gpu
# --format=csv,noheader,nounits` output (memory in MiB, one line per GPU).
parse_nvidia_output() {
    local line total used free util

    line=$(awk -F',' '
        function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
        NF >= 3 {
            t = trim($1); u = trim($2); f = trim($3); g = (NF >= 4) ? trim($4) : ""
            if (t ~ /^[0-9]+$/ && f ~ /^[0-9]+$/) {
                total += t
                free += f
                used += (u ~ /^[0-9]+$/) ? u : t - f
                n++
                if (g ~ /^[0-9]+$/) { util += g; un++ }
            }
        }
        END {
            if (n == 0) exit 1
            printf "%.0f %.0f %.0f %s\n", total * 1048576, used * 1048576, free * 1048576,
                (un > 0 ? sprintf("%.0f", util / un) : "-")
        }
    ' <<<"$1") || return 1

    read -r total used free util <<<"$line"
    gpu_set "$total" "$used" "$free" "$util"
}

nvidia_gpu() {
    local data

    data=$(nvidia-smi \
        --query-gpu=memory.total,memory.used,memory.free,utilization.gpu \
        --format=csv,noheader,nounits 2>/dev/null) || return 1
    parse_nvidia_output "$data"
}

# Parse `rocm-smi --showmeminfo vram --showuse` output (memory in bytes).
parse_rocm_output() {
    local line total used free util

    line=$(awk '
        { l = tolower($0); v = $NF; gsub(/%/, "", v) }
        l ~ /vram total memory \(b\)/      { if (v ~ /^[0-9]+$/) { total += v; n++ }; next }
        l ~ /vram total used memory \(b\)/ { if (v ~ /^[0-9]+$/) { used += v; un_mem++ }; next }
        l ~ /gpu use \(%\)/                { if (v ~ /^[0-9]+$/) { util += v; un++ } }
        END {
            if (n == 0 || un_mem == 0) exit 1
            free = total - used
            if (free < 0) free = 0
            printf "%.0f %.0f %.0f %s\n", total, used, free,
                (un > 0 ? sprintf("%.0f", util / un) : "-")
        }
    ' <<<"$1") || return 1

    read -r total used free util <<<"$line"
    gpu_set "$total" "$used" "$free" "$util"
}

amd_gpu() {
    local data

    # rocm-smi may exit non-zero on warnings while still printing usable data.
    data=$(rocm-smi --showmeminfo vram --showuse 2>/dev/null) || true
    parse_rocm_output "$data"
}

# collect_gpu BACKEND
collect_gpu() {
    gpu_reset
    case "$1" in
        nvidia) nvidia_gpu || return 1 ;;
        amd) amd_gpu || return 1 ;;
        *) return 1 ;;
    esac
    GPU_BACKEND="$1"
}
