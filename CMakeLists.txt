cmake_minimum_required(VERSION 3.20)

project(connection-logger
  VERSION 0.1.0
  DESCRIPTION "A TCP connection logger: POSIX socket server + client, built from scratch"
  LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# clangd / clang-tidy read this; CI configures with it and lints from build/.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
endif()

option(CONNLOG_WERROR "Treat compiler warnings as errors (CI turns this on)" OFF)
option(ENABLE_ASAN "Build with AddressSanitizer + UndefinedBehaviorSanitizer" OFF)

# Warning/sanitizer policy lives in one interface target so every binary gets
# exactly the same flags. Add new targets by linking connlog_flags.
add_library(connlog_flags INTERFACE)
target_compile_options(connlog_flags INTERFACE
  -Wall -Wextra -Wpedantic -Wshadow -Wconversion)
if(CONNLOG_WERROR)
  target_compile_options(connlog_flags INTERFACE -Werror)
endif()
if(ENABLE_ASAN)
  target_compile_options(connlog_flags INTERFACE
    -fsanitize=address,undefined -fno-omit-frame-pointer -g)
  target_link_options(connlog_flags INTERFACE -fsanitize=address,undefined)
endif()

# --- binaries -----------------------------------------------------------------
# server.cpp    : v1, accepts one connection and logs the peer, then exits.
# server_v2.cpp : current server, accepts one connection and logs every chunk
#                 until the peer hangs up.
# client.cpp    : v1, connects and reports its own end of the pair.
# client_v2.cpp : current client, sends a message in three parts through a
#                 send-all loop. Pass "slow" to space the parts 500ms apart and
#                 watch the server log them as separate chunks.
add_executable(connlog-server server_v2.cpp)
add_executable(connlog-server-v1 server.cpp)
add_executable(connlog-client client_v2.cpp)
add_executable(connlog-client-v1 client.cpp)

foreach(target connlog-server connlog-server-v1 connlog-client connlog-client-v1)
  target_link_libraries(${target} PRIVATE connlog_flags)
endforeach()

# --- tests --------------------------------------------------------------------
include(CTest)

if(BUILD_TESTING)
  set(SMOKE_TEST "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke_test.sh")

  # End-to-end: run the real binaries against each other over a real socket and
  # assert on what the server logged. No mocks — this is the whole product.
  # The current pair: the client sends "Hello, world!" in three parts and the
  # server has to log the bytes and then notice the hangup.
  add_test(NAME server_logs_chunks_and_hangup
    COMMAND "${SMOKE_TEST}"
      $<TARGET_FILE:connlog-server>
      $<TARGET_FILE:connlog-client>
      "Listening to port 8080"
      "Client connected"
      "Hello"
      "world!"
      "Client closed the connection")

  add_test(NAME server_v1_logs_peer_address
    COMMAND "${SMOKE_TEST}"
      $<TARGET_FILE:connlog-server-v1>
      $<TARGET_FILE:connlog-client-v1>
      "wait for client"
      "Connection from 127.0.0.1:")

  # Every binary binds the same hardcoded port, so never run these concurrently
  # (ctest -j would otherwise hand one of them EADDRINUSE).
  set_tests_properties(server_logs_chunks_and_hangup server_v1_logs_peer_address
    PROPERTIES RESOURCE_LOCK tcp_port_8080 TIMEOUT 30)
endif()
