cmake_minimum_required(VERSION 3.20)

set(VST3_SDK "${IPLUG2_SDK_PATH}/Dependencies/IPlug/VST3_SDK" CACHE PATH "VST3 SDK directory.")
set(vst3_target_arch "")

if (NOT EXISTS ${VST3_SDK}/CMakeLists.txt)
  message(FATAL_ERROR "VST3_SDK not found or invalid")
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

if (IPLUG_OS MATCHES "Windows")
  set(_paths
    $ENV{LOCALAPPDATA}/Programs/Common/VST3
    $ENV{CommonProgramFiles}/VST3
  )
  if (CMAKE_SYSTEM_PROCESSOR MATCHES "X86")
    set(vst3_target_arch "x86-win")
  elseif (CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "(AMD64)|(IA64)")
    set(vst3_target_arch "x86_64-win")
  endif()

elseif (IPLUG_OS MATCHES "Darwin")
  set(_paths
    "$ENV{HOME}/Library/Audio/Plug-Ins/VST3"
    "/Library/Audio/Plug-Ins/VST3"
  )

elseif (IPLUG_OS MATCHES "Linux")
  set(_paths "$ENV{HOME}/.vst3")
  set(vst3_target_arch "${CMAKE_SYSTEM_PROCESSOR}-linux")
endif()

iplug_find_path(VST3_INSTALL_PATH REQUIRED DIR DEFAULT_IDX 0
  DOC "Path to install VST3 plugins"
  PATHS ${_paths})

set(IPLUG2_VST_ICON
  "${VST3_SDK}/doc/artwork/VST_Logo_Steinberg.ico"
  CACHE FILEPATH "Path to VST3 plugin icon")

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
  iplug_get_common_plugin_variables(vst3)

  # Create target
  add_library(${target} MODULE)
  # Link to iPlug library and GUI libraries
  target_link_libraries(${target} PUBLIC iPlug2_VST3 ${base_plugin} ${gui_libraries})
  # Copy properties
  iplug_copy_properties(${target} ${base_plugin} IPLUG_COPY_AFTER_BUILD IPLUG_RESOURCES)
  # Add the entry point
  smtg_target_add_library_main(${target})

  set(install_dir "${VST3_INSTALL_PATH}/${plugin_name}.vst3")
  set(res_dir "${output_dir}/Contents/Resources")

  if (IPLUG_OS MATCHES "Windows")
    set(dll_dir "${output_dir}/Contents/${vst3_target_arch}/")
    # Use .vst3 as the extension instead of .dll
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      LIBRARY_OUTPUT_DIRECTORY ${dll_dir}
      LIBRARY_OUTPUT_DIRECTORY_DEBUG ${dll_dir}
      LIBRARY_OUTPUT_DIRECTORY_RELEASE ${dll_dir}
      PREFIX ""
      SUFFIX ".vst3")

  elseif (IPLUG_OS MATCHES "Darwin")
    # Set the Info.plist file we're using and add resources
    set_target_properties(${target} PROPERTIES
      BUNDLE TRUE
      MACOSX_BUNDLE TRUE
      MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/resources/${PLUG_NAME}-VST3-Info.plist
      BUNDLE_EXTENSION "vst3"
      PREFIX ""
      SUFFIX "")

    if (CMAKE_GENERATOR STREQUAL "Xcode")
      set(output_dir "${CMAKE_BINARY_DIR}/$<CONFIG>/${plugin_name}.vst3")
      set(res_dir "")
    endif()

  elseif (IPLUG_OS MATCHES "Linux")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${IPLUG_APP_NAME}"
      LIBRARY_OUTPUT_DIRECTORY "${output_dir}/Contents/${vst3_target_arch}/"
      PREFIX ""
      SUFFIX ".so")

  endif()

  if (res_dir)
    iplug_target_bundle_resources(${target} "${res_dir}")
  endif()

  iplug_add_post_build_copy(${target} "${output_dir}" "${install_dir}")
endfunction()
