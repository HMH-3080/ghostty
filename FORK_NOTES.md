# Ghostty — Arabic/RTL fork notes

This repository is a fork of **[commandlinetips/ghostty](https://github.com/commandlinetips/ghostty)**,
which itself forks **[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)**.
It provides Arabic/Hebrew **RTL text shaping** using FriBidi (not yet merged
upstream — see ghostty-org discussion #9774).

All credit for the RTL work goes to the `commandlinetips` fork author.

## Changes in this fork (on top of `commandlinetips/ghostty`)

1. **Build fix for Zig 0.15.2 on modern glibc (Arch/GCC 16)**:
   Zig's self-hosted linker fails with

   ```
   fatal linker error: unhandled relocation type R_X86_64_PC64
   note: in .../crt1.o:.sframe
   ```

   Fixed by building the two host tools (`gtk_blueprint_compiler` and
   `ghostty-build-data`) with the LLVM backend (`.use_llvm = true`).
2. **Helper scripts**:
   - `rebuild.sh` — build and install in one step.
   - `install-system.sh` — install to `/usr/local` (Arch-oriented), removing
     any distro/user-local copy and making the desktop icon launch the binary
     directly (dbus-broker only loads service files at session start).

## Building

Requirements (Arch package names):

```
zig 0.15.2  blueprint-compiler  gtk4  libadwaita  fribidi
harfbuzz  fontconfig  pkgconf  gettext
```

Then:

```sh
zig build -Doptimize=ReleaseFast -Dfribidi=true
sudo bash install-system.sh ./zig-out
```

Or simply:

```sh
./rebuild.sh
```

## Releases

Ready-made builds are attached to
[GitHub Releases](https://github.com/HMH-3080/ghostty/releases):

- Linux x86_64: `.tar.zst` + `install-system.sh`
- macOS Apple Silicon: unsigned `.zip` app bundle (built in CI)
- Windows: not supported by Ghostty; use WSL2 + WSLg
  (see [docs/INSTALL.md](docs/INSTALL.md))

Install instructions: [docs/INSTALL.md](docs/INSTALL.md).
Release checklist: [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md).

## Recommended configuration

A monospaced font that covers Arabic well, with TokyoNight colors:

```ini
font-family = "CaskaydiaMono Nerd Font Mono"
font-family = "IBM Plex Sans Arabic"
font-size = 14

background = #1a1b26
foreground = #c0caf5
cursor-color = #c0caf5
cursor-text = #15161e
selection-background = #33467c
selection-foreground = #c0caf5
```

The full TokyoNight palette and Windows Terminal-style keybinds are in the
maintainer's dotfiles (adapt freely; `Ctrl+C` is left as SIGINT).

## Known limitations (inherited from the RTL fork)

- Mouse selection in RTL text is still imperfect.
- Some Arabic diacritics (tashkeel) can detach from their base letter.

## License

MIT — see [LICENSE](LICENSE). This fork keeps the original copyright notices.
