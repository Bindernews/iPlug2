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

set(IPLUG_AU2_CUSTOM_XML [=[
  <key>AudioUnit Version</key> <string>0x00010000</string>
  <key>NSPrincipalClass</key> <string>@PLUGIN_NAME@_View</string>
  <key>AudioComponents</key>
  <array>
    <dict>
      <key>description</key> <string>@PLUGIN_NAME</string>
      <key>factoryFunction</key> <string>@PLUGIN_NAME@_Factory</string>
      <key>manufacturer</key> <string>Acme</string>
      <key>name</key> <string>AcmeInc: @PLUGIN_NAME</string>
      <key>sandboxSafe</key> <true/>
      <key>subtype</key> <string>@BUNDLE_SIGNATURE@</string>
      <key>type</key> <string>aumu</string>
      <key>version</key> <integer>65536</integer>
    </dict>
  </array>
]=] CACHE INTERNAL "")

function(iplug_configure_au2 base_plugin target)
  # Create target
  add_library(${target} MODULE)
  # Setup
  iplug_configure_helper(GET_VARS au2 COPY_PROPERTIES ${target})
  # Link to iPlug library and GUI libraries
  target_link_libraries(${target} PUBLIC iPlug2_AUv2 ${base_plugin} ${gui_libraries})

  # Xcode vs Make/Ninja
  if (CMAKE_GENERATOR STREQUAL "Xcode")
    set(out_dir "${CMAKE_BINARY_DIR}/$<CONFIG>/${PLUG_NAME}.component")
    set(res_dir "")
  else()
    set(out_dir "${CMAKE_BINARY_DIR}/${PLUG_NAME}.component")
    set(res_dir "${out_dir}/Contents/Resources")
  endif()
  set(install_dir "${AUv2_INSTALL_PATH}/${PLUG_NAME}.component")

  iplug_file_in_binary_dir(${target} Info.plist info_plist)
  iplug_configure_basic_plist(
    ${base_plugin}
    OUTPUT "${info_plist}"
    FORMAT au2
    CUSTOM_XML "${IPLUG_AU2_CUSTOM_XML}"
  )

  set_target_properties(${target} PROPERTIES
    BUNDLE TRUE
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST ${info_plist}
    BUNDLE_EXTENSION "component"
    PREFIX ""
    SUFFIX "")

  if (res_dir)
    iplug_target_bundle_resources(${target} "${res_dir}")
  endif()
  iplug_add_post_build_copy(${target} "${output_dir}" "${install_dir}")
endfunction(iplug_configure_au2)

set(IPlugAUv2_FOUND TRUE)
