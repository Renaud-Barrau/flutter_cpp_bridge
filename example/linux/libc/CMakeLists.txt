cmake_minimum_required(VERSION 3.13)
project(libc LANGUAGES CXX)

add_library(libc SHARED libc.cpp)
target_compile_features(libc PRIVATE cxx_std_17)
target_include_directories(libc PRIVATE "${FCB_CPP_INCLUDE}")
set_target_properties(libc PROPERTIES
  CXX_VISIBILITY_PRESET default
  PREFIX ""
)
