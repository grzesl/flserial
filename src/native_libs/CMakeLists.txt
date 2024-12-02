cmake_minimum_required(VERSION 3.14)

project(native_libs)

if(APPLE)
    find_library(IOKIT_LIBRARY IOKit)
    find_library(FOUNDATION_LIBRARY Foundation)
endif()

if(UNIX AND NOT APPLE AND NOT ANDROID)
    set(rt_LIBRARIES rt)
    set(pthread_LIBRARIES pthread)
endif()

## Sources
set(native_libs_SRCS
    src/serial.cc
    include/serial/serial.h
    include/serial/v8stdint.h
)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

list(APPEND native_libs_SRCS src/impl/tinycthread.c)
list(APPEND native_libs_SRCS src/impl/fifo.c)

if(APPLE)
    list(APPEND native_libs_SRCS src/impl/unix.cc)
    list(APPEND native_libs_SRCS src/impl/list_ports/list_ports_osx.cc)
elseif(ANDROID)
    list(APPEND native_libs_SRCS src/impl/cglob.c)
    list(APPEND native_libs_SRCS src/impl/unix.cc)
    list(APPEND native_libs_SRCS src/impl/list_ports/list_ports_linux.cc)
elseif(UNIX)
    list(APPEND native_libs_SRCS src/impl/unix.cc)
    list(APPEND native_libs_SRCS src/impl/list_ports/list_ports_linux.cc)
else()
    list(APPEND native_libs_SRCS src/impl/win.cc)
    list(APPEND native_libs_SRCS src/impl/list_ports/list_ports_win.cc)
endif()

add_library(${PROJECT_NAME} ${native_libs_SRCS})
if(APPLE)
    target_link_libraries(${PROJECT_NAME} ${FOUNDATION_LIBRARY} ${IOKIT_LIBRARY})
elseif(ANDROID)

elseif(UNIX)
    target_link_libraries(${PROJECT_NAME} rt pthread)
else()
    target_link_libraries(${PROJECT_NAME} setupapi)
endif()


## Include headers
include_directories(include)


## Install headers
if(ANDROID OR UNIX OR APPLE)
install(FILES include/serial/serial.h include/serial/v8stdint.h
  DESTINATION ~/prj/flserial/build/native_libs)
endif()
