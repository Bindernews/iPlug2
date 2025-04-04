cmake_minimum_required(VERSION 3.20)

function(_iplug_load_module_clap)
  include(ExternalProject)

  set(cwd ${IPLUG2_SDK_PATH}/IPlug/CLAP)
  set(deps_dir ${IPLUG2_SDK_PATH}/Dependencies/IPlug)
  set(extern_install_dir ${CMAKE_BINARY_DIR}/IPlug)

  add_subdirectory(${deps_dir}/CLAP_SDK ${extern_install_dir}/clap)
  add_subdirectory(${deps_dir}/CLAP_HELPERS ${extern_install_dir}/clap_helpers)

  # Load clap and clap-helper as external projects.
  # We set their install directories so they build separately from
  # our internal clap stuff.
  # ExternalProject_Add(
  #   clap
  #   SOURCE_DIR ${deps_dir}/CLAP_SDK
  #   INSTALL_DIR ${extern_install_dir}
  #   # This is required, since INSTALL_DIR just sets a placeholder
  #   CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${extern_install_dir}
  # )
  # ExternalProject_Add(
  #   clap_helpers
  #   SOURCE_DIR ${deps_dir}/CLAP_HELPERS
  #   INSTALL_DIR ${extern_install_dir}
  #   CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${extern_install_dir}
  # )


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
    CLAP_INSTALL_PATH DIR
    DEFAULT_IDX 0
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

endfunction(_iplug_load_module_clap)
_iplug_load_module_clap()

function(iplug_configure_clap base_plugin target)
  iplug_get_common_plugin_variables(clap)
  set(install_dir "${CLAP_INSTALL_PATH}/${plugin_name}")
  set(res_dir "${output_dir}/resources")

  add_library(${target} MODULE)
  iplug_target_add(${target} PUBLIC LINK iPlug2_CLAP ${base_plugin} ${gui_libraries})
  iplug_copy_properties(${target} ${base_plugin} IPLUG_COPY_AFTER_BUILD IPLUG_RESOURCES)

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
  iplug_target_bundle_resources(${base_plugin} "${res_dir}")
  # After building copy to the correct directory
  iplug_add_post_build_copy(${target} "${output_dir}" "${install_dir}")
endfunction()
