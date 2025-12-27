cmake_minimum_required(VERSION 3.20)

# Set the cache value. Does nothing if cache value is already set or given on CLI.
set(VST2_SDK "${IPLUG2_SDK_PATH}/Dependencies/IPlug/VST2_SDK" CACHE PATH "VST2 SDK directory.")

# Check to make sure we have at least one of the files we need.
if (NOT EXISTS "${VST2_SDK}/aeffectx.h")
  set(IPlugVST2_FOUND FALSE CACHE INTERNAL "")
  set(IPlugVST2_ERROR "VST2 SDK not found or missing files")
  return()
endif()

set(_suffix "")
bn_case(_suffix "${CMAKE_SYSTEM_NAME}"
  "Windows" ".dll"
  "Darwin"  ".vst"
  "Linux"   ".so"
)

iplug_format_helper(
  SETUP
  FORMAT vst2
  # Determine VST2 directories
  USER_INSTALL_PATH
    # For Windows, install locally to the VST3 directory, since most hosts will find it there as well
    "Windows" "$ENV{LOCALAPPDATA}/Programs/Common/VST3"
    "Darwin"  "$ENV{HOME}/Library/Audio/Plug-Ins/VST"
    "Linux"   "$ENV{HOME}/.vst"
  SYSTEM_INSTALL_PATH
    # Technically we should use $ENV{ProgramFiles\(x86\)} for Win32 on Win64, but since Win32
    # is deprecated as of Windows 11, and it's much more work, just ignore that issue.
    "Windows" "$ENV{ProgramFiles}/Steinberg/VstPlugins"
    "Darwin"  "/Library/Audio/Plug-Ins/VST"
    "Linux"   "/usr/local/lib/vst"
  SUFFIX "${_suffix}"
  CUSTOM_XML ""
)

set(cwd ${IPLUG2_SDK_PATH}/IPlug/VST2)

add_library(iPlug2_VST2 INTERFACE)
iplug_target_add(iPlug2_VST2 INTERFACE
  SOURCE
  ${cwd}/IPlugVST2.h
  ${cwd}/IPlugVST2.cpp

  INCLUDE
  ${cwd}
  ${VST2_SDK}

  DEFINE
  "VST2_API"
  "VST_FORCE_DEPRECATED"
  "IPLUG_DSP=1"

  LINK
  iPlug2_Core
)
if(IPLUG_OS STREQUAL "Linux")
  # Linux needs this define
  bn_target_add(iPlug2_VST2 INTERFACE DEFINE "SMTG_OS_LINUX")
endif()
if(${CMAKE_CXX_COMPILER_ID} MATCHES "GNU")
  # GCC doesn't like __cdecl, so instead of having people modify their
  # aeffect.h file, just redefine __cdecl.
  bn_target_add(iPlug2_VST2 INTERFACE DEFINE "__cdecl=__attribute__(())")
endif()

#--------------------------------------------------------------------
# configure function
function(iplug_configure_vst2 base_plugin target)
  iplug_format_helper(FORMAT vst2 GET_VARS)
  # Create module and link it to dependencies
  add_library(${target} MODULE)
  iplug_format_helper(FORMAT vst2 TARGET ${target} TARGET_COMMON)
  iplug_target_add(
    ${target} PUBLIC
    LINK iPlug2_VST2 ${base_plugin} ${gui_libraries}
  )
  # Handle resources
  iplug_target_bundle_resources(${target} "${res_dir}" PREFER_EMBED)
  bn_set_output_directory(${target} "${output_dir}")
endfunction()

set(IPlugVST2_FOUND TRUE)