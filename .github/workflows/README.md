# GitHub Actions Workflows

This directory contains GitHub Actions workflows for building Telluride binaries on different architectures.

## Available Workflows

1. **build-windows-x86_64.yml** - Builds `telluride.exe` for Windows x86_64 (`--onefile`)
2. **build-linux-x86_64.yml** - Builds `telluride_linux.x86_64` for Linux x86_64 (`--onefile`)
3. **build-linux-arm64.yml** - Builds `telluride_linux.arm64` for Linux ARM64 (`--onefile`)
4. **build-macos-arm64.yml** - Builds `telluride_macos.arm64.zip` for macOS ARM64 (Apple Silicon, `--onedir` folder)
5. **build-macos-x86_64.yml** - Builds `telluride_macos.x86_64.zip` for macOS x86_64 (Intel, `--onedir` folder)

## Triggering Workflows

Each workflow can be triggered in two ways:

### 1. Manual Trigger (workflow_dispatch)
Go to the Actions tab in GitHub, select the desired workflow, and click "Run workflow".

### 2. Automatic Trigger on Version Tags
Push a tag starting with `telluride-build-` (e.g., `telluride-build-40`, `telluride-build-41`) to automatically trigger all workflows:

```bash
git tag telluride-build-41
git push origin telluride-build-41
```

## Downloading Artifacts

After a workflow completes successfully:

1. Go to the Actions tab in GitHub
2. Click on the completed workflow run
3. Scroll down to the "Artifacts" section
4. Download the binary artifact for your platform

Artifacts are retained for 90 days.

## Build Process

Each workflow:
- Sets up Python 3.13
- Installs dependencies (pip, astroid, pylint, yt_dlp, pyinstaller)
- Runs pylint for code quality checks
- Builds with PyInstaller (`--onefile --noupx` on Windows/Linux; `--onedir --noupx` on macOS, see below)
- Uploads the resulting binary (macOS: `ditto` zip of the `--onedir` folder) as an artifact

## Platform-Specific Notes

- **Windows**: Uses `windows-latest` runner with x64 architecture
- **Linux x86_64**: Uses `ubuntu-latest` runner for maximum compatibility
- **Linux ARM64**: Uses Docker with QEMU emulation
- **macOS ARM64**: Uses `macos-15` runner (Apple Silicon), so the binary is natively arm64
- **macOS x86_64**: Uses `macos-15-intel` runner (Intel), so the binary is natively x86_64

macOS uses `--onedir` instead of `--onefile` because a `--onefile` binary
re-extracts into a fresh random temp folder on every launch and macOS
re-validates every Mach-O it loads from that new path (~8s per launch).
The `--onedir` folder is already signed on disk, so macOS caches the
validation and startup is ~0.2s. The builders verify with `file` that the
produced executable is the expected architecture and ship it as a
`ditto` zip (`telluride_macos.<arch>.zip`, containing the
`telluride_macos.<arch>/` folder). No Developer ID identity is available
on the runners, so the binaries are ad-hoc signed; the maintainer
re-signs/notarizes them after download (see `sign.sh`).
