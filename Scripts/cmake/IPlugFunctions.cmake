cmake_minimum_required(VERSION 3.20)
include_guard(GLOBAL)
find_package(Embedc QUIET)

# Find ibtool on MacOS
bn_tern(IBTOOL_REQUIRED "REQUIRED" "" CMAKE_HOST_SYSTEM_NAME MATCHES "Darwin")
find_program(
  IBTOOL
  NAMES ibtool
  HINTS "/usr/bin" "${OSX_DEVELOPER_ROOT}/usr/bin"
  ${IBTOOL_REQUIRED}
)

# Python is required for everything, because we need to run cmutil.py
find_package(Python 3.8 REQUIRED COMPONENTS Interpreter)
# Find cmutil.py
find_path(
  cmutil_PATH
  NAMES cmutil.py
  PATHS ${IPLUG2_SDK_PATH}/Scripts ${CMAKE_CURRENT_LIST_DIR}/..
  DOC "Directory containing cmutil.py"
  REQUIRED
)
set(
  CALL_CMUTIL_PY
  WORKING_DIRECTORY "${cmutil_PATH}"
  OUTPUT_STRIP_TRAILING_WHITESPACE
  COMMAND_ERROR_IS_FATAL ANY
  COMMAND ${Python_EXECUTABLE} -c
  CACHE INTERNAL ""
)

# Define iplug-specific properties
define_property(TARGET PROPERTY IPLUG_PLUGIN_NAME
  BRIEF_DOCS "The name of the plugin/app"
  FULL_DOCS "The name of the plugin/app. If not specified it will default to the project name.")
define_property(TARGET PROPERTY IPLUG_PLUGIN_METADATA
  BRIEF_DOCS "Metadata about the plugin, stored as a json string"
  FULL_DOCS "
  This property exists both to make it easier to externally define metadata,
  as well as to consolidate what would otherwise be a large number of CMake properties.

  The following fields are available:
  - description: a description of the plugin
  - year: the copyright year
  - author: the author or manufacturer
  - copyright: the full copyright string, defaults to \"Copyright (c) <year> <author>\"
  - category: The plugin category/categories, used by hosts for organization.
    This uses values from CLAP (https://github.com/free-audio/clap/blob/main/include/clap/plugin-features.h)
    and converts them to other formats as appropriate.
  - url: The home page URL for the plugin
  - support_url: The support URL for the plugin, defaults to the home page URL
  ")
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

# List of valid plugin categories, sourced from plugin-features.h
set(IPLUG_VALID_PLUGIN_CATEGORIES
  # Main categories
  "instrument" "audio-effect" "note-effect" "note-detector" "analyzer"
  # Sub-categories - instrument
  "synthesizer" "sampler" "drum" "drum-machine"
  # Sub-categories - audio effect
  "filter" "phaser" "equalizer" "de-esser" "phase-vocoder" "granular" "frequency-shifter" "pitch-shifter"
  "distortion" "transient-shaper" "compressor" "expander" "gate" "limiter"
  "flanger" "chorus" "delay" "reverb" "tremolo" "glitch"
  # Sub-categories - misc
  "utility" "pitch-correction" "restoration"
  "multi-effects"
  "mixing" "mastering"
)
set_property(GLOBAL PROPERTY IPLUG_VALID_PLUGIN_CATEGORIES "${IPLUG_VALID_PLUGIN_CATEGORIES}")

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

function(iplug_set_install_paths format user_path system_path)
  set(IPLUG_${format}_USER_INSTALL_PATH "${user_path}" CACHE PATH
  "User-writeable path to install ${format} plugins for local development")
  set(IPLUG_${format}_SYSTEM_INSTALL_PATH "${system_path}" CACHE PATH
  "Path to install ${format} plugins to the system, potentially requiring administrator permissions")
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
  get_target_property(PLUGIN_META ${base_target} IPLUG_PLUGIN_METADATA)
  set(PLUGIN_FORMAT "${arg_FORMAT}")
  string(JSON PLUGIN_COPYRIGHT GET "${PLUGIN_META}" copyright)
  string(JSON PLUGIN_VERSION GET "${PLUGIN_META}" version)
  # Defaults to English
  string(JSON DEVELOPMENT_LANGUAGE GET "${PLUGIN_META}" dev_language)

  set(BUNDLE_PACKAGE_TYPE "BNDL")
  set(BUNDLE_SIGNATURE "PmBl")

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
    @ONLY
  )
endfunction()


function(iplug_guess_file_types VAR)
  string(SHA1 argn_hash "${ARGN}")
  set(cache_key file_types_${argn_hash})
  if(NOT DEFINED ${cache_key})
    # Guess file types for all files
    execute_process(
      ${CALL_CMUTIL_PY} "import cmutil; cmutil.do_guess_file_types('${ARGN}')"
      OUTPUT_VARIABLE file_types
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
  if (NOT "${method}" MATCHES "(rc)|(xcode)|(embedc)|(copy)")
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
        set(ln "\"${fn}\" TTF")
      elseif(kind MATCHES ",icon,")
        set(ln "${next_id} ICON")
        math(EXPR next_id "${next_id} + 1")
      elseif(kind MATCHES ",image,")
        set(ln "\"${fn}\" IMAGE")
      else()
        set(ln "\"${fn}\" OCTET")
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

.. code-block:: cmake
  iplug_configure_helper(
    TARGET <target>
    [GET_VARS <format>]
    [PLATFORM_SETUP]
    [MAIN_RC]
    [COPY_PROPERTIES <target>]
    [POST_BUILD_COPY <destination>]
  )

Combines several pieces of helper code for the ``iplug_configure_*`` functions
into one place. This function makes certain assumptions about what variables
exist, and what are safe to set so it shouldn't be used by external code.

``TARGET``
  The target to operate on for various actions. Mostly required.

``GET_VARS``
  Sets `plugin_name`, `gui_libraries`, `output_dir`, and ``resource_dir`` in
  the parent scope. These are common variables used by most/all output formats.
  The ``<format>`` argument is the lowercased format name.

``COPY_PROPERTIES``
  Copies ``IPLUG_RESOURCES`` and ``IPLUG_COPY_AFTER_BUILD`` from the base plugin
  target to ``<target>``.

``PLATFORM_SETUP``
  Does platform/OS specific setup.

``MAIN_RC``
  On Windows, this will configure main.rc and resource.h for the named target, copying
  them to the correct directory and linking them to the target. Does nothing on other
  platforms.

``POST_BUILD_COPY``
  If given, this will setup a copy of the target's output directory (with resources)
  into the given destination. This is usually for debugging.

``CONVERT_XIB``
  Configure a .xib file, and then convert it to a .nib file.

``MAKE_BUNDLE``
  :param: plist - Path to the .plist file
  On Apple platforms, this sets the target as a bundle, and uses the given
  .plist path for the bundle's plist. Does nothing on non-Apple platforms.

#]===]
function(iplug_configure_helper)
  if (NOT TARGET ${base_plugin})
    message(FATAL_ERROR "iplug_configure_util called but 'base_plugin' not defined.\n
    This is an error in the format's configure function.")
  endif()
  cmake_parse_arguments(
    PARSE_ARGV 0 arg
    "PLATFORM_SETUP;COPY_PROPERTIES;MAIN_RC"
    "TARGET;GET_VARS;POST_BUILD_COPY;CONVERT_XIB;MAKE_BUNDLE;SET_EXTENSION"
    ""
  )

  set(target "${arg_TARGET}")

  if (arg_GET_VARS)
    set(format ${arg_GET_VARS})
    get_target_property(plugin_name ${base_plugin} IPLUG_PLUGIN_NAME)
    get_target_property(gui_libraries ${base_plugin} IPLUG_PLUGIN_GRAPHICS)
    set(output_dir "${CMAKE_BINARY_DIR}/${plugin_name}/${format}")
    set(resource_dir "${output_dir}/resources")
    set(binary_subdir "${CMAKE_CURRENT_BINARY_DIR}/${target}.dir")

    # Set these in the parent scope
    set(output_dir "${output_dir}" PARENT_SCOPE)
    set(resource_dir "${resource_dir}" PARENT_SCOPE)
    set(plugin_name ${plugin_name} PARENT_SCOPE)
    set(gui_libraries ${gui_libraries} PARENT_SCOPE)
    set(binary_subdir "${binary_subdir}" PARENT_SCOPE)
  endif()

  if (arg_COPY_PROPERTIES)
    iplug_copy_properties(${target} ${base_plugin} "IPLUG_COPY_AFTER_BUILD;IPLUG_RESOURCES")
  endif()

  #--------------------------------------------------------
  # OS specific setup
  if(arg_MAIN_RC AND IPLUG_OS MATCHES "Windows")
    # Configure main.rc and resource.h
    # N.B. Assumes ${binary_subdir} is already set in parent scope.
    set(app_main_rc ${binary_subdir}/main.rc)
    set(app_resource_h ${binary_subdir}/resource.h)
    set(config_in_dir ${IPLUG2_SDK_PATH}/IPlug/Resources)
    set(icon_in_file ${CMAKE_CURRENT_SOURCE_DIR}/resources/${plugin_name}.ico)

    # Copy .ico to temp dir
    file(MAKE_DIRECTORY ${binary_subdir})
    file(COPY_FILE ${icon_in_file} ${binary_subdir}/${plugin_name}.ico ONLY_IF_DIFFERENT)
    # Config variables
    get_target_property(PLUGIN_META ${base_target} IPLUG_PLUGIN_METADATA)
    get_target_property(PLUGIN_VERSION ${base_target} VERSION)
    string(REPLACE "." "," PLUGIN_VERSION_COMMAS "${PLUGIN_VERSION}")
    get_target_property(PLUGIN_NAME ${base_target} IPLUG_PLUGIN_NAME)
    string(JSON PLUGIN_COPYRIGHT GET "${PLUGIN_META}" copyright)

    # Do the configure
    configure_file(${config_in_dir}/main.rc.in ${app_main_rc} @ONLY)
    configure_file(${config_in_dir}/resource.h ${app_resource_h} COPYONLY)
    # Add as sources
    target_sources(${target} PRIVATE ${app_main_rc} ${app_resource_h})
    target_include_directories(${target} PRIVATE ${binary_subdir})
    source_group("IPlug" FILES ${app_main_rc} ${app_resource_h})
  endif()

  if(arg_CONVERT_XIB AND IPLUG_OS MATCHES "(Darwin)|(IOS)")
    # Do some path operations
    list(GET arg_CONVERT_XIB 0 xib_in_path)
    cmake_path(GET xib_in_path FILENAME xib_fn)
    cmake_path(SET xib_bin_path NORMALIZE "${resource_dir}/${xib_fn}")
    cmake_path(REPLACE_EXTENSION xib_bin_path ".xib")
    cmake_path(GET xib_path STEM LAST_ONLY stem)
    set(nib_path "${resource_dir}/${stem}.nib")
    # Configure
    get_target_property(PLUGIN_NAME ${base_target} IPLUG_PLUGIN_NAME)
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

  if(arg_PLATFORM_SETUP)
    if(IPLUG_OS MATCHES "Darwin")
      # For MacOS we make sure the output name is the same as the app name.
      # This is basically required for bundles.
      set_property(TARGET ${target} PROPERTY OUTPUT_NAME "${plugin_name}")

    else()
      # Nothing for other platforms yet
    endif()
  endif()

  if(arg_MAKE_BUNDLE AND APPLE)
    set_target_properties(${target} PROPERTIES
      BUNDLE TRUE
      MACOSX_BUNDLE TRUE
      # Argument is the plist
      MACOSX_BUNDLE_INFO_PLIST "${arg_MAKE_BUNDLE}"
    )
  endif()

  if(arg_SET_EXTENSION)
    get_property(is_bundle TARGET ${target} PROPERTY MACOSX_BUNDLE)
    set(ext "${arg_SET_EXTENSION}")
    set(bundle_ext "")
    if(is_bundle)
      set(bundle_ext "${ext}")
      set(ext "")
    endif()

    set_target_properties(${target} PROPERTIES
      BUNDLE_EXTENSION "${bundle_ext}"
      PREFIX ""
      SUFFIX "${ext}")
  endif()

  if(arg_POST_BUILD_COPY)
    get_target_property(r ${target} IPLUG_COPY_AFTER_BUILD)
    # Assume ${output_dir} exists from previous call in parent function
    if(r)
      set(dest_dir "${arg_POST_BUILD_COPY}")
      add_custom_command(
        TARGET ${target} POST_BUILD
        COMMAND ${CMAKE_COMMAND} ARGS "-E" "remove_directory" "${dest_dir}"
        COMMAND ${CMAKE_COMMAND} ARGS "-E" "copy_directory" "${output_dir}" "${dest_dir}"
        COMMENT "Copied ${output_dir} to ${dest_dir}"
      )
    endif()
  endif()

endfunction(iplug_configure_helper)

#[===[.rst:

Setup the base INTERFACE target for an iPlug2 plugin with required options.

.. code-block:: cmake
  iplug_setup_plugin(
    <base_target>
    FORMATS [``ALL`` | formats...]
    [GRAPHICS <backend> [api]]
    [COPY_AFTER_BUILD]

    [NAME <name>]
    [VERSION <version>]
    [CLASS_NAME <cxx class>]
    [DESCRIPTION <description>]
    [EMAIL <support email>]
    [AUTHOR <author>]
    [AUTHOR_ID <author id>]
    [YEAR <year>]
    [COPYRIGHT <copyright>]
    [CATEGORY category1,category2,...]
    [URL <home page url>]
    [SUPPORT_URL <support page url>]
    [MANUAL_URL <manual url>]
    [MIDI_IN <bool>]
    [MIDI_OUT <bool>]
    [DOES_MPE <bool>]
    [EXTRA_METADATA <key1> <value1> <key2> <value2> ...]
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


Metadata Options
^^^^^^^^^^^^^^^^

``NAME``
  The name of the plugin. If unspecified, this defaults to the project name.

``VERSION``
  The plugin version. If unspecified, this defaults to the project version.

``CLASS_NAME``
  The C++ class name of the main plugin class. This will override the default, which is the same
  as the project name.

``DESCRIPTION``
  A description of the plugin. If unspecified, defaults to the project description, or an empty string.

``AUTHOR``
  The plugin author, or the company who makes it. Defaults to an empty string.

``AUTHOR_ID``
  The plugin manufacturer's ID. This must be a 4 character ASCII string. If not provided,
  it will default to the first 4 characters of `AUTHOR`_. If ``AUTHOR`` is an empty string,
  an error will be reported.

``YEAR``
  The year the plugin was released. Defaults to the current year.

``COPYRIGHT``
  A custom copyright string. The default is "Copyright (c) <year> <author>".

``CATEGORY``
  The plugin category/categories, used by hosts for organization.
  This uses values from CLAP (https://github.com/free-audio/clap/blob/main/include/clap/plugin-features.h).

``EMAIL``
  The support email for the plugin.

``URL``
  The primary URL for information about the plugin.

``SUPPORT_URL``
  The URL for getting support for the plugin. Defaults to the primary URL.

``MANUAL_URL``
  The URL of a manual (usually .pdf) for the plugin.

``MIDI_IN``
  Boolean (default FALSE) which controls if this plugin has MIDI input.

``MIDI_OUT``
  Boolean (default FALSE) which controls if this plugin has MIDI output.

``DOES_MPE``
  Boolean (default FALSE) which controls if the plugin does MPE or not.

``ALLOW_HOST_RESIZE``
  Boolean (default FALSE), allow the host to resize the plugin's GUI.

``EXTRA_METADATA``
  Additional key-value pairs of metadata options to be added to the metadata json.

#]===]
function(iplug_setup_plugin base_target)
  set(one_value_args
    # Main options, with defaults pulled from the project.
    # These MUST have non-empty valid values
    VERSION NAME CLASS_NAME AUTHOR_ID
    # These options are basically pure metadata, and don't change how the plugin works at all
    DESCRIPTION AUTHOR YEAR COPYRIGHT EMAIL URL SUPPORT_URL MANUAL_URL
    # These options change how the plugin functions, but have reasonable defaults.
    CATEGORY MIDI_IN MIDI_OUT DOES_MPE ALLOW_HOST_RESIZE
  )
  cmake_parse_arguments(
    PARSE_ARGV 1 arg
    "COPY_AFTER_BUILD"
    "${one_value_args}"
    "GRAPHICS;FORMATS;EXTRA_METADATA"
  )

  if (NOT arg_FORMATS)
    message(SEND_ERROR "In iplug_setup_plugin the FORMATS argument is required")
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
  # Append NOTFOUND value to make sure we have at least 2 items so getting
  # items 1 and 2 always works.
  list(APPEND arg_GRAPHICS NOTFOUND)

  set(GUI0_OPTIONS NanoVG Skia Custom None)
  set(NANOVG_API_OPTIONS GL2 GL3)
  set(SKIA_API_OPTIONS GL2 GL3 CPU)
  list(GET arg_GRAPHICS 0 gui0)
  list(GET arg_GRAPHICS 1 gui_api)

  if (NOT gui0 IN_LIST GUI0_OPTIONS)
    message(FATAL_ERROR "Invalid IGraphics backend ${gui0} - choices are ${GUI0_OPTIONS}")
  endif()

  # Checks for NanoVG
  if (gui0 STREQUAL "NanoVG")
    # Default api for NanoVG is GL2
    bn_fallback(gui_api "${gui_api}" "GL2")
    if (NOT gui_api IN_LIST NANOVG_API_OPTIONS)
      message(FATAL_ERROR "Invalid api for NanoVG ${gui_api} - choices are \"\";${NANOVG_API_OPTIONS}")
    endif()
  endif()

  # Checks for Skia
  if (gui0 STREQUAL "Skia")
    # Try to find Skia package
    find_package(Skia REQUIRED)
    # Default api for Skia is CPU
    bn_fallback(gui_api "${gui_api}" "CPU")
    if (NOT gui_api IN_LIST SKIA_API_OPTIONS)
      message(FATAL_ERROR "Invalid api for Skia ${gui_api} - choices are \"\";${SKIA_API_OPTIONS}")
    endif()
  endif()

  # Determine libraries to link to.
  # Also, set plug_has_ui for the configure_file later.
  set(plug_has_ui 1)
  if (gui0 STREQUAL "None")
    set(gui_libs iPlug2_NoGraphics)
    set(plug_has_ui 0)
  elseif (gui0 STREQUAL "Custom")
    set(gui_libs iPlug2_CustomGraphics)
  else()
    set(gui_libs iPlug2_${gui0} iPlug2_${gui_api})
  endif()

  message(VERBOSE "GUI libraries for ${base_target} are ${gui_libs}")

  # End parse graphics options
  #========================================================

  #========================================================
  # Parse metadata options, with defaults.

  # Build up plugin metadata options, with fallbacks and default values.
  string(TIMESTAMP current_year "%Y" UTC)
  bn_fallback(plugin_name "${arg_NAME}" "${CMAKE_PROJECT_NAME}")
  bn_fallback(plug_version "${arg_VERSION}" "${CMAKE_PROJECT_VERSION}" "0.0.1")
  bn_fallback(plug_class_name "${arg_CLASS_NAME}" "${CMAKE_PROJECT_NAME}")
  bn_fallback(plug_description "${arg_DESCRIPTION}" "${CMAKE_PROJECT_DESCRIPTION}" "@@ @@")
  bn_fallback(plug_email "${arg_EMAIL}" "spam@me.com")
  bn_fallback(plug_author "${arg_AUTHOR}" "@@ @@")
  # Author ID falls-back to first 4 characters of author, or an empty string.
  # If it's an empty string, we'll check for that later.
  string(SUBSTRING "${plug_author}" 0 4 plug_author_4)
  bn_fallback(plug_author_id "${arg_AUTHOR_ID}" "${plug_author_4}" "@@ @@")
  bn_fallback(plug_year "${arg_YEAR}" "${current_year}")
  bn_fallback(plug_copyright "${arg_COPYRIGHT}" "@@ Copyright (c) ${plug_year} ${plug_author} @@")
  bn_fallback(plug_category "${arg_CATEGORY}" "@@ @@")
  bn_fallback(plug_url "${arg_URL}" "${CMAKE_PROJECT_HOMEPAGE_URL}" "@@ @@")
  bn_fallback(plug_support_url "${arg_SUPPORT_URL}" "${plug_url}" "@@ @@")
  bn_fallback(plug_manual_url "${arg_MANUAL_URL}" "@@ @@")

  # Parse boolean options with defaults
  set(bool_option_vars plug_midi_in plug_midi_out plug_does_mpe plug_allow_host_resize)
  set(bool_option_defaults FALSE FALSE FALSE FALSE)
  foreach(out_var default_val IN ZIP_LISTS bool_option_vars bool_option_defaults)
    # Convert local variable name into argument name
    string(TOUPPER "${out_var}" arg_var)
    string(REPLACE "PLUG_" "arg_" arg_var "${arg_var}")
    # Parse option from argument or fallback
    bn_fallback(${out_var} "${${arg_var}}" "${default_val}")
  endforeach()

  # Convert the booleans to 1/0 strings so we can #define them easier
  foreach(out_var IN LISTS bool_option_vars)
    bn_tern(${out_var} "1" "0" "${${out_var}}")
  endforeach()

  # Verify author id
  string(LENGTH "${plug_author_id}" author_id_len)
  if(NOT ${author_id_len} EQUAL 4)
    message(WARNING "The author_id must be a 4-character ASCII string. Using 'Test' as the fallback.")
    set(plug_author_id "Test")
  endif()

  execute_process(
    ${CALL_CMUTIL_PY} "import cmutil; cmutil.do_hex_version('${plug_version}')"
    OUTPUT_VARIABLE plug_version_hex
  )

  # Put them into a json dictionary
  bn_json_dict(
    meta
    "name" "${plugin_name}"
    version "${plug_version}"
    version_hex "${plug_version_hex}"
    class_name "${plug_class_name}"
    author "${plug_author}"
    author_id "${plug_author_id}"
    category "${plug_category}"
    copyright "${plug_copyright}"
    description "${plug_description}"
    year "${plug_year}"
    dev_language "English"
    email "${plug_email}"
    url "${plug_url}"
    support_url "${plug_support_url}"
    midi_in "${plug_midi_in}"
    midi_out "${plug_midi_out}"
    does_mpe "${plug_does_mpe}"
    allow_host_resize "${plug_allow_host_resize}"
    # By being last, values from EXTRA_METADATA can override values we set
    ${arg_EXTRA_METADATA}
  )
  string(REPLACE "\n" "" meta "${meta}")
  # Set it in the cache for debugging, and maybe later we can use it without re-computing?
  set(${base_target}_metadata "${meta}" CACHE INTERNAL "" FORCE)

  set(plug_unique_id "PmBl")
  string(MAKE_C_IDENTIFIER "${plug_author}" plug_author_csafe)

  configure_file(
    ${IPLUG2_SDK_PATH}/IPlug/Resources/config.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/${plugin_name}.bin/config.h
    @ONLY
  )

  # End parse metadata options
  #=========================================================

  # Set our own properties on the target
  set_target_properties(
    ${base_target}
    PROPERTIES
    VERSION ${plug_version}
    IPLUG_PLUGIN_METADATA "${meta}"
    IPLUG_PLUGIN_NAME "${plugin_name}"
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
