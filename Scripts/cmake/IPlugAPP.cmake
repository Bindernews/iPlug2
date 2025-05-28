cmake_minimum_required(VERSION 3.20)

set(cwd ${IPLUG2_SDK_PATH}/IPlug/APP)

add_subdirectory(${cwd}/RTLibs ${iPlug2_BINARY_DIR}/RTLibs)

iplug_format_helper(
  SETUP
  FORMAT app
  SUFFIX
    "Windows" ".exe"
    "Darwin"  ""
    "Linux"   ""
  CUSTOM_XML [[
  <key>LSApplicationCategoryType</key> <string>public.app-category.music</string>
  <key>NSMainNibFile</key> <string>${PLUGIN_NAME}-macOS-MainMenu</string>
  <key>NSPrincipalClass</key> <string>SWELLApplication</string>
  <key>CFBundleIconFile</key> <string>${PLUGIN_NAME}.icns</string>
  ]]
)

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

if (CMAKE_COMPILER_IS_GNUCXX)
  target_compile_options(iPlug2_APP INTERFACE $<$<COMPILE_LANGUAGE:CXX>:-Wno-suggest-override>)
endif()

iplug_target_add(
  iPlug2_APP INTERFACE
  SOURCE ${_src}
  INCLUDE ${cwd}
  DEFINE ${_def}
  LINK ${_lib}
  OPTION ${IPLUG_MSVC_FLAGS}
)

#--------------------------------------------------------------------
# configure function
function(iplug_configure_app base_plugin target)
  iplug_format_helper(FORMAT app GET_VARS)

  # Create target
  add_executable(${target} WIN32 MACOSX_BUNDLE)
  # Setup and link
  iplug_format_helper(FORMAT app TARGET ${target} TARGET_COMMON COPY_RESOURCE_H)
  iplug_target_add(${target} PUBLIC LINK iPlug2_APP ${base_plugin} ${gui_libraries})

  #--------------------------------------------------------
  # MacOS
  if(IPLUG_OS MATCHES "Darwin")
    # Configure the .xib file
    iplug_format_helper(
      FORMAT app
      TARGET ${target}
      CONVERT_XIB ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/macOS-MainMenu.xib
    )

    # Add the icon file
    set(icon_file "${CMAKE_SOURCE_DIR}/resources/${plugin_name}.icns")
    source_group("Resources" FILES ${icon_file})
    iplug_target_add(${target} PUBLIC SOURCE ${icon_file})
    set_property(TARGET ${target} APPEND PROPERTY RESOURCE "${icon_file}")
  endif()

  bn_set_output_directory(${target} "${output_dir}")
  iplug_target_bundle_resources(${target} "${resource_dir}")
endfunction()

set(IPlugAPP_FOUND TRUE)
