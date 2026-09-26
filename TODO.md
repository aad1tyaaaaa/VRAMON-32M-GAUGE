# VRAMON-32M-GAUGE - Remaining Work

Everything from [project.md](project.md) is implemented and passes the test
suite (142 tests) and ShellCheck. However, development so far happened on
Windows (Git Bash) using fixture/stub commands only. The items below are
**not yet verified or not yet done**.

## 1. Verification on real systems

- [ ] Run on a real **Linux** machine (`free -b`, `/proc/meminfo` fallback)
- [ ] Run on a real **macOS** machine (`vm_stat`, `sysctl hw.memsize`)
- [ ] Run with the stock macOS **Bash 3.2** (`/bin/bash`) to confirm compatibility
- [ ] Run on a machine with an **NVIDIA GPU** (`nvidia-smi`)
- [ ] Run on a machine with an **AMD GPU** (`rocm-smi`); output varies across
      ROCm versions and only one fixture format is covered
- [ ] Confirm `mawk` (Debian/Ubuntu default) and BSD `awk` (macOS) parse identically

## 2. Interactive behavior

- [ ] Manually test `vramon --watch` in a real terminal (redraw, no flicker)
- [ ] Confirm Ctrl+C / `SIGTERM` restores the cursor and colors
- [ ] Test `#(vramon --tmux)` inside a real tmux status bar

## 3. Tooling not yet exercised

- [ ] `make test`, `make lint`, `make fmt`, `make run` (no `make` on the dev machine)
- [ ] Run `shfmt` and commit any formatting changes
- [ ] Run `./install.sh` / `./uninstall.sh` on Linux and macOS (only tested
      under Git Bash with a temporary `PREFIX`)

## 4. Repository housekeeping

- [ ] Set executable bits in git (Windows does not preserve them):
      `git add --chmod=+x bin/vramon install.sh uninstall.sh tests/*.sh`
- [ ] Make the initial commit (all files are currently untracked)
- [ ] Tick the **Definition of Done** checklist in [project.md](project.md) once
      the items above are verified

## 5. Known gaps / improvements

- [ ] **CI:** add a GitHub Actions workflow running tests, ShellCheck and shfmt
      on `ubuntu-latest` and `macos-latest`
- [ ] **GPU command timeout:** a hung `nvidia-smi`/`rocm-smi` (broken driver)
      would block `vramon`, and tmux would keep spawning new instances
- [ ] **Watch-mode test coverage:** no automated test for the ANSI redraw loop
- [ ] **README badges** (version, tests, ShellCheck) are static and must be
      updated by hand, or replaced with CI-driven badges

## 6. Spec ambiguities resolved by choice

`project.md` shows conflicting examples in a few places. Current choices:

| Area    | Chosen format                         | Alternative in spec     |
| ------- | ------------------------------------- | ----------------------- |
| tmux    | `RAM 82% \| VRAM 52%` (section 19)    | `RAM:61% VRAM:51%` (§5) |
| Compact | Separate RAM / VRAM lines (section 17) | Single `MEM ▰▰▰` line (§5) |
| JSON    | Nested document (section 21)          | Flat object (§42)       |

Revisit if a different format is preferred.
