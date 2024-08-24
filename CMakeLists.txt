cmake_minimum_required(VERSION 3.29)
project(photonMapping CUDA CXX C)

include(cmake/embed_ptx.cmake)

set(CMAKE_CUDA_STANDARD 11)
set(OptiX_ROOT_DIR $ENV{OptiX_INSTALL_DIR})
set(CMAKE_PREFIX_PATH $ENV{OptiX_INSTALL_DIR})

embed_ptx(
  OUTPUT_TARGET
    photonMapping-ptx
  PTX_LINK_LIBRARIES
    owl::owl
  SOURCES
    deviceCode.cu
)

add_executable(photonMapping hostCode.cxx)

set(owl_dir ${PROJECT_SOURCE_DIR}/externals/owl)
add_subdirectory(${owl_dir} EXCLUDE_FROM_ALL)
target_link_libraries(photonMapping PRIVATE photonMapping-ptx owl::owl)