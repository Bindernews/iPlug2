cmake_minimum_required(VERSION 3.20)


set(cwd ${IPLUG2_SDK_PATH}/IPlug/LV2)
set(deps_dir ${IPLUG2_SDK_PATH}/Dependencies/IPlug)

# So that we can generate the .ttl file
add_subdirectory(${deps_dir}/rundyn ${CMAKE_BINARY_DIR}/IPlug/rundyn)

# Locate the LV2 sdk
find_path(LV2_SDK_PATH "lv2"
  PATHS "${deps_dir}/lv2" "${deps_dir}/LV2"
  DOC "Path to LV2 sdk"
  REQUIRED
)

# Find the install path for lv2 plugins based on OS.
if (IPLUG_OS MATCHES "Windows")
  set(_paths "$ENV{APPDATA}/LV2" "$ENV{COMMONPROGRAMFILES}/LV2")
elseif (IPLUG_OS MATCHES "Darwin")
  set(_paths "$ENV{HOME}/Library/Audio/Plug-Ins/LV2" "/Library/Audio/Plug-Ins/LV2")
elseif (IPLUG_OS MATCHES "Linux")
  set(_paths "$ENV{HOME}/.lv2" "/usr/local/lib/lv2" "/usr/lib/lv2")
endif()

iplug_find_path(
  LV2_INSTALL_PATH DIR
  DEFAULT_IDX 0
  DOC "Path to install LV2 plugins"
  PATHS ${_paths}
)

# Core LV2 interface library.
add_library(iPlug2_LV2 INTERFACE)
iplug_target_add(iPlug2_LV2 INTERFACE
  DEFINE
  "LV2_API"
  "SAMPLE_TYPE_FLOAT=1"
  # "LV2_CONTROL_PORTS"

  SOURCE
  ${cwd}/IPlugLV2.h
  ${cwd}/IPlugLV2.cpp

  INCLUDE
  ${LV2_SDK_PATH}
  ${cwd}

  LINK
  iPlug2_Core
)

# The DSP portion of the LV2 library, also used to generate the configuration.
add_library(iPlug2_LV2_DSP INTERFACE)
iplug_target_add(iPlug2_LV2_DSP INTERFACE
  DEFINE
  "LV2P_API=1"
  "IPLUG_DSP=1"

  SOURCE
  ${cwd}/IPlugLV2_cfg.cpp
  ${cwd}/TTLDocument.h
  ${cwd}/TTLDocument.cpp

  LINK
  iPlug2_LV2
)

# The UI portion of the LV2 library
add_library(iPlug2_LV2_UI INTERFACE)
iplug_target_add(iPlug2_LV2_UI INTERFACE
  DEFINE
  "LV2C_API=1"
  "IPLUG_EDITOR=1"

  LINK
  iPlug2_LV2
)

function(iplug_configure_lv2 base_plugin target)
  # We don't copy properties to the DSP target
  iplug_configure_helper(GET_VARS lv2)
  set(install_dir "${LV2_INSTALL_PATH}/${plugin_name}.lv2")

  # DSP target first
  add_library(${target} MODULE)
  iplug_target_add(${target} PUBLIC LINK iPlug2_LV2_DSP iPlug2_NoGraphics ${base_plugin})

  if (IPLUG_OS MATCHES "Windows")
    set(suffix ".dll")
  elseif (IPLUG_OS MATCHES "Darwin")
    set(suffix ".dylib")
  elseif (IPLUG_OS MATCHES "Linux")
    set(suffix ".so")
  endif()

  # Set dependencies for our target
  set_target_properties(
    ${target} PROPERTIES
    OUTPUT_NAME "${plugin_name}"
    LIBRARY_OUTPUT_DIRECTORY "${output_dir}"
    PREFIX ""
    SUFFIX ${suffix}
  )

  # Add TTL generator command
  add_custom_command(
    TARGET ${target} POST_BUILD
    COMMAND rundyn "$<TARGET_FILE:${target}>,write_ttl" "${output_dir}"
    COMMENT "Generating TTL file for ${target}"
  )
  # add_dependencies(${target} rundyn)

  # Add ui library
  if (NOT gui_libraries STREQUAL iPlug2_NoGraphics)
    set(target_ui ${target}_ui)
    add_library(${target_ui} MODULE)
    target_link_libraries(${target_ui} PUBLIC iPlug2_LV2_UI ${base_plugin} ${gui_libraries})
    set_target_properties(${target_ui} PROPERTIES
      OUTPUT_NAME "${plugin_name}_ui"
      LIBRARY_OUTPUT_DIRECTORY "${output_dir}"
      PREFIX ""
      SUFFIX ${suffix}
    )

    # Ensure that building the main LV2 target will also build the UI
    add_dependencies(${target} ${target_ui})

    # Handle resources
    iplug_target_bundle_resources(${target_ui} "${resource_dir}")
  endif()

  # After building copy to the correct directory
  iplug_add_post_build_copy(${target} "${output_dir}" "${install_dir}")
endfunction()

set(IPlugLV2_FOUND TRUE)