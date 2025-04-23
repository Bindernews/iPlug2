cmake_minimum_required(VERSION 3.20)

# Set the cache value. Does nothing if cache value is already set or given on CLI.
set(VST2_SDK "${IPLUG2_SDK_PATH}/Dependencies/IPlug/VST2_SDK" CACHE PATH "VST2 SDK directory.")

# Check to make sure we have at least one of the files we need.
if (NOT EXISTS "${VST2_SDK}/aeffectx.h")
  set(IPlugVST2_FOUND FALSE)
  message(WARNING "VST2 SDK not found or missing files.")
  return()
endif()

# Determine VST2 directories
if (IPLUG_OS MATCHES "Windows")
  set(fn "VstPlugins")
  set(_paths $ENV{CommonProgramFiles}/VST2)
  if (PROCESSOR_ARCH STREQUAL "Win32")
    list(APPEND _paths "$ENV{ProgramFiles\(x86\)}/${fn}" "$ENV{ProgramFiles\(x86\)}/Steinberg/${fn}")
  endif()
  # Append this for x86, x64, and ARM I guess
  list(APPEND _paths "'$ENV{ProgramFiles}/${fn}'" "'$ENV{ProgramFiles}/Steinberg/${fn}'")
elseif (IPLUG_OS MATCHES "Darwin")
  set(fn "VST")
  set(_paths "$ENV{HOME}/Library/Audio/Plug-Ins/${fn}" "/Library/Audio/Plug-Ins/${fn}")
elseif (IPLUG_OS MATCHES "Linux")
  set(_paths "$ENV{HOME}/.vst" "/usr/local/lib/vst" "/usr/local/vst")
endif()

iplug_find_path(
  VST2_INSTALL_PATH REQUIRED DIR
  DEFAULT_IDX 0
  DOC "Path to install VST2 plugins"
  PATHS ${_paths}
)

# Check if we're compiling with GCC
iplug_ternary(is_gcc 1 0 ${CMAKE_CXX_COMPILER_ID} MATCHES "GNU")

set(cwd ${IPLUG2_SDK_PATH}/IPlug/VST2)

add_library(iPlug2_VST2 INTERFACE)
iplug_target_add(iPlug2_VST2 INTERFACE
  SOURCE
  ${cwd}/IPlugVST2.h
  ${cwd}/IPlugVST2.cpp

  INCLUDE
  ${cwd}
  ${VST2_SDK}

  DEFINE
  "VST2_API"
  "VST_FORCE_DEPRECATED"
  "IPLUG_DSP=1"

  # Linux needs this define
  $<$<STREQUAL:${IPLUG_OS},"Linux">:"SMTG_OS_LINUX">

  # GCC doesn't like __cdecl, so instead of having people modify their
  # aeffect.h file, just redefine __cdecl.
  $<$<BOOL:${is_gcc}>: "__cdecl=__attribute__(())" >

  LINK
  iPlug2_Core
)

source_group(IPlug/VST2 FILES ${cwd}/IPlugVST2.h ${cwd}/IPlugVST2.cpp)


# Get all propreties that cmake supports
if(NOT CMAKE_PROPERTY_LIST)
    execute_process(COMMAND ${CMAKE_COMMAND} --help-property-list OUTPUT_VARIABLE CMAKE_PROPERTY_LIST)

    # Convert command output into a CMake list
    string(REGEX REPLACE ";" "\\\\;" CMAKE_PROPERTY_LIST "${CMAKE_PROPERTY_LIST}")
    string(REGEX REPLACE "\n" ";" CMAKE_PROPERTY_LIST "${CMAKE_PROPERTY_LIST}")
    list(REMOVE_DUPLICATES CMAKE_PROPERTY_LIST)
    set(CMAKE_PROPERTY_LIST "${CMAKE_PROPERTY_LIST}" CACHE INTERNAL "" FORCE)
endif()

function(print_properties)
    message("CMAKE_PROPERTY_LIST = ${CMAKE_PROPERTY_LIST}")
endfunction()

function(print_target_properties target)
    if(NOT TARGET ${target})
      message(STATUS "There is no target named '${target}'")
      return()
    endif()

    foreach(property ${CMAKE_PROPERTY_LIST})
        string(REPLACE "<CONFIG>" "${CMAKE_BUILD_TYPE}" property ${property})

        # Fix https://stackoverflow.com/questions/32197663/how-can-i-remove-the-the-location-property-may-not-be-read-from-target-error-i
        if(property STREQUAL "LOCATION" OR property MATCHES "^LOCATION_" OR property MATCHES "_LOCATION$")
            continue()
        endif()

        get_property(was_set TARGET ${target} PROPERTY ${property} SET)
        if(was_set)
            get_target_property(value ${target} ${property})
            message(STATUS "${target} ${property} = ${value}")
        endif()
    endforeach()
endfunction()

#--------------------------------------------------------------------
# configure function
function(iplug_configure_vst2 base_plugin target)
  # Create module and link it to dependencies
  add_library(${target} MODULE)
  iplug_configure_helper(GET_VARS vst2 COPY_PROPERTIES ${target})
  iplug_target_add(${target} PUBLIC LINK iPlug2_VST2 ${base_plugin} ${gui_libraries})

  set(res_dir "${output_dir}/resources")

  if (IPLUG_OS MATCHES "Windows")
    set(install_dir "${VST2_INSTALL_PATH}/${plugin_name}")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      LIBRARY_OUTPUT_DIRECTORY "${output_dir}"
      PREFIX ""
      SUFFIX ".dll"
    )

  elseif (IPLUG_OS MATCHES "Darwin")
    iplug_file_in_binary_dir(${target} "Info.plist" info_plist)
    iplug_configure_basic_plist(${base_plugin} FORMAT vst2 OUTPUT "${info_plist}")

    set_target_properties(${target} PROPERTIES
      BUNDLE TRUE
      MACOSX_BUNDLE TRUE
      MACOSX_BUNDLE_INFO_PLIST "${info_plist}"
      BUNDLE_EXTENSION "vst"
      PREFIX ""
      SUFFIX "")

    if (CMAKE_GENERATOR STREQUAL "Xcode")
      set(output_dir "${CMAKE_BINARY_DIR}/$<CONFIG>/${plugin_name}.vst")
      set(res_dir "")
    endif()

  elseif (IPLUG_OS MATCHES "Linux")
    set(install_dir "${VST2_INSTALL_PATH}/${plugin_name}.vst2")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      LIBRARY_OUTPUT_DIRECTORY "${output_dir}"
      PREFIX ""
      SUFFIX ".so"
    )
  endif()

  # Handle resources
  if (res_dir)
    iplug_target_bundle_resources(${target} "${res_dir}")
  endif()

  iplug_add_post_build_copy(${target} "${output_dir}" "${install_dir}")

endfunction()

set(IPlugVST2_FOUND TRUE)