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

# The macOS product is one file, telluride_macos.<arch> (x86_64 on
# Intel, arm64 on Apple Silicon): a native launcher with the
# PyInstaller --onedir bundle telluride_macos.<arch>.dir/ embedded in
# it (see launcher.c, macos_launcher.sh). The bundle's binaries are
# signed first, then embedded, then the launcher is signed, so its
# signature covers the signed payload.
TARGET="telluride_macos.${ARCH}"
BUNDLE_DIR="${TARGET}.dir"

if [ ! -x "${BUNDLE_DIR}/telluride" ]; then
  echo "telluride/sign.sh: ERROR - ${BUNDLE_DIR}/telluride not found, run build.sh first"
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

sign_mach_o_tree() {
  # A plain folder is not a .app bundle, so `codesign --deep` on
  # the folder itself fails ("bundle format unrecognized"). Sign
  # every Mach-O inside it instead: the main executable and the
  # nested dylibs/.so files under _internal/. PyInstaller already
  # signs them when it can (build.sh passes --codesign-identity
  # when the Developer ID identity is in the keychain), so this
  # re-sign is idempotent on the maintainer's Mac and converts
  # ad-hoc signatures to Developer ID on machines where
  # PyInstaller could not sign.
  while IFS= read -r -d '' file; do
    # Skip the top-level copies inside a .framework bundle
    # (Python.framework/Python, Versions/Current/Python): in a
    # proper --onedir build those are symlinks (already excluded
    # by -type f), but a GitHub Actions artifact zip dereferences
    # them into regular files, and codesign rejects them with
    # "bundle format is ambiguous". The real Mach-O at
    # Versions/<version>/Python is signed instead.
    case "$file" in
      *.framework/Python|*.framework/Versions/Current/Python)
        continue
        ;;
    esac
    if file "$file" | grep -q "Mach-O"; then
      sign_one "$file"
    fi
  done < <(find "$1" -type f -print0)
}

echo "Signing ${BUNDLE_DIR} (bundle)..."
sign_mach_o_tree "${BUNDLE_DIR}"
codesign -vvv "${BUNDLE_DIR}/telluride"

echo "Embedding the signed bundle in ${TARGET}..."
./macos_launcher.sh "${ARCH}"

echo "Signing ${TARGET}..."
sign_one "${TARGET}"

echo "Verifying signature..."
codesign -vvv "${TARGET}"

echo "Successfully signed ${TARGET}"

# This tool must be symlinked from our private repo given it includes credentials.
# It ditto-zips the path it is given and submits it to notarytool.
# Submit the launcher together with the bundle folder it embeds: the
# notary service does not look inside the launcher's payload section,
# so this puts every Mach-O the launcher unpacks in the ticket too.
if [ -f ./notarizeMacOSApp.sh ]; then
  echo "Submitting for notarization..."
  STAGE="${TARGET}.staging"
  rm -rf "${STAGE}"
  mkdir -p "${STAGE}"
  cp -R "${TARGET}" "${BUNDLE_DIR}" "${STAGE}/"
  ./notarizeMacOSApp.sh "${STAGE}" com.frostwire.Telluride
  rm -rf "${STAGE}"
else
  echo "telluride/sign.sh: ${TARGET} signed but not sent for notarization, notarizeMacOSApp.sh not found (symlink from private tools repository)"
fi
