#!/bin/bash
set -e

if [ $(uname -a | grep -c Darwin) == 0 ]
then
  echo "telluride/sign.sh: this script is only meant for macos, exiting"
  exit 0
fi
ARCH=`arch`
if [ ${ARCH} == "i386" ]; then
  ARCH=x86_64
fi

# macOS builds are PyInstaller --onedir folders:
# telluride_macos.<arch>/telluride (x86_64 on Intel, arm64 on Apple Silicon).
# A legacy --onefile build is a single file with the same name.
TARGET="telluride_macos.${ARCH}"

if [ ! -e "${TARGET}" ]; then
  echo "telluride/sign.sh: ERROR - ${TARGET} not found, run build.sh first"
  exit 1
fi

sign_one() {
  # If the signing key is not in this device, you need to get it from the private repo frostwire-tools/certs/Apple...
  codesign --verbose=4 \
           -s KET68JTS3L \
           --entitlements Entitlements.plist \
           --options runtime \
           -f \
           "$1"
}

echo "Signing ${TARGET}..."
if [ -d "${TARGET}" ]; then
  # A plain folder is not a .app bundle, so `codesign --deep` on the
  # folder itself fails ("bundle format unrecognized"). Sign every
  # Mach-O inside it instead: the main executable and the nested
  # dylibs/.so files under _internal/. PyInstaller already signs
  # them when it can (build.sh passes --codesign-identity when the
  # Developer ID identity is in the keychain), so this re-sign is
  # idempotent on the maintainer's Mac and converts ad-hoc signatures
  # to Developer ID on machines where PyInstaller could not sign.
  while IFS= read -r -d '' file; do
    if file "$file" | grep -q "Mach-O"; then
      sign_one "$file"
    fi
  done < <(find "${TARGET}" -type f -print0)
else
  sign_one "${TARGET}"
fi

echo "Verifying signature..."
codesign -vvv "${TARGET}/telluride" 2>/dev/null || codesign -vvv "${TARGET}"

echo "Successfully signed ${TARGET}"

# This tool must be symlinked from our private repo given it includes credentials.
# It ditto-zips the target (folder or file) and submits it to notarytool.
if [ -f ./notarizeMacOSApp.sh ]
then
  echo "Submitting for notarization..."
  ./notarizeMacOSApp.sh "${TARGET}" com.frostwire.Telluride
else
  echo "telluride/sign.sh: ${TARGET} signed but not sent for notarization, notarizeMacOSApp.sh not found (symlink from private tools repository)"
fi
