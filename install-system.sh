#!/usr/bin/env bash
# Install the patched (Arabic/RTL) Ghostty system-wide under /usr/local and
# remove any other installed copy (distro package + user-local install).
#
# Arch Linux oriented: it removes the distro `ghostty` package, installs
# terminfo into /usr/share/terminfo, and refreshes desktop/icon caches.
#
# Usage: sudo bash install-system.sh [BUILD_DIR]
#   BUILD_DIR defaults to <this repo>/zig-out
set -euo pipefail

BUILD_DIR="${1:-$HOME/IdeaProjects/ghostty-rtl/zig-out}"
PREFIX=/usr/local
USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
  echo "Run with sudo from your normal user account: sudo bash install-system.sh"
  exit 1
fi
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"

[ "$(id -u)" -eq 0 ] || { echo "Run me with sudo."; exit 1; }
[ -x "$BUILD_DIR/bin/ghostty" ] || { echo "Missing build at $BUILD_DIR"; exit 1; }

echo "==> Preserving man pages from the distro package"
MAN1_TMP="$(mktemp)"; MAN5_TMP="$(mktemp)"
if [ -f /usr/share/man/man1/ghostty.1.gz ]; then cp /usr/share/man/man1/ghostty.1.gz "$MAN1_TMP"; fi
if [ -f /usr/share/man/man5/ghostty.5.gz ]; then cp /usr/share/man/man5/ghostty.5.gz "$MAN5_TMP"; fi

echo "==> Removing the distro ghostty package (no dependents)"
if command -v pacman >/dev/null 2>&1 && pacman -Q ghostty >/dev/null 2>&1; then
  runuser -u "$USER_NAME" -- systemctl --user stop app-com.mitchellh.ghostty.service 2>/dev/null || true
  pacman -R --noconfirm ghostty
fi

echo "==> Installing patched Ghostty to $PREFIX"
install -Dm755 "$BUILD_DIR/bin/ghostty" "$PREFIX/bin/ghostty"

# Copy resources (themes, shell integration, completions, icons, desktop entry,
# dbus/systemd activation units, terminfo) and fix build-time absolute paths.
cp -a "$BUILD_DIR/share/." "$PREFIX/share/"
while IFS= read -r f; do
  sed -i "s|$BUILD_DIR/bin/ghostty|$PREFIX/bin/ghostty|g" "$f"
done < <(grep -rl "$BUILD_DIR/bin/ghostty" "$PREFIX/share" 2>/dev/null || true)

# dbus-broker only reads service files at session start, so the freshly
# installed D-Bus name is not activatable until the next login. Make the
# desktop entry launch the binary directly so app-icon clicks always work.
DESKTOP_FILE="$PREFIX/share/applications/com.mitchellh.ghostty.desktop"
if [ -f "$DESKTOP_FILE" ]; then
  sed -i 's/^DBusActivatable=true$/DBusActivatable=false/' "$DESKTOP_FILE"
fi

# ncurses on Arch does not look in /usr/local/share/terminfo; install the
# entries into the system terminfo DB as well (unowned by any package).
echo "==> Installing terminfo entries system-wide"
install -d /usr/share/terminfo/g /usr/share/terminfo/x
install -m644 "$BUILD_DIR/share/terminfo/g/ghostty" /usr/share/terminfo/g/ghostty
install -m644 "$BUILD_DIR/share/terminfo/x/xterm-ghostty" /usr/share/terminfo/x/xterm-ghostty

echo "==> Installing man pages to $PREFIX/share/man"
if [ -s "$MAN1_TMP" ]; then install -Dm644 "$MAN1_TMP" "$PREFIX/share/man/man1/ghostty.1.gz"; fi
if [ -s "$MAN5_TMP" ]; then install -Dm644 "$MAN5_TMP" "$PREFIX/share/man/man5/ghostty.5.gz"; fi
rm -f "$MAN1_TMP" "$MAN5_TMP"

echo "==> Removing the user-local duplicate install"
rm -f  "$USER_HOME/.local/bin/ghostty"
rm -rf "$USER_HOME/.local/share/ghostty"
rm -f  "$USER_HOME/.local/share/terminfo/g/ghostty"
rm -f  "$USER_HOME/.local/share/terminfo/x/xterm-ghostty"
rm -f  "$USER_HOME/.local/share/applications/com.mitchellh.ghostty.desktop"

echo "==> Refreshing caches"
update-desktop-database "$PREFIX/share/applications" >/dev/null 2>&1 || true
gtk-update-icon-cache -f -t "$PREFIX/share/icons/hicolor" >/dev/null 2>&1 || true
dbus-send --session --type=method_call --dest=org.freedesktop.DBus \
  / org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
runuser -u "$USER_NAME" -- systemctl --user daemon-reload 2>/dev/null || true

echo "==> Verifying"
"$PREFIX/bin/ghostty" +version | head -1
echo "Done."
