cmake_minimum_required(VERSION 3.14)
project(libmessage LANGUAGES CXX)

# ── FlatBuffers (fetched at configure time if not installed) ──────────────────
include(FetchContent)
FetchContent_Declare(
    flatbuffers
    GIT_REPOSITORY https://github.com/google/flatbuffers.git
    GIT_TAG        v24.3.25
    GIT_SHALLOW    TRUE
)
# Build only what we need: the compiler (flatc) and the headers.
set(FLATBUFFERS_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_BUILD_FLATLIB  OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_BUILD_FLATHASH OFF CACHE BOOL "" FORCE)
set(FLATBUFFERS_INSTALL        OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(flatbuffers)

# ── Generate C++ header from the schema ──────────────────────────────────────
# Re-runs flatc whenever messages.fbs changes.
set(GENERATED_HEADER "${CMAKE_CURRENT_BINARY_DIR}/messages_generated.h")

add_custom_command(
    OUTPUT  "${GENERATED_HEADER}"
    COMMAND "$<TARGET_FILE:flatc>"
            --cpp --gen-mutable
            -o "${CMAKE_CURRENT_BINARY_DIR}"
            "${CMAKE_CURRENT_SOURCE_DIR}/messages.fbs"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/messages.fbs" flatc
    COMMENT "Generating FlatBuffers C++ header for libmessage"
    VERBATIM
)
add_custom_target(libmessage_fbs DEPENDS "${GENERATED_HEADER}")

# ── Service shared library ────────────────────────────────────────────────────
add_library(libmessage SHARED libmessage.cpp)
add_dependencies(libmessage libmessage_fbs)

target_compile_features(libmessage PRIVATE cxx_std_17)
target_include_directories(libmessage PRIVATE
    "${FCB_CPP_INCLUDE}"                    # flutter_cpp_bridge/service_helpers.h
    "${flatbuffers_SOURCE_DIR}/include"     # flatbuffers/flatbuffers.h
    "${CMAKE_CURRENT_BINARY_DIR}"           # messages_generated.h
)
set_target_properties(libmessage PROPERTIES
    CXX_VISIBILITY_PRESET default
    PREFIX ""   # produce libmessage.so, not liblibmessage.so
)
