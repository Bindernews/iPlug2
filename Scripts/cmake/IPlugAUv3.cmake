cmake_minimum_required(VERSION 3.20)


iplug_format_helper(
  SETUP
  FORMAT au3
  PLIST_VARIABLES
    "BUNDLE_PACKAGE_TYPE=XPC!"
)

set(_sdk ${IPLUG2_SDK_PATH}/IPlug/AUv3)
add_library(iPlug2_AUv3 INTERFACE)
iplug_target_add(iPlug2_AUv3 INTERFACE
  INCLUDE
    ${_sdk}
  SOURCE
    ${_sdk}/GenericUI.mm
    ${_sdk}/IPlugAUAudioUnit.mm
    ${_sdk}/IPlugAUv3.mm
    ${_sdk}/IPlugAUv3Appex.m
    ${_sdk}/IPlugAUViewController.mm
  DEFINE
    AUv3_API
    IPLUG_EDITOR=1
    IPLUG_DSP=1
  LINK
    iPlug2_Core
    iPlug2_Plugin
    "-framework AudioToolbox"
    "-framework AVFoundation"
    "-framework CoreAudio"
    "-framework CoreAudioKit"
)
iplug_source_tree(iPlug2_AUv3)

function(iplug_configure_au3)
  #message("AUv3 not yet implemented" FATAL_ERROR)
endfunction(iplug_configure_au3)

