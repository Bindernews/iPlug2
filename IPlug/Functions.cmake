cmake_minimum_required(VERSION 3.20)
include_guard(GLOBAL)

# Define iplug-specific properties
define_property(TARGET PROPERTY IPLUG_PLUGIN_NAME
  BRIEF_DOCS "The name of the plugin/app"
  FULL_DOCS "The name of the plugin/app")
define_property(TARGET PROPERTY IPLUG_PLUGIN_VERSION
  BRIEF_DOCS "The version (major.minor.bugfix) of the plugin."
  FULL_DOCS "The version (major.minor.bugfix) of the plugin. If not specified it will default to the project version.")
define_property(TARGET PROPERTY IPLUG_PLUGIN_GRAPHICS
  BRIEF_DOCS "The IGraphics backend API."
  FULL_DOCS "See iplug_setup_plugin.")
define_property(TARGET PROPERTY IPLUG_COPY_AFTER_BUILD
  BRIEF_DOCS "If true the plugin will be copied to the appropriate directory after a successful build."
  FULL_DOCS "iPlug2 will attempt to automatically find the correct directories to copy to, but if you
    want to set them manually the variables are: VST2_INSTALL_PATH, VST3_INSTALL_PATH, AUv2_INSTALL_PATH, LV2_INSTALL_PATH")
define_property(TARGET PROPERTY IPLUG_RESOURCES
  BRIEF_DOCS "List of resource files to be copied or loaded into the plugin's resource directory"
  FULL_DOCS "See brief doc")

#! iplug_target_add : Helper function to add sources, include directories, etc.
#
# This helper function combines calls to target_include_directories, target_sources,
# target_compile_definitions, target_compile_options, target_link_libraries,
# add_dependencies, and target_compile_features into a single function call.
# This means you don't have to re-type the target name so many times, and makes it
# clearer exactly what you're adding to a given target.
#
# \arg:target The name of the target
# \arg:set_type <PUBLIC | PRIVATE | INTERFACE>
# \group:INCLUDE List of include directories
# \group:SOURCE List of source files
# \group:DEFINE Compiler definitions
# \group:OPTION Compile options
# \group:LINK Link libraries (including other targets)
# \group:DEPEND Add dependencies on other targets
# \group:FEATURE Add compile features
function(iplug_target_add target set_type)
  cmake_parse_arguments("cfg" "" "" "INCLUDE;SOURCE;DEFINE;OPTION;LINK;LINK_DIR;DEPEND;FEATURE;RESOURCE" ${ARGN})
  #message("CALL iplug_add_target ${target}")
  if (cfg_UNUSED)
    message("Unused arguments ${cfg_UNUSED}" FATAL_ERROR)
  endif()

  get_target_property(ttype ${target} TYPE)
  if (${ttype} STREQUAL "INTERFACE_LIBRARY")
    set(_set_type "INTERFACE")
  else()
    set(_set_type ${set_type})
  endif()

  if (cfg_INCLUDE)
    target_include_directories(${target} ${_set_type} ${cfg_INCLUDE})
  endif()
  if (cfg_SOURCE)
    target_sources(${target} ${_set_type} ${cfg_SOURCE})
  endif()
  if (cfg_DEFINE)
    target_compile_definitions(${target} ${_set_type} ${cfg_DEFINE})
  endif()
  if (cfg_OPTION)
    target_compile_options(${target} ${_set_type} ${cfg_OPTION})
  endif()
  if (cfg_LINK)
    target_link_libraries(${target} ${_set_type} ${cfg_LINK})
  endif()
  if (cfg_LINK_DIR)
    target_link_directories(${target} ${_set_type} ${cfg_LINK_DIR})
  endif()
  if (cfg_DEPEND)
    add_dependencies(${target} ${_set_type} ${cfg_DEPEND})
  endif()
  if (cfg_FEATURE)
    target_compile_features(${target} ${_set_type} ${cfg_FEATURE})
  endif()

  # Versions of CMake prior to 3.19 didn't allow general properties on INTERFACE targets.
  # Version 3.23 adds filesets, but this works well and doesn't bump up the version.
  if (cfg_RESOURCE)
    # Make resource paths absolute
    set(resources_abs)
    foreach (path ${cfg_RESOURCE})
      cmake_path(ABSOLUTE_PATH path NORMALIZE OUTPUT_VARIABLE out_path)
      list(APPEND resources_abs ${out_path})
    endforeach()
    # Append to list of resources.
    set_property(TARGET ${target} APPEND PROPERTY IPLUG_RESOURCES ${resources_abs})
  endif()
endfunction()

#! iplug_ternary : Evaluates extra arguments as a conditional and sets VAR to val_true or val_false accordingly.
#
# \arg:VAR Variable name to set
# \arg:val_true Value to set if condition is true
# \arg:val_false Value to set if condition is false
# \argn Remaining arguments will be passed to IF()
macro(iplug_ternary VAR val_true val_false)
  if (${ARGN})
    set(${VAR} ${val_true})
  else()
    set(${VAR} ${val_false})
  endif()
endmacro()

macro(iplug_source_tree target)
  get_target_property(_tmp ${target} INTERFACE_SOURCES)
  if (NOT "${_tmp}" STREQUAL "_tmp-NOTFOUND")
    source_group(TREE ${IPLUG2_SDK_PATH} PREFIX "IPlug" FILES ${_tmp})
  endif()
endmacro()

#! iplug_find_path : An alternative to find_file and find_path that allows a default value.
#
# \arg:VAR Variable name to set
# \flag:DIR Search for a directory (cannot be used with FILE)
# \flag:FILE Search for a file (cannot be used with DIR)
# \flag:REQUIRED If this is set and there is no default cmake will abort with an error
# \param:DEFAULT_IDX If the path can't be found use the path in PATHS at index DEFAULT_IDX,
#                    negative values start from the end
# \param:DEFAULT If the path can't be found use this path instead
# \param:DOC Documentation string. If this is set the value will be set as a cache variable
# \group:PATHS List of paths to search for
function(iplug_find_path VAR)
  cmake_parse_arguments("arg" "REQUIRED;DIR;FILE" "DEFAULT_IDX;DEFAULT;DOC" "PATHS" ${ARGN})
  if (NOT arg_DIR AND NOT arg_FILE)
    message("ERROR: iplug_find_path MUST specify either DIR or FILE as an argument" FATAL_ERROR)
  endif()

  set(out 0)
  foreach (pt ${arg_PATHS})
    if (EXISTS ${pt})
      iplug_ternary(is_dir 1 0 IS_DIRECTORY ${pt})
      #message("Found path ${pt} and is_dir=${is_dir}")

      if ( (arg_FILE AND NOT ${is_dir}) OR (arg_DIR AND ${is_dir}) )
        set(out ${pt})
        break()
      endif()
    endif()
  endforeach()

  # Handle various default options
  if ((NOT out) AND (arg_DEFAULT))
    set(out ${arg_DEFAULT})
  endif()
  if ((NOT out) AND NOT ("${arg_DEFAULT_IDX}" STREQUAL ""))
    list(GET arg_PATHS "${arg_DEFAULT_IDX}" out)
  endif()

  # Determine cache type for the variable
  iplug_ternary(_cache_type PATH FILEPATH ${arg_DIR})
  # Handle required
  if ((NOT out) AND (arg_REQUIRED))
    set(${VAR} "${VAR}-NOTFOUND" CACHE ${_cache_type} ${arg_DOC}})
    message(FATAL_ERROR "Path ${VAR} not found!")
  endif()
  # Set cache var or var in parent scope
  if (arg_DOC)
    set(${VAR} ${out} CACHE ${_cache_type} ${arg_DOC})
  else()
    set(${VAR} ${out} PARENT_SCOPE)
  endif()
endfunction(iplug_find_path)

#! iplug_target_bundle_resource : Internal function to copy all resources to the output directory
#
# This pulls the list of resources from the target's RESOURCE property. Currently
# resources will be copied directly into res_dir unless the resource is a font
# or image, this is to comply with iPlug2's resource finding code.
#
# \arg:target The target to apply the changes on
# \arg:res_dir Directory to copy the resources into
function(iplug_target_bundle_resources target res_dir)
  get_property(resources TARGET ${target} PROPERTY IPLUG_RESOURCES)
  if (CMAKE_GENERATOR STREQUAL "Xcode")
    set_target_properties(${target} PROPERTIES RESOURCE ${resources})
    # On Xcode we mark each file as non-compiled
    foreach (res ${resources})
      get_filename_component(fn "${res}" NAME)
      set(file_type "file")
      if (fn MATCHES ".*\\.xib")
        set(file_type "file.xib")
      endif()
      set_property(SOURCE ${res} PROPERTY XCODE_LAST_KNOWN_FILE_TYPE ${file_type})
    endforeach()
  else()
    # Without Xcode we manually copy resources.
    foreach (res ${resources})

      get_filename_component(fn "${res}" NAME)
      # Default is to simply copy the file, some file types may need special
      # handling in which case they set copy to FALSE.
      set(copy TRUE)

      set(dst "${res_dir}/${fn}")
      if (NOT APPLE)
        # No Apple, this is the "normal" case
        if (fn MATCHES ".*\\.ttf")
          set(dst "${res_dir}/fonts/${fn}")
        elseif ((fn MATCHES ".*\\.png") OR (fn MATCHES ".*\\.svg"))
          set(dst "${res_dir}/img/${fn}")
        endif()
      else()
        # Apple but no Xcode? Manually compile xib files
        if (fn MATCHES ".*\\.xib")
          get_filename_component(tmp "${res}" NAME_WE)
          set(dst "${res_dir}/${tmp}.nib")
          add_custom_command(OUTPUT ${dst}
            COMMAND ${IBTOOL} ARGS "--errors" "--warnings" "--notices" "--compile" "${dst}" "${res}"
            MAIN_DEPENDENCY "${res}")
          set(copy FALSE)
        endif()
      endif()

      target_sources(${target} PUBLIC "${dst}")

      if (copy)
        add_custom_command(OUTPUT "${dst}"
          COMMAND ${CMAKE_COMMAND} ARGS "-E" "copy" "${res}" "${dst}"
          COMMENT "Copying resource to ${dst}"
          MAIN_DEPENDENCY "${res}")
      endif()
    endforeach()
  endif()
endfunction()

#[===[.rst:
.. code-block:: cmake

  iplug_copy_properties(<target_dst> <target_src> <properties>)

Copies property values from ``target_src`` to ``target_dst``. This is
used to propogate things like the resources list when adding output formats.
The ``properties`` argument lists names of properties to copy.

#]===]
function(iplug_copy_properties target_dst target_src properties)
  foreach(prop IN LISTS properties)
    get_target_property(tmp ${target_src} ${prop})
    set_target_properties(${target_dst} PROPERTIES ${prop} "${tmp}")
  endforeach()
endfunction(iplug_copy_properties)


#[===[.rst:
.. code-block:: cmake

  iplug_add_post_build_copy(
    <target>
    <source_directory>
    <destination_directory>
    [FORCE])

``FORCE``
  If this is specified then the post-build command will be added regardless
  of the state of the ``IPLUG_COPY_AFTER_BUILD`` property.

#]===]
function(iplug_add_post_build_copy target src_dir dest_dir)
  cmake_parse_arguments(arg "FORCE" "" "" ${ARGN})
  get_target_property(r ${target} IPLUG_COPY_AFTER_BUILD)
  if (r OR arg_FORCE)
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} ARGS "-E" "remove_directory" "${dest_dir}"
      COMMAND ${CMAKE_COMMAND} ARGS "-E" "copy_directory" "${src_dir}" "${dest_dir}"
      COMMENT "Copying ${target} to ${dest_dir}")
  endif()
endfunction(iplug_add_post_build_copy)

#[===[.rst:
.. code-block:: cmake

  iplug_setup_plugin(
    <target>
    [NAME <name>]
    [VERSION <version>]
    [GRAPHICS <backend> [api]])

``<target>``
  Plugin base target to configure.

``NAME``
  The name of the plugin. If unspecified, this defaults to the project name.

``VERSION``
  The plugin version. If unspecified, this defaults to the project version.

``GRAPHICS <backend> [api]``
  The ``GRAPHICS`` option selects the graphics backend. The options for
  `backend` are ``NanoVG``, ``Skia``, ``Custom``, or ``None``. NanoVG and Skia
  will use those libraries to implement the `IGraphics` backend. ``None``
  indicates the plugin has no custom UI, while ``Custom`` means the plugin has
  a GUI, but the developer will provide the implementation.

  For extra control the ``api`` option may be given as ``GL2``, ``GL3``, or ``CPU``.
  These extra options control specifically which rendering API the backend uses.
  Use ``_`` for the default api for a given backend.

#]===]
function(iplug_setup_plugin target)
  cmake_parse_arguments(arg "HAS_UI" "VERSION;NAME" "GRAPHICS" ${ARGN})

  if (NOT arg_NAME)
    set(arg_NAME ${CMAKE_PROJECT_NAME})
  endif()
  if (NOT arg_VERSION)
    set(arg_VERSION ${CMAKE_PROJECT_VERSION})
  endif()

  if (NOT arg_HAS_UI)
    # Determine default for arg_HAS_UI
    get_target_property(link_libs ${target} INTERFACE_LINK_LIBRARIES)

    set(arg_HAS_UI TRUE)
    if ("iPlug2_NoGraphics" IN_LIST link_libs)
      set(arg_HAS_UI FALSE)
    endif()
  endif()

  ## Parse graphics options ##

  # Default to NanoVG
  if (NOT arg_GRAPHICS)
    set(arg_GRAPHICS "NanoVG")
  endif()

  set(GUI0_OPTIONS NanoVG Skia Custom None)
  set(NANOVG_API_OPTIONS _ GL2 GL3)
  set(SKIA_API_OPTIONS _ GL2 GL3 CPU)
  list(GET arg_GRAPHICS 0 gui0)
  list(SUBLIST arg_GRAPHICS 1 1 gui_api)

  # Default api option
  if (NOT gui_api)
    set(gui_api "_")
  endif()

  if (NOT gui0 IN_LIST GUI0_OPTIONS)
    message(FATAL_ERROR "Invalid IGraphics backend ${gui0} - choices are ${GUI0_OPTIONS}")
  endif()

  # Checks for NanoVG
  if (gui0 STREQUAL "NanoVG")
    if (NOT gui_api IN_LIST NANOVG_API_OPTIONS)
      message(FATAL_ERROR "Invalid api for NanoVG ${gui_api} - choices are ${NANOVG_API_OPTIONS}")
    endif()
    # Default api for NanoVG is GL2
    if (gui_api STREQUAL "_")
      set(gui_api "GL2")
    endif()
  endif()

  # Checks for Skia
  if (gui0 STREQUAL "Skia")
    if (NOT gui_api IN_LIST SKIA_API_OPTIONS)
      message(FATAL_ERROR "Invalid api for Skia ${gui_api} - choices are ${SKIA_API_OPTIONS}")
    endif()
    # Default api for Skia is also CPU
    if (gui_api STREQUAL "_")
      set(gui_api "CPU")
    endif()
  endif()

  # Determine libraries to link to
  if (gui0 STREQUAL "None")
    set(gui_libs iPlug2_NoGraphics)
  elseif (gui0 STREQUAL "Custom")
    set(gui_libs iPlug2_CustomGraphics)
  else()
    set(gui_libs iPlug2_${gui0} iPlug2_${gui_api})
  endif()

  ## End parse graphics options ##

  set_target_properties(
    ${target}
    PROPERTIES
    IPLUG_PLUGIN_NAME ${arg_NAME}
    IPLUG_PLUGIN_VERSION ${arg_VERSION}
    IPLUG_PLUGIN_GRAPHICS "${gui_libs}"
  )
endfunction(iplug_setup_plugin)


#[===[.rst:
.. code-block:: cmake

  iplug_add_format(<base_target> <format>
    [TARGET <target>]
    [COPY_AFTER_BUILD]
    [PLUGIN_NAME <name>]
    [VERSION <major.minor.bugfix>]
    [GRAPHICS <NONE | SKIA_GL2 | SKIA_GL3 | SKIA_CPU | NANOVG_GL2 | NANOVG_GL3 | CUSTOM>])

Creates a non-interface target that builds the ``<base_target>`` for the given ``<format>``.
The ``<base_target>`` should be an interface so that the source gets re-built with different
configurations based on the plugin format.

``<format>``
  The output format, one of ``aax, app, au2, au3, lv2, vst2, vst3, web, wam``.

  Some output formats are only available with certain outputs. If an output format is
  not supported on the current platform CMake will output a warning and not create the target
  or try to load any dependencies for it. For example au2 and au3 are only available on Apple
  platforms, while web and wam are only available when using the Emscripten SDK.
  See the `Emscripten CMake SDK`_ for details on how to use Emscripten with CMake.

``TARGET <target>``
  Override the output target name. By default the output target will be ``${PLUG_NAME}_${format}``.

``COPY_AFTER_BUILD``
  After a plugin format builds successfully the plugin will be copied to a directory where
  hosts can locate it. This is for easier debugging.

.. _`Emscripten CMake SDK`: https://github.com/emscripten-core/emscripten/blob/main/cmake/Modules/Platform/Emscripten.cmake
#]===]
function(iplug_add_format base_target format)
  cmake_parse_arguments(arg "COPY_AFTER_BUILD" "TARGET" "" ${ARGN})

  # List of all valid plugin formats
  set(VALID_FORMATS "aax;app;au2;au3;lv2;vst2;vst3;web")
  # Directory to load for each format in VALID_FORMATS
  set(FORMAT_DIRS "AAX;APP;AUv2;AUv3;LV2;VST2;VST3;WEB")

  # Ensure the format is one of the valid options
  if (NOT ${format} IN_LIST VALID_FORMATS)
    message(FATAL_ERROR "Invalid plugin format ${format}")
  endif()

  # Ensure the format is valid on this platform by copying the list of
  # valid formats, then removing any invalid ones.
  set(ok_formats ${VALID_FORMATS})
  if (NOT IPLUG_OS MATCHES "Darwin")
    list(REMOVE_ITEM ok_formats "au2" "au3")
  elseif (NOT IPLUG_OS MATCHES "Linux")
    list(REMOVE_ITEM ok_formats "lv2")
  elseif (CMAKE_SYSTEM_NAME MATCHES "Emscripten")
    # Straight up override the valid formats
    set(ok_formats web)
  endif()
  # Check if the format is valid
  if (NOT ${format} IN_LIST ok_formats)
    message(STATUS "Plugin format ${format} not available on ${CMAKE_SYSTEM_NAME}, ignoring")
    return()
  endif()

  # Call iplug_setup_plugin() if the user hasn't already done so.
  get_target_property(plugin_name ${base_target} IPLUG_PLUGIN_NAME)
  # Specifically check the variable, not the string, so that we
  if (NOT plugin_name)
    iplug_setup_plugin(${base_target})
    # Re-get the plugin name
    get_target_property(plugin_name ${base_target} IPLUG_PLUGIN_NAME)
  endif()

  # Determine the output target
  set(target "${plugin_name}_${format}")
  if (arg_TARGET)
    set(target ${arg_TARGET})
  endif()

  # Automatically create target if required

  # if (NOT TARGET ${target})
  #   add_library(${target})
  #   if (${format} MATCHES "app")
  #     add_executable(${target} WIN32 MACOSX_BUNDLE)
  #   else()
  #     add_library(${target} MODULE)
  #   endif()
  # endif()

  # # Copy list of resources and other properties to the output target
  # iplug_copy_properties(${target} ${base_target}
  #   "IPLUG_RESOURCES;IPLUG_PLUGIN_NAME;IPLUG_PLUGIN_VERSION;IPLUG_PLUGIN_GRAPHICS")

  # # Link our output target to the base target
  # target_link_libraries(${target} PUBLIC ${base_target})

  # Dynamically load the configure command
  set(configure_command "iplug_configure_${format}")
  if (NOT COMMAND ${configure_command})
    # Get format index and convert it to format subdir
    list(FIND VALID_FORMATS ${format} format_index)
    list(GET FORMAT_DIRS ${format_index} format_subdir)
    # Load subdirectory with explicit binary directory because it's outside normal path.
    add_subdirectory(${IPLUG2_SDK_PATH}/IPlug/${format_subdir} ${CMAKE_BINARY_DIR}/IPlug/${format_subdir})
  endif()

  # Call the configure command
  cmake_language(CALL ${configure_command} ${base_target} ${target})

  # Platform-handling for all formats.
  if (IPLUG_OS MATCHES "Windows")
    # On Windows ours fonts are included in the RC file, meaning we need to include main.rc
    # in ALL our builds. Yay for platform-specific bundling!
    set(_res "${CMAKE_SOURCE_DIR}/resources/main.rc")
    iplug_target_add(${target} PUBLIC RESOURCE ${_res})
    source_group("Resources" FILES ${_res})

  elseif (IPLUG_OS MATCHES "Darwin")
    # For MacOS we make sure the output name is the same as the app name.
    # This is basically required for bundles.
    set_property(TARGET ${target} PROPERTY OUTPUT_NAME "${plugin_name}")

  elseif (IPLUG_OS MATCHES "Linux")
    # Nothing special here!

  endif()

endfunction()

