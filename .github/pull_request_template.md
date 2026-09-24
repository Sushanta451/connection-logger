## What this changes

<!-- One or two sentences. What does the code do now that it didn't before? -->

## Why

<!-- The reason, not the restatement. What was broken, missing, or unclear? -->

## How it was verified

<!-- Delete what doesn't apply. -->
- [ ] `./scripts/dev.sh ci` passes locally
- [ ] `./scripts/dev.sh test` covers the new behaviour (or: why it can't be tested yet)
- [ ] Ran the server and client by hand and watched the log

## Socket checklist

<!-- Delete this section if the PR touches no socket code. -->
- [ ] Every syscall return value is checked
- [ ] Every file descriptor is closed on every path, including error paths
- [ ] `recv` handles all three cases: `-1` (error, incl. `EINTR`), `0` (peer hung up), `>0`
- [ ] Buffers are bounded by `sizeof(buf)` and never treated as NUL-terminated strings
- [ ] Byte order is converted at the boundary (`htons`/`ntohs`/`htonl`/`ntohl`)

---
Merging is blocked until the **Claude review** check passes. See CONTRIBUTING.md.
