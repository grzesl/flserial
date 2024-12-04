cmake_minimum_required(VERSION 3.14)

project(flserial_library VERSION 0.2.1 LANGUAGES C CXX)

add_subdirectory(native_libs)

include_directories(native_libs/include native_libs/include/serial)

if(MSVC)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
endif()

add_library(flserial SHARED
  "flserial.cpp"
  "flserial.def"
)
target_link_libraries(flserial native_libs)

set_target_properties(flserial PROPERTIES
  PUBLIC_HEADER flserial.h
  OUTPUT_NAME "flserial"
)

target_compile_definitions(flserial PUBLIC DART_SHARED_LIB)
