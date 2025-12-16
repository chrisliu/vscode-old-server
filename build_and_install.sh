#!/bin/bash
#
# Build all components and install to a remote server
#
# Usage: ./build_and_install.sh <ssh-target>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <ssh-target>"
    echo ""
    echo "This script builds all components and installs them to the remote server."
    echo "The build process takes approximately 30-90 minutes."
    echo ""
    echo "Arguments:"
    echo "  ssh-target    SSH destination (username@host or SSH config alias)"
    echo ""
    echo "To build only (without installing):"
    echo "  ./build/crosstool-ng/build.sh"
    echo "  ./build/patchelf/build.sh"
    exit 1
}

log_step() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# Check arguments
if [[ $# -lt 1 ]]; then
    usage
fi

SSH_TARGET="$1"

# Step 1: Build sysroot (if not already built)
if [[ -f "$SCRIPT_DIR/output/sysroot.tar" ]]; then
    echo "sysroot.tar already exists, skipping build..."
    echo "  (Delete output/sysroot.tar to rebuild)"
else
    log_step "Step 1/3: Building custom glibc sysroot"
    "$SCRIPT_DIR/build/crosstool-ng/build.sh"
fi

# Step 2: Build patchelf (if not already built)
if [[ -f "$SCRIPT_DIR/output/patchelf" ]]; then
    echo "patchelf already exists, skipping build..."
    echo "  (Delete output/patchelf to rebuild)"
else
    log_step "Step 2/3: Building static patchelf"
    "$SCRIPT_DIR/build/patchelf/build.sh"
fi

# Step 3: Install to remote server
log_step "Step 3/3: Installing to $SSH_TARGET"
"$SCRIPT_DIR/install.sh" "$SSH_TARGET"

log_step "All done!"
echo "VS Code Server patch has been installed to $SSH_TARGET"
echo "Connect with VS Code Remote-SSH to test."
