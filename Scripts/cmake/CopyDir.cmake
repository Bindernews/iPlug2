# This should be run in script mode.
cmake_minimum_required(VERSION 3.20)

if(${ARG_BINARY} IS_NEWER_THAN ${ARG_DESTINATION})
  set(copy_src "${ARG_SOURCE}")
  cmake_path(GET ARG_DESTINATION PARENT_PATH copy_dst)
  file(REMOVE_RECURSE "${copy_dst}")
  file(COPY "${copy_src}" DESTINATION "${copy_dst}")
  message(NOTICE "Copied ${copy_src} to ${copy_dst}")
endif()
