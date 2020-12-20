cmake_minimum_required(VERSION 3.11)


##################
# IGraphics Core #
##################

add_library(iPlug2_IGraphicsCore INTERFACE)
set(_def "IPLUG_EDITOR=1")
set(_lib "")
set(_inc
  # IGraphics
  ${IGRAPHICS_SRC}
  ${IGRAPHICS_SRC}/Controls
  ${IGRAPHICS_SRC}/Drawing
  ${IGRAPHICS_SRC}/Platforms
  ${IGRAPHICS_SRC}/Extras
  ${IGRAPHICS_DEPS}/NanoSVG/src
  ${IGRAPHICS_DEPS}/NanoVG/src
  ${IGRAPHICS_DEPS}/Cairo
  ${IGRAPHICS_DEPS}/STB
  ${IGRAPHICS_DEPS}/imgui
  ${IGRAPHICS_DEPS}/imgui/examples
  ${IGRAPHICS_DEPS}/yoga
  ${IGRAPHICS_DEPS}/yoga/yoga
  ${IPLUG2_DIR}/Dependencies/Build/src
  ${IPLUG2_DIR}/Dependencies/Build/src/freetype/include
)
set(_src
  ${IGRAPHICS_SRC}/IControl.cpp
  ${IGRAPHICS_SRC}/IGraphics.cpp
  ${IGRAPHICS_SRC}/IGraphicsEditorDelegate.cpp
  ${IGRAPHICS_SRC}/Controls/IControls.cpp
  ${IGRAPHICS_SRC}/Controls/IPopupMenuControl.cpp
  ${IGRAPHICS_SRC}/Controls/ITextEntryControl.cpp
  ${IPLUG_SRC}/IPlugTaskThread.h
  ${IPLUG_SRC}/IPlugTaskThread.cpp
)

# Platform Settings
if (CMAKE_SYSTEM_NAME MATCHES "Windows")
  list(APPEND _src ${IGRAPHICS_SRC}/Platforms/IGraphicsWin.cpp)

elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
  list(APPEND _src
    ${IGRAPHICS_SRC}/Platforms/IGraphicsLinux.cpp
    ${IGRAPHICS_DEPS}/xcbt/xcbt.c
  )
  list(APPEND _inc
    ${IGRAPHICS_DEPS}/xcbt
  )
  list(APPEND _lib "xcb" "dl" "fontconfig" "freetype")
  set_property(SOURCE ${IGRAPHICS_DEPS}/xcbt/xcbt.c PROPERTY LANGUAGE C)

elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
  list(APPEND _src 
    ${IPLUG_SRC}/IPlugPaths.mm
    ${IGRAPHICS_SRC}/Platforms/IGraphicsMac.mm
    ${IGRAPHICS_SRC}/Platforms/IGraphicsMac_view.mm
    ${IGRAPHICS_SRC}/Platforms/IGraphicsCoreText.mm
  )
  list(APPEND _inc ${WDL_DIR}/swell)
  list(APPEND _lib
    "-framework Cocoa" "-framework Carbon" "-framework Metal" "-framework MetalKit" "-framework QuartzCore"
    "-framework OpenGL"
  )
  list(APPEND _opts "-Wno-deprecated-declarations")
else()
  message("Unhandled system ${CMAKE_SYSTEM_NAME}" FATAL_ERROR)
endif()

source_group(TREE ${IPLUG2_DIR} PREFIX "IPlug" FILES ${_src})
iplug2_target_add(iPlug2_IGraphicsCore INTERFACE DEFINE ${_def} INCLUDE ${_inc} SOURCE ${_src} LINK ${_lib})


###############
# No Graphics #
###############

add_library(iPlug2_NoGraphics INTERFACE)
iplug2_target_add(iPlug2_NoGraphics INTERFACE DEFINE "NO_IGRAPHICS=1")

#######################
# OpenGL Dependencies #
#######################

set(_glx_inc "")
set(_glx_src "")
if (CMAKE_SYSTEM_NAME MATCHES "Linux")
  set(_glx_inc ${IGRAPHICS_DEPS}/glad_GLX/include ${IGRAPHICS_DEPS}/glad_GLX/src)
  set(_glx_src ${IGRAPHICS_DEPS}/glad_GLX/src/glad_glx.c)
endif()

add_library(iPlug2_GL2 INTERFACE)
iplug2_target_add(iPlug2_GL2 INTERFACE
  INCLUDE 
    ${IGRAPHICS_DEPS}/glad_GL2/include ${IGRAPHICS_DEPS}/glad_GL2/src ${_glx_inc}
  SOURCE
    ${_glx_src}
  DEFINE "IGRAPHICS_GL2"
)

add_library(iPlug2_GL3 INTERFACE)
iplug2_target_add(iPlug2_GL3 INTERFACE
  INCLUDE
    ${IGRAPHICS_DEPS}/glad_GL3/include ${IGRAPHICS_DEPS}/glad_GL3/src ${_glx_inc}
  SOURCE
    ${_glx_src}
  DEFINE "IGRAPHICS_GL3"
)

##########
# NanoVG #
##########

add_library(iPlug2_NANOVG INTERFACE)
iplug2_target_add(iPlug2_NANOVG INTERFACE
  DEFINE "IGRAPHICS_NANOVG"
  LINK iPlug2_IGraphicsCore
)
if (CMAKE_SYSTEM_NAME MATCHES "Darwin")
  set(_src ${IPLUG_DEPS}/IGraphics/NanoVG/src/nanovg.c)
  iplug2_target_add(iPlug2_NANOVG INTERFACE SOURCE ${_src})
  set_property(SOURCE ${_src} PROPERTY LANGUAGE C)
endif()
<<<<<<< HEAD:Scripts/cmake/IGraphics.cmake
iplug2_source_tree(iPlug2_NANOVG)
=======

add_library(iPlug2_NoGraphics INTERFACE)
iplug2_target_add(iPlug2_NoGraphics INTERFACE
  DEFINE "NO_GRAPHICS"
)
>>>>>>> parent of b539a5f6a... Move CMake scripts into Scripts dir and fix MacOS builds.:cmake/IGraphics.cmake

########
# Skia #
########

add_library(iPlug2_Skia INTERFACE)
iplug2_target_add(iPlug2_Skia INTERFACE 
  DEFINE "IGRAPHICS_SKIA"
  LINK iPlug2_IGraphicsCore)

if (WIN32)
  set(sdk "${BUILD_DEPS}/win/${PROCESSOR_ARCH}/$<IF:$<CONFIG:DEBUG>,Debug,Release>")
  iplug2_target_add(iPlug2_Skia INTERFACE
    LINK
      "${sdk}/libpng.lib"
      "${sdk}/pixman.lib"
      "${sdk}/skia.lib"
      "${sdk}/skottie.lib"
      "${sdk}/skparagraph.lib"
      "${sdk}/sksg.lib"
      "${sdk}/skshaper.lib")

elseif (OS_MAC)
  # TODO MAC: Check if this is the real path
  set(sdk "${IPLUG_DEPS}/../Build/mac/${PROCESSOR_ARCH}/lib")

elseif (OS_LINUX)
  set(sdk "${IPLUG_DEPS}/../Build/linux/lib")
  iplug2_target_add(iPlug2_Skia INTERFACE
    LINK 
      "${sdk}/libpng.a"
      "${sdk}/libpixman-1.a"
      "${sdk}/libskia.a"
      "${sdk}/libskottie.a"
      "${sdk}/libskparagraph.a"
      "${sdk}/libsksg.a"
      "${sdk}/libskshaper.a")

endif()

iplug2_target_add(iPlug2_Skia INTERFACE
  INCLUDE
    ${BUILD_DEPS}/src/skia
    ${BUILD_DEPS}/src/skia/include/core
    ${BUILD_DEPS}/src/skia/include/effects
    ${BUILD_DEPS}/src/skia/include/config
    ${BUILD_DEPS}/src/skia/include/utils
    ${BUILD_DEPS}/src/skia/include/gpu
    ${BUILD_DEPS}/src/skia/experimental/svg/model)

add_library(iPlug2_Skia_GL2 INTERFACE)
target_link_libraries(iPlug2_Skia_GL2 INTERFACE iPlug2_Skia iPlug2_GL2)

add_library(iPlug2_Skia_GL3 INTERFACE)
target_link_libraries(iPlug2_Skia_GL3 INTERFACE iPlug2_Skia iPlug2_GL3)

add_library(iPlug2_Skia_CPU INTERFACE)
iplug2_target_add(iPlug2_Skia_CPU INTERFACE DEFINE "IGRAPHICS_CPU" LINK iPlug2_Skia)

########
# LICE #
########

include("${IPLUG2_DIR}/cmake/LICE.cmake")

# LICE build is different between APP and all other targets when using swell.
# Link to iPlug2_LICE and we'll fix it in configure.
add_library(iPlug2_LICE INTERFACE)
iplug2_target_add(iPlug2_LICE INTERFACE
  DEFINE "IGRAPHICS_LICE" "SWELL_EXTRA_MINIMAL" "SWELL_LICE_GDI" "SWELL_FREETYPE"
  SOURCE "${IGRAPHICS_SRC}/Drawing/IGraphicsLice_src.cpp"
  LINK iPlug2_IGraphicsCore LICE_Core LICE_PNG LICE_ZLIB "dl" "pthread"
)

# set(swell_src
#   swell.h
#   swell.cpp
#   swell-dlg-generic.cpp
#   swell-gdi-generic.cpp
#   swell-ini.cpp
#   swell-menu-generic.cpp
#   swell-wnd-generic.cpp
#   swell-gdi-lice.cpp
# )
# list(TRANSFORM swell_src PREPEND "${WDL_DIR}/swell/")

if (OS_LINUX)
  pkg_check_modules(Freetype2 REQUIRED IMPORTED_TARGET "freetype2")
  iplug2_target_add(iPlug2_LICE INTERFACE
    INCLUDE 
      ${IGRAPHICS_DEPS}/glad_GL2/include
      ${IGRAPHICS_DEPS}/glad_GL2/src
      ${_glx_inc}
    SOURCE ${_glx_src}
    LINK PkgConfig::Freetype2
  )  
endif()

#########
# Cairo #
#########

if ("Cairo" IN_LIST "${iPlug2_FIND_COMPONENTS}")
  add_library(iPlug2_Cairo INTERFACE)
  iplug2_target_add(iPlug2_Cairo
    DEFINE "IGRAPHICS_CAIRO"
    INCLUDE 
      "${IGRAPHICS_DEPS}/NanoSVG/src"
      "${IGRAPHICS_DEPS}/cairo"
  )
  if (OS_LINUX)
    pkg_check_modules(Cairo REQUIRED IMPORTED_TARGET "cairo")

    iplug2_target_add(iPlug2_Cairo INTERFACE
      LINK PkgConfig::Cairo "freetype" "png" "z" "xcb" "xcb-shm" "xcb-render"
    )
  else()
    message("Cairo not supported on this system" FATAL_ERROR)
  endif()
endif()

#######
# AAG #
#######

set(sdk "${IPLUG2_DIR}/Dependencies/IGraphics/AGG/agg-2.4")
set(_src
  "${sdk}/src/agg_arc.cpp"
  "${sdk}/src/agg_arrowhead.cpp"
  "${sdk}/src/agg_bezier_arc.cpp"
  "${sdk}/src/agg_bspline.cpp"
  "${sdk}/src/agg_color_rgba.cpp"
  "${sdk}/src/agg_curves.cpp"
  "${sdk}/src/agg_image_filters.cpp"
  "${sdk}/src/agg_line_aa_basics.cpp"
  "${sdk}/src/agg_line_profile_aa.cpp"
  "${sdk}/src/agg_rounded_rect.cpp"
  "${sdk}/src/agg_sqrt_tables.cpp"
  "${sdk}/src/agg_trans_affine.cpp"
  "${sdk}/src/agg_trans_double_path.cpp"
  "${sdk}/src/agg_trans_single_path.cpp"
  "${sdk}/src/agg_trans_warp_magnifier.cpp"
  "${sdk}/src/agg_vcgen_bspline.cpp"
  "${sdk}/src/agg_vcgen_contour.cpp"
  "${sdk}/src/agg_vcgen_dash.cpp"
  "${sdk}/src/agg_vcgen_markers_term.cpp"
  "${sdk}/src/agg_vcgen_smooth_poly1.cpp"
  "${sdk}/src/agg_vcgen_stroke.cpp"
  "${sdk}/src/agg_vpgen_clip_polygon.cpp"
  "${sdk}/src/agg_vpgen_clip_polyline.cpp"
  "${sdk}/src/agg_vpgen_segmentator.cpp"
)
add_library(AGG STATIC ${_src})
iplug2_target_add(AGG PUBLIC
  INCLUDE
    "${sdk}/include"
    "${sdk}/font_freetype"
    "${sdk}/include/util"
    "${sdk}/src"
    "${sdk}/include/platform/win32"
    "${sdk}/src/platform/win32"
)

add_library(iPlug2_AGG INTERFACE)
iplug2_target_add(iPlug2_AGG INTERFACE
  LINK AGG iPlug2_IGraphicsCore
  DEFINE "IGRAPHICS_AGG"
)
