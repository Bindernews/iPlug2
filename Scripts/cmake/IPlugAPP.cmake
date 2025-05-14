cmake_minimum_required(VERSION 3.20)

set(cwd ${IPLUG2_SDK_PATH}/IPlug/APP)
add_subdirectory(${cwd}/RTLibs ${CMAKE_BINARY_DIR}/IPlug/RTLibs)

##############
# iPlug2_APP #
##############

add_library(iPlug2_APP INTERFACE)
set(_src
  ${cwd}/IPlugAPP_dialog.cpp
  ${cwd}/IPlugAPP_host.cpp
  ${cwd}/IPlugAPP_host.h
  ${cwd}/IPlugAPP_main.cpp
  ${cwd}/IPlugAPP.cpp
  ${cwd}/IPlugAPP.h
)
set(_lib
  iPlug2_Core
  iPlug2_IGraphicsCore
  RTAudioMidi
)
set(_inc
  ${cwd}
)
set(_def
  APP_API
  IPLUG_EDITOR=1
  IPLUG_DSP=1
  BUILT_WITH_CMAKE
)

if (MSVC)
  # Not set charset for MSVC
  list(APPEND _def _SBCS)
endif()

# Link Windows sound libraies if on Windows
if (IPLUG_OS MATCHES "Windows")
  # Nothing to do
elseif (IPLUG_OS MATCHES "Darwin")
  # Some source files here combine C++ and Objective-C, so we tell clang how to compile them
  set_property(SOURCE ${_src} PROPERTY LANGUAGE "OBJCXX")
  # Link to swell, and additional platform-specific frameworks
  list(APPEND _lib
    WDL_SWELL
    "-framework AppKit"
    "-framework CoreMIDI"
    "-framework CoreAudio"
  )
elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
  # Link to swell
  list(APPEND _lib WDL_SWELL)
else()
  message(FATAL_ERROR "APP not supported on platform ${CMAKE_SYSTEM_NAME}")
endif()

iplug_target_add(iPlug2_APP INTERFACE
  SOURCE ${_src}
  INCLUDE ${_inc}
  DEFINE ${_def}
  LINK ${_lib}
  OPTION ${IPLUG_MSVC_FLAGS}
)

#--------------------------------------------------------------------
# configure function
function(iplug_configure_app base_plugin target)
  # Create target
  add_executable(${target} WIN32 MACOSX_BUNDLE)
  # setup
  iplug_configure_helper(TARGET ${target} GET_VARS app COPY_PROPERTIES)
  # Link
  iplug_target_add(${target} PUBLIC LINK iPlug2_APP ${base_plugin} ${gui_libraries})

  #--------------------------------------------------------
  # Windows
  if(IPLUG_OS MATCHES "Windows")
    set_target_properties(${target} PROPERTIES OUTPUT_NAME "${plugin_name}")

  #--------------------------------------------------------
  # MacOS
  elseif(CMAKE_SYSTEM_NAME MATCHES "Darwin")
    # Configure the .xib file
    set(resource_dir "${CMAKE_BINARY_DIR}/${target}/${plugin_name}.app/Contents/Resources")
    set(config_in_dir ${IPLUG2_SDK_PATH}/IPlug/Resources)
    iplug_configure_helper(TARGET ${target} CONVERT_XIB ${config_in_dir}/macOS-MainMenu.xib)

    # Setup the .plist file
    set(info_plist "${binary_subdir}/Info.plist")
    iplug_configure_basic_plist(${base_plugin} FORMAT app OUTPUT "${info_plist}")
    set_property(TARGET ${target} PROPERTY MACOSX_BUNDLE_INFO_PLIST "${info_plist}")

    # Add the icon file
    set(icon_file "${CMAKE_SOURCE_DIR}/resources/${plugin_name}.icns")
    source_group("Resources" FILES ${icon_file})
    iplug_target_add(${target} PUBLIC SOURCE ${icon_file})
    set_property(TARGET ${target} APPEND PROPERTY RESOURCE "${icon_file}")

  #--------------------------------------------------------
  # Linux
  elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
    set_target_properties(${target} PROPERTIES OUTPUT_NAME "${plugin_name}")

  endif()

  bn_set_output_directory(${target} "${output_dir}")
  iplug_configure_helper(TARGET ${target} MAIN_RC PLATFORM_SETUP)
  iplug_target_bundle_resources(${target} "${resource_dir}")
endfunction()

set(IPlugAPP_FOUND TRUE)
