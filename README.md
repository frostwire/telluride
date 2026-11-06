# Telluride Cloud Video Downloader.

![Telluride Logo](logo/1024X1024-white-telluride-logo.png)

### A portable and easy to use [yt_dlp](https://github.com/yt-dlp/yt-dlp) wrapper by FrostWire.

## Usage
```
Telluride Cloud Video Downloader. Build 30
Copyright 2020-2024 FrostWire LLC. Licensed under Apache 2.0.
Python 3.12.1 (v3.12.1:2305ca5144, Dec  7 2023, 17:23:38) [Clang 13.0.0 (clang-1300.0.29.30)]
sys.version_info(major=3, minor=12, micro=1, releaselevel='final', serial=0)
CWD=/Users/gubatron/workspace/frostwire/telluride

usage: telluride_macos.arm64 [-h] [--audio-only] [--meta-only] [page_url]

positional arguments:
  page_url          The URL of the page that hosts the video you need to backup locally

options:
  -h, --help        show this help message and exit
  --audio-only, -a  Downloads the video and keeps only a separate audio file usually a .mp3. (requires
                    ffmpeg installed in the system)
  --meta-only, -m   Prints a JSON dictionary with all the metadata available on the video file found in the
                    page_url. Does not download the video file
```

## Building

```bash
$ ./configure_update.sh # tries to install (or update) all dependencies
$ ./build.sh     # runs pylint on the code, pauses, performs binary packaging
```

You should end up with a stand-alone executable for the platform you are on:

 - telluride.exe (Windows, PyInstaller `--onefile`)
 - telluride_linux.<arch> (Linux, PyInstaller `--onefile`)
 - telluride_macos.<arch> (macOS x86_64 and arm64: a single native file, `launcher.c`, with the signed PyInstaller `--onedir` bundle embedded in it; also zipped as `telluride_macos.<arch>.zip`)

macOS does not use `--onefile` because a `--onefile` binary re-extracts
into a fresh random temp folder on every launch and macOS re-validates
every Mach-O it loads from that new path (~8s per launch for telluride).
Instead the signed `--onedir` folder is zipped into a section of a tiny
native launcher (`macos_launcher.sh`), so `telluride_macos.<arch>` is
still one file. Its first run unpacks the folder once into
`~/Library/Caches/com.frostwire.Telluride/<build>-<arch>-<hash>/` (~8s,
while macOS validates it) and every later run execs it from there in
~0.15s. A new build unpacks next to the old one, and versions unused for
a week are removed. Linux/Windows keep `--onefile` since they have no
such per-file trust check.


## Requirements
 Aside from `bash`,`python3` and `ffmpeg`, the rest should be installed by the `configure.sh` script.
    
 - `bash`
 - `python3`, `pip`, `pylint`
 - `ffmpeg` (for audio-only downloads. audio is extracted from the downloaded video)
 - `yt_dlp`, `pycryptodome`, `pyinstaller`
 
## Signing

See `frostwire-tools/installer_builders/windows/TOKEN_README.md` 

## License
```
Copyright 2020-2025 FrostWire LLC.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    
    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

## Donations

If you find this software useful, please support or donate to this project what you can at [https://www.frostwire.com/give](https://www.frostwire.com/give)
