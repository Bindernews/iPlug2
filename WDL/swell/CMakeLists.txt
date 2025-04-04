cmake_minimum_required(VERSION 3.20)

if (CMAKE_SYSTEM_NAME MATCHES "Windows")
  # SWELL not required on Windows
  return()
endif()

add_library(WDL_SWELL STATIC)
set(_src)
set(_inc)
set(_lib)
set(_def)

if (CMAKE_SYSTEM_NAME MATCHES "Darwin")
  list(APPEND _def
    "SWELL_COMPILED"
  )
  list(APPEND _lib
    "-framework AppKit"
  )
  # -pipe -fvisibility=hidden -fno-math-errno -fPIC -DPIC -Wall -Wshadow -Wno-unused-function -Wno-multichar -Wtype-limits
  list(APPEND _src
    swell-appstub.mm
    swellappmain.mm
    swell-ini.cpp
    swell-dlg.mm
    swell-kb.mm
    swell-miscdlg.mm
    swell-menu.mm
    swell-wnd.mm
    swell.cpp
    swell-misc.mm
    swell-gdi.mm
  )
  list(APPEND _inc
    ${CMAKE_CURRENT_LIST_DIR}
  )

elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")

  option(SWELL_SUPPORT_GTK "Enable GTK+ support in SWELL" OFF)

  find_package(PkgConfig REQUIRED)
  pkg_check_modules(
    SWELL_PrivDependencies REQUIRED IMPORTED_TARGET
    "glib-2.0"
    "x11"
    "xi"
    "glx"
    "freetype2"
    "fontconfig"
  )

  set(pub_dep "gdk-3.0")
  if (SWELL_SUPPORT_GTK)
    set(pub_dep "gtk+-3.0")
  endif()
  pkg_check_modules(SWELL_PubDependencies REQUIRED IMPORTED_TARGET ${pub_dep})

  # Build and link Swell properly on Linux. This uses GTK+ 3.0 and X11
  list(APPEND _src
    swell.h
    swell.cpp
    swell-appstub-generic.cpp
    swell-dlg-generic.cpp
    swell-gdi-generic.cpp
    swell-gdi-lice.cpp
    swell-ini.cpp
    swell-kb-generic.cpp
    swell-menu-generic.cpp
    swell-miscdlg-generic.cpp
    swell-misc-generic.cpp
    swell-wnd-generic.cpp
    swell-generic-gdk.cpp
  )

  list(APPEND _def
    SWELL_COMPILED
    SWELL_TARGET_GDK=3
    $<$<BOOL:${SWELL_SUPPORT_GTK}>:SWELL_SUPPORT_GTK>
    SWELL_LICE_GDI
    SWELL_FREETYPE
    SWELL_FONTCONFIG
    _FILE_OFFSET_BITS=64
    WDL_ALLOW_UNSIGNED_DEFAULT_CHAR
  )
  list(APPEND _inc
    ${CMAKE_CURRENT_LIST_DIR}
    ${CMAKE_CURRENT_LIST_DIR}/../lice/
  )
  list(APPEND _lib
    WDL_LICE
    PkgConfig::SWELL_PrivDependencies
    # Xinput library, we only need to dynamically link to it
    "Xi"
  )
  list(APPEND _src
    ${swell_src}
    ${CMAKE_SOURCE_DIR}/resources/main.rc_mac_dlg
    ${CMAKE_SOURCE_DIR}/resources/main.rc_mac_menu
  )
  target_link_libraries(WDL_SWELL PUBLIC PkgConfig::SWELL_PubDependencies)
endif()

target_sources(WDL_SWELL PRIVATE ${_src})
target_include_directories(WDL_SWELL PUBLIC ${_inc})
target_link_libraries(WDL_SWELL PRIVATE ${_lib})
target_compile_definitions(WDL_SWELL PUBLIC ${_def})
target_compile_options(WDL_SWELL PRIVATE -Wno-deprecated-declarations)
