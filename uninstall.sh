#!/usr/bin/env bash
# Uninstall VRAMON-32M-GAUGE. Configuration is kept unless --purge is given.
set -Eeuo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
SHARE_DIR="$PREFIX/share/vramon"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/vramon"
PURGE=0

info() { printf '==> %s\n' "$*"; }

usage() {
    printf 'Usage: %s [--purge]\n\n  --purge   Also remove %s\n' "$0" "$CONFIG_DIR"
}

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

if [ -f "$BIN_DIR/vramon" ]; then
    if grep -q 'VRAMON-32M-GAUGE' "$BIN_DIR/vramon" 2>/dev/null; then
        rm -f "$BIN_DIR/vramon"
        info "Removed $BIN_DIR/vramon"
    else
        printf 'warning: %s does not look like VRAMON; leaving it in place\n' "$BIN_DIR/vramon" >&2
    fi
fi

if [ -d "$SHARE_DIR" ]; then
    rm -rf "$SHARE_DIR"
    info "Removed $SHARE_DIR"
fi

if [ "$PURGE" = "1" ]; then
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        info "Removed $CONFIG_DIR"
    fi
elif [ -d "$CONFIG_DIR" ]; then
    info "Configuration kept at $CONFIG_DIR (use --purge to remove it)"
fi
