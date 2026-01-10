# MIPS32 Toolchain Builder - Copyright and License Information

This project provides build scripts and documentation for creating a MIPS32
cross-compiler toolchain targeting PIC32 microcontrollers. The build scripts
themselves are original work, while the toolchain components they build are
third-party free software.

## Project License

The build scripts, documentation, and original content in this repository are
licensed under the GNU General Public License version 3 or later (GPL-3.0-or-later).

```
MIPS32 Toolchain Builder
Copyright (C) 2025 Kotuku Aerospace Limited

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```

---

## What This Project Builds

This project downloads, patches, and builds the following components:

| Component | Version | License | Source |
|-----------|---------|---------|--------|
| GCC | 15.2.0 | GPL-3.0-or-later | https://ftp.gnu.org/gnu/gcc/ |
| Binutils | 2.44 | GPL-3.0-or-later | https://ftp.gnu.org/gnu/binutils/ |
| GDB | 16.2 | GPL-3.0-or-later | https://ftp.gnu.org/gnu/gdb/ |
| Newlib | 4.5.0 | BSD/MIT (mixed) | https://sourceware.org/newlib/ |
| GMP | 6.3.0 | LGPL-3.0+ / GPL-2.0+ | https://ftp.gnu.org/gnu/gmp/ |
| MPFR | 4.2.2 | LGPL-3.0-or-later | https://ftp.gnu.org/gnu/mpfr/ |
| MPC | 1.3.1 | LGPL-3.0-or-later | https://ftp.gnu.org/gnu/mpc/ |

The build scripts download source code directly from official GNU and
Sourceware mirrors. No third-party source code is stored in this repository.

---

## Third-Party Component Licenses

### GNU Compiler Collection (GCC)

**License:** GPL-3.0-or-later with GCC Runtime Library Exception  
**Copyright:** Free Software Foundation, Inc.

```
Copyright (C) Free Software Foundation, Inc.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
```

The GCC Runtime Library Exception ensures that programs compiled with GCC
are not subject to the GPL. See: https://www.gnu.org/licenses/gcc-exception-3.1.html

### GNU Binutils

**License:** GPL-3.0-or-later  
**Copyright:** Free Software Foundation, Inc.

```
Copyright (C) Free Software Foundation, Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.
```

### GNU Debugger (GDB)

**License:** GPL-3.0-or-later  
**Copyright:** Free Software Foundation, Inc.

```
Copyright (C) Free Software Foundation, Inc.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
```

### Newlib C Library

**License:** BSD/MIT/Public Domain (mixed)  
**Copyright:** Red Hat, Inc. and contributors

```
Copyright (c) 1994-2024 Red Hat, Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

    Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
```

Newlib uses BSD-compatible licenses throughout, making it suitable for
embedded systems without copyleft requirements.

### GNU GMP, MPFR, and MPC

**License:** LGPL-3.0-or-later (MPFR, MPC) / Dual LGPL-3.0+ or GPL-2.0+ (GMP)  
**Copyright:** Free Software Foundation, Inc. (GMP, MPFR) / INRIA (MPC)

These libraries are build-time dependencies only. They are statically linked
into GCC and are not distributed separately in the final toolchain.

---

## Patches Applied

The build script applies the following patches to enable building on MSYS2/Windows:

### GMP Patches

1. **Reliability Test Skip** - Disables a long-running reliability test that
   can fail spuriously on some systems.

2. **mp_limb_t Size** - Hardcodes the mp_limb_t size to 8 bytes for 64-bit
   Windows builds.

### GCC Patches

1. **MSYS2 Path Conversion** - Converts MSYS2-style paths (`/c/path`) to
   Windows-style paths (`C:/path`) in the gtyp-input.list file to fix
   gengtype processing.

These patches are minimal and necessary for cross-compilation on Windows.
They do not change the functionality of the resulting toolchain.

---

## Files in This Repository

| File/Directory | Purpose | License |
|----------------|---------|---------|
| `build-pic32m.sh` | Main build script | GPL-3.0-or-later |
| `README.md` | Documentation | GPL-3.0-or-later |
| `COPYRIGHT.md` | This file | GPL-3.0-or-later |
| `releases/` | Output directory for release archives | N/A (generated) |
| `sources/` | Downloaded source archives (not committed) | Various (see above) |
| `build/` | Build directory (not committed) | N/A (temporary) |

---

## Contributing

Contributions to this project are welcome. By submitting a pull request or
patch, you agree to license your contribution under the GPL-3.0-or-later
license, consistent with the rest of this project.

---

## Disclaimer

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

The toolchain produced by these scripts is intended for embedded development.
Users are responsible for ensuring their use complies with all applicable
regulations, particularly for safety-critical applications such as aviation.

---

## Full License Texts

The complete text of the licenses referenced above can be found at:

- **GPL-3.0:** https://www.gnu.org/licenses/gpl-3.0.html
- **LGPL-3.0:** https://www.gnu.org/licenses/lgpl-3.0.html
- **GPL-2.0:** https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
- **GCC Runtime Library Exception:** https://www.gnu.org/licenses/gcc-exception-3.1.html
- **BSD-3-Clause:** https://opensource.org/licenses/BSD-3-Clause

---

## Contact

This project is maintained by Kotuku Aerospace Limited.

- Website: https://kotuku.aero
- Repository: https://gitea.kotuku.aero/kotuku/mips32
- Toolchain Releases: https://gitea.kotuku.aero/kotuku/pic32
