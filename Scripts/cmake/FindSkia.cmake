cmake_minimum_required(VERSION 3.20)

# This is dynamically loaded on user request, as they might not have
# or want to download the dependencies.
set(build_deps ${IPLUG2_SDK_PATH}/Dependencies/Build)

add_library(iPlug2_Skia INTERFACE)
set(_src)
set(_inc
  ${build_deps}/src/skia
  ${build_deps}/src/skia/include/core
  ${build_deps}/src/skia/include/effects
  ${build_deps}/src/skia/include/config
  ${build_deps}/src/skia/include/utils
  ${build_deps}/src/skia/include/gpu
  ${build_deps}/src/skia/modules/svg
)
set(_def IGRAPHICS_SKIA)
set(_lib iPlug2_IGraphicsCore)

if (IPLUG_OS MATCHES "Windows")
  set(sdk "${build_deps}/win/${PROCESSOR_ARCH}/$<IF:$<CONFIG:DEBUG>,Debug,Release>")
  list(APPEND _lib
    "${sdk}/skia.lib"
    "${sdk}/skottie.lib"
    "${sdk}/skparagraph.lib"
    "${sdk}/sksg.lib"
    "${sdk}/skshaper.lib"
    "${sdk}/svg.lib"
  )
elseif (OS_MAC)
  # TODO MAC: Check if this is the real path
  set(sdk "${build_deps}/mac/${PROCESSOR_ARCH}/lib")

elseif (OS_LINUX)
  set(sdk "${build_deps}/linux/lib")
  list(APPEND _lib
    "${sdk}/libskia.a"
    "${sdk}/libskottie.a"
    "${sdk}/libskparagraph.a"
    "${sdk}/libsksg.a"
    "${sdk}/libskshaper.a"
    "${sdk}/libsvg.a"
  )
endif()

iplug_target_add(
  iPlug2_Skia INTERFACE
  INCLUDE ${_inc}
  DEFINE ${_def}
  LINK ${_lib}
)
