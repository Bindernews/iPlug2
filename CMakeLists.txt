cmake_minimum_required(VERSION 3.24)
# Convert relative source paths to absolute
cmake_policy(SET CMP0076 NEW)
# Enable setting MSVC runtime flags with CMAKE_MSVC_RUNTIME_LIBRARY
cmake_policy(SET CMP0091 NEW)

project(
  iPlug2
  DESCRIPTION "A C++ framework for developing cross-platform audio plugins."
  LANGUAGES C CXX)

if (APPLE)
  enable_language(OBJC)
  enable_language(OBJCXX)
endif()

# This is used in many places
set(IPLUG2_SDK_PATH ${CMAKE_CURRENT_LIST_DIR} CACHE PATH "Path to the iPlug2 SDK")

# Make sure MSVC uses static linking for compatibility with Skia libraries and easier distribution.
# Note that settings CMAKE_MSVC_RUNTIME_LIBRARY doesn't seem to work consistently, so we set the flags directly.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>" CACHE STRING "")
set(IPLUG_MSVC_FLAGS "")
if (MSVC)
  set(IPLUG_MSVC_FLAGS "/MT$<$<CONFIG:Debug>:d>")
endif()
set(IPLUG_MSVC_FLAGS "${IPLUG_MSVC_FLAGS}" CACHE STRING "")

# We generate folders for targets that support it (Visual Studio, Xcode, etc.)
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

add_subdirectory(WDL/lice)
add_subdirectory(WDL/swell)
add_subdirectory(IPlug)
add_subdirectory(IGraphics)

#================================================
# Determine supported formats

# List of all known plugin formats.
set(IPLUG_ALL_FORMATS "aax;app;au2;au3;lv2;vst2;vst3;wam;clap")
set_property(GLOBAL PROPERTY IPLUG_ALL_FORMATS ${IPLUG_ALL_FORMATS})

# Module name to load for each format in IPLUG_ALL_FORMATS.
# The index must match the index in IPLUG_ALL_FORMATS.
set(IPLUG_FORMAT_MOD_NAMES "AAX;APP;AUv2;AUv3;LV2;VST2;VST3;WEB;CLAP")
set_property(GLOBAL PROPERTY IPLUG_FORMAT_MOD_NAMES ${IPLUG_FORMAT_MOD_NAMES})

# Only determine valid formats if we haven't already run CMake for this.
if (NOT CACHE{IPLUG_VALID_FORMATS})

  # Get a list of all valid formats for the current compiler toolchain / platform
  # by copying the list of valid formats, then removing any invalid ones.
  set(ok_formats ${IPLUG_ALL_FORMATS})

  if (NOT IPLUG_OS MATCHES "(Darwin)|(iOS)")
    list(REMOVE_ITEM ok_formats "au2" "au3")
  endif()
  # AAX is windows and mac only
  if (NOT IPLUG_OS MATCHES "(Darwin)|(Windows)")
    list(REMOVE_ITEM ok_formats "aax")
  endif()
  # Currently only support LV2 on Linux and Windows, through it's technically cross-platform
  if (NOT IPLUG_OS MATCHES "(Linux)|(Windows)")
    list(REMOVE_ITEM ok_formats "lv2")
  endif()
  # On emscripten, currently we only support WebAudioModules, though we'd like to support
  # CLAP for web in the future.
  if (CMAKE_SYSTEM_NAME MATCHES "Emscripten")
    # Straight up override the valid formats
    set(ok_formats wam)
  else()
    list(REMOVE_ITEM ok_formats "wam")
  endif()

  # Save this as a cache variable
  set(IPLUG_VALID_FORMATS "${ok_formats}" CACHE INTERNAL "List of valid output formats for iPlug2")

endif()

#================================================
# Load format modules

# List of successfully loaded formats, will be set as cache variable later
set(IPLUG_LOADED_FORMATS "")

foreach (format format_subdir IN ZIP_LISTS IPLUG_ALL_FORMATS IPLUG_FORMAT_MOD_NAMES)
  # Skip invalid formats
  if(NOT format IN_LIST IPLUG_VALID_FORMATS)
    continue()
  endif()

  # Dynamically load the plugin format, and the associated configure command.
  # If include() fails, that's a hard-error.
  set(module_name IPlug${format_subdir})
  include(${module_name})

  # Just because it included, doesn't mean we succeeded though.
  # If we succeeded, but ${module_name}_FOUND is not set, then we still failed, like find_package.
  if(${module_name}_FOUND)
    list(APPEND IPLUG_LOADED_FORMATS ${format})
  else()
    # Allow modules to add an extra error message
    bn_tern(extra_error "${${module_name}_ERROR}" "error" DEFINED ${module_name}_ERROR)
    message(NOTICE "Failed to load plugin format ${format_subdir}:` ${extra_error}")
  endif()
endforeach()

# Set as cache variable for global scope
set(IPLUG_LOADED_FORMATS "${IPLUG_LOADED_FORMATS}" CACHE INTERNAL "" FORCE)
