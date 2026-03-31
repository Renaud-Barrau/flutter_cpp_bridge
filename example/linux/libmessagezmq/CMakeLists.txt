cmake_minimum_required(VERSION 3.14)
project(libmessagezmq LANGUAGES CXX)

# ── FlatBuffers (reuse if already fetched by libmessage) ──────────────────────
include(FetchContent)
FetchContent_GetProperties(flatbuffers)
if(NOT flatbuffers_POPULATED)
    FetchContent_Declare(
        flatbuffers
        GIT_REPOSITORY https://github.com/google/flatbuffers.git
        GIT_TAG        v24.3.25
        GIT_SHALLOW    TRUE
    )
    set(FLATBUFFERS_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
    set(FLATBUFFERS_BUILD_FLATLIB  OFF CACHE BOOL "" FORCE)
    set(FLATBUFFERS_BUILD_FLATHASH OFF CACHE BOOL "" FORCE)
    set(FLATBUFFERS_INSTALL        OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(flatbuffers)
    FetchContent_GetProperties(flatbuffers)
endif()

# ── ZMQ ───────────────────────────────────────────────────────────────────────
find_package(PkgConfig REQUIRED)
pkg_check_modules(ZMQ REQUIRED IMPORTED_TARGET libzmq)
# cppzmq is header-only; zmq.hpp is expected on the system include path
# (install: apt install cppzmq-dev)
find_path(CPPZMQ_INCLUDE_DIR zmq.hpp REQUIRED)

# ── Generate C++ header from the schema ──────────────────────────────────────
# libmessagezmq shares the same FlatBuffers schema as libmessage.
set(SCHEMA "${CMAKE_CURRENT_SOURCE_DIR}/messages.fbs")
set(GENERATED_HEADER "${CMAKE_CURRENT_BINARY_DIR}/messages_generated.h")

add_custom_command(
    OUTPUT  "${GENERATED_HEADER}"
    COMMAND "$<TARGET_FILE:flatc>"
            --cpp --gen-mutable
            -o "${CMAKE_CURRENT_BINARY_DIR}"
            "${SCHEMA}"
    DEPENDS "${SCHEMA}" flatc
    COMMENT "Generating FlatBuffers C++ header for libmessagezmq"
    VERBATIM
)
add_custom_target(libmessagezmq_fbs DEPENDS "${GENERATED_HEADER}")

# ── Service shared library ────────────────────────────────────────────────────
add_library(libmessagezmq SHARED libmessagezmq.cpp)
add_dependencies(libmessagezmq libmessagezmq_fbs)

target_compile_features(libmessagezmq PRIVATE cxx_std_17)
target_include_directories(libmessagezmq PRIVATE
    "${FCB_CPP_INCLUDE}"                    # flutter_cpp_bridge/service_helpers.h
    "${flatbuffers_SOURCE_DIR}/include"     # flatbuffers/flatbuffers.h
    "${CPPZMQ_INCLUDE_DIR}"                 # zmq.hpp
    "${CMAKE_CURRENT_BINARY_DIR}"           # messages_generated.h
)
target_link_libraries(libmessagezmq PRIVATE PkgConfig::ZMQ)
set_target_properties(libmessagezmq PROPERTIES
    CXX_VISIBILITY_PRESET default
    PREFIX ""   # produce libmessagezmq.so, not liblibmessagezmq.so
)
