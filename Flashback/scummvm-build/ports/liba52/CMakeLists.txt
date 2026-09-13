# SPDX-License-Identifier: GPL-3.0-only
cmake_minimum_required(VERSION 3.15)
project(flashback_a52 C)
set(CMAKE_C_STANDARD 99)
# macOS is little-endian on both supported architectures. The portable decoder
# needs no DJBFFT or memalign dependency; calloc/malloc are suitably aligned.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/config.h" "#define HAVE_INTTYPES_H 1\n#define HAVE_STDINT_H 1\n")
add_library(a52 STATIC liba52/bitstream.c liba52/imdct.c liba52/bit_allocate.c liba52/parse.c liba52/downmix.c)
target_include_directories(a52 PRIVATE include "${CMAKE_CURRENT_BINARY_DIR}")
install(TARGETS a52 ARCHIVE DESTINATION lib)
install(FILES include/a52.h include/mm_accel.h DESTINATION include/a52dec)
