cmake_minimum_required(VERSION 3.20)
include(ExternalProject)

set(cwd ${IPLUG2_SDK_PATH}/IPlug/CLAP)
set(deps_dir ${IPLUG2_SDK_PATH}/Dependencies/IPlug)
set(extern_install_dir ${CMAKE_BINARY_DIR}/iplug)

add_subdirectory(${deps_dir}/CLAP_SDK ${extern_install_dir}/clap)
add_subdirectory(${deps_dir}/CLAP_HELPERS ${extern_install_dir}/clap_helpers)

# Make sure our targets loaded successfully
if (NOT TARGET clap OR NOT TARGET clap-helpers)
  set(IPlugCLAP_FOUND FALSE)
  return()
endif()

# Put the 'clap-tests' in a folder to keep the top level clean.
set_target_properties(clap-tests PROPERTIES FOLDER "Libraries")

iplug_format_helper(
  SETUP
  FORMAT clap
  # Find the install path for clap plugins based on OS.
  # Source: https://github.com/free-audio/clap/blob/main/include/clap/entry.h
  USER_INSTALL_PATH
    "Windows" "$ENV{LOCALAPPDATA}/Programs/Common/CLAP"
    "Darwin"  "$ENV{HOME}/Library/Audio/Plug-Ins/CLAP"
    "Linux"   "$ENV{HOME}/.clap"
  SYSTEM_INSTALL_PATH
    "Windows" "$ENV{COMMONPROGRAMFILES}/CLAP"
    "Darwin"  "/Library/Audio/Plug-Ins/CLAP"
    "Linux"   "/usr/local/lib/clap" # Or /usr/lib/clap
  SUFFIX
    "Windows" ".clap"
    "Darwin"  ".clap"
    "Linux"   ".clap"
  CUSTOM_XML ""
  INSTALL_SUBDIR "\${plugin_name}"
)

# Core LV2 interface library.
add_library(iPlug2_CLAP INTERFACE)
bn_target_add(iPlug2_CLAP INTERFACE
  DEFINE
  "CLAP_API"
  "BUILT_WITH_CMAKE"
  "IPLUG_DSP=1"
  # "SAMPLE_TYPE_FLOAT=1"

  SOURCE
  ${cwd}/IPlugCLAP.h
  ${cwd}/IPlugCLAP.cpp

  INCLUDE ${cwd}

  LINK
  clap
  clap-helpers
)

#--------------------------------------------------------------------
# configure function
function(iplug_configure_clap base_plugin target)
  iplug_format_helper(FORMAT clap GET_VARS)

  add_library(${target} MODULE)
  iplug_target_add(
    ${target} PUBLIC
    LINK iPlug2_CLAP ${base_plugin} ${gui_libraries}
  )
  iplug_format_helper(
    FORMAT clap TARGET ${target}
    COPY_PROPERTIES GENERATE_PLIST MAKE_BUNDLE SET_NAME MAIN_RC
    # After building copy to the correct directory
    POST_BUILD_COPY
  )
  # Handle resources
  iplug_target_bundle_resources(${target} "${resource_dir}")
  # Set the output directories to remove config sub-folders.
  bn_set_output_directory(${target} "${output_dir}")
endfunction()

set(IPlugCLAP_FOUND TRUE)