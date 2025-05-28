cmake_minimum_required(VERSION 3.23)
project(Yoga VERSION 1.18.0 LANGUAGES CXX)
add_library(yoga STATIC)
target_sources(yoga
  PRIVATE
    yoga/log.cpp
    yoga/Utils.cpp
    yoga/YGConfig.cpp
    yoga/YGEnums.cpp
    yoga/YGLayout.cpp
    yoga/YGNode.cpp
    yoga/YGNodePrint.cpp
    yoga/YGStyle.cpp
    yoga/YGValue.cpp
    yoga/Yoga.cpp
    yoga/event/event.cpp

    yoga/Bitfield.h
    yoga/CompactValue.h
    yoga/log.h
    yoga/Utils.h
    yoga/YGConfig.h
    yoga/YGEnums.h
    yoga/YGFloatOptional.h
    yoga/YGLayout.h
    yoga/YGMacros.h
    yoga/YGNode.h
    yoga/YGNodePrint.h
    yoga/YGStyle.h
    yoga/YGValue.h
    yoga/Yoga-internal.h
    yoga/event/event.h
  PUBLIC FILE_SET HEADERS FILES
    yoga/Yoga.h
)
target_include_directories(yoga
  PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}/yoga
)