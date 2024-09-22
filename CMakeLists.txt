cmake_minimum_required(VERSION 3.27)
project(photonMapping CUDA CXX C)

include(cmake/embed_ptx.cmake)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CUDA_STANDARD 11)
set(OptiX_ROOT_DIR $ENV{OptiX_INSTALL_DIR})
set(CMAKE_PREFIX_PATH $ENV{OptiX_INSTALL_DIR})

set(owl_dir ${PROJECT_SOURCE_DIR}/externals/owl)
set(assimp_dir ${PROJECT_SOURCE_DIR}/externals/assimp)
set(cukd_dir ${PROJECT_SOURCE_DIR}/externals/cudaKDTree)
add_subdirectory(${owl_dir} EXCLUDE_FROM_ALL)
add_subdirectory(${cukd_dir} EXCLUDE_FROM_ALL)
add_subdirectory(${assimp_dir} EXCLUDE_FROM_ALL)

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
    cudaKDTree
    owl::owl
  SOURCES
    ray-tracer/cuda/deviceCode.cu
)

add_executable(photonMapping photon-mapping/src/hostCode.cxx)
add_executable(rayTracer ray-tracer/src/hostCode.cxx)

set(common_sources
    common/src/assetImporter.h
    common/src/assetImporter.cxx
    common/src/mesh.h
    common/src/world.h
    common/src/material.h
    common/src/light.h
    common/src/ray.h
)

target_sources(rayTracer
        PRIVATE
        # NOTE: the headers aren't really necessary but CLion will complain without them here.
        ${common_sources}
)

target_sources(photonMapping
        PRIVATE
        # NOTE: the headers aren't really necessary but CLion will complain without them here.
        ${common_sources}
)

target_link_libraries(photonMapping PRIVATE photonMapping-ptx owl::owl assimp::assimp)
target_link_libraries(rayTracer PRIVATE rayTracer-ptx owl::owl assimp::assimp cudaKDTree)

set_target_properties(cudaKDTree PROPERTIES CUDA_SEPARABLE_COMPILATION ON)