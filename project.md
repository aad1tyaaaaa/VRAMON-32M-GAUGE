git add --chmod=+x bin/vramon install.sh uninstall.sh tests/*.sh# VRAMON-32M-GAUGE

**Visual Resource Monitoring for RAM & VRAM**

A minimal, dependency-light shell monitoring tool that displays live
system memory and GPU memory utilization as a compact terminal/tmux
status-bar gauge.

> Project type: Systems / Shell / CLI\
> Primary language: Bash\
> Target platforms: Linux + macOS\
> GPU backends: NVIDIA (`nvidia-smi`), AMD (`rocm-smi` / `rocm-smi`
> compatible systems), macOS system-memory monitoring via `vm_stat`\
> Name: **VRAMON-32M-GAUGE**

------------------------------------------------------------------------

## 1. Project Vision

VRAMON-32M-GAUGE answers one simple question:

**"How much memory capacity do I still have before my machine starts
getting uncomfortable?"**

The tool periodically collects:

-   System RAM usage
-   Available/free RAM
-   GPU VRAM usage when a supported GPU is detected
-   GPU utilization when available
-   Remaining memory percentage
-   A color-coded terminal gauge

It is designed to work both as:

1.  A standalone terminal monitor
2.  A compact `tmux` status-bar component
3.  A script that can be embedded into other shell workflows

The first version intentionally avoids Python, Node.js, Rust, Go,
databases, daemons, or GUI dependencies.

------------------------------------------------------------------------

# 2. Core Concept

The project separates **collection**, **calculation**, **rendering**,
and **presentation**.

``` text
                +-----------------------+
                |      VRAMON CLI       |
                +-----------+-----------+
                            |
                            v
                +-----------------------+
                | Platform Detection    |
                +-----------+-----------+
                            |
             +--------------+--------------+
             |                             |
             v                             v
       Linux / NVIDIA                 macOS / Unix
             |                             |
      +------+-------+                +----+----+
      |              |                |
      v              v                v
     free        nvidia-smi         vm_stat
      |              |                |
      +--------------+----------------+
                     |
                     v
             Normalized Metrics
                     |
                     v
             Headroom Calculation
                     |
                     v
             Gauge / ANSI Renderer
                     |
          +----------+-----------+
          |                      |
          v                      v
      Terminal                tmux
```

------------------------------------------------------------------------

# 3. Functional Requirements

## FR-01 --- RAM monitoring

The program must calculate:

-   Total RAM
-   Used RAM
-   Available RAM
-   Free/available percentage

Linux source:

``` bash
free -b
```

macOS source:

``` bash
vm_stat
sysctl hw.memsize
```

------------------------------------------------------------------------

## FR-02 --- GPU VRAM monitoring

For NVIDIA:

``` bash
nvidia-smi
```

For AMD:

``` bash
rocm-smi
```

If no supported GPU tool is available, GPU monitoring should gracefully
degrade instead of crashing.

Example:

``` text
GPU: unavailable
```

------------------------------------------------------------------------

## FR-03 --- Headroom calculation

RAM headroom:

``` text
RAM_HEADROOM = available_ram / total_ram * 100
```

VRAM headroom:

``` text
VRAM_HEADROOM = free_vram / total_vram * 100
```

Overall headroom:

``` text
OVERALL_HEADROOM = minimum(RAM_HEADROOM, VRAM_HEADROOM)
```

If VRAM is unavailable:

``` text
OVERALL_HEADROOM = RAM_HEADROOM
```

This makes the tool useful on CPU-only systems as well.

------------------------------------------------------------------------

# 4. Memory State Model

VRAMON uses three default states.

``` text
GREEN
> 30% available
Healthy resource headroom

YELLOW
10% - 30% available
Resource pressure increasing

RED
< 10% available
Low memory headroom
```

The thresholds should be configurable.

Example:

``` bash
VRAMON_WARN=30
VRAMON_CRITICAL=10
```

------------------------------------------------------------------------

# 5. Visual Gauge

Default terminal output:

``` text
RAM  [████████████████░░░░]  82% free
VRAM [██████████░░░░░░░░░░]  51% free
```

Compact mode:

``` text
MEM ▰▰▰▰▰▰▰▱▱▱ 61%
```

tmux mode:

``` text
RAM:61% VRAM:51%
```

------------------------------------------------------------------------

# 6. Project Structure

``` text
vramon-32m-gauge/
│
├── bin/
│   └── vramon
│
├── lib/
│   ├── platform.sh
│   ├── memory.sh
│   ├── gpu.sh
│   ├── metrics.sh
│   ├── renderer.sh
│   └── config.sh
│
├── tests/
│   ├── test_memory.sh
│   ├── test_metrics.sh
│   ├── test_renderer.sh
│   └── fixtures/
│       ├── free.txt
│       ├── nvidia.txt
│       └── vm_stat.txt
│
├── examples/
│   ├── tmux.conf
│   └── .vramonrc
│
├── docs/
│   ├── architecture.md
│   └── supported-platforms.md
│
├── Makefile
├── install.sh
├── uninstall.sh
├── README.md
├── LICENSE
└── project.md
```

------------------------------------------------------------------------

# 7. Design Principle

Keep the executable small.

The main executable should orchestrate modules:

``` bash
#!/usr/bin/env bash

source "$VRAMON_ROOT/lib/platform.sh"
source "$VRAMON_ROOT/lib/memory.sh"
source "$VRAMON_ROOT/lib/gpu.sh"
source "$VRAMON_ROOT/lib/metrics.sh"
source "$VRAMON_ROOT/lib/renderer.sh"
source "$VRAMON_ROOT/lib/config.sh"
```

The collection modules should return normalized values.

Example:

``` text
RAM_TOTAL=17179869184
RAM_AVAILABLE=8589934592

VRAM_TOTAL=8589934592
VRAM_FREE=4294967296
```

The renderer should not care where these values came from.

------------------------------------------------------------------------

# 8. Dependencies

Required:

``` bash
bash
awk
sed
grep
printf
sleep
```

Linux:

``` bash
procps
```

For NVIDIA:

``` bash
nvidia-smi
```

For AMD:

``` bash
rocm-smi
```

macOS:

``` bash
vm_stat
sysctl
```

No external package manager is required for the basic RAM monitor.

------------------------------------------------------------------------

# 9. Platform Detection

Create:

``` text
lib/platform.sh
```

Implementation concept:

``` bash
detect_os() {
    case "$(uname -s)" in
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
```

GPU detection:

``` bash
detect_gpu_backend() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "nvidia"
    elif command -v rocm-smi >/dev/null 2>&1; then
        echo "amd"
    else
        echo "none"
    fi
}
```

------------------------------------------------------------------------

# 10. Linux RAM Collector

Create:

``` text
lib/memory.sh
```

Use:

``` bash
free -b
```

Example output:

``` text
               total        used        free      shared  buff/cache   available
Mem:     16777216000  6000000000  2000000000   300000000   8777216000  10777216000
Swap:     2147483648   100000000    ...
```

The important value is `available`.

Implementation:

``` bash
linux_memory() {
    local line

    line=$(free -b | awk '/^Mem:/ {
        print $2, $3, $4, $6, $7
    }')

    read -r total used free buff_cache available <<< "$line"

    RAM_TOTAL="$total"
    RAM_USED="$used"
    RAM_FREE="$available"
}
```

Use available memory instead of raw `free` memory because Linux
aggressively uses unused RAM for cache.

------------------------------------------------------------------------

# 11. macOS RAM Collector

macOS exposes VM statistics through:

``` bash
vm_stat
```

Total physical memory:

``` bash
sysctl -n hw.memsize
```

Example:

``` bash
macos_memory() {
    local total
    total=$(sysctl -n hw.memsize)

    local page_size
    page_size=$(vm_stat | awk '/page size of/ {
        gsub("[^0-9]", "", $0)
        print $0
    }')

    # Parse vm_stat counters here.
    # Calculate free + inactive + speculative memory
    # as an approximation of available memory.

    RAM_TOTAL="$total"
    RAM_FREE="$available"
}
```

The exact macOS parsing should be isolated in this function so the rest
of VRAMON remains platform-independent.

------------------------------------------------------------------------

# 12. NVIDIA VRAM Collector

Use:

``` bash
nvidia-smi
```

Preferred query:

``` bash
nvidia-smi \
    --query-gpu=memory.total,memory.used,memory.free,utilization.gpu \
    --format=csv,noheader,nounits
```

Example:

``` text
8192, 3012, 5180, 42
```

Parse:

``` bash
nvidia_gpu() {
    local data

    data=$(nvidia-smi \
        --query-gpu=memory.total,memory.used,memory.free,utilization.gpu \
        --format=csv,noheader,nounits 2>/dev/null) || return 1

    IFS=',' read -r VRAM_TOTAL VRAM_USED VRAM_FREE GPU_UTIL <<< "$data"

    VRAM_TOTAL=$(printf '%s' "$VRAM_TOTAL" | xargs)
    VRAM_USED=$(printf '%s' "$VRAM_USED" | xargs)
    VRAM_FREE=$(printf '%s' "$VRAM_FREE" | xargs)
    GPU_UTIL=$(printf '%s' "$GPU_UTIL" | xargs)

    # nvidia-smi reports memory in MiB.
    VRAM_TOTAL=$((VRAM_TOTAL * 1024 * 1024))
    VRAM_USED=$((VRAM_USED * 1024 * 1024))
    VRAM_FREE=$((VRAM_FREE * 1024 * 1024))
}
```

------------------------------------------------------------------------

# 13. AMD VRAM Collector

The AMD implementation should be separated because `rocm-smi` output
differs between ROCm versions and GPU generations.

Start with:

``` bash
rocm-smi --showmeminfo vram
```

and:

``` bash
rocm-smi --showuse
```

Normalize the resulting values into:

``` text
VRAM_TOTAL
VRAM_USED
VRAM_FREE
GPU_UTIL
```

If parsing fails, return:

``` bash
return 1
```

The main program should continue with RAM-only monitoring.

------------------------------------------------------------------------

# 14. Metric Calculation

Create:

``` text
lib/metrics.sh
```

Percentage function:

``` bash
percent() {
    awk -v used="$1" -v total="$2" '
        BEGIN {
            if (total <= 0) {
                print 0
            } else {
                printf "%.1f", (used / total) * 100
            }
        }
    '
}
```

RAM headroom:

``` bash
RAM_HEADROOM=$(percent "$RAM_FREE" "$RAM_TOTAL")
```

VRAM headroom:

``` bash
VRAM_HEADROOM=$(percent "$VRAM_FREE" "$VRAM_TOTAL")
```

Overall headroom:

``` bash
if [ "$HAS_VRAM" = "1" ]; then
    OVERALL_HEADROOM=$(awk -v r="$RAM_HEADROOM" -v v="$VRAM_HEADROOM" \
        'BEGIN { print (r < v ? r : v) }')
else
    OVERALL_HEADROOM="$RAM_HEADROOM"
fi
```

------------------------------------------------------------------------

# 15. Gauge Renderer

Create:

``` text
lib/renderer.sh
```

The renderer accepts:

``` text
percentage
width
```

Example:

``` bash
render_bar() {
    local percentage="$1"
    local width="${2:-20}"

    local filled
    filled=$(awk -v p="$percentage" -v w="$width" \
        'BEGIN {
            printf "%d", (p / 100) * w
        }')

    local empty=$((width - filled))

    printf '['

    printf '%*s' "$filled" '' | tr ' ' '█'
    printf '%*s' "$empty" '' | tr ' ' '░'

    printf ']'
}
```

------------------------------------------------------------------------

# 16. ANSI Color System

Create:

``` bash
RESET='\033[0m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
```

State function:

``` bash
memory_color() {
    local value="$1"

    if awk -v v="$value" 'BEGIN { exit !(v > 30) }'; then
        printf '%s' "$GREEN"
    elif awk -v v="$value" 'BEGIN { exit !(v >= 10) }'; then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$RED"
    fi
}
```

------------------------------------------------------------------------

# 17. Terminal Output

Full mode:

``` text
VRAMON-32M-GAUGE

RAM  [████████████████░░░░]  82.3% free
VRAM [██████████░░░░░░░░░░]  51.7% free

GPU  [████████░░░░░░░░░░░░]  42%
STATUS: HEALTHY
```

Compact mode:

``` text
RAM ▰▰▰▰▰▰▰▱▱▱ 82%
VRAM ▰▰▰▰▰▱▱▱▱▱ 52%
```

------------------------------------------------------------------------

# 18. Live Mode

Command:

``` bash
vramon --watch
```

Default refresh:

``` text
2 seconds
```

Implementation:

``` bash
while true; do
    clear
    render_status
    sleep "$INTERVAL"
done
```

A more efficient terminal redraw can use:

``` bash
printf '\033[H'
printf '\033[K'
```

and redraw only the required lines.

For a full screen dashboard, clear once:

``` bash
printf '\033[2J\033[H'
```

Then move the cursor home on each iteration:

``` bash
printf '\033[H'
```

------------------------------------------------------------------------

# 19. tmux Mode

Command:

``` bash
vramon --tmux
```

Output:

``` text
RAM 82% | VRAM 52%
```

Example `tmux.conf`:

``` tmux
set -g status-right '#(vramon --tmux)'
set -g status-interval 2
```

Important:

The script must produce only one line in tmux mode.

No ANSI cursor movement should be emitted.

------------------------------------------------------------------------

# 20. CLI Interface

The main command should support:

``` text
vramon
vramon --once
vramon --watch
vramon --tmux
vramon --json
vramon --no-color
vramon --width 20
vramon --interval 2
vramon --help
vramon --version
```

Suggested behavior:

``` text
--once       Print one snapshot and exit
--watch      Continuously monitor
--tmux       Compact one-line output
--json       Machine-readable output
--no-color   Disable ANSI colors
--width N    Gauge width
--interval N Refresh interval
--help       Show help
--version    Show version
```

------------------------------------------------------------------------

# 21. JSON Output

Command:

``` bash
vramon --json
```

Output:

``` json
{
  "ram": {
    "total": 17179869184,
    "used": 8589934592,
    "available": 8589934592,
    "headroom_percent": 50.0
  },
  "vram": {
    "available": true,
    "total": 8589934592,
    "used": 4294967296,
    "free": 4294967296,
    "headroom_percent": 50.0
  },
  "gpu": {
    "available": true,
    "utilization_percent": 42
  },
  "overall_headroom_percent": 50.0
}
```

Do not depend on `jq` for the basic implementation. JSON should be
constructed with `printf`.

------------------------------------------------------------------------

# 22. Configuration

Configuration file:

``` text
~/.config/vramon/config
```

Example:

``` bash
VRAMON_INTERVAL=2
VRAMON_WIDTH=20
VRAMON_WARN=30
VRAMON_CRITICAL=10
VRAMON_COLOR=1
```

Optional project-local configuration:

``` text
.vramonrc
```

Configuration precedence:

``` text
Built-in defaults
        ↓
Global config
        ↓
Project config
        ↓
Environment variables
        ↓
CLI arguments
```

------------------------------------------------------------------------

# 23. Main Execution Flow

The main `bin/vramon` script should follow:

``` text
START
  |
  v
Load configuration
  |
  v
Parse CLI arguments
  |
  v
Detect operating system
  |
  v
Collect RAM
  |
  v
Detect GPU backend
  |
  +---- NVIDIA ---> nvidia-smi
  |
  +---- AMD ------> rocm-smi
  |
  +---- None -----> RAM-only mode
  |
  v
Normalize metrics
  |
  v
Calculate percentages
  |
  v
Determine state
  |
  v
Render output
  |
  +---- once -----> EXIT
  |
  +---- tmux -----> one line
  |
  +---- watch ----> sleep -> repeat
```

------------------------------------------------------------------------

# 24. Error Handling

The tool must not terminate just because GPU monitoring is unavailable.

Bad:

``` bash
nvidia-smi || exit 1
```

Preferred:

``` bash
if nvidia_gpu; then
    HAS_VRAM=1
else
    HAS_VRAM=0
fi
```

Then:

``` text
VRAM: N/A
```

The RAM monitor should continue.

------------------------------------------------------------------------

# 25. Exit Codes

Use predictable exit codes:

``` text
0 = success
1 = general error
2 = invalid command-line argument
3 = unsupported platform
4 = configuration error
5 = collector error
```

GPU absence should NOT be treated as a fatal error.

------------------------------------------------------------------------

# 26. Signal Handling

The live monitor should clean up when interrupted.

``` bash
cleanup() {
    printf '\033[0m'
    printf '\033[?25h'
}

trap cleanup EXIT INT TERM
```

Hide cursor:

``` bash
printf '\033[?25l'
```

Show cursor:

``` bash
printf '\033[?25h'
```

This prevents the terminal from looking broken after:

``` text
Ctrl+C
```

------------------------------------------------------------------------

# 27. Shell Safety

Every executable script should start with:

``` bash
#!/usr/bin/env bash
```

For production scripts:

``` bash
set -Eeuo pipefail
```

However, avoid letting optional GPU collectors terminate the entire
program.

Use controlled error handling:

``` bash
if ! gpu_collect; then
    HAS_VRAM=0
fi
```

Always quote variables:

``` bash
"$value"
```

Do not use:

``` bash
$value
```

when word splitting could occur.

------------------------------------------------------------------------

# 28. Testing Strategy

Tests should not require a real GPU.

Use fixtures.

Example NVIDIA fixture:

``` text
8192, 3012, 5180, 42
```

Test:

``` text
total = 8192 MiB
used  = 3012 MiB
free  = 5180 MiB
util  = 42%
```

Expected VRAM headroom:

``` text
63.2%
```

------------------------------------------------------------------------

# 29. RAM Test Cases

Test cases:

``` text
100% available
50% available
30% available
10% available
9.9% available
0% available
```

Expected state:

``` text
> 30       GREEN
10 - 30    YELLOW
< 10       RED
```

Boundary tests are important.

------------------------------------------------------------------------

# 30. Renderer Tests

Input:

``` text
100
50
0
```

Expected:

``` text
[████████████████████]
[██████████░░░░░░░░░░]
[░░░░░░░░░░░░░░░░░░░░]
```

The renderer must never produce a negative number of empty characters.

Clamp:

``` bash
filled=$(( filled < 0 ? 0 : filled ))
filled=$(( filled > width ? width : filled ))
```

------------------------------------------------------------------------

# 31. Performance Requirements

VRAMON is intended to be extremely lightweight.

Target:

``` text
CPU usage: negligible
Memory: < 10 MB process footprint
Refresh: configurable
Dependencies: system utilities only
```

Do not spawn unnecessary processes inside tight loops.

For example, avoid repeatedly calling:

``` bash
grep | sed | awk | cut | tr
```

when one `awk` process can perform the parsing.

------------------------------------------------------------------------

# 32. Security Considerations

VRAMON is a local read-only monitoring utility.

It should:

-   Never require root
-   Never modify GPU settings
-   Never modify system memory
-   Never send telemetry
-   Never upload metrics
-   Never execute arbitrary configuration commands
-   Never require network access

Configuration files should only contain simple variable assignments.

Do not implement:

``` bash
eval "$USER_CONFIG"
```

Use controlled parsing instead.

------------------------------------------------------------------------

# 33. Installation

Recommended installation path:

``` text
~/.local/bin/vramon
```

Install command:

``` bash
./install.sh
```

The installer should:

1.  Create `~/.local/bin`
2.  Copy the executable
3.  Copy library files
4.  Mark scripts executable
5.  Verify dependencies
6.  Print PATH instructions if necessary

Example:

``` bash
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/vramon"
```

------------------------------------------------------------------------

# 34. Uninstallation

``` bash
./uninstall.sh
```

Remove:

``` text
~/.local/bin/vramon
~/.local/share/vramon
```

Do not automatically delete:

``` text
~/.config/vramon
```

unless the user explicitly asks for configuration removal.

------------------------------------------------------------------------

# 35. Makefile

Suggested commands:

``` text
make install
make uninstall
make test
make lint
make run
make watch
make tmux
```

Example:

``` makefile
install:
    ./install.sh

uninstall:
    ./uninstall.sh

test:
    ./tests/test_memory.sh
    ./tests/test_metrics.sh
    ./tests/test_renderer.sh

run:
    ./bin/vramon --once

watch:
    ./bin/vramon --watch

tmux:
    ./bin/vramon --tmux
```

------------------------------------------------------------------------

# 36. Shell Linting

Use:

``` bash
shellcheck bin/vramon
shellcheck lib/*.sh
shellcheck tests/*.sh
```

Formatting:

``` bash
shfmt -w bin lib tests
```

These should be optional development dependencies, not runtime
dependencies.

------------------------------------------------------------------------

# 37. Development Milestones

## Phase 1 --- Skeleton

Create:

``` text
bin/
lib/
tests/
examples/
docs/
```

Implement:

``` bash
vramon --help
vramon --version
```

------------------------------------------------------------------------

## Phase 2 --- Linux RAM

Implement:

``` bash
free -b
```

Output:

``` text
RAM [████████████░░░░░░░░] 62%
```

------------------------------------------------------------------------

## Phase 3 --- NVIDIA

Implement:

``` bash
nvidia-smi
```

Output:

``` text
RAM 62%
VRAM 47%
GPU 38%
```

------------------------------------------------------------------------

## Phase 4 --- Renderer

Add:

``` text
GREEN
YELLOW
RED
```

and configurable gauge width.

------------------------------------------------------------------------

## Phase 5 --- Live Monitor

Implement:

``` bash
vramon --watch
```

Add ANSI cursor handling.

------------------------------------------------------------------------

## Phase 6 --- tmux

Implement:

``` bash
vramon --tmux
```

Then add:

``` tmux
set -g status-right '#(vramon --tmux)'
```

------------------------------------------------------------------------

## Phase 7 --- macOS

Implement:

``` bash
vm_stat
sysctl
```

Make RAM monitoring portable.

------------------------------------------------------------------------

## Phase 8 --- AMD

Implement:

``` bash
rocm-smi
```

Normalize AMD output to the same internal metric structure.

------------------------------------------------------------------------

## Phase 9 --- JSON

Implement:

``` bash
vramon --json
```

This makes VRAMON usable by other tools.

------------------------------------------------------------------------

## Phase 10 --- Testing

Add fixture-based tests.

No test should require:

-   NVIDIA GPU
-   AMD GPU
-   root access
-   internet

------------------------------------------------------------------------

## Phase 11 --- Packaging

Create:

``` text
install.sh
uninstall.sh
Makefile
README.md
LICENSE
```

------------------------------------------------------------------------

# 38. Versioning

Start:

``` text
VRAMON-32M-GAUGE v0.1.0
```

Suggested progression:

``` text
0.1.0  Linux RAM
0.2.0  NVIDIA VRAM
0.3.0  Live mode
0.4.0  tmux integration
0.5.0  macOS
0.6.0  AMD
0.7.0  JSON
0.8.0  Tests
0.9.0  Packaging
1.0.0  Stable release
```

------------------------------------------------------------------------

# 39. Future Features

Potential v2 features:

``` text
CPU temperature
CPU utilization
GPU temperature
GPU power consumption
Swap usage
Disk usage
Load average
Network throughput
Battery health
Process-level memory usage
Top memory-consuming processes
OOM-risk warnings
Historical sparklines
Threshold notifications
Desktop notifications
Custom themes
```

Possible future output:

``` text
VRAMON-32M-GAUGE

RAM   █████████████░░░░░░░  65%
VRAM  ██████████░░░░░░░░░░  51%
GPU   ███████░░░░░░░░░░░░░  37%
TEMP  ████████░░░░░░░░░░░░  42°C

STATUS: OK
```

------------------------------------------------------------------------

# 40. Architecture for Future Expansion

Keep collectors independent.

``` text
Collectors
    |
    +-- linux_memory
    +-- macos_memory
    +-- nvidia_gpu
    +-- amd_gpu
    +-- cpu
    +-- temperature
    |
    v
Normalized Metrics
    |
    v
Decision Layer
    |
    v
Renderers
    |
    +-- terminal
    +-- compact
    +-- tmux
    +-- json
```

This is important because the project can eventually become a
general-purpose shell resource-monitoring framework instead of being
tied exclusively to VRAM.

------------------------------------------------------------------------

# 41. Suggested Internal API

Collectors should expose variables:

``` bash
RAM_TOTAL
RAM_USED
RAM_FREE

VRAM_AVAILABLE
VRAM_TOTAL
VRAM_USED
VRAM_FREE

GPU_AVAILABLE
GPU_UTIL
```

Metrics layer:

``` bash
RAM_HEADROOM
VRAM_HEADROOM
OVERALL_HEADROOM
MEMORY_STATE
```

Renderer:

``` bash
render_full
render_compact
render_tmux
render_json
```

This keeps responsibilities clean.

------------------------------------------------------------------------

# 42. Example Complete User Experience

Run:

``` bash
vramon
```

Output:

``` text
VRAMON-32M-GAUGE
Visual Resource Monitoring for RAM & VRAM

RAM  [████████████████░░░░]  81.4% free
VRAM [███████████░░░░░░░░░]  56.2% free
GPU  [███████░░░░░░░░░░░░░]  37% used

STATUS: HEALTHY
```

Run:

``` bash
vramon --watch
```

The dashboard updates every two seconds.

Run:

``` bash
vramon --tmux
```

Output:

``` text
RAM 81% | VRAM 56%
```

Run:

``` bash
vramon --json
```

Output:

``` json
{"ram_headroom":81.4,"vram_headroom":56.2,"gpu_util":37,"status":"healthy"}
```

------------------------------------------------------------------------

# 43. Definition of Done

VRAMON-32M-GAUGE is considered version 1.0 complete when:

-   [ ] Linux RAM monitoring works
-   [ ] NVIDIA VRAM monitoring works
-   [ ] macOS RAM monitoring works
-   [ ] AMD collector works where `rocm-smi` provides the required
    metrics
-   [ ] GPU absence does not crash the program
-   [ ] Gauge renders correctly
-   [ ] Color thresholds work
-   [ ] Live mode works
-   [ ] tmux mode works
-   [ ] JSON mode works
-   [ ] CLI arguments work
-   [ ] Configuration works
-   [ ] Ctrl+C restores terminal state
-   [ ] ShellCheck passes
-   [ ] Unit tests pass without physical GPU hardware
-   [ ] Installation script works
-   [ ] Uninstallation script works
-   [ ] README contains usage examples
-   [ ] No root privileges are required
-   [ ] No network connection is required
-   [ ] No telemetry is collected

------------------------------------------------------------------------

# 44. Recommended First Implementation Order

Do NOT start by implementing every platform.

Build the smallest working version first:

``` text
STEP 1
bash executable
        ↓
STEP 2
Linux `free`
        ↓
STEP 3
RAM percentage
        ↓
STEP 4
ASCII/Unicode gauge
        ↓
STEP 5
ANSI colors
        ↓
STEP 6
NVIDIA `nvidia-smi`
        ↓
STEP 7
Live refresh
        ↓
STEP 8
tmux output
        ↓
STEP 9
macOS support
        ↓
STEP 10
AMD support
        ↓
STEP 11
JSON
        ↓
STEP 12
Tests + packaging
```

This prevents the project from becoming a giant shell script before the
core monitoring loop is proven.

------------------------------------------------------------------------

# 45. Final Project Identity

## VRAMON-32M-GAUGE

**Visual Resource Monitoring for RAM & VRAM**

A tiny, dependency-light terminal resource monitor that transforms raw
memory statistics into an immediately readable visual gauge.

The design philosophy is:

``` text
Collect → Normalize → Calculate → Render
```

The project should feel like a small Unix utility rather than a
conventional application.

The ultimate command should be as simple as:

``` bash
vramon
```

and the terminal should immediately tell the user:

``` text
How much RAM do I have?
How much VRAM do I have?
How much GPU is being used?
How much resource headroom remains?
Am I approaching a dangerous threshold?
```

**Project codename:** `VRAMON-32M-GAUGE`

**Initial release:** `v0.1.0`

**Primary language:** Bash

**License recommendation:** MIT
