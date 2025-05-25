cmake_minimum_required(VERSION 3.24)
include_guard(GLOBAL)
include(FindPackageHandleStandardArgs)

include(BnFunctions OPTIONAL RESULT_VARIABLE BnFunctions_FOUND)

if(NOT EMBEDC_COMMAND)
  find_program(EMBEDC_COMMAND NAMES embedc)
endif()
if(NOT EMBEDC_COMMAND)
  find_package(Python 3.8 COMPONENTS Interpreter)
  find_file(
    EMBEDC_PY_PATH embedc.py
    PATHS
      ${CMAKE_CURRENT_LIST_DIR}
      ${CMAKE_CURRENT_LIST_DIR}/..
    DOC "Path to embedc.py"
  )
  set(EMBEDC_COMMAND "${Python_EXECUTABLE} ${EMBEDC_PY_PATH}" CACHE STRING "")
endif()

find_package_handle_standard_args(
  Embedc # Package name
  REQUIRED_VARS Python_FOUND BnFunctions_FOUND EMBEDC_COMMAND
)

# Exit early if we don't have all dependencies
if (NOT Embedc_FOUND)
  return()
endif()

define_property(TARGET PROPERTY EMBEDC_FILES
  BRIEF_DOCS "List of converted C files that will be bundled for a target using embedc.py"
  FULL_DOCS "See brief doc")

#[===[.rst

Embed files in the target as byte arrays. All embedded resources will be comined
into a single array with names, so the files can be found, like in a ZIP file.

.. parsed-literal::

  embedc_add_files(<target> [DIR <default_dir>] FILES <files...>)

``<target>``
  The target to embed resources into, as generated C files.

``DIR``
  Set the default embed directory for the listed files. Files with explicit
  directories or renames will not be overridden.

``FILES``
  List of files to embed. To have the file be in a specific "directory" when
  embedding, use the form `<embed_dir>/=<file_path>`. To rename the file, use
  `<renamed_path>=<file_path>`. See `embedc.py --help` for more.

Example
^^^^^^^

.. code-block:: cmake

  add_library(my_resources STATIC)
  # Add all images into the img/ directory
  embedc_add_files(
    my_resources
    DIR img/
    FILES assets/img/*.png
  )
  # Add specific resources
  embedc_add_files(
    my_resources
    FILES
      # This goes into the "font/" directory
      font/=assets/font/Roboto-Regular.ttf
      # Embed path: "license/zlib.txt"
      license/=thirdparty/licenses/zlib.txt
      # Embed path: "license/libpng2.txt", due to explicit rename
      license/libpng2.txt=thirdparty/licenses/libpng.txt
  )

]===]
function(embedc_add_files target)
  # Get the variables back in-scope. Since this package is already found at the start of the file
  # it should give the same results as earlier.
  find_package(Python QUIET COMPONENTS Interpreter)

  # Parse arguments
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "DIR" "FILES")
  if (NOT arg_FILES)
    message(SEND_ERROR "argument FILES is required")
  endif()

  # Setup some paths
  get_target_property(binary_dir ${target} BINARY_DIR)
  set(bundle_c ${binary_dir}/${target}_bundle.c)
  set(bundle_h ${binary_dir}/${target}_bundle.h)

  # Determine set-type for target_sources
  get_target_property(target_type ${target} TYPE)
  bn_tern(set_type "INTERFACE" "PRIVATE" "${target_type}" STREQUAL "INTERFACE_LIBRARY")

  # Get the existing property value. If NOTFOUND then we know we need to
  # do some initialization.
  get_target_property(embedc_files ${target} EMBEDC_FILES)
  if (NOT embedc_files)
    set(bundle_depends $<TARGET_PROPERTY:${target},EMBEDC_FILES>)
    add_custom_command(
      OUTPUT ${bundle_c} ${bundle_h}
      COMMAND ${EMBEDC_COMMAND} --bundle -o "${bundle_c}" --header "${bundle_h}" ${bundle_depends}
      DEPENDS ${bundle_depends}
      COMMAND_EXPAND_LISTS
      VERBATIM
    )
    # Make target depend on the generated bundle files
    target_sources(${target} ${set_type} ${bundle_c} ${bundle_h})
    source_group("Resources" FILES ${bundle_c} ${bundle_h})
    # Clear embedc_files so we can append it properly later
    set(embedc_files "")
  endif()

  # Make unique name for data file
  string(SHA256 names_hash "${arg_FILES}")
  set(convert_c "${binary_dir}/embedc/convert_${names_hash}.c")

  # Use embedc to parse the inputs
  bn_tern(into_option "--into=${arg_DIR}" "" arg_DIR)
  execute_process(
    COMMAND
      ${EMBEDC_COMMAND} --show -o -
      -C "${CMAKE_CURRENT_SOURCE_DIR}" ${into_option}
      ${arg_FILES}
    OUTPUT_VARIABLE convert_input
    # ECHO_OUTPUT_VARIABLE
  )

  # Extract the resource files from the output by replacing all "keys" with ";".
  string(REGEX REPLACE "\n([^=]+)=" ";" resource_files "\n${convert_input}")
  # Turn newline-separated list into CMake list so it outputs correctly
  string(REPLACE "\n" ";" resource_input "${convert_input}")
  # Custom command to generate the embed file
  add_custom_command(
    OUTPUT ${convert_c}
    COMMAND ${EMBEDC_COMMAND} --convert -o "${convert_c}" ${resource_input}
    DEPENDS ${resource_files}
    COMMAND_EXPAND_LISTS
    VERBATIM
  )
  # The target needs to actually compile and link the generated C file
  target_sources(${target} ${set_type} ${convert_c})
  source_group("Resources" FILES ${convert_c})
  # Update the EMBEDC_FILES property
  list(APPEND embedc_files "${convert_c}")
  set_property(TARGET ${target} PROPERTY EMBEDC_FILES "${embedc_files}")
endfunction()


