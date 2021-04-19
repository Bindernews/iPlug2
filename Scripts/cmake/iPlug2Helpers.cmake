include_guard(GLOBAL)

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
  if (cfg_RESOURCE AND (NOT ttype STREQUAL "INTERFACE_LIBRARY"))
    set_property(TARGET ${target} APPEND PROPERTY IPLUG_RESOURCES ${cfg_RESOURCE})
  endif()
endfunction()


function(iplug_add_resources target)
  cmake_parse_arguments(arg "" "" "RESOURCES" ${ARGN})

  get_target_property(ttype ${target} TYPE)
  if (NOT "${ttype}" STREQUAL "INTERFACE_LIBRARY")
    set_property(TARGET ${target} APPEND PROPERTY IPLUG_RESOURCES ${arg_RESOURCES})
  endif()

  set(subs "${IPLUG_${target}_SUB_TARGETS}")
  if (subs)
    foreach(sub IN LISTS subs)
      message(INFO "Adding resources to ${sub}")
      iplug_add_resources(${sub} RESOURCES ${arg_RESOURCES} ${ARGN})
    endforeach()
  endif()
  
endfunction(iplug_add_resources)


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

#! iplug_copy_properties : Copies properties from target_src to target_dst
# \param:target_dst Destination target name
# \param:target_src Source target name
# \param:properties List of properties to copy
function(iplug_copy_properties target_dst target_src properties)
  foreach(prop IN LISTS properties)
    get_target_property(tmp ${target_src} ${prop})
    set_target_properties(${target_dst} PROPERTIES ${prop} ${tmp})
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
