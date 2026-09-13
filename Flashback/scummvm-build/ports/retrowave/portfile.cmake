vcpkg_download_distfile(ARCHIVE
    URLS "https://codeload.github.com/SudoMaker/RetroWave/tar.gz/e6bf60eed2d2bd1deff688d645be71a32bbf05bb"
    FILENAME "RetroWave-e6bf60eed2d2bd1deff688d645be71a32bbf05bb.tar.gz"
    SHA512 559dab35498b0b8e4438fbf044212982c076be0b7acff1b0ecb02bc3978e7d42002a2e510347461441d682461f9819ff1492791931dd4f806bb343737a431a8f)
vcpkg_extract_source_archive(SOURCE_PATH ARCHIVE "${ARCHIVE}")
vcpkg_cmake_configure(SOURCE_PATH "${SOURCE_PATH}" OPTIONS -DRETROWAVE_BUILD_PLAYER=OFF -DCMAKE_INSTALL_LIBDIR=lib)
vcpkg_cmake_install()
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
