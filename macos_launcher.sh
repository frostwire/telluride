#!/bin/bash
# Builds the single-file macOS telluride_macos.<arch>: the native launcher
# (launcher.c) with the PyInstaller --onedir bundle telluride_macos.<arch>.dir/
# zipped into its __TELLURIDE,__payload section. The launcher unpacks it
# once into ~/Library/Caches/com.frostwire.Telluride/<id>/ and runs it
# from there (see launcher.c).
#
# Run it after the bundle's binaries are signed (sign.sh does), then sign
# the launcher: the payload is part of the launcher's code signature, so
# re-signing the bundle means running this again.
#
# Usage: ./macos_launcher.sh [arch]   (default: this Mac's architecture)
set -euo pipefail

ARCH="${1:-$(arch)}"
if [ "${ARCH}" == "i386" ]; then
  ARCH=x86_64
fi
TARGET="telluride_macos.${ARCH}"
BUNDLE_DIR="${TARGET}.dir"
PAYLOAD="${TARGET}.payload.zip"

if [ ! -x "${BUNDLE_DIR}/telluride" ]; then
  echo "macos_launcher.sh: ERROR - ${BUNDLE_DIR}/telluride not found, run build.sh first"
  exit 1
fi

BUILD=$(sed -n 's/^BUILD = \([0-9][0-9]*\).*/\1/p' telluride.py | head -1)
if [ -z "${BUILD}" ]; then
  echo "macos_launcher.sh: ERROR - cannot read BUILD from telluride.py"
  exit 1
fi

# The launcher must run wherever the bundle runs: take the bundle's minimum
# macOS version. Without it cc targets the build Mac's own macOS version.
MIN_OS=$(vtool -show-build "${BUNDLE_DIR}/telluride" | awk '/minos/{print $2; exit}')
if [ -z "${MIN_OS}" ]; then
  echo "macos_launcher.sh: ERROR - cannot read the minimum macOS version of ${BUNDLE_DIR}/telluride"
  exit 1
fi

# ditto keeps the symlinks Python.framework needs and the code signatures
# embedded in each Mach-O. Extended attributes, quarantine flags and ACLs of
# the build machine stay out of the payload.
rm -f "${PAYLOAD}"
ditto -c -k --norsrc --noextattr --noqtn --noacl "${BUNDLE_DIR}" "${PAYLOAD}"
HASH=$(shasum -a 256 "${PAYLOAD}" | cut -c1-16)
ID="${BUILD}-${ARCH}-${HASH}"

rm -f "${TARGET}"
cc -O2 -Wall -Wextra -Werror \
   -arch "${ARCH}" \
   -mmacosx-version-min="${MIN_OS}" \
   -DTELLURIDE_PAYLOAD_ID="\"${ID}\"" \
   -Wl,-sectcreate,__TELLURIDE,__payload,"${PAYLOAD}" \
   -o "${TARGET}" launcher.c
rm -f "${PAYLOAD}"

echo "Built ${TARGET} ($(du -h "${TARGET}" | cut -f1)), embedded bundle ${ID}, macOS ${MIN_OS}+"
