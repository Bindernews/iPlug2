cmake_minimum_required(VERSION 3.20)

set(cwd ${CMAKE_CURRENT_LIST_DIR})
set(_src
  curverasterbuffer.h
  lice_arc.cpp
  lice_bezier.h
  lice_bmp.cpp
  lice_colorspace.cpp
  lice_combine.h
  lice.cpp
  lice_extended.h
  lice.h
  lice_ico.cpp
  lice_image.cpp
  lice_import.h
  lice_line.cpp
  lice_lvg.cpp
  lice_palette.cpp
  lice_pcx.cpp
  lice_texgen.cpp
  lice_text.cpp
  lice_text.h
  lice_textnew.cpp
)
add_library(WDL_LICE STATIC)
target_include_directories(WDL_LICE PUBLIC ${cwd})
target_sources(WDL_LICE PRIVATE ${_src})
target_compile_options(
  WDL_LICE PRIVATE
  -Wno-multichar
  -Wno-deprecated-declarations
)
