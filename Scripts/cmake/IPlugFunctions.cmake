cmake_minimum_required(VERSION 3.20)
include_guard(GLOBAL)

bn_make_python_venv(
  IPLUG_PYENV_EXECUTABLE
  VERSION 3.8
  DIRECTORY "${IPLUG2_SDK_PATH}/.venv"
  PROMPT "iplug"
  ADD_TO_PATH
  PACKAGES "${CMAKE_CURRENT_LIST_DIR}/../pyplug"
)

find_package(Embedc QUIET)

# Find ibtool on MacOS
bn_tern(IBTOOL_REQUIRED "REQUIRED" "" CMAKE_HOST_SYSTEM_NAME MATCHES "Darwin")
find_program(
  IBTOOL
  NAMES ibtool
  HINTS "/usr/bin" "${OSX_DEVELOPER_ROOT}/usr/bin"
  ${IBTOOL_REQUIRED}
)

# Define iplug-specific properties
define_property(TARGET PROPERTY IPLUG_PLUGIN_NAME
  BRIEF_DOCS "The name of the plugin/app"
  FULL_DOCS "The name of the plugin/app. If not specified it will default to the project name.")
define_property(TARGET PROPERTY IPLUG_PLUGIN_METADATA
  BRIEF_DOCS "Metadata about the plugin, stored as a json string"
  FULL_DOCS  "This combines an otherwise-large set of different properties into one, and it can be cached.")
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
  cmake_parse_arguments(PARSE_ARGV 2 cfg "" "" "INCLUDE;SOURCE;DEFINE;OPTION;LINK;LINK_DIR;DEPEND;FEATURE;RESOURCE")
  #message("CALL iplug_add_target ${target}")
  if (cfg_UNUSED)
    message("Unused arguments ${cfg_UNUSED}" FATAL_ERROR)
  endif()

  get_target_property(ttype ${target} TYPE)
  bn_tern(_set_type "INTERFACE" ${set_type} ${ttype} STREQUAL "INTERFACE_LIBRARY")
  set(BN_RESOURCE_PROPERTY IPLUG_RESOURCES)
  bn_target_add(${target} ${_set_type} ${ARGN})
endfunction()

function(iplug_source_tree target)
  cmake_parse_arguments(arg "" "PREFIX" "" ${ARGN})
  if (NOT TARGET ${target})
    return()
  endif()
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

#[=[.rst
.. code-block:: cmake
  iplug_format_helper(SETUP FORMAT <format> ...)
  iplug_format_helper(FORMAT <format> TARGET <target> ...)

Combines several pieces of helper code for the ``iplug_configure_*`` functions
into one place. This function makes certain assumptions about what variables
exist, and what are safe to set so it shouldn't be used by external code.

``FORMAT``
  Lowercase format name.

Setup Options
^^^^^^^^^^^^^

``SETUP``
  Setup cache variables and global properties.
``USER_INSTALL_PATH``
  bn_case() list of arguments for selecting the user install path.
``SYSTEM_INSTALL_PATH``
  bn_case() list of arguments for selecting the system install path.
``SUFFIX``
  bn_case() list of arguments for selecting the library or bundle suffix.
``RESOURCE_METHOD``
  bn_case() list of resource bundling methods.
``CUSTOM_XML``
  Custom XML to be included in the generated .plist.
``PLIST_VARIABLES``
  List of <key>=<value> items that will set/override variables when
  configuring the .plist file.
``INSTALL_SUBDIR``
  The directory inside either `USER_INSTALL_PATH` where the plugin should
  be copied to. Defaults to `${plugin_name}.${format}`.

Target Options
^^^^^^^^^^^^^^

``TARGET``
  The target to apply options on, required argument for the following options.
``COPY_PROPERTIES``
  Copies `IPLUG_RESOURCES, IPLUG_COPY_AFTER_BUILD` from the base plugin target to <target>.
``GENERATE_PLIST``
  If on MacOS/iOS, generate a .plist file for this target.
``MAKE_BUNDLE``
  If on MacOS/iOS, make this target into a bundle.
``SET_NAME``
  Set the output name, prefix, and suffix for the target.
``MAIN_RC``
  On Windows, this will configure main.rc and resource.h for the named target, copying them to the
  correct directory and linking them to the target. Does nothing on other platforms.
``CONVERT_XIB``
  Configure a .xib file, and then convert it to a .nib file.
``POST_BUILD_COPY``
  Add a post-build command to copy the target's output directory (with resources)
  into `${USER_INSTALL_PATH}/${INSTALL_SUBDIR}`.
``TARGET_COMMON``
  Implies `COPY_PROPERTIES, GENERATE_PLIST, MAKE_BUNDLE, SET_NAME, MAIN_RC, POST_BUILD_COPY`.
  Useful for non-split builds.

Misc Options
^^^^^^^^^^^^

``GET_VARS``
  Sets `plugin_name`, `gui_libraries`, `output_dir`, and ``resource_dir`` in
  the parent scope. These are common variables used by most/all output formats.

]=]
function(iplug_format_helper)
  cmake_parse_arguments(
    PARSE_ARGV 0 a13
    "SETUP;APPLY;MAKE_BUNDLE;GENERATE_PLIST;MAIN_RC;POST_BUILD_COPY;GET_VARS;COPY_PROPERTIES;TARGET_COMMON"
    "FORMAT;TARGET;CUSTOM_XML;INSTALL_SUBDIR;CONVERT_XIB"
    "USER_INSTALL_PATH;SYSTEM_INSTALL_PATH;SUFFIX;RESOURCE_METHOD;PLIST_VARIABLES"
  )

  string(TOUPPER "${a13_FORMAT}" format_cap)
  set(format ${a13_FORMAT})
  set(prop_key "iplug_${a13_FORMAT}")

  # Set global and cache variables based on the arguments and system settings.
  if(a13_SETUP)
    # Determine user install path, always set a cache value even if empty
    if(a13_USER_INSTALL_PATH)
      bn_case(tmp "${IPLUG_OS}" ${a13_USER_INSTALL_PATH})
    else()
      set(tmp "")
    endif()
    set(
      IPLUG_${format_cap}_USER_INSTALL_PATH "${tmp}" CACHE PATH
      "User-writeable path to install ${format_cap} plugins for local development")

    # Determine the system install path, even if empty
    if(a13_SYSTEM_INSTALL_PATH)
      bn_case(tmp "${IPLUG_OS}" ${a13_SYSTEM_INSTALL_PATH})
    else()
      set(tmp "")
    endif()
    set(
      IPLUG_${format_cap}_SYSTEM_INSTALL_PATH "${tmp}" CACHE PATH
      "Path to install ${format_cap} plugins to the system,
      potentially requiring administrator permissions")

    # Determine the suffix
    if(a13_SUFFIX)
      bn_case(tmp "${IPLUG_OS}" ${a13_SUFFIX})
      set_property(GLOBAL PROPERTY ${prop_key}_suffix "${tmp}")
    endif()

    # Determine the resource method, default to "auto"
    if(a13_RESOURCE_METHOD)
      bn_case(tmp "${IPLUG_OS}" ${a13_RESOURCE_METHOD})
    else()
      set(tmp "auto")
    endif()
    set_property(GLOBAL PROPERTY ${prop_key}_resource_method "${tmp}")

    # Record any custom XML to add to the .plist before formatting.
    bn_tern(tmp "${a13_CUSTOM_XML}" "" a13_CUSTOM_XML)
    set_property(GLOBAL PROPERTY ${prop_key}_custom_xml "${tmp}")

    # Record plist variables
    bn_fallback(tmp "${a13_PLIST_VARIABLES}" "@@ @@")
    set_property(GLOBAL PROPERTY ${prop_key}_plist_variables "${tmp}")

    #
    bn_fallback(tmp "${a13_INSTALL_SUBDIR}" "\${plugin_name}.${format}")
    set_property(GLOBAL PROPERTY ${prop_key}_install_subdir "${tmp}")
  endif()

  if (a13_GET_VARS)
    get_target_property(plugin_name ${base_plugin} IPLUG_PLUGIN_NAME)
    get_target_property(gui_libraries ${base_plugin} IPLUG_PLUGIN_GRAPHICS)
    set(output_dir "${CMAKE_BINARY_DIR}/${plugin_name}/${format}")
    if(CMAKE_GENERATOR MATCHES "Visual Studio")
      set(binary_subdir "${CMAKE_CURRENT_BINARY_DIR}/${target}.dir")
    else()
      set(binary_subdir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${target}.dir")
    endif()
    set(resource_dir "${output_dir}/resources")
    if(IPLUG_OS MATCHES "Darwin|iOS")
      # Bundle mode for resources
      set(resource_dir "${output_dir}/Contents/Resources")
    endif()

    # Convert clap category to the appropriate category for the format
    get_target_property(meta ${base_plugin} IPLUG_PLUGIN_METADATA)
    string(JSON plug_category ERROR_VARIABLE err GET "${meta}" "category")
    string(JSON plug_format_category ERROR_VARIABLE err GET "${meta}" "category_${format}")
    if(err)
      set(tmp "${plug_category}")
    else()
      set(tmp "${plug_format_category}")
    endif()
    set(plugin_sub_category "${tmp}" PARENT_SCOPE)

    # Set these in the parent scope
    set(output_dir "${output_dir}" PARENT_SCOPE)
    set(resource_dir "${resource_dir}" PARENT_SCOPE)
    set(plugin_name "${plugin_name}" PARENT_SCOPE)
    set(gui_libraries "${gui_libraries}" PARENT_SCOPE)
    set(binary_subdir "${binary_subdir}" PARENT_SCOPE)
    # Exit early
    return()
  endif()

  # Early exit if TARGET option isn't given
  if(NOT a13_TARGET)
    return()
  endif()
  # Make sure we have required variables defined
  if(NOT (DEFINED base_plugin AND DEFINED binary_subdir AND DEFINED resource_dir))
    message(SEND_ERROR "iplug_format_helper() called in invalid context")
  endif()

  # Variables for when we have TARGET
  set(target "${a13_TARGET}")
  set(a13_plist_output ${binary_subdir}/Info.plist)
  get_target_property(PLUGIN_NAME ${base_plugin} IPLUG_PLUGIN_NAME)

  # Enable common options for non-split target builds
  if(a13_TARGET_COMMON)
    set(a13_COPY_PROPERTIES ON)
    set(a13_GENERATE_PLIST ON)
    set(a13_MAKE_BUNDLE ON)
    set(a13_SET_NAME ON)
    set(a13_POST_BUILD ON)
    set(a13_MAIN_RC ON)
  endif()

  if (a13_COPY_PROPERTIES)
    iplug_copy_properties(${target} ${base_plugin} "IPLUG_COPY_AFTER_BUILD;IPLUG_RESOURCES")
  endif()

  # Generate .plist
  if(a13_GENERATE_PLIST AND APPLE)
    get_property(a13_custom_xml GLOBAL PROPERTY ${prop_key}_custom_xml)
    get_property(a13_plist_variables GLOBAL PROPERTY ${prop_key}_plist_variables)

    get_target_property(PLUGIN_META ${base_plugin} IPLUG_PLUGIN_METADATA)
    set(PLUGIN_FORMAT "${a13_FORMAT}")
    string(JSON PLUGIN_COPYRIGHT GET "${PLUGIN_META}" copyright)
    string(JSON PLUGIN_VERSION GET "${PLUGIN_META}" version)
    string(JSON DEVELOPMENT_LANGUAGE GET "${PLUGIN_META}" dev_language)
    set(BUNDLE_PACKAGE_TYPE "BNDL")
    set(BUNDLE_SIGNATURE "PmBl")

    # Load plist variable overrides
    foreach(entry IN_LIST a13_plist_variables)
      if("${entry}" MATCHES "^([A-Za-z0-9_])=(.+)$")
        set(${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
      else()
        message(FATAL_ERROR "Invalid plist variable '${entry}'")
      endif()
    endforeach()

    # Interpolate custom XML
    string(CONFIGURE "${a13_custom_xml}" FORMAT_CUSTOM_XML @ONLY)

    # Configure the file
    configure_file(
      ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/Basic-Info.plist.in
      ${a13_plist_output}
      @ONLY NEWLINE_STYLE UNIX
    )
    # Return early
    return()
  endif()

  if(a13_MAKE_BUNDLE AND APPLE)
    set_target_properties(${target} PROPERTIES
      BUNDLE TRUE
      MACOSX_BUNDLE TRUE
      MACOSX_BUNDLE_INFO_PLIST "${a13_plist_output}"
    )
  endif()

  if(a13_SET_NAME)
    get_property(a13_suffix GLOBAL PROPERTY ${prop_key}_suffix)
    get_property(a13_is_bundle TARGET ${target} PROPERTY MACOSX_BUNDLE)
    bn_tern(suffix_property "BUNDLE_EXTENSION" "SUFFIX" a13_is_bundle)

    set_target_properties(${target} PROPERTIES
      # Make sure the output name is the same as the app name.
      # This is basically required for bundles, but good for all formats.
      OUTPUT_NAME "${PLUGIN_NAME}"
      PREFIX ""
      # Set either the bundle extension or the file suffix
      ${suffix_property} "${a13_suffix}"
    )
  endif()

  if(a13_MAIN_RC AND IPLUG_OS MATCHES "Windows")
    # Configure main.rc and resource.h
    # N.B. Assumes ${binary_subdir}, ${base_plugin}, ${plugin_name} are already set in parent scope.
    set(app_main_rc ${binary_subdir}/main.rc)
    set(app_resource_h ${binary_subdir}/resource.h)
    set(icon_in_file ${CMAKE_CURRENT_SOURCE_DIR}/resources/${PLUGIN_NAME}.ico)

    # Copy .ico to temp dir
    file(MAKE_DIRECTORY ${binary_subdir})
    file(COPY_FILE ${icon_in_file} ${binary_subdir}/${PLUGIN_NAME}.ico ONLY_IF_DIFFERENT)
    # Config variables
    get_target_property(PLUGIN_META ${base_plugin} IPLUG_PLUGIN_METADATA)
    get_target_property(PLUGIN_VERSION ${base_plugin} VERSION)
    string(REPLACE "." "," PLUGIN_VERSION_COMMAS "${PLUGIN_VERSION}")

    string(JSON PLUGIN_COPYRIGHT GET "${PLUGIN_META}" copyright)

    # Do the configure
    configure_file(${CMAKE_CURRENT_FUNCTION_LIST_DIR}/main.rc.in ${app_main_rc} @ONLY)
    configure_file(${CMAKE_CURRENT_FUNCTION_LIST_DIR}/resource.h ${app_resource_h} COPYONLY)
    # Add as sources
    target_sources(${target} PRIVATE ${app_main_rc} ${app_resource_h})
    target_include_directories(${target} PRIVATE ${binary_subdir})
    source_group("IPlug" FILES ${app_main_rc} ${app_resource_h})
  endif()

  if(a13_CONVERT_XIB AND IPLUG_OS MATCHES "(Darwin)|(IOS)")
    # Do some path operations
    list(GET a13_CONVERT_XIB 0 xib_in_path)
    cmake_path(GET xib_in_path FILENAME xib_fn)
    cmake_path(SET xib_bin_path NORMALIZE "${resource_dir}/${xib_fn}")
    cmake_path(REPLACE_EXTENSION xib_bin_path ".xib")
    cmake_path(GET xib_path STEM LAST_ONLY stem)
    set(nib_path "${resource_dir}/${stem}.nib")
    # Configure
    get_target_property(PLUGIN_NAME ${base_plugin} IPLUG_PLUGIN_NAME)
    configure_file(${xib_in_path} ${xib_bin_path} @ONLY NEWLINE_STYLE UNIX)
    # Compile .xib to .nib
    add_custom_command(
      OUTPUT ${nib_path}
      COMMAND ${IBTOOL} "--errors" "--warnings" "--notices" "--compile" "${nib_path}" "${xib_bin_path}"
      MAIN_DEPENDENCY "${xib_bin_path}"
      VERBATIM
    )
    set_property(TARGET ${target} APPEND PROPERTY RESOURCE ${nib_path})
  endif()

  if(a13_POST_BUILD_COPY)
    get_property(a13_do_copy TARGET ${target} PROPERTY IPLUG_COPY_AFTER_BUILD)
    get_property(a13_install_subdir GLOBAL PROPERTY ${prop_key}_install_subdir)
    set(a13_install_superdir "${IPLUG_${format_cap}_USER_INSTALL_PATH}")
    if("${a13_do_copy}" AND "${a13_install_superdir}" AND "${a13_install_subdir}")
      # Assume ${output_dir} exists from parent function
      set(dest_dir "${a13_install_superdir}/${a13_install_subdir}")
      add_custom_command(
        TARGET ${target} POST_BUILD
        COMMAND ${CMAKE_COMMAND} "-E" "remove_directory" "${dest_dir}"
        COMMAND ${CMAKE_COMMAND} "-E" "copy_directory" "${output_dir}" "${dest_dir}"
        COMMENT "Copied ${output_dir} to ${dest_dir}"
      )
    endif()
  endif()
endfunction(iplug_format_helper)

function(iplug_guess_file_types VAR)
  string(SHA1 argn_hash "${ARGN}")
  set(cache_key file_types_${argn_hash})
  if(NOT DEFINED ${cache_key})
    # Guess file types for all files
    execute_process(
      COMMAND ${IPLUG_PYENV_EXECUTABLE} -c "import iplug; iplug.do_guess_file_types('${ARGN}')"
      OUTPUT_STRIP_TRAILING_WHITESPACE
      OUTPUT_VARIABLE file_types
      COMMAND_ERROR_IS_FATAL ANY
    )
    set(${cache_key} ${file_types} CACHE INTERNAL "")
  endif()
  set(${VAR} ${${cache_key}} PARENT_SCOPE)
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
  cmake_parse_arguments(PARSE_ARGV 2 arg "PREFER_EMBED" "METHOD" "")

  # Parse the embed method to use
  string(TOLOWER "${arg_METHOD}" method)
  if ("${method}" STREQUAL "auto" OR "${method}" STREQUAL "")
    # Select the resource bundling method
    get_property(is_bundle TARGET ${target} PROPERTY BUNDLE)
    if (CMAKE_GENERATOR MATCHES "Visual Studio")
      set(method "rc")
    elseif (CMAKE_GENERATOR STREQUAL "Xcode")
      set(method "xcode")
    elseif (arg_PREFER_EMBED AND NOT is_bundle)
      set(method "embedc")
    else()
      set(method "copy")
    endif()
  endif()
  if (NOT "${method}" MATCHES "rc|xcode|embedc|copy")
    message(FATAL_ERROR "Parameter METHOD has invalid value ${arg_METHOD}")
  endif()

  # Get the resources we're dealing with
  get_property(resources TARGET ${target} PROPERTY IPLUG_RESOURCES)

  #--------------------------------------------------------
  # Xcode embeds files in bundles automatically
  if (method STREQUAL "xcode")
    # Copy IPLUG_RESOURCES to the actual RESOURCE property
    set_target_properties(${target} PROPERTIES RESOURCE ${resources})
    # On Xcode we mark each file as non-compiled
    foreach (res ${resources})
      get_filename_component(fn "${res}" NAME)
      set(file_type "file")
      if (fn MATCHES ".*\\.xib$")
        set(file_type "file.xib")
      endif()
      set_property(SOURCE ${res} PROPERTY XCODE_LAST_KNOWN_FILE_TYPE ${file_type})
    endforeach()

  #--------------------------------------------------------
  # Generate a main.rc file containing the resources to embed.
  # Ususally used only on Windows.
  elseif (method STREQUAL "rc")
    # Contents of the generated RC file
    set(rc_content "")
    # Auto-incrementing ID for resources that use integer IDs as keys
    set(next_id 39000)

    iplug_guess_file_types(file_types ${resources})
    # Process each resources
    foreach (res kind IN ZIP_LISTS resources file_types)
      # Get the filename for use in generating the .rc file
      cmake_path(GET res FILENAME fn)

      if(kind MATCHES ",font,")
        set(ln "\"${fn}\" FONT")
      elseif(kind MATCHES ",icon,")
        set(ln "${next_id} ICON")
        math(EXPR next_id "${next_id} + 1")
      elseif(kind MATCHES ",image,")
        set(ln "\"${fn}\" IMAGE")
      else()
        set(ln "\"${fn}\" RCDATA")
      endif()
      string(APPEND rc_content "${ln} \"${res}\"\n")
    endforeach()
    set(rc_path ${target}.dir/bundled.rc)
    file(
      CONFIGURE OUTPUT "${rc_path}"
      CONTENT "${rc_content}"
      @ONLY
      NEWLINE_STYLE WIN32
    )
    target_sources(${target} PRIVATE ${rc_path})

  #--------------------------------------------------------
  # Copy files into the resources/ directory relative to
  # the target's output.
  elseif (method STREQUAL "copy")
    # Guess file types for all
    iplug_guess_file_types(file_types ${resources})

    foreach (res kind IN ZIP_LISTS resources file_types)
      # Get the filename so and file extension so we can pick the right destination.
      cmake_path(GET res FILENAME fn)

      # Default is to simply copy the file, some file types may need special
      # handling in which case they set copy to FALSE.
      set(copy TRUE)

      if (kind MATCHES ",font,")
        set(dst "${res_dir}/fonts/${fn}")
      elseif (kind MATCHES ",image,")
        set(dst "${res_dir}/img/${fn}")
      elseif (kind MATCHES ",xib,")
        if (NOT IBTOOL)
          message(WARNING "ibtool not found, cannot compile .xib files")
          continue()
        endif()
        # Compile .xib to .nib
        cmake_path(GET res STEM LAST_ONLY stem)
        set(dst "${res_dir}/${stem}.nib")
        add_custom_command(
          OUTPUT ${dst}
          COMMAND ${IBTOOL} "--errors" "--warnings" "--notices" "--compile" "${dst}" "${res}"
          MAIN_DEPENDENCY "${res}"
          VERBATIM
        )
        set(copy FALSE)
      else()
        # Default destination
        set(dst "${res_dir}/${fn}")
      endif()

      if (copy)
        add_custom_command(
          OUTPUT "${dst}"
          COMMAND ${CMAKE_COMMAND} -E copy_if_different "${res}" "${dst}"
          COMMENT "Copying resource to ${dst}"
          MAIN_DEPENDENCY "${res}"
          VERBATIM
        )
      endif()

      # Make the target depend on the resource output so it gets copied.
      target_sources(${target} PRIVATE "${dst}")
      source_group("Resources" FILES ${dst})
    endforeach()

  #--------------------------------------------------------
  # Use embedc to convert resources into C files and embed
  # the data as constant byte arrays directly.
  elseif (method STREQUAL "embedc")
    find_package(Embedc REQUIRED QUIET)
    list(SORT resources COMPARE STRING)
    embedc_add_files(${target} FILES ${resources})
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

Setup the base INTERFACE target for an iPlug2 plugin with required options.

.. code-block:: cmake
  iplug_setup_plugin(
    <base_target>
    FORMATS [``ALL`` | formats...]
    [GRAPHICS backend[+api]]
    [COPY_AFTER_BUILD]
    CONFIG <yaml>
  )

Main Arguments
^^^^^^^^^^^^^^

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

``GRAPHICS``
  Select the graphics backend. Arguments are formatted `<backend>+<api>` where `+api` is optional.
  The backend options are `NanoVG`, `Skia`, `Custom`, or `None`. NanoVG and Skia will use those
  libraries to implement the `IGraphics` backend. ``None`` indicates the plugin has no custom UI,
  while ``Custom`` means the plugin has a GUI, but the developer will provide the implementation.

  For extra control the ``api`` option may be given as ``GL2``, ``GL3``, or ``CPU``.
  These extra options control specifically which rendering API the backend uses.
  Use ``_`` for the default api for a given backend.

``COPY_AFTER_BUILD``
  For the output formats that support it, the plugin will be copied to the default
  user-writable location where DAWs and other tools will search for plugins of
  that format.

``CONFIG``
  A set of "key: value" pairs, one per line. See the `Config Options`_ section for a list
  of valid options. Using CMake's literal strings (e.g. [[my text]]) is recommended.
  Technically, this is a yaml dictionary, so indentation does matter slightly.

Config Options
^^^^^^^^^^^^^^

``name``
  The name of the plugin. If unspecified, this defaults to the project name.

``version``
  The plugin version. If unspecified, this defaults to the project version.

``class_name``
  The C++ class name of the main plugin class. This will override the default, which is the same
  as the project name.

``description``
  A description of the plugin. If unspecified, defaults to the project description, or an empty string.

``author``
  The plugin author, or the company who makes it. Defaults to an empty string.

``author_id``
  The plugin manufacturer's ID. This must be a 4 character ASCII string. If not provided,
  it will default to the first 4 characters of `AUTHOR`_. If ``AUTHOR`` is an empty string,
  an error will be reported.

``year``
  The year the plugin was released. Defaults to the current year.

``copyright``
  A custom copyright string. The default is "Copyright (c) <year> <author>".

``category``
  The plugin category/categories, used by hosts for organization.
  This uses values from CLAP (https://github.com/free-audio/clap/blob/main/include/clap/plugin-features.h).

``email``
  The support email for the plugin.

``url``
  The primary URL for information about the plugin.

``support_url``
  The URL for getting support for the plugin. Defaults to the primary URL.

``manual_url``
  The URL of a manual (usually .pdf) for the plugin.

``midi_in``
  Boolean (default FALSE) which controls if this plugin has MIDI input.

``midi_out``
  Boolean (default FALSE) which controls if this plugin has MIDI output.

``does_mpe``
  Boolean (default FALSE) which controls if the plugin does MPE or not.

``allow_host_resize``
  Boolean (default FALSE), allow the host to resize the plugin's GUI.

``ui_width``
  The default width of the UI.
``ui_height``
  The default height of the UI.
``ui_fps``
  The target FPS for the UI.

#]===]
function(iplug_setup_plugin base_target)
  cmake_parse_arguments(
    PARSE_ARGV 1 arg
    "COPY_AFTER_BUILD"
    "CONFIG"
    "GRAPHICS;FORMATS"
  )

  if (NOT arg_FORMATS)
    message(SEND_ERROR "In iplug_setup_plugin the FORMATS argument is required")
  endif()
  if (NOT arg_COPY_AFTER_BUILD)
    set(arg_COPY_AFTER_BUILD OFF)
  endif()

  #========================================================
  # Parse graphics options

  # Use the global/cli flag, then the argument, then the default.
  bn_fallback(graphics_api "${IPLUG_FORCE_GRAPHICS}" "${arg_GRAPHICS}" "nanovg+gl2")
  string(TOLOWER "${graphics_api}" graphics_api)
  if(NOT "${graphics_api}" MATCHES "(nanovg|skia|custom|none)([+](gl2|gl3|cpu|auto))?")
    message(FATAL_ERROR "Invalid IGraphics backend ${arg_GRAPHICS} - choices are NanoVG, Skia, Custom, None")
  endif()
  set(gui0 "${CMAKE_MATCH_1}")
  set(gui_api "${CMAKE_MATCH_3}")
  # Auto defaults to empty string so bn_fallback works
  if(gui_api STREQUAL "auto")
    set(gui_api "")
  endif()

  # Check NanoVG options
  if(gui0 STREQUAL "nanovg")
    bn_fallback(gui_api "${gui_api}" "gl2")
    if(NOT "${gui_api}" MATCHES "gl2|gl3")
      message(FATAL_ERROR "Invalid api for NanoVG ${gui_api} - choices are auto, GL2, GL3")
    endif()
  endif()

  # Check Skia options
  if(gui0 STREQUAL "skia")
    bn_fallback(gui_api "${gui_api}" "cpu")
    if(NOT "${gui_api}" MATCHES "gl2|gl3|cpu")
      message(FATAL_ERROR "Invalid api for Skia ${gui_api} - choices are auto, GL2, GL3, CPU")
    endif()
    # Try to find Skia package
    find_package(Skia REQUIRED)
  endif()

  # Set plug_has_ui for the configure_file later.
  set(plug_has_ui 1)
  # Determine libraries to link to.
  if (gui0 STREQUAL "none")
    set(gui_libs iPlug2_NoGraphics)
    set(plug_has_ui 0)
  elseif (gui0 STREQUAL "custom")
    set(gui_libs iPlug2_CustomGraphics)
  else()
    set(gui_libs iPlug2_${gui0} iPlug2_${gui_api})
  endif()

  message(VERBOSE "GUI libraries for ${base_target} are ${gui_libs}")

  # End parse graphics options
  #========================================================

  # Parse config options
  bn_cache_call(
    CACHE_VARIABLE "${base_target}_metadata"
    OUTPUT_VARIABLE "meta"
    DID_RERUN meta_changed
    CALL iplug_build_config meta "${arg_CONFIG}"
  )

  # Load all config variables from the json with a plug_ prefix
  bn_json_to_variables(plug JSON "${meta}")
  set(plugin_name "${plug_name}")

  if(meta_changed)
    configure_file(
      ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/config.h.in
      ${CMAKE_CURRENT_BINARY_DIR}/${plug_name}.bin/config.h
      @ONLY
    )
  endif()

  # End parse metadata options
  #=========================================================

  # Set our own properties on the target
  set_target_properties(
    ${base_target}
    PROPERTIES
    VERSION ${plug_version}
    IPLUG_PLUGIN_METADATA "${meta}"
    IPLUG_PLUGIN_NAME "${plug_name}"
    IPLUG_PLUGIN_GRAPHICS "${gui_libs}"
    IPLUG_COPY_AFTER_BUILD ${arg_COPY_AFTER_BUILD}
  )

  #========================================================
  # Generate output targets for the desired formats

  set(all_formats FALSE)
  set(output_formats ${arg_FORMATS})
  if ("ALL" IN_LIST arg_FORMATS)
    set(output_formats "${IPLUG_VALID_FORMATS}")
    set(all_formats TRUE)
  endif()

  # Load global property
  get_property(IPLUG_ALL_FORMATS GLOBAL PROPERTY IPLUG_ALL_FORMATS)
  set(IPLUG_LOADED_FORMATS "$CACHE{IPLUG_LOADED_FORMATS}")
  set(IPLUG_VALID_FORMATS "$CACHE{IPLUG_VALID_FORMATS}")

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
      # Don't message if a format is not loaded, but we were doing all formats.
      if (NOT all_formats)
        message(WARNING "Output format '${format}' failed to load, skipping")
      endif()
      # Either way, skip this format
      continue()
    endif()

    # Determine the output target
    set(target "${plugin_name}_${format}")
    # Call the configure command to setup the plugin target(s).
    cmake_language(CALL "iplug_configure_${format}" ${base_target} ${target})
  endforeach()

  # For CMake, files have to be organized on a per-directory or per-target basis,
  # it's not 100% clear. Either way, if we repeat the organization steps it works consistently.
  iplug_source_tree(iPlug2_Core PREFIX "IPlug")
  iplug_source_tree(iPlug2_IGraphicsCore PREFIX "IPlug/IGraphics")
  iplug_source_tree(iPlug2_Synth PREFIX "IPlug/Extras/Synth")
  iplug_source_tree(iPlug2_GL2 PREFIX "IPlug/IGraphics")
  iplug_source_tree(iPlug2_GL3 PREFIX "IPlug/IGraphics")

  iplug_source_tree(iPlug2_APP PREFIX "IPlug/APP")
  iplug_source_tree(iPlug2_AUv2 PREFIX "IPlug/AUv2")
  iplug_source_tree(iPlug2_AUv3 PREFIX "IPlug/AUv3")
  iplug_source_tree(iPlug2_CLAP PREFIX "IPlug/CLAP")
  iplug_source_tree(iPlug2_LV2 PREFIX "IPlug/LV2")
  iplug_source_tree(iPlug2_LV2_DSP PREFIX "IPlug/LV2")
  iplug_source_tree(iPlug2_LV2_UI PREFIX "IPlug/LV2")
  iplug_source_tree(iPlug2_VST2 PREFIX "IPlug/VST2")
  iplug_source_tree(iPlug2_VST3 PREFIX "IPlug/VST3")

endfunction(iplug_setup_plugin)

function(iplug_build_config VAR config_in)
  set(build_config_cmd "
import iplug; iplug.cm_build_config(\"\"\"${arg_CONFIG}\"\"\", {
  'name': '''${CMAKE_PROJECT_NAME}''',
  'version': '''${CMAKE_PROJECT_VERSION}''',
  'description': '''${CMAKE_PROJECT_DESCRIPTION}''',
  'url': '''${CMAKE_PROJECT_HOMEPAGE_URL}''',
  'has_ui': '${plug_has_ui}',
})")
  execute_process(
    COMMAND ${IPLUG_PYENV_EXECUTABLE} -c "${build_config_cmd}"
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
    OUTPUT_VARIABLE meta
  )
  set(${VAR} "${meta}" PARENT_SCOPE)
endfunction()
