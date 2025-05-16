cmake_minimum_required(VERSION 3.25)

set(cwd ${IPLUG2_SDK_PATH}/IPlug/LV2)
set(deps_dir ${IPLUG2_SDK_PATH}/Dependencies/IPlug)

# So that we can generate the .ttl file
add_subdirectory(${deps_dir}/rundyn ${CMAKE_BINARY_DIR}/IPlug/rundyn)

# Locate the LV2 sdk
find_path(LV2_SDK_PATH
  NAMES "lv2.pc.in"
  PATHS "${deps_dir}/lv2" "${deps_dir}/LV2"
  DOC "Path to LV2 sdk"
)

if (NOT LV2_SDK_PATH)
  set(IPlugLV2_FOUND FALSE)
  set(IPlugLV2_ERROR "LV2 sdk not found or doesn't contain required files.")
  return()
endif()

iplug_format_helper(
  SETUP
  FORMAT lv2
  # Determine VST2 directories
  USER_INSTALL_PATH
    # For Windows, install locally to the VST3 directory, since most hosts will find it there as well
    "Windows" "$ENV{APPDATA}/LV2"
    "Darwin"  "$ENV{HOME}/Library/Audio/Plug-Ins/LV2"
    "Linux"   "$ENV{HOME}/.lv2"
  SYSTEM_INSTALL_PATH
    # Technically we should use $ENV{ProgramFiles\(x86\)} for Win32 on Win64, but since Win32
    # is deprecated as of Windows 11, and it's much more work, just ignore that issue.
    "Windows" "$ENV{COMMONPROGRAMFILES}/LV2"
    "Darwin"  "/Library/Audio/Plug-Ins/LV2"
    "Linux"   "/usr/local/lib/lv2" # Or /usr/lib/lv2
  SUFFIX
    "Windows" ".dll"
    "Darwin"  ".dylib"
    "Linux"   ".so"
  RESOURCE_METHOD
    "Windows" "embed"

  CUSTOM_XML ""
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

  SOURCE
  ${cwd}/IPlugLV2Editor.cpp

  LINK
  iPlug2_LV2
)

function(iplug_configure_lv2 base_plugin target)
  # DSP target first
  add_library(${target} MODULE)
  iplug_format_helper(FORMAT lv2 GET_VARS)
  iplug_format_helper(
    FORMAT lv2 TARGET ${target}
    COPY_PROPERTIES GENERATE_PLIST MAKE_BUNDLE SET_NAME
    # After building copy to the correct directory
    POST_BUILD_COPY
  )
  iplug_target_add(${target} PUBLIC LINK iPlug2_LV2_DSP iPlug2_NoGraphics ${base_plugin})

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
    # Copy properties, set prefix and suffix, and bundle main.rc for the UI target instead of the DSP target.
    iplug_format_helper(
      FORMAT lv2 TARGET ${target_ui}
      COPY_PROPERTIES SET_NAME MAIN_RC
    )
    # Override output name
    set_target_properties(${target_ui} PROPERTIES OUTPUT_NAME "${plugin_name}_ui")
    # Ensure that building the main LV2 target will also build the UI
    add_dependencies(${target} ${target_ui})

    # Handle resources
    iplug_target_bundle_resources(${target_ui} "${resource_dir}")
    # All in one directory
    bn_set_output_directory(${target_ui} "${output_dir}")
  endif()

  # Remove configuration sub-directories.
  bn_set_output_directory(${target} "${output_dir}")
endfunction()

set(IPlugLV2_FOUND TRUE)