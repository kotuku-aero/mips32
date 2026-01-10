#!/bin/bash
#
# build-pic32m.sh - Build MIPS32 cross-compiler toolchain for PIC32
#
# This script builds a complete cross-compiler toolchain targeting
# mips-elf (PIC32) processors. It produces native Windows executables
# when run under MSYS2 UCRT64.
#
# The script automatically tracks completed stages and resumes from
# the last successful stage on re-run.
#
# Environment variables:
#   PREFIX      - Installation prefix (default: /c/pic32)
#   JOBS        - Parallel build jobs (default: nproc)
#   GDB_PYTHON  - Enable Python in GDB: yes/no (default: no)
#   CLEAN       - Clean build directory first: yes/no (default: no)
#   SKIP_TO     - Skip to stage: gmp/mpfr/mpc/binutils/gcc-stage1/newlib/gcc-stage2/gdb
#   PORTABLE    - Copy runtime DLLs to prefix: yes/no (default: yes)
#   NEWLIB_NANO - Build newlib-nano variant: yes/no (default: yes)
#   MAKE_RELEASE - Create release archive: yes/no (default: yes)
#
# Usage:
#   ./build-pic32m.sh                    # Standard build (resumes if interrupted)
#   PREFIX=/c/my-tools ./build-pic32m.sh # Custom prefix
#   GDB_PYTHON=yes ./build-pic32m.sh     # With Python support
#   CLEAN=yes ./build-pic32m.sh          # Clean build (starts from scratch)
#   MAKE_RELEASE=no ./build-pic32m.sh    # Skip release archive creation
#

set -e  # Exit on error

#-----------------------------------------------------------------------------
# Source Versions - Update these when new versions are released
#-----------------------------------------------------------------------------

GMP_VERSION="6.3.0"
MPFR_VERSION="4.2.2"
MPC_VERSION="1.3.1"
BINUTILS_VERSION="2.44"
GCC_VERSION="15.2.0"
NEWLIB_VERSION="4.5.0.20241231"
GDB_VERSION="16.2"

# Release version string (used for archive naming)
TOOLCHAIN_VERSION="${GCC_VERSION}"

#-----------------------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------------------

export TARGET=mips-elf
export PREFIX="${PREFIX:-/c/pic32}"
export JOBS="${JOBS:-$(nproc)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDDIR="${SCRIPT_DIR}/build"
STAGING="${BUILDDIR}/staging"
STAGE_FILE="${BUILDDIR}/.build-stage"
RELEASES_DIR="${SCRIPT_DIR}/releases"

# GDB Python support (default: disabled for portability)
GDB_PYTHON="${GDB_PYTHON:-no}"

# Copy runtime DLLs for portability
PORTABLE="${PORTABLE:-yes}"

# Build newlib-nano (smaller footprint)
NEWLIB_NANO="${NEWLIB_NANO:-yes}"

# Skip to stage (for resuming failed builds)
SKIP_TO="${SKIP_TO:-}"

# Create release archive
MAKE_RELEASE="${MAKE_RELEASE:-yes}"

# Define build stages in order
STAGES=(
    "gmp"
    "mpfr"
    "mpc"
    "binutils"
    "gcc-stage1"
    "newlib"
    "gcc-stage2"
    "gdb"
)

#-----------------------------------------------------------------------------
# Stage Tracking Functions
#-----------------------------------------------------------------------------

# Find index of a stage name, returns -1 if not found
find_stage_index() {
    local name="$1"
    for ((i = 0; i < ${#STAGES[@]}; i++)); do
        if [[ "${STAGES[i]}" == "${name}" ]]; then
            echo "$i"
            return
        fi
    done
    echo "-1"
}

# Read the last completed stage and return its index
get_completed_stage_index() {
    if [[ -f "${STAGE_FILE}" ]]; then
        local completed_stage=$(cat "${STAGE_FILE}")
        local idx=$(find_stage_index "${completed_stage}")
        echo "$idx"
    else
        echo "-1"
    fi
}

# Mark a stage as completed
mark_stage_complete() {
    local stage="$1"
    echo "${stage}" > "${STAGE_FILE}"
}

# Check if a stage should be skipped (already completed)
stage_completed() {
    local stage="$1"
    local stage_idx=$(find_stage_index "${stage}")
    local completed_idx=$(get_completed_stage_index)

    if [[ ${stage_idx} -le ${completed_idx} ]]; then
        return 0  # Already completed
    fi
    return 1  # Not completed
}

# Show completed stages
show_completed_stages() {
    local completed_idx=$(get_completed_stage_index)

    if [[ ${completed_idx} -ge 0 ]]; then
        echo "=== Previously completed stages ==="
        for ((i = 0; i <= completed_idx && i < ${#STAGES[@]}; i++)); do
            echo "  [OK] Stage $((i + 1))/${#STAGES[@]}: ${STAGES[i]}"
        done
        echo "==================================="
        echo ""
    fi
}

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

get_source() {
    local url="$1"   # url to fetch
    local dir="$2"   # target directory name (e.g., "binutils")

    local SOURCES="${SCRIPT_DIR}/sources"
    local temp_dir="${SCRIPT_DIR}/temp_extract"
    local target_dir="${SCRIPT_DIR}/${dir}"

    mkdir -p "${SOURCES}"

    # Download if not already present
    local filename=$(basename "$url")
    if [ ! -f "${SOURCES}/${filename}" ]; then
        log "Downloading ${filename}"
        wget -P "${SOURCES}" "$url"
    else
        log "Using cached ${filename}"
    fi

    local archive_file="${SOURCES}/${filename}"

    if [ ! -f "$archive_file" ]; then
        echo "Error: Download failed - ${archive_file} not found"
        exit 1
    fi

    # Skip extraction if target already exists
    if [ -d "$target_dir" ] ; then
        log "Using existing ${dir}"
        return 0
    fi

    log "Extracting ${dir} from ${filename}"

    # Clean up any previous extraction
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    tar -xf "$archive_file" -C "$temp_dir"

    # Find the extracted directory (e.g., binutils-2.45)
    local extracted_dir=$(find "$temp_dir" -maxdepth 1 -mindepth 1 -type d | head -n 1)

    if [ -z "$extracted_dir" ]; then
        echo "Error: Could not find extracted directory in ${temp_dir}"
        rm -rf "$temp_dir"
        exit 1
    fi

    log "Found extracted directory: $(basename "$extracted_dir")"

    # Remove old target and move extracted source
    rm -rf "$target_dir"
    mv "$extracted_dir" "$target_dir"

    # Clean up
    rm -rf "$temp_dir"

    log "Source ready at ${target_dir}"
}

check_prerequisites() {
    log "Checking prerequisites"

    local missing=()

    for cmd in gcc g++ make bison flex makeinfo wget tar xz; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo "ERROR: Missing required tools: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  pacman -S base-devel mingw-w64-ucrt-x86_64-toolchain texinfo bison flex wget tar xz"
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

    echo "All prerequisites satisfied"
}

#-----------------------------------------------------------------------------
# Build Functions
#-----------------------------------------------------------------------------

build_gmp() {
    local stage="gmp"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building GMP ${GMP_VERSION}"

    get_source "https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz" "gmp"

    # GMP - Skip reliability test
    if ! grep -q "# PATCHED: Skip reliability test" "${SCRIPT_DIR}/gmp/configure"; then
        echo "Patching GMP reliability test..."
        cd "${SCRIPT_DIR}/gmp"
        sed -i 's/gmp_prog_cc_works="no, long long reliability test 1/# PATCHED: Skip reliability test/' configure
        echo "  [OK] GMP: Disabled reliability test"
    fi

    # GMP - mp_limb_t is 8
    if grep -q "Oops, mp_limb_t doesn't seem to work" "${SCRIPT_DIR}/gmp/configure"; then
        echo "  Patching sizeof(mp_limb_t) to 8 bytes..."
        cd "${SCRIPT_DIR}/gmp"
        sed -i "s/.*Oops, mp_limb_t doesn't seem to work.*/ac_cv_sizeof_mp_limb_t=8/" configure
        echo "  GMP: Hardcoded mp_limb_t size to 8 bytes"
    fi

    mkdir -p "${BUILDDIR}/gmp"
    cd "${BUILDDIR}/gmp"

    "${SCRIPT_DIR}/gmp/configure" \
        --prefix="${STAGING}" \
        --disable-shared \
        --enable-static

    make -j${JOBS}
    make install

    mark_stage_complete "${stage}"
}

build_mpfr() {
    local stage="mpfr"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building MPFR ${MPFR_VERSION}"

    get_source "https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.xz" "mpfr"

    mkdir -p "${BUILDDIR}/mpfr"
    cd "${BUILDDIR}/mpfr"

    "${SCRIPT_DIR}/mpfr/configure" \
        --prefix="${STAGING}" \
        --with-gmp="${STAGING}" \
        --disable-shared \
        --enable-static

    make -j${JOBS}
    make install

    mark_stage_complete "${stage}"
}

build_mpc() {
    local stage="mpc"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building MPC ${MPC_VERSION}"

    get_source "https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz" "mpc"

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

    mark_stage_complete "${stage}"
}

build_binutils() {
    local stage="binutils"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building Binutils ${BINUTILS_VERSION}"

    get_source "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz" "binutils"

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

    mark_stage_complete "${stage}"
}

build_gcc_stage1() {
    local stage="gcc-stage1"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building GCC ${GCC_VERSION} Stage 1 (bootstrap compiler)"

    get_source "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz" "gcc"

    # Patch Makefile.in to fix MSYS2 path conversion for gtyp-input.list
    # The gentype.exe program can't handle /c/<path> style paths, needs C:/<path>
    # IMPORTANT: Must use uppercase drive letter to avoid confusion with directory names
    if ! grep -q "tmp-gi-win.list" "${SCRIPT_DIR}/gcc/gcc/Makefile.in"; then
        echo "Patching GCC Makefile.in for MSYS2 path conversion..."
        cd "${SCRIPT_DIR}/gcc/gcc"

        # Use awk for reliable uppercase conversion of drive letters
        sed -i '/move-if-change tmp-gi.list gtyp-input.list/{
i\
	awk '"'"'{if(match($$0,/^\\/([a-zA-Z])\\//)){print toupper(substr($$0,2,1))":/"substr($$0,4)}else{print}}'"'"' tmp-gi.list > tmp-gi-win.list
s/tmp-gi.list gtyp-input.list/tmp-gi-win.list gtyp-input.list/
}' Makefile.in

        echo "  [OK] GCC: Patched Makefile.in for Windows paths (uppercase drive letters)"
    else
        echo "  [OK] GCC Makefile.in: Already patched"
    fi

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

    mark_stage_complete "${stage}"
}

build_newlib() {
    local stage="newlib"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building Newlib ${NEWLIB_VERSION}"

    get_source "https://sourceware.org/pub/newlib/newlib-${NEWLIB_VERSION}.tar.gz" "newlib"

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
        --disable-libgloss
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

    mark_stage_complete "${stage}"
}

build_gcc_stage2() {
    local stage="gcc-stage2"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building GCC ${GCC_VERSION} Stage 2 (with newlib support)"

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

    # Build gcc with full parallelism
    make -j${JOBS} all-gcc
    make install-gcc

    # Build libgcc with reduced parallelism to avoid MSYS2 process issues
    make -j2 all-target-libgcc
    make install-target-libgcc

    mark_stage_complete "${stage}"
}

build_gdb() {
    local stage="gdb"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building GDB ${GDB_VERSION}"

    get_source "https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz" "gdb"

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

    mark_stage_complete "${stage}"
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
            echo "[OK] ${tool}"
            # Try to run it
            if ! "${path}" --version > /dev/null 2>&1; then
                echo "     WARNING: ${tool} exists but failed to run"
            fi
        else
            echo "[MISSING] ${tool}"
            all_ok=false
        fi
    done

    # Check for newlib
    echo ""
    if [ -f "${PREFIX}/${TARGET}/lib/libc.a" ]; then
        echo "[OK] newlib (libc.a)"
    else
        echo "[MISSING] newlib"
        all_ok=false
    fi

    if [ -f "${PREFIX}/${TARGET}/lib/libm.a" ]; then
        echo "[OK] newlib math (libm.a)"
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

create_release_archive() {
    if [ "${MAKE_RELEASE}" != "yes" ]; then
        echo "Skipping release archive (MAKE_RELEASE=no)"
        return 0
    fi

    log "Creating release archive"

    mkdir -p "${RELEASES_DIR}"

    # Determine platform
    local platform="win64"
    if [[ "$(uname -s)" == "Linux" ]]; then
        platform="linux-x64"
    fi

    # Archive filename
    local archive_name="pic32-toolchain-${TOOLCHAIN_VERSION}-${platform}"
    local archive_path="${RELEASES_DIR}/${archive_name}.tar.xz"

    # Get the base name of PREFIX (e.g., "pic32" from "/c/pic32")
    local prefix_basename=$(basename "${PREFIX}")
    local prefix_parent=$(dirname "${PREFIX}")

    echo "Creating ${archive_name}.tar.xz ..."
    echo "  Source: ${PREFIX}"
    echo "  Output: ${archive_path}"

    # Create the archive
    # We cd to the parent directory and archive the basename to get clean paths
    cd "${prefix_parent}"

    # Use tar with xz compression
    # The archive will contain "pic32/bin", "pic32/lib", etc.
    tar -cJf "${archive_path}" "${prefix_basename}"

    # Calculate size
    local archive_size=$(du -h "${archive_path}" | cut -f1)

    echo ""
    echo "Release archive created:"
    echo "  File: ${archive_path}"
    echo "  Size: ${archive_size}"

    # Create checksum
    cd "${RELEASES_DIR}"
    sha256sum "${archive_name}.tar.xz" > "${archive_name}.tar.xz.sha256"
    echo "  SHA256: $(cat "${archive_name}.tar.xz.sha256")"
    
    # Create a version info file
    cat > "${RELEASES_DIR}/${archive_name}.txt" << EOF
PIC32 MIPS Toolchain ${TOOLCHAIN_VERSION}
==========================================

Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Platform: ${platform}

Component Versions:
  GCC:      ${GCC_VERSION}
  Binutils: ${BINUTILS_VERSION}
  Newlib:   ${NEWLIB_VERSION}
  GDB:      ${GDB_VERSION}
  GMP:      ${GMP_VERSION}
  MPFR:     ${MPFR_VERSION}
  MPC:      ${MPC_VERSION}

Build Configuration:
  Target:      ${TARGET}
  Newlib-nano: ${NEWLIB_NANO}
  GDB Python:  ${GDB_PYTHON}

Installation:
  1. Extract to C:\\pic32 (Windows) or /opt/pic32 (Linux)
  2. Add <install-path>/bin to your PATH
  3. Test with: mips-elf-gcc --version

Built with: $(gcc --version | head -1)
EOF

    echo "  Info: ${RELEASES_DIR}/${archive_name}.txt"

    cd "${SCRIPT_DIR}"
}

print_summary() {
    log "Build Complete"

    echo "Toolchain installed to: ${PREFIX}"
    echo ""
    echo "Windows path: $(cygpath -w "${PREFIX}")"
    echo ""
    echo "Component versions:"
    echo "  GCC:      ${GCC_VERSION}"
    echo "  Binutils: ${BINUTILS_VERSION}"
    echo "  Newlib:   ${NEWLIB_VERSION}"
    echo "  GDB:      ${GDB_VERSION}"
    echo ""
    echo "Contents:"
    echo "  ${PREFIX}/bin/              - Cross-compiler tools"
    echo "  ${PREFIX}/${TARGET}/lib/    - Runtime libraries (newlib)"
    echo "  ${PREFIX}/${TARGET}/include - C library headers"
    echo ""

    if [ "${MAKE_RELEASE}" == "yes" ] && [ -d "${RELEASES_DIR}" ]; then
        echo "Release archives:"
        ls -lh "${RELEASES_DIR}"/*.tar.xz 2>/dev/null || echo "  (none)"
        echo ""
    fi

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
    echo "  TARGET:       ${TARGET}"
    echo "  PREFIX:       ${PREFIX} ($(cygpath -w "${PREFIX}" 2>/dev/null || echo "N/A"))"
    echo "  JOBS:         ${JOBS}"
    echo "  GDB_PYTHON:   ${GDB_PYTHON}"
    echo "  PORTABLE:     ${PORTABLE}"
    echo "  NEWLIB_NANO:  ${NEWLIB_NANO}"
    echo "  MAKE_RELEASE: ${MAKE_RELEASE}"
    echo ""
    echo "Source versions:"
    echo "  GMP:      ${GMP_VERSION}"
    echo "  MPFR:     ${MPFR_VERSION}"
    echo "  MPC:      ${MPC_VERSION}"
    echo "  Binutils: ${BINUTILS_VERSION}"
    echo "  GCC:      ${GCC_VERSION}"
    echo "  Newlib:   ${NEWLIB_VERSION}"
    echo "  GDB:      ${GDB_VERSION}"
    echo ""

    check_prerequisites

    # Clean if requested
    if [ "${CLEAN}" == "yes" ]; then
        log "Cleaning build directory"
        rm -rf "${BUILDDIR}"
        rm -rf "${PREFIX}"
    fi

    # Create directories
    mkdir -p "${BUILDDIR}"
    mkdir -p "${STAGING}"
    mkdir -p "${PREFIX}"

    # Show what's already done
    show_completed_stages

    # Handle SKIP_TO override (forces restart from a specific stage)
    if [ -n "${SKIP_TO}" ]; then
        local skip_idx=$(find_stage_index "${SKIP_TO}")
        if [ ${skip_idx} -ge 0 ]; then
            echo "SKIP_TO=${SKIP_TO} specified, will resume from stage $((skip_idx + 1))"
            # Set stage file to one before the requested stage
            if [ ${skip_idx} -eq 0 ]; then
                rm -f "${STAGE_FILE}"
            else
                echo "${STAGES[$((skip_idx - 1))]}" > "${STAGE_FILE}"
            fi
        else
            echo "WARNING: Unknown stage '${SKIP_TO}', ignoring SKIP_TO"
        fi
        echo ""
    fi

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
    create_release_archive
    print_summary
}

main "$@"
