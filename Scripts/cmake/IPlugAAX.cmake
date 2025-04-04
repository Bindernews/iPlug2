cmake_minimum_required(VERSION 3.20)

set(AAX_SDK "${IPLUG2_SDK_PATH}/Dependencies/IPlug/AAX_SDK" CACHE PATH "Path to the AAX sdk")
set(IPLUG2_AAX_ICON "${AAX_SDK}/Utilities/PlugIn.ico" CACHE FILEPATH "Path to AAX plugin icon")

# TODO determine a real file that we can check to make sure the SDK is valid
if (NOT EXISTS ${AAX_SDK}/CMakeLists.txt)
  set(IPlugAAX_FOUND NOTFOUND CACHE PATH "" FORCE)

  # Fow now, dummy function so we don't crash
  function(iplug_configure_aax base_plugin target)
    add_library(${target} INTERFACE)
  endfunction()

  return()
endif()

# Decide on the install directory
if (WIN32)
  if (CMAKE_SYSTEM_PROCESSOR MATCHES "X86")
    set(aax_path $ENV{CommonProgramFiles}/Avid/Audio/Plug-Ins)
    cmake_path(NORMAL_PATH aax_path)
  elseif (CMAKE_SYSTEM_PROCESSOR MATCHES "(AMD64)|(IA64)")
    set(aax_path $ENV{CommanProgramW6432}/Avid/Audio/Plug-Ins)
    cmake_path(NORMAL_PATH aax_path)
  else()
    message(SEND_ERROR "Unknown architecture ${CMAKE_SYSTETM_PROCESSR}")
  endif()
elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
  # The AAX folder should be the location of the PT Dev build plug-ins folder, installer scripts will copy to the non-developer build
  set(aax_path "/Library/Application Support/Avid/Audio/Plug-Ins")
else()
  message(SEND_ERROR "AAX not supported on ${CMAKE_SYSTEM_NAME}")
endif()
set(AAX_INSTALL_PATH ${aax32_path} CACHE PATH "Path to install AAX plugins")

set(cwd ${IPLUG2_SDK_PATH}/IPlug/AAX)
add_library(iPlug2_AAX INTERFACE)
set(_inc
  ${cwd}
  ${AAX_SDK}/Interfaces
  ${AAX_SDK}/Interfaces/ACF
)
set(_src
  ${cwd}/IPlugAAX_Describe.cpp
  ${cwd}/IPlugAAX_Parameters.cpp
  ${cwd}/IPlugAAX_Parameters.h
  ${cwd}/IPlugAAX_TaperDelegate.h
  ${cwd}/IPlugAAX_view_interface.h
  ${cwd}/IPlugAAX.cpp
  ${cwd}/IPluxAAX.h
)
set(_def
  AAX_API
  IPLUG_EDITOR=1
  IPLUG_DSP=1
)
set(_lib
  iPlug2_Core
  iPlug2_Plugin
)

if (IPLUG_OS STREQUAL "Windows")
  list(APPEND _def
    _WINDOWS
    WIN32
    _WIN32
    WINDOWS_VERSION
    _LIB
  )
  # Windows libraries to link with
  list(APPEND _lib
    wininet.lib
    odbc32.lib
    odbccp32.lib
    psapi.lib
    kernel32.lib
    user32.lib
    gdi32.lib
    winspool.lib
    comdlg32.lib
    advapi32.lib
    shell32.lib
    ole32.lib
    oleaut32.lib
    uuid.lib
    comctl32.lib
  )
  target_link_directories(iPlug2_AAX INTERFACE ${AAX_SDK}/Libs/$<CONFIG>)
endif()

iplug_target_add(iPlug2_AAX INTERFACE
  DEFINE ${def}
  LINK ${_lib}
  INCLUDE ${_inc}
  SOURCE ${_src}
)
iplug_source_tree(iPlug2_AAX PREFIX "IPlug/AAX")

#--------------------------------------------------------------------
function(iplug_configure_aax base_plugin target)
  message(WARNING "AAX not yet fully implemented, expect bugs")

  # Common variables
  iplug_get_common_plugin_variables(app)
  # Create target
  add_library(${target} MODULE)
  # Link to interfaces and copy properties
  iplug_target_add(${target} PUBLIC LINK iPlug2_AAX ${base_plugin} ${gui_libraries})
  iplug_copy_properties(${target} ${base_plugin} IPLUG_COPY_AFTER_BUILD IPLUG_RESOURCES)

  # Default resources directory
  set(res_dir "${output_dir}/resources")

  if (WIN32)
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      RUNTIME_OUTPUT_DIRECTORY "${output_dir}")

  elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
    set(res_dir "${CMAKE_BINARY_DIR}/${target}/${plugin_name}.app/Contents/Resources")
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
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      RUNTIME_OUTPUT_DIRECTORY "${output_dir}")
  endif()

  iplug_target_bundle_resources(${target} "${res_dir}")
endfunction()
