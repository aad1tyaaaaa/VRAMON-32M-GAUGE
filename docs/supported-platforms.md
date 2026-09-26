# Supported Platforms

| Platform       | RAM source                          | GPU source                       |
| -------------- | ----------------------------------- | -------------------------------- |
| Linux          | `free -b` (fallback `/proc/meminfo`) | `nvidia-smi` or `rocm-smi`       |
| macOS          | `sysctl -n hw.memsize` + `vm_stat`  | none (unified memory, see below) |
| WSL 2          | Same as Linux                       | `nvidia-smi` if exposed by WSL   |
| Other (BSD...) | Not supported (exit code 3)         |                                  |

Bash 3.2+ is supported, so the stock macOS `/bin/bash` works.

## Linux

The `available` column of `free -b` is used rather than `free`, because Linux
uses otherwise idle RAM for page cache. Legacy procps output without an
`available` column falls back to `free + buffers + cached`. If `free` is
missing, `/proc/meminfo` (`MemAvailable`) is read directly.

## macOS

Available memory is approximated as
`(Pages free + Pages inactive + Pages speculative) * page size`.
Apple Silicon uses unified memory, so there is no separate VRAM figure; the
RAM gauge already reflects GPU allocations. VRAM is shown as `N/A`.

## NVIDIA

```bash
nvidia-smi --query-gpu=memory.total,memory.used,memory.free,utilization.gpu \
           --format=csv,noheader,nounits
```

Values are reported in MiB and converted to bytes. With several GPUs, memory
is summed and utilization is averaged. GPUs reporting `[N/A]` utilization still
contribute VRAM figures.

## AMD

```bash
rocm-smi --showmeminfo vram --showuse
```

Lines containing `VRAM Total Memory (B)`, `VRAM Total Used Memory (B)` and
`GPU use (%)` are parsed case-insensitively. Output differs between ROCm
versions; if the required memory lines are missing, VRAMON continues in
RAM-only mode.

## Graceful degradation

A missing, failing or unparsable GPU tool is never fatal. VRAMON reports
`VRAM N/A` / `GPU unavailable` and bases the overall headroom on RAM alone.
