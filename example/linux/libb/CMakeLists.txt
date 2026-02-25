cmake_minimum_required(VERSION 3.13)
project(libb LANGUAGES CXX)

add_library(libb SHARED libb.cpp)
target_compile_features(libb PRIVATE cxx_std_17)
target_include_directories(libb PRIVATE "${FCB_CPP_INCLUDE}")
set_target_properties(libb PROPERTIES
  CXX_VISIBILITY_PRESET default
  PREFIX ""          # produce libb.so, not liblibb.so
)
