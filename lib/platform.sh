# shellcheck shell=bash
# Platform and GPU backend detection.

detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Linux)
            echo "linux"
            ;;
        Darwin)
            echo "macos"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

detect_gpu_backend() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "nvidia"
    elif command -v rocm-smi >/dev/null 2>&1; then
        echo "amd"
    else
        echo "none"
    fi
}
