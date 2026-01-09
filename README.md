# MIPS32 Cross-Compiler Toolchain for PIC32

This repository contains the source code and build scripts for creating a MIPS32 cross-compiler toolchain targeting PIC32 microcontrollers. The toolchain is built using MSYS2 on Windows and produces native Windows executables suitable for use with CLion and other IDEs.

## Quick Start

For experienced developers who just want to get building:

```bash
# In MSYS2 UCRT64 terminal
pacman -S --needed base-devel mingw-w64-ucrt-x86_64-toolchain mingw-w64-ucrt-x86_64-python
cd /c/mips32
./build-pic32m.sh
```

The toolchain will be installed to `C:\pic32`. Add `C:\pic32\bin` to your Windows PATH.

## Directory Structure

```
c:\mips32\
├── binutils/          # GNU Binutils source (assembler, linker, objcopy, etc.)
├── gcc/               # GCC source (C/C++ compiler)
├── gdb/               # GDB source (debugger)
├── gmp/               # GNU Multiple Precision library (GCC dependency)
├── mpc/               # GNU MPC library (GCC dependency)
├── mpfr/              # GNU MPFR library (GCC dependency)
├── newlib/            # Newlib C library source
├── atom/              # Atom library syscalls integration
│   ├── syscalls.c     # Newlib syscall stubs for Atom
│   ├── syscalls.h     # Syscalls API header
│   └── pic32mz_common.ld  # Example linker script with heap
├── src/               # Additional source files
├── build/             # Build directory (created during build)
│   └── staging/       # Temporary install for build dependencies
├── build-pic32m.sh    # Main build script
└── README.md          # This file
```

## Prerequisites

### 1. Install MSYS2

Download and install MSYS2 from https://www.msys2.org/

Run the installer and follow the prompts. The default installation path is `C:\msys64`.

### 2. Update MSYS2

Open "MSYS2 UCRT64" from the Start menu (important: use UCRT64, not MSYS or MINGW64):

```bash
pacman -Syu
```

Close the terminal when prompted, then reopen and run:

```bash
pacman -Su
```

### 3. Install Required Packages

```bash
pacman -S --needed \
    base-devel \
    mingw-w64-ucrt-x86_64-toolchain \
    mingw-w64-ucrt-x86_64-python \
    mingw-w64-ucrt-x86_64-ntldd-git \
    texinfo \
    bison \
    flex \
    git
```

**Package explanations:**

| Package | Purpose |
|---------|---------|
| `base-devel` | Basic build tools (make, etc.) |
| `mingw-w64-ucrt-x86_64-toolchain` | Native Windows compiler (gcc, g++) |
| `mingw-w64-ucrt-x86_64-python` | Python for GDB scripting (optional) |
| `mingw-w64-ucrt-x86_64-ntldd-git` | Tool to check DLL dependencies |
| `texinfo` | Documentation generation |
| `bison`, `flex` | Parser generators (required by some builds) |
| `git` | Version control |

### 4. Download Newlib Source

```bash
cd /c/mips32
git clone git://sourceware.org/git/newlib-cygwin.git newlib
# Or download from https://sourceware.org/newlib/
```

### 5. Verify Installation

```bash
which gcc
# Should output: /ucrt64/bin/gcc

gcc --version
# Should show UCRT64 GCC
```

## Building the Toolchain

### Standard Build

```bash
cd /c/mips32
./build-pic32m.sh 2>&1 | tee build.log
```

The build takes approximately 30-60 minutes depending on your hardware.

### Build Options

The build script supports several environment variables:

```bash
# Custom installation prefix (default: /c/pic32)
PREFIX=/c/my-toolchain ./build-pic32m.sh

# Parallel jobs (default: auto-detected)
JOBS=8 ./build-pic32m.sh

# Enable Python support in GDB (default: disabled)
GDB_PYTHON=yes ./build-pic32m.sh

# Clean build (removes build directory first)
CLEAN=yes ./build-pic32m.sh
```

### Build Stages

The build proceeds in stages. If a stage fails, you can restart from that stage:

```bash
# Skip to GCC build (after binutils, gmp, mpfr, mpc are done)
SKIP_TO=gcc ./build-pic32m.sh
```

## Post-Build Setup

### 1. Add to Windows PATH

Add `C:\pic32\bin` to your Windows PATH:

1. Press Win+R, type `sysdm.cpl`, press Enter
2. Click "Advanced" tab → "Environment Variables"
3. Under "System variables", find "Path", click "Edit"
4. Click "New" and add `C:\pic32\bin`
5. Click OK to close all dialogs

### 2. Verify Installation

Open a new Command Prompt (not MSYS2) and run:

```cmd
mips-elf-gcc --version
mips-elf-gdb --version
```

### 3. Check DLL Dependencies

To verify the executables are portable:

```bash
# In MSYS2 UCRT64
ntldd /c/pic32/bin/mips-elf-gcc.exe
```

The output should only show Windows system DLLs and UCRT64 DLLs. See "Runtime Dependencies" below for details.

## CLion Integration

### Toolchain Configuration

1. Open CLion Settings (Ctrl+Alt+S)
2. Navigate to **Build, Execution, Deployment → Toolchains**
3. Click "+" and select "System"
4. Configure:
   - Name: `PIC32 MIPS`
   - C Compiler: `C:\pic32\bin\mips-elf-gcc.exe`
   - C++ Compiler: (leave empty or `C:\pic32\bin\mips-elf-g++.exe` if built)
   - Debugger: `C:\pic32\bin\mips-elf-gdb.exe`

### CMake Toolchain File

Create a file `pic32-toolchain.cmake` in your project:

```cmake
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR mips)

# Toolchain paths
set(TOOLCHAIN_PREFIX "C:/pic32/bin/mips-elf-")

set(CMAKE_C_COMPILER "${TOOLCHAIN_PREFIX}gcc.exe")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_PREFIX}g++.exe")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_PREFIX}gcc.exe")
set(CMAKE_OBJCOPY "${TOOLCHAIN_PREFIX}objcopy.exe")
set(CMAKE_OBJDUMP "${TOOLCHAIN_PREFIX}objdump.exe")
set(CMAKE_SIZE "${TOOLCHAIN_PREFIX}size.exe")

# Don't try to run test executables on the host
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Search paths
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
```

In CLion, set the toolchain file in **Settings → Build → CMake → CMake options**:

```
-DCMAKE_TOOLCHAIN_FILE=pic32-toolchain.cmake
```

## Runtime Dependencies

The built executables depend on certain DLLs. When using UCRT64:

**Required DLLs (included with Windows 10+):**
- `KERNEL32.dll`
- `ucrtbase.dll`
- `api-ms-win-crt-*.dll`

**Required DLLs (from MSYS2 UCRT64):**

If you need to distribute the toolchain to machines without MSYS2, copy these from `C:\msys64\ucrt64\bin\`:

```
libgcc_s_seh-1.dll
libstdc++-6.dll
libwinpthread-1.dll
```

To create a fully portable distribution:

```bash
# Copy required DLLs to the toolchain bin directory
cp /ucrt64/bin/libgcc_s_seh-1.dll /c/pic32/bin/
cp /ucrt64/bin/libstdc++-6.dll /c/pic32/bin/
cp /ucrt64/bin/libwinpthread-1.dll /c/pic32/bin/
```

### Python Dependencies for GDB

If GDB was built with Python support (`GDB_PYTHON=yes`), you'll also need:

```
libpython3.*.dll
python3*.zip (standard library)
```

These must be in a location GDB can find. The simplest approach is to build GDB without Python support (the default).

## Troubleshooting

### "Could not find platform dependent libraries"

This warning from GDB is harmless and can be ignored. It appears when Python support is enabled but Python isn't fully configured.

### Build fails with "texinfo" errors

Install texinfo:

```bash
pacman -S texinfo
```

### Executables won't run outside MSYS2

Check DLL dependencies:

```bash
ntldd /c/pic32/bin/mips-elf-gcc.exe | grep -i "not found"
```

Copy any missing DLLs to `C:\pic32\bin\`.

### "mips-elf-gcc: command not found" in Command Prompt

Ensure `C:\pic32\bin` is in your Windows PATH and open a **new** Command Prompt window.

### GDB Python errors

Either rebuild GDB without Python (`GDB_PYTHON=no`) or ensure Python is properly installed and PYTHONHOME is set:

```cmd
set PYTHONHOME=C:\msys64\ucrt64
```

## Source Versions

Current source versions in this repository:

| Component | Version | Source |
|-----------|---------|--------|
| Binutils | 2.43 | https://ftp.gnu.org/gnu/binutils/ |
| GCC | 14.2 | https://ftp.gnu.org/gnu/gcc/ |
| GDB | 17.1 | https://ftp.gnu.org/gnu/gdb/ |
| GMP | 6.3.0 | https://ftp.gnu.org/gnu/gmp/ |
| MPFR | 4.2.1 | https://ftp.gnu.org/gnu/mpfr/ |
| MPC | 1.3.1 | https://ftp.gnu.org/gnu/mpc/ |
| Newlib | 4.4.0 | https://sourceware.org/newlib/ |

## Newlib and Atom Library Integration

### How Newlib Works

Newlib is a C standard library for embedded systems. It provides familiar functions like `printf()`, `malloc()`, `strcpy()`, etc. However, newlib needs "syscall stubs" to interface with your hardware because it doesn't know how to:

- Write characters to your UART/display
- Read characters from your keyboard/serial port  
- Allocate memory from your heap

The syscall stubs are weak symbols in newlib that do nothing by default. You must provide implementations that hook into your system.

### Syscall Stubs for Atom

The `atom/syscalls.c` file provides implementations that bridge newlib to the Atom library's stream interface:

| Syscall | Newlib Uses For | Atom Implementation |
|---------|-----------------|---------------------|
| `_write()` | printf(), puts(), fwrite() | `stream->write()` |
| `_read()` | scanf(), getchar(), fread() | `stream->read()` |
| `_sbrk()` | malloc(), calloc(), realloc() | Heap pointer management |
| `_close()` | fclose() | `neutron_free()` |
| `_lseek()` | fseek(), ftell() | `stream->setpos()` |
| `_fstat()` | Internal file info | Returns device type |
| `_isatty()` | Line buffering decisions | Returns 1 for fd 0-2 |

### Usage

1. **Include syscalls.c in your build**

2. **Define heap symbols in your linker script:**
```ld
/* In your linker script */
PROVIDE(_heap_start = 0x80070000);  /* Start of heap region */
PROVIDE(_heap_end = 0x80080000);    /* End of heap region */
```

3. **Initialize early in main():**
```c
#include "syscalls.h"

int main(void)
{
    /* Create your console stream (UART, USB CDC, etc.) */
    stream_t* console;
    uart_create_stream(UART1, 115200, &console);
    
    /* Initialize syscalls - MUST be done before using printf */
    syscalls_init(console);
    
    /* Now printf works! */
    printf("Hello from PIC32!\r\n");
    
    /* And malloc works! */
    char* buf = malloc(100);
    sprintf(buf, "Dynamic allocation works!");
    printf("%s\r\n", buf);
    free(buf);
    
    /* ... rest of your application ... */
}
```

### Newlib-Nano

By default, the build script creates newlib-nano, a size-optimized variant that:
- Uses smaller printf/scanf (no floating point by default)
- Has a smaller malloc implementation
- Reduces overall code size significantly

To enable floating point in printf with newlib-nano, link with:
```
-u _printf_float
```

To build full newlib instead of nano:
```bash
NEWLIB_NANO=no ./build-pic32m.sh
```

### File Descriptor Mapping

| fd | Stream | Purpose |
|----|--------|---------|
| 0 | stdin | Console input |
| 1 | stdout | Console output (printf) |
| 2 | stderr | Error output |
| 3+ | Files | Available for filesystem |

You can redirect streams after initialization:
```c
/* Redirect stderr to a different UART */
stream_t* error_uart;
uart_create_stream(UART2, 115200, &error_uart);
syscalls_set_fd(2, error_uart);
```

### Memory Considerations

| Configuration | Approximate Size |
|--------------|------------------|
| newlib-nano (no float) | ~20-30KB |
| newlib-nano (with float printf) | ~40-50KB |
| Full newlib | ~80-120KB |
| Just Atom stream_printf | ~2-5KB |

If code size is critical and you only need basic printf, consider using Atom's `stream_printf()` directly instead of newlib.

## License

The toolchain components are licensed under various open-source licenses:
- GCC, Binutils, GDB: GNU GPL v3
- GMP, MPFR, MPC: GNU LGPL v3

See individual source directories for complete license information.

## Contributing

1. Fork this repository
2. Create a feature branch
3. Make your changes
4. Test the build on a clean MSYS2 installation
5. Submit a pull request

## Support

For issues specific to this toolchain build, open an issue in this repository.

For general PIC32/MIPS development questions, see:
- Microchip Developer Forums
- PIC32 Reference Manual
