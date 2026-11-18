# Installing this Arabic/RTL Ghostty fork

Platform support matches Ghostty itself:

| Platform | Status | How to install |
| --- | --- | --- |
| Linux (x86_64, GTK4) | ✅ Ready build | release `.tar.zst` + `install-system.sh` |
| macOS (Apple Silicon) | ✅ Built in CI | release `.zip` (unsigned) |
| Windows | ❌ Not supported by Ghostty | use WSL2 (see below) |

The releases are on
<https://github.com/HMH-3080/ghostty/releases>.

---

## Linux (x86_64)

Requirements: GTK4, libadwaita, FriBidi and their runtime dependencies
(test done on Arch Linux). The installer copies everything to `/usr/local`.

> [!NOTE]
> Use a **monospaced** Arabic font. A proportional font such as
> `IBM Plex Sans Arabic` forced with `font-codepoint-map` will look distorted
> because the terminal grid has fixed cell widths. `CaskaydiaMono Nerd Font
> Mono` already contains Arabic glyphs and works out of the box.

```sh
tar --zstd -xf ghostty-1.3.2-rtl.5-linux-x86_64.tar.zst
cd ghostty-1.3.2-rtl.5-linux-x86_64
sudo bash install-system.sh "$PWD"
```

What `install-system.sh` does:

- installs the binary to `/usr/local/bin/ghostty`;
- installs resources (themes, shell integration, terminfo, icons, desktop
  entry, D-Bus/systemd activation units) under `/usr/local/share`;
- if the distro `ghostty` package is installed, stops and removes it first
  (there must be only one Ghostty);
- removes a previous `~/.local` Ghostty install for the invoking user;
- makes the desktop icon launch the binary directly (works with
  dbus-broker, which only scans service files at session start).

To make this fork the default terminal:

```sh
mkdir -p ~/.config
printf 'com.mitchellh.ghostty.desktop\n' > ~/.config/xdg-terminals.list
```

## macOS (Apple Silicon)

The macOS asset is **unsigned** (ad-hoc signed only). After downloading:

```sh
unzip Ghostty-rtl-<tag>-macos-arm64.zip
mv Ghostty.app /Applications/
xattr -dr com.apple.quarantine /Applications/Ghostty.app
open /Applications/Ghostty.app
```

If macOS still refuses to open it, right-click the app → **Open** → **Open**
once, or allow it in System Settings → Privacy & Security.

The build requires the same RTL/fribidi support: the shared Zig core uses
FriBidi when built with `-Dfribidi=true` (already set in CI).

## Windows

**Ghostty does not support Windows natively** — the upstream project has no
Windows application backend. This fork cannot change that, so there is no
`.exe`/`.msi` build. (Only the portable `libghostty-vt` library can target
Windows/WASM; that is not a terminal.)

The practical options on Windows:

1. **WSL2 + WSLg** (recommended): install a Linux distro, then follow the
   Linux instructions inside WSL. WSLg shows the GTK window on your Windows
   desktop.
2. SSH into a Linux/macOS machine and run Ghostty there.
3. Use another terminal on Windows (Windows Terminal, WezTerm, etc.) until
   Windows support exists upstream.

## Build from source

Linux (Arch package names):

```sh
sudo pacman -S --needed base-devel zig0.15 gtk4 libadwaita blueprint-compiler \
  fribidi harfbuzz fontconfig
zig build -Doptimize=ReleaseFast -Dfribidi=true
sudo bash install-system.sh "$PWD/zig-out"
```

macOS (Xcode 26 + macOS 26 SDK, Metal toolchain):

```sh
brew install zig@0.15 fribidi
zig build -Doptimize=ReleaseFast -Dfribidi=true
# app bundle: macos/build/ReleaseLocal/Ghostty.app
```

Or use the wrapper that also installs on Linux:

```sh
./rebuild.sh
```

## Recommended config

See [FORK_NOTES.md](../FORK_NOTES.md) for fonts, TokyoNight colors and the
Windows Terminal-style keybindings.

## Known limitations (inherited from the RTL fork)

- Mouse selection in RTL text is imperfect.
- Some Arabic diacritics (tashkeel) can detach from the base letter.

## ملخص بالعربية

- **لينكس:** نزّل ملف `.tar.zst` من صفحة الإصدارات، فك الضغط، ثم
  `sudo bash install-system.sh "$PWD"`.
- **ماك (Apple Silicon):** نزّل `.zip`، انقل `Ghostty.app` إلى
  `/Applications`، ثم `xattr -dr com.apple.quarantine /Applications/Ghostty.app`.
- **ويندوز:** غير مدعوم أصلاً في Ghostty — استخدم WSL2 مع WSLg.
- **الترخيص:** MIT، مع نسبة الفضل لفورك `commandlinetips/ghostty` وأصل
  `ghostty-org/ghostty`.
