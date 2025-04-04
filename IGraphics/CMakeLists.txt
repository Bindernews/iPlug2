cmake_minimum_required(VERSION 3.20)

set(WDL_DIR ${IPLUG2_SDK_PATH}/WDL)
if (IPLUG_OS MATCHES "Linux")
  find_package(PkgConfig)
endif()

########################
# iPlug2_IGraphicsCore #
########################

set(cwd ${CMAKE_CURRENT_LIST_DIR})
set(deps_dir ${IPLUG2_SDK_PATH}/Dependencies/IGraphics)
set(_def
  "IPLUG_EDITOR=1"
  BUILT_WITH_CMAKE
)
set(_lib iPlug2_Core)
set(_inc
  # IGraphics
  ${cwd}
  ${cwd}/Controls
  ${cwd}/Drawing
  ${cwd}/Platforms
  ${cwd}/Extras
  ${deps_dir}/NanoSVG/src
  ${deps_dir}/NanoVG/src
  ${deps_dir}/STB
  ${deps_dir}/imgui
  ${deps_dir}/imgui/examples
  ${deps_dir}/yoga
  ${deps_dir}/yoga/yoga
  ${IPLUG2_SDK_PATH}/Dependencies/Build/src
  ${IPLUG2_SDK_PATH}/Dependencies/Build/src/freetype/include
)
set(_src
  ${cwd}/IControl.cpp
  ${cwd}/IGraphics.cpp
  ${cwd}/IGraphicsEditorDelegate.cpp
  ${cwd}/Controls/IControls.cpp
  ${cwd}/Controls/IPopupMenuControl.cpp
  ${cwd}/Controls/ITextEntryControl.cpp
)
set(_opt "")

# Platform Settings
if (IPLUG_OS MATCHES "Windows")
  list(APPEND _src ${cwd}/Platforms/IGraphicsWin.cpp)

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
        libglx-dev
      )
    else()
      set(apt_prog "<package_manager install>")
      set(pkgs "<unknown>")
    endif()

    list(JOIN pkgs " " pkgs2)
    message(SEND_ERROR "Please `${apt_prog}` the following packages:\n${pkgs2}")
  endif()

  list(APPEND _src
    ${cwd}/Platforms/IGraphicsLinux.cpp
    ${deps_dir}/xcbt/xcbt.c
  )
  list(APPEND _inc
    ${deps_dir}/xcbt
    ${WDL_DIR}
  )
  list(APPEND _lib
    PkgConfig::X11Libraries
    "dl"
  )
  set_property(SOURCE ${deps_dir}/xcbt/xcbt.c PROPERTY LANGUAGE C)

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
  ${deps_dir}/NanoSVG/src
  ${deps_dir}/NanoVG/src
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
add_library(iPlug2_CPU INTERFACE)
iplug_target_add(iPlug2_CPU INTERFACE
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
set(tgt iPlug2_GL2)
add_library(iPlug2_GL2 INTERFACE)
target_sources(${tgt} INTERFACE ${deps_dir}/glad_GL2/src/glad.c)
target_include_directories(${tgt} INTERFACE ${deps_dir}/glad_GL2/include)
target_link_libraries(${tgt} INTERFACE iPlug2_DesktopGL_Base)
target_compile_definitions(${tgt} INTERFACE "IGRAPHICS_GL2")

# Target for using desktop OpenGL 3.0/3.3 or higher as the graphics backend.
set(tgt iPlug2_GL3)
add_library(iPlug2_GL3 INTERFACE)
target_sources(${tgt} INTERFACE ${deps_dir}/glad_GL3/src/glad.c)
target_include_directories(${tgt} INTERFACE ${deps_dir}/glad_GL3/include)
target_link_libraries(${tgt} INTERFACE iPlug2_DesktopGL_Base)
target_compile_definitions(${tgt} INTERFACE "IGRAPHICS_GL3")

##########
# NanoVG #
##########

set(tgt iPlug2_NanoVG)
add_library(iPlug2_NanoVG INTERFACE)
set(_def "IGRAPHICS_NANOVG")
set(_lib iPlug2_IGraphicsCore)
set(_src)
set(_inc)

if (IPLUG_OS MATCHES "Darwin")
  # Prefer MetalNanoVG on macOS/iOS
  set(nvg_dir ${deps_dir}/MetalNanoVG)
  list(APPEND _inc ${nvg_dir}/src)
  list(APPEND _def "IGRAPHICS_METAL")
  list(APPEND _lib iPlug2_DesktopGL_Base)
else()
  # Link to normal NanoVG
  set(nvg_dir ${deps_dir}/NanoVG)
  set(sdk ${nvg_dir}/src)
  # list(APPEND _src
  #   ${sdk}/nanovg.c
  #   ${sdk}/fontstash.h
  #   ${sdk}/nanovg_gl_utils.h
  #   ${sdk}/nanovg_gl.h
  #   ${sdk}/nanovg.h
  #   ${sdk}/stb_image.h
  #   ${sdk}/stb_truetype.h
  #   ${cwd}/Drawing/IGraphicsNanoVG.cpp
  # )
  list(APPEND _inc
    ${deps_dir}/NanoVG/src
    ${deps_dir}/NanoSVG/src
  )
endif()

iplug_target_add(iPlug2_NanoVG INTERFACE
  SOURCE ${_src}
  INCLUDE ${_inc}
  DEFINE ${_def}
  LINK ${_lib}
)

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

########
# Skia #
########
# Use find_package(Skia) to load the Skia libraries.
