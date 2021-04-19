cmake_minimum_required(VERSION 3.11)

function(_iplug_setup_lv2)

  add_subdirectory(${IPLUG2_SDK_PATH}/Dependencies/IPlug/rundyn tools/rundyn)

  set(_doc "Path to install LV2 plugins")
  if (WIN32)
    iplug_find_path(LV2_INSTALL_PATH DIR DEFAULT_IDX 0 DOC ${_doc}
      PATHS "$ENV{APPDATA}/LV2" "$ENV{COMMONPROGRAMFILES}/LV2")
  elseif (OS_MAC)
    iplug_find_path(LV2_INSTALL_PATH DIR DEFAULT_IDX 0 DOC ${_doc}
      PATHS "$ENV{HOME}/Library/Audio/Plug-Ins/LV2" "/Library/Audio/Plug-Ins/LV2")
  elseif (OS_LINUX)
    iplug_find_path(LV2_INSTALL_PATH DIR DEFAULT_IDX 0 DOC ${_doc}
      PATHS "$ENV{HOME}/.lv2" "/usr/local/lib/lv2" "/usr/lib/lv2")
  endif()


  set(IPLUG_SRC ${IPLUG2_SDK_PATH}/IPlug)
  set(IPLUG_DEPS ${IPLUG2_SDK_PATH}/Dependencies/IPlug)

  find_path(LV2_SDK_PATH "lv2"
    PATHS "${IPLUG_DEPS}/LV2" "${IPLUG_DEPS}/lv2"
    DOC "Path to LV2 sdk"
    REQUIRED
  )

  set(dir "${IPLUG_SRC}/LV2/")

  add_library(iPlug2_LV2 INTERFACE)
  iplug_target_add(iPlug2_LV2 INTERFACE
    DEFINE "LV2_API" "SAMPLE_TYPE_FLOAT=1" "LV2_CONTROL_PORTS"
    INCLUDE "${LV2_SDK_PATH}" "${IPLUG_SRC}/LV2"
    LINK iPlug2_Core)

  add_library(iPlug2_LV2_DSP INTERFACE)
  iplug_target_add(iPlug2_LV2_DSP INTERFACE
    DEFINE "LV2P_API=1" "IPLUG_DSP=1" "NO_IGRAPHICS"
    SOURCE
      "${dir}/IPlugLV2.h"
      "${dir}/IPlugLV2.cpp"
      "${dir}/IPlugLV2_cfg.cpp"
    LINK iPlug2_LV2)

  add_library(iPlug2_LV2_UI INTERFACE)
  iplug_target_add(iPlug2_LV2_UI INTERFACE
    DEFINE "LV2C_API=1" "IPLUG_EDITOR=1"
    SOURCE 
      "${dir}/IPlugLV2.h"
      "${dir}/IPlugLV2.cpp"
    LINK iPlug2_LV2)

endfunction(_iplug_setup_lv2)
_iplug_setup_lv2()

function(iplug_configure_lv2 target)
  get_target_property(plugin_name ${target} IPLUG_PLUGIN_NAME)
  set(out_dir "${CMAKE_BINARY_DIR}/${target}")
  set(install_dir "${LV2_INSTALL_PATH}/${plugin_name}.lv2")

  iplug_target_add(${target} PUBLIC LINK iPlug2_LV2_DSP)

  set_target_properties(${target} PROPERTIES
    OUTPUT_NAME "${plugin_name}"
    LIBRARY_OUTPUT_DIRECTORY "${out_dir}"
    PREFIX "")

  if (WIN32)
    set_target_properties(${target} PROPERTIES
      SUFFIX ".dll")
    set(res_dir "${out_dir}/resources")

  elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
    set_target_properties(${target} PROPERTIES
      SUFFIX ".dylib")
    set(res_dir "${out_dir}/resources")

  elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
    set_target_properties(${target} PROPERTIES
      SUFFIX ".so")
    set(res_dir "${out_dir}/resources")
    
  endif()

  # Add TTL generator command
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND rundyn "$<TARGET_FILE:${target}>,write_ttl" "${out_dir}"
    COMMENT "Generating TTL file for ${target}")

  # Handle resources
  if (res_dir)
    iplug_target_bundle_resources(${target} "${res_dir}")
  endif()

  # After building copy to the correct directory
  iplug_add_post_build_copy(${target} "${out_dir}" "${install_dir}")
endfunction()

function(iplug_configure_lv2_ui target main_target)
  target_link_libraries(${target} PUBLIC iPlug2_LV2_UI)

  get_target_property(plugin_name ${target} IPLUG_PLUGIN_NAME)

  set(out_dir "${CMAKE_BINARY_DIR}/${main_target}")
  set(res_dir "${CMAKE_BINARY_DIR}/${main_target}/resources")

  if (WIN32)
    set(suffix ".dll")
  elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
    set(suffix ".dylib")
  elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
    set(suffix ".so")
  endif()

  set_target_properties(${target} PROPERTIES
    OUTPUT_NAME "${plugin_name}_ui"
    LIBRARY_OUTPUT_DIRECTORY "${out_dir}"
    PREFIX ""
    SUFFIX "${suffix}")

  # Ensure that building the main LV2 target will also build the UI
  add_dependencies(${main_target} ${target})

  # DO NOT handle resources. That's dealt with by main target
  # DO NOT copy to install directory
endfunction(iplug_configure_lv2_ui)

