# Release process

This fork publishes GitHub releases with ready-to-run builds.

## Versioning

Tags look like `v1.3.2-rtl.3`:

- `1.3.2` — upstream Ghostty base version (`1.3.2-dev` in `build.zig.zon`);
- `rtl.N` — fork release counter.

## What a release contains

| Asset | Built by | Notes |
| --- | --- | --- |
| `ghostty-<ver>-linux-x86_64.tar.zst` | maintainer machine | `zig build -Doptimize=ReleaseFast -Dfribidi=true` |
| `SHA256SUMS-linux.txt` | maintainer machine | `sha256sum` |
| `Ghostty-rtl-<tag>-macos-arm64.zip` | GitHub Actions | `.github/workflows/release-macos.yml` |
| `SHA256SUMS-macos.txt` | GitHub Actions | generated in the workflow |
| source zip/tar.gz | GitHub | automatic from the tag |

Windows is intentionally absent: Ghostty has no Windows backend. The install
docs explain the WSL2 route.

## Step by step

1. **Bump/commit everything** on `main` (code, docs, workflow).

2. **Build Linux locally:**

   ```sh
   ./rebuild.sh          # builds into zig-out/ and installs on this machine
   ```

3. **Package the Linux asset:**

   ```sh
   TAG=v1.3.2-rtl.3
   STAGE="ghostty-1.3.2-rtl.1-linux-x86_64"
   rm -rf "/tmp/$STAGE" && mkdir -p "/tmp/$STAGE"
   cp -a zig-out/bin zig-out/share "/tmp/$STAGE/"
   cp install-system.sh "/tmp/$STAGE/"
   tar -C /tmp -I 'zstd -19 -T0' -cf "$STAGE.tar.zst" "$STAGE"
   sha256sum "$STAGE.tar.zst" > SHA256SUMS-linux.txt
   ```

4. **Push the workflow** to `main` before publishing (release events run the
   workflow from the default branch):

   ```sh
   git push origin main
   ```

5. **Create the release** (this also creates the tag at the current commit):

   ```sh
   gh release create "$TAG" \
     --title "Ghostty 1.3.2 RTL (Arabic) — Linux & macOS" \
     --notes-file docs/RELEASE_NOTES.md \
     --latest \
     "$STAGE.tar.zst" SHA256SUMS-linux.txt
   ```

6. **Watch the macOS job** and confirm the asset is attached:

   ```sh
   gh run list --workflow release-macos.yml
   gh release view "$TAG"
   ```

   If the macOS job fails, fix the workflow, commit, push to `main`, then
   re-run it against the existing release:

   ```sh
   gh workflow run release-macos.yml -f tag="$TAG"
   ```

7. **Smoke test the assets** on a clean machine where possible:
   extract the tarball, run `sudo bash install-system.sh "$PWD"`,
   launch Ghostty, check Arabic text and `ghostty +version`.

## macOS notes

- Runner: `macos-26-arm64` (Apple Silicon). `macos-26` is Intel; the Icon
  Composer (`.icon`) asset also requires the macOS 26 toolchain.
- Xcode 26 is selected automatically when present; the project requires the
  macOS 26 SDK and the Metal toolchain.
- Zig 0.15 is installed from Homebrew (`zig@0.15`) because it contains the
  Xcode 26.4 linker workaround.
- `-Doptimize=ReleaseFast` maps to the Xcode `ReleaseLocal` configuration, so
  the bundle is at `macos/build/ReleaseLocal/Ghostty.app`.
- The app is **ad-hoc signed** (`codesign -s -`). It is not notarized, so
  users must clear the quarantine attribute (documented).

## Updating from upstream

```sh
git fetch upstream
git merge upstream/main
```

Resolve conflicts in `src/build/GhosttyResources.zig` and
`src/build/SharedDeps.zig` (the `.use_llvm = true` lines). Then repeat the
release steps with a new `rtl.N` tag.
