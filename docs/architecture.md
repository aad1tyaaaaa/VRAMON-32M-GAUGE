# Architecture

VRAMON-32M-GAUGE follows a strict pipeline:

```text
Collect -> Normalize -> Calculate -> Render
```

```text
bin/vramon  (argument parsing, config, orchestration, watch loop)
    |
    +-- lib/config.sh    defaults, config-file parser (no eval), validation
    +-- lib/platform.sh  detect_os, detect_gpu_backend
    |
    +-- Collectors -------------------------------------------------------
    |   lib/memory.sh    linux_memory (free -b, /proc/meminfo fallback)
    |                    macos_memory (sysctl hw.memsize + vm_stat)
    |   lib/gpu.sh       nvidia_gpu (nvidia-smi), amd_gpu (rocm-smi)
    |
    +-- lib/metrics.sh   headroom percentages, state model
    |
    +-- lib/renderer.sh  render_full, render_compact, render_tmux, render_json
```

## Internal API

Collectors set normalized variables (all sizes in bytes):

| Variable         | Meaning                                   |
| ---------------- | ----------------------------------------- |
| `RAM_TOTAL`      | Physical memory                           |
| `RAM_USED`       | `RAM_TOTAL - RAM_FREE`                    |
| `RAM_FREE`       | *Available* memory (includes reclaimable) |
| `VRAM_AVAILABLE` | `1` if a GPU collector succeeded          |
| `VRAM_TOTAL`     | GPU memory, summed across GPUs            |
| `VRAM_USED`      | Used GPU memory                           |
| `VRAM_FREE`      | Free GPU memory                           |
| `GPU_AVAILABLE`  | `1` if utilization is known               |
| `GPU_UTIL`       | Utilization percent, averaged across GPUs |
| `GPU_BACKEND`    | `nvidia`, `amd` or `none`                 |

The metrics layer derives:

| Variable           | Meaning                                  |
| ------------------ | ---------------------------------------- |
| `RAM_HEADROOM`     | `RAM_FREE / RAM_TOTAL * 100` (one decimal) |
| `VRAM_HEADROOM`    | `VRAM_FREE / VRAM_TOTAL * 100`           |
| `OVERALL_HEADROOM` | `min(RAM, VRAM)`, or RAM when no VRAM    |
| `MEMORY_STATE`     | `green`, `yellow` or `red`               |

Each percentage also has a `*_T` twin holding integer tenths (`82.3` -> `823`).
This lets thresholds, gauges and rounding use pure Bash arithmetic, so a
refresh only spawns the collector commands plus one `awk` per parser.

## State model

| State  | Headroom                      | Label    |
| ------ | ----------------------------- | -------- |
| GREEN  | `> VRAMON_WARN` (30)          | HEALTHY  |
| YELLOW | `VRAMON_CRITICAL`..`VRAMON_WARN` | WARNING |
| RED    | `< VRAMON_CRITICAL` (10)      | CRITICAL |

## Error handling

- The executable runs with `set -Eeuo pipefail`.
- GPU collectors are always called in a conditional context; any failure
  resets the GPU variables and VRAMON continues in RAM-only mode.
- Failure to read RAM is fatal (exit code 5).

| Code | Meaning              |
| ---- | -------------------- |
| 0    | Success              |
| 1    | General error        |
| 2    | Invalid argument     |
| 3    | Unsupported platform |
| 4    | Configuration error  |
| 5    | Collector error      |

## Configuration

Precedence, lowest to highest:

1. Built-in defaults
2. Global config: `$VRAMON_CONFIG`, else `$XDG_CONFIG_HOME/vramon/config`,
   else `~/.config/vramon/config`
3. Project config: `./.vramonrc`
4. Environment variables
5. Command-line arguments

Config files are parsed line by line. Only `KEY=value` (optionally prefixed
with `export`, optionally quoted) for known `VRAMON_*` keys is accepted; files
are never sourced or evaluated.

## Watch mode

When stdout is a terminal, the screen is cleared once, the cursor is hidden,
and each frame is redrawn from the home position with per-line clear
(`ESC[K`) and clear-to-end (`ESC[J`) to avoid flicker. An `EXIT` trap restores
colors and the cursor after Ctrl+C or `SIGTERM`. When stdout is not a
terminal (or in `--tmux` / `--json` mode) frames are simply printed one after
another, so `vramon --json --watch` produces newline-delimited JSON.

## Adding a collector

1. Write a `parse_<tool>_output` function that takes the raw text and sets the
   normalized variables (or returns non-zero).
2. Write a thin wrapper that runs the tool and calls the parser.
3. Add a fixture under `tests/fixtures/` and a test case.
