# SPDX-License-Identifier: GPL-3.0-only
cmake_minimum_required(VERSION 3.15)
project(flashback_mpeg2 C)
set(CMAKE_C_STANDARD 99)
# Portable C decoder on both architectures; no unretained assembly generator.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/config.h" "#define HAVE_INTTYPES_H 1\n#define HAVE_STDINT_H 1\n#define PACKAGE_VERSION \"0.5.1\"\n")
add_library(mpeg2 STATIC libmpeg2/alloc.c libmpeg2/cpu_accel.c libmpeg2/cpu_state.c libmpeg2/decode.c libmpeg2/header.c libmpeg2/idct.c libmpeg2/motion_comp.c libmpeg2/slice.c)
target_include_directories(mpeg2 PRIVATE include "${CMAKE_CURRENT_BINARY_DIR}")
add_library(mpeg2convert STATIC libmpeg2/convert/rgb.c libmpeg2/convert/uyvy.c)
target_include_directories(mpeg2convert PRIVATE include "${CMAKE_CURRENT_BINARY_DIR}")
install(TARGETS mpeg2 mpeg2convert ARCHIVE DESTINATION lib)
install(FILES include/mpeg2.h include/mpeg2convert.h DESTINATION include/mpeg2dec)
