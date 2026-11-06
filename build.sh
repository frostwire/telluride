#!/usr/bin/env bash
##########################################################################
# Created by Angel Leon (@gubatron)
# Copyright (c) 2011-2022, FrostWire(R). All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################
#set -x
PYINSTALLER_CMD="pyinstaller"
PYLINT_CMD="python3 -m pylint"
source ./common.sh

if ismac;
then
    PYLINT_CMD="python3 -m pylint"
fi

if iswindows;
then
    PYLINT_CMD="python -m pylint"
fi

# Linux's pyinstaller PATH
if isubuntu;
then
    PYINSTALLER_CMD="${HOME}/.local/bin/pyinstaller"
fi

if isdocker;
then
    #echo "isdocker: true, setting pylint command to 'pylint3'"
    PYINSTALLER_CMD=/usr/local/bin/pyinstaller
    PYLINT_CMD="pylint"
fi

echo PYINSTALLER_CMD=${PYINSTALLER_CMD}

# Windows + MINGW
# pylint and pyinstaller might be in a place like this if you are in windows
# We make sure they are in the PATH
# c:\users\myuser\appdata\local\programs\python\python38-32\scripts
if iswindows
then
  echo "PYTHON_HOME=${PYTHON_HOME}"
  if [ ! $(which pyinstaller) ]
  then
    if [ -z "${PYTHON_HOME}" ]
	then
	  echo "Aborting, PYTHON_HOME env variable not set"
	  exit 1
	fi

    echo "Adding PYTHON_HOME/scripts to PATH..."
    PATH=${PATH}:${PYTHON_HOME}/scripts
  fi
fi

# macOS: use --onedir instead of --onefile.
# --onefile extracts the bundle into a fresh random _MEIxxxxxx temp
# directory on every launch, and macOS runs a code-signature/trust
# check for every Mach-O it loads from that new path (~8s for
# telluride, re-checked on every invocation). Linux/Windows have no
# such per-file trust check, so --onefile stays fast there and is
# kept for a single-file binary.
# --onedir ships a folder whose binaries are already signed on
# disk, so macOS caches the validation and startup is ~0.2s,
# the same as running `python3 telluride.py`. A tiny native
# launcher (launcher.c) is placed at the classic
# telluride_macos.<arch> path and execs that folder, so
# FrostWire and the installers keep finding a single
# executable file exactly where they always did.
PYINSTALLER_MODE="--onefile"
EXTRA_FLAGS=
if ismac
then
  PYINSTALLER_MODE="--onedir"
  EXTRA_FLAGS="--osx-bundle-identifier com.frostwire.Telluride --osx-entitlements-file Entitlements.plist"
  # Sign every collected binary with the Developer ID identity when
  # it is available in the keychain (the maintainer's Mac). Without
  # it PyInstaller falls back to ad-hoc signing and sign.sh will
  # re-sign the folder with --deep, so CI / other machines still work.
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "KET68JTS3L"
  then
    EXTRA_FLAGS="${EXTRA_FLAGS} --codesign-identity KET68JTS3L"
  fi
fi

echo "Cleaning up..."
cleanup
echo "Running ${PYLINT_CMD}..."
echo ${PYLINT_CMD} --max-line-length=350 telluride.py
${PYLINT_CMD} --max-line-length=350 telluride.py
read -p "[Press any key to continue] [Press Ctrl+C to cancel build]"
echo "Running ${PYINSTALLER_CMD} ${PYINSTALLER_MODE} ${EXTRA_FLAGS} telluride.py"
${PYINSTALLER_CMD} ${PYINSTALLER_MODE} --noupx ${EXTRA_FLAGS} telluride.py

if [ -f dist/telluride ] || [ -f dist/telluride/telluride ] || [ -f dist/telluride.exe ]
then
  if isubuntu || isdocker
  then
    LINUX_ARCH=`uname -m`
    if [ ${LINUX_ARCH} == "aarch64" ]; then
        LINUX_ARCH="arm64"
    elif [ ${LINUX_ARCH} == "i386" ] || [ ${LINUX_ARCH} == "i686" ]; then
        LINUX_ARCH="x86_64"
    fi
    mv dist/telluride telluride_linux.${LINUX_ARCH}
  elif ismac
  then
    ARCH=`arch`
    if [ ${ARCH} == "i386" ]; then
        ARCH=x86_64
    fi
    # --onedir output is a folder; keep it as
    # telluride_macos.<arch>.dir/ (x86_64 on Intel Macs, arm64 on
    # Apple Silicon, decided by the machine this script runs on)
    # and put a native launcher at the path FrostWire and the
    # installers have always looked for: telluride_macos.<arch>
    # (see launcher.c). The launcher just execs the bundle next
    # to it, so the visible artifact stays a single executable
    # file while startup stays ~0.2s instead of the ~8s a
    # --onefile binary pays on macOS.
    mv dist/telluride telluride_macos.${ARCH}.dir
    cc -O2 -arch ${ARCH} -o telluride_macos.${ARCH} launcher.c
    ./sign.sh
    # ditto (not zip) preserves executable bits, symlinks (the
    # Python.framework layout depends on them; plain zip follows
    # them and breaks the code signature) and macOS metadata.
    # ditto cannot archive multiple sources, so stage both the
    # launcher file and its .dir folder into one directory and
    # archive its contents at the zip root; unzip the result
    # into FrostWire.app/Contents/MacOS/ (or the telluride/
    # folder when running from source).
    STAGE="telluride_macos.${ARCH}.staging"
    rm -rf "${STAGE}"
    mkdir -p "${STAGE}"
    cp -R telluride_macos.${ARCH} telluride_macos.${ARCH}.dir "${STAGE}/"
    ditto -c -k --sequesterRsrc "${STAGE}" telluride_macos.${ARCH}.zip
    rm -rf "${STAGE}"
    echo "Built telluride_macos.${ARCH} (launcher) + telluride_macos.${ARCH}.dir/ (bundle) and telluride_macos.${ARCH}.zip"
  elif iswindows
  then
    mv dist/telluride.exe .
    ./sign.bat
  fi
  cleanup
  ls -lth
fi
#set +x
