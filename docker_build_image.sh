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

PLATFORM_ARG=""
TAG_SUFFIX=""
if [ -n "${PLATFORM}" ]; then
  PLATFORM_ARG="--platform=${PLATFORM}"
  # Tag suffix based on platform, e.g. linux/amd64 -> amd64
  TAG_SUFFIX="-${PLATFORM##*/}"
fi

docker build ${PLATFORM_ARG} -t telluride-ubuntu${TAG_SUFFIX} .
