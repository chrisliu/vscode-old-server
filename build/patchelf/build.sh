#!/bin/bash
#
# Build static patchelf binary using Alpine Linux
#
# patchelf 0.18.0 requires C++17, which is not available on CentOS 7.
# We build a statically-linked binary using Alpine so it runs anywhere.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/output"

PATCHELF_VERSION="0.18.0"
PATCHELF_URL="https://github.com/NixOS/patchelf/releases/download/${PATCHELF_VERSION}/patchelf-${PATCHELF_VERSION}.tar.bz2"

echo "==> Building static patchelf ${PATCHELF_VERSION}..."
mkdir -p "$OUTPUT_DIR"

# Download patchelf source
TARBALL="$OUTPUT_DIR/patchelf-${PATCHELF_VERSION}.tar.bz2"
if [[ ! -f "$TARBALL" ]]; then
    echo "    Downloading patchelf source..."
    curl -L "$PATCHELF_URL" -o "$TARBALL"
fi

# Build statically using Alpine (has modern GCC with C++17 support)
echo "    Building in Alpine container..."
docker run --rm --platform linux/amd64 \
    -v "$OUTPUT_DIR:/output" \
    alpine:latest sh -c "
        set -e
        apk add --no-cache build-base bzip2
        cd /tmp
        tar -xjf /output/patchelf-${PATCHELF_VERSION}.tar.bz2
        cd patchelf-${PATCHELF_VERSION}
        ./configure LDFLAGS='-static'
        make -j\$(nproc)
        cp src/patchelf /output/patchelf
        chmod +x /output/patchelf
    "

echo "==> Done! Static patchelf saved to: $OUTPUT_DIR/patchelf"
echo "    Size: $(du -h "$OUTPUT_DIR/patchelf" | cut -f1)"

# Verify it's statically linked
if command -v file >/dev/null 2>&1; then
    echo "    Type: $(file "$OUTPUT_DIR/patchelf" | cut -d: -f2)"
fi
