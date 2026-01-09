#!/bin/bash
#
# check-deps.sh - Check and optionally copy DLL dependencies
#
# Usage:
#   ./check-deps.sh                    # Just check dependencies
#   ./check-deps.sh --copy             # Copy missing DLLs to PREFIX/bin
#   ./check-deps.sh --copy --verbose   # Verbose output
#

PREFIX="${PREFIX:-/c/pic32}"
COPY_DLLS=false
VERBOSE=false
USE_NTLDD=false
USE_OBJDUMP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --copy)
            COPY_DLLS=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "Checking DLL dependencies for toolchain in ${PREFIX}"
echo ""

# Determine which tool to use for dependency checking
if command -v ntldd &> /dev/null; then
    USE_NTLDD=true
    echo "Using ntldd for dependency analysis"
elif command -v objdump &> /dev/null; then
    USE_OBJDUMP=true
    echo "Using objdump for dependency analysis (install ntldd for better results)"
    echo "  pacman -S mingw-w64-ucrt-x86_64-ntldd-git"
else
    echo "WARNING: Neither ntldd nor objdump found"
    echo "Install ntldd: pacman -S mingw-w64-ucrt-x86_64-ntldd-git"
    echo ""
    echo "Falling back to known runtime DLLs list..."
fi
echo ""

# Function to get DLL dependencies using available tool
get_dll_deps() {
    local exe="$1"
    if [ "$USE_NTLDD" = true ]; then
        ntldd "$exe" 2>/dev/null | grep -v "Windows" | awk '{print $1}'
    elif [ "$USE_OBJDUMP" = true ]; then
        objdump -p "$exe" 2>/dev/null | grep "DLL Name:" | awk '{print $3}'
    fi
}

# Collect all unique DLL dependencies
declare -A all_dlls
declare -A msys2_dlls

# Known MSYS2/UCRT64 runtime DLLs that are commonly needed
known_runtime_dlls=(
    "libgcc_s_seh-1.dll"
    "libstdc++-6.dll"
    "libwinpthread-1.dll"
)

if [ "$USE_NTLDD" = true ] || [ "$USE_OBJDUMP" = true ]; then
    for exe in "${PREFIX}/bin"/*.exe; do
        if [ ! -f "$exe" ]; then
            continue
        fi
        
        if [ "$VERBOSE" = true ]; then
            echo "Checking: $(basename "$exe")"
        fi
        
        # Get dependencies
        while IFS= read -r dll; do
            if [ -z "$dll" ]; then
                continue
            fi
            
            all_dlls["$dll"]=1
            
            # Check if it's an MSYS2 DLL
            for search_path in /ucrt64/bin /mingw64/bin /usr/bin; do
                if [ -f "${search_path}/${dll}" ]; then
                    msys2_dlls["$dll"]="${search_path}/${dll}"
                    break
                fi
            done
        done < <(get_dll_deps "$exe")
    done
fi

echo "=== DLL Dependencies ==="
echo ""

if [ ${#msys2_dlls[@]} -gt 0 ]; then
    echo "--- MSYS2/UCRT64 Runtime DLLs needed ---"
    for dll in "${!msys2_dlls[@]}"; do
        path="${msys2_dlls[$dll]}"
        echo "  $dll => $path"
        
        # Check if we should copy
        if [ "$COPY_DLLS" = true ]; then
            if [ ! -f "${PREFIX}/bin/${dll}" ]; then
                echo "    -> Copying to ${PREFIX}/bin/"
                cp "$path" "${PREFIX}/bin/"
            fi
        fi
    done
elif [ "$USE_NTLDD" = false ] && [ "$USE_OBJDUMP" = false ]; then
    echo "--- Known runtime DLLs (checking presence) ---"
    for dll in "${known_runtime_dlls[@]}"; do
        if [ -f "/ucrt64/bin/${dll}" ]; then
            echo "  $dll => /ucrt64/bin/${dll}"
            if [ "$COPY_DLLS" = true ] && [ ! -f "${PREFIX}/bin/${dll}" ]; then
                echo "    -> Copying to ${PREFIX}/bin/"
                cp "/ucrt64/bin/${dll}" "${PREFIX}/bin/"
            fi
        fi
    done
else
    echo "  No MSYS2 DLLs detected (executables may be fully static or use only Windows DLLs)"
fi

if [ "$VERBOSE" = true ] && [ ${#all_dlls[@]} -gt 0 ]; then
    echo ""
    echo "--- All DLLs referenced ---"
    for dll in "${!all_dlls[@]}"; do
        echo "  $dll"
    done
fi

echo ""
echo "=== Summary ==="

# Check what's in the bin directory
echo ""
echo "DLLs currently in ${PREFIX}/bin/:"
ls -1 "${PREFIX}/bin/"*.dll 2>/dev/null | while read f; do
    echo "  $(basename "$f")"
done

if [ -z "$(ls -1 "${PREFIX}/bin/"*.dll 2>/dev/null)" ]; then
    echo "  (none)"
fi

# Final recommendations
echo ""
echo "=== Recommendations ==="

# Check for common runtime DLLs in the install directory
missing_runtime=()

for dll in "${known_runtime_dlls[@]}"; do
    if [ ! -f "${PREFIX}/bin/${dll}" ]; then
        missing_runtime+=("$dll")
    fi
done

if [ ${#missing_runtime[@]} -gt 0 ]; then
    echo ""
    echo "For a portable toolchain, copy these DLLs to ${PREFIX}/bin/:"
    for dll in "${missing_runtime[@]}"; do
        if [ -f "/ucrt64/bin/${dll}" ]; then
            echo "  cp /ucrt64/bin/${dll} ${PREFIX}/bin/"
        else
            echo "  $dll (not found in /ucrt64/bin - may not be needed)"
        fi
    done
    echo ""
    echo "Or run: $0 --copy"
else
    echo "✓ Runtime DLLs are in place for portability"
fi
