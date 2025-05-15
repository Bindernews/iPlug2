cmake_minimum_required(VERSION 3.20)
include(FindPackageHandleStandardArgs)

# This is dynamically loaded on user request, as they might not have
# or want to download the dependencies.
set(build_deps ${IPLUG2_SDK_PATH}/Dependencies/Build)

find_path(
  SKIA_INCLUDE_DIR
  NAMES sksl
  PATHS ${build_deps}/src/skia/include
  DOC "Path to the Skia include directory"
)

find_path(
  SKIA_LIBRARY_DIR
  NAMES
    Debug/skia.lib
    libskia.a
  PATHS
    ${build_deps}/win/x64/
    ${build_deps}/mac/lib/
    ${build_deps}/ios/lib/
    ${build_deps}/linux/lib/
  DOC "Directory containing skia libraries"
)

find_package_handle_standard_args(
  Skia # Package name
  REQUIRED_VARS
    SKIA_INCLUDE_DIR
    SKIA_LIBRARY_DIR
)

add_library(iPlug2_skia INTERFACE)

set(skia_libs
  skia
  skottie
  skparagraph
  sksg
  skshaper
  svg
)
if (IPLUG_OS STREQUAL "Windows")
  list(TRANSFORM skia_libs APPEND ".lib")
  set(skia_link_dir "${SKIA_LIBRARY_DIR}/$<IF:$<CONFIG:DEBUG>,Debug,Release>")
else()
  list(TRANSFORM skia_libs PREPEND "lib")
  list(TRANSFORM skia_libs APPEND ".a")
  set(skia_link_dir ${SKIA_LIBRARY_DIR})
endif()

bn_target_add(
  iPlug2_skia INTERFACE
  DEFINE
    IGRAPHICS_SKIA
  LINK_DIR
    ${skia_link_dir}
  LINK
    iPlug2_IGraphicsCore
    ${skia_libs}
  INCLUDE
    ${SKIA_INCLUDE_DIR}/..
    ${SKIA_INCLUDE_DIR}/core
    ${SKIA_INCLUDE_DIR}/effects
    ${SKIA_INCLUDE_DIR}/config
    ${SKIA_INCLUDE_DIR}/utils
    ${SKIA_INCLUDE_DIR}/gpu
)
