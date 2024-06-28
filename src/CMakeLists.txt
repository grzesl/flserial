# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(flserial_library VERSION 0.0.1 LANGUAGES C CXX)

add_subdirectory(serial)

include_directories(serial/include serial/include/serial)

add_library(flserial SHARED
  "flserial.cpp"
  "flserial.def"
)

target_link_libraries(flserial serial)



  
set_target_properties(flserial PROPERTIES
  PUBLIC_HEADER flserial.h
  OUTPUT_NAME "flserial"
)

target_compile_definitions(flserial PUBLIC DART_SHARED_LIB)
