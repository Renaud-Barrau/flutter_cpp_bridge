cmake_minimum_required(VERSION 3.13)
project(liba LANGUAGES CXX)

add_library(liba SHARED liba.cpp)
target_compile_features(liba PRIVATE cxx_std_17)
target_include_directories(liba PRIVATE "${FCB_CPP_INCLUDE}")
set_target_properties(liba PROPERTIES
  CXX_VISIBILITY_PRESET default
  PREFIX ""          # produce liba.so, not libliba.so
)
