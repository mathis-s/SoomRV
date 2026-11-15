cmake_minimum_required(VERSION 3.13)

project(soomrv_cosim LANGUAGES CXX)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_EXTENSIONS OFF)
add_compile_options(-fno-rtti -Wno-unused-parameter -Wno-unused-function)

set(DYNO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../..")
set(DYNO_BUILD "${DYNO_ROOT}/build.release")
set(RISCV "${CMAKE_CURRENT_SOURCE_DIR}/../riscv-isa-sim")

if(NOT SOOMRV_HEADERS_DIR)
  set(SOOMRV_HEADERS_DIR "${CMAKE_CURRENT_BINARY_DIR}")
endif()

add_executable(soomrv_cosim sim/Top_tb.cpp sim/Simif.cpp)

target_include_directories(soomrv_cosim PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/sim"
  "${SOOMRV_HEADERS_DIR}"
  "${DYNO_ROOT}/include"
  "${DYNO_ROOT}/tools/dyno-sim/include"
  "${DYNO_ROOT}/tools/dyno-sim/libfst/src"
  "${RISCV}")

option(SOOMRV_FST "Write FST waveforms" OFF)
target_compile_definitions(soomrv_cosim PRIVATE COSIM)
if(SOOMRV_FST)
  target_compile_definitions(soomrv_cosim PRIVATE ENABLE_FST)
endif()

target_link_libraries(soomrv_cosim PRIVATE
  "${DYNO_BUILD}/lib/libcore.a"
  "${DYNO_BUILD}/lib/libhw.a"
  "${DYNO_BUILD}/tools/dyno-sim/libfst.a"
  "${RISCV}/libriscv.a"
  "${RISCV}/libsoftfloat.a"
  "${RISCV}/libdisasm.a"
  z pthread)
