cmake_minimum_required(VERSION 3.20)

set(AUv2_INSTALL_PATH "$ENV{HOME}/Library/Audio/Plug-Ins/Components")

#################
# Audio Unit v2 #
#################

find_library(AUDIOUNIT_LIB AudioUnit)
find_library(COREAUDIO_LIB CoreAudio)

# AU_PATH = $(HOME)/Library/Audio/Plug-Ins/Components

add_library(iPlug2_AUv2 INTERFACE)
set(cwd ${IPLUG2_SDK_PATH}/IPlug/AUv2)
iplug_target_add(iPlug2_AUv2 INTERFACE
  DEFINE
    "AU_API"
    "IPLUG_EDITOR=1"
    "IPLUG_DSP=1"
  LINK
    iPlug2_Core
    iPlug2_Plugin
    ${AUDIOUNIT_LIB}
    ${COREAUDIO_LIB}
    "-framework CoreMidi"
    "-framework AudioToolbox"
  INCLUDE
    ${cwd}
  SOURCE
    ${cwd}/dfx-au-utilities.c
    ${cwd}/IPlugAU.cpp
    ${cwd}/IPlugAU.r
    ${cwd}/IPlugAU_view_factory.mm
)

function(iplug_configure_au2 base_plugin target)
  iplug_get_common_plugin_variables(vst3)
  # Create target
  add_library(${target} MODULE)
  # Link to iPlug library and GUI libraries, and copy properties
  target_link_libraries(${target} PUBLIC iPlug2_AUv2 ${base_plugin} ${gui_libraries})
  iplug_copy_properties(${target} ${base_plugin} IPLUG_COPY_AFTER_BUILD IPLUG_RESOURCES)

  # Xcode vs Make/Ninja
  if (CMAKE_GENERATOR STREQUAL "Xcode")
    set(out_dir "${CMAKE_BINARY_DIR}/$<CONFIG>/${PLUG_NAME}.component")
    set(res_dir "")
  else()
    set(out_dir "${CMAKE_BINARY_DIR}/${PLUG_NAME}.component")
    set(res_dir "${out_dir}/Contents/Resources")
  endif()
  set(install_dir "${AUv2_INSTALL_PATH}/${PLUG_NAME}.component")

  set_target_properties(${target} PROPERTIES
    BUNDLE TRUE
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/resources/${PLUG_NAME}-AU-Info.plist
    BUNDLE_EXTENSION "component"
    PREFIX ""
    SUFFIX "")


  if (res_dir)
    iplug_target_bundle_resources(${target} "${res_dir}")
  endif()
  iplug_add_post_build_copy(${target} "${output_dir}" "${install_dir}")
endfunction(iplug_configure_au2)