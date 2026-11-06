---
schema_version: 1
name: telluride-release-pipeline
description: Release a new Telluride build (FrostWire's yt-dlp wrapper) end to end — update the Python tooling with configure_update.sh, bump BUILD in telluride.py, test from source against real sites, build/sign/notarize the binary per platform, changelog, tag and draft GitHub release, attach binaries from each machine, publish, then move FrostWire's telluride submodule to the tag. Use when asked to "release telluride build N", "update telluride", "bump yt-dlp in telluride", or to sync the FrostWire submodule to a new Telluride build.
tags: [frostwire, telluride, yt-dlp, release, pyinstaller, notarization, github-releases]
triggers: [telluride release, release telluride, telluride build, update telluride, bump yt-dlp, sync telluride submodule]
---

# telluride-release-pipeline

**Pipeline:** pull → `configure_update.sh` → bump `BUILD` → tests, pylint and live smoke tests from source → changelog → commit and push → `build.sh` on each platform (sign + notarize on macOS) → smoke-test each binary → tag `telluride-build-N` → draft GitHub release with the binaries → maintainer attaches the remaining platforms and publishes → move FrostWire's `telluride` submodule to the tag, with a changelog line in FrostWire.

Binaries are built on physical machines: macOS arm64 and x86_64 on Macs, Windows on a Windows PC, Linux (x86_64 and arm64) in Docker (`docker_build_binaries.sh --platform=linux/<arch>`, never on a host Ubuntu). An agent on one machine builds that machine's binary only, creates the release as a **draft**, and leaves publishing to the maintainer once every binary is attached.

## 1. Update and bump

1. `git pull` first: the remote often has Dockerfile or `configure_update.sh` changes.
2. Record the versions before (`python3 -m pip show pip astroid pylint yt_dlp pyinstaller pyinstaller-hooks-contrib`), run `./configure_update.sh` (upgrades pip, pylint, yt-dlp and PyInstaller in the build machine's Python), record the versions after. The changelog lists old → new for each changed tool; take "old" from the previous changelog entry when it recorded one.
3. `BUILD = N` in `telluride.py` (the banner prints it; FrostWire's `TellurideBuild` parses it).

## 2. Verify from source

- `python3 -m unittest -q test_telluride` and `python3 -m pylint --max-line-length=350 telluride.py` (10.00/10).
- Live smoke tests, the real gate, since yt-dlp's value is tracking site changes:
  - `python3 telluride.py -m <youtube watch url>`: JSON with a title and formats;
  - `python3 telluride.py <short youtube video>` in a scratch directory: downloads and merges without HTTP 403;
  - `python3 telluride.py -p https://www.youtube.com/@frostwire`: JSON entries;
  - `-m` on a SoundCloud track.
- A site that now needs login (e.g. Vimeo) is an upstream limitation: note it in the release, don't block on it.

## 3. Changelog, commit, push

Top of `changelog.txt`: `build N - mon/dd/yyyy`, then ` - tool old -> new` lines and any behavior change. Commit `build N: yt-dlp <version>`; push to `origin master`.

## 4. Build, sign, notarize (per machine)

- `printf '\n' | ./build.sh` (it pauses after pylint). Windows/Linux keep PyInstaller `--onefile` and it moves the binary to `telluride_<os>.<arch>` (or `telluride.exe`), signed with `sign.bat`. macOS uses `--onedir` instead (a `--onefile` binary re-extracts into a fresh temp folder and macOS re-validates every Mach-O on every launch, ~8s): it moves the bundle to `telluride_macos.<arch>.dir/`, compiles the native launcher (`launcher.c`) to `telluride_macos.<arch>` — the file FrostWire looks for, which execs the bundle next to it — signs both with `sign.sh`, submits them for notarization, and `ditto`-zips both to `telluride_macos.<arch>.zip`. Binaries are not tracked in git.
- macOS notarization: `notarizeMacOSApp.sh` and `notarizationLog.sh` are symlinks into frostwire-tools, which hold the notarytool credentials (`notarytool-auth.sh`, never copied here). Check with `./notarizationLog.sh <submission id>` until `"status": "Accepted"`; then `codesign -vvv telluride_macos.<arch>` and `codesign -vvv telluride_macos.<arch>.dir/telluride` must show `Developer ID Application: FrostWire, LLC` and `spctl` must say `Notarized Developer ID`. An empty submission id means the credentials weren't found.
- Smoke-test the binary itself: `./telluride_<os>.<arch> -m <youtube url>` on every platform (on macOS that's the launcher file); it prints `Build N` and the title, and the macOS one should answer in well under a second once warmed up (a `--onefile` macOS build taking ~8s means the `--onedir` switch regressed).

## 5. Tag and release

- `git tag -a telluride-build-N -m "Telluride build N" && git push origin telluride-build-N`, so other machines build the same commit.
- `gh release create telluride-build-N --draft --verify-tag --title "Telluride Build N — <headline>" --notes-file <notes> <binaries…>`. Notes follow the previous release: what Telluride is, what changed for users, a tools table (old → new), usage examples, and the compare link `telluride-build-<previous published>...telluride-build-N`.
- Other machines: `gh release upload telluride-build-N <binary>`. The asset names stay `telluride.exe`, `telluride_linux.arm64`, `telluride_linux.x86_64`; the macOS assets are `telluride_macos.arm64.zip` and `telluride_macos.x86_64.zip`, each containing the launcher file `telluride_macos.<arch>` and its bundle folder `telluride_macos.<arch>.dir/`. FrostWire (`FrostWireUtils.getTellurideLauncherFile()`, unchanged) looks for the single file `telluride_macos.<arch>`; its installers unzip the macOS zip into `FrostWire.app/Contents/MacOS/` so the launcher and its `.dir` folder sit side by side.
- The maintainer publishes the draft once all five are attached.

## 6. FrostWire submodule

In the frostwire repo: `git -C telluride fetch --tags && git -C telluride checkout telluride-build-N`, commit `[desktop] Update the Telluride submodule to build N (yt-dlp <version>)`, then a desktop changelog line under the UNRELEASED header (`update:Telluride build N with yt-dlp <version>, …`). Run the Telluride tests (`./gradlew test --tests "*Telluride*"` from `desktop/`) and push to both remotes.
