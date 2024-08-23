cmake_minimum_required(VERSION 3.29)
project(testing CUDA)

set(CMAKE_CUDA_STANDARD 11)

add_executable(testing main.cu)

set_target_properties(testing PROPERTIES
        CUDA_SEPARABLE_COMPILATION ON)
