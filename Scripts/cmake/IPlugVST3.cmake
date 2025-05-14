cmake_minimum_required(VERSION 3.20)
include(FindPackageHandleStandardArgs)

set(VST3_SDK "${IPLUG2_SDK_PATH}/Dependencies/IPlug/VST3_SDK" CACHE PATH "VST3 SDK directory.")
set(vst3_target_arch "")

if (NOT EXISTS ${VST3_SDK}/CMakeLists.txt)
  set(IPlugVST3_FOUND FALSE)
  message(WARNING "VST3_SDK not found or invalid")
  return()
endif()

# Disable VST3 extras that we're not using
set(SMTG_ENABLE_VST3_PLUGIN_EXAMPLES OFF CACHE BOOL "")
set(SMTG_ENABLE_VST3_HOSTING_EXAMPLES OFF CACHE BOOL "")
set(SMTG_ENABLE_VSTGUI_SUPPORT OFF CACHE BOOL "")

# Add vst3 sdk as subdirectory
add_subdirectory(${VST3_SDK} ${CMAKE_CURRENT_BINARY_DIR}/VST3_SDK)
# Required
smtg_enable_vst3_sdk()

# Set the MSVC static vs dll stdandard library mode for the VST3 sdk.
# This MUST be consistent for all libraries that link together.
target_compile_options(sdk PUBLIC ${IPLUG_MSVC_FLAGS})
target_compile_options(sdk_common PUBLIC ${IPLUG_MSVC_FLAGS})
target_compile_options(pluginterfaces PUBLIC ${IPLUG_MSVC_FLAGS})
target_compile_options(base PUBLIC ${IPLUG_MSVC_FLAGS})

# Reference: https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical+Documentation/Locations+Format/Plugin+Locations.html
if (IPLUG_OS MATCHES "Windows")
  set(_user_install_path "$ENV{LOCALAPPDATA}/Programs/Common/VST3")
  set(_system_install_path $ENV{CommonProgramFiles}/VST3)
  # Tehcnically we should install to "$ENV{CommonProgramFiles\(x86\)}/VST3"
  # of the host is x64 but the plugin is x32. For now, this is good enough.
  if (CMAKE_SYSTEM_PROCESSOR MATCHES "X86")
    set(vst3_target_arch "x86-win")
  elseif (CMAKE_SYSTEM_PROCESSOR MATCHES "(AMD64)|(IA64)")
    set(vst3_target_arch "x86_64-win")
  endif()
elseif (IPLUG_OS MATCHES "Darwin")
  set(_user_install_path "$ENV{HOME}/Library/Audio/Plug-Ins/VST3")
  set(_system_install_path "/Library/Audio/Plug-Ins/VST3")
  set(vst3_target_arch "MacOS")
elseif (IPLUG_OS MATCHES "Linux")
  set(_user_install_path "$ENV{HOME}/.vst3")
  set(_system_install_path "/usr/local/lib/vst3")
  set(vst3_target_arch "${CMAKE_SYSTEM_PROCESSOR}-linux")
endif()

iplug_set_install_paths(VST3 "${_user_install_path}" "${_system_install_path}")
set(IPLUG_VST3_TARGET_ARCH "${vst3_target_arch}" CACHE INTERNAL "")

set(IPLUG_VST3_ICON "${VST3_SDK}/doc/artwork/VST_Logo_Steinberg.ico" CACHE FILEPATH
  "Path to VST3 plugin icon")

##########################
# VST3 Interface Library #
##########################

add_library(iPlug2_VST3 INTERFACE)
set(sdk ${IPLUG2_SDK_PATH}/IPlug/VST3)
set(_src
  "${sdk}/IPlugVST3.h"
  "${sdk}/IPlugVST3.cpp"
  "${sdk}/IPlugVST3_Common.h"
  "${sdk}/IPlugVST3_Controller.h"
  "${sdk}/IPlugVST3_Controller.cpp"
  "${sdk}/IPlugVST3_ControllerBase.h"
  "${sdk}/IPlugVST3_Defs.h"
  "${sdk}/IPlugVST3_Parameter.h"
  "${sdk}/IPlugVST3_Processor.h"
  #"${sdk}/IPlugVST3_Processor.cpp"
  "${sdk}/IPlugVST3_ProcessorBase.h"
  "${sdk}/IPlugVST3_ProcessorBase.cpp"
  "${sdk}/IPlugVST3_View.h"
)
# Required "extras" from the VST3 sdk
list(APPEND _src
  ${VST3_SDK}/public.sdk/source/vst/vstsinglecomponenteffect.cpp
  ${VST3_SDK}/public.sdk/source/vst/vstsinglecomponenteffect.h
)

if (IPLUG_OS MATCHES "Linux")
  list(APPEND _src ${sdk}/IPlugVST3_RunLoop.cpp)
endif()

iplug_target_add(iPlug2_VST3 INTERFACE
  SOURCE
    ${_src}

  INCLUDE
    ${sdk}

  DEFINE
    VST3_API
    IPLUG_DSP=1
    # This define sets additional flags in VST3
    $<IF:$<CONFIG:Debug>,DEVELOPMENT,RELEASE>
    # Need this on MacOS
    $<$<PLATFORM_ID:Darwin>:"SWELL_CLEANUP_ON_UNLOAD">

  LINK
    iPlug2_Core
    # sdk is the vst3 SDK
    sdk
)

source_group(IPlug/VST3 FILES ${_src})

function(iplug_configure_vst3 base_plugin target)
  # Create target
  add_library(${target} MODULE)
  # Grab some variables and copy props
  iplug_configure_helper(TARGET ${target} GET_VARS vst3 COPY_PROPERTIES)
  # Link to iPlug library and GUI libraries
  target_link_libraries(${target} PUBLIC iPlug2_VST3 ${base_plugin} ${gui_libraries})

  # Add the entry point
  set(public_sdk_SOURCE_DIR ${smtg_public_sdk_SOURCE_DIR})
  smtg_target_add_library_main(${target})

  if (IPLUG_VST3_USER_INSTALL_PATH)
    set(install_dir "${IPLUG_VST3_USER_INSTALL_PATH}/${plugin_name}.vst3")
  else()
    set(install_dir "")
  endif()
  set(res_dir "${output_dir}/Contents/Resources")

  if (IPLUG_OS MATCHES "Windows")
    # Use .vst3 as the extension instead of .dll
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      PREFIX ""
      SUFFIX ".vst3")

  elseif (IPLUG_OS MATCHES "Darwin")
    # Configure the .plist file
    set(info_plist "${binary_subdir}/Info.plist")
    iplug_configure_basic_plist(${base_plugin} FORMAT vst3 OUTPUT "${info_plist}")

    # Set bundle settings
    set_target_properties(${target} PROPERTIES
      BUNDLE TRUE
      MACOSX_BUNDLE TRUE
      MACOSX_BUNDLE_INFO_PLIST "${info_plist}"
      BUNDLE_EXTENSION "vst3"
      PREFIX ""
      SUFFIX "")

  elseif (IPLUG_OS MATCHES "Linux")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${IPLUG_APP_NAME}"
      PREFIX ""
      SUFFIX ".so")

  endif()

  iplug_target_bundle_resources(${target} "${res_dir}")
  bn_set_output_directory(${target} "${output_dir}/Contents/${IPLUG_VST3_TARGET_ARCH}")
  iplug_configure_helper(TARGET ${target} MAIN_RC POST_BUILD_COPY "${install_dir}")
endfunction()

set(IPlugVST3_FOUND TRUE)

