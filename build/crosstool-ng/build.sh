#!/bin/bash
#
# Build custom glibc 2.28 sysroot using crosstool-ng
#
# This script:
# 1. Builds the crosstool-ng Docker image
# 2. Runs ct-ng build inside the container
# 3. Extracts the sysroot tarball to output/
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/output"

DOCKER_IMAGE="crosstool-ng:1.26.0"
CONTAINER_NAME="ct-build-$$"

# Number of parallel jobs (default: number of CPUs)
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

echo "==> Building crosstool-ng Docker image..."
docker build -t "$DOCKER_IMAGE" "$SCRIPT_DIR"

echo "==> Starting crosstool-ng build (this may take 30-90 minutes)..."
echo "    Using $PARALLEL_JOBS parallel jobs"

# Run the build inside the container
docker run --name "$CONTAINER_NAME" \
    --cpus="$PARALLEL_JOBS" \
    -v "$SCRIPT_DIR/config:/home/builder/input.config:ro" \
    "$DOCKER_IMAGE" bash -c "
        set -e
        mkdir -p ~/toolchain-dir
        cp ~/input.config ~/toolchain-dir/.config
        cd ~/toolchain-dir
        echo 'Starting ct-ng build...'
        ct-ng build
        echo 'Build completed successfully!'
    "

echo "==> Extracting sysroot..."
mkdir -p "$OUTPUT_DIR"

# Commit the container state and extract the sysroot
docker commit "$CONTAINER_NAME" ct-build-snapshot
docker run --rm ct-build-snapshot \
    tar -cf - -C /home/builder/toolchain-dir x86_64-linux-gnu \
    > "$OUTPUT_DIR/sysroot.tar"

echo "==> Cleaning up..."
docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker rmi ct-build-snapshot >/dev/null 2>&1 || true

echo "==> Done! Sysroot saved to: $OUTPUT_DIR/sysroot.tar"
echo "    Size: $(du -h "$OUTPUT_DIR/sysroot.tar" | cut -f1)"
