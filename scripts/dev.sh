#!/usr/bin/env bash
# connection-logger dev CLI — one entry point for every routine task.
#
#   ./scripts/dev.sh build            configure + build (Debug)
#   ./scripts/dev.sh build --release  optimized build
#   ./scripts/dev.sh build --asan     build with AddressSanitizer + UBSan
#   ./scripts/dev.sh server           run the current server (server_v2.cpp)
#   ./scripts/dev.sh server --v1      run the v1 server (server.cpp)
#   ./scripts/dev.sh client           run the client against 127.0.0.1:8080
#   ./scripts/dev.sh client slow      same, but 500ms between the three sends
#   ./scripts/dev.sh client --v1      run the v1 client (client.cpp)
#   ./scripts/dev.sh test             build, then run the CTest suite
#   ./scripts/dev.sh lint             clang-tidy over every source file
#   ./scripts/dev.sh fmt              clang-format in place
#   ./scripts/dev.sh fmt --check      fail if anything is unformatted (CI mode)
#   ./scripts/dev.sh ci               everything CI runs, locally
#   ./scripts/dev.sh branch <name>    start a feature/<name> branch off main
#   ./scripts/dev.sh pr               push the branch and open a PR against main
#   ./scripts/dev.sh clean            delete build directories
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

build_dir="build"
sources=(server.cpp server_v2.cpp client.cpp client_v2.cpp)

die() { echo "error: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

generator() {
  if have ninja; then echo "Ninja"; else echo "Unix Makefiles"; fi
}

cmd_build() {
  local build_type="Debug" asan="OFF" werror="OFF"
  for arg in "$@"; do
    case "${arg}" in
      --release) build_type="RelWithDebInfo" ;;
      --asan)    asan="ON"; build_dir="build-asan" ;;
      --werror)  werror="ON" ;;
      *) die "unknown build flag: ${arg}" ;;
    esac
  done

  have cmake || die "cmake not found (brew install cmake)"

  cmake -S . -B "${build_dir}" -G "$(generator)" \
    -DCMAKE_BUILD_TYPE="${build_type}" \
    -DENABLE_ASAN="${asan}" \
    -DCONNLOG_WERROR="${werror}" \
    -DBUILD_TESTING=ON
  cmake --build "${build_dir}"
  echo
  echo "binaries in ${build_dir}/: connlog-server, connlog-server-v1, connlog-client"
}

# Pick the build directory the requested flags imply, then build only if the
# binaries are not there yet.
ensure_built() {
  for arg in "$@"; do
    [ "${arg}" = "--asan" ] && build_dir="build-asan"
  done
  [ -x "${build_dir}/connlog-server" ] || cmd_build "$@"
}

cmd_server() {
  local target="connlog-server"
  [ "${1:-}" = "--v1" ] && target="connlog-server-v1"
  ensure_built
  echo "running ${target} (ctrl-c to stop)"
  exec "./${build_dir}/${target}"
}

cmd_client() {
  local target="connlog-client"
  if [ "${1:-}" = "--v1" ]; then
    target="connlog-client-v1"
    shift
  fi
  ensure_built
  exec "./${build_dir}/${target}" "$@"
}

cmd_test() {
  ensure_built "$@"
  ctest --test-dir "${build_dir}" --output-on-failure
}

cmd_lint() {
  have clang-tidy || die "clang-tidy not found (brew install llvm, then add it to PATH)"
  [ -f "${build_dir}/compile_commands.json" ] || cmd_build
  clang-tidy -p "${build_dir}" "${sources[@]}"
}

cmd_fmt() {
  have clang-format || die "clang-format not found (brew install clang-format)"
  if [ "${1:-}" = "--check" ]; then
    clang-format --dry-run --Werror "${sources[@]}"
    echo "formatting ok"
  else
    clang-format -i "${sources[@]}"
    echo "formatted: ${sources[*]}"
  fi
}

# Mirrors .github/workflows/ci.yml as closely as a laptop can. Formatting is
# deliberately not part of this: clang-format is a convenience here, not a gate.
cmd_ci() {
  cmd_build --werror
  cmd_test
  if have clang-tidy; then
    cmd_lint
  else
    echo "skipping lint (clang-tidy not installed)"
  fi
  echo
  echo "local CI passed — the Claude review gate only runs on the PR itself"
}

cmd_branch() {
  local name="${1:-}"
  [ -n "${name}" ] || die "usage: dev.sh branch <name>   (creates feature/<name>)"
  [ -z "$(git status --porcelain)" ] || die "working tree is dirty — commit or stash first"
  git checkout main
  git pull --ff-only origin main
  git checkout -b "feature/${name}"
  echo "on feature/${name} — commit your work, then ./scripts/dev.sh pr"
}

cmd_pr() {
  have gh || die "gh not found (brew install gh && gh auth login)"
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [ "${branch}" != "main" ] || die "you are on main — branch first: ./scripts/dev.sh branch <name>"
  [ -z "$(git status --porcelain)" ] || die "uncommitted changes — commit them before opening a PR"

  git push -u origin "${branch}"
  gh pr create --base main --head "${branch}" --fill
  echo
  echo "CI + the Claude review gate run now. Merge is blocked until 'Claude review' passes."
  echo "Watch it with: gh pr checks --watch"
}

cmd_clean() {
  rm -rf build build-asan
  echo "removed build/ and build-asan/"
}

usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "${BASH_SOURCE[0]}"; }

case "${1:-help}" in
  build)  shift; cmd_build "$@" ;;
  server) shift; cmd_server "$@" ;;
  client) shift; cmd_client "$@" ;;
  test)   shift; cmd_test "$@" ;;
  lint)   shift; cmd_lint "$@" ;;
  fmt)    shift; cmd_fmt "$@" ;;
  ci)     shift; cmd_ci "$@" ;;
  branch) shift; cmd_branch "$@" ;;
  pr)     shift; cmd_pr "$@" ;;
  clean)  shift; cmd_clean "$@" ;;
  help|-h|--help) usage ;;
  *) echo "unknown command: $1" >&2; echo >&2; usage >&2; exit 2 ;;
esac
