cmake_minimum_required(VERSION 3.20)

set(WDL_DIR ${IPLUG2_SDK_PATH}/WDL)

add_subdirectory(RTLibs ${CMAKE_BINARY_DIR}/IPlug/RTLibs)
add_subdirectory(${WDL_DIR}/lice ${CMAKE_BINARY_DIR}/WDL/lice)
add_subdirectory(${WDL_DIR}/swell ${CMAKE_BINARY_DIR}/WDL/swell)

##############
# iPlug2_APP #
##############

add_library(iPlug2_APP INTERFACE)
set(cwd ${CMAKE_CURRENT_LIST_DIR})
set(_src
  ${cwd}/IPlugAPP.h
  ${cwd}/IPlugAPP.cpp
  ${cwd}/IPlugAPP_dialog.cpp
  ${cwd}/IPlugAPP_host.cpp
  ${cwd}/IPlugAPP_main.cpp
)
set(_lib
  iPlug2_Core
  iPlug2_IGraphicsCore
  iPlug2_RTLibs
)
set(_inc
  ${cwd}
)
set(_def
  APP_API
  IPLUG_EDITOR=1
  IPLUG_DSP=1
)

# Link Windows sound libraies if on Windows
if (IPLUG_OS MATCHES "Windows")
  # Nothing to do
elseif (IPLUG_OS MATCHES "Darwin")
  # Some source files here combine C++ and Objective-C, so we tell clang how to compile them
  set_property(SOURCE ${_src} PROPERTY LANGUAGE "OBJCXX")
  # Link to swell
  list(APPEND _lib WDL_SWELL)
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
)
# iplug_source_tree(iPlug2_APP)

function(iplug_configure_app base_plugin target)
  get_target_property(plugin_name ${base_plugin} IPLUG_PLUGIN_NAME)
  get_target_property(gui_libraries ${base_plugin} IPLUG_PLUGIN_GRAPHICS)

  # Create target
  add_executable(${target} WIN32 MACOSX_BUNDLE)
  iplug_target_add(${target} PUBLIC LINK iPlug2_APP ${base_plugin} ${gui_libraries})

  set(out_dir "${CMAKE_BINARY_DIR}/${target}")
  set(res_dir "${out_dir}/resources")

  if (WIN32)
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      RUNTIME_OUTPUT_DIRECTORY "${out_dir}")

  elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
    set(res_dir "${CMAKE_BINARY_DIR}/${target}/${PLUG_NAME}.app/Contents/Resources")
    # Set the Info.plist file and add required resources
    set(_res
      "${CMAKE_SOURCE_DIR}/resources/${plugin_name}.icns"
      "${CMAKE_SOURCE_DIR}/resources/${plugin_name}-macOS-MainMenu.xib")
    source_group("Resources" FILES ${_res})
    iplug_target_add(${target} PUBLIC SOURCE ${_res} RESOURCE ${_res})
    set_target_properties(${target} PROPERTIES
      MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/resources/${plugin_name}-macOS-Info.plist")
    # Disable resource processing
    set(res_dir "")

  elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
    set(res_dir "${CMAKE_BINARY_DIR}/${target}/resources")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      RUNTIME_OUTPUT_DIRECTORY "${out_dir}")

  endif()

  if (res_dir)
    iplug_target_bundle_resources(${target} "${res_dir}")
  endif()
endfunction()
