# connection-logger

A TCP connection logger written straight against the POSIX sockets API. A server
accepts a connection and logs everything that arrives on it; a client connects and
reports its own end of the pair. No frameworks — the syscalls are the point.

```
$ ./scripts/dev.sh server              $ ./scripts/dev.sh client slow
Listening to port 8080
Client connected                       sent: [Hello]
chuck 1:5bytes [ Hello]                sent: [, ]
chuck 2:2bytes [ , ]                   sent: [world!]
chuck 3:6bytes [ world!]
Client closed the connection
```

## Getting started

```bash
brew install cmake ninja            # macOS; apt: cmake ninja-build
./scripts/dev.sh build
./scripts/dev.sh server             # terminal 1
./scripts/dev.sh client             # terminal 2
```

## The dev CLI

Everything routine goes through `./scripts/dev.sh`:

| Command | What it does |
| --- | --- |
| `build [--release\|--asan\|--werror]` | Configure + build |
| `server [--v1]` | Run the server (`--v1` runs the original `src/server/server.cpp`) |
| `client [slow]` | Run the client against `127.0.0.1:8080` (`slow` spaces the sends out) |
| `test` | Build, then run the CTest suite |
| `lint` | clang-tidy over every source file |
| `fmt [--check]` | clang-format |
| `ci` | Everything CI runs, locally |
| `branch <name>` | Start `feature/<name>` off `main` |
| `pr` | Push the branch and open a PR against `main` |
| `clean` | Remove `build/` and `build-asan/` |

## Repo layout

```
src/server/
  server_v2.cpp      current server — logs every chunk until the peer hangs up
  server.cpp         v1 server — logs the peer address, then exits
src/client/
  client_v2.cpp      current client — sends a message in three parts, send-all loop
  client.cpp         v1 client — connects, prints its own address, closes
CMakeLists.txt       build + test definitions
tests/smoke_test.sh  end-to-end test: real server + real client over a real socket
scripts/dev.sh       the dev CLI
scripts/setup_repo.sh  one-time GitHub setup (owner runs this)
CLAUDE.md            project rules — also what the PR reviewer enforces
CONTRIBUTING.md      branch, commit, and PR rules
```

## Tests

```bash
./scripts/dev.sh test
```

Two end-to-end tests, one per server binary. Each starts the real server, drives
it with the real client, and asserts on what the server logged. Both bind port
8080, so CTest serializes them with a resource lock.

## How a change gets to main

`main` is protected: no direct pushes, no force-pushes, squash merges only.

1. `./scripts/dev.sh branch my-change`
2. Commit, then `./scripts/dev.sh pr`
3. CI runs: build on GCC and Clang with `-Werror`, tests under ASan + UBSan,
   clang-tidy, shellcheck.
4. **Claude reviews the PR.** It reads the diff against the rules in `CLAUDE.md`
   and returns a verdict. `approve` passes the check; `request_changes` fails it
   and lists what's blocking, inline on the diff.
5. GitHub blocks the merge button until **Claude review** and every CI check is
   green. Then squash-merge.

The gate fails closed — if the review can't run or returns nothing, the merge
stays blocked. Details in `CONTRIBUTING.md`.

You can also mention `@claude` in any PR or issue comment to ask a question or
ask for a change; that's interactive and never gates a merge.

## One-time setup (repo owner)

```bash
# 1. the key the review gate runs on
gh secret set ANTHROPIC_API_KEY --repo Sushanta451/connection-logger

# 2. branch ruleset + merge settings (asks before it changes anything)
./scripts/setup_repo.sh --dry-run
./scripts/setup_repo.sh
```

Required status checks only start blocking once GitHub has seen each check run
once, so the first PR after setup is what registers them.

## Known limitations

- Both servers handle exactly one connection, then exit. An accept loop is the
  obvious next step.
- `SO_NOSIGPIPE` (macOS) and `MSG_NOSIGNAL` (Linux) are both needed to keep a
  write to a hung-up peer from killing the client; `src/client/client_v2.cpp`
  guards them with `#ifdef`.
- The port is hardcoded to 8080 in all three binaries.
- The smoke test asserts after the server exits, because `std::cout` is
  block-buffered when redirected to a file. A server that ran forever would need
  explicit flushes to be testable the same way.
