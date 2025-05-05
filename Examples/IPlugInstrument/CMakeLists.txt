cmake_minimum_required(VERSION 3.20 FATAL_ERROR)

#########
# This is a build file for iPlug2.
# It may work on Windows and MacOS, but that isn't the initial goal.
#
# To setup the build:
#   cmake -S. --preset default-linux
# To build the VST2 version:
#   cmake --build build-linux --target IPlugInstrument_vst2

set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)
project(IPlugInstrument VERSION 1.0.0 LANGUAGES C CXX)

if (NOT IPLUG2_SDK_PATH)
  set(IPLUG2_SDK_PATH ${CMAKE_SOURCE_DIR}/../../)
endif()
include(${IPLUG2_SDK_PATH}/iPlug2.cmake)

# Verify that the required formats loaded successfully.
foreach (format app clap)
  if (NOT ${format} IN_LIST IPLUG_LOADED_FORMATS)
    message(FATAL_ERROR "Missing required output format: ${format}")
  endif()
endforeach()

# Disable compiler-dependent C++ extension features (optional, but recommended for code portability)
set(CMAKE_CXX_EXTENSIONS OFF)

# Setup the plugin base library. This contains the user's source code
# and will be linked to different targets for each output format.
# The plugin base target MUST be an interface library.
add_library(plugin_base INTERFACE)

# Shorthand for the current directory
set(cwd "${CMAKE_CURRENT_LIST_DIR}")

# Absolute paths are not required for sources or resources.
set(_src
  config.h
  IPlugInstrument.h
  IPlugInstrument.cpp
  IPlugInstrument_DSP.h
)
# List of resources to include. These may also be added directly
# with iplug_target_add(<target> INTERFACE RESOURCE <file1> <files...>).
set(_res
  resources/fonts/Roboto-Regular.ttf
)

iplug_target_add(plugin_base INTERFACE
  SOURCE
    ${_src}
  RESOURCE
    ${_res}
  LINK
    # This is an instrument, so we link to Synth to help generate output
    iPlug2_Synth
  FEATURE
    # Using C++ 17
    cxx_std_17
  INCLUDE
    ${cwd}
    ${cwd}/resources
)

iplug_embed_files(
  plugin_base
  FILES
    ${IPLUG2_SDK_PATH}/IPlug/resource/Roboto-Regular.ttf
    resources/IPlugInstrument.ico
)

# Make things pretty in IDEs.
# source_group(TREE ${cwd} FILES ${_src})
source_group(TREE "${cwd}/resources" PREFIX Resources FILES ${_res})

# Configure the plugin with the default name and version
# from the project, using NanoVG with OpenGL 3 as the backend.
iplug_setup_plugin(
  plugin_base
  GRAPHICS NanoVG GL3
  # List of plugin formats to export, or ALL for all supported formats on this platform.
  FORMATS
    app clap
    vst2 vst3 au2 au3 lv2 wam
  COPY_AFTER_BUILD
)
