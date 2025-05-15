cmake_minimum_required(VERSION 3.20)

# Set the cache value. Does nothing if cache value is already set or given on CLI.
set(VST2_SDK "${IPLUG2_SDK_PATH}/Dependencies/IPlug/VST2_SDK" CACHE PATH "VST2 SDK directory.")

# Check to make sure we have at least one of the files we need.
if (NOT EXISTS "${VST2_SDK}/aeffectx.h")
  set(IPlugVST2_FOUND FALSE CACHE INTERNAL "")
  message(WARNING "VST2 SDK not found or missing files.")
  return()
endif()

# Determine VST2 directories
bn_case(IPLUG_OS _user_install_path
  # For Windows, install locally to the VST3 directory, since most hosts will find it there as well
  "Windows" "$ENV{LOCALAPPDATA}/Programs/Common/VST3"
  "Darwin" "$ENV{HOME}/Library/Audio/Plug-Ins/VST"
  "Linux" "$ENV{HOME}/.vst"
)
bn_case(IPLUG_OS _system_install_path
  # Technically we should use $ENV{ProgramFiles\(x86\)} for Win32 on Win64, but since Win32
  # is deprecated as of Windows 11, and it's much more work, just ignore that issue.
  "Windows" "$ENV{ProgramFiles}/Steinberg/VstPlugins"
  "Darwin" "/Library/Audio/Plug-Ins/VST"
  "Linux" "/usr/local/lib/vst"
)

iplug_set_install_paths(VST2 "${_user_install_path}" "${_system_install_path}")

# Check if we're compiling with GCC
bn_tern(is_gcc 1 0 ${CMAKE_CXX_COMPILER_ID} MATCHES "GNU")

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

#--------------------------------------------------------------------
# configure function
function(iplug_configure_vst2 base_plugin target)
  # Create module and link it to dependencies
  add_library(${target} MODULE)
  iplug_configure_helper(TARGET ${target} GET_VARS vst2 COPY_PROPERTIES)
  iplug_target_add(${target} PUBLIC LINK iPlug2_VST2 ${base_plugin} ${gui_libraries})
  set(install_dir "${IPLUG_VST2_USER_INSTALL_PATH}/${plugin_name}.vst2")
  set(res_dir "${output_dir}/resources")

  if (IPLUG_OS MATCHES "Windows")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      LIBRARY_OUTPUT_DIRECTORY "${output_dir}"
      PREFIX ""
      SUFFIX ".dll"
    )

  elseif (IPLUG_OS MATCHES "Darwin")
    set(info_plist "${binary_subdir}/Info.plist")
    iplug_configure_basic_plist(${base_plugin} FORMAT vst2 OUTPUT "${info_plist}")

    set_target_properties(${target} PROPERTIES
      BUNDLE TRUE
      MACOSX_BUNDLE TRUE
      MACOSX_BUNDLE_INFO_PLIST "${info_plist}"
      BUNDLE_EXTENSION "vst"
    )

    if (CMAKE_GENERATOR STREQUAL "Xcode")
      set(output_dir "${CMAKE_BINARY_DIR}/$<CONFIG>/${plugin_name}.vst")
      set(res_dir "")
    endif()

  elseif (IPLUG_OS MATCHES "Linux")
    set_target_properties(${target} PROPERTIES
      OUTPUT_NAME "${plugin_name}"
      PREFIX ""
      SUFFIX ".so"
    )
  endif()

  # Handle resources
  iplug_target_bundle_resources(${target} "${res_dir}" PREFER_EMBED)
  bn_set_output_directory(${target} "${output_dir}")
  iplug_configure_helper(TARGET ${target} MAIN_RC POST_BUILD_COPY "${install_dir}")
endfunction()

set(IPlugVST2_FOUND TRUE)