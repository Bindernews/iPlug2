cmake_minimum_required(VERSION 3.20)

add_library(WDL_SWELL STATIC)
set(_src)
set(_inc)
set(_lib)
set(_def)
if (CMAKE_SYSTEM_NAME MATCHES "Windows")
  # SWELL not required on Windows

elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
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
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(Glib_20 REQUIRED IMPORTED_TARGET "glib-2.0")
  pkg_check_modules(Gdk_30 REQUIRED IMPORTED_TARGET "gdk-3.0")
  pkg_check_modules(X11 REQUIRED IMPORTED_TARGET "x11")
  pkg_check_modules(XInput IMPORTED_TARGET "xi")
  pkg_check_modules(Freetype2 REQUIRED IMPORTED_TARGET "freetype2")
  pkg_check_modules(Glx REQUIRED IMPORTED_TARGET "glx")

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
    SWELL_LICE_GDI
    SWELL_FREETYPE
    _FILE_OFFSET_BITS=64
    WDL_ALLOW_UNSIGNED_DEFAULT_CHAR
  )
  list(APPEND _inc
    ${CMAKE_CURRENT_LIST_DIR}
    ${CMAKE_CURRENT_LIST_DIR}/../lice/
  )
  list(APPEND _lib
    WDL_LICE
    PkgConfig::Gdk_30
    PkgConfig::Glib_20
    PkgConfig::X11
    PkgConfig::Freetype2
    PkgConfig::Glx
    # Xinput library, we only need to dynamically link to it
    "Xi"
  )
  list(APPEND _src
    ${swell_src}
    ${CMAKE_SOURCE_DIR}/resources/main.rc_mac_dlg
    ${CMAKE_SOURCE_DIR}/resources/main.rc_mac_menu
  )
  target_link_libraries(WDL_SWELL PUBLIC PkgConfig::Gdk_30)
endif()

target_sources(WDL_SWELL PRIVATE ${_src})
target_include_directories(WDL_SWELL PUBLIC ${_inc})
target_link_libraries(WDL_SWELL PRIVATE ${_lib})
target_compile_definitions(WDL_SWELL PUBLIC ${_def})
