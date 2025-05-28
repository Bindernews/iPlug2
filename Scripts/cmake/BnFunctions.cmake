#[=[
Copyright (c) 2025 Andrew Heintz <bindernews@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#]=]
# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 3.20)
include_guard(GLOBAL)

set(
  BN_RESOURCE_PROPERTY "RESOURCES" CACHE INTERNAL
  "Property to append to when calling bn_target_add with the RESOURCE option")

#[===[.rst
Evaluates extra arguments as a conditional and sets ``VAR`` to ``val_true`` or ``val_false`` accordingly.

`VAR` - Output variable name
`val_true` - Value if the condition is true
`val_false` - Value if the condition is false
``...`` - Remaining arguments are passed to ``if()``
]===]
macro(bn_tern VAR val_true val_false)
  if (${ARGN})
    set(${VAR} ${val_true})
  else()
    set(${VAR} ${val_false})
  endif()
endmacro()

#[===[.rst
Sets `VAR` to the first argument that is not "NOTFOUND" or an empty string.
Other falsy values ARE valid. If none of the arguments are valid, then `VAR`
will be set to "NOTFOUND".

If an option begins and ends with "@@" (e.g. "@@ @@") then it will match
since it's not empty, but the "@@"s will be removed and the inner string will
be stripped. This means that "@@ @@" will match as a fallback string, but
the result will be an empty string.

]===]
function(bn_fallback VAR option1 option2...)
  foreach(_index RANGE 1 ${ARGC})
    set(opt "${ARGV${_index}}")
    if(opt STREQUAL "" OR opt MATCHES "NOTFOUND$")
      continue()
    endif()
    if(opt MATCHES "^@@(.+)@@$")
      string(STRIP "${CMAKE_MATCH_1}" opt)
    endif()
    set(${VAR} "${opt}" PARENT_SCOPE)
    return()
  endforeach()
  set(${VAR} "NOTFOUND" PARENT_SCOPE)
endfunction()

#[===[.rst
.. code-block:: cmake
  bn_case(<output-variable> <input> <pattern1> <value1> <pattern2> <value2>...)

Tries to match `<input`> against each "pattern" argument in order, where patterns are regexes.
When a match is found, `<output_variable>` is set to the corresponding value. If no match is
found, the output is set to the empty string.
]===]
function(bn_case output_variable input)
  set(${output_variable} "" PARENT_SCOPE)

  foreach (_bn_case_index RANGE 2 ${ARGC} 2)
    set(_bn_case_condition "${ARGV${_bn_case_index}}")
    if ("${input}" MATCHES "${_bn_case_condition}")
      math(EXPR _bn_case_index2 "${_bn_case_index} + 1")
      set(${output_variable} "${ARGV${_bn_case_index2}}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction(bn_case)

#[===[.rst
.. code-block:: cmake
  bn_unzip(<count> <list1> <list2>... <listN> <item1> <item2>... <itemN>)

  # Equivalent to: set(a "name" "age") set(b "John" "25")
  bn_unzip(
    2 a b
    "name" "John"
    "age"  "25"
  )

Unzip the listed arguments into multiple output lists. This is intended
to make it easier to handle key-value pairs of arguments.

``count``
  The number of lists to split the input into.
``lists``
  ${count} names which are the output lists.
``items...``
  Items to be split into the output lists.
]===]
function(bn_unzip count lists items...)
  # Clear lists
  math(EXPR countN1 "${count} - 1")
  foreach(bn6140_ix RANGE 0 ${countN1})
    set(bn6140_list_${bn6140_ix} "")
  endforeach()
  # Set items
  math(EXPR bn6140_start_ix "${count} + 1")
  foreach(bn6140_ix RANGE ${bn6140_start_ix} ${ARGC})
    math(EXPR bn6140_list_id "(${bn6140_ix} - ${bn6140_start_ix}) % ${count}")
    list(APPEND bn6140_list_${bn6140_list_id} "${ARGV${bn6140_ix}}")
  endforeach()
  # Set lists in parent scope
  foreach(bn6140_ix RANGE 0 ${countN1})
    math(EXPR bn6140_argn "${bn6140_ix} + 1")
    set(${ARGV${bn6140_argn}} "${bn6140_list_${bn6140_ix}}" PARENT_SCOPE)
  endforeach()
endfunction()

#[===[.rst
.. code-block:: cmake
  bn_list_contains_any(<output-variable> <list> <item> [<items>...])

Returns ``TRUE`` if the list contains any of the given items, ``FALSE`` otherwise.

]===]
function(bn_list_contains_any VAR list)
  set(items "${ARGN}")
  # Default to false, succeed on found item
  set(${VAR} FALSE PARENT_SCOPE)
  foreach (item IN LISTS items)
    if ("${item}" IN_LIST ${list})
      set(${VAR} TRUE PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction()

#[===[.rst
.. code-block:: cmake
  bn_list_contains_all(<output-variable> <list> <item> [<items>...])

Returns ``TRUE`` if the list contains all the listed items, ``FALSE`` otherwise.

]===]
function(bn_list_contains_all VAR list)
  set(items "${ARGN}")
  # Default to true, fail if missing item
  set(${VAR} TRUE PARENT_SCOPE)
  foreach (item IN LISTS items)
    if (NOT "${item}" IN_LIST ${list})
      set(${VAR} FALSE PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction()

#[===[.rst:
.. code-block:: cmake
  bn_copy_properties(<target_dst> <target_src> <properties>)

Copies property values from ``target_src`` to ``target_dst``. This is
used to propogate things like the resources list when adding output formats.
The ``properties`` argument lists names of properties to copy.

]===]
function(bn_copy_properties target_dst target_src properties)
  foreach(prop IN LISTS properties)
    get_target_property(tmp ${target_src} ${prop})
    set_target_properties(${target_dst} PROPERTIES ${prop} "${tmp}")
  endforeach()
endfunction(bn_copy_properties)

#[===[.rst

.. code-block:: cmake
  bn_make_absolute_paths(VAR <list> [NORMALIZE] [BASE_DIRECTORY <base_dir>])

Make all paths in `<list>` absolute, using either the provided `BASE_DIRECTORY`
or `${CMAKE_CURRENT_SOURCE_DIR}`. The result will be written to `VAR`.

]===]
function(bn_make_absolute_paths VAR list_)
  cmake_parse_arguments(PARSE_ARGV 2 arg "NORMALIZE" "BASE_DIRECTORY" "")
  # Parse arguments into additional options that we can pass to cmake_path()
  set(_opts "")
  if (arg_NORMALIZE)
    list(APPEND _opts NORMALIZE)
  endif()
  if (arg_BASE_DIRECTORY)
    list(APPEND _opts BASE_DIRECTORY "${arg_BASE_DIRECTORY}")
  endif()
  # Loop and update
  set(result "")
  foreach (path IN LISTS ${list_})
    cmake_path(ABSOLUTE_PATH path ${_opts} OUTPUT_VARIABLE out_path)
    list(APPEND result "${out_path}")
  endforeach()
  # Update in parent scope
  set(${VAR} "${result}" PARENT_SCOPE)
endfunction()

#[===[.rst

A function that combines calls to the various ``target_*`` functions that add
to various target properties.

.. code-block:: cmake
  bn_target_add(
    <target>
    <INTERFACE|PUBLIC|PRIVATE>
    [INCLUDE <include directories...>]
    [SOURCE <source files...>]
    [RESOURCE <resources...>]
    [DEFINE <compiler definitions...>]
    [OPTION <compiler options...>]
    [FEATURE <compile features...>]
    [LINK <link libraries...>]
    [LINK_DIR <link directories...>]
    [LINK_OPTION <link options...>]
  )

`<target>`_ - Name of the target to add information to
`INCLUDE`_ - Calls ``target_include_directories()``
`SOURCE`_ - Calls ``target_sources()``
`RESOURCE`_ - Appends to the ``${BN_RESOURCE_PROPERTY}`` property for the target,
  which defaults to ``RESOURCES`` but may be overridden by setting BN_RESOURCE_PROPERTY
  either as a cache or local variable
`DEFINE`_ - Calls ``target_compile_definitions()``
`OPTION`_ - Calls ``target_compile_options()``
`FEATURE`_ - Calls ``target_compile_features()``
`LINK`_ - Calls ``target_link_libraries()``
`LINK_DIR`_ - Calls ``target_link_directories()``
`LINK_OPTION`_ - Calls ``target_link_options()``

]===]
function(bn_target_add target set_type)
  cmake_parse_arguments(PARSE_ARGV 2 cfg "" "" "INCLUDE;SOURCE;DEFINE;OPTION;FEATURE;LINK;LINK_DIR;LINK_OPTION;RESOURCE")
  if (cfg_UNUSED)
    message(FATAL_ERROR "Unused arguments ${cfg_UNUSED}")
  endif()

  set(_set_type "${set_type}")

  if (cfg_INCLUDE)
    target_include_directories(${target} ${_set_type} ${cfg_INCLUDE})
  endif()
  if (cfg_SOURCE)
    target_sources(${target} ${_set_type} ${cfg_SOURCE})
  endif()
  if (cfg_RESOURCE)
    # Versions of CMake prior to 3.19 didn't allow general properties on INTERFACE targets.
    # Version 3.23 adds filesets, but this works well and doesn't bump up the version.

    # Make resource paths absolute
    set(resources_abs)
    foreach (path ${cfg_RESOURCE})
      # Assume the current BASE_DIRECTORY is sufficient. If not, callers should pass
      # already-absolute paths.
      cmake_path(ABSOLUTE_PATH path NORMALIZE OUTPUT_VARIABLE out_path)
      list(APPEND resources_abs ${out_path})
    endforeach()
    # Append to list of resources.
    set_property(TARGET ${target} APPEND PROPERTY ${BN_RESOURCE_PROPERTY} ${resources_abs})
  endif()


  if (cfg_DEFINE)
    target_compile_definitions(${target} ${_set_type} ${cfg_DEFINE})
  endif()
  if (cfg_OPTION)
    target_compile_options(${target} ${_set_type} ${cfg_OPTION})
  endif()
  if (cfg_FEATURE)
    target_compile_features(${target} ${_set_type} ${cfg_FEATURE})
  endif()
  if (cfg_LINK)
    target_link_libraries(${target} ${_set_type} ${cfg_LINK})
  endif()
  if (cfg_LINK_DIR)
    target_link_directories(${target} ${_set_type} ${cfg_LINK_DIR})
  endif()
  if (cfg_LINK_OPTION)
    target_link_options(${target} ${_set_type} ${cfg_LINK_OPTION})
  endif()
endfunction()

#[===[.rst
.. cmake:signature::
  bn_make_python_venv(
    <OUTPUT_VARIABLE>
    [VERSION <python-version>]
    [DIRECTORY <venv directory>]
    [PROMPT <venv prompt>]
    [ADD_TO_PATH]
  )

``VAR``
  Output variable where the path to the venv'd Python executable will
  be stored. This is a cache variable.
``VERSION``
  Minimum Python version required.
``DIRECTORY``
  Specify an alternate directory for the venv. The default is "${CMAKE_SOURCE_DIR}/.venv".
``PROMPT``
  Specify an alternate CLI prompt for users who activate the venv. The default
  is the project name.
``ADD_TO_PATH``
  If given, this will add the binary directory containing the python executable
  into `CMAKE_PROGRAM_PATH`, so that other scripts may find programs installed there.
``PACKAGES``
  List of packages to install using pip. This is a convenient way to ensure that one
  or more packages are installed.
]===]
function(bn_make_python_venv VAR)
  cmake_parse_arguments(PARSE_ARGV 1 bn950 "ADD_TO_PATH" "VERSION;DIRECTORY;PROMPT" "PACKAGES")

  # Do nothing if the cached variable is already set
  set(bn950_py_exe "$CACHE{${VAR}}")
  if(bn950_py_exe)
    return()
  endif()
  unset(bn950_py_exe)

  # Default values
  if(NOT bn950_VERSION)
    set(bn950_VERSION "3.8")
  endif()
  if(NOT bn950_DIRECTORY)
    set(bn950_DIRECTORY "${CMAKE_SOURCE_DIR}/.venv")
  endif()
  if(NOT bn950_PROMPT)
    set(bn950_PROMPT "${CMAKE_PROJECT_NAME}")
  endif()
  cmake_path(NORMAL_PATH bn950_DIRECTORY)

  # find_program arguments, on Unix/Linux systems python will be <venv>/bin/python
  # while on Windows it's normally <venv>/Scripts/python.exe

  set(bn950_find_py_args
    bn950_py_exe
    NAMES python python3 python.exe
    PATHS "${bn950_DIRECTORY}/bin" "${bn950_DIRECTORY}/Scripts"
    NO_SYSTEM_ENVIRONMENT_PATH
    NO_CMAKE_ENVIRONMENT_PATH
    NO_CMAKE_SYSTEM_PATH
    NO_CMAKE_INSTALL_PREFIX
    NO_CACHE
  )

  # What if the venv exists but it's not in the cache?
  find_program(${bn950_find_py_args})
  if(bn950_py_exe)
    message(STATUS "Using Python venv in ${bn950_DIRECTORY}")
  else()
    # Okay, try to create it

    # Find python version 3.8 or higher
    find_package(Python ${bn950_VERSION} REQUIRED COMPONENTS Interpreter)

    # Create a virtual environment in <project source directory>/.venv
    # This is safe to do multiple times, as it won't delete packages from an existing venv.
    message(STATUS "Creating Python venv in ${bn950_DIRECTORY}")
    execute_process(
      COMMAND ${Python_EXECUTABLE} -m venv --prompt "${bn950_PROMPT}" "${bn950_DIRECTORY}"
      COMMAND_ERROR_IS_FATAL ANY
    )

    # Call find_program again
    unset(bn950_py_exe)
    find_program(${bn950_find_py_args})
  endif()
  if(NOT bn950_py_exe)
    message(FATAL_ERROR "Unable to create virtual environment at ${bn950_DIRECTORY}")
    return()
  endif()

  set(${VAR} "${bn950_py_exe}" CACHE PATH "Python executable in venv" FORCE)

  # Optionally, add to the path
  if(bn950_ADD_TO_PATH)
    cmake_path(GET bn950_py_exe PARENT_PATH bn950_bin_dir)
    list(APPEND CMAKE_PROGRAM_PATH "${bn950_bin_dir}")
    set(CMAKE_PROGRAM_PATH "${CMAKE_PROGRAM_PATH}" PARENT_SCOPE)
  endif()

  if(bn950_PACKAGES)
    set(pip_flags -q --disable-pip-version-check --require-virtualenv)
    execute_process(
      COMMAND ${bn950_py_exe} -m pip ${pip_flags} install ${bn950_PACKAGES}
      OUTPUT_QUIET
      COMMAND_ERROR_IS_FATAL LAST
    )
  endif()
endfunction()


function(bn_cache_call)
  cmake_parse_arguments(PARSE_ARGV 0 bn961 "" "CACHE_VARIABLE;OUTPUT_VARIABLE;DID_RERUN" "CALL")
  if(NOT bn961_CACHE_VARIABLE OR NOT bn961_OUTPUT_VARIABLE OR NOT bn961_CALL)
    message(FATAL_ERROR "Arguments CACHE_VARIABLE, OUTPUT_VARIABLE, CALL are required")
  endif()
  # Separate the function name from the arguments
  list(POP_FRONT bn961_CALL bn961_func)
  # Hash the arguments and get the current hash
  string(SHA1 bn961_args_hash "${bn961_CALL}")
  set(bn961_hash_var "${bn961_CACHE_VARIABLE}_BN_SHA1")
  set(bn961_current_hash "$CACHE{${bn961_hash_var}}")
  # Only recompute if necessary
  if(NOT bn961_args_hash STREQUAL "${bn961_current_hash}")
    cmake_language(CALL ${bn961_func} ${bn961_CALL})
    set(${bn961_CACHE_VARIABLE} "${${bn961_OUTPUT_VARIABLE}}" CACHE INTERNAL "" FORCE)
    set(${bn961_hash_var} "${bn961_args_hash}" CACHE INTERNAL "" FORCE)
    set(bn961_rerun ON)
  else()
    set(bn961_rerun OFF)
  endif()
  # Return results
  set(${bn961_OUTPUT_VARIABLE} "$CACHE{${bn961_CACHE_VARIABLE}}" PARENT_SCOPE)
  if(bn961_DID_RERUN)
    set(${bn961_DID_RERUN} ${bn961_rerun} PARENT_SCOPE)
  endif()
endfunction()

#[===[.rst

.. code-block:: cmake
  bn_set_output_directory(<target> <output-directory>)

Sets the output directory to be the same for all configurations. Some generators
use different output directories depending on the configuration, which can complicate
things if your output requires a certain directory structure. This function forces
all outputs into the same directory, regardless of configuration.

]===]
function(bn_set_output_directory target output_directory)
  set(out_dir "${output_directory}")
  set_target_properties(${target} PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${out_dir}"
    LIBRARY_OUTPUT_DIRECTORY "${out_dir}"
    RUNTIME_OUTPUT_DIRECTORY "${out_dir}"
  )
  foreach (config_type ${CMAKE_CONFIGURATION_TYPES})
    string(TOUPPER "${config_type}" config_type_up)
    set_target_properties(${target} PROPERTIES
      ARCHIVE_OUTPUT_DIRECTORY_${config_type_up} "${out_dir}"
      LIBRARY_OUTPUT_DIRECTORY_${config_type_up} "${out_dir}"
      RUNTIME_OUTPUT_DIRECTORY_${config_type_up} "${out_dir}"
    )
  endforeach()
endfunction(bn_set_output_directory)

#[===[.rst

.. code-block:: cmake
  bn_json_dict(VAR <key1> <value1> [<key2> <value2>] ...)

Sets `VAR` to a json dictionary made of the key-value argument pairs.
Values that are not valid json by themselves will be quoted as strings.

]===]
function(bn_json_dict VAR)
  set(dict "{}")
  math(EXPR _indexN "${ARGC} - 2")
  # json types that we don't need to quote
  set(quote_skip OBJECT ARRAY STRING)
  foreach (_index0 RANGE 1 ${_indexN} 2)
    math(EXPR _index1 "${_index0} + 1")
    set(key "${ARGV${_index0}}")
    set(value "${ARGV${_index1}}")
    # Check if we should quote the value
    string(JSON jtype ERROR_VARIABLE err TYPE "[ ${value} ]" 0)
    if(NOT "${jtype}" IN_LIST quote_skip)
      # Value is not valid json by itself, so quote it
      string(CONFIGURE "\"@value@\"" value @ONLY ESCAPE_QUOTES)
    endif()
    # Update the dict
    string(JSON dict SET "${dict}" "${key}" "${value}")
  endforeach()
  # Set VAR in parent scope
  set(${VAR} "${dict}" PARENT_SCOPE)
endfunction()

function(bn_json_set dict key)
  # Sanitize and quote the value
  set(bn5470_value "${ARGN}")
  string(REPLACE "\n" "\\n" bn5470_value "${bn5470_value}")
  string(CONFIGURE "\"@bn5470_value@\"" bn5470_value @ONLY ESCAPE_QUOTES)
  # Update the dict
  string(JSON bn5470_dict SET "${${dict}}" "${key}" "${bn5470_value}")
  # Update parent scope
  set(${dict} "${bn5470_dict}" PARENT_SCOPE)
endfunction()

function(bn_json_get VAR dict key)
  string(JSON bn5470_value ERROR_VARIABLE bn5470_err GET "${${dict}}" "${key}")
  if(bn5470_err)
    set(${VAR} "${VAR}-NOTFOUND" PARENT_SCOPE)
  else()
    set(${VAR} "${bn5470_value}" PARENT_SCOPE)
  endif()
endfunction()

function(bn_json_minify VAR input)
  # Remove newlines
  string(REGEX REPLACE "\n *" "" bn5470_value "${input}")
  # Replace " : " with ":"
  string(REPLACE "\" : \"" "\":\"" bn5470_value "${bn5470_value}")
  # Set in parent
  set(${VAR} "${bn5470_value}" PARENT_SCOPE)
endfunction()

#[===[.rst
.. cmake:signature::
  bn_json_to_varaibles(<prefix> JSON <json> [KEYS <specific keys>...])

Load keys from the json dictionary as variables in the local scope.

``prefix``
  The prefix for variable names. For example if the prefix is "foo" and the
  json key is "bar" the variable will be "foo_bar".
``JSON``
  The input json string.
``KEYS``
  If given, load this specific list of keys instead of all keys.

#]===]
function(bn_json_to_variables prefix)
  cmake_parse_arguments(PARSE_ARGV 1 bn5470 "" "JSON" "KEYS")
  if(NOT bn5470_JSON)
    message(FATAL_ERROR "Argument JSON is required")
  endif()
  if(bn547_KEYS)
    foreach(key IN LISTS bn5470_KEYS)
      string(JSON bn5470_val GET "${bn5470_JSON}" "${bn5470_key}")
      set(${prefix}_${bn5470_key} "${bn5470_val}" PARENT_SCOPE)
    endforeach()
  else()
    string(JSON bn5470_count LENGTH "${bn5470_JSON}")
    math(EXPR bn5470_count "${bn5470_count} - 1")
    foreach(ix RANGE ${bn5470_count})
      string(JSON bn5470_key MEMBER "${bn5470_JSON}" ${ix})
      string(JSON bn5470_val GET "${bn5470_JSON}" "${bn5470_key}")
      set(${prefix}_${bn5470_key} "${bn5470_val}" PARENT_SCOPE)
    endforeach()
  endif()
endfunction()
