cmake_minimum_required(VERSION 3.27)
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
    photon-mapping/cuda/deviceCode.cu
)

embed_ptx(
  OUTPUT_TARGET
    rayTracer-ptx
  PTX_LINK_LIBRARIES
    owl::owl
  SOURCES
    ray-tracer/cuda/deviceCode.cu
)

add_executable(photonMapping photon-mapping/src/hostCode.cxx)
add_executable(rayTracer ray-tracer/src/hostCode.cxx)

target_sources(rayTracer
        PRIVATE
            ray-tracer/src/assetImporter.h
            ray-tracer/src/assetImporter.cxx
)

set(owl_dir ${PROJECT_SOURCE_DIR}/externals/owl)
set(assimp_dir ${PROJECT_SOURCE_DIR}/externals/assimp)
add_subdirectory(${owl_dir} EXCLUDE_FROM_ALL)
add_subdirectory(${assimp_dir} EXCLUDE_FROM_ALL)
target_link_libraries(photonMapping PRIVATE photonMapping-ptx owl::owl assimp::assimp)
target_link_libraries(rayTracer PRIVATE rayTracer-ptx owl::owl assimp::assimp)