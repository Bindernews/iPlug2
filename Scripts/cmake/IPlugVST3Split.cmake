# Load success is based on if the normal VST3 module loaded
bn_tern(IPlugVST3Split_FOUND TRUE FALSE COMMAND iplug_configure_vst3)
if(NOT IPlugVST3Split_FOUND)
  return()
endif()

# Configure a VST3 plugin with a split UI/controller and DSP/processor.
function(iplug_configure_vst3split base_plugin target)
  set(target_dsp ${target})
  set(target_ui ${target}_ui)

  # Grab some variables
  iplug_configure_helper(GET_VARS vst3split)

  #--------------------------------------------------------
  # Processor / DSP
  add_library(${target_dsp} MODULE)
  # Copy properties and link
  iplug_configure_helper(TARGET ${target_dsp} COPY_PROPERTIES)
  target_link_libraries(${target_dsp} PUBLIC iPlug2_VST3_DSP ${base_plugin} iPlug2_Plugin)
  # Add the entry point
  set(public_sdk_SOURCE_DIR ${smtg_public_sdk_SOURCE_DIR})
  smtg_target_add_library_main(${target_dsp})

  #--------------------------------------------------------
  # Controller / UI
  add_library(${target_ui} MODULE)
  # Copy properties and link
  iplug_configure_helper(TARGET ${target_ui} COPY_PROPERTIES)
  target_link_libraries(${target_ui} PUBLIC iPlug2_VST3_UI ${base_plugin} iPlug2_Plugin ${gui_libraries})

  # Platform-specific handling
  if(IPLUG_OS MATCHES "Darwin")
    # Configure the .plist file
    set(info_plist "${binary_subdir}/Info.plist")
    iplug_configure_basic_plist(${base_plugin} FORMAT vst3split OUTPUT "${info_plist}")
    # Only make the DSP a bundle, the UI lives in the bundle with it
    iplug_configure_helper(TARGET ${target_dsp} MAKE_BUNDLE "${info_plist}")
  endif()
  # Use the plugin name instead of the target name
  set_target_properties(${target_dsp} PROPERTIES OUTPUT_NAME "${plugin_name}")
  set_target_properties(${target_ui} PROPERTIES OUTPUT_NAME "${plugin_name}_ui")
  # Set the extension/bundle extension to be .vst3
  iplug_configure_helper(TARGET ${target_dsp} SET_EXTENSION ".vst3")
  iplug_configure_helper(TARGET ${target_ui} SET_EXTENSION ".vst3")

  bn_tern(install_dir "${IPLUG_VST3_USER_INSTALL_PATH}/${plugin_name}-split.vst3" "" IPLUG_VST3_USER_INSTALL_PATH)
  set(res_dir "${output_dir}/Contents/Resources")

  iplug_target_bundle_resources(${target_ui} "${res_dir}")
  bn_set_output_directory(${target_ui} "${output_dir}/Contents/${IPLUG_VST3_TARGET_ARCH}")
  bn_set_output_directory(${target_dsp} "${output_dir}/Contents/${IPLUG_VST3_TARGET_ARCH}")
  iplug_configure_helper(TARGET ${target_ui} MAIN_RC POST_BUILD_COPY "${install_dir}")
endfunction(iplug_configure_vst3split)


