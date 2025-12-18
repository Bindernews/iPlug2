cmake_minimum_required(VERSION 3.24)
include(FetchContent)

# Set SDL options before making it available.
set(SDL_SHARED OFF CACHE BOOL "")
set(SDL_STATIC ON CACHE BOOL "")
set(SDL_WAYLAND OFF CACHE BOOL "")
set(SDL_STATIC_PIC ON CACHE BOOL "")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "")
set(BUILD_STATIC_LIBS ON CACHE BOOL "")


FetchContent_Declare(
    SDL3
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
#    GIT_TAG release-3.2.16
    GIT_TAG 0f061ff154dafb2f65fd882aa69beb119f99318d
    SOURCE_DIR "${IPLUG2_SDK_PATH}/Dependencies/sdl3"
)
FetchContent_MakeAvailable(SDL3)
set_target_properties(SDL3-static PROPERTIES POSITION_INDEPENDENT_CODE ON)

set(WDL_DIR ${IPLUG2_SDK_PATH}/WDL)
if (IPLUG_OS MATCHES "Linux")
  find_package(PkgConfig)
endif()

set(cwd ${CMAKE_CURRENT_LIST_DIR})
set(deps_dir ${IPLUG2_SDK_PATH}/Dependencies/IGraphics)

add_subdirectory(${deps_dir}/yoga ${CMAKE_CURRENT_BINARY_DIR}/yoga)

########################
# iPlug2_IGraphicsCore #
########################

set(_def
  "IPLUG_EDITOR=1"
  BUILT_WITH_CMAKE
)
set(_lib
  iPlug2_Core
)
set(_inc
  # IGraphics
  ${cwd}
  ${cwd}/Controls
  ${cwd}/Extras
  ${deps_dir}/NanoSVG/src
  ${deps_dir}/NanoVG/src
  ${deps_dir}/STB
  ${deps_dir}/imgui
  ${deps_dir}/imgui/examples
  ${IPLUG2_SDK_PATH}/Dependencies/Build/src
  ${IPLUG2_SDK_PATH}/Dependencies/Build/src/freetype/include
)
set(_src
  ${cwd}/IControl.cpp
  ${cwd}/IControl.h
  ${cwd}/IGraphics_select.h
  ${cwd}/IGraphics.cpp
  ${cwd}/IGraphics.h
  ${cwd}/IGraphicsConstants.h
  ${cwd}/IGraphicsEditorDelegate.cpp
  ${cwd}/IGraphicsEditorDelegate.h
  ${cwd}/IGraphicsLiveEdit.h
  ${cwd}/IGraphicsPopupMenu.h
  ${cwd}/IGraphicsPrivate.h
  ${cwd}/IGraphicsStructs.h
  ${cwd}/IGraphicsUtilities.h

  ${cwd}/Controls/IControls.cpp
  ${cwd}/Controls/IControls.h
  ${cwd}/Controls/IPopupMenuControl.cpp
  ${cwd}/Controls/IPopupMenuControl.h
  ${cwd}/Controls/ITextEntryControl.cpp
  ${cwd}/Controls/ITextEntryControl.h
)
set(_opt "")

# Platform Settings
if (IPLUG_OS MATCHES "Windows")
  list(APPEND _src
    ${cwd}/Platforms/IGraphicsWin.cpp
    ${cwd}/Platforms/IGraphicsWin.h
    ${cwd}/Platforms/IGraphicsWinFonts.h
  )

elseif (IPLUG_OS MATCHES "Linux")
  pkg_check_modules(
    X11Libraries REQUIRED IMPORTED_TARGET
    "freetype2"
    "fontconfig"
    "x11-xcb"
    "xcb"
    "xcb-event"
    "xcb-util"
    "xcb-icccm"
    "xcb-xfixes"
  )

  # Try to help user by listing required dev packages for their platform.
  if (NOT X11Libraries_FOUND)
    find_package(LinuxDistro)
    if (LINUX_DISTRO_ID MATCHES "ubuntu")
      set(apt_prog "apt-get install")
      set(pkgs
        # Font stuff
        libfreetype-dev
        libfontconfig-dev
        # Audio libraries
        libasound2-dev
        # GTK / GDK
        libglib2.0-dev
        libgtk-3-dev
        # X11/XCB
        libx11-xcb-dev
        libxcb-util-dev
        libxcb-icccm4-dev
        libxcb-xfixes0-dev
        libglx-dev # only required for APP
      )
    else()
      set(apt_prog "<package_manager install>")
      set(pkgs "<unknown>")
    endif()

    list(JOIN pkgs " " pkgs2)
    message(SEND_ERROR "Please `${apt_prog}` the following packages:\n${pkgs2}")
  endif()

  list(APPEND _src
    ${cwd}/Platforms/SDL_events.hpp
    ${cwd}/Platforms/IGraphicsLinux.cpp
    ${cwd}/Platforms/IGraphicsLinux.h
    ${cwd}/Platforms/PlatformX11.cpp
    ${cwd}/Platforms/PlatformX11.hpp
  )
  list(APPEND _inc
    ${WDL_DIR}
  )
  list(APPEND _lib
    PkgConfig::X11Libraries
    SDL3::SDL3-static
    "dl"
  )

elseif (IPLUG_OS MATCHES "Darwin")
  list(APPEND _src
    ${cwd}/Platforms/IGraphicsMac.mm
    ${cwd}/Platforms/IGraphicsMac_view.mm
    ${cwd}/Platforms/IGraphicsCoreText.mm
  )
  list(APPEND _inc ${WDL_DIR}/swell)
  list(APPEND _lib
    "-framework Cocoa"
    "-framework Carbon"
    "-framework QuartzCore"
  )
  list(APPEND _opt "-Wno-deprecated-declarations")
endif()

add_library(iPlug2_IGraphicsCore INTERFACE)
iplug_target_add(iPlug2_IGraphicsCore INTERFACE
  DEFINE ${_def}
  INCLUDE ${_inc}
  SOURCE ${_src}
  LINK ${_lib}
  OPTION ${_opt}
)
source_group(IPlug FILES ${_src})

################
# Misc Options #
################

# No graphics
add_library(iPlug2_NoGraphics INTERFACE)
iplug_target_add(iPlug2_NoGraphics INTERFACE
  DEFINE
  "NO_IGRAPHICS=1"

  INCLUDE
  # IGraphics
  ${cwd}
  ${cwd}/Controls
  ${cwd}/Drawing
  ${cwd}/Platforms
  ${cwd}/Extras
  ${deps_dir}/STB
  ${deps_dir}/imgui
  ${deps_dir}/imgui/examples
  ${IPLUG2_SDK_PATH}/Dependencies/Build/src
  ${IPLUG2_SDK_PATH}/Dependencies/Build/src/freetype/include
)

# Custom graphics
add_library(iPlug2_CustomGraphics INTERFACE)
iplug_target_add(iPlug2_CustomGraphics
  DEFINE "IGRAPHICS_CUSTOM=1"
)

# Use CPU rendering for the IGraphics backend. Currently only supported on Skia.
add_library(iPlug2_cpu INTERFACE)
iplug_target_add(iPlug2_cpu INTERFACE
  DEFINE "IGRAPHICS_CPU"
)

#######################
# OpenGL Dependencies #
#######################

# Base OpenGL Desktop target. This links to the platform-specific
# GL libraries, but doesn't set IGRAPHICS_ defines. Users should NOT
# link to this library directly.
set(tgt iPlug2_DesktopGL_Base)
add_library(iPlug2_DesktopGL_Base INTERFACE)

if (IPLUG_OS MATCHES "Darwin")
  # Also link to Metal on MacOS
  target_link_libraries(${tgt} INTERFACE
    "-framework OpenGL"
    "-framework Metal"
    "-framework MetalKit"
  )
elseif (IPLUG_OS MATCHES "Linux")
  pkg_check_modules(GLX REQUIRED IMPORTED_TARGET "glx")
  iplug_target_add(${tgt} INTERFACE
    INCLUDE ${deps_dir}/glad_GLX/include
    SOURCE ${deps_dir}/glad_GLX/src/glad_glx.c
    LINK PkgConfig::GLX
    OPTION "-fPIC"
  )
endif()

# Target for using desktop OpenGL 2.1 as the graphics backend.
set(tgt iPlug2_gl2)
add_library(iPlug2_gl2 INTERFACE)
target_sources(${tgt} INTERFACE ${deps_dir}/glad_GL2/src/glad.c)
target_include_directories(${tgt} INTERFACE ${deps_dir}/glad_GL2/include)
target_link_libraries(${tgt} INTERFACE iPlug2_DesktopGL_Base)
target_compile_definitions(${tgt} INTERFACE "IGRAPHICS_GL2")

# Target for using desktop OpenGL 3.0/3.3 or higher as the graphics backend.
set(tgt iPlug2_gl3)
add_library(iPlug2_gl3 INTERFACE)
target_sources(${tgt} INTERFACE ${deps_dir}/glad_GL3/src/glad.c)
target_include_directories(${tgt} INTERFACE ${deps_dir}/glad_GL3/include)
target_link_libraries(${tgt} INTERFACE iPlug2_DesktopGL_Base)
target_compile_definitions(${tgt} INTERFACE "IGRAPHICS_GL3")

##########
# NanoVG #
##########

set(tgt iPlug2_gui_nanovg)
add_library(${tgt} INTERFACE)
bn_target_add(
  ${tgt} INTERFACE
  DEFINE
    "IGRAPHICS_NANOVG"
  LINK
    iPlug2_IGraphicsCore
)

if (IPLUG_OS MATCHES "Darwin")
  # Prefer MetalNanoVG on macOS/iOS
  set(nvg_dir ${deps_dir}/MetalNanoVG)
  bn_target_add(
    ${tgt} INTERFACE
    INCLUDE ${nvg_dir}/src
    DEFINE "IGRAPHICS_METAL"
    LINK iPlug2_DesktopGL_Base
  )
else()
  # Link to normal NanoVG
  set(sdk ${deps_dir}/NanoVG/src)
  bn_target_add(
    ${tgt} INTERFACE
    INCLUDE
      ${deps_dir}/NanoVG/src
      ${deps_dir}/NanoSVG/src
    # SOURCE
      # ${sdk}/nanovg.c
      # ${sdk}/fontstash.h
      # ${sdk}/nanovg_gl_utils.h
      # ${sdk}/nanovg_gl.h
      # ${sdk}/nanovg.h
      # ${sdk}/stb_image.h
      # ${sdk}/stb_truetype.h
      # ${cwd}/Drawing/IGraphicsNanoVG.cpp
    )
endif()

#######################
# Canvas Graphics API #
#######################

set(tgt iPlug2_WebCanvas)
add_library(iPlug2_WebCanvas INTERFACE)
# Only do this for emscripten builds
if (CMAKE_SYSTEM_NAME MATCHES "Emscripten")
  iplug_target_add(
    iPlug2_WebCanvas INTERFACE
    DEFINE
      # Using canvas graphics backend
      IGRAPHICS_CANVAS
      # Force using GLES2
      IGRAPHICS_GLES2
    SOURCE
      ${cwd}/Drawing/IGraphicsCanvas.h
      # ${cwd}/Drawing/IGraphicsCanvas.cpp
      ${cwd}/Platforms/IGraphicsWeb.h
      ${cwd}/Platforms/IGraphicsWeb.cpp
    INCLUDE
      # Include NanoVG directorys, not sure why
      ${deps_dir}/NanoVG/src
      ${deps_dir}/NanoSVG/src
    LINK
      iPlug2_IGraphicsCore
  )
endif()

#--------#
# Extras #
#--------#

add_library(iplug2_flex_box INTERFACE)
bn_target_add(
  iplug2_flex_box INTERFACE
  SOURCE
    Extras/IGraphicsFlexBox.cpp
    Extras/IGraphicsFlexBox.h
  LINK
    yoga
)

########
# Skia #
########
# Loaded dynamically during iplug_setup_plugin.
