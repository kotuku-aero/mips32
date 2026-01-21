# PIC32 Cross-Compiler Toolchain

A modern, open-source cross-compiler toolchain for PIC32MZ microcontrollers, built from standard GNU sources without requiring Microchip's XC32 compiler.

## Overview

This project provides build scripts to create a complete GCC-based toolchain targeting PIC32MZ processors. The toolchain produces standalone Windows executables (via MSYS2) or Linux binaries, with tools renamed to `pic32-gcc`, `pic32-gdb`, etc. for easy IDE integration.

**Key Features:**
- Modern GCC 14.2.0 with full C/C++ support
- Hardware floating-point support for PIC32MZ EF series
- Soft-float support for PIC32MZ DA series
- Newlib-nano for reduced code size
- Clean `pic32-*` tool naming for IDE integration
- Fully portable Windows executables (no MSYS2 runtime required)

## Quick Start

```bash
# In MSYS2 UCRT64 terminal
pacman -S --needed base-devel mingw-w64-ucrt-x86_64-toolchain texinfo bison flex wget
cd /c/mips32
./build-pic32m.sh
```

The release package will be created in the `releases/` directory with `pic32-gcc`, `pic32-gdb`, etc.

## Background: Reverse Engineering the XC32 Build

### The Problem

Microchip's XC32 compiler is based on GCC but uses a proprietary build configuration. Building a standard MIPS GCC toolchain for PIC32 processors presented several challenges:

1. **Architecture naming**: PIC32MZ uses MIPS32r2 architecture, but standard GCC MIPS targets don't match Microchip's configuration
2. **Floating-point ABI**: PIC32MZ EF has a hardware FPU requiring specific ABI settings
3. **Multilib configuration**: Getting the correct library variants for different PIC32 families

### The Discovery

By examining the differences between Microchip's XC32 v4.35 source code (based on GCC 8.3) and later GCC versions, the key insight was found in the MIPS configuration scripts:

**In XC32's `gcc/config.gcc`:**
```
mipsisa32r2-*-elf*)
    # Microchip renames this to their xc32 target internally
    tm_file="mips/mips.h mips/elf.h mips/pic32mz.h"
    ...
```

The critical discovery was that **`mipsisa32r2-elf` is a valid GCC target** that maps correctly to PIC32MZ's MIPS32r2 architecture. Standard MIPS targets like `mips-elf` or `mipsel-elf` don't provide the same multilib configuration.

### Key Configuration Findings

| Setting | Value | Purpose |
|---------|-------|---------|
| `--target` | `mipsisa32r2-elf` | Matches PIC32MZ MIPS32r2 core |
| `--with-arch` | `mips32r2` | Default architecture |
| `--with-float` | `hard` | Hardware FPU default (soft-float via multilib) |
| `--enable-multilib` | yes | Multiple library variants |

### Multilib Output

With `--with-float=hard`, the toolchain produces these library variants:

```
.;                              # Default: hard-float, big-endian
el/mips32r2;@EL@mips32r2       # PIC32MZ EF: hard-float, little-endian ✓
soft-float/el/mips32r2;...     # PIC32MZ DA: soft-float, little-endian ✓
```

The full multilib list includes mips32, mips64, big-endian variants, etc., but only the little-endian mips32r2 variants are needed for PIC32MZ.

## PIC32 Processor Mapping

| Processor | FPU | Endian | Compiler Flags | Library Path |
|-----------|-----|--------|----------------|--------------|
| PIC32MZ EF | Hardware | Little | `-march=mips32r2 -EL` | `el/mips32r2/` |
| PIC32MZ DA | None | Little | `-march=mips32r2 -msoft-float -EL` | `soft-float/el/mips32r2/` |

## Directory Structure

```
c:\mips32\
├── build-pic32m.sh        # Main build script
├── README.md              # This file
├── sources/               # Downloaded source archives (auto-created)
├── build/                 # Build directory (auto-created)
│   ├── staging/           # Temporary install for build dependencies
│   └── release-staging/   # Staged release package
├── releases/              # Final release archives
└── [source directories]   # Extracted during build:
    ├── binutils/
    ├── gcc/
    ├── gdb/
    ├── gmp/
    ├── mpc/
    ├── mpfr/
    └── newlib/
```

## Prerequisites

### Windows (MSYS2 UCRT64)

1. Install MSYS2 from https://www.msys2.org/
2. Open "MSYS2 UCRT64" terminal
3. Update and install packages:

```bash
pacman -Syu
pacman -Su
pacman -S --needed \
    base-devel \
    mingw-w64-ucrt-x86_64-toolchain \
    texinfo \
    bison \
    flex \
    wget \
    tar \
    xz \
    zip
```

### Linux

```bash
sudo apt install build-essential texinfo bison flex wget tar xz-utils
```

## Building the Toolchain

### Standard Build

```bash
cd /c/mips32  # or your chosen directory
./build-pic32m.sh 2>&1 | tee build.log
```

Build time: approximately 30-60 minutes depending on hardware.

### Build Options

```bash
# Custom installation prefix
PREFIX=/c/my-toolchain ./build-pic32m.sh

# Parallel jobs (default: auto-detected)
JOBS=8 ./build-pic32m.sh

# Enable Python support in GDB
GDB_PYTHON=yes ./build-pic32m.sh

# Clean build (removes previous build state)
CLEAN=yes ./build-pic32m.sh

# Skip release archive creation
MAKE_RELEASE=no ./build-pic32m.sh

# Resume from a specific stage
SKIP_TO=newlib ./build-pic32m.sh
```

### Build Stages

The script tracks progress and can resume after failures:

1. `gmp` - GNU Multiple Precision library
2. `mpfr` - GNU MPFR library  
3. `mpc` - GNU MPC library
4. `binutils` - Assembler, linker, objcopy, etc.
5. `gcc-stage1` - Bootstrap C compiler
6. `newlib` - C library with multilib
7. `gcc-stage2` - Full C/C++ compiler with libgcc
8. `gdb` - Debugger

## Release Package

The build creates a streamlined release package containing only PIC32-relevant components:

```
pic32-toolchain/
├── bin/
│   ├── pic32-gcc.exe
│   ├── pic32-g++.exe
│   ├── pic32-gdb.exe
│   ├── pic32-as.exe
│   ├── pic32-ld.exe
│   ├── pic32-objcopy.exe
│   ├── pic32-objdump.exe
│   └── [runtime DLLs]
├── libexec/gcc/pic32/<version>/
│   ├── cc1.exe
│   ├── cc1plus.exe
│   └── collect2.exe
├── pic32/
│   ├── include/
│   └── lib/
│       ├── el/mips32r2/           # PIC32MZ EF libraries
│       ├── soft-float/el/mips32r2/ # PIC32MZ DA libraries
│       └── ldscripts/
├── lib/gcc/pic32/<version>/
│   ├── el/mips32r2/
│   ├── soft-float/el/mips32r2/
│   └── include/
└── README.txt
```

The release excludes unused multilib variants (mips64, big-endian, etc.) to minimize size.

## Usage

### Basic Compilation

```bash
# PIC32MZ EF (hardware FPU)
pic32-gcc -march=mips32r2 -EL -O2 -c main.c -o main.o

# PIC32MZ DA (software float)
pic32-gcc -march=mips32r2 -msoft-float -EL -O2 -c main.c -o main.o
```

### Typical Compiler Flags for PIC32MZ

```bash
pic32-gcc \
    -march=mips32r2 \
    -EL \
    -msoft-float \        # Omit for PIC32MZ EF
    -O2 \
    -ffunction-sections \
    -fdata-sections \
    -Wall \
    -c main.c -o main.o
```

### Linking

```bash
pic32-gcc \
    -march=mips32r2 \
    -EL \
    -T linker_script.ld \
    -Wl,--gc-sections \
    -nostartfiles \
    main.o -o firmware.elf

pic32-objcopy -O ihex firmware.elf firmware.hex
```

## IDE Integration

### CLion / CMake

Create `pic32-toolchain.cmake`:

```cmake
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR mips)

set(TOOLCHAIN_PREFIX "C:/pic32-toolchain/bin/pic32-")

set(CMAKE_C_COMPILER "${TOOLCHAIN_PREFIX}gcc.exe")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_PREFIX}g++.exe")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_PREFIX}gcc.exe")
set(CMAKE_OBJCOPY "${TOOLCHAIN_PREFIX}objcopy.exe")
set(CMAKE_OBJDUMP "${TOOLCHAIN_PREFIX}objdump.exe")
set(CMAKE_SIZE "${TOOLCHAIN_PREFIX}size.exe")

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
```

In CMakeLists.txt or CLion settings:
```
-DCMAKE_TOOLCHAIN_FILE=pic32-toolchain.cmake
```

### Visual Studio Code

Create `.vscode/c_cpp_properties.json`:

```json
{
    "configurations": [
        {
            "name": "PIC32",
            "compilerPath": "C:/pic32-toolchain/bin/pic32-gcc.exe",
            "compilerArgs": ["-march=mips32r2", "-EL"],
            "intelliSenseMode": "gcc-x86",
            "includePath": [
                "${workspaceFolder}/**",
                "C:/pic32-toolchain/pic32/include"
            ],
            "defines": ["__PIC32MZ__"]
        }
    ]
}
```

## Newlib Integration

### Syscall Stubs

Newlib requires syscall implementations for your hardware. Minimal stubs:

```c
#include <sys/stat.h>
#include <errno.h>

extern char _heap_start;
extern char _heap_end;
static char *heap_ptr = &_heap_start;

void *_sbrk(int incr) {
    char *prev = heap_ptr;
    if (heap_ptr + incr > &_heap_end) {
        errno = ENOMEM;
        return (void *)-1;
    }
    heap_ptr += incr;
    return prev;
}

int _write(int fd, const void *buf, size_t count) {
    // Implement for your UART
    const char *p = buf;
    for (size_t i = 0; i < count; i++) {
        uart_putc(p[i]);
    }
    return count;
}

int _read(int fd, void *buf, size_t count) {
    // Implement for your UART
    return 0;
}

int _close(int fd) { return -1; }
int _fstat(int fd, struct stat *st) { st->st_mode = S_IFCHR; return 0; }
int _isatty(int fd) { return 1; }
int _lseek(int fd, int offset, int whence) { return 0; }
void _exit(int status) { while(1); }
int _kill(int pid, int sig) { return -1; }
int _getpid(void) { return 1; }
```

### Linker Script Heap Definition

```ld
PROVIDE(_heap_start = ORIGIN(RAM) + LENGTH(RAM) - 0x10000);
PROVIDE(_heap_end = ORIGIN(RAM) + LENGTH(RAM));
```

### Newlib-Nano

The default build uses newlib-nano for smaller code size. To enable floating-point printf:

```bash
pic32-gcc ... -Wl,-u,_printf_float
```

| Configuration | Approximate Size |
|--------------|------------------|
| newlib-nano (no float) | ~20-30KB |
| newlib-nano (with float printf) | ~40-50KB |
| Full newlib | ~80-120KB |

## Component Versions

| Component | Version | Source |
|-----------|---------|--------|
| GCC | 14.2.0 | https://ftp.gnu.org/gnu/gcc/ |
| Binutils | 2.43.1 | https://ftp.gnu.org/gnu/binutils/ |
| Newlib | 4.4.0 | https://sourceware.org/newlib/ |
| GDB | 15.1 | https://ftp.gnu.org/gnu/gdb/ |
| GMP | 6.3.0 | https://ftp.gnu.org/gnu/gmp/ |
| MPFR | 4.2.1 | https://ftp.gnu.org/gnu/mpfr/ |
| MPC | 1.3.1 | https://ftp.gnu.org/gnu/mpc/ |

## Troubleshooting

### Build Fails at GCC Stage 1

The most common issue is stale build directories. Try:
```bash
CLEAN=yes ./build-pic32m.sh
```

### "mips-formats.h: static_assert" Error

This is a C11 keyword conflict in older binutils/GDB. The build script patches this automatically, but if building manually:
```bash
sed -i 's/static_assert\[/_static_assert[/g' opcodes/mips-formats.h
```

### Executables Won't Run Outside MSYS2

The build script copies required DLLs to the release package. If running from the full build directory, copy DLLs manually:
```bash
cp /ucrt64/bin/libgcc_s_seh-1.dll /c/pic32/mipsisa32r2-elf/bin/
cp /ucrt64/bin/libstdc++-6.dll /c/pic32/mipsisa32r2-elf/bin/
cp /ucrt64/bin/libwinpthread-1.dll /c/pic32/mipsisa32r2-elf/bin/
```

### GDB Python Warnings

If GDB shows Python warnings, either rebuild without Python (`GDB_PYTHON=no`, the default) or set:
```cmd
set PYTHONHOME=C:\msys64\ucrt64
```

### Wrong Libraries Being Linked

Verify the multilib selection:
```bash
pic32-gcc -march=mips32r2 -EL -print-multi-directory
# Should output: el/mips32r2

pic32-gcc -march=mips32r2 -msoft-float -EL -print-multi-directory  
# Should output: soft-float/el/mips32r2
```

## Technical Notes

### Why mipsisa32r2-elf?

Standard GCC MIPS targets (`mips-elf`, `mipsel-elf`) don't provide the correct multilib configuration for PIC32. The `mipsisa32r2-elf` target:

1. Defaults to MIPS32r2 architecture (matching PIC32MZ)
2. Provides proper endianness multilib variants
3. Supports the hard-float/soft-float multilib split
4. Is the same base target Microchip uses internally for XC32

### Floating-Point Configuration

With `--with-float=hard`:
- Default libraries are built with hardware FPU instructions
- Soft-float libraries are available via `-msoft-float` flag
- No ABI mismatch warnings when linking PIC32MZ EF code

### MSYS2 Path Handling

The build script includes a patch for GCC's `gtyp-input.list` generation, which fails on MSYS2 due to path format differences (`/c/path` vs `C:/path`).

## License

- GCC, Binutils, GDB: GNU GPL v3
- GMP, MPFR, MPC: GNU LGPL v3  
- Newlib: BSD-style licenses (see newlib source)
- Build scripts: MIT

## Contributing

Contributions welcome! Please:

1. Test on a clean MSYS2 installation
2. Verify both PIC32MZ EF and DA library variants build correctly
3. Test the release package on a system without MSYS2 installed

## Acknowledgments

- GNU toolchain developers
- Newlib maintainers
- Microchip for the XC32 source releases that enabled this reverse engineering
- The PIC32 hobbyist community

## Related Projects

- [CanFly](https://github.com/user/canfly) - Open-source avionics for experimental aircraft (uses this toolchain)
- [Microchip XC32](https://www.microchip.com/xc32) - Official (proprietary) compiler
