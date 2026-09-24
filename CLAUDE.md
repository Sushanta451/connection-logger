# connection-logger — Project Context for Claude Code

A TCP connection logger written directly against the POSIX sockets API: a server
that accepts a connection and logs what arrives on it, and a client that connects
and reports its own end of the pair. No frameworks, no wrappers — the point of the
project is the syscalls themselves.

## Why this stack

Raw BSD sockets in C++20, built with CMake. Every abstraction that would normally
hide `bind`/`listen`/`accept`/`recv` is deliberately absent, because the goal is to
understand the connection lifecycle, not to ship a web server. Prefer the plain
syscall over a library that wraps it.

## Repo layout

| Path | What it is |
| --- | --- |
| `server_v2.cpp` | Current server. Accepts one connection, logs every chunk until the peer hangs up. Built as `connlog-server`. |
| `server.cpp` | v1 server. Accepts one connection, logs the peer address and the descriptor numbers, exits. Built as `connlog-server-v1`. Kept as a reference for the minimal accept path. |
| `client.cpp` | Connects to `127.0.0.1:8080`, prints its own address via `getsockname`, closes. Built as `connlog-client`. |
| `CMakeLists.txt` | Build + test definitions. Warning and sanitizer flags live in the `connlog_flags` interface target. |
| `tests/smoke_test.sh` | End-to-end test: runs a real server and a real client against each other and asserts on the server's log. |
| `scripts/dev.sh` | The dev CLI. Every routine task goes through it. |
| `scripts/setup_repo.sh` | One-time GitHub setup (branch ruleset, merge settings). The user runs this, not Claude. |
| `.github/workflows/` | `ci.yml` (build/test/lint), `claude-review.yml` (the merge gate), `claude.yml` (@claude mentions). |

## Build system

CMake ≥ 3.20, C++20, Ninja when available. Three binaries, one interface target
(`connlog_flags`) carrying the warning and sanitizer policy — new targets link it
so flags never drift between binaries.

- `-Wall -Wextra -Wpedantic -Wshadow -Wconversion` everywhere.
- `-DCONNLOG_WERROR=ON` turns those into errors. CI builds with it on; keep the
  tree warning-clean or CI goes red.
- `-DENABLE_ASAN=ON` adds AddressSanitizer + UBSan, into `build-asan/`.

### Quick start

```bash
./scripts/dev.sh build          # configure + build into build/
./scripts/dev.sh server         # terminal 1
./scripts/dev.sh client         # terminal 2
./scripts/dev.sh test           # the CTest suite
./scripts/dev.sh ci             # everything CI runs, locally
```

Run `./scripts/dev.sh help` for the full command list. Use the CLI rather than
raw `cmake`/`ctest` invocations so local runs match CI.

## Critical rules

These are what the PR review gate enforces. Violating one blocks the merge.

### Syscalls
- **Check every return value.** `socket`, `setsockopt`, `bind`, `listen`,
  `accept`, `connect`, `recv`, `send`, `close`, `inet_pton`, `getaddrinfo` — all
  of them. On failure, print to `stderr` with `std::strerror(errno)` and return
  non-zero.
- `getaddrinfo` reports errors through `gai_strerror`, **not** `errno`.
- **Close every descriptor on every path**, including the error paths. A `return 1`
  between `socket()` and `close()` is a descriptor leak.

### recv / send
- `recv` has three outcomes and all three must be handled: `-1` is an error (retry
  on `EINTR`, bail otherwise), `0` means the peer closed the connection, `> 0` is
  a byte count.
- A `recv` buffer is **not** a string. It is not NUL-terminated. Print it with
  `std::string_view(buf, n)`, never `std::cout << buf`.
- Always bound the read by `sizeof(buf)`.
- `send` may transmit fewer bytes than asked. Loop until everything is out, or
  explain in a comment why a partial send is impossible here.

### Addresses and byte order
- Ports and addresses cross the boundary in network byte order: `htons`/`htonl`
  going out, `ntohs`/`ntohl` coming in. A missing conversion is a bug even when it
  happens to work on this machine.
- `reinterpret_cast<sockaddr*>(&addr)` is the expected cast for
  `bind`/`connect`/`accept`. It is not a smell here.
- `inet_ntop` for printing, `inet_pton` for parsing. Never `inet_addr`.

### C++ style
- C++20. Brace initialization (`int fd{socket(...)}`) — it is the style already in
  the tree and it catches narrowing.
- Errors to `stderr`, normal output to `stdout`.
- `std::cout` is block-buffered when redirected, so anything a long-running server
  prints may not appear until it exits. End a line that must be visible
  immediately with `std::flush` or `std::endl`. `tests/smoke_test.sh` works around
  this by asserting after the process exits — read its header comment before
  changing it.
- Keep the code readable over clever. This is a learning project; a comment
  explaining *why* a syscall is called the way it is earns its place.

### Security
- Never commit secrets, API keys, or credentials.
- Never trust a length that came off the wire without bounding it against the
  buffer.
- Bind to `INADDR_ANY` only when the program is meant to be reachable; prefer
  `INADDR_LOOPBACK` for experiments.

## Testing

`tests/smoke_test.sh` runs the real binaries against each other over a real
socket and asserts on the server's log. CTest wires it up twice — once per server
— with `RESOURCE_LOCK tcp_port_8080`, because both servers bind the same hardcoded
port and must never run concurrently.

New behaviour needs a test unless there is a reason it can't have one; say so in
the PR when there is. Add cases by adding an `add_test` entry with the lines the
server should log.

## Branch strategy

- `main` — protected. No direct pushes; merges only through a PR, squash only.
- `feature/<name>` — branch off `main`, PR back to `main`.

```bash
./scripts/dev.sh branch partial-send   # creates feature/partial-send off main
./scripts/dev.sh pr                    # pushes and opens the PR
```

## CI/CD (GitHub Actions)

### `ci.yml` — every PR and every push to main
- `build (gcc)` / `build (clang)` — configure, build with `-Werror`, run CTest
- `tests (ASan + UBSan)` — same suite under sanitizers
- `clang-tidy` — lints every translation unit in `compile_commands.json`
- `shellcheck` — lints `scripts/*.sh` and `tests/*.sh`

### `claude-review.yml` — the merge gate
Claude reviews the PR diff against this file, returns a JSON verdict, and
`.github/scripts/enforce_review.py` turns that verdict into the pass/fail status
of the **Claude review** check. That check is required by the `main` ruleset, so
nothing merges until Claude approves. The gate **fails closed**: a missing or
malformed verdict blocks the merge.

### `claude.yml` — @claude mentions
Interactive only. Mention `@claude` in a PR or issue comment to ask a question or
request a change. It never gates a merge.

## Rules for Claude Code working in this repo

- **Never run `git commit` or `git push`.** Make the changes, explain them, and
  leave committing to the repository owner.
- **Never add `Co-Authored-By` trailers or any AI attribution** to a commit
  message, PR description, or comment. Not once, not ever.
- Don't run `scripts/setup_repo.sh` — it changes GitHub settings and is the
  owner's to run.
- Before proposing a change, run `./scripts/dev.sh ci` and report what it printed.
- When changing anything in `tests/`, run the suite; don't assume it still passes.
