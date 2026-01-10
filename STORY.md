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

- **Build Scripts**: https://gitea.kotuku.aero/kotuku/mips32
- **Pre-built Toolchain**: https://gitea.kotuku.aero/kotuku/pic32

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

*This document was written in January 2025 by Peter with assistance from Claude (Anthropic). It may be freely distributed under the terms of the GPL-3.0 license.*
