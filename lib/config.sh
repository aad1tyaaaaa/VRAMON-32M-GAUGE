# shellcheck shell=bash
# Configuration loading and validation.
#
# Precedence: built-in defaults < global config < project config (.vramonrc)
#             < environment variables < command-line arguments.
#
# Config files may only contain KEY=value assignments for known keys. They are
# parsed, never sourced or evaluated.

VRAMON_CONFIG_KEYS="VRAMON_INTERVAL VRAMON_WIDTH VRAMON_WARN VRAMON_CRITICAL VRAMON_COLOR"
VRAMON_MAX_WIDTH=200

config_defaults() {
    VRAMON_INTERVAL=2
    VRAMON_WIDTH=20
    VRAMON_WARN=30
    VRAMON_CRITICAL=10
    VRAMON_COLOR=1
}

config_is_key() {
    case " $VRAMON_CONFIG_KEYS " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

config_global_path() {
    if [ -n "${VRAMON_CONFIG:-}" ]; then
        printf '%s' "$VRAMON_CONFIG"
    elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
        printf '%s/vramon/config' "$XDG_CONFIG_HOME"
    elif [ -n "${HOME:-}" ]; then
        printf '%s/.config/vramon/config' "$HOME"
    fi
}

# config_parse_file FILE -> returns 4 on malformed input. Missing files are ignored.
config_parse_file() {
    local file="$1" line trimmed key value lineno=0
    local re='^(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$'

    if [ -z "$file" ] || [ ! -f "$file" ]; then
        return 0
    fi
    if [ ! -r "$file" ]; then
        printf 'vramon: cannot read config file: %s\n' "$file" >&2
        return 4
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line="${line%$'\r'}"
        trimmed="${line#"${line%%[![:space:]]*}"}"

        case "$trimmed" in
            '' | '#'*) continue ;;
        esac

        if ! [[ $trimmed =~ $re ]]; then
            printf 'vramon: %s:%d: invalid line (expected KEY=value)\n' "$file" "$lineno" >&2
            return 4
        fi
        key="${BASH_REMATCH[2]}"
        value="${BASH_REMATCH[3]}"

        case "$value" in
            \"*)
                value="${value#\"}"
                value="${value%%\"*}"
                ;;
            \'*)
                value="${value#\'}"
                value="${value%%\'*}"
                ;;
            *)
                value="${value%%[[:space:]]#*}"
                value="${value%"${value##*[![:space:]]}"}"
                ;;
        esac

        if config_is_key "$key"; then
            printf -v "$key" '%s' "$value"
        else
            printf 'vramon: %s:%d: ignoring unknown setting %s\n' "$file" "$lineno" "$key" >&2
        fi
    done <"$file"
}

# Load defaults and config files, then re-apply any values from the environment.
config_load() {
    local key ref env_keys=""

    for key in $VRAMON_CONFIG_KEYS; do
        if [ -n "${!key+x}" ]; then
            printf -v "_VRAMON_ENV_${key}" '%s' "${!key}"
            env_keys="$env_keys $key"
        fi
    done

    config_defaults
    config_parse_file "$(config_global_path)" || return 4
    config_parse_file "${VRAMON_PROJECT_CONFIG:-.vramonrc}" || return 4

    for key in $env_keys; do
        ref="_VRAMON_ENV_${key}"
        printf -v "$key" '%s' "${!ref}"
    done
}

valid_interval() {
    local zero='^0+(\.0+)?$'
    is_number "$1" && ! [[ $1 =~ $zero ]]
}

valid_width() {
    is_uint "$1" && [ "$((10#$1))" -ge 1 ] && [ "$((10#$1))" -le "$VRAMON_MAX_WIDTH" ]
}

valid_percent() {
    is_number "$1" && [ "$(to_tenths "$1")" -le 1000 ]
}

# Validate the effective configuration; prints the first problem found.
config_validate() {
    if ! valid_interval "$VRAMON_INTERVAL"; then
        printf 'vramon: invalid VRAMON_INTERVAL: %s (expected a positive number)\n' "$VRAMON_INTERVAL" >&2
        return 4
    fi
    if ! valid_width "$VRAMON_WIDTH"; then
        printf 'vramon: invalid VRAMON_WIDTH: %s (expected 1-%d)\n' "$VRAMON_WIDTH" "$VRAMON_MAX_WIDTH" >&2
        return 4
    fi
    if ! valid_percent "$VRAMON_WARN"; then
        printf 'vramon: invalid VRAMON_WARN: %s (expected 0-100)\n' "$VRAMON_WARN" >&2
        return 4
    fi
    if ! valid_percent "$VRAMON_CRITICAL"; then
        printf 'vramon: invalid VRAMON_CRITICAL: %s (expected 0-100)\n' "$VRAMON_CRITICAL" >&2
        return 4
    fi
    if [ "$(to_tenths "$VRAMON_CRITICAL")" -gt "$(to_tenths "$VRAMON_WARN")" ]; then
        printf 'vramon: VRAMON_CRITICAL (%s) must not exceed VRAMON_WARN (%s)\n' \
            "$VRAMON_CRITICAL" "$VRAMON_WARN" >&2
        return 4
    fi
    case "$VRAMON_COLOR" in
        0 | 1) ;;
        *)
            printf 'vramon: invalid VRAMON_COLOR: %s (expected 0 or 1)\n' "$VRAMON_COLOR" >&2
            return 4
            ;;
    esac
    VRAMON_WIDTH=$((10#$VRAMON_WIDTH))
}
