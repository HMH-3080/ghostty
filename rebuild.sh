#!/usr/bin/env bash
# Rebuild the Arabic/RTL Ghostty fork and install it system-wide under
# /usr/local (replacing the previous /usr/local install in place).
#
# Requirements:
#   - Zig 0.15.2 (`zig` in PATH)
#   - blueprint-compiler (`blueprint-compiler` in PATH)
#   - system FriBidi, GTK4, libadwaita and the usual Ghostty build deps
#
# Running Ghostty windows keep working during the update; restart Ghostty
# (or let the single-instance server exit) to pick up the new binary.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Common local toolchain locations (mise / a dedicated venv) are used when
# present; otherwise rely on PATH.
if [ -d "$HOME/.local/share/bp-venv/bin" ]; then
  PATH="$HOME/.local/share/bp-venv/bin:$PATH"
fi
if [ -d "$HOME/.local/share/mise/installs/zig/0.15.2/bin" ]; then
  PATH="$HOME/.local/share/mise/installs/zig/0.15.2/bin:$PATH"
fi
export PATH

cd "$SRC_DIR"

zig version
zig build -Doptimize=ReleaseFast -Dfribidi=true

exec sudo bash "$SRC_DIR/install-system.sh" "$SRC_DIR/zig-out"
