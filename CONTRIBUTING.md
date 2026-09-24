# Contributing

This is a small repo run like a real one: `main` is protected, work happens on
branches, and nothing lands without review. The reviewer is Claude — the
**Claude review** check has to pass before GitHub will let a PR merge.

## The loop

```bash
./scripts/dev.sh branch partial-send   # feature/partial-send, branched off main
# ... edit, build, test ...
./scripts/dev.sh ci                    # what CI will run, run locally first
git add -p && git commit               # see the commit rules below
./scripts/dev.sh pr                    # push + open the PR against main
gh pr checks --watch                   # wait for CI and the review gate
```

## Branches

| Branch | Rule |
| --- | --- |
| `main` | Protected. No direct pushes, no force-pushes, no deletion, linear history. |
| `feature/<name>` | Branch off `main`, PR back to `main`. Deleted automatically on merge. |

Use `fix/<name>` for bug fixes and `chore/<name>` for tooling or docs if you
prefer — nothing enforces the prefix, but keep the name descriptive.

## Commits

- Imperative subject line, ≤ 72 characters: "handle partial sends in the client",
  not "handled partial sends" or "updates".
- Body explains *why* when the diff doesn't already say it. Wrap at 72.
- One logical change per commit. PRs are squash-merged, so the PR title becomes
  the commit on `main` — make it a good one.
- **No `Co-Authored-By` trailers and no AI attribution of any kind**, in commits
  or PR descriptions.

## Pull requests

- Fill in the template. "How it was verified" is the part reviewers actually read.
- Keep PRs small enough to review in one sitting. A 600-line PR gets a worse
  review than three 200-line ones.
- Draft PRs are skipped by the review gate; mark it ready when you want the review.
- CI must be green and Claude must approve. Then squash-merge.

## What the review gate blocks on

Claude reads `CLAUDE.md` and blocks the merge on real defects — an unchecked
syscall, a descriptor that leaks on an error path, an unbounded read, a `recv`
result that isn't handled in all three cases, byte-order confusion, a broken or
missing test, a committed secret. Style preferences and refactor opinions come
back as non-blocking notes, not as a block.

If it blocks and you disagree, reply in the PR thread explaining why — then push
the fix or re-run the job. The check re-runs on every push.

If the check fails with "Claude produced no verdict", the review step itself
failed; the usual cause is a missing `ANTHROPIC_API_KEY` secret. The gate fails
closed on purpose: no verdict is not an approval.

## First-time setup for the repo owner

```bash
gh secret set ANTHROPIC_API_KEY --repo Sushanta451/connection-logger
./scripts/setup_repo.sh --dry-run   # review what it will change
./scripts/setup_repo.sh             # apply the ruleset + merge settings
```

## Local tooling

Required: `cmake`, a C++20 compiler. Recommended: `ninja`, `clang-tidy`,
`clang-format`, `shellcheck`, `gh`.

```bash
brew install cmake ninja llvm clang-format shellcheck gh
```

`clang-tidy` ships inside Homebrew's `llvm`; add it to your `PATH`
(`export PATH="/opt/homebrew/opt/llvm/bin:$PATH"`) for `./scripts/dev.sh lint` to
find it.
