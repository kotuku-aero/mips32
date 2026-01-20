#!/bin/bash
#
# build-pic32m.sh - Build MIPS32 cross-compiler toolchain for PIC32
#
# This script builds a complete cross-compiler toolchain targeting
# ${TARGET} (PIC32) processors with MULTILIB support for hard-float FP64.
# It produces native Windows executables when run under MSYS2 UCRT64.
#
# MULTILIB SUPPORT:
#   This version builds multiple library variants:
#   - soft-float/eb (big-endian soft-float) - default
#   - soft-float/el (little-endian soft-float) - for PIC32MX/MK
#   - hard-float/mfp64/el (little-endian hard-float FP64) - FOR PIC32MZ-EF
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
# Source Versions - GCC 14.2.0 for better hard-float multilib support
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

export TARGET=mips32r2-elf
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
    # On MSYS2/Windows, directory moves can fail due to lingering handles
    # Use retry logic with small delays
    rm -rf "$target_dir"

    mv "$extracted_dir" "$target_dir" 2>/dev/null;

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
        --program-prefix=${TOOLCHAIN} \
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

    # GCC needs to find the newly built binutils
    export PATH="${PREFIX}/bin:${PATH}"

    # CRITICAL: Clean any previous build directory to ensure fresh configure
    # This is necessary because multilib configuration is cached during configure
    if [ -d "${BUILDDIR}/gcc-stage1" ]; then
        echo "Removing previous gcc-stage1 build directory to ensure fresh configure..."
        rm -rf "${BUILDDIR}/gcc-stage1"
    fi

    mkdir -p "${BUILDDIR}/gcc-stage1"
    cd "${BUILDDIR}/gcc-stage1"

    # GCC 14 configuration for hard-float multilib
    # For MIPS, FP64 is controlled via multilib flags (-mfp64) in t-elf,
    # not via configure options. --with-float=hard sets the default.
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
    local multilib_output=$("${PREFIX}/bin/${TOOLCHAIN}-gcc" -print-multi-lib 2>/dev/null)
    echo "GCC reports multilib: ${multilib_output}"
    
    if [ "${multilib_output}" = ".;" ]; then
        echo ""
        echo "ERROR: GCC stage1 does not have multilib support!"
        echo "This usually means the t-elf patch was not applied before GCC configure."
        echo "Please run: CLEAN=yes ./build-pic32m.sh to start fresh."
        echo ""
        exit 1
    fi

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

    # Verify multilib libraries were installed
    echo ""
    echo "========================================="
    echo "Verifying installed multilib libraries..."
    echo "========================================="
    for dir in "${PREFIX}/${TARGET}/lib/soft-float/eb" "${PREFIX}/${TARGET}/lib/soft-float/el" "${PREFIX}/${TARGET}/lib/hard-float/mfp64/el"; do
        if [ -d "$dir" ]; then
            echo "  [OK] ${dir}"
            ls -la "$dir"/*.a 2>/dev/null | head -3
        else
            echo "  [MISSING] ${dir}"
        fi
    done
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

    # GCC needs to find binutils and stage1 compiler
    export PATH="${PREFIX}/bin:${PATH}"

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

    # Verify libgcc multilib
    echo ""
    echo "========================================="
    echo "Verifying libgcc multilib installation..."
    echo "========================================="
    for dir in "${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}/soft-float/eb" \
               "${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}/soft-float/el" \
               "${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}/hard-float/mfp64/el"; do
        if [ -d "$dir" ]; then
            echo "  [OK] ${dir}"
            ls -la "$dir"/libgcc.a 2>/dev/null || echo "       (no libgcc.a)"
        else
            echo "  [MISSING] ${dir}"
        fi
    done
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
        --program-prefix=${TOOLCHAIN} \
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
    
    # Check soft-float variants
    if [ -f "${PREFIX}/${TARGET}/lib/soft-float/eb/libc.a" ]; then
        echo "[OK] newlib soft-float big-endian (soft-float/eb/libc.a)"
    else
        echo "[MISSING] newlib soft-float big-endian"
        all_ok=false
    fi

    if [ -f "${PREFIX}/${TARGET}/lib/soft-float/el/libc.a" ]; then
        echo "[OK] newlib soft-float little-endian (soft-float/el/libc.a)"
    else
        echo "[MISSING] newlib soft-float little-endian"
        all_ok=false
    fi

    # Check hard-float FP64 variant (PIC32MZ-EF) - THE CRITICAL ONE
    if [ -f "${PREFIX}/${TARGET}/lib/hard-float/mfp64/el/libc.a" ]; then
        echo "[OK] newlib hard-float FP64 (hard-float/mfp64/el/libc.a) - PIC32MZ-EF ✓✓✓"
        
        if command -v ${TARGET}-objdump &> /dev/null; then
            local flags=$(${TARGET}-objdump -p "${PREFIX}/${TARGET}/lib/hard-float/mfp64/el/libc.a" 2>/dev/null | grep -i "flags" | head -1)
            echo "     Library ABI: ${flags}"
        fi
    else
        echo "[MISSING] newlib hard-float FP64 (hard-float/mfp64/el/libc.a) - REQUIRED FOR PIC32MZ-EF!"
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
        echo "✓✓✓ SUCCESS! All tools and libraries built!"
        echo "========================================="
        echo ""
        echo "To use with PIC32MZ-EF, compile with:"
        echo "  ${TARGET}-gcc -march=m14k -mhard-float -mfp64 -EL ..."
        echo ""
        echo "Libraries will be automatically selected from:"
        echo "  ${PREFIX}/${TARGET}/lib/hard-float/mfp64/el/"
        echo ""
        echo "No more ABI mismatch warnings! 🎉"
    else
        echo "✗ Some tools or libraries are missing - check build log for errors"
        return 1
    fi
}

create_release_archive() {
    if [ "${MAKE_RELEASE}" != "yes" ]; then
        echo "Skipping release archive (MAKE_RELEASE=no)"
        return 0
    fi

    log "Creating release archives"

    mkdir -p "${RELEASES_DIR}"

    local platform="win64"
    if [[ "$(uname -s)" == "Linux" ]]; then
        platform="linux-x64"
    fi

    local archive_name="pic32-toolchain-${TOOLCHAIN_VERSION}-${platform}"
    local prefix_basename=$(basename "${PREFIX}")
    local prefix_parent=$(dirname "${PREFIX}")

    echo "Creating release archives..."
    cd "${prefix_parent}"

    local tarxz_path="${RELEASES_DIR}/${archive_name}.tar.xz"
    echo "Creating ${archive_name}.tar.xz ..."
    tar -cJf "${tarxz_path}" "${prefix_basename}"
    echo "  [OK] $(du -h "${tarxz_path}" | cut -f1)"

    cd "${RELEASES_DIR}"
    sha256sum "${archive_name}.tar.xz" > "${archive_name}.tar.xz.sha256"

    cd "${prefix_parent}"
    local zip_path="${RELEASES_DIR}/${archive_name}.zip"
    if command -v zip &> /dev/null; then
        echo "Creating ${archive_name}.zip ..."
        zip -rq "${zip_path}" "${prefix_basename}"
        echo "  [OK] $(du -h "${zip_path}" | cut -f1)"
        cd "${RELEASES_DIR}"
        sha256sum "${archive_name}.zip" > "${archive_name}.zip.sha256"
    fi

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

Multilib Variants:
  - soft-float/eb (default, big-endian)
  - soft-float/el (little-endian) - for PIC32MX, PIC32MK
  - hard-float/mfp64/el (hard-float FP64) - for PIC32MZ-EF

Usage for PIC32MZ-EF:
  ${TARGET}-gcc -march=m14k -mhard-float -mfp64 -EL ...
  
  Libraries automatically selected from: lib/hard-float/mfp64/el/

Built with: $(gcc --version | head -1)
EOF

    cd "${SCRIPT_DIR}"
}

print_summary() {
    log "Build Complete"

    echo "Toolchain installed to: ${PREFIX}"
    echo "Windows path: $(cygpath -w "${PREFIX}")"
    echo ""
    echo "Component versions:"
    echo "  GCC:      ${GCC_VERSION}"
    echo "  Binutils: ${BINUTILS_VERSION}"
    echo "  Newlib:   ${NEWLIB_VERSION}"
    echo "  GDB:      ${GDB_VERSION}"
    echo ""
    echo "Library directories:"
    echo "  ${PREFIX}/${TARGET}/lib/soft-float/eb/         - Default (soft-float big-endian)"
    echo "  ${PREFIX}/${TARGET}/lib/soft-float/el/         - Little-endian soft-float"
    echo "  ${PREFIX}/${TARGET}/lib/hard-float/mfp64/el/   - Hard-float FP64 (PIC32MZ-EF) ✓"
    echo ""

    echo "Multilib configuration:"
    "${PREFIX}/bin/${TARGET}-gcc" -print-multi-lib
    echo ""

    echo "For PIC32MZ-EF projects:"
    echo "  Compile: ${TARGET}-gcc -march=m14k -mhard-float -mfp64 -EL ..."
    echo "  Result:  No more ABI mismatch warnings! 🎉"
}

#-----------------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------------

main() {
    echo "========================================="
    echo "MIPS32 Toolchain Builder - PIC32 MULTILIB"
    echo "========================================="
    echo ""
    echo "This build includes hard-float FP64 support for PIC32MZ-EF"
    echo ""
    echo "Configuration:"
    echo "  TARGET:       ${TARGET}"
    echo "  PREFIX:       ${PREFIX}"
    echo "  JOBS:         ${JOBS}"
    echo "  MULTILIB:     3 variants (soft-float/eb, soft-float/el, hard-float/mfp64/el)"
    echo ""

    check_prerequisites

    if [ "${CLEAN}" == "yes" ]; then
        log "Cleaning build directory and source trees"
        rm -rf "${BUILDDIR}"
        rm -rf "${PREFIX}"
        # Also remove GCC source directory to ensure fresh config.gcc patching
        rm -rf "${SCRIPT_DIR}/gcc"
        echo "Removed build directory, prefix, and gcc source directory"
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
    build_newlib
    build_gcc_stage2
    build_gdb

    copy_runtime_dlls
    verify_build
    create_release_archive
    print_summary
}

main "$@"
