cmake_minimum_required(VERSION 3.11)

if (NOT VST2_SDK)
  set(VST2_SDK "${IPLUG2_SDK_PATH}/Dependencies/IPlug/VST2_SDK" CACHE PATH "VST2 SDK directory.")
endif()

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

iplug_find_path(VST2_INSTALL_PATH REQUIRED DIR DEFAULT_IDX 0 
  DOC "Path to install VST2 plugins"
  PATHS ${_paths})

set(sdk ${IPLUG2_SDK_PATH}/IPlug/VST2)
add_library(iPlug2_VST2 INTERFACE)
iplug_target_add(iPlug2_VST2 INTERFACE
  INCLUDE ${sdk} ${VST2_SDK}
  SOURCE ${sdk}/IPlugVST2.cpp
  DEFINE "VST2_API" "VST_FORCE_DEPRECATED" "IPLUG_DSP=1"
  LINK iPlug2_Core
)
if (OS_LINUX)
  iplug_target_add(iPlug2_VST2 INTERFACE
    DEFINE "SMTG_OS_LINUX"
  )
  # CMake doesn't like __cdecl, so instead of having people modify their aeffect.h file,
  # just redefine __cdecl.
  if ("${CMAKE_C_COMPILER_ID}" STREQUAL "GNU")
    iplug_target_add(iPlug2_VST2 INTERFACE DEFINE "__cdecl=__attribute__((__cdecl__))")
  endif()
endif()

list(APPEND IPLUG2_TARGETS iPlug2_VST2)

function(iplug_configure_vst2 target)
  get_target_property(plugin_name ${target} IPLUG_PLUGIN_NAME)
  set(out_dir "${CMAKE_BINARY_DIR}/${target}")
  set(res_dir "${out_dir}/resources")
  
  iplug_target_add(${target} PUBLIC LINK iPlug2_VST2)

  if (WIN32)
    set(install_dir "${VST2_INSTALL_PATH}/${plugin_name}")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      LIBRARY_OUTPUT_DIRECTORY "${out_dir}"
      PREFIX ""
      SUFFIX ".dll"
    )

  elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
    set_target_properties(${target} PROPERTIES
      BUNDLE TRUE
      MACOSX_BUNDLE TRUE
      MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/resources/${plugin_name}-VST2-Info.plist"
      BUNDLE_EXTENSION "vst"
      PREFIX ""
      SUFFIX "")

    if (CMAKE_GENERATOR STREQUAL "Xcode")
      set(out_dir "${CMAKE_BINARY_DIR}/$<CONFIG>/${plugin_name}.vst")
      set(res_dir "")
    endif()

  elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
    set(install_dir "${VST2_INSTALL_PATH}/${plugin_name}.vst2")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      LIBRARY_OUTPUT_DIRECTORY "${out_dir}"
      PREFIX ""
      SUFFIX ".so"
    )
  endif()

  # Handle resources
  if (res_dir)
    iplug_target_bundle_resources(${target} "${res_dir}")
  endif()

  iplug_add_post_build_copy(${target} "${out_dir}" "${install_dir}")
endfunction()
