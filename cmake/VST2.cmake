cmake_minimum_required(VERSION 3.11)

# Determine VST2 and VST3 directories
if (WIN32)
  set(fn "VstPlugins")
  if (PROCESSOR_ARCH STREQUAL "Win32")
    set(_paths "$ENV{ProgramFiles(x86)}/${fn}" "$ENV{ProgramFiles(x86)}/Steinberg/${fn}")
  endif()
  # Append this for x86, x64, and ARM I guess
  list(APPEND _paths "$ENV{ProgramFiles}/${fn}" "$ENV{ProgramFiles}/Steinberg/${fn}")
elseif (OS_MAC)
  set(fn "VST")
  set(_paths "$ENV{HOME}/Library/Audio/Plug-Ins/${fn}" "/Library/Audio/Plug-Ins/${fn}")
elseif (OS_LINUX)
  set(_paths "$ENV{HOME}/.vst" "/usr/local/lib/vst" "/usr/local/vst")
endif()

iplug2_find_path(VST2_INSTALL_PATH REQUIRED DIR DEFAULT_IDX 0 
  DOC "Path to install VST2 plugins"
  PATHS ${_paths})

set(sdk ${IPLUG2_DIR}/IPlug/VST2)
add_library(iPlug2_VST2 INTERFACE)
iplug2_target_add(iPlug2_VST2 INTERFACE
  INCLUDE ${sdk} ${IPLUG_DEPS}/VST2_SDK
  SOURCE ${sdk}/IPlugVST2.cpp
  DEFINE "VST2_API" "VST_FORCE_DEPRECATED" "IPLUG_DSP=1"
  LINK iPlug2_Core
)
if (OS_LINUX)
  iplug2_target_add(iPlug2_VST2 INTERFACE
    DEFINE "SMTG_OS_LINUX"
  )
  # CMake doesn't like __cdecl, so instead of having people modify their aeffect.h
  # file, just redefine __cdecl.
  if ("${CMAKE_C_COMPILER_ID}" STREQUAL "GNU")
    iplug2_target_add(iPlug2_VST2 INTERFACE DEFINE "__cdecl=__attribute__((__cdecl__))")
  endif()
endif()

function(iplug2_configure_vst2 target)
  if (WIN32)
    set(out_dir "${CMAKE_BINARY_DIR}/${target}")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${IPLUG_APP_NAME}"
      LIBRARY_OUTPUT_DIRECTORY "${out_dir}"
      PREFIX ""
      SUFFIX ".dll"
    )
    set(res_dir "${CMAKE_BINARY_DIR}/${target}/resources")

    # After building, we run the post-build script
    add_custom_command(TARGET ${target} POST_BUILD 
      COMMAND "${CMAKE_BINARY_DIR}/postbuild-win.bat" 
      ARGS "\"$<TARGET_FILE:${target}>\"" "\".dll\""
    )
    
  elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
    # TODO Add MacOS build

    set(res_dir "")

  elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
    set(out_dir "${CMAKE_BINARY_DIR}/${target}")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${IPLUG_APP_NAME}"
      LIBRARY_OUTPUT_DIRECTORY "${out_dir}"
      PREFIX ""
      SUFFIX ".so"
    )
    set(res_dir "${CMAKE_BINARY_DIR}/${target}/resources")

    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} ARGS "-E" "copy_directory" "${out_dir}" "${VST2_INSTALL_PATH}/${PLUG_NAME}")
  endif()

  # Handle resources
  if (res_dir)
    iplug2_target_bundle_resources(${target} "${res_dir}")
  endif()

endfunction()