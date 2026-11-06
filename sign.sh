#!/bin/bash
set -e

if [ $(uname -a | grep -c Darwin) == 0 ]
then
  echo "telluride/sign.sh: this script is only meant for macos, exiting"
  exit 0
fi
usage() {
  cat <<USAGE
Usage: ./sign.sh <arm64|x86_64>

Signs the macOS Telluride build for that architecture with the Developer ID
(KET68JTS3L), embeds the signed bundle in the single-file launcher, signs the
launcher and submits both for notarization.

It needs, in this folder:
  telluride_macos.<arch>.dir/   the PyInstaller --onedir bundle, from either
    - ./build.sh on a Mac of that architecture, or
    - the "Build macOS ARM64" / "Build macOS x86_64" GitHub Actions artifact,
      unzipped here (it holds telluride_macos.<arch> and telluride_macos.<arch>.dir/)

Any Mac can sign either architecture. Examples:
  ./sign.sh arm64
  ./sign.sh x86_64      # e.g. the Intel CI artifact, on an Apple Silicon Mac
USAGE
}

if [ $# -ne 1 ]; then
  echo "telluride/sign.sh: ERROR - missing the architecture to sign." >&2
  echo >&2
  usage >&2
  exit 1
fi
case "$1" in
  -h|--help) usage; exit 0 ;;
  arm64|x86_64) ARCH="$1" ;;
  *)
    echo "telluride/sign.sh: ERROR - unknown architecture '$1' (use arm64 or x86_64)." >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac

# The macOS product is one file, telluride_macos.<arch> (x86_64 on
# Intel, arm64 on Apple Silicon): a native launcher with the
# PyInstaller --onedir bundle telluride_macos.<arch>.dir/ embedded in
# it (see launcher.c, macos_launcher.sh). The bundle's binaries are
# signed first, then embedded, then the launcher is signed, so its
# signature covers the signed payload.
TARGET="telluride_macos.${ARCH}"
BUNDLE_DIR="${TARGET}.dir"

if [ ! -x "${BUNDLE_DIR}/telluride" ]; then
  echo "telluride/sign.sh: ERROR - ${BUNDLE_DIR}/telluride not found in $(pwd)." >&2
  echo "  Build it with ./build.sh on a ${ARCH} Mac, or download the \"Build macOS ${ARCH}\"" >&2
  echo "  GitHub Actions artifact and unzip it here, then run ./sign.sh ${ARCH} again." >&2
  exit 1
fi
# A wrong-architecture bundle would be signed, embedded and notarized
# under the wrong name; refuse it.
if ! lipo -archs "${BUNDLE_DIR}/telluride" 2>/dev/null | tr ' ' '\n' | grep -qx "${ARCH}"; then
  echo "telluride/sign.sh: ERROR - ${BUNDLE_DIR}/telluride is not a ${ARCH} binary ($(lipo -archs "${BUNDLE_DIR}/telluride" 2>/dev/null || echo unknown))." >&2
  echo "  Rebuild or re-download the ${ARCH} bundle." >&2
  exit 1
fi
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "KET68JTS3L"; then
  echo "telluride/sign.sh: ERROR - the Developer ID signing identity KET68JTS3L is not in this Mac's keychain." >&2
  echo "  Import it from the private frostwire-tools repository (certs/Apple...), then run ./sign.sh ${ARCH} again." >&2
  exit 1
fi

restore_framework_symlinks() {
  # A GitHub Actions artifact zip replaces the symlinks of a .framework
  # (Python, Resources, Versions/Current) with full copies. Those copies
  # are extra, unsigned Mach-O files (the payload grows from ~32 MB to
  # ~47 MB) that notarization rejects. Put the standard layout back:
  # Versions/Current -> <the one version>, <name> -> Versions/Current/<name>.
  local fw versions version entry name
  while IFS= read -r -d '' fw; do
    versions="${fw}/Versions"
    [ -d "${versions}" ] || continue
    version=""
    for entry in "${versions}"/*; do
      name="$(basename "${entry}")"
      [ "${name}" = "Current" ] && continue
      if [ -n "${version}" ]; then
        echo "telluride/sign.sh: ${fw} has more than one version, leaving it as is"
        version=""
        continue 2
      fi
      version="${name}"
    done
    [ -n "${version}" ] || continue
    if [ ! -L "${versions}/Current" ]; then
      echo "Restoring symlink ${versions}/Current -> ${version}"
      rm -rf "${versions}/Current"
      ln -s "${version}" "${versions}/Current"
    fi
    for entry in "${versions}/${version}"/*; do
      name="$(basename "${entry}")"
      if [ -e "${fw}/${name}" ] && [ ! -L "${fw}/${name}" ]; then
        echo "Restoring symlink ${fw}/${name} -> Versions/Current/${name}"
        rm -rf "${fw:?}/${name}"
        ln -s "Versions/Current/${name}" "${fw}/${name}"
      fi
    done
  done < <(find "$1" -type d -name "*.framework" -print0)
}

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

restore_framework_symlinks "${BUNDLE_DIR}"
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
