cmake_minimum_required(VERSION 3.20)

set(cwd ${IPLUG2_SDK_PATH}/IPlug/WEB)
set(iplug_deps ${IPLUG2_SDK_PATH}/Dependencies/IPlug)
set(WAM_SDK_PATH ${iplug_deps}/WAM_SDK/wamsdk)
set(WAM_AWP_PATH ${iplug_deps}/WAM_AWP)

# Common options for both WAM and WEB
set(_opt
  -Wno-bitwise-op-parentheses
)
# Defines for both WAM and WEB targets
set(_def
  "WDL_NO_DEFINE_MINMAX"
  $<$<CONFIG:Release>:NDEBUG=1>
)
# LDFLAGS for both WAM and WEB targets
set(_ldflags
  "SHELL:-s ALLOW_MEMORY_GROWTH=1"
  --bind
  $<$<CONFIG:Debug>:-g4 -O0>
  $<$<CONFIG:Release>:SHELL:-s ASSERTIONS=0>
)

##############
# iPlug2_WEB #
##############

add_library(iPlug2_WEB INTERFACE)
iplug_target_add(
  iPlug2_WEB INTERFACE
  DEFINE
    "WEB_API"
    "IPLUG_EDITOR=1"
    # Using canvas graphics backend and NanoVG together somehow
    "IGRAPHICS_CANVAS"
    # Force using NanoVG and GLES2
    IGRAPHICS_GLES2
    ${_def}
  OPTION
    ${_opt}
  SOURCE
    ${cwd}/IPlugWeb.h
    ${cwd}/IPlugWeb.cpp
  INCLUDE
    ${cwd}
  LINK
    idbfs.js
    iPlug2_Core
    iPlug2_WebCanvas
)

# List of wasm functions the web UI should export
iplug_list_to_js_list(WEB_EXPORTS
  _main
  _iplug_fsready
  _iplug_syncfs
)
iplug_list_to_js_list(WEB_IMPORTS
  UTF8ToString
  ccall
)


target_link_options(iPlug2_WEB INTERFACE
  "SHELL:-s EXPORTED_FUNCTIONS=\"${WEB_EXPORTS}\""
  "SHELL:-s EXPORTED_RUNTIME_METHODS=\"${WEB_IMPORTS}\""
  "SHELL:-s BINARYEN_ASYNC_COMPILATION=1"
  "SHELL:-s FORCE_FILESYSTEM=1"
  "SHELL:-s ENVIRONMENT=web"
  -sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$ccall'
  # NanoVG link flags
  "-sUSE_WEBGL2=0"
  "-sFULL_ES3=1"
  # Common LD flags
  ${_ldflags}
)


##############
# iPlug2_WAM #
##############

add_library(iPlug2_WAM INTERFACE)
iplug_target_add(iPlug2_WAM INTERFACE
  DEFINE
    "WAM_API"
    "IPLUG_DSP=1"
    "NO_IGRAPHICS"
    "SAMPLE_TYPE_FLOAT"
    ${_def}
  OPTION
    ${_opt}
  SOURCE
    #every cpp file that is needed for the WAM audio processor WASM module running in the audio worklet
    ${cwd}/IPlugWAM.h
    ${cwd}/IPlugWAM.cpp
    ${cwd}/../IPlugProcessor.h
    ${cwd}/../IPlugProcessor.cpp
    ${WAM_SDK_PATH}/processor.h
    ${WAM_SDK_PATH}/processor.cpp
  INCLUDE
    ${cwd}
    ${WAM_SDK_PATH}
  LINK
    iPlug2_Core
    iPlug2_NoGraphics
)

iplug_list_to_js_list(WAM_EXPORTS
  _createModule
  _wam_init
  _wam_terminate
  _wam_resize
  _wam_onprocess
  _wam_onmidi
  _wam_onsysex
  _wam_onparam
  _wam_onmessageN
  _wam_onmessageS
  _wam_onmessageA
  _wam_onpatch
)
iplug_list_to_js_list(WAM_IMPORTS
  ccall
  cwrap
  setValue
  UTF8ToString
)

# We can't compile the WASM module synchronously on main thread (.wasm over 4k in size requires async compile on chrome)
# https://developers.google.com/web/updates/2018/04/loading-wasm and you can't compile asynchronously in AudioWorklet scope
# The following settings mean the WASM is delivered as BASE64 and included in the MyPluginName-wam.js file.
target_link_options(iPlug2_WAM INTERFACE
  "SHELL:-s EXPORTED_FUNCTIONS=\"${WAM_EXPORTS}\""
  "SHELL:-s EXPORTED_RUNTIME_METHODS=\"${WAM_IMPORTS}\""
  # -sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$ccall'
  "SHELL:-s BINARYEN_ASYNC_COMPILATION=0"
  "SHELL:-s SINGLE_FILE=1"
  #"SHELL:-s ENVIRONMENT=worker"
  ${_ldflags}
)


function(iplug_configure_wam base_plugin target)
  iplug_get_common_plugin_variables(wam)

  # Do the DSP portion first
  add_executable(${target})
  target_link_libraries(${target} PUBLIC ${base_plugin} iPlug2_WAM)
  set_target_properties(
    ${target} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${output_dir}/scripts
    OUTPUT_NAME "${plugin_name}-wam")

  # Now the UI portion
  set(target_ui ${target}_ui)
  add_executable(${target_ui})
  target_link_libraries(${target_ui} PUBLIC ${base_plugin} iPlug2_WEB)
  set_target_properties(
    ${target_ui} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${output_dir}/scripts
    OUTPUT_NAME "${plugin_name}-web")

  # Copy template and scripts
  set(template_dir ${IPLUG2_SDK_PATH}/IPlug/WEB/Template)
  set(NAME_PLACEHOLDER ${plugin_name})
  set(files_to_configure
    index.html
    scripts/IPlugWAM-awn.js
    scripts/IPlugWAM-awp.js
    scripts/websocket.js
    styles/style.css
  )
  foreach(source_name ${files_to_configure})
    string(REPLACE "IPlugWAM" ${plugin_name} dest_name ${source_name})
    configure_file(${template_dir}/${source_name} ${output_dir}/${dest_name} @ONLY)
  endforeach()

  # Copy from WAM AMP
  set(WAM_AWP_PATH ${IPLUG2_SDK_PATH}/Dependencies/IPlug/WAM_AWP)
  foreach(source_name audioworker.js audioworklet.js)
    configure_file(${WAM_AWP_PATH}/${source_name} ${output_dir}/scripts/${source_name} COPYONLY)
  endforeach()

endfunction()
