# GitHub Actions Workflows

This directory contains GitHub Actions workflows for building Telluride binaries on different architectures.

## Available Workflows

1. **build-windows-x86_64.yml** - Builds `telluride.exe` for Windows x86_64
2. **build-linux-x86_64.yml** - Builds `telluride_linux.x86_64` for Linux x86_64
3. **build-linux-arm64.yml** - Builds `telluride_linux.arm64` for Linux ARM64
4. **build-macos-arm64.yml** - Builds `telluride_macos.arm64` for macOS ARM64 (Apple Silicon)
5. **build-macos-x86_64.yml** - Builds `telluride_macos.x86_64` for macOS x86_64 (Intel)

## Triggering Workflows

Each workflow can be triggered in two ways:

### 1. Manual Trigger (workflow_dispatch)
Go to the Actions tab in GitHub, select the desired workflow, and click "Run workflow".

### 2. Automatic Trigger on Version Tags
Push a tag starting with `v` (e.g., `v1.0.0`, `v2.1.3`) to automatically trigger all workflows:

```bash
git tag v1.0.0
git push origin v1.0.0
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
- Builds the binary using PyInstaller with `--onefile --noupx` flags
- Uploads the resulting binary as an artifact

## Platform-Specific Notes

- **Windows**: Uses `windows-latest` runner with x64 architecture
- **Linux x86_64**: Uses `ubuntu-20.04` runner for maximum compatibility
- **Linux ARM64**: Uses Docker with QEMU emulation on `ubuntu-20.04`
- **macOS ARM64**: Uses `macos-14` runner (Apple Silicon)
- **macOS x86_64**: Uses `macos-13` runner (Intel)
