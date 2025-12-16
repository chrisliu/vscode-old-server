#!/bin/bash
#
# Install VS Code Server glibc patch to a remote server
#
# Usage: ./install.sh <ssh-target>
#
# The ssh-target can be:
#   - username@hostname
#   - An SSH config alias (e.g., "myserver" from ~/.ssh/config)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <ssh-target>"
    echo ""
    echo "Arguments:"
    echo "  ssh-target    SSH destination (username@host or SSH config alias)"
    echo ""
    echo "Examples:"
    echo "  $0 user@server.example.com"
    echo "  $0 myserver  # Uses SSH config alias"
    exit 1
}

log_info() {
    echo -e "${GREEN}==>${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}==> WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}==> ERROR:${NC} $1" >&2
}

# Check arguments
if [[ $# -lt 1 ]]; then
    usage
fi

SSH_TARGET="$1"

# Validate build artifacts exist
if [[ ! -f "$OUTPUT_DIR/sysroot.tar" ]]; then
    log_error "sysroot.tar not found in $OUTPUT_DIR"
    echo "Run ./build/crosstool-ng/build.sh first"
    exit 1
fi

if [[ ! -f "$OUTPUT_DIR/patchelf" ]]; then
    log_error "patchelf not found in $OUTPUT_DIR"
    echo "Run ./build/patchelf/build.sh first"
    exit 1
fi

# Test SSH connection
log_info "Testing SSH connection to $SSH_TARGET..."
if ! ssh -o ConnectTimeout=10 "$SSH_TARGET" "echo 'Connection successful'" >/dev/null 2>&1; then
    log_error "Cannot connect to $SSH_TARGET"
    echo "Please check your SSH configuration and try again"
    exit 1
fi

# Copy artifacts to remote server
log_info "Copying sysroot.tar to $SSH_TARGET... ($(du -h "$OUTPUT_DIR/sysroot.tar" | cut -f1))"
scp "$OUTPUT_DIR/sysroot.tar" "$SSH_TARGET:~/"

log_info "Copying patchelf to $SSH_TARGET..."
scp "$OUTPUT_DIR/patchelf" "$SSH_TARGET:~/"

# Install on remote server
log_info "Installing on remote server..."
ssh "$SSH_TARGET" bash -s << 'REMOTE_SCRIPT'
set -e

echo "  Creating directories..."
mkdir -p ~/vscode-sysroot ~/.local/bin

echo "  Extracting sysroot..."
tar -xf ~/sysroot.tar -C ~/vscode-sysroot

echo "  Installing patchelf..."
mv ~/patchelf ~/.local/bin/
chmod +x ~/.local/bin/patchelf

echo "  Cleaning up..."
rm -f ~/sysroot.tar

# Configure environment variables
ENV_BLOCK='
# VS Code Server custom glibc configuration
export VSCODE_SERVER_CUSTOM_GLIBC_LINKER="$HOME/vscode-sysroot/x86_64-linux-gnu/x86_64-linux-gnu/sysroot/lib/ld-linux-x86-64.so.2"
export VSCODE_SERVER_CUSTOM_GLIBC_PATH="$HOME/vscode-sysroot/x86_64-linux-gnu/x86_64-linux-gnu/sysroot/lib:$HOME/vscode-sysroot/x86_64-linux-gnu/x86_64-linux-gnu/lib64"
export VSCODE_SERVER_PATCHELF_PATH="$HOME/.local/bin/patchelf"
'

# Add to shell config files (if not already present)
for rcfile in ~/.bashrc ~/.bash_profile ~/.profile; do
    if [[ -f "$rcfile" ]]; then
        if ! grep -q "VSCODE_SERVER_CUSTOM_GLIBC_LINKER" "$rcfile" 2>/dev/null; then
            echo "  Adding environment variables to $rcfile..."
            echo "$ENV_BLOCK" >> "$rcfile"
        else
            echo "  Environment variables already in $rcfile, skipping..."
        fi
    fi
done

# Clear VS Code Server cache
if [[ -d ~/.vscode-server ]]; then
    echo "  Clearing VS Code Server cache..."
    rm -rf ~/.vscode-server
fi

echo "  Installation complete!"
REMOTE_SCRIPT

log_info "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Connect to $SSH_TARGET with VS Code Remote-SSH"
echo "  2. If you see errors, reconnect after the server restarts"
echo ""
echo "The following environment variables have been configured:"
echo "  - VSCODE_SERVER_CUSTOM_GLIBC_LINKER"
echo "  - VSCODE_SERVER_CUSTOM_GLIBC_PATH"
echo "  - VSCODE_SERVER_PATCHELF_PATH"
