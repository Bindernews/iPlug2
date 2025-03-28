cmake_minimum_required(VERSION 3.20)

if (CMAKE_SYSTEM_NAME MATCHES "Linux")
  option(IPLUG_APP_ALSA "Use ALSA on Linux (requires libasound2-dev)" ON)
  option(IPLUG_APP_JACK "Use JACK on Linux" ON)
  option(IPLUG_APP_PULSE "Use Pulse Audio on Linux" OFF)
endif()

set(IPLUG_DEPS ${IPLUG2_SDK_PATH}/Dependencies/IPlug)

# Statically build RTAudio and RTMidi, configured here
# because their CMakeLists.txt files are funky.

add_library(iPlug2_RTLibs STATIC)
set(_def)
set(_lib)
set(_src
  ${IPLUG_DEPS}/RTAudio/RtAudio.cpp
  ${IPLUG_DEPS}/RTMidi/RtMidi.cpp
)
set(_inc
  ${IPLUG_DEPS}/RTAudio
  ${IPLUG_DEPS}/RTMidi
)

if (CMAKE_SYSTEM_NAME MATCHES "Windows")
  # Link Windows sound libraies if on Windows
  list(APPEND _def
    "__WINDOWS_DS__"
    "__WINDOWS_MM__"
    "__WINDOWS_ASIO__"
  )
  list(APPEND _src
    ${IPLUG_DEPS}/RTAudio/include/asio.cpp
    ${IPLUG_DEPS}/RTAudio/include/asiodrivers.cpp
    ${IPLUG_DEPS}/RTAudio/include/asiolist.cpp
    ${IPLUG_DEPS}/RTAudio/include/iasiothiscallresolver.cpp
    ${IPLUG_DEPS}/RTMidi/rtmidi_c.cpp
  )
  list(APPEND _lib
    dsound.lib
    winmm.lib
  )
elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
  # For MacOS
  list(APPEND _def
    "__MACOSX_CORE__"
  )
  list(APPEND _lib
    "-framework AppKit"
    "-framework CoreMIDI"
    "-framework CoreAudio"
  )
elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
  # RtAudio / RTMidi
  find_package(PkgConfig REQUIRED)
  if (IPLUG_APP_ALSA)
    pkg_check_modules(Alsa REQUIRED IMPORTED_TARGET "alsa")
    list(APPEND _def "__LINUX_ALSA__")
    list(APPEND _lib PkgConfig::Alsa)
  endif()
  if (IPLUG_APP_JACK)
    pkg_check_modules(Jack REQUIRED IMPORTED_TARGET "jack")
    list(APPEND _def "__UNIX_JACK__")
    list(APPEND _lib PkgConfig::Jack)
  endif()
  if (IPLUG_APP_PULSE)
    pkg_check_modules(PulseAudio REQUIRED IMPORTED_TARGET "libpulse")
    pkg_check_modules(PulseAudioSimple REQUIRED IMPORTED_TARGET "libpulse-simple")
    list(APPEND _def "__LINUX_PULSE__")
    list(APPEND _lib PkgConfig::PulseAudio PkgConfig::PulseAudioSimple)
  endif()
endif()

# Set properties on iPlug2_RTLibs target
set(tgt iPlug2_RTLibs)
target_sources(${tgt} PRIVATE ${_src})
target_include_directories(${tgt} PUBLIC ${_inc})
target_link_libraries(${tgt} PRIVATE ${_lib})
target_compile_definitions(${tgt} PUBLIC ${_def})
