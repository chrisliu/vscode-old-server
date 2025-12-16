# VS Code Server Patch for Older Linux Distributions

This repository provides a reproducible build system for running VS Code Server on older Linux distributions like CentOS 7 that have outdated glibc versions.

## Problem

VS Code 1.99+ requires glibc >= 2.28, but CentOS 7 ships with glibc 2.17. When connecting via Remote-SSH, you'll see errors like:
- `FATAL: kernel too old`
- `channel closed`
- Connection failures after VS Code updates

## Solution

Build a custom glibc 2.28 sysroot using [crosstool-ng](https://crosstool-ng.github.io/) and use [patchelf](https://github.com/NixOS/patchelf) to redirect VS Code Server binaries to the custom glibc at runtime.

This approach is documented in the [VS Code Remote FAQ](https://code.visualstudio.com/docs/remote/faq#_can-i-run-vs-code-server-on-older-linux-distributions).

## Quick Start

```bash
# Build everything and install to remote server (30-90 minutes for first build)
./build_and_install.sh user@server.example.com

# Or use an SSH config alias
./build_and_install.sh myserver
```

## Manual Build Steps

```bash
# 1. Build the custom glibc sysroot (30-90 minutes)
./build/crosstool-ng/build.sh

# 2. Build static patchelf binary (1-2 minutes)
./build/patchelf/build.sh

# 3. Install to remote server
./install.sh user@server.example.com
```

## Requirements

- Docker (for building sysroot and patchelf)
- SSH access to the target server
- ~500MB disk space on the target server

## Version Rationale

| Component | Version | Why This Version |
|-----------|---------|------------------|
| **Kernel headers** | 3.2.101 | **Critical.** glibc embeds an ABI tag that's checked against the runtime kernel. CentOS 7's kernel is 3.10.0, so the headers must produce an ABI tag <= 3.10.0. Using kernel 3.2.101 headers produces ABI tag `3.2.101`, which passes the check. Higher kernel versions (4.x, 5.x, 6.x) cause "FATAL: kernel too old" errors. |
| **glibc** | 2.28 | Minimum version required by VS Code 1.99+. CentOS 7 ships with glibc 2.17 which is too old. |
| **GCC** | 8.5.0 | Matches Microsoft's official VS Code Linux build toolchain configuration. Ensures binary compatibility with VS Code Server. |
| **binutils** | 2.29.1 | Compatible with GCC 8.5.0 and glibc 2.28. Provides the linker and assembler. |
| **crosstool-ng** | 1.26.0 | Latest stable release that supports all the required component versions. |
| **patchelf** | 0.18.0 | Latest stable release. Requires C++17 to compile, which CentOS 7's GCC 4.8 doesn't support, hence we build it statically using Alpine Linux. |

### Why Kernel 3.2.101?

This is the most critical version choice. Here's why:

1. glibc binaries contain an ELF note with a "minimum kernel version" ABI tag
2. At runtime, the kernel checks if this ABI tag is <= the running kernel version
3. If the check fails, you get "FATAL: kernel too old"

The ABI tag comes from the kernel headers used during glibc compilation:
- Kernel 3.2.101 headers → ABI tag `3.2.101` → Works on CentOS 7 (kernel 3.10.0)
- Kernel 4.x headers → ABI tag `4.x` → **Fails** on CentOS 7 (3.10.0 < 4.x)

We use 3.2.101 because it's old enough to work on CentOS 7 while still being modern enough for glibc 2.28.

## How It Works

1. **crosstool-ng** builds a complete cross-compilation toolchain with glibc 2.28
2. The **sysroot** (containing glibc libraries) is extracted and installed to `~/vscode-sysroot/`
3. **patchelf** is installed to modify ELF binaries at runtime
4. VS Code Server detects these environment variables and uses patchelf to redirect its binaries to the custom glibc:
   - `VSCODE_SERVER_CUSTOM_GLIBC_LINKER` - Path to the custom ld-linux dynamic linker
   - `VSCODE_SERVER_CUSTOM_GLIBC_PATH` - Library search paths for the custom glibc
   - `VSCODE_SERVER_PATCHELF_PATH` - Path to the patchelf binary

## Directory Structure

```
vscode-patch/
├── build/
│   ├── crosstool-ng/
│   │   ├── Dockerfile      # Ubuntu image with crosstool-ng 1.26.0
│   │   ├── config          # crosstool-ng configuration
│   │   └── build.sh        # Build script
│   └── patchelf/
│       └── build.sh        # Build script (uses Alpine for C++17)
├── output/                  # Build artifacts (gitignored)
│   ├── sysroot.tar         # Custom glibc sysroot (~260MB)
│   └── patchelf            # Static patchelf binary (~6MB)
├── install.sh              # Install to remote server
├── build_and_install.sh    # Build all + install
└── README.md
```

## Troubleshooting

### "FATAL: kernel too old"

The kernel headers in the sysroot are too new for your server's kernel. This shouldn't happen with the provided config (kernel 3.2.101), but if you modify the config, ensure `CT_LINUX_VERSION` is <= your target kernel version.

### Connection still fails after installation

1. Ensure environment variables are set: `ssh server 'echo $VSCODE_SERVER_CUSTOM_GLIBC_LINKER'`
2. Clear VS Code Server cache: `ssh server 'rm -rf ~/.vscode-server'`
3. Check that patchelf is executable: `ssh server '~/.local/bin/patchelf --version'`

### Build fails with disk space errors

crosstool-ng needs significant disk space during build. Ensure Docker has at least 20GB available.

## References

- [VS Code Remote FAQ - Older Linux Distributions](https://code.visualstudio.com/docs/remote/faq#_can-i-run-vs-code-server-on-older-linux-distributions)
- [crosstool-ng Documentation](https://crosstool-ng.github.io/docs/)
- [Microsoft's VS Code Linux Build Agent Config](https://github.com/nicknisi/vscode-linux-build-agent)
- [patchelf GitHub](https://github.com/NixOS/patchelf)
