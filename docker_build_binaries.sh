#!/usr/bin/env bash

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

# One Step Build (It will be cached if nothing changed)
./docker_build_image.sh

# Mounts this repo's folder as a volume in the container's /telluride-ubuntu folder
# Then executes the build scripts
docker \
 run \
 --cpus ${CPUS} \
 -v "$PWD:/telluride-ubuntu" \
 -it telluride-ubuntu \
 /bin/bash -c "cd telluride-ubuntu && ./configure_update.sh && ./build.sh"

