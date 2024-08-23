cmake_minimum_required(VERSION 3.29)
project(testing CUDA CXX C)

include(cmake/embed_ptx.cmake)

set(CMAKE_CUDA_STANDARD 11)
set(OptiX_ROOT_DIR $ENV{OptiX_INSTALL_DIR})
set(CMAKE_PREFIX_PATH $ENV{OptiX_INSTALL_DIR})

#set_target_properties(testing PROPERTIES
#        CUDA_SEPARABLE_COMPILATION ON)

embed_ptx(
  OUTPUT_TARGET
    testing-ptx
  PTX_LINK_LIBRARIES
    owl::owl
  SOURCES
    deviceCode.cu
)

add_executable(testing hostCode.cxx)

set(owl_dir ${PROJECT_SOURCE_DIR}/externals/owl)
add_subdirectory(${owl_dir} EXCLUDE_FROM_ALL)
target_link_libraries(testing PRIVATE testing-ptx owl::owl)