cmake_minimum_required(VERSION 3.20)

set(VST3_SDK "${IPLUG2_SDK_PATH}/Dependencies/IPlug/VST3_SDK" CACHE PATH "VST3 SDK directory.")
set(vst3_target_arch "")

if (NOT EXISTS ${VST3_SDK}/CMakeLists.txt)
  set(IPlugVST3_FOUND FALSE)
  set(IPlugVST3_ERROR "VST3_SDK not found or missing files")
  return()
endif()

#
set(IPLUG_VST3_ICON "${VST3_SDK}/doc/artwork/VST_Logo_Steinberg.ico"
  CACHE FILEPATH "Path to VST3 plugin icon")

# Disable VST3 extras that we're not using
set(SMTG_ENABLE_VST3_PLUGIN_EXAMPLES OFF CACHE BOOL "")
set(SMTG_ENABLE_VST3_HOSTING_EXAMPLES OFF CACHE BOOL "")
set(SMTG_ENABLE_VSTGUI_SUPPORT OFF CACHE BOOL "")
set(SMTG_USE_STATIC_CRT ON CACHE BOOL "")

# Add vst3 sdk as subdirectory
add_subdirectory(${VST3_SDK} ${CMAKE_CURRENT_BINARY_DIR}/VST3_SDK)
# Required
smtg_enable_vst3_sdk()

add_library(iplug2_smtg_defines INTERFACE)
target_compile_definitions(iplug2_smtg_defines INTERFACE $<IF:$<CONFIG:Debug>,DEVELOPMENT,RELEASE>)

# Set the MSVC static vs dll stdandard library mode for the VST3 sdk.
# This MUST be consistent for all libraries that link together.
set(vst3_targets sdk sdk_common sdk_hosting pluginterfaces base moduleinfotool validator)
set_property(TARGET ${vst3_targets} APPEND PROPERTY COMPILE_OPTIONS ${IPLUG_MSVC_FLAGS})
set_property(TARGET ${vst3_targets} APPEND PROPERTY LINK_LIBRARIES iplug2_smtg_defines)
# set_property(TARGET ${vst3_targets} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Reference: https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical+Documentation/Locations+Format/Plugin+Locations.html
iplug_format_helper(
  SETUP
  FORMAT vst3
  # Determine VST2 directories
  USER_INSTALL_PATH
    # For Windows, install locally to the VST3 directory, since most hosts will find it there as well
    "Windows" "$ENV{LOCALAPPDATA}/Programs/Common/VST3"
    "Darwin"  "$ENV{HOME}/Library/Audio/Plug-Ins/VST3"
    "Linux"   "$ENV{HOME}/.vst3"
  SYSTEM_INSTALL_PATH
    # Tehcnically we should install to "$ENV{CommonProgramFiles\(x86\)}/VST3"
    # if the host is x64 but the plugin is x32. For now, this is good enough.
    "Windows" "$ENV{CommonProgramFiles}/VST3"
    "Darwin"  "/Library/Audio/Plug-Ins/VST3"
    "Linux"   "/usr/local/lib/vst3"
  SUFFIX ".vst3"
  CUSTOM_XML ""
)

# Determine the VST3 target architecture
if(IPLUG_OS MATCHES "Windows")
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "X86")
    set(tmp "x86-win")
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "(AMD64)|(IA64)")
    set(tmp "x86_64-win")
  endif()
elseif(IPLUG_OS MATCHES "Darwin")
  set(tmp "MacOS")
elseif(IPLUG_OS MATCHES "Linux")
  set(tmp "${CMAKE_SYSTEM_PROCESSOR}-linux")
else()
  set(tmp "${CMAKE_SYSTEM_PROCESSOR}-unknown")
endif()
set(IPLUG_VST3_TARGET_ARCH "${tmp}" CACHE INTERNAL "")


##########################
# VST3 Interface Library #
##########################


set(sdk ${IPLUG2_SDK_PATH}/IPlug/VST3)
set(common_source
  "${sdk}/IPlugVST3.h"
  "${sdk}/IPlugVST3.cpp"
  "${sdk}/IPlugVST3_Common.h"
  "${sdk}/IPlugVST3_Defs.h"
  "${sdk}/IPlugVST3_Parameter.h"
  # Required "extras" from the VST3 sdk
  ${VST3_SDK}/public.sdk/source/vst/vstsinglecomponenteffect.cpp
  ${VST3_SDK}/public.sdk/source/vst/vstsinglecomponenteffect.h
)
set(ui_source
  "${sdk}/IPlugVST3_Controller.h"
  "${sdk}/IPlugVST3_Controller.cpp"
  "${sdk}/IPlugVST3_ControllerBase.h"
  "${sdk}/IPlugVST3_View.h"
)
set(dsp_source
  "${sdk}/IPlugVST3_Processor.h"
  #"${sdk}/IPlugVST3_Processor.cpp"
  "${sdk}/IPlugVST3_ProcessorBase.h"
  "${sdk}/IPlugVST3_ProcessorBase.cpp"
)
if(IPLUG_OS MATCHES "Linux")
  list(APPEND common_source ${sdk}/IPlugVST3_RunLoop.cpp)
endif()

set(_src ${common_source} ${ui_source} ${dsp_source})

add_library(iPlug2_VST3_Common INTERFACE)
iplug_target_add(
  iPlug2_VST3_Common INTERFACE
  INCLUDE ${sdk}
  DEFINE
    VST3_API
    # This define sets additional flags in VST3
    $<IF:$<CONFIG:Debug>,DEVELOPMENT,RELEASE>
  LINK
    iPlug2_Core
    # sdk is the vst3 SDK
    sdk
)

add_library(iPlug2_VST3 INTERFACE)
iplug_target_add(
  iPlug2_VST3 INTERFACE
  SOURCE ${_src}
  DEFINE IPLUG_DSP=1
  LINK   iPlug2_VST3_Common
)

add_library(iPlug2_VST3_UI INTERFACE)
bn_target_add(
  iPlug2_VST3_UI INTERFACE
  SOURCE ${ui_source}
  DEFINE VST3C_API IPLUG_EDITOR=1
  LINK   iPlug2_VST3_Common
)

add_library(iPlug2_VST3_DSP INTERFACE)
bn_target_add(
  iPlug2_VST3_DSP INTERFACE
  SOURCE ${dsp_source}
  DEFINE VST3P_API IPLUG_DSP=1
  LINK   iPlug2_VST3_Common
)

function(iplug_configure_vst3 base_plugin target)

  # Grab some variables and copy props
  iplug_format_helper(FORMAT vst3 GET_VARS)
  # vst3 outputs are formatted like MacOS bundles on all platforms
  set(resource_dir "${output_dir}/Contents/Resources")

  # Create target
  add_library(${target} MODULE)
  iplug_format_helper(FORMAT vst3 TARGET ${target} TARGET_COMMON)
  # Link to iPlug library and GUI libraries
  target_link_libraries(${target} PUBLIC iPlug2_VST3 ${base_plugin} ${gui_libraries} iPlug2_Plugin)

  # Add the entry point
  set(public_sdk_SOURCE_DIR ${smtg_public_sdk_SOURCE_DIR})
  smtg_target_add_library_main(${target})

  # Bundle resources
  iplug_target_bundle_resources(${target} "${resource_dir}")
  bn_set_output_directory(${target} "${output_dir}/Contents/${IPLUG_VST3_TARGET_ARCH}")
endfunction()

set(IPlugVST3_FOUND TRUE)

