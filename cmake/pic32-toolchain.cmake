# pic32-toolchain.cmake
#
# CMake toolchain file for PIC32 (MIPS32) cross-compilation
#
# Usage:
#   cmake -DCMAKE_TOOLCHAIN_FILE=pic32-toolchain.cmake ..
#
# Or in CLion:
#   Settings -> Build -> CMake -> CMake options:
#   -DCMAKE_TOOLCHAIN_FILE=<path>/pic32-toolchain.cmake
#

cmake_minimum_required(VERSION 3.16)

# Target system
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR mips)

# Toolchain location - adjust if installed elsewhere
if(WIN32)
    set(TOOLCHAIN_ROOT "C:/pic32")
else()
    set(TOOLCHAIN_ROOT "/opt/pic32")
endif()

set(TOOLCHAIN_PREFIX "${TOOLCHAIN_ROOT}/bin/mips-elf-")

# Compilers
set(CMAKE_C_COMPILER "${TOOLCHAIN_PREFIX}gcc${CMAKE_EXECUTABLE_SUFFIX}")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_PREFIX}g++${CMAKE_EXECUTABLE_SUFFIX}")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_PREFIX}gcc${CMAKE_EXECUTABLE_SUFFIX}")

# Binutils
set(CMAKE_OBJCOPY "${TOOLCHAIN_PREFIX}objcopy${CMAKE_EXECUTABLE_SUFFIX}")
set(CMAKE_OBJDUMP "${TOOLCHAIN_PREFIX}objdump${CMAKE_EXECUTABLE_SUFFIX}")
set(CMAKE_SIZE "${TOOLCHAIN_PREFIX}size${CMAKE_EXECUTABLE_SUFFIX}")
set(CMAKE_AR "${TOOLCHAIN_PREFIX}ar${CMAKE_EXECUTABLE_SUFFIX}")
set(CMAKE_RANLIB "${TOOLCHAIN_PREFIX}ranlib${CMAKE_EXECUTABLE_SUFFIX}")
set(CMAKE_NM "${TOOLCHAIN_PREFIX}nm${CMAKE_EXECUTABLE_SUFFIX}")
set(CMAKE_STRIP "${TOOLCHAIN_PREFIX}strip${CMAKE_EXECUTABLE_SUFFIX}")

# Don't try to link during compiler tests (no runtime yet)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Search behavior
set(CMAKE_FIND_ROOT_PATH "${TOOLCHAIN_ROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

#-----------------------------------------------------------------------------
# PIC32MZ-specific flags (adjust for your target)
#-----------------------------------------------------------------------------

# Common PIC32MZ flags
set(PIC32_COMMON_FLAGS "-mprocessor=32MZ2048EFH144")
set(PIC32_COMMON_FLAGS "${PIC32_COMMON_FLAGS} -mno-float")
set(PIC32_COMMON_FLAGS "${PIC32_COMMON_FLAGS} -G0")

# If using specific processor, uncomment and modify:
# set(PIC32_COMMON_FLAGS "-march=mips32r2 -msoft-float -EL")

# C flags
set(CMAKE_C_FLAGS_INIT "${PIC32_COMMON_FLAGS}")
set(CMAKE_C_FLAGS_DEBUG_INIT "-g -O0")
set(CMAKE_C_FLAGS_RELEASE_INIT "-O2 -DNDEBUG")
set(CMAKE_C_FLAGS_MINSIZEREL_INIT "-Os -DNDEBUG")
set(CMAKE_C_FLAGS_RELWITHDEBINFO_INIT "-O2 -g -DNDEBUG")

# C++ flags (if building C++)
set(CMAKE_CXX_FLAGS_INIT "${PIC32_COMMON_FLAGS} -fno-exceptions -fno-rtti")
set(CMAKE_CXX_FLAGS_DEBUG_INIT "-g -O0")
set(CMAKE_CXX_FLAGS_RELEASE_INIT "-O2 -DNDEBUG")
set(CMAKE_CXX_FLAGS_MINSIZEREL_INIT "-Os -DNDEBUG")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO_INIT "-O2 -g -DNDEBUG")

# ASM flags
set(CMAKE_ASM_FLAGS_INIT "${PIC32_COMMON_FLAGS}")

# Linker flags
set(CMAKE_EXE_LINKER_FLAGS_INIT "-nostartfiles -nostdlib")

#-----------------------------------------------------------------------------
# Helper functions
#-----------------------------------------------------------------------------

# Function to generate .hex file from ELF
function(pic32_generate_hex TARGET)
    add_custom_command(TARGET ${TARGET} POST_BUILD
        COMMAND ${CMAKE_OBJCOPY} -O ihex $<TARGET_FILE:${TARGET}> $<TARGET_FILE_DIR:${TARGET}>/${TARGET}.hex
        COMMENT "Generating ${TARGET}.hex"
    )
endfunction()

# Function to generate .bin file from ELF
function(pic32_generate_bin TARGET)
    add_custom_command(TARGET ${TARGET} POST_BUILD
        COMMAND ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:${TARGET}> $<TARGET_FILE_DIR:${TARGET}>/${TARGET}.bin
        COMMENT "Generating ${TARGET}.bin"
    )
endfunction()

# Function to print size information
function(pic32_print_size TARGET)
    add_custom_command(TARGET ${TARGET} POST_BUILD
        COMMAND ${CMAKE_SIZE} $<TARGET_FILE:${TARGET}>
        COMMENT "Size of ${TARGET}:"
    )
endfunction()

# Function to add all common post-build steps
function(pic32_firmware TARGET)
    pic32_generate_hex(${TARGET})
    pic32_generate_bin(${TARGET})
    pic32_print_size(${TARGET})
endfunction()
