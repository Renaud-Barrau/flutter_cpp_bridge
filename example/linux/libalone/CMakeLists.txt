cmake_minimum_required(VERSION 3.13)
project(libalone LANGUAGES CXX)

add_library(libalone SHARED libalone.cpp)
target_compile_features(libalone PRIVATE cxx_std_17)
set_target_properties(libalone PROPERTIES
  CXX_VISIBILITY_PRESET default
  PREFIX ""          # produce libalone.so, not liblibalone.so
)
