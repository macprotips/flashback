vcpkg_download_distfile(ARCHIVE
    URLS "https://download.videolan.org/pub/contrib/a52/a52dec-0.7.4.tar.gz"
    FILENAME "a52dec-0.7.4.tar.gz"
    SHA512 4b26fe9492f218b775fb190b76ecf06edaeb656adfe6dcbd24d0a0f86871c3ba917edb88a398eb12dccedaa1605b6f0a0be06b09f9fddd9a46e457b7dd244848)
vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/CMakeLists.txt" DESTINATION "${SOURCE_PATH}")
vcpkg_cmake_configure(SOURCE_PATH "${SOURCE_PATH}")
vcpkg_cmake_install()
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include" "${CURRENT_PACKAGES_DIR}/share/man" "${CURRENT_PACKAGES_DIR}/bin")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
