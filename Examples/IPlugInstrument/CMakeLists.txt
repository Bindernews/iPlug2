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

iplug_target_add(plugin_base INTERFACE
  SOURCE
    config.h
    IPlugInstrument.h
    IPlugInstrument.cpp
    IPlugInstrument_DSP.h
  RESOURCE
    # Resources to include
    resources/fonts/Roboto-Regular.ttf
  LINK
    # This is an instrument, so we link to Synth to help generate output
    iPlug2_Synth
  FEATURE
    # Using C++ 17
    cxx_std_17
  INCLUDE
    ${CMAKE_CURRENT_LIST_DIR}
)


# Configure the plugin with the default name and version
# from the project, using NanoVG with OpenGL 3 as the backend.
iplug_setup_plugin(
  plugin_base
  GRAPHICS NanoVG+GL3
  # List of plugin formats to export, or ALL for all supported formats on this platform.
  FORMATS ALL
  # The icon to use for the plugin
  # ICON resources/IPlugInstrument.ico
  COPY_AFTER_BUILD
  # Metadata
  YEAR 2025
  AUTHOR "Acme Inc."
  DESCRIPTION "iPlug2 instrument example"
  MIDI_IN ON
  MIDI_OUT ON
  DOES_MPE ON
  URL "https://iplug2.github.io"
  SUPPORT_URL "https://github.com/iPlug2/iPlug2/wiki"
  MANUAL_URL "https://iplug2.github.io/manuals/example_manual.pdf"
)
