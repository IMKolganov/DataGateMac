# DataGateMac engine: build OpenVPN 3 core for macOS.
# Mirrors DataGateWin/engine approach: same source set, same deps (OpenSSL, fmt, jsoncpp, lz4, xxhash, asio).
# Use from repo root: mkdir build-engine && cd build-engine && cmake ../engine && cmake --build .

cmake_minimum_required(VERSION 3.22)
project(datagate-engine LANGUAGES CXX)

if(NOT APPLE)
  message(FATAL_ERROR "This CMake is for macOS only. Use DataGateWin/engine for Windows.")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# OpenVPN 3 source tree (git submodule at repo root)
set(O3_DIR_RAW "${CMAKE_CURRENT_LIST_DIR}/../openvpn3")
get_filename_component(O3_DIR "${O3_DIR_RAW}" REALPATH)
if(NOT EXISTS "${O3_DIR}/client/ovpncli.cpp")
  message(FATAL_ERROR "openvpn3 not found at ${O3_DIR}. Run: git submodule update --init --recursive")
endif()

# Use openvpn3's Findasio.cmake if needed (asio is header-only)
set(CMAKE_MODULE_PATH "${O3_DIR}/cmake" ${CMAKE_MODULE_PATH})

# jsoncpp: build static here so the packet tunnel appex does not link Homebrew dylibs (Team ID mismatch at extension load).
include(FetchContent)
set(JSONCPP_WITH_TESTS OFF CACHE BOOL "" FORCE)
set(JSONCPP_WITH_POST_BUILD_UNITTEST OFF CACHE BOOL "" FORCE)
# jsoncpp uses BUILD_SHARED_LIBS / BUILD_STATIC_LIBS (not only BUILD_SHARED_LIBS).
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
FetchContent_Declare(
  jsoncpp
  GIT_REPOSITORY https://github.com/open-source-parsers/jsoncpp.git
  GIT_TAG 1.9.6
)
FetchContent_MakeAvailable(jsoncpp)

# Dependencies (Homebrew: brew install asio cmake fmt lz4 openssl pkg-config xxhash — jsoncpp is vendored above)
find_package(OpenSSL REQUIRED)
find_package(fmt CONFIG REQUIRED)
find_package(lz4 REQUIRED)
find_package(xxHash CONFIG REQUIRED)
find_package(asio REQUIRED)
find_package(Threads REQUIRED)

# Same source set as DataGateWin/engine: client + openvpn, exclude agent and omi/openvpn.cpp
file(GLOB_RECURSE OPENVPN3_CORE_SOURCES
  "${O3_DIR}/client/*.cpp"
  "${O3_DIR}/openvpn/*.cpp"
)
list(FILTER OPENVPN3_CORE_SOURCES EXCLUDE REGEX ".*/openvpn/ovpnagent/.*")
# openvpn/omi/openvpn.cpp pulls unix peercred; exclude for cleaner cross-platform core
list(FILTER OPENVPN3_CORE_SOURCES EXCLUDE REGEX ".*/openvpn/omi/openvpn\\.cpp$")

add_library(ovpn3-core STATIC ${OPENVPN3_CORE_SOURCES})

target_include_directories(ovpn3-core PUBLIC "${O3_DIR}")

target_compile_definitions(ovpn3-core PUBLIC
  USE_ASIO
  USE_OPENSSL
  HAVE_LZ4
  ASIO_STANDALONE
  USE_TUN_BUILDER
)

# macOS system frameworks (same as openvpn3 findcoredeps for APPLE)
find_library(coreFoundation CoreFoundation)
find_library(iokit IOKit)
find_library(coreServices CoreServices)
find_library(systemConfiguration SystemConfiguration)

target_link_libraries(ovpn3-core PUBLIC
  OpenSSL::SSL
  OpenSSL::Crypto
  fmt::fmt
  jsoncpp_static
  lz4::lz4
  xxHash::xxhash
  asio::asio
  Threads::Threads
  ${coreFoundation}
  ${iokit}
  ${coreServices}
  ${systemConfiguration}
)

# Single path for Xcode: link libjsoncpp.a next to libovpn3-core.a (static; avoids /opt/homebrew jsoncpp dylib).
add_custom_command(
  TARGET ovpn3-core POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:jsoncpp_static>
    ${CMAKE_BINARY_DIR}/libjsoncpp.a
  COMMENT "Export libjsoncpp.a for DataGateMacPacketTunnel (static link)"
)

# Allow alternate fmt target name (vcpkg uses fmt-header-only)
if(NOT TARGET fmt::fmt)
  if(TARGET fmt::fmt-header-only)
    add_library(fmt::fmt ALIAS fmt::fmt-header-only)
  endif()
endif()

# ovpncli.cpp can be large; allow larger object file if needed
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|AppleClang")
  foreach(_src IN LISTS OPENVPN3_CORE_SOURCES)
    if(_src MATCHES ".*/client/ovpncli\\.cpp$")
      set_source_files_properties("${_src}" PROPERTIES COMPILE_OPTIONS "-Wno-deprecated-declarations")
    endif()
  endforeach()
endif()

message(STATUS "ovpn3-core: ${O3_DIR} (${OPENVPN3_CORE_SOURCES} sources)")
