cmake_minimum_required(VERSION 3.20)
cmake_policy(SET CMP0076 NEW)
# Only interpret if() arguments as variables or keywords when unquoted
cmake_policy(SET CMP0054 NEW)
# So we can check for optimization flags
include(CheckCXXCompilerFlag)
include(CheckLinkerFlag)

# Load helper functions
set(BN_RESOURCE_PROPERTY "IPLUG_RESOURCES" CACHE INTERNAL "" FORCE)
include(BnFunctions)
include(IPlugFunctions)

if (CMAKE_SYSTEM_NAME MATCHES "Windows")
  # Need to determine processor arch for postbuild-win.bat
  if (CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64")
    set(PROCESSOR_ARCH "x64" CACHE STRING "Processor architecture")
  else()
    set(PROCESSOR_ARCH "Win32" CACHE STRING "Processor architecture")
  endif()
  set(IPLUG_OS "Windows")

elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
  set(IPLUG_OS "Darwin")

elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
  set(IPLUG_OS "Linux")

elseif (CMAKE_SYSTEM_NAME MATCHES "Emscripten")
  set(IPLUG_OS "Emscripten")

elseif (CMAKE_SYSTEM_NAME MATCHES "iOS")
  set(IPLUG_OS "iOS")
  message(WARNING "Building iPlug2 for iOS with CMake is currently *very* experimental.")

else()
  message(FATAL_ERROR "Unsupported platform ${CMAKE_SYSTEM_NAME}")
endif()
# Force-set it as a cache variable
set(IPLUG_OS ${IPLUG_OS} CACHE STRING "OS name" FORCE)

# These functions MUST be run in a global scope
CHECK_CXX_COMPILER_FLAG("-march=native" COMPILER_OPT_ARCH_NATIVE_SUPPORTED)
CHECK_CXX_COMPILER_FLAG("/arch:AVX" COMPILER_OPT_ARCH_AVX_SUPPORTED)
check_linker_flag(C "--error-unresolved-symbols" IPLUG_LINKER_FLAG_ERROR_UNRESOLVED_SYMBOLS)

# Add .gitignore to the build root
write_file(${CMAKE_BINARY_DIR}/.gitignore "*\n")

# Use advanced SIMD instructions when available.
add_library(iplug2_opt_simd INTERFACE)
if (COMPILER_OPT_ARCH_NATIVE_SUPPORTED)
  target_compile_options(iplug2_opt_simd INTERFACE "-march=native")
elseif(COMPILER_OPT_ARCH_AVX_SUPPORTED)
  target_compile_options(iplug2_opt_simd INTERFACE "/arch:AVX")
endif()

#########################
# iPlug2 Core Interface #
#########################

# Core iPlug2 interface. All targets MUST link to this.
add_library(iPlug2_Core INTERFACE)

set(IPLUG_SRC ${IPLUG2_SDK_PATH}/IPlug)
set(IGRAPHICS_SRC ${IPLUG2_SDK_PATH}/IGraphics)
set(WDL_DIR ${IPLUG2_SDK_PATH}/WDL)
set(IPLUG_DEPS ${IPLUG2_SDK_PATH}/Dependencies/IPlug)
set(IGRAPHICS_DEPS ${IPLUG2_SDK_PATH}/Dependencies/IGraphics)
set(BUILD_DEPS ${IPLUG2_SDK_PATH}/Dependencies/Build)

set(cwd ${CMAKE_CURRENT_LIST_DIR})

# Make sure we define DEBUG for debug builds
set(_def
  # Required for SWELL and MSVC builds
  NOMINMAX
  $<$<CONFIG:Debug>:_DEBUG>
)
set(_opt "")
set(_lib "")
set(_inc
  ${cwd}
  ${cwd}/Extras
  # iPlug2
  ${WDL_DIR}
  ${WDL_DIR}/libpng
  ${WDL_DIR}/zlib
)
set(_src
  ${cwd}/IPlugAPIBase.h
  ${cwd}/IPlugAPIBase.cpp
  ${cwd}/IPlugEditorDelegate.h
  ${cwd}/IPlugPluginBase.h
  ${cwd}/IPlugPluginBase.cpp
)

# Parts of the iPlug source that (eventually) will be statically built,
# as opposed to being re-compiled for each output format.
set(_static_src
  ${cwd}/IPlugConstants.h
  ${cwd}/IPlugPlatform.h
  ${cwd}/IPlugLogger.h
  ${cwd}/IPlugMidi.h
  ${cwd}/IPlugParameter.h
  ${cwd}/IPlugParameter.cpp
  ${cwd}/IPlugPaths.h
  ${cwd}/IPlugPaths.cpp
  ${cwd}/IPlugProcessor.h
  ${cwd}/IPlugProcessor.cpp
  ${cwd}/IPlugQueue.h
  ${cwd}/IPlugStructs.h
  ${cwd}/IPlugTimer.h
  ${cwd}/IPlugTimer.cpp
  ${cwd}/IPlugUtilities.h
)

# Platform Settings
if (IPLUG_OS MATCHES "Windows")
  list(APPEND _lib
    "Shlwapi.lib"
    "comctl32.lib"
    "wininet.lib"
  )

elseif (IPLUG_OS MATCHES "Linux")
  list(APPEND _inc ${WDL_DIR}/swell)
  list(APPEND _lib "pthread" "rt")
  list(APPEND _opt "-Wno-multichar")
  # We require the task thread for our gui loop on Linux and to implement IPlugTimer
  list(APPEND _static_src
    ${cwd}/IPlugTaskThread.h
    ${cwd}/IPlugTaskThread.cpp
  )

elseif (IPLUG_OS MATCHES "Darwin")
  list(APPEND _static_src
    ${IPLUG_SRC}/IPlugPaths.mm)
  list(APPEND _inc
    ${WDL_DIR}/swell)
  # Macos frameworks for all formats.
  # This excludes Cocoa, Carbon, and QuartzCore since those are included in IGraphics linking
  list(APPEND _lib
    "-framework CoreFoundation"
    "-framework CoreData"
    "-framework Foundation"
    "-framework CoreServices")
  list(APPEND _opts
    "-Wno-deprecated-declarations"
    "-Wno-c++11-narrowing")
endif()

if (CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
  list(APPEND _def "_CRT_SECURE_NO_WARNINGS" "_CRT_SECURE_NO_DEPRECATE" "_CRT_NONSTDC_NO_DEPRECATE" "NOMINMAX" "_MBCS")
  list(APPEND _opt
    # Warning options
    "/wd4996" "/wd4250" "/wd4018" "/wd4267" "/wd4068"
    # Make sure MSVC uses static linking for compatibility with Skia libraries and easier distribution.
    ${IPLUG_MSVC_FLAGS}
  )
endif()

# Set certain compiler flags, specifically errors if there are undefined symbols
if (CMAKE_CXX_COMPILER_ID MATCHES "(Clang)|(GNU)" AND NOT IPLUG_OS MATCHES "Emscripten")
  list(APPEND _opt "-Wl,--no-undefined")
endif()

# Add all the things we've setup
iplug_target_add(iPlug2_Core INTERFACE
  DEFINE ${_def}
  INCLUDE ${_inc}
  SOURCE ${_src} ${_static_src}
  OPTION ${_opt}
  LINK ${_lib} iplug2_opt_simd
  FEATURE cxx_std_17
)

#------------------------------------------------

# This is specific to plugins, as opposed to APP, WAM, etc.
add_library(iPlug2_Plugin INTERFACE)
if (CMAKE_SYSTEM_NAME MATCHES "Windows")
  iplug_target_add(iPlug2_Plugin INTERFACE
    DEFINE
      _CRT_SECURE_NO_WARNINGS
      _CRT_SECURE_NO_DEPRECATE
      _CRT_NONSTDC_NO_DEPRECATE
  )
elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
  # macro for all plug-in builds
  iplug_target_add(iPlug2_Plugin INTERFACE
    DEFINE
      SWELL_CLEANUP_ON_UNLOAD
  )
endif()
if (IPLUG_LINKER_FLAG_ERROR_UNRESOLVED_SYMBOLS)
  # This way we get errors on GCC/clang for missing symbols
  target_link_options(iPlug2_Plugin INTERFACE "--error-unresolved-symbols")
endif()

# Load extras libraries
add_subdirectory(Extras)
