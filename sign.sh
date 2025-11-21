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

echo "Signing telluride_macos.${ARCH}..."
codesign --verbose=4 \
         -s KET68JTS3L \
         --entitlements Entitlements.plist \
         --options runtime \
         -f \
         telluride_macos.${ARCH}

if [ $? -ne 0 ]; then
  # If the signing key is not in this device, you need to get it from the private repo frostwire-tools/certs/Apple...
  echo "telluride/sign.sh: ERROR - Failed to sign the binary"
  exit 1
fi

echo "Verifying signature..."
codesign -vvv telluride_macos.${ARCH}

if [ $? -ne 0 ]; then
  echo "telluride/sign.sh: ERROR - Signature verification failed"
  exit 1
fi

echo "Successfully signed telluride_macos.${ARCH}"

# This tool must be symlinked from our private repo given it includes credentials
if [ -f ./notarizeMacOsApp.sh ]
then
  echo "Submitting for notarization..."
  ./notarizeMacOsApp.sh telluride_macos.${ARCH} com.frostwire.Telluride
else
  echo "telluride/sign.sh: telluride_macos signed but not sent for notarization, notarizeMacOsApp.sh not found (symlink from private tools repository)"
fi
