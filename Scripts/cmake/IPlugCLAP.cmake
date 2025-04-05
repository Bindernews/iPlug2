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
  set(install_paths
    $ENV{LOCALAPPDATA}/Programs/Common/CLAP
    $ENV{COMMONPROGRAMFILES}/CLAP
    $ENV{CLAP_PATH}
  )
elseif (IPLUG_OS MATCHES "Darwin")
  set(install_paths
    $ENV{HOME}/Library/Audio/Plug-Ins/CLAP
    /Library/Audio/Plug-Ins/CLAP
    $ENV{CLAP_PATH}
  )
elseif (IPLUG_OS MATCHES "Linux")
  set(install_paths
    ~/.clap
    /usr/local/lib/clap
    /usr/lib/clap
    $ENV{CLAP_PATH}
  )
endif()

iplug_find_path(
  CLAP_INSTALL_PATH
  DIR DEFAULT_IDX 0
  DOC "Path to install CLAP plugins"
  PATHS ${install_paths}
)

set(_src
  ${cwd}/IPlugCLAP.h
  ${cwd}/IPlugCLAP.cpp
)

# Core LV2 interface library.
add_library(iPlug2_CLAP INTERFACE)
iplug_target_add(iPlug2_CLAP INTERFACE
  DEFINE
  "CLAP_API"
  "BUILT_WITH_CMAKE"
  # "SAMPLE_TYPE_FLOAT=1"

  SOURCE ${_src}

  INCLUDE ${cwd}

  LINK
  clap
  clap-helpers
)

source_group(IPlug/CLAP FILES ${_src})

#--------------------------------------------------------------------
# configure function
function(iplug_configure_clap base_plugin target)
  add_library(${target} MODULE)
  iplug_configure_helper(GET_VARS clap COPY_PROPERTIES ${target})
  iplug_target_add(${target} PUBLIC LINK iPlug2_CLAP ${base_plugin} ${gui_libraries})
  set(install_dir "${CLAP_INSTALL_PATH}/${plugin_name}")

  if (IPLUG_OS MATCHES "Windows")
    set(suffix ".dll")
  elseif (IPLUG_OS MATCHES "Darwin")
    set(suffix ".dylib")
  elseif (IPLUG_OS MATCHES "Linux")
    set(suffix ".so")
  endif()

  # Set dependencies for our target
  set_target_properties(${target} PROPERTIES
    OUTPUT_NAME "${plugin_name}"
    LIBRARY_OUTPUT_DIRECTORY "${output_dir}"
    PREFIX ""
    SUFFIX ".clap"
  )

  # Handle resources
  iplug_target_bundle_resources(${base_plugin} "${resource_dir}")
  # After building copy to the correct directory
  iplug_add_post_build_copy(${target} "${output_dir}" "${install_dir}")
endfunction()

set(IPlugCLAP_FOUND TRUE)