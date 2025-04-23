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

#[===[.rst

.. parsed-literal::

  iplug_list(`CONTAINS_ALL` <list> <item> [<items>...] <output-variable>)
  iplug_list(`CONTAINS_ANY` <list> <item> [<items>...] <output-variable>)

.. signature::
  iplug_list(CONTAINS_ALL <list> <item> [<items>...] <output-variable>)

  Returns ``TRUE`` if the list contains all the listed items, ``FALSE`` otherwise.

.. signature::
  iplug_list(CONTAINS_ANY <list> <item> [<items>...] <output-variable>)

  Returns ``TRUE`` if the list contains any of the given items, ``FALSE`` otherwise.

#]===]
function(iplug_list command)
  if (command STREQUAL "CONTAINS_ALL" OR command STREQUAL "CONTAINS_ANY")
    # Same setup for both
    set(items "${ARGN}")
    list(POP_FRONT items list_var)
    list(POP_BACK items out_var)

    if (command STREQUAL "CONTAINS_ALL")
      # Default to true, fail if missing item
      set(ok TRUE)
      foreach (item IN LISTS items)
        if (NOT "${item}" IN_LIST ${list_var})
          set(ok FALSE)
          break()
        endif()
      endforeach()
    else()
      # Default to false, succeed on found item
      set(ok FALSE)
      foreach (item IN LISTS items)
        if ("${item}" IN_LIST ${list_var})
          set(ok TRUE)
          break()
        endif()
      endforeach()
    endif()

    set(${out_var} ${ok} PARENT_SCOPE)
    return()

  else()
    message(FATAL_ERROR "Unknown command '${command}'")
  endif()
endfunction(iplug_list)

function(iplug_source_tree target)
  cmake_parse_arguments(arg "" "PREFIX" "" ${ARGN})
  get_target_property(_tmp ${target} INTERFACE_SOURCES)
  if ("${_tmp}" STREQUAL "_tmp-NOTFOUND")
    return()
  endif()
  if (arg_PREFIX)
    source_group(${arg_PREFIX} FILES ${_tmp})
  else()
    source_group(TREE ${IPLUG2_SDK_PATH} PREFIX "IPlug" FILES ${_tmp})
  endif()
endfunction()

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
    cmake_path(NORMAL_PATH pt OUTPUT_VARIABLE pt2)
    if (EXISTS ${pt2})
      iplug_ternary(is_dir 1 0 IS_DIRECTORY ${pt2})
      #message("Found path ${pt} and is_dir=${is_dir}")

      if ( (arg_FILE AND NOT ${is_dir}) OR (arg_DIR AND ${is_dir}) )
        set(out ${pt2})
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

function(iplug_file_in_binary_dir target filename out_var)
  get_target_property(bin_dir ${target} BINARY_DIR)
  set(${out_var} "${bin_dir}/${target}.dir/${filename}" PARENT_SCOPE)
endfunction()

function(iplug_configure_basic_plist base_target)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "FORMAT;CUSTOM_XML;OUTPUT" "")

  # Check required arguments
  if (NOT arg_OUTPUT)
    message(SEND_ERROR "Argument OUTPUT is required")
  endif()
  if (NOT arg_FORMAT)
    message(SEND_ERROR "Argument FORMAT is required")
  endif()

  get_target_property(PLUGIN_NAME ${base_target} IPLUG_PLUGIN_NAME)
  get_target_property(PLUGIN_VERSION ${base_target} IPLUG_PLUGIN_VERSION)
  set(PLUGIN_FORMAT "${arg_FORMAT}")
  set(BUNDLE_PACKAGE_TYPE "BNDL")

  # TODO determine some way to allow the developer to override or set these values
  set(DEVELOPMENT_LANGUAGE "English")
  set(BUNDLE_SIGNATURE "PmBl")
  set(PLUGIN_COPYRIGHT "Copyright 2020 Acme Inc")

  # List of additional XML lines to put in the file
  set(custom "")

  # Format specific custom XML
  set(FORMAT_CUSTOM_XML "")
  if (arg_CUSTOM_XML)
    string(CONFIGURE "${arg_CUSTOM_XML}" FORMAT_CUSTOM_XML @ONLY)
  endif()

  if (arg_FORMAT STREQUAL "aax")
    list(APPEND custom
      "<key>LSMultipleInstancesProhibited</key> <string>true</string>"
      "<key>LSPrefersCarbon</key> <false/>"
      "<key>NSAppleScriptEnabled</key> <string>No</string>"
    )
    set(BUNDLE_PACKAGE_TYPE "TDMw")
    # Not sure if this is required
    set(BUNDLE_SIGNATURE "PTul")
  endif()

  if (arg_FORMAT STREQUAL "au3")
    set(BUNDLE_PACKAGE_TYPE "XPC!")
  endif()

  if (arg_FORMAT STREQUAL "app")
    list(APPEND custom
      "<key>LSApplicationCategoryType</key> <string>public.app-category.music</string>"
      "<key>NSMainNibFile</key> <string>${PLUGIN_NAME}-macOS-MainMenu</string>"
      "<key>NSPrincipalClass</key> <string>SWELLApplication</string>"
      "<key>CFBundleIconFile</key> <string>${PLUGIN_NAME}.icns</string>"
    )
  endif()

  list(JOIN custom "\n" CUSTOM_XML)

  configure_file(
    ${IPLUG2_SDK_PATH}/IPlug/resource/Basic-Info.plist.in
    ${arg_OUTPUT}
    NEWLINE_STYLE UNIX
    @ONLY)
endfunction()



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

      if (copy)
        add_custom_command(
          OUTPUT "${dst}"
          COMMAND ${CMAKE_COMMAND} ARGS "-E" "copy" "${res}" "${dst}"
          COMMENT "Copying resource to ${dst}"
          MAIN_DEPENDENCY "${res}"
        )
      endif()

      # Make the target depend on the resource output so it gets copied.
      target_sources(${target} PRIVATE "${dst}")
      source_group("Resources" FILES ${dst})


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
      COMMENT "Copied ${src_dir} to ${dest_dir}"
    )
  endif()
endfunction(iplug_add_post_build_copy)

#[===[.rst:

.. code-block:: cmake

  iplug_list_to_js_list(<dst_var> <items...>)

Convert a CMake list into a JS list of strings. The output variable will be a
single string that appears as a JavaScript list. This is used for WAM output.

`<dst_var>`
  Destination variable name

`<items...>`
  List of items to convert. If you have an existing list variable
  it should be included without quotes.

#]===]
function(iplug_list_to_js_list dst_var)
  # Convert web exports into a JS string array
  set(tmp_list ${ARGN})
  list(JOIN tmp_list "','" tmp)
  set(${dst_var} "['${tmp}']" PARENT_SCOPE)
endfunction(iplug_list_to_js_list)

#[===[.rst:

.. code-block:: cmake
  iplug_configure_helper(
    `GET_VARS`_ <format>
    `COPY_PROPERTIES`_ <target>
  )

Combines several pieces of helper code for the ``iplug_configure_*`` functions
into one place. This function makes certain assumptions about what variables
exist, and what are safe to set.

`GET_VARS`
  Sets `plugin_name`, `gui_libraries`, `output_dir`, and ``resource_dir`` in
  the parent scope. These are common variables used by most/all output formats.
  The ``<format>`` argument is the lowercased format name.

`COPY_PROPERTIES`
  Copies ``IPLUG_RESOURCES`` and ``IPLUG_COPY_AFTER_BUILD`` from the base plugin
  target to ``<target>``.

#]===]
function(iplug_configure_helper)
  if (NOT TARGET ${base_plugin})
    message(FATAL_ERROR "iplug_configure_util called but 'base_plugin' not defined.\n
    This is an error in the format's configure function.")
  endif()
  cmake_parse_arguments(arg "" "GET_VARS;COPY_PROPERTIES" "" ${ARGN})

  if (arg_GET_VARS)
    set(format ${arg_GET_VARS})
    get_target_property(plugin_name ${base_plugin} IPLUG_PLUGIN_NAME)
    get_target_property(gui_libraries ${base_plugin} IPLUG_PLUGIN_GRAPHICS)
    set(output_dir "${CMAKE_BINARY_DIR}/${plugin_name}/${format}")
    set(resource_dir "${output_dir}/resources")

    # Set these in the parent scope
    set(output_dir "${output_dir}" PARENT_SCOPE)
    set(resource_dir "${resource_dir}" PARENT_SCOPE)
    set(plugin_name ${plugin_name} PARENT_SCOPE)
    set(gui_libraries ${gui_libraries} PARENT_SCOPE)
  endif()

  if (arg_COPY_PROPERTIES)
    set(target ${arg_COPY_PROPERTIES})
    iplug_copy_properties(${target} ${base_plugin} "IPLUG_COPY_AFTER_BUILD;IPLUG_RESOURCES")
  endif()
endfunction(iplug_configure_helper)


# Clear the cache of loaded modules
set(_iplug_load_module_seen "" CACHE INTERNAL "" FORCE)

#[===[.rst

Attempt to load a module, allowing the module to check if it can load successfully.
This is similar to ``find_package()`` but it doesn't assume that ``${module_name}_FOUND``
being set in the cache means there's no work to do. Modules may create new functions,
targets, etc. It's safe to call the function multiple times, as it will only attempt
to load a module once.

#]===]
function(iplug_load_module module_name)
  cmake_parse_arguments(arg2 "" "OPTIONAL;ERROR_MESSAGE" "" ${ARGN})

  set(known_modules $CACHE{_iplug_load_module_seen})

  # Check if we've tried to load the module already. We specifically check
  # our module list instead of a cache variable, since the cache variables persist
  # through each re-build but the module list is explicity cleared.
  if ("${module_name}" IN_LIST known_modules)
    return()
  endif()
  # Update the module list so we know we've seen this module.
  list(APPEND known_modules "${module_name}")
  set(_iplug_load_module_seen ${known_modules} CACHE INTERNAL "" FORCE)

  # Default error message
  if (NOT arg2_ERROR_MESSAGE)
    set(arg2_ERROR_MESSAGE "Failed to load module ${module_name}")
  endif()
  # Default OPTIONAL to false
  if (NOT DEFINED arg2_OPTIONAL)
    set(arg2_OPTIONAL FALSE)
  endif()

  set(extra_error "")

  # Try to include the module
  include(${module_name} OPTIONAL RESULT_VARIABLE mod_found)
  # If we succeeded, but ${module_name}_FOUND is not set, then we still failed
  if (NOT mod_found)
    message(WARNING "Module ${module_name} not found; ${CMAKE_MODULE_PATH}")
  endif()
  if (mod_found AND NOT ${module_name}_FOUND)
    set(mod_found FALSE)
    # Allow modules to add an extra error message
    if (DEFINED ${module_name}_ERROR)
      set(extra_error ": ${${module_name}_ERROR}")
    endif()
  endif()

  # Set the result in the cache, force-overriding exisitng values
  set(${module_name}_FOUND ${mod_found} CACHE BOOL "" FORCE)

  # Now this will trigger if we failed for any reason
  if (NOT mod_found)
    # If arg_OPTIONAL is set, then warn but don't fail the full build
    iplug_ternary(msg_status NOTICE SEND_ERROR arg2_OPTIONAL)
    message(${msg_status} "${arg2_ERROR_MESSAGE}${extra_error}")
    return()
  endif()
endfunction(iplug_load_module)


#[===[.rst:

Setup the base INTERFACE target for an iPlug2 plugin with required options.

.. code-block:: cmake
  iplug_setup_plugin(
    <base_target>
    FORMATS [``ALL`` | formats...]
    [NAME <name>]
    [VERSION <version>]
    [GRAPHICS <backend> [api]]
    [COPY_AFTER_BUILD])

``<base_target>``
  Plugin base target to configure. This target MUST be an INTERFACE.

``FORMATS``
  The list of output formats to build for this target. One or more of
  ``aax, app, au2, au3, lv2, vst2, vst3, web, wam, clap``. If the option ``ALL``
  is given, output for all formats supported on this platform.

  Some output formats are only available with certain outputs. If an output format is
  not supported on the current platform CMake will output a warning and not create the target
  or try to load any dependencies for it. For example au2 and au3 are only available on Apple
  platforms, while web and wam are only available when using the Emscripten SDK.
  See the `Emscripten CMake SDK`_ for details on how to use Emscripten with CMake.

  The formats will generate library and executable targets named "<name>_<format>".
  Some formats may generate more than one target, depending on the requirements.

``NAME``
  The name of the plugin. If unspecified, this defaults to the project name.

``VERSION``
  The plugin version. If unspecified, this defaults to the project version.

``GRAPHICS``
  The ``GRAPHICS`` option selects the graphics backend. The options for
  `backend` are ``NanoVG``, ``Skia``, ``Custom``, or ``None``. NanoVG and Skia
  will use those libraries to implement the `IGraphics` backend. ``None``
  indicates the plugin has no custom UI, while ``Custom`` means the plugin has
  a GUI, but the developer will provide the implementation.

  For extra control the ``api`` option may be given as ``GL2``, ``GL3``, or ``CPU``.
  These extra options control specifically which rendering API the backend uses.
  Use ``_`` for the default api for a given backend.

``COPY_AFTER_BUILD``
  For the output formats that support it, the plugin will be copied to the default
  user-writable location where DAWs and other tools will search for plugins of
  that format.

#]===]
function(iplug_setup_plugin base_target)
  cmake_parse_arguments(arg "COPY_AFTER_BUILD" "VERSION;NAME" "GRAPHICS;FORMATS" ${ARGN})

  if (NOT arg_FORMATS)
    message(SEND_ERROR "In iplug_setup_plugin the FORMATS argument is required")
  endif()
  if (NOT arg_NAME)
    set(arg_NAME ${CMAKE_PROJECT_NAME})
  endif()
  if (NOT arg_VERSION)
    set(arg_VERSION ${CMAKE_PROJECT_VERSION})
  endif()
  if (NOT arg_COPY_AFTER_BUILD)
    set(arg_COPY_AFTER_BUILD OFF)
  endif()

  #========================================================
  # Parse graphics options

  # Default to NanoVG
  if (NOT arg_GRAPHICS)
    set(arg_GRAPHICS "NanoVG")
  endif()
  # Append _ to make sure we have at least 2 items so getting
  # items 1 and 2 always works.
  list(APPEND arg_GRAPHICS "_")

  set(GUI0_OPTIONS NanoVG Skia Custom None)
  set(NANOVG_API_OPTIONS _ GL2 GL3)
  set(SKIA_API_OPTIONS _ GL2 GL3 CPU)
  list(GET arg_GRAPHICS 0 gui0)
  list(GET arg_GRAPHICS 1 gui_api)

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

  message(VERBOSE "GUI libraries for ${base_target} are ${gui_libs}")

  # End parse graphics options
  #========================================================

  # On Windows, we automatically include main.rc and resource.h
  if (WIN32)
    # On Windows ours fonts are included in the RC file, meaning we need to include main.rc
    # in ALL our builds. Yay for platform-specific bundling!
    get_target_property(plugin_src_dir ${base_target} SOURCE_DIR)
    set(_src
      ${plugin_src_dir}/resources/main.rc
      ${plugin_src_dir}/resources/resource.h
    )
    target_sources(${base_target} INTERFACE ${_src})
    source_group(Resources FILES ${_src})
  endif()

  set_target_properties(
    ${base_target}
    PROPERTIES
    IPLUG_PLUGIN_NAME ${arg_NAME}
    IPLUG_PLUGIN_VERSION ${arg_VERSION}
    IPLUG_PLUGIN_GRAPHICS "${gui_libs}"
    IPLUG_COPY_AFTER_BUILD ${arg_COPY_AFTER_BUILD}
  )

  #========================================================
  # Generate output targets for the desired formats

  set(output_formats ${arg_FORMATS})
  if ("ALL" IN_LIST arg_FORMATS)
    set(output_formats "${IPLUG_VALID_FORMATS}")
  endif()

  foreach (format IN LISTS output_formats)
    # Check that the format is known, valid for this platform, and loaded successfully
    if (NOT "${format}" IN_LIST IPLUG_ALL_FORMATS)
      message(SEND_ERROR "Invalid output format '${format}'")
    endif()
    if (NOT "${format}" IN_LIST IPLUG_VALID_FORMATS)
      message(VERBOSE "Skipping output format '${format}'")
      continue()
    endif()
    if (NOT "${format}" IN_LIST IPLUG_LOADED_FORMATS)
      message(WARNING "Output format '${format}' failed to load, skipping")
      continue()
    endif()

    # Determine the output target
    set(target "${arg_NAME}_${format}")

    # Call the configure command to setup the plugin target(s).
    cmake_language(CALL "iplug_configure_${format}" ${base_target} ${target})

    # Platform-handling for all formats.
    # This happens *after* calling the configure command so that the target exists.
    if (IPLUG_OS MATCHES "(Windows)|(Linux)")
      # Nothing special here!

    elseif (IPLUG_OS MATCHES "Darwin")
      # For MacOS we make sure the output name is the same as the app name.
      # This is basically required for bundles.
      set_property(TARGET ${target} PROPERTY OUTPUT_NAME "${plugin_name}")

    endif()
  endforeach()

  # For CMake, files have to be organized on a per-directory or per-target basis,
  # it's not 100% clear. Either way, if we repeat the organization steps it works consistently.
  iplug_source_tree(iPlug2_Core PREFIX "IPlug")
  iplug_source_tree(iPlug2_IGraphicsCore PREFIX "IPlug/IGraphics")
  iplug_source_tree(iPlug2_Synth PREFIX "IPlug/Extras/Synth")
  iplug_source_tree(iPlug2_GL2 PREFIX "IPlug/IGraphics")
  iplug_source_tree(iPlug2_GL3 PREFIX "IPlug/IGraphics")

  iplug_source_tree(iPlug2_APP PREFIX "IPlug/APP")
  iplug_source_tree(iPlug2_CLAP PREFIX "IPlug/CLAP")
  iplug_source_tree(iPlug2_LV2 PREFIX "IPlug/LV2")
  iplug_source_tree(iPlug2_LV2_DSP PREFIX "IPlug/LV2")
  iplug_source_tree(iPlug2_LV2_UI PREFIX "IPlug/LV2")
  iplug_source_tree(iPlug2_VST2 PREFIX "IPlug/VST2")
  iplug_source_tree(iPlug2_VST3 PREFIX "IPlug/VST3")

endfunction(iplug_setup_plugin)
