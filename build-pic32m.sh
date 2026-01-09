#!/bin/bash
#
# build-pic32m.sh - Build MIPS32 cross-compiler toolchain for PIC32
#
# This script builds a complete cross-compiler toolchain targeting
# mips-elf (PIC32) processors. It produces native Windows executables
# when run under MSYS2 UCRT64.
#
# Environment variables:
#   PREFIX      - Installation prefix (default: /c/pic32)
#   JOBS        - Parallel build jobs (default: nproc)
#   GDB_PYTHON  - Enable Python in GDB: yes/no (default: no)
#   CLEAN       - Clean build directory first: yes/no (default: no)
#   SKIP_TO     - Skip to stage: gmp/mpfr/mpc/binutils/gcc-stage1/newlib/gcc-stage2/gdb
#   PORTABLE    - Copy runtime DLLs to prefix: yes/no (default: yes)
#   NEWLIB_NANO - Build newlib-nano variant: yes/no (default: yes)
#
# Usage:
#   ./build-pic32m.sh                    # Standard build
#   PREFIX=/c/my-tools ./build-pic32m.sh # Custom prefix
#   GDB_PYTHON=yes ./build-pic32m.sh     # With Python support
#   CLEAN=yes ./build-pic32m.sh          # Clean build
#

set -e  # Exit on error

#-----------------------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------------------

export TARGET=mips-elf
export PREFIX="${PREFIX:-/c/pic32}"
export JOBS="${JOBS:-$(nproc)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDDIR="${SCRIPT_DIR}/build"
STAGING="${BUILDDIR}/staging"

# GDB Python support (default: disabled for portability)
GDB_PYTHON="${GDB_PYTHON:-no}"

# Copy runtime DLLs for portability
PORTABLE="${PORTABLE:-yes}"

# Build newlib-nano (smaller footprint)
NEWLIB_NANO="${NEWLIB_NANO:-yes}"

# Skip to stage (for resuming failed builds)
SKIP_TO="${SKIP_TO:-}"

#-----------------------------------------------------------------------------
# Utility Functions
#-----------------------------------------------------------------------------

log() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

check_prerequisites() {
    log "Checking prerequisites"
    
    local missing=()
    
    for cmd in gcc g++ make bison flex makeinfo; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo "ERROR: Missing required tools: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  pacman -S base-devel mingw-w64-ucrt-x86_64-toolchain texinfo bison flex"
        exit 1
    fi
    
    # Check we're in UCRT64 environment
    if [[ ! "$MSYSTEM" == "UCRT64" ]]; then
        echo "WARNING: Not running in UCRT64 environment (MSYSTEM=$MSYSTEM)"
        echo "         For best results, use 'MSYS2 UCRT64' terminal"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check for newlib source
    if [ ! -d "${SCRIPT_DIR}/newlib" ]; then
        echo "WARNING: newlib source not found at ${SCRIPT_DIR}/newlib"
        echo "         Download from: https://sourceware.org/newlib/"
        echo "         Or: git clone git://sourceware.org/git/newlib-cygwin.git newlib"
        echo ""
        read -p "Continue without newlib? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    echo "All prerequisites satisfied"
}

should_skip() {
    local stage="$1"
    local stages="gmp mpfr mpc binutils gcc-stage1 newlib gcc-stage2 gdb"
    
    if [ -z "$SKIP_TO" ]; then
        return 1  # Don't skip
    fi
    
    # Check if we've reached the skip target
    for s in $stages; do
        if [ "$s" == "$SKIP_TO" ]; then
            SKIP_TO=""  # Clear so subsequent stages run
            return 1    # Don't skip this one
        fi
        if [ "$s" == "$stage" ]; then
            echo "Skipping $stage (SKIP_TO=$SKIP_TO)"
            return 0    # Skip
        fi
    done
    
    return 1
}

#-----------------------------------------------------------------------------
# Build Functions
#-----------------------------------------------------------------------------

build_gmp() {
    should_skip "gmp" && return 0
    log "Building GMP"
    
    mkdir -p "${BUILDDIR}/gmp"
    cd "${BUILDDIR}/gmp"
    
    "${SCRIPT_DIR}/gmp/configure" \
        --prefix="${STAGING}" \
        --disable-shared \
        --enable-static
    
    make -j${JOBS}
    make install
}

build_mpfr() {
    should_skip "mpfr" && return 0
    log "Building MPFR"
    
    mkdir -p "${BUILDDIR}/mpfr"
    cd "${BUILDDIR}/mpfr"
    
    "${SCRIPT_DIR}/mpfr/configure" \
        --prefix="${STAGING}" \
        --with-gmp="${STAGING}" \
        --disable-shared \
        --enable-static
    
    make -j${JOBS}
    make install
}

build_mpc() {
    should_skip "mpc" && return 0
    log "Building MPC"
    
    mkdir -p "${BUILDDIR}/mpc"
    cd "${BUILDDIR}/mpc"
    
    "${SCRIPT_DIR}/mpc/configure" \
        --prefix="${STAGING}" \
        --with-gmp="${STAGING}" \
        --with-mpfr="${STAGING}" \
        --disable-shared \
        --enable-static
    
    make -j${JOBS}
    make install
}

build_binutils() {
    should_skip "binutils" && return 0
    log "Building Binutils"
    
    mkdir -p "${BUILDDIR}/binutils"
    cd "${BUILDDIR}/binutils"
    
    "${SCRIPT_DIR}/binutils/configure" \
        --prefix="${PREFIX}" \
        --target="${TARGET}" \
        --disable-nls \
        --disable-shared \
        --disable-werror
    
    make -j${JOBS}
    make install
}

build_gcc_stage1() {
    should_skip "gcc-stage1" && return 0
    log "Building GCC Stage 1 (bootstrap compiler)"
    
    # GCC needs to find the newly built binutils
    export PATH="${PREFIX}/bin:${PATH}"
    
    mkdir -p "${BUILDDIR}/gcc-stage1"
    cd "${BUILDDIR}/gcc-stage1"
    
    "${SCRIPT_DIR}/gcc/configure" \
        --prefix="${PREFIX}" \
        --target="${TARGET}" \
        --enable-languages=c \
        --disable-threads \
        --disable-shared \
        --disable-nls \
        --disable-libssp \
        --disable-libquadmath \
        --disable-libgomp \
        --disable-libatomic \
        --with-newlib \
        --without-headers \
        --with-gmp="${STAGING}" \
        --with-mpfr="${STAGING}" \
        --with-mpc="${STAGING}"
    
    make -j${JOBS} all-gcc
    make install-gcc
}

build_newlib() {
    should_skip "newlib" && return 0
    
    log "Building Newlib"
    
    # Ensure the stage1 compiler is in PATH
    export PATH="${PREFIX}/bin:${PATH}"
    
    mkdir -p "${BUILDDIR}/newlib"
    cd "${BUILDDIR}/newlib"
    
    # Common newlib configuration
    local newlib_opts=(
        --prefix="${PREFIX}"
        --target="${TARGET}"
        --disable-newlib-supplied-syscalls
        --enable-newlib-reent-small
        --disable-newlib-fvwrite-in-streamio
        --disable-newlib-fseek-optimization
        --disable-newlib-wide-orient
        --enable-newlib-nano-malloc
        --disable-newlib-unbuf-stream-opt
        --enable-lite-exit
        --enable-newlib-global-atexit
        --disable-nls
    )
    
    if [ "${NEWLIB_NANO}" == "yes" ]; then
        log "Building Newlib-nano variant"
        newlib_opts+=(
            --enable-newlib-nano-formatted-io
            --disable-newlib-io-float
        )
    fi
    
    "${SCRIPT_DIR}/newlib/configure" "${newlib_opts[@]}"
    
    make -j${JOBS}
    make install
}

build_gcc_stage2() {
    should_skip "gcc-stage2" && return 0
    log "Building GCC Stage 2 (with newlib support)"
    
    # GCC needs to find binutils and stage1 compiler
    export PATH="${PREFIX}/bin:${PATH}"
    
    mkdir -p "${BUILDDIR}/gcc-stage2"
    cd "${BUILDDIR}/gcc-stage2"
    
    "${SCRIPT_DIR}/gcc/configure" \
        --prefix="${PREFIX}" \
        --target="${TARGET}" \
        --enable-languages=c,c++ \
        --disable-threads \
        --disable-shared \
        --disable-nls \
        --disable-libssp \
        --disable-libquadmath \
        --disable-libgomp \
        --disable-libatomic \
        --with-newlib \
        --with-gmp="${STAGING}" \
        --with-mpfr="${STAGING}" \
        --with-mpc="${STAGING}"
    
    make -j${JOBS} all-gcc all-target-libgcc
    make install-gcc install-target-libgcc
}

build_gdb() {
    should_skip "gdb" && return 0
    log "Building GDB"
    
    mkdir -p "${BUILDDIR}/gdb"
    cd "${BUILDDIR}/gdb"
    
    local python_opt="--with-python=no"
    if [ "${GDB_PYTHON}" == "yes" ]; then
        python_opt="--with-python=$(which python3)"
        echo "Building GDB with Python support"
    else
        echo "Building GDB without Python support (portable)"
    fi
    
    "${SCRIPT_DIR}/gdb/configure" \
        --prefix="${PREFIX}" \
        --target="${TARGET}" \
        --with-gmp="${STAGING}" \
        --with-mpfr="${STAGING}" \
        --disable-nls \
        --disable-werror \
        ${python_opt}
    
    make -j${JOBS}
    make install
}

copy_runtime_dlls() {
    if [ "${PORTABLE}" != "yes" ]; then
        return 0
    fi
    
    log "Copying runtime DLLs for portability"
    
    local dlls=(
        "libgcc_s_seh-1.dll"
        "libstdc++-6.dll"
        "libwinpthread-1.dll"
    )
    
    local dll_src="/ucrt64/bin"
    local dll_dst="${PREFIX}/bin"
    
    for dll in "${dlls[@]}"; do
        if [ -f "${dll_src}/${dll}" ]; then
            echo "Copying ${dll}"
            cp "${dll_src}/${dll}" "${dll_dst}/"
        else
            echo "WARNING: ${dll} not found in ${dll_src}"
        fi
    done
    
    # If Python is enabled, we need more DLLs
    if [ "${GDB_PYTHON}" == "yes" ]; then
        echo ""
        echo "NOTE: GDB was built with Python support."
        echo "      You may need to copy additional Python DLLs for portability."
        echo "      Or set PYTHONHOME environment variable on target machines."
    fi
}

verify_build() {
    log "Verifying build"
    
    local tools=(
        "mips-elf-gcc"
        "mips-elf-g++"
        "mips-elf-as"
        "mips-elf-ld"
        "mips-elf-objcopy"
        "mips-elf-objdump"
        "mips-elf-gdb"
    )
    
    local all_ok=true
    
    for tool in "${tools[@]}"; do
        local path="${PREFIX}/bin/${tool}.exe"
        if [ -f "$path" ]; then
            echo "✓ ${tool}"
            # Try to run it
            if ! "${path}" --version > /dev/null 2>&1; then
                echo "  WARNING: ${tool} exists but failed to run"
            fi
        else
            echo "✗ ${tool} NOT FOUND"
            all_ok=false
        fi
    done
    
    # Check for newlib
    echo ""
    if [ -f "${PREFIX}/${TARGET}/lib/libc.a" ]; then
        echo "✓ newlib (libc.a)"
    else
        echo "✗ newlib NOT FOUND"
        all_ok=false
    fi
    
    if [ -f "${PREFIX}/${TARGET}/lib/libm.a" ]; then
        echo "✓ newlib math (libm.a)"
    fi
    
    echo ""
    
    if [ "$all_ok" = true ]; then
        echo "All tools built successfully!"
    else
        echo "Some tools are missing - check build log for errors"
        return 1
    fi
    
    # Show DLL dependencies
    if command -v ntldd &> /dev/null; then
        echo ""
        echo "DLL dependencies for mips-elf-gcc:"
        ntldd "${PREFIX}/bin/mips-elf-gcc.exe" 2>/dev/null | grep -v "Windows" | head -20
    fi
}

print_summary() {
    log "Build Complete"
    
    echo "Toolchain installed to: ${PREFIX}"
    echo ""
    echo "Windows path: $(cygpath -w "${PREFIX}")"
    echo ""
    echo "Contents:"
    echo "  ${PREFIX}/bin/          - Cross-compiler tools"
    echo "  ${PREFIX}/${TARGET}/lib/    - Runtime libraries (newlib)"
    echo "  ${PREFIX}/${TARGET}/include - C library headers"
    echo ""
    echo "Next steps:"
    echo "  1. Add $(cygpath -w "${PREFIX}/bin") to your Windows PATH"
    echo "  2. Open a new Command Prompt and test:"
    echo "     mips-elf-gcc --version"
    echo ""
    echo "To use newlib in your projects:"
    echo "  mips-elf-gcc -T linker.ld -nostartfiles startup.c main.c syscalls.c -o firmware.elf"
    echo ""
    echo "For CLion integration, see README.md"
}

#-----------------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------------

main() {
    echo "MIPS32 Cross-Compiler Toolchain Builder"
    echo ""
    echo "Configuration:"
    echo "  TARGET:      ${TARGET}"
    echo "  PREFIX:      ${PREFIX} ($(cygpath -w "${PREFIX}" 2>/dev/null || echo "N/A"))"
    echo "  JOBS:        ${JOBS}"
    echo "  GDB_PYTHON:  ${GDB_PYTHON}"
    echo "  PORTABLE:    ${PORTABLE}"
    echo "  NEWLIB_NANO: ${NEWLIB_NANO}"
    echo "  SKIP_TO:     ${SKIP_TO:-<none>}"
    echo ""
    
    check_prerequisites
    
    # Clean if requested
    if [ "${CLEAN}" == "yes" ]; then
        log "Cleaning build directory"
        rm -rf "${BUILDDIR}"
    fi
    
    # Create directories
    mkdir -p "${BUILDDIR}"
    mkdir -p "${STAGING}"
    mkdir -p "${PREFIX}"
    
    # Build stages (two-stage GCC build for newlib)
    build_gmp
    build_mpfr
    build_mpc
    build_binutils
    build_gcc_stage1    # Bootstrap compiler without libc
    build_newlib        # Build newlib using stage1 compiler
    build_gcc_stage2    # Full compiler with newlib support
    build_gdb
    
    # Post-build
    copy_runtime_dlls
    verify_build
    print_summary
}

main "$@"
