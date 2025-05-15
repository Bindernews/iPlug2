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

function(bn_case variable output_variable)
  set(${output_variable} "" PARENT_SCOPE)

  foreach (_bn_case_index RANGE 2 ${ARGC} 2)
    set(_bn_case_condition "${ARGV${_bn_case_index}}")
    if (${variable} MATCHES "${_bn_case_condition}")
      math(EXPR _bn_case_index2 "${_bn_case_index} + 1")
      set(${output_variable} "${ARGV${_bn_case_index2}}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction(bn_case)



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

function(bn_memoize VAR function_name)
  string(SHA1 _bn_memoize_input_hash "${ARGN}")
  set(_bn_memoize_key bn_memoize_${function_name}_${_bn_memoize_input_hash})
  if(NOT DEFINED CACHE{${_bn_memoize_key}})
    cmake_language(CALL ${function_name} ${ARGN})
    set(${_bn_memoize_key} "${VAR}" CACHE INTERNAL "memoize")
  endif()
  set(${VAR} $CACHE{${_bn_memoize_key}} PARENT_SCOPE)
endfunction()
