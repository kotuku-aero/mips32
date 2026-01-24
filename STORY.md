# The Story Behind This Toolchain

## How a Simple Request for a Debugger Became a Five-Week Journey

*January 2025*

---

## The Problem

It started simply enough: I needed a MIPS debugger.

I'm Peter, founder of Kotuku Aerospace Limited, and I've been developing custom avionics systems for experimental aircraft for over 25 years. My current project, the CanFly avionics system, runs on PIC32MZ microcontrollers - Microchip's MIPS32-based chips with hardware floating-point units, perfect for real-time flight systems.

For years, I'd been using Microchip's MPLABX IDE and their XC32 compiler. It worked, mostly. But I wanted to move to CLion for a better development experience, and that meant I needed standalone tools - particularly `mips-elf-gdb` for debugging.

How hard could it be?

---

## The Microchip Maze (Weeks 1-2)

My first attempt was to build Microchip's open-source XC32 compiler from their GitHub repository. After all, it's based on GCC - surely someone at Microchip had documented the build process?

Two weeks later, I had:
- Partial builds that failed at random stages
- Undocumented dependencies
- Build scripts that assumed a Linux environment
- A growing collection of cryptic error messages
- No working debugger

The XC32 source tree is a maze of patches, custom modifications, and assumptions about the build environment. The documentation, such as it exists, is scattered across multiple repositories and often out of date.

I was stuck.

---

## Enter Claude

In early January 2025, I started a conversation with Claude (Anthropic's AI assistant) about my build problems. What began as "help me fix this configure error" evolved into something far more ambitious.

Claude suggested a different approach entirely: instead of fighting with Microchip's modified GCC, why not build a clean, upstream GNU toolchain from scratch?

The logic was compelling:
- Upstream GCC is well-documented and actively maintained
- The MIPS backend is mature and stable
- Newlib provides a lightweight C library perfect for embedded systems
- We'd have complete control over the build process
- No vendor lock-in, no licensing restrictions on optimisation levels

"But that sounds like a lot of work," I said.

"Let's find out," Claude replied.

---

## Building the Toolchain (Weeks 3-5)

What followed was an intensive collaboration. Claude and I worked through:

### The Build System

We developed `build-pic32m.sh`, a comprehensive build script that:
- Downloads source packages from GNU mirrors automatically
- Builds GMP, MPFR, and MPC (GCC's arithmetic dependencies)
- Builds Binutils (assembler, linker, and binary utilities)
- Builds GCC in two stages (bootstrap compiler, then full compiler with C++)
- Builds Newlib (the embedded C library)
- Builds GDB (the debugger that started this whole journey!)
- Creates release archives for distribution

The script includes automatic stage tracking - if the build fails at 3am, it resumes from where it left off in the morning.

### The MSYS2 Challenges

Building a cross-compiler on Windows using MSYS2 presented unique challenges:

**Path Conversion Hell**: GCC's `gengtype` tool couldn't handle MSYS2's Unix-style paths (`/c/path`) and needed Windows-style paths (`C:/path`). But using lowercase `c:` confused gengtype when parsing paths containing `/c/` directories (like `gcc/c/c-parser.cc`). The fix required uppercase drive letters via an `awk` patch in the Makefile.

**Process Limits**: MSYS2's process management struggles with highly parallel builds. GCC's stage 2 `libgcc` build would randomly fail with "wait: No child processes" errors. Solution: reduce parallelism for just that stage.

**GMP Reliability Tests**: GMP's configure script includes a "reliability test" that fails spuriously on some systems. We patch it out.

### The Newlib Integration

Newlib is designed to be flexible - it provides the C library functions but expects you to implement the underlying system calls. Claude helped design a clean integration layer:

- `syscalls.c` bridges Newlib to my Atom kernel's stream-based I/O
- A custom linker script defines memory regions for PIC32MZ
- The build uses Newlib-nano for smaller code size

### The CMake Toolchain Files

For CLion integration, we created CMake toolchain files for both PIC32MZ variants:
- `pic32-EF-toolchain.cmake` - For chips with FPU (hard float, `-mfp64`)
- `pic32-DA-toolchain.cmake` - For chips without FPU (soft float)

These handle all the architecture-specific flags, floating-point configuration, and helper functions for generating firmware images.

---

## What Claude Brought to the Process

Working with Claude was unlike any previous development experience. Some observations:

**Institutional Knowledge**: Claude understood the GCC build system, the quirks of cross-compilation, and the intricacies of MSYS2 - knowledge that would have taken me weeks to acquire through documentation and trial-and-error.

**Rapid Iteration**: When something failed, Claude could analyse the error, understand the context, and suggest fixes almost immediately. The feedback loop was minutes, not hours.

**Documentation as We Go**: Claude generated comprehensive documentation alongside the code - README files, copyright notices, this very document. The project is documented because documentation was part of the conversation, not an afterthought.

**Pattern Recognition**: Claude spotted issues I would have missed - like the lowercase drive letter problem that caused `gt-c-c-parser.h` to be generated as `gt-c-parser.h`. That kind of bug can take days to track down manually.

**Patience**: At 2am when the build failed for the fifteenth time, Claude was still there, ready to analyse the next error message. No frustration, no "have you tried turning it off and on again."

---

## The Irony

All I wanted was a debugger.

What I got was:
- A complete, reproducible build system for MIPS32 cross-compilers
- A modern GCC 15.2 toolchain with no licensing restrictions
- Full C and C++ support with hardware FPU capabilities
- A debugger (finally!)
- Proper Newlib integration with my embedded kernel
- CMake toolchain files for CLion
- Two open-source repositories for the community
- This documentation

The build script that creates all this is about 700 lines of bash. The journey to write those 700 lines took five weeks and countless conversations.

Was it worth it? Absolutely.

I now have a toolchain I understand completely, that I can modify as needed, that isn't subject to vendor whims or licensing restrictions. When GCC 16 comes out, I can update the version number and rebuild. When I need to support a new PIC32 variant, I know exactly what to change.

And yes, I have my debugger.

---

## Acknowledgements

This project exists because of the work of many people and organisations:

- **The GNU Project** - For GCC, Binutils, GDB, GMP, MPFR, and MPC
- **Red Hat and the Newlib contributors** - For a robust embedded C library
- **The MSYS2 Project** - For making cross-compilation on Windows possible
- **Microchip Technology** - For the BSD-licensed Device Family Packs
- **Anthropic** - For Claude, who turned a frustrating problem into an educational journey

And a special acknowledgement to Claude itself. This document, like much of the project, was written collaboratively. The code is real, the builds work, and the conversations that produced them were genuinely productive. AI-assisted development is no longer theoretical - it's how I built my toolchain.

---

## Try It Yourself

The toolchain and build system are available at:

- **Build Scripts**: https://github.com/kotuku-aero/mips32
- **Pre-built Toolchain**: https://github.com/kotuku-aero/pic32

Both repositories are public. Use them, learn from them, improve them.

If you're building avionics, flight controllers, or any embedded system on PIC32, I hope this saves you the five weeks it took me to figure it out.

Clear skies,

**Peter**  
Kotuku Aerospace Limited  
New Zealand

---

## Technical Summary

For those who just want the facts:

| Component | Version | Notes |
|-----------|---------|-------|
| GCC | 15.2.0 | C and C++ enabled |
| Binutils | 2.44 | Full suite |
| Newlib | 4.5.0 | Nano variant, no libgloss |
| GDB | 16.2 | Without Python for portability |
| Target | mips-elf | Generic MIPS32 ELF |
| Host | Windows x64 | Built on MSYS2 UCRT64 |

Build time: ~2-3 hours on a modern PC  
Output size: ~2.5GB uncompressed, ~200MB compressed  
Archive format: `.tar.xz`

The toolchain is self-contained and portable. Extract to `C:\pic32`, add `bin` to your PATH, and you're ready to compile.

---

## Addendum: The Final Mile (Week 5 - CLion Integration)

*January 24, 2025*

Having the toolchain built was one thing. Getting a real application to compile and link was another.

### The Reality Check

With the toolchain in place, I turned to my actual application - kMFD3, a multi-function display for aircraft with:
- 14 XML-generated UI layouts (using custom XSLT tooling)
- Integration with 7+ internal libraries (neutron, photon, atom, graviton, etc.)
- Hardware graphics acceleration (nano2d library)
- USB support
- Custom memory allocator (neutron_malloc instead of standard malloc)
- Target: PIC32MZ2064DAR176 (2MB flash, 512KB RAM, no FPU)

The toolchain worked. The application? Not so much.

### The ABI Alignment Crisis

**Error**: Undefined references to `__adddf3`, `__subdf3`, `__muldf3`, `__divdf3`

These are libgcc soft-float helper functions. They should have been automatically linked. Why weren't they?

**Root cause**: Our Microchip library (`libpic32.a`) had been compiled years ago with XC32 using `-mfp64` (hard-float, 64-bit FPU registers). Our new soft-float toolchain expected `-msoft-float` ABIs. The object files were fundamentally incompatible.

**Solution**: Rebuild ALL Microchip-derived libraries from source with the new toolchain:
```bash
cd libs/pic32
./build-mipsisa32.sh
```

This script compiles the entire PIC32 support infrastructure (crt0.S, initialization code, peripheral libraries) with the correct soft-float ABI. Created `libpic32.a` that's ABI-compatible with our toolchain.

### The Linker Script Mismatch

**Error**: Linking succeeded, but runtime crashes immediately after reset.

**Investigation**: Single-stepping through `crt0.S` (the startup code) revealed it was trying to copy initialized data from flash to RAM using symbols that didn't exist:
```
undefined reference to `__data_start`
undefined reference to `__data_init`
undefined reference to `__data_end`
undefined reference to `__ramfunc_begin`
undefined reference to `__ramfunc_end`
undefined reference to `__ramfunc_load`
undefined reference to `__ramfunc_length`
```

**Root cause**: Our `crt0.S` (from the Microchip Device Family Pack) expects **double-underscore** symbols (`__data_start`), but the Microchip linker scripts provide **single-underscore** symbols (`_data_start`). This is an XC32-ism that was never documented.

Additionally, the Microchip linker scripts don't use `AT>` clauses to load data from flash to RAM - they allocate everything directly in RAM (VMA == LMA). But `crt0.S` has a copy loop that expects to copy data.

**Solution**: Define the missing symbols via linker command line to make the copy loops no-ops:
```cmake
target_link_options(kMFD3 PRIVATE
    -Wl,--defsym=__data_start=0x80000000
    -Wl,--defsym=__data_init=0x80000000
    -Wl,--defsym=__data_end=0x80000000
    -Wl,--defsym=__ramfunc_begin=0
    -Wl,--defsym=__ramfunc_end=0
    -Wl,--defsym=__ramfunc_load=0
    -Wl,--defsym=__ramfunc_length=0
)
```

Since `__data_start == __data_end`, the data copy loop executes zero times - which is correct since there's no data to copy from flash.

**Documentation added**: Annotated `crt0.S` with 100+ lines of comments explaining:
- The boot sequence order (NMI detection → stack setup → BSS clear → data init → main)
- What each linker symbol means (VMA vs LMA)
- Why the copy loops might execute zero times
- How to enable data copying if needed in the future
- Debugging tips for single-stepping through startup

### The Newlib Syscall Stubs

**Error**: Linking failed with undefined references to POSIX system calls:
```
undefined reference to `sbrk`
undefined reference to `_exit`
undefined reference to `close`, `read`, `write`, `fstat`, `isatty`, `lseek`
undefined reference to `kill`, `getpid`
```

**Root cause**: Newlib expects these POSIX-like functions to be implemented by the platform. Since PIC32 is bare-metal (no OS), we need to provide stub implementations.

**Solution**: Created `newlib_stubs.c` with minimal implementations:
- `sbrk()` - Calls `panic()` since we use custom allocator
- `_exit()` - Infinite loop with low-power wait
- File I/O functions - Return errors (no filesystem)
- Process functions - Return dummy values (no processes)

**Critical linking order discovery**: The stubs must be linked **after** `libc`, `libm`, and `libgcc`:
```cmake
target_link_libraries(kMFD3 PRIVATE
    # Application libraries first
    neutron photon atom
    # Standard libraries
    c m gcc
    # Stubs last (to resolve newlib's undefined references)
    atom  # linked again to provide newlib stubs
)
```

### The CLion Experience

Once these issues were resolved, CLion "just worked":
- CMake integration picked up the toolchain files
- Code completion understood PIC32-specific headers
- Debugger (GDB + JLink) connected flawlessly
- Build times: ~30 seconds incremental, ~2 minutes clean
- Final binary: 439,789 bytes text + 79,187 bytes data = 518KB total (same size as XC32!)

### What We Learned

1. **ABI compatibility is non-negotiable** - You cannot mix hard-float and soft-float object files
2. **Linker scripts are full of magic** - Undocumented symbols, vendor-specific assumptions
3. **Startup code is critical** - One wrong symbol and your chip crashes before `main()`
4. **Documentation prevents pain** - Annotating `crt0.S` now will save hours of debugging later
5. **AI assistance shines in integration** - Claude helped identify the double-underscore issue in minutes; it would have taken me days

### The Build That Finally Worked

```
[3/3] Linking C executable firmware\kMFD3.elf
   text    data     bss     dec     hex filename
 439789   79187   31986  550962   86832 kMFD3.elf

Build finished
```

After a month of work - from "I need a debugger" to "I have a complete, documented, working toolchain with real application builds" - we're done.

The toolchain is in production. The documentation is comprehensive. The libraries are rebuilt. The application builds cleanly.

And I have my debugger.

---

## Updated Technical Summary

| Component | Version | Status |
|-----------|---------|--------|
| GCC | 15.2.0 | ✓ Built, tested |
| Binutils | 2.44 | ✓ Built, tested |
| Newlib | 4.5.0 | ✓ Built, integrated |
| GDB | 16.2 | ✓ Built, tested with JLink |
| libpic32 | Custom | ✓ Rebuilt for soft-float ABI |
| CMake | 3.15+ | ✓ Toolchain files working |
| CLion | 2025.2 | ✓ Full integration |
| Real Application | kMFD3 | ✓ **Builds successfully** |

**Application complexity**:
- 14 auto-generated UI layouts from XML
- 7+ internal libraries
- Custom RTOS (Atom kernel)
- Hardware acceleration
- USB stack
- Final size: 439KB code + 79KB data + 32KB BSS = **550KB total**

**Build environment**: CLion 2025.2 on Windows 11, MSYS2 UCRT64 for toolchain builds

**Time investment**: 5 weeks from "download XC32 sources" to "production builds in CLion"

---

*This document was written in January 2025 by Peter with assistance from Claude (Anthropic). It may be freely distributed under the terms of the GPL-3.0 license.*
