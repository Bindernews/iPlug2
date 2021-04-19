cmake_minimum_required(VERSION 3.16 FATAL_ERROR)

#########
# This is a build file for iPlug2 on Linux.
# It may work on Windows and MacOS, but that isn't the initial goal.
#
# To setup the build (change CMAKE_BUILD_TYPE as desired):
#   cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
# To build the VST2 version:
#   cmake --build build-linux --target IPlugInstrument-vst2
# To build the VST3 version:
#   cmake --build build-linux --target IPlugInstrument-vst3

project(IPlugInstrument VERSION 1.0.0)

set(IPLUG2_SDK_PATH ${CMAKE_SOURCE_DIR}/../..)
include(${IPLUG2_SDK_PATH}/iPlug2.cmake)
find_package(iPlug2 REQUIRED)

set(dir "${CMAKE_SOURCE_DIR}")
set(SRC_FILES
  "${dir}/config.h"
  "${dir}/IPlugInstrument.h"
  "${dir}/IPlugInstrument.cpp"
  "${dir}/IPlugInstrument_DSP.h"
)
source_group(TREE ${dir} FILES ${SRC_FILES})
set(RES_FILES
  "${dir}/resources/fonts/Roboto-Regular.ttf"
)
source_group(TREE "${dir}/resources" PREFIX Resources FILES ${RES_FILES})

# Disable compiler-dependent C++ extension features (optional, but recommended for code portability)
set(CMAKE_CXX_EXTENSIONS OFF)

iplug_add_plugin(IPlugInstrument
  PLUGIN_NAME "IPlugInstrument"
  GRAPHICS NANOVG_GL2
  FORMATS APP LV2 VST2 VST3 AU2 AU3
  RESOURCES ${RES_FILES}
  COPY_AFTER_BUILD
)
target_link_libraries(IPlugInstrument INTERFACE iPlug2_Synth)
target_compile_features(IPlugInstrument INTERFACE cxx_std_17)
target_sources(IPlugInstrument INTERFACE ${SRC_FILES} ${RES_FILES})
target_include_directories(IPlugInstrument INTERFACE "." "./resources")
# iplug_add_resources(IPlugInstrument RESOURCES ${RES_FILES})
# iplug_finish_plugin(IPlugInstrument)
