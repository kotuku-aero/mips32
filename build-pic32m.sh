#!/bin/bash
#
# build-pic32m.sh - Build MIPS32 cross-compiler toolchain for PIC32
#
# This script builds a complete cross-compiler toolchain targeting
# mipsisa32r2-elf (PIC32) processors with full MULTILIB support.
# It produces native Windows executables when run under MSYS2 UCRT64.
#
# MULTILIB SUPPORT:
#   Built with --with-float=hard, the toolchain provides these variants:
#   - . (root)              - hard-float, big-endian (default)
#   - el/mips32r2           - hard-float, little-endian, mips32r2 (PIC32MZ EF)
#   - soft-float/el/mips32r2 - soft-float, little-endian, mips32r2 (PIC32MZ DA)
#   - Plus many other architecture/endian/float combinations
#
#   Use: mipsisa32r2-elf-gcc -print-multi-lib to see all variants
#
# The script automatically tracks completed stages and resumes from
# the last successful stage on re-run.
#
# Environment variables:
#   PREFIX      - Installation prefix (default: /c/pic32/mipsisa32r2-elf)
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
# Source Versions - GCC 14.2.0 for multilib support
#-----------------------------------------------------------------------------

GMP_VERSION="6.3.0"
MPFR_VERSION="4.2.1"
MPC_VERSION="1.3.1"
BINUTILS_VERSION="2.43.1"
GCC_VERSION="14.2.0"
NEWLIB_VERSION="4.4.0.20231231"
GDB_VERSION="15.1"

# Release version string (used for archive naming)
TOOLCHAIN_VERSION="${GCC_VERSION}-multilib"

#-----------------------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------------------

export TARGET=mipsisa32r2-elf
export PREFIX="${PREFIX:-/c/pic32}"
export JOBS="${JOBS:-$(nproc)}"

export PATH=${PREFIX}:$PATH

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

    echo "moving from $extracted_dir to $target_dir"

    mv "$extracted_dir" "$target_dir"

    if [ ! -d "$target_dir" ]; then
        echo "Error: Failed to move $extracted_dir to $target_dir after $max_retries attempts"
        echo "Try manually: mv $extracted_dir $target_dir"
        rm -rf "$temp_dir"
        exit 1
    fi

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
# GDB Patches for MSYS2/Windows compatibility
#-----------------------------------------------------------------------------

patch_gdb() {
    log "Patching GDB for MSYS2/Windows compatibility"

    # Patch 1: Fix static_assert C11 keyword clash in mips-formats.h
    local mips_formats="${SCRIPT_DIR}/gdb/opcodes/mips-formats.h"
    if [ -f "${mips_formats}" ]; then
        if grep -q 'static_assert\[' "${mips_formats}"; then
            echo "Patching mips-formats.h for C11 static_assert keyword clash..."
            sed -i 's/static_assert\[/_static_assert[/g' "${mips_formats}"
            echo "  [OK] Renamed static_assert arrays to _static_assert"
        else
            echo "  [OK] mips-formats.h: Already patched or not needed"
        fi
    fi

    # Patch 2: Fix signal handler calling convention in readline/signals.c
    local signals_c="${SCRIPT_DIR}/gdb/readline/readline/signals.c"
    if [ -f "${signals_c}" ]; then
        if ! grep -q "define VOID_SIGHANDLER" "${signals_c}"; then
            echo "Patching readline/signals.c for signal handler convention..."
            # Add VOID_SIGHANDLER define after #if defined (HANDLE_SIGNALS)
            sed -i '/#if defined (HANDLE_SIGNALS)/a\
\
#define VOID_SIGHANDLER' "${signals_c}"
            echo "  [OK] Added VOID_SIGHANDLER define"
        else
            echo "  [OK] readline/signals.c: VOID_SIGHANDLER already defined"
        fi

        # Fix SigHandler typedef
        if grep -q 'typedef RETSIGTYPE SigHandler ();' "${signals_c}"; then
            echo "Patching SigHandler typedef..."
            sed -i 's/typedef RETSIGTYPE SigHandler ();/typedef RETSIGTYPE SigHandler (int);/' "${signals_c}"
            echo "  [OK] Fixed SigHandler typedef"
        else
            echo "  [OK] readline/signals.c: SigHandler typedef already patched"
        fi
    fi

    # Patch 3: Fix signal handler in sim/common/nrun.c
    local nrun_c="${SCRIPT_DIR}/gdb/sim/common/nrun.c"
    if [ -f "${nrun_c}" ]; then
        if grep -q 'RETSIGTYPE (\*prev_sigint) ();' "${nrun_c}"; then
            echo "Patching sim/common/nrun.c for signal handler..."
            sed -i 's/RETSIGTYPE (\*prev_sigint) ();/RETSIGTYPE (*prev_sigint) (int);/' "${nrun_c}"
            echo "  [OK] Fixed prev_sigint declaration"
        else
            echo "  [OK] sim/common/nrun.c: Already patched or not needed"
        fi
    fi

    echo ""
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

    # remove the output directory so that we have new tools
    rm -rf "${PREFIX}"
    mkdir "${PREFIX}"

    get_source "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz" "binutils"

    # Fix static_assert keyword clash in mips-formats.h (C11 reserved keyword)
    # This may or may not be needed in 2.43.1
    local mips_formats="${SCRIPT_DIR}/binutils/opcodes/mips-formats.h"
    if [ -f "${mips_formats}" ] && grep -q 'static_assert\[' "${mips_formats}"; then
        echo "Patching mips-formats.h for C11 static_assert keyword clash..."
        sed -i 's/static_assert\[/static_assert_check[/g' "${mips_formats}"
        echo "  [OK] Renamed static_assert arrays to static_assert_check"
    fi

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

    log "Building GCC ${GCC_VERSION} Stage 1 (bootstrap compiler with multilib)"

    get_source "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz" "gcc"

    # Patch Makefile.in to fix MSYS2 path conversion for gtyp-input.list
    if ! grep -q "tmp-gi-win.list" "${SCRIPT_DIR}/gcc/gcc/Makefile.in"; then
        echo "Patching GCC Makefile.in for MSYS2 path conversion..."
        cd "${SCRIPT_DIR}/gcc/gcc"

        sed -i '/move-if-change tmp-gi.list gtyp-input.list/{
i\
	awk '"'"'{if(match($$0,/^\\/([a-zA-Z])\\//)){print toupper(substr($$0,2,1))":/"substr($$0,4)}else{print}}'"'"' tmp-gi.list > tmp-gi-win.list
s/tmp-gi.list gtyp-input.list/tmp-gi-win.list gtyp-input.list/
}' Makefile.in

        echo "  [OK] GCC: Patched Makefile.in for Windows paths"
    else
        echo "  [OK] GCC Makefile.in: Already patched"
    fi

    # CRITICAL: Clean any previous build directory to ensure fresh configure
    # This is necessary because multilib configuration is cached during configure
    if [ -d "${BUILDDIR}/gcc-stage1" ]; then
        echo "Removing previous gcc-stage1 build directory to ensure fresh configure..."
        rm -rf "${BUILDDIR}/gcc-stage1"
    fi

    mkdir -p "${BUILDDIR}/gcc-stage1"
    cd "${BUILDDIR}/gcc-stage1"

    # GCC configuration with --with-float=hard
    # Hard-float becomes the default; soft-float is a multilib variant
    "${SCRIPT_DIR}/gcc/configure" \
        --prefix="${PREFIX}" \
        --target="${TARGET}" \
        --enable-languages=c \
        --enable-fixed-point \
        --disable-threads \
        --disable-shared \
        --disable-nls \
        --disable-libssp \
        --disable-libquadmath \
        --disable-libgomp \
        --disable-libatomic \
        --with-newlib \
        --with-arch=mips32r2 \
        --without-headers \
        --with-gmp="${STAGING}" \
        --with-mpfr="${STAGING}" \
        --with-mpc="${STAGING}" \
        --with-float=hard \
        --enable-multilib

    make -j${JOBS} all-gcc

    make install-gcc

    # Verify multilib configuration
    echo ""
    echo "========================================="
    echo "Verifying Stage 1 GCC multilib configuration..."
    echo "========================================="
    if command -v "${PREFIX}/bin/${TARGET}-gcc" &> /dev/null; then
        "${PREFIX}/bin/${TARGET}-gcc" -print-multi-lib
    fi
    echo ""

    mark_stage_complete "${stage}"
}

build_newlib() {
    local stage="newlib"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building Newlib ${NEWLIB_VERSION} with multilib support"

    get_source "https://sourceware.org/pub/newlib/newlib-${NEWLIB_VERSION}.tar.gz" "newlib"

    # Verify that GCC stage1 has multilib support before proceeding
    echo "Checking GCC multilib configuration..."
    local multilib_output=$("${PREFIX}/bin/${TARGET}-gcc" -print-multi-lib 2>/dev/null)
    echo "GCC reports multilib variants:"
    echo "${multilib_output}"
    echo ""

    # Check for more than just the default variant
    local variant_count=$(echo "${multilib_output}" | wc -l)
    if [ "${variant_count}" -lt 2 ]; then
        echo ""
        echo "ERROR: GCC stage1 does not have multilib support!"
        echo "Expected multiple variants but only found: ${multilib_output}"
        echo "Please run: CLEAN=yes ./build-pic32m.sh to start fresh."
        echo ""
        exit 1
    fi
    echo "Found ${variant_count} multilib variants - OK"

    # CRITICAL: Clean any previous build directory to ensure fresh configure
    if [ -d "${BUILDDIR}/newlib" ]; then
        echo "Removing previous newlib build directory to ensure fresh configure..."
        rm -rf "${BUILDDIR}/newlib"
    fi

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
        --enable-multilib
    )

    if [ "${NEWLIB_NANO}" == "yes" ]; then
        log "Building Newlib-nano variant with multilib"
        newlib_opts+=(
            --enable-newlib-nano-formatted-io
            --disable-newlib-io-float
        )
    fi

    # Configure for multilib build
    "${SCRIPT_DIR}/newlib/configure" "${newlib_opts[@]}"

    # Build with reduced parallelism to avoid issues
    make -j2
    make install

    # Show installed library directories
    echo ""
    echo "========================================="
    echo "Installed newlib multilib directories:"
    echo "========================================="
    echo "Contents of ${PREFIX}/${TARGET}/lib:"
    ls -la "${PREFIX}/${TARGET}/lib/" 2>/dev/null | head -20
    echo ""

    mark_stage_complete "${stage}"
}

build_gcc_stage2() {
    local stage="gcc-stage2"

    if stage_completed "${stage}"; then
        echo "[OK] Stage: ${stage} (already completed)"
        return 0
    fi

    log "Building GCC ${GCC_VERSION} Stage 2 (with newlib and multilib support)"

    # CRITICAL: Clean any previous build directory to ensure fresh configure
    # Stage2 must also pick up the multilib configuration
    if [ -d "${BUILDDIR}/gcc-stage2" ]; then
        echo "Removing previous gcc-stage2 build directory to ensure fresh configure..."
        rm -rf "${BUILDDIR}/gcc-stage2"
    fi

    mkdir -p "${BUILDDIR}/gcc-stage2"
    cd "${BUILDDIR}/gcc-stage2"

    "${SCRIPT_DIR}/gcc/configure" \
        --prefix="${PREFIX}" \
        --target="${TARGET}" \
        --enable-languages=c,c++ \
        --enable-fixed-point \
        --disable-threads \
        --disable-shared \
        --disable-nls \
        --disable-libssp \
        --disable-libquadmath \
        --disable-libgomp \
        --disable-libatomic \
        --with-arch=mips32r2 \
        --with-newlib \
        --with-gmp="${STAGING}" \
        --with-mpfr="${STAGING}" \
        --with-mpc="${STAGING}" \
        --with-float=hard \
        --enable-multilib

    # Build gcc with full parallelism
    make -j${JOBS} all-gcc
    make install-gcc

    # Build libgcc with reduced parallelism to avoid MSYS2 process issues
    make -j2 all-target-libgcc
    make install-target-libgcc

    # Show installed libgcc directories
    echo ""
    echo "========================================="
    echo "Installed libgcc multilib directories:"
    echo "========================================="
    echo "Contents of ${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}:"
    ls -la "${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}/" 2>/dev/null | head -20
    echo ""

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

    # Apply GDB patches for MSYS2/Windows compatibility
    patch_gdb

    mkdir -p "${BUILDDIR}/gdb"
    cd "${BUILDDIR}/gdb"

    local gdb_opts=(
        --prefix="${PREFIX}"
        --target="${TARGET}"
        --disable-nls
        --disable-shared
        --disable-werror
    )

    if [ "${GDB_PYTHON}" == "yes" ]; then
        echo "Building GDB with Python support"
        gdb_opts+=(--with-python)
    else
        gdb_opts+=(--without-python)
    fi

    "${SCRIPT_DIR}/gdb/configure" "${gdb_opts[@]}"

    make -j${JOBS}
    make install

    mark_stage_complete "${stage}"
}

copy_runtime_dlls() {
    if [ "${PORTABLE}" != "yes" ]; then
        echo "Skipping DLL copy (PORTABLE=no)"
        return 0
    fi

    log "Copying runtime DLLs for portability"

    local dll_dst="${PREFIX}/bin"

    # Common search paths for MSYS2/UCRT64
    local search_paths="/ucrt64/bin /mingw64/bin /usr/bin"

    # Recursively find and copy DLL dependencies
    local pass=0
    local max_passes=5
    local total_copied=0

    while [ $pass -lt $max_passes ]; do
        local dlls_needed=""

        for exe in "${dll_dst}"/*.exe "${dll_dst}"/*.dll; do
            [ -f "$exe" ] || continue

            for dll in $(objdump -p "$exe" 2>/dev/null | grep "DLL Name:" | awk '{print $3}'); do
                # Skip Windows system DLLs
                case "$dll" in
                    KERNEL32.dll|kernel32.dll|USER32.dll|user32.dll|GDI32.dll|gdi32.dll|\
                    ADVAPI32.dll|advapi32.dll|SHELL32.dll|shell32.dll|ole32.dll|OLE32.dll|\
                    OLEAUT32.dll|oleaut32.dll|MSVCRT.dll|msvcrt.dll|WS2_32.dll|ws2_32.dll|\
                    CRYPT32.dll|crypt32.dll|SHLWAPI.dll|shlwapi.dll|COMDLG32.dll|comdlg32.dll|\
                    ntdll.dll|NTDLL.dll|api-ms-*.dll|API-MS-*.dll|ext-ms-*.dll|EXT-MS-*.dll)
                        continue
                        ;;
                esac

                # Skip if already present
                if [ -f "${dll_dst}/${dll}" ]; then
                    continue
                fi

                dlls_needed="${dlls_needed} ${dll}"
            done
        done

        dlls_needed="${dlls_needed# }"

        if [ -z "$dlls_needed" ]; then
            echo "  No new dependencies found"
            break
        fi

        echo "  Copying DLLs:${dlls_needed}"
        for dll in $dlls_needed; do
            for search_path in $search_paths; do
                if [ -f "${search_path}/${dll}" ]; then
                    echo "    [OK] ${dll}"
                    cp "${search_path}/${dll}" "${dll_dst}/"
                    total_copied=$((total_copied + 1))
                    break
                fi
            done
        done

        pass=$((pass + 1))
    done

    echo ""
    echo "DLL Summary: Total copied: ${total_copied}"
}

verify_build() {
    log "Verifying build"

    local tools=(
        "${TARGET}-gcc"
        "${TARGET}-g++"
        "${TARGET}-as"
        "${TARGET}-ld"
        "${TARGET}-objcopy"
        "${TARGET}-objdump"
        "${TARGET}-gdb"
    )

    local all_ok=true

    for tool in "${tools[@]}"; do
        local path="${PREFIX}/bin/${tool}.exe"
        if [ -f "$path" ]; then
            echo "[OK] ${tool}"
            if ! "${path}" --version > /dev/null 2>&1; then
                echo "     WARNING: ${tool} exists but failed to run"
            fi
        else
            echo "[MISSING] ${tool}"
            all_ok=false
        fi
    done

    echo ""
    echo "Checking newlib libraries..."
    
    # Check for PIC32MZ EF variant (hard-float, little-endian, mips32r2)
    if [ -f "${PREFIX}/${TARGET}/lib/el/mips32r2/libc.a" ]; then
        echo "[OK] newlib for PIC32MZ EF (el/mips32r2/libc.a) - hard-float, little-endian"
    else
        echo "[MISSING] newlib for PIC32MZ EF (el/mips32r2/libc.a)"
        all_ok=false
    fi

    # Check for PIC32MZ DA variant (soft-float, little-endian, mips32r2)
    if [ -f "${PREFIX}/${TARGET}/lib/soft-float/el/mips32r2/libc.a" ]; then
        echo "[OK] newlib for PIC32MZ DA (soft-float/el/mips32r2/libc.a) - soft-float, little-endian"
    else
        echo "[MISSING] newlib for PIC32MZ DA (soft-float/el/mips32r2/libc.a)"
        all_ok=false
    fi

    # Check default library
    if [ -f "${PREFIX}/${TARGET}/lib/libc.a" ]; then
        echo "[OK] newlib default (lib/libc.a) - hard-float, big-endian"
    else
        echo "[MISSING] newlib default (lib/libc.a)"
        all_ok=false
    fi

    echo ""
    echo "Multilib configuration:"
    if command -v "${PREFIX}/bin/${TARGET}-gcc" &> /dev/null; then
        "${PREFIX}/bin/${TARGET}-gcc" -print-multi-lib
    fi

    echo ""

    if [ "$all_ok" = true ]; then
        echo "========================================="
        echo "SUCCESS! All tools and libraries built!"
        echo "========================================="
        echo ""
        echo "PIC32MZ EF (hard-float FPU):"
        echo "  ${TARGET}-gcc -march=mips32r2 -EL ..."
        echo "  Libraries: ${PREFIX}/${TARGET}/lib/el/mips32r2/"
        echo ""
        echo "PIC32MZ DA (soft-float):"
        echo "  ${TARGET}-gcc -march=mips32r2 -msoft-float -EL ..."
        echo "  Libraries: ${PREFIX}/${TARGET}/lib/soft-float/el/mips32r2/"
        echo ""
    else
        echo "Some tools or libraries are missing - check build log for errors"
        return 1
    fi
}

create_release_archive() {
    if [ "${MAKE_RELEASE}" != "yes" ]; then
        echo "Skipping release archive (MAKE_RELEASE=no)"
        return 0
    fi

    log "Creating PIC32 release package"

    mkdir -p "${RELEASES_DIR}"

    local platform="win64"
    local exe_suffix=".exe"
    if [[ "$(uname -s)" == "Linux" ]]; then
        platform="linux-x64"
        exe_suffix=""
    fi

    local archive_name="pic32-toolchain-${TOOLCHAIN_VERSION}-${platform}"
    local build_archive_name="mipsisa32r2-${TOOLCHAIN_VERSION}-${platform}"
    local stage_dir="${BUILDDIR}/release-staging/pic32-toolchain"

    # Clean and create staging directory
    rm -rf "${BUILDDIR}/release-staging"
    mkdir -p "${stage_dir}/bin"
    mkdir -p "${stage_dir}/pic32/lib"
    mkdir -p "${stage_dir}/lib/gcc/pic32/${GCC_VERSION}"

    echo "Staging PIC32-specific release package..."

    # =========================================================================
    # 1. Copy and rename executables from mipsisa32r2-elf-* to pic32-*
    # =========================================================================
    echo "Copying and renaming executables..."
    
    local tools=(
        "gcc"
        "g++"
        "cpp"
        "as"
        "ld"
        "ld.bfd"
        "ar"
        "nm"
        "objcopy"
        "objdump"
        "ranlib"
        "readelf"
        "size"
        "strings"
        "strip"
        "addr2line"
        "c++filt"
        "elfedit"
        "gprof"
        "gdb"
        "run"
    )

    for tool in "${tools[@]}"; do
        local src="${PREFIX}/bin/${TARGET}-${tool}${exe_suffix}"
        local dst="${stage_dir}/bin/pic32-${tool}${exe_suffix}"
        if [ -f "$src" ]; then
            cp "$src" "$dst"
            echo "  [OK] pic32-${tool}"
        fi
    done

    # Also copy gcc/g++ without prefix for convenience
    if [ -f "${PREFIX}/bin/${TARGET}-gcc${exe_suffix}" ]; then
        cp "${PREFIX}/bin/${TARGET}-gcc${exe_suffix}" "${stage_dir}/bin/pic32-gcc${exe_suffix}"
    fi

    # Copy cc1, cc1plus, collect2, lto1, lto-wrapper from libexec
    echo "Copying compiler support executables..."
    local libexec_src="${PREFIX}/libexec/gcc/${TARGET}/${GCC_VERSION}"
    local libexec_dst="${stage_dir}/libexec/gcc/pic32/${GCC_VERSION}"
    if [ -d "$libexec_src" ]; then
        mkdir -p "$libexec_dst"
        for exe in cc1 cc1plus collect2 lto1 lto-wrapper liblto_plugin*; do
            if [ -f "${libexec_src}/${exe}${exe_suffix}" ] || [ -f "${libexec_src}/${exe}" ]; then
                cp "${libexec_src}/${exe}"* "$libexec_dst/" 2>/dev/null || true
            fi
        done
        # Copy any .dll files in libexec
        cp "${libexec_src}"/*.dll "$libexec_dst/" 2>/dev/null || true
        echo "  [OK] libexec/gcc/pic32/${GCC_VERSION}/"
    fi

    # Copy runtime DLLs
    echo "Copying runtime DLLs..."
    cp "${PREFIX}/bin"/*.dll "${stage_dir}/bin/" 2>/dev/null || true

    # =========================================================================
    # 2. Copy only PIC32-relevant libraries (little-endian mips32r2)
    # =========================================================================
    echo "Copying PIC32-specific libraries..."

    # Newlib libraries - only el/mips32r2 variants
    local newlib_src="${PREFIX}/${TARGET}/lib"
    local newlib_dst="${stage_dir}/pic32/lib"

    # Hard-float little-endian mips32r2 (PIC32MZ EF) - this is the primary target
    if [ -d "${newlib_src}/el/mips32r2" ]; then
        mkdir -p "${newlib_dst}/el/mips32r2"
        cp "${newlib_src}/el/mips32r2"/*.a "${newlib_dst}/el/mips32r2/"
        echo "  [OK] pic32/lib/el/mips32r2/ (PIC32MZ EF - hard-float)"
    fi

    # Soft-float little-endian mips32r2 (PIC32MZ DA)
    if [ -d "${newlib_src}/soft-float/el/mips32r2" ]; then
        mkdir -p "${newlib_dst}/soft-float/el/mips32r2"
        cp "${newlib_src}/soft-float/el/mips32r2"/*.a "${newlib_dst}/soft-float/el/mips32r2/"
        echo "  [OK] pic32/lib/soft-float/el/mips32r2/ (PIC32MZ DA - soft-float)"
    fi

    # Copy include files
    if [ -d "${PREFIX}/${TARGET}/include" ]; then
        cp -r "${PREFIX}/${TARGET}/include" "${stage_dir}/pic32/"
        echo "  [OK] pic32/include/"
    fi

    # =========================================================================
    # 3. Copy GCC libraries (libgcc) - only el/mips32r2 variants
    # =========================================================================
    echo "Copying GCC support libraries..."

    local gcc_lib_src="${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}"
    local gcc_lib_dst="${stage_dir}/lib/gcc/pic32/${GCC_VERSION}"

    # Hard-float little-endian mips32r2
    if [ -d "${gcc_lib_src}/el/mips32r2" ]; then
        mkdir -p "${gcc_lib_dst}/el/mips32r2"
        cp "${gcc_lib_src}/el/mips32r2"/*.a "${gcc_lib_dst}/el/mips32r2/" 2>/dev/null || true
        cp "${gcc_lib_src}/el/mips32r2"/*.o "${gcc_lib_dst}/el/mips32r2/" 2>/dev/null || true
        echo "  [OK] lib/gcc/pic32/${GCC_VERSION}/el/mips32r2/"
    fi

    # Soft-float little-endian mips32r2
    if [ -d "${gcc_lib_src}/soft-float/el/mips32r2" ]; then
        mkdir -p "${gcc_lib_dst}/soft-float/el/mips32r2"
        cp "${gcc_lib_src}/soft-float/el/mips32r2"/*.a "${gcc_lib_dst}/soft-float/el/mips32r2/" 2>/dev/null || true
        cp "${gcc_lib_src}/soft-float/el/mips32r2"/*.o "${gcc_lib_dst}/soft-float/el/mips32r2/" 2>/dev/null || true
        echo "  [OK] lib/gcc/pic32/${GCC_VERSION}/soft-float/el/mips32r2/"
    fi

    # Copy GCC include files and plugin headers
    if [ -d "${gcc_lib_src}/include" ]; then
        cp -r "${gcc_lib_src}/include" "${gcc_lib_dst}/"
        echo "  [OK] lib/gcc/pic32/${GCC_VERSION}/include/"
    fi
    if [ -d "${gcc_lib_src}/include-fixed" ]; then
        cp -r "${gcc_lib_src}/include-fixed" "${gcc_lib_dst}/"
        echo "  [OK] lib/gcc/pic32/${GCC_VERSION}/include-fixed/"
    fi
    if [ -d "${gcc_lib_src}/install-tools" ]; then
        cp -r "${gcc_lib_src}/install-tools" "${gcc_lib_dst}/"
    fi

    # =========================================================================
    # 4. Copy linker scripts
    # =========================================================================
    if [ -d "${PREFIX}/${TARGET}/lib/ldscripts" ]; then
        cp -r "${PREFIX}/${TARGET}/lib/ldscripts" "${newlib_dst}/"
        echo "  [OK] pic32/lib/ldscripts/"
    fi

    # =========================================================================
    # 5. Create GCC spec file to use pic32 paths
    # =========================================================================
    echo "Creating GCC specs for pic32 paths..."
    cat > "${gcc_lib_dst}/specs" << 'SPECS'
*cross_compile:
1

*multilib_defaults:
EL mips32r2

SPECS
    echo "  [OK] lib/gcc/pic32/${GCC_VERSION}/specs"

    # =========================================================================
    # 6. Create README
    # =========================================================================
    cat > "${stage_dir}/README.txt" << EOF
PIC32 Toolchain ${TOOLCHAIN_VERSION}
==========================================

Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Platform: ${platform}

Component Versions:
  GCC:      ${GCC_VERSION}
  Binutils: ${BINUTILS_VERSION}
  Newlib:   ${NEWLIB_VERSION}
  GDB:      ${GDB_VERSION}

This is a streamlined release containing only the libraries needed for
PIC32MZ processors. Tools have been renamed from mipsisa32r2-elf-* to pic32-*.

Included Library Variants:
  - el/mips32r2           : PIC32MZ EF (hard-float, little-endian)
  - soft-float/el/mips32r2: PIC32MZ DA (soft-float, little-endian)

Usage Examples:

  PIC32MZ EF (has hardware FPU):
    pic32-gcc -march=mips32r2 -EL -c main.c

  PIC32MZ DA (no hardware FPU):
    pic32-gcc -march=mips32r2 -msoft-float -EL -c main.c

Tools Included:
  pic32-gcc, pic32-g++, pic32-as, pic32-ld, pic32-objcopy,
  pic32-objdump, pic32-gdb, pic32-ar, pic32-nm, pic32-strip, etc.

Source: https://github.com/kotuku-aero/mips32
License: GPL v3 (GCC, Binutils, GDB), BSD/MIT (Newlib)

Built with: $(gcc --version | head -1)

The archives mipsisa32-elf-win64.tar.xz and mipsisa32-elf-win64.zip are the generated
mips compilers and libraries without any renaming of the tools to pic32.  Also all
multilib variants are included.
EOF

    # =========================================================================
    # 7. Create archives
    # =========================================================================
    echo ""
    echo "Creating release archives..."
    cd "${BUILDDIR}/release-staging"

    local tarxz_path="${RELEASES_DIR}/${archive_name}.tar.xz"
    echo "Creating ${archive_name}.tar.xz ..."
    tar -cJf "${tarxz_path}" "pic32-toolchain"
    echo "  [OK] $(du -h "${tarxz_path}" | cut -f1)"

    cd "${RELEASES_DIR}"
    sha256sum "${archive_name}.tar.xz" > "${archive_name}.tar.xz.sha256"

    cd "${BUILDDIR}/release-staging"
    local zip_path="${RELEASES_DIR}/${archive_name}.zip"
    if command -v zip &> /dev/null; then
        echo "Creating ${archive_name}.zip ..."
        zip -rq "${zip_path}" "pic32-toolchain"
        echo "  [OK] $(du -h "${zip_path}" | cut -f1)"
        cd "${RELEASES_DIR}"
        sha256sum "${archive_name}.zip" > "${archive_name}.zip.sha256"
    fi

    # copy the actual build to the archive as well
    local build_tarxz_path="${RELEASES_DIR}/${build_archive_name}.tar.xz"
    echo "Creating ${build_archive_name}.tar.xz ..."
    tar -cJf "${build_tarxz_path}" $PREFIX
    echo "  [OK] $(du -h "${tarxz_path}" | cut -f1)"

    cd "${RELEASES_DIR}"
    sha256sum "${build_archive_name}.tar.xz" > "${build_archive_name}.tar.xz.sha256"

    cd "${BUILDDIR}/release-staging"
    local build_zip_path="${RELEASES_DIR}/${build_archive_name}.zip"
    if command -v zip &> /dev/null; then
        echo "Creating ${build_archive_name}.zip ..."
        zip -rq "${build_zip_path}" $PREFIX
        echo "  [OK] $(du -h "${build_zip_path}" | cut -f1)"
        cd "${RELEASES_DIR}"
        sha256sum "${build_archive_name}.zip" > "${build_archive_name}.zip.sha256"
    fi

    # Copy README to releases dir too
    cp "${stage_dir}/README.txt" "${RELEASES_DIR}/${archive_name}-README.txt"

    # Show size comparison
    echo ""
    echo "Release package contents:"
    du -sh "${stage_dir}"/* 2>/dev/null || true
    echo ""
    local full_size=$(du -sh "${PREFIX}" | cut -f1)
    local release_size=$(du -sh "${stage_dir}" | cut -f1)
    echo "Size comparison:"
    echo "  Full build:     ${full_size}"
    echo "  Release package: ${release_size}"

    # Cleanup staging
    # rm -rf "${BUILDDIR}/release-staging"

    cd "${SCRIPT_DIR}"
}

print_summary() {
    log "Build Complete"

    echo "Toolchain installed to: ${PREFIX}"
    if command -v cygpath &> /dev/null; then
        echo "Windows path: $(cygpath -w "${PREFIX}")"
    fi
    echo ""
    echo "Component versions:"
    echo "  GCC:      ${GCC_VERSION}"
    echo "  Binutils: ${BINUTILS_VERSION}"
    echo "  Newlib:   ${NEWLIB_VERSION}"
    echo "  GDB:      ${GDB_VERSION}"
    echo ""
    echo "Full build library directories:"
    echo "  ${PREFIX}/${TARGET}/lib/                        - Default (hard-float, big-endian)"
    echo "  ${PREFIX}/${TARGET}/lib/el/mips32r2/            - PIC32MZ EF (hard-float, little-endian)"
    echo "  ${PREFIX}/${TARGET}/lib/soft-float/el/mips32r2/ - PIC32MZ DA (soft-float, little-endian)"
    echo ""

    echo "Multilib configuration:"
    "${PREFIX}/bin/${TARGET}-gcc" -print-multi-lib
    echo ""

    echo "Usage with full toolchain (${TARGET}-*):"
    echo "  PIC32MZ EF: ${TARGET}-gcc -march=mips32r2 -EL ..."
    echo "  PIC32MZ DA: ${TARGET}-gcc -march=mips32r2 -msoft-float -EL ..."
    echo ""

    if [ -d "${RELEASES_DIR}" ]; then
        echo "Release package created with pic32-* tool names:"
        echo "  PIC32MZ EF: pic32-gcc -march=mips32r2 -EL ..."
        echo "  PIC32MZ DA: pic32-gcc -march=mips32r2 -msoft-float -EL ..."
        echo ""
        echo "Release archives in: ${RELEASES_DIR}/"
        ls -la "${RELEASES_DIR}"/*.tar.xz "${RELEASES_DIR}"/*.zip 2>/dev/null || true
    fi
}

#-----------------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------------

main() {
    echo "========================================="
    echo "MIPS32 Toolchain Builder - PIC32 MULTILIB"
    echo "========================================="
    echo ""
    echo "Configuration:"
    echo "  TARGET:       ${TARGET}"
    echo "  PREFIX:       ${PREFIX}"
    echo "  JOBS:         ${JOBS}"
    echo "  MULTILIB:     Full support (hard-float default)"
    echo ""

    check_prerequisites

    if [ "${CLEAN}" == "yes" ]; then
        log "Cleaning build directory and source trees"
        rm -rf "${BUILDDIR}"
        # Also remove GCC source directory to ensure fresh config.gcc patching
        rm -rf "${SCRIPT_DIR}/gcc"
        echo "Removed build directory and gcc source directory"
    fi

    mkdir -p "${BUILDDIR}"
    mkdir -p "${STAGING}"
    mkdir -p "${PREFIX}"

    show_completed_stages

    if [ -n "${SKIP_TO}" ]; then
        local skip_idx=$(find_stage_index "${SKIP_TO}")
        if [ ${skip_idx} -ge 0 ]; then
            echo "SKIP_TO=${SKIP_TO} specified, will resume from stage $((skip_idx + 1))"
            if [ ${skip_idx} -eq 0 ]; then
                rm -f "${STAGE_FILE}"
            else
                echo "${STAGES[$((skip_idx - 1))]}" > "${STAGE_FILE}"
            fi
        fi
        echo ""
    fi

    build_gmp
    build_mpfr
    build_mpc
    build_binutils
    build_gcc_stage1


    # GCC needs to find binutils and stage1 compiler
    export PATH="${PREFIX}/bin:${PATH}"

    build_newlib
    build_gcc_stage2
    build_gdb

    copy_runtime_dlls
    verify_build
    create_release_archive
    print_summary
}

main "$@"
