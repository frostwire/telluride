#!/usr/bin/env bash

# Parse optional --platform argument
PLATFORM=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    --platform=*)
      PLATFORM="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Detect the operating system
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    CPUS=$(nproc)
elif [[ "$OSTYPE" == "darwin"* ]]; then
    CPUS=$(sysctl -n hw.ncpu)
elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    CPUS=$(echo %NUMBER_OF_PROCESSORS%)
else
    echo "Unsupported OS type: $OSTYPE"
    exit 1
fi

PLATFORM_ARG=""
TAG_SUFFIX=""
if [ -n "${PLATFORM}" ]; then
  PLATFORM_ARG="--platform=${PLATFORM}"
  TAG_SUFFIX="-${PLATFORM##*/}"
fi

docker \
 run \
 ${PLATFORM_ARG} \
 --cpus ${CPUS} \
 -v "$PWD:/telluride-ubuntu" \
 -it telluride-ubuntu${TAG_SUFFIX}
