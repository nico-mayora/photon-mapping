cmake_minimum_required(VERSION 3.27)
project(photonMapping CUDA CXX C)

include(cmake/embed_ptx.cmake)
set(CMAKE_CUDA_STANDARD 17)
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
    photonViewer-ptx
  PTX_LINK_LIBRARIES
    owl::owl
  SOURCES
    photon-viewer/cuda/deviceCode.cu
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

add_executable(photonMapping photon-mapping/src/hostCode.cu
        common/src/world.cpp)
add_executable(photonViewer photon-viewer/src/hostCode.cu
        common/src/world.cpp)
add_executable(rayTracer ray-tracer/src/hostCode.cu
        common/src/world.cpp)

set(common_sources
    common/src/assetImporter.h
    common/src/configLoader.h
    common/src/assetImporter.cxx
    common/src/mesh.h
    common/src/world.h
    common/src/ray.h
    common/src/camera.h
    common/src/common.h
)

target_sources(rayTracer
  PRIVATE
    ${common_sources}
)

target_sources(photonViewer
  PRIVATE
    ${common_sources}
)

target_sources(photonMapping
  PRIVATE
    ${common_sources}
)

include_directories(
    externals/glm
)

set(owl_dir ${PROJECT_SOURCE_DIR}/externals/owl)
set(assimp_dir ${PROJECT_SOURCE_DIR}/externals/assimp)
set(cukd_dir ${PROJECT_SOURCE_DIR}/externals/cudaKDTree)

add_subdirectory(${owl_dir} EXCLUDE_FROM_ALL)
add_subdirectory(${cukd_dir} EXCLUDE_FROM_ALL)
add_subdirectory(${assimp_dir} EXCLUDE_FROM_ALL)

target_link_libraries(photonMapping PRIVATE photonMapping-ptx owl::owl assimp::assimp)
target_link_libraries(photonViewer PRIVATE photonViewer-ptx owl::owl assimp::assimp)
target_link_libraries(rayTracer PRIVATE rayTracer-ptx owl::owl assimp::assimp cudaKDTree)

set_property(TARGET rayTracer PROPERTY CXX_STANDARD 17)
target_compile_features(rayTracer PRIVATE cxx_std_17)
target_compile_features(photonViewer PRIVATE cxx_std_17)
target_compile_features(photonMapping PRIVATE cxx_std_17)