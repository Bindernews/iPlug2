cmake_minimum_required(VERSION 3.20)
include(ExternalProject)

set(cwd ${IPLUG2_SDK_PATH}/IPlug/CLAP)
set(deps_dir ${IPLUG2_SDK_PATH}/Dependencies/IPlug)
set(extern_install_dir ${CMAKE_BINARY_DIR}/IPlug)

add_subdirectory(${deps_dir}/CLAP_SDK ${extern_install_dir}/clap)
add_subdirectory(${deps_dir}/CLAP_HELPERS ${extern_install_dir}/clap_helpers)

# Make sure our targets loaded successfully
if (NOT TARGET clap OR NOT TARGET clap-helpers)
  set(IPlugCLAP_FOUND FALSE)
  return()
endif()

# Put the 'clap-tests' in a folder to keep the top level clean.
set_target_properties(clap-tests PROPERTIES FOLDER "Libraries")

# Find the install path for clap plugins based on OS.
# Generally we prefer user-writable values in index 0 for faster iteration.
# Source: https://github.com/free-audio/clap/blob/main/include/clap/entry.h
if (IPLUG_OS MATCHES "Windows")
  set(_user_install_path "$ENV{LOCALAPPDATA}/Programs/Common/CLAP")
  set(_system_install_path "$ENV{COMMONPROGRAMFILES}/CLAP")
elseif (IPLUG_OS MATCHES "Darwin")
  set(_user_install_path "$ENV{HOME}/Library/Audio/Plug-Ins/CLAP")
  set(_system_install_path "/Library/Audio/Plug-Ins/CLAP")
elseif (IPLUG_OS MATCHES "Linux")
  set(_user_install_path "$ENV{HOME}/.clap")
  set(_system_install_path "/usr/local/lib/clap") # Or /usr/lib/clap
endif()

iplug_set_install_paths(CLAP "${_user_install_path}" "${_system_install_path}")

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
  add_library(${target} MODULE)
  iplug_configure_helper(TARGET ${target} GET_VARS clap COPY_PROPERTIES)
  iplug_target_add(${target} PUBLIC LINK iPlug2_CLAP ${base_plugin} ${gui_libraries})
  set(install_dir "${IPLUG_CLAP_USER_INSTALL_PATH}/${plugin_name}")

  #--------------------------------------------------------
  # Windows
  if (IPLUG_OS MATCHES "Windows")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      SUFFIX ".clap"
    )

  #--------------------------------------------------------
  # MacOS
  elseif (IPLUG_OS MATCHES "Darwin")
    set(info_plist "${temporary_dir}/Info.plist")
    iplug_configure_basic_plist(${base_plugin} FORMAT clap OUTPUT "${info_plist}")

    set_target_properties(${target} PROPERTIES
      BUNDLE TRUE
      BUNDLE_EXTENSION clap
      MACOSX_BUNDLE_INFO_PLIST "${info_plist}"
    )

  #--------------------------------------------------------
  # Linux
  elseif (IPLUG_OS MATCHES "Linux")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      SUFFIX ".clap"
    )
  endif()

  # Handle resources
  iplug_target_bundle_resources(${target} "${resource_dir}")
  # Set the output directories to remove config sub-folders.
  bn_set_output_directory(${target} "${output_dir}")
  iplug_configure_helper(TARGET ${target} MAIN_RC POST_BUILD_COPY "${install_dir}")
endfunction()

set(IPlugCLAP_FOUND TRUE)