#
# This file should be included in your main CMakeLists.txt file. #
#

if (APPLE)
  enable_language(OBJCXX)
endif()

# This is used in many places
set(IPLUG2_SDK_PATH ${CMAKE_CURRENT_LIST_DIR} CACHE PATH "Path to the iPlug2 SDK")

# We need this so we can find call FindFaust.cmake
list(APPEND CMAKE_MODULE_PATH ${IPLUG2_SDK_PATH}/Scripts/cmake)

# Make sure MSVC uses static linking for compatibility with Skia libraries and easier distribution.
# Note that settings CMAKE_MSVC_RUNTIME_LIBRARY doesn't seem to work consistently, so we set the flags directly.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(IPLUG_MSVC_FLAGS "")
if (MSVC)
  set(IPLUG_MSVC_FLAGS "/MT$<$<CONFIG:Debug>:d>")
endif()

# We generate folders for targets that support it (Visual Studio, Xcode, etc.)
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

add_subdirectory(${IPLUG2_SDK_PATH}/IPlug ${CMAKE_BINARY_DIR}/IPlug)
add_subdirectory(${IPLUG2_SDK_PATH}/IGraphics ${CMAKE_BINARY_DIR}/IGraphics)