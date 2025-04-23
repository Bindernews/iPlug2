# This file should be included in your main CMakeLists.txt file.

# We need this so we can find our other modules. Also it has to be outside an add_subdirectory
# call, otherwise it won't propogate and be useable later.
list(APPEND CMAKE_MODULE_PATH ${IPLUG2_SDK_PATH}/Scripts/cmake)
# Add this directory as a subdirectory.
add_subdirectory(${CMAKE_CURRENT_LIST_DIR} ${CMAKE_BINARY_DIR}/iplug)
