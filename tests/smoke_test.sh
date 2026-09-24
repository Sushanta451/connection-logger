#!/usr/bin/env bash
# End-to-end smoke test: start a server binary, point the real client at it, and
# assert on what the server logged.
#
# Usage: smoke_test.sh <server-binary> <client-binary> <expected-line>...
#
# Notes for anyone extending this:
#   * Readiness is detected by retrying the client, not by grepping the log.
#     std::cout is block-buffered when stdout is a file, so nothing the server
#     prints is visible until it exits — and a probe that opened a TCP
#     connection would eat the server's single accept().
#   * The assertions therefore run after the server process exits, which it does
#     once the client hangs up. A server that loops forever would need a
#     different harness (flush on write, or drive it over a pty).
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <server-binary> <client-binary> <expected-line>..." >&2
  exit 2
fi

server="$1"
client="$2"
shift 2
expected=("$@")

server_log="$(mktemp -t connlog-server.XXXXXX)"
client_log="$(mktemp -t connlog-client.XXXXXX)"
server_pid=""

# shellcheck disable=SC2317,SC2329  # invoked through the EXIT trap
cleanup() {
  if [ -n "${server_pid}" ] && kill -0 "${server_pid}" 2>/dev/null; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  rm -f "${server_log}" "${client_log}"
}
trap cleanup EXIT

# shellcheck disable=SC2317,SC2329  # invoked from the failure paths below
dump_logs() {
  echo "--- server output ---" >&2
  cat "${server_log}" >&2
  echo "--- client output ---" >&2
  cat "${client_log}" >&2
}

"${server}" >"${server_log}" 2>&1 &
server_pid=$!

# Retry the client until the listener is up. A refused connect costs the server
# nothing, so this is safe to repeat.
connected=0
for _ in $(seq 1 100); do
  if "${client}" >"${client_log}" 2>&1; then
    connected=1
    break
  fi
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    echo "FAIL: server exited before accepting a connection" >&2
    dump_logs
    exit 1
  fi
  sleep 0.1
done

if [ "${connected}" -ne 1 ]; then
  echo "FAIL: client never connected (is port 8080 already in use?)" >&2
  dump_logs
  exit 1
fi

# Both servers hang up and exit once the client disconnects; that exit is what
# flushes their stdout.
for _ in $(seq 1 100); do
  kill -0 "${server_pid}" 2>/dev/null || break
  sleep 0.1
done

if kill -0 "${server_pid}" 2>/dev/null; then
  echo "FAIL: server still running 10s after the client disconnected" >&2
  dump_logs
  exit 1
fi

wait "${server_pid}" 2>/dev/null || true
server_pid=""

status=0
for line in "${expected[@]}"; do
  if grep -qF "${line}" "${server_log}"; then
    echo "ok: server logged '${line}'"
  else
    echo "FAIL: server never logged '${line}'" >&2
    status=1
  fi
done

[ "${status}" -eq 0 ] || dump_logs
exit "${status}"
