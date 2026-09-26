#!/usr/bin/env bash
# Install VRAMON-32M-GAUGE for the current user (no root required).
# Override the destination with PREFIX, e.g. PREFIX=/opt/vramon ./install.sh
set -Eeuo pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
SHARE_DIR="$PREFIX/share/vramon"

info() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

check_dependencies() {
    local missing=0 cmd

    for cmd in bash awk uname sleep; do
        if ! have "$cmd"; then
            warn "required command not found: $cmd"
            missing=1
        fi
    done

    case "$(uname -s)" in
        Linux)
            if ! have free && [ ! -r /proc/meminfo ]; then
                warn "neither 'free' (procps) nor /proc/meminfo is available"
                missing=1
            fi
            ;;
        Darwin)
            for cmd in vm_stat sysctl; do
                if ! have "$cmd"; then
                    warn "required command not found: $cmd"
                    missing=1
                fi
            done
            ;;
        *)
            warn "unsupported platform: $(uname -s) (Linux and macOS are supported)"
            ;;
    esac

    if have nvidia-smi; then
        info "GPU backend: NVIDIA (nvidia-smi)"
    elif have rocm-smi; then
        info "GPU backend: AMD (rocm-smi)"
    else
        info "No supported GPU tool found; VRAMON will run in RAM-only mode"
    fi

    return "$missing"
}

main() {
    if ! check_dependencies; then
        warn "missing dependencies; aborting installation"
        exit 1
    fi

    info "Installing to $PREFIX"
    mkdir -p "$BIN_DIR" "$SHARE_DIR/lib"
    rm -f "$SHARE_DIR"/lib/*.sh
    cp "$SRC_DIR"/lib/*.sh "$SHARE_DIR/lib/"
    chmod 644 "$SHARE_DIR"/lib/*.sh
    cp "$SRC_DIR/bin/vramon" "$BIN_DIR/vramon"
    chmod 755 "$BIN_DIR/vramon"

    info "Installed $BIN_DIR/vramon ($("$BIN_DIR/vramon" --version))"

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            printf '\n%s is not in your PATH. Add this line to your shell profile:\n\n' "$BIN_DIR"
            # shellcheck disable=SC2016
            printf '    export PATH="%s:$PATH"\n\n' "$BIN_DIR"
            ;;
    esac
}

main "$@"
