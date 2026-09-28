# ARM32 Dev Backend: History Cleanup, Verification and Catching Up

How the arm32 work (`projects/big/arm32-dev-backend.md`) is cleaned up,
verified commit by commit and unit by unit, run through CI, and then brought
up to date with upstream `main` (`roc-lang/roc`) before it is proposed there.
This file holds the plan and, as it runs, the results.

## Goal and rules

- **Goal:** every step of the arm32 plan is shown to be free of problems, with
  evidence, before the work goes upstream in reviewable pieces.
- **One history rewrite, then none.** The owner asked (2026-09-29) for one
  cleanup: squash the two identical "vibe plan" commits into one and remove the
  merge commit that joined them (part 1). After that, history is not rewritten
  again: a commit found broken stays as it is, the fix is a new commit, and
  this file records "red at X, fixed by Y".
- **Verify first, then catch up.** Catching up is a merge of upstream `main`
  into the branch tip; it does not change any existing commit, so results for
  existing commits stay valid after it, and anything that breaks after the
  merge is attributable to the merge.
- **CI runs only on GitHub-hosted runners**, on the owner's public fork
  (`origin`, `InvisOn/roc`), where they are free. No GitHub Actions runner is
  ever installed on the owner's machines; the Raspberry Pis are for manual,
  local runs over ssh only.
- **Nothing is pushed without the owner's go-ahead at that moment.** Pushing to
  the public fork makes the work public.
- Notes produced along the way follow the routing table at the top of
  `projects/big/arm32-dev-backend-issues.md`.

## Schedule

| When | Parts |
|---|---|
| Today, first | Part 1 (history cleanup), fully verified |
| Today | Part 2 at the tip (full local run), part 3 (push after go-ahead, tip CI, phase PRs), trial merges (part 4, step 1) |
| Overnight | Part 2's per-commit sweep (about a day of machine time) |
| Next | Part 2's acceptance checklist, fixes, then the real merge and its verification (parts 4 and 5) |

The per-commit sweep does not fit in a day; everything else can start today.

## Part 1: history cleanup (one-time rewrite)

### What changes

The history starts with two commits named "vibe plan" holding the same three
files (`projects/big/arm32-dev-backend.md`, `arm32-dev-backend.old.md`,
`arm64-backend-reference.md`), committed on two different upstream bases
(`904d57d0a4` on `1d982dca64`, `379469a2c4` on the merge base `58508d582b`),
and a merge commit (`5ce438e86f`) joining them. Checked: the merge's tree is
byte-identical to `379469a2c4`'s, and the 103 commits after it are linear.

The new history is:

1. One commit on `58508d582b` with `379469a2c4`'s tree and author, and a
   descriptive message ("Add the arm32 dev backend plan").
2. Every later commit replayed with **exactly its original tree**, author,
   author date, committer and committer date, on the new parent.

Because every replayed commit has the same tree as before, all file contents
at every commit are unchanged; only commit hashes change. Every result
obtained for an old commit holds for its replay.

### How

Plumbing, not `git rebase`, so nothing is re-applied or merged:
`git commit-tree <original tree> -p <new parent>` for each commit in order,
with the original author and committer identities and dates in the
environment. Commit messages that cite earlier commits by abbreviated hash are
rewritten through the old-to-new hash map as the replay goes (each message
only cites earlier commits, which already have new hashes).

### Steps

1. **Safety copies:** a local tag `backup/32-bit-backend-before-rewrite` at the
   current tip, and a `git bundle` of the branch in the scratch directory.
   Kept until part 3 is finished.
2. **Build** the new history on a new local branch, `32-bit-backend-clean`.
3. **Verify the rewrite** (all must hold):
   - for every replayed commit, its tree hash equals the original's;
   - the new tip's tree equals the old tip's (`git diff --quiet`);
   - `git range-diff` shows only the squash and hash changes in messages;
   - authors and dates are identical, commit by commit;
   - no commit message still cites a hash that was rewritten.
4. **Switch:** point `32-bit-backend` at the new history (the old one stays
   reachable through the backup tag).
5. **Update citations in the docs:** the notes cite about fifty commits by
   hash. One new commit at the tip rewrites every citation through the map,
   and this file gains the full old-to-new map (appendix), so hashes quoted in
   historical versions of the notes can still be resolved.
6. **Clean up:** remove the local `private-ci` branch and its worktree (no
   longer used), and update the memory notes (one-time rewrite done; no
   runners on the owner's machines).

### What it affects outside this machine

The public fork's `32-bit-backend` already holds the two "vibe plan" commits
and the merge. Publishing the cleaned history there is a force-push
(`git push --force-with-lease=32-bit-backend:5ce438e86f origin 32-bit-backend`,
which refuses if the remote moved). It needs the owner's go-ahead at the time.

## The history being verified

After part 1: 105 commits on `32-bit-backend` since the merge base with
upstream `main` (`58508d582b`, 2026-09-24), linear. The commit hashes in the
tables below are the pre-rewrite ones; step 5 of part 1 updates them.

The plan's units interleave in the history (A2's commits are mixed with A3,
Track C, the NEON batch, Track D and fixes; J3b landed before J2), so a unit
is verified at its own last commit, and CI runs on phases cut at natural
boundaries.

One invariant covers almost the whole history: the 64-bit eval hash file
(`test/dev_code_hashes/eval.blake3`) was committed in A0 and never changed
afterwards, and the `dev_object` snapshots changed only in J4 and only in
their `arm32*=` lines. From A0 on, every commit must reproduce the committed
64-bit output exactly.

### Units and their last commits

The acceptance criteria are quoted in the plan under each unit; the "How"
column says where each can be checked.

| Unit | Last commit | How |
|---|---|---|
| Track B (encoder, NEON batch) | `60be8c5855` (#36) | local: encoder tests, `ci/arm32_encoding_oracle.py --check`, test count ≥ `pub fn` count |
| A0 (byte-identity oracles) | `82e4e93092` (#6) | local x86_64; the aarch64 host and "every ci_zig host" parts need CI |
| A1 (dispatch, D10, CC seam, facade) | `013e9f13f6` (#13) | local: oracles, `run-test-zig`, eval, host effects, CLI, the three `rg` checks, the `@compileError` gate still present |
| A3 (ELF32 containers) | `301db39b9a` (#14) | local: oracles, the `elf.zig` tests and the aarch64 sibling test |
| Track C (arm32 target artifacts) | `75c55299d2` (#15); fix `2760f61aa1` (#53) | local: the six objects, `ci/elf32_reader.py` output, baseline pin test, non-zero cross case count |
| A2 (width model) | `0ba1d611fa` (#37) | local: as A1 |
| Track D (CI lanes) | `b3b397ad8a` (#38) | CI only (the jobs must appear and their steps run) |
| J1a–J1f (arm32 CodeGen) | `0364d47adb` (#40), `c7528522f4` (#43), `1c9bdcfa57` (#48), `2e4ce3f8a8` (#50), `7654e0f561` (#51), `2cf0c7ffd5` (#52) | local: no `arm => @compileError` left, the `LirCodeGen(.arm32musl)` test block, the hello-world link-and-run test under qemu |
| J3b (`--cross-run`) | `1202fbae9e` (#57) | local: fx and int cases pass under qemu with the x86_64 dev stdout |
| J2 (cross-compilation on) | `aa6c9c2485` (#67) | local Linux parts (int app, `elf32_reader.py` on object and executable, qemu stdout, arm32linux, the `--opt=speed` diagnostic, the SIMD lane, D10 in Debug builds); the macOS and Windows hosts need CI |
| J3a (dev backend on arm32 hosts) | `79f9ccf002` (#77) | local under qemu, plus the Raspberry Pi 5; the "Debug runner" clause cannot be met (see the issues note) |
| J3c (required cross-compile lanes) | `cd563f5c05` (#78) | CI only (all four hosts) |
| J3 hardware (call-shape battery, atomics) | `57bdd065a2` (#85) | Pi 3 and Pi 5, manually |
| J4 (lock-in) | `13547918d4` (#88) | local x86_64; "all six ci_zig hosts" needs CI |

### Phases (cut points for CI and for walkthroughs)

| Phase | Ends at | Contains |
|---|---|---|
| 1 | `013e9f13f6` (#13) | plan documents, Track B batch 1, A0, A1 |
| 2 | `75c55299d2` (#15) | A3, Track C |
| 3 | `013809c2b6` (#39) | A2, Track B NEON, Track D, fixes to existing code |
| 4 | `2cf0c7ffd5` (#52) | J1a–J1f |
| 5 | `aa6c9c2485` (#67) | J2, J3b |
| 6 | `79f9ccf002` (#77) | J3a |
| 7 | `352d062072` (#89) | J3c, J3 battery, J4 |
| 8 | the tip | post-plan fixes and notes |

Each phase becomes a branch pointing at its existing last commit
(`arm32/phase-1` ... `arm32/phase-8`); no new commits are made for them.

## Part 2: local verification

### Preparation

1. A separate git worktree for verification, so the working branch is never
   checked out at old commits (`git worktree add ../roc-verify`).
2. Its own Zig cache directory, deleted whole whenever it passes 50 GB, never
   partially (a partial delete breaks Zig's cache; see the issues note on
   `.zig-cache`).
3. `git config rerere.enabled true`, so conflict resolutions from the trial
   merges (part 4) are reused by the real merge.
4. The per-commit script, which lives outside the repository tree; its checks
   are listed here so the results can be reproduced.

### 2a. The tip, in full (today)

At the tip, before anything is pushed: `zig build minici` section by section;
the arm32 eval corpus, host effects and fx suite under qemu (`cortex-a9`, the
CPU floor); the same on the Raspberry Pi 5 and the fx suite and int app (musl
and glibc) on the Raspberry Pi 3, run by hand over ssh.

### 2b. Every commit (overnight)

For each commit, skipping commits that change only Markdown files, in the
verification worktree:

| Check | From | Command |
|---|---|---|
| Builds | first commit | `zig build roc` |
| Format, lint, tidy, git lints | first commit | `zig build run-check-zig-format run-check-zig-lints run-check-tidy run-check-git-lints` (each separately, where the step exists) |
| Backend unit tests | first commit | `zig build run-test-zig-module-backend`, judged by the test binary's totals (until the wasm-merge fix the step exits non-zero on a passing run because a wasm test wrote to stderr) |
| Encoding oracle | Track B batch 1 | `zig build run-check-arm32-encoding-oracle` (or `python3 ci/arm32_encoding_oracle.py --check`) |
| 64-bit byte identity | A0 | `zig build run-check-dev-code-hashes` and `zig build run-check-snapshots` with no diff in `test/snapshots` |

A step that does not exist yet at a commit is recorded as "n/a", not as a
pass. Each commit's result is one row: commit, each check's result, and for a
failure the first error line. Commits already known to be red on their own
(lint and tidy violations fixed later, for example) are expected; the point
is to find anything not already known. Estimated cost: about 85 commits at
10-15 minutes each.

### 2c. Every unit's acceptance criteria

At each unit's last commit, run the unit's acceptance criteria as written in
the plan, and record each criterion with its command, the output that shows
the result, and pass/fail. Criteria that need other hosts are marked "needs
CI" and settled in part 3. Criteria the work could not meet as written (for
example J3a's "Debug runner") are recorded with the reason and the evidence
used instead, not counted as passing.

### 2d. Fix what 2a-2c find

Each problem found is fixed in a new commit at the tip, one problem per
commit, and recorded twice: in the results below and in the issues note
(resolved, with the commit). Known problems:

- The J3a CI lane needs 18 GB to build the arm32 eval runners (issues note,
  1.2); hosted Linux runners on public repositories have 16 GB. First
  experiment: build the two runners one at a time (`-j1`), measuring peak
  memory with `--summary all`, and see whether the larger one fits in 16 GB
  plus the runner's swap; if not, find what takes the memory.
- The interpreter's hosted calls on arm32 hosts (issues note, 1.2, plan
  step 1).

## Part 3: CI on GitHub-hosted runners (public fork)

After the owner's go-ahead to push:

1. **Push** the cleaned `32-bit-backend` to `origin` (a force-push, part 1),
   and a branch `arm32/base` at the merge base `58508d582b`, so pull requests
   compare against exactly the base the work was written on and CI tests the
   commits themselves rather than a merge with a newer `main`.
2. **Tip, per-PR checks:** a pull request `32-bit-backend` → `arm32/base` in the
   fork runs upstream's per-PR checks: `zig build minici` on Linux x64
   (`ubuntu-24.04`), macOS arm64 (`macos-15`) and Windows x64
   (`windows-2025`), and the arm64 Linux hello world (`ubuntu-26.04-arm`).
3. **Tip, full suite:** `gh workflow run ci_zig.yml -R InvisOn/roc --ref
   32-bit-backend -f full-run=true` runs the nightly suite: the six-OS test
   matrix (macOS arm64 and x64, Linux x64 and arm64, Windows 2022 and 2025),
   the cross-compile workflow (arm32 int app built on Linux, macOS arm64,
   macOS x64 and Windows, and compared) and the arm32 qemu lane. The arm32 eval
   lane is expected to fail until the 18 GB problem is fixed.
4. **Phases:** push `arm32/phase-1` ... `arm32/phase-7` and open stacked pull
   requests (phase 1 → `arm32/base`, phase N → phase N-1), so each gets the
   per-PR checks on exactly its change; dispatch the full suite on a phase
   when its "needs CI" criteria require it. Hosted concurrency is limited
   (macOS especially), so the tip goes first and phases queue behind it.
5. **Read the results** with `gh` (`gh run list`, `gh run view --log-failed`)
   and record them below.

Note: the fork's `pull_request` workflows compare against the pull request's
base branch, so the base must be `arm32/base`, not the fork's `main`.

## Part 4: catch up with upstream

1. **Trial merges, starting today**, in a throwaway worktree: merge
   `upstream/main` into the tip without committing it to the branch, to see
   where conflicts are (expected in `LirCodeGen.zig`, the shared driver) and
   to record resolutions for `rerere`. Repeat as upstream moves.
2. **The real merge**, once part 2 and the tip's CI pass: one merge commit of
   the then current `upstream/main` into `32-bit-backend`. Conflicts are
   resolved by keeping upstream's behaviour and re-applying the arm32 change on
   top of it; every non-trivial resolution is described in the merge commit
   message.
3. Upstream changes that break arm32 at compile time (a new code path with no
   arm32 arm) are fixed in commits after the merge, one per issue.

## Part 5: verify the merge

The committed 64-bit golden hashes describe the old base; upstream's own
changes may legitimately change 64-bit output, so after the merge the check
becomes relative:

1. **Relative 64-bit oracle:** generate the eval hashes
   (`--write-dev-code-hashes`) and the `dev_object` snapshot lines for the
   merged tip and for the `upstream/main` commit that was merged, into scratch
   files, and require the x86_64 and aarch64 values to be identical. That is
   Track A's promise on the new base: the arm32 work changes nothing for the
   64-bit targets. Then commit the regenerated golden files in their own
   commit, citing this comparison.
2. Part 2a again at the merged tip.
3. Part 3 again: a pull request of the merged tip against the fork's `main`
   brought up to the merged upstream commit, and the full suite dispatched.

## Part 6: walkthroughs and upstream

After each phase passes, a walkthrough for the owner: what changed, which plan
decision it implements, what the checks prove. Then the conversation with the
maintainers, and upstream pull requests phase by phase, each brought up to
date with the `main` of that time by a merge and verified with the relative
oracle.

## Open decisions

- Whether J1's six sub-units each get their own CI run (finer phases).

## Results

### Findings so far

| Found | Red at | Fixed by | What |
|---|---|---|---|
| 2026-09-28, drafting a CI workflow | `ee65370868` (#70) | `da35674feb` | The instruction-cache file moved to `src/backend/dev/`, but `ci_manager.yml`'s arm64 hello-world job (run on every pull request) still tested the old path. The moved file passes `zig test -O ReleaseSafe` on the Raspberry Pi 5 (aarch64). |

### Part 1: history cleanup

Not run yet.

### Part 2: local verification

Not run yet.

### Part 3: CI

Not run yet.

### Part 4: trial merges

Not run yet.

### Part 5

Not run yet.
