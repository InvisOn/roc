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

105 commits on `32-bit-backend` since the merge base with upstream `main`
(`58508d582b`, 2026-09-24), linear (after part 1). Hashes and `#N` numbers in
this section and below are the new ones; the appendix maps old hashes to
new.

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
| Track B (encoder, NEON batch) | `4d3de2e56e` (#34) | local: encoder tests, `ci/arm32_encoding_oracle.py --check`, test count ≥ `pub fn` count |
| A0 (byte-identity oracles) | `5ee8a07527` (#4) | local x86_64; the aarch64 host and "every ci_zig host" parts need CI |
| A1 (dispatch, D10, CC seam, facade) | `81fd7f7774` (#11) | local: oracles, `run-test-zig`, eval, host effects, CLI, the three `rg` checks, the `@compileError` gate still present |
| A3 (ELF32 containers) | `277feeecfd` (#12) | local: oracles, the `elf.zig` tests and the aarch64 sibling test |
| Track C (arm32 target artifacts) | `db8d0e81d5` (#13); fix `77c761ec12` (#51) | local: the six objects, `ci/elf32_reader.py` output, baseline pin test, non-zero cross case count |
| A2 (width model) | `37cc054a58` (#35) | local: as A1 |
| Track D (CI lanes) | `727d84088f` (#36) | CI only (the jobs must appear and their steps run) |
| J1a–J1f (arm32 CodeGen) | `506b0486f2` (#38), `ecf471509f` (#41), `b392284263` (#46), `f017e3b2a5` (#48), `a31e7a2a91` (#49), `a50e40a165` (#50) | local: no `arm => @compileError` left, the `LirCodeGen(.arm32musl)` test block, the hello-world link-and-run test under qemu |
| J3b (`--cross-run`) | `a02d04458f` (#55) | local: fx and int cases pass under qemu with the x86_64 dev stdout |
| J2 (cross-compilation on) | `2ec8ae751e` (#65) | local Linux parts (int app, `elf32_reader.py` on object and executable, qemu stdout, arm32linux, the `--opt=speed` diagnostic, the SIMD lane, D10 in Debug builds); the macOS and Windows hosts need CI |
| J3a (dev backend on arm32 hosts) | `5887997c63` (#75) | local under qemu, plus the Raspberry Pi 5; the "Debug runner" clause cannot be met (see the issues note) |
| J3c (required cross-compile lanes) | `fc02e3fb45` (#76) | CI only (all four hosts) |
| J3 hardware (call-shape battery, atomics) | `fd1cec553e` (#83) | Pi 3 and Pi 5, manually |
| J4 (lock-in) | `0c66ab5b94` (#86) | local x86_64; "all six ci_zig hosts" needs CI |

### Phases (cut points for CI and for walkthroughs)

| Phase | Ends at | Contains |
|---|---|---|
| 1 | `81fd7f7774` (#11) | plan documents, Track B batch 1, A0, A1 |
| 2 | `db8d0e81d5` (#13) | A3, Track C |
| 3 | `f2fb602f74` (#37) | A2, Track B NEON, Track D, fixes to existing code |
| 4 | `a50e40a165` (#50) | J1a–J1f |
| 5 | `2ec8ae751e` (#65) | J2, J3b |
| 6 | `5887997c63` (#75) | J3a |
| 7 | `43ed156943` (#87) | J3c, J3 battery, J4 |
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

Checklist for the upstream pull requests:

- **In the final pull request, note the prebuilt binaries** (owner's
  request, 2026-09-29): the arm32 work adds five committed runtime binaries
  (`crt1.o`/`libc.a` for `arm32musl` in the fx and int platforms, `Scrt1.o`
  for `arm32linux`) only to follow Roc's current practice; say that the owner
  considers committed binaries a security risk (the xz-utils backdoor hid its
  payload in binary test files) and intends to propose generating them at
  build time for every target. Details: the issues note, "Stop committing
  prebuilt binaries".
- **Point out the Zig ABI workaround in the test host** (owner's request,
  2026-09-29): `test/fx/platform/host.zig` works around a Zig 0.16 bug (a
  by-value nested `extern struct` passed off-ABI on arm) so the fx host
  receives `Host.get_greeting!`'s argument correctly. AGENTS.md forbids
  workarounds, so say plainly that this one is confined to a test host, is
  guarded by two tripwires (a probe test in CI that fails once Zig is fixed,
  and a Zig version check), and name the alternatives (change the test
  platform's API, or skip those fx programs on arm32 until Zig is fixed).
  Report the bug to Zig first and link the report. Details: the issues note,
  "Zig 0.16 passes nested `extern struct` arguments off-ABI on arm".

## Open decisions

- Whether J1's six sub-units each get their own CI run (finer phases).

## Results

### Findings so far

| Found | Red at | Fixed by | What |
|---|---|---|---|
| 2026-09-28, drafting a CI workflow | `49bf1449b9` (#68) | `6eeba018af` | The instruction-cache file moved to `src/backend/dev/`, but `ci_manager.yml`'s arm64 hello-world job (run on every pull request) still tested the old path. The moved file passes `zig test -O ReleaseSafe` on the Raspberry Pi 5 (aarch64). |
| 2026-09-29, CI (pull request #1, Spellcheck) | the notes, from part 1 on | the commit that adds this row | `typos` flags seven words in the arm32 notes. `zig build minici` does not run the spellcheck, so the local run passed; `typos` is now run locally too. |
| 2026-09-29, CI (pull request #1, `zig-minici` macOS and Windows) | `a50e40a165` (#50, J1f) | the commit that adds this row | The J1f test "arm32: a proc compiles through LirCodeGen(.arm32musl)" compiled arm32 code in native-execution mode, which embeds this host's builtin addresses; `CallBuilder.call` narrowed them to 32 bits with `@intCast`, which panics where the test binary is loaded above 4 GiB (macOS, Windows) and passed on Linux only because the image is loaded low. The test now compiles in object-file mode, as cross-compilation does, and the arm32 absolute call reports the broken invariant (native arm32 code needs an arm32 host) instead of a bare cast. Backend tests pass on x86_64 (898/900) and for arm32 under qemu (895/900). |
| 2026-09-30, CI (full suite, `zig-tests` Windows 2022 and 2025) | `6205c06435` (#88) | the commit that adds this row | The test "resolveCrossRunner keeps commands and absolute paths and anchors relative paths" expected `/` between the project root and a relative runner path, but `std.fs.path.join` uses the host separator, giving `/repo\ci/ssh_cross_runner.sh` on Windows. The code was right; the expected strings now use `std.fs.path.sep_str`. |
| 2026-09-30, minici on the upstream merge (`run-test-zig-module-lir_core`) | `41eb92cfaa` (the merge) | the commit that adds this row | Upstream shortened the procedure-symbol prefix from `roc__proc_` to `roc__p`. `canonicalizeSymbolNames` reads the constant and kept working (the relative oracle passed); only A0's unit test spelled the old prefix, so nothing in its input was renamed. The test now builds its names from `ProcIdentity.symbol_name_prefix`. |
| 2026-09-30, minici on the upstream merge (`run-test-cli`, "default platform builds for arm32musl with the dev backend") | `41eb92cfaa` (the merge) | the commit that adds this row | Upstream `f4a81572cd` declares all-zero static data as zero-fill: `.bss` on ELF, COFF and Mach-O, written by `write64`. A3's `write32` (arm32's ELF32) had no `.bss` and gave `.bss` symbols section index 0, so they were undefined and LLD failed (`undefined hidden symbol: roc__d1`). `write32` now declares `.bss` (SHT_NOBITS, section 14, after `.ARM.attributes`) and points those symbols at it; a new test pins it. The program links and prints the same line under qemu as on x64musl. Only the 32 `arm32*` lines of the `dev_object` snapshots change. |
| 2026-10-01, arm32 eval corpus under qemu on the upstream merge | `41eb92cfaa` (the merge; upstream #11705 added the prefix parsers) | the commit that adds this row | Upstream's new `generateNumFromStrPrefix` passed a string's or list's length and capacity at offsets 8 and 16, which assume 8-byte words; on arm32 the builtin read the wrong words (every number `NotANumber`, `rest` padded with spaces, some children died). 36 `from_str_prefix`/`from_utf8_prefix` cases failed. The offsets now come from `strFieldOffset`/`listFieldOffset` (A2's width-generic helpers), the same values on 64-bit targets. All 42 prefix, Json-number and issue-11471 cases pass under qemu. The same run crashed once in "issue 11471: primitive alias list elements retain their parser" ("compilation/lowering did not complete"); it passes on rerun (open: watch for recurrence). |
| 2026-09-30 and 2026-10-01, CI `zig-tests` ReleaseFast pass (macOS-15, Windows 2025) and local ReleaseFast run | `5ee8a07527` (#4, A0) | the commit that adds this row | A0's `dev_object_str_ops` and `dev_object_recursion_rc` hashed a Debug compiler's output, which includes Debug-only validity checks for Str and Box locals; a ReleaseFast compiler emits none, so `snapshot validation` failed in every ReleaseFast pass. Both snapshots are removed; the gating is upstream's code and stays. |
| 2026-09-29, sweep | `506b0486f2` (#38, J1a) | `ac6b9ca982` (#39, J1b) | `zig build run-check-tidy`: the test helper `expectCode` in `arm32/CodeGen.zig` returned an inferred error set (`!void`); J1b made it `error{TestExpectedEqual}!void`. |

### Part 1: history cleanup

Done 2026-09-29, locally (nothing pushed).

- Safety copies: tag `backup/32-bit-backend-before-rewrite` at the old tip
  `8ff3b64374`, and a verified `git bundle` of it in the scratch directory.
- New history: `8e7c114321` ("Add the arm32 dev backend plan") on
  `58508d582b`, with `379469a2c4`'s tree, then 104 commits replayed by
  `git commit-tree -S` (every original commit was signed with the owner's SSH
  key, so every replayed one is too). New tip before this update:
  `aadf66a29b`.
- Checks, all passed: every replayed commit has its original tree, author,
  committer and dates; the history is linear from the merge base with 105
  commits and no merges; every commit is signed; no commit message cites a
  rewritten commit by its old hash (two messages had citations rewritten);
  the old and new tips have identical trees; `git range-diff` shows only the
  squash, the two rewritten citations, and one repaired message.
- The message of `8ff3b64374` had lost its end to a shell quoting mistake;
  its replay (`aadf66a29b`) carries the intended message.
- Citations in the notes updated in the commit that adds this section.

### Part 2: local verification

- 2a at `e76f346470` (the tip after part 1), 2026-09-29, all passing:
  - `zig build minici`: 79 of 79 phases, in 59 minutes.
  - arm32 eval corpus (ReleaseFast runners built at the tip): 2171/2171
    under qemu (`cortex-a9`, the CPU floor) and 2171/2171 on the Raspberry
    Pi 5, the dev backend running 2030 evaluations in each, as on x86_64.
  - arm32 host effects: 86/86 under qemu and on the Pi 5.
  - fx suite through `ci/ssh_cross_runner.sh`: 122/122 on the Pi 3 (32-bit
    kernel) and 122/122 on the Pi 5.
  - int app on the Pi 3: `arm32musl` and `arm32linux` (glibc) both print
    exactly what the x64musl build prints (54 lines, heap addresses masked)
    and exit 0.
- 2b, the per-commit sweep, 2026-09-29, finished: all 114 commits up to
  `fe779eee30` (82 with code; the rest change only Markdown), on the desktop,
  with #82-#85, #92, #104 and #109 run on the Ubuntu laptop. Every build,
  format, lint, backend-test, encoding-oracle and 64-bit byte-identity check
  passed on every code commit, except three failures, each fixed by a later
  commit:

  | Check | Red at | Fixed at | Cause |
  |---|---|---|---|
  | git-lints | #21-#76 | #77 | `arm32_link_smoke.zig` was not imported anywhere |
  | tidy | #38 (J1a) | #39 (J1b) | a test helper with an inferred error set |
  | tidy | #77 | #78 | `std.mem.indexOf` (banned; `std.mem.find`) in the link smoke test |

  So from A0 (#4) on, every commit reproduces the committed x86_64 and
  aarch64 output exactly: Track A's promise holds at every step. The raw
  results table is kept in `.git/verify-tools/sweep-results.tsv`.
- 2c, the criteria that are searches over source files, checked at each
  unit's last commit with `git grep` / `git show` (no build), 2026-09-29:

  | Unit | Criterion | Result |
  |---|---|---|
  | A0 | golden hash file, compare step, `dev_object` snapshots exist | PASS (16 snapshots) |
  | A1 | `rg 'arch == \.\|arch != \.\|toCpuArch...'` empty outside host-side test guards (amended) | PASS: all 41 matches are `builtin.cpu.arch` test guards |
  | A1 | the arm32 `@compileError` gates still in place | PASS |
  | A1 | no register literal in `LirCodeGen.zig` | **not met**: 136 matches (see the issues note, "The driver still names mnemonics and register literals") |
  | A3 | `elf.zig` tests assert EM_ARM, `0x05000400`, `SHT_REL` and the four ARM relocation types; aarch64 sibling test | PASS |
  | Track B | every `pub fn` in `arm32/Emit.zig` has a byte-exact test | PASS in substance: 158 of 163 are called by a test (the tests live in the generated `encoding_oracle_tests.zig`, not in `Emit.zig` as the criterion words it); the other five are `Emit` itself and four helpers (`fitsImmediate`, used by 11 test lines; `bits`, `encodeMovwMovt`, `codeOffset`) exercised through the emitters |
  | Track C | a unit test pins Zig's arm baseline (D2) | PASS (`src/target/mod.zig`, "arm32 targets' architecture baseline is the dev backend's CPU floor") |
  | J1 | `rg 'arm => @compileError' src/backend/dev src/layout/abi` empty | PASS |
  | J1 | the `LirCodeGen(.arm32musl)` test block asserts types, registers and sizes | PASS |
  | J1 | `rg 'codegen\.emit\.' src/backend/dev/LirCodeGen.zig` empty (moved here from A1) | **not met**: 611 matches (issues note, same entry) |
  | J4 | no `arm32*=NOT_IMPLEMENTED` snapshot line; the lock-in changed only `arm32*=` lines | PASS (64 changed lines, all `arm32*=`) |

  The criteria that need builds, qemu or CI:
  - A1 at `81fd7f7774`, 2026-09-30: `run-test-zig` (6,536 tests),
    `run-test-eval` (2171/2171), `run-test-eval-host-effects` (86/86) and
    `run-test-cli` (no failures) all pass.
  - Track C at `db8d0e81d5`, 2026-09-30: `zig build` and the six
    `arm32musl` objects (ELF32, ARM, `0x5000400`, `Tag_ABI_VFP_args: 1`)
    pass. The non-zero cross-target case count cannot pass at this commit:
    the plan's own amendment moved the `arm32musl` roster rows out of Track
    C, so the runner rejects `--cross-target=arm32musl` as unknown (which is
    the runner-hygiene behaviour C added). The count is met at J2 (121 fx
    cases and 1 int case, below).
  - J2 at `2ec8ae751e`, 2026-09-30: all 10 criteria pass, including the
    kept object (ELF32, ARM, `0x5000400`, VFP args, `Tag_CPU_arch: 10`),
    the int app under qemu cortex-a9 and as arm32linux (glibc) on the
    Raspberry Pi 3 with the x64musl stdout, the `--opt=speed` diagnostic,
    the arm32 SIMD lane, and Debug `roc` building all 121 fx and 1 int
    programs for arm32 without tripping D10. The first run's two failures
    were bugs in the acceptance script (it built only `roc`, not the glibc
    stubs of the install step, and missed the kept object's path); fixed
    and rerun.
  - J3a at `5887997c63`, 2026-09-30: all 6 pass. The ReleaseFast arm32 eval
    runners build; under qemu cortex-a9 the eval corpus passes 2171/2171
    and host effects 86/86; the x86_64 runner passes the same 2171; the
    arm32 backend tests pass under qemu (894/899, 5 skipped).

### Part 3: CI

- Pushed 2026-09-29 to the public fork: `32-bit-backend` → `e76f346470`
  (force-push over `5ce438e86f`, with lease) and `arm32/base` → `58508d582b`.
- Pull request InvisOn/roc#1 (`32-bit-backend` → `arm32/base`): no
  pull-request workflows were triggered, even after closing and reopening it,
  while a manual dispatch runs. Likely GitHub's safeguard for forks, which
  keeps event-triggered workflows off until the owner confirms once in the
  fork's Actions tab; waiting on the owner.
- Full suite dispatched on `e76f346470`: `ci_zig.yml` with `full-run=true`,
  run 36494296904, ended cancelled. Every failed job, attributed:
  - `zig-tests` on macOS arm64 and Windows 2022/2025, `nix-build (macos-15)`,
    and the pull request's `zig-minici` macOS-core and Windows-core shards:
    all the same arm32 test, native call addresses above 4 GiB; fixed (see
    the findings table).
  - `zig-cross-compile (arm-linux-musleabihf)`: the runner starved building
    the arm32 eval runners (the 18 GB issue).
  - `zig-tests (macos-15-intel)`: RustGlue plugins fail to load
    (`UndefinedSymbol`) and some `--opt=speed` tests fail. Upstream's own
    nightly fails or is cancelled on this job in every run since at least
    2026-09-18, with the same glue errors before this branch's base, so it is
    not from the arm32 work.
  - Jobs killed by the runner (exit 143) on x86-linux-musl, x86_64-macos,
    aarch64-linux and the Ubuntu test job: upstream's nightly loses the same
    jobs.
  - All 12 `roc-cross-compile` jobs passed, including the arm32 app built on
    Linux, Windows, macOS arm64 and macOS x86_64.
- Spellcheck on the pull request: seven words in the notes; fixed.
- ReleaseSmall probe, run 36675742296 (branch `arm32/releasesmall-probe`,
  one throwaway workflow running `ci_zig.yml`'s arm32 eval-runner steps
  without the LLVM build that gets the runner killed): passed on a 16 GB,
  4-core hosted runner. Build peak 7.7 GB, 10 minutes; eval 2171/2171 and
  host effects 86/86 under qemu cortex-a9. The 18 GB issue is resolved.
- Full run 36615593810 on `56029eddf9`: `zig-tests` on Windows 2022 and
  2025 failed one test of the branch's (see the findings table, fixed).
  `zig-tests (macos-15)` failed 11 tests, all in its ReleaseFast `-Dfuzz`
  `run-test-zig` pass (the Debug pass had no failures). Local attribution,
  2026-09-30, the same command on Linux under a 16 GB cap at `-j4`, at the
  tip `5d8523a894` and at the base `58508d582b`: both runs reach the same
  three failures and no others (the LIR proc-pass no-op worker test and two
  staged SpecConstr tests, one expecting `error.OutOfMemory`), so those
  three come from upstream. Both runs were then stopped by the cap
  (`oom-kill`) before finishing. A third run, filtered to the other eight
  (tip at `-j2` under 24 GB; base at `-j1` under 16 GB), settled them:
  - Upstream (fail at the base too): the two interface-summary tests,
    "LIR pass workers deterministically prove runtime range guards", and
    `lir_inline_test` "interface summaries relocate across bodies and
    executor lanes".
  - macOS only (pass on Linux at the tip): the three fx stack-overflow
    tests.
  - Open: "snapshot validation" fails at the tip because a ReleaseFast
    snapshot tool produces different x86_64, aarch64 and arm32 bytes than
    the Debug build that wrote the hashes, for `dev_object_str_ops` and
    `dev_object_recursion_rc` only. Both snapshots were added by A0, so the
    base has no such test and its pass says nothing. The output depending on
    the compiler's optimize mode means some code-generation input is not
    deterministic (for example uninitialized memory, which Debug fills with a
    fixed pattern). Next: run the Debug and ReleaseFast snapshot tools at the
    base on these two files; the same difference there puts the cause
    upstream, otherwise bisect the branch.
    **Cause found 2026-10-01** (CI run 36764332316 on the merge: the same
    two snapshots, the same targets, on macOS-15 and Windows 2025, so not
    uninitialized memory): the driver emits runtime validity checks for Box
    and Str locals only when the compiler itself is built in Debug
    (`emitDebugAssertValidBoxLocal` and `emitDebugAssertValidStrLocal`,
    gated on `comptime builtin.mode != .Debug`, upstream code). These two
    snapshots are the only ones with Str or Box locals, so their expected
    hashes describe a Debug compiler's output and a ReleaseFast compiler's
    differs. A0 added a test whose expectation depends on the compiler's
    optimize mode; CI's ReleaseFast `run-test-zig` pass checks it. The eval
    hash file has the same dependence but is only checked by a Debug runner.
    Resolved by removing the two snapshots (the gating is upstream's code;
    the eval hashes cover strings and boxes); see the findings table and
    DESIGN.md, "Snapshot hashes must not depend on the compiler's optimize
    mode".
- Pull-request run 36534635511 on `fe779eee30`: every `zig-minici` shard
  passed except `windows-harness`, cancelled at its 2-hour limit.
  `run-check-dev-code-hashes` alone took 46 minutes there. The hash file is
  host-independent, so minici now runs that check on Linux only and reports
  it skipped elsewhere; `ubuntu-full` still checks it on every pull request.

### Part 4: trial merges

- 2026-09-29, `upstream/main` at `9093111a90` (2026-09-28), 465 commits past
  the base: 17 files conflict. `src/backend/dev/LirCodeGen.zig` 8 hunks (269
  lines); `ObjectFileCompiler.zig` 2 hunks, `object/elf.zig`,
  `backend/wasm/WasmCodeGen.zig`, `base/LargeBlockAllocator.zig` 1 each;
  `.github/workflows/ci_zig.yml` (103 lines) and `ci_manager.yml` (57 lines);
  and the hash block of 10 `dev_object` snapshots, which part 5 regenerates
  rather than merges by hand. `rerere` is enabled.

### Part 5

- 2026-09-30, the real merge: `upstream/main` at `00cab95af8` (517 commits
  past the base, 43 past the trial) merged into `32-bit-backend` as
  `41eb92cfaa`. rerere replayed the trial's resolutions for 17 files; one
  new conflict (`src/cli/test/parallel_cli_runner.zig`, two independent CLI
  cases added at the same place) keeps both. The 16 `dev_object` snapshots
  (only their hash lines changed) and `test/dev_code_hashes/eval.blake3`
  (2,133 cases, 172 new from upstream) are regenerated.
- Relative 64-bit oracle on the merge: PASS. Eval dev-code hashes: 2,133
  cases, none differ, none on one side only; the committed hash file is
  byte-identical to the oracle's merged side. `dev_object` snapshots: 16
  files, no 64-bit line differs.
- Local checks on the merge, 2026-09-30 to 2026-10-01. Three fixes were
  needed on top of the merge (findings table): `65458f0f9b` (two new upstream
  tests adapted to the branch's interfaces), `b70e57798c` (A0's test spells
  the new symbol prefix from its constant) and `b3199c8912` (arm32's ELF32
  declares `.bss`), then `99a837b08b` (the prefix parsers' field offsets).
  - minici at `b3199c8912`: 79/79 phases pass.
  - arm32 at `b3199c8912`: host effects under qemu 104/104; all 122 `test/fx`
    programs cross-built with the dev backend pass under qemu and on the
    Raspberry Pi 5; the int app as arm32linux (glibc) on the Pi 3 prints
    x64musl's 54 lines.
  - At `99a837b08b`: the arm32 eval corpus under qemu 2381/2381 (the issue
    11471 crash did not recur); `run-check-dev-code-hashes` 2,133/2,133;
    format, zig lints, tidy and git lints pass.
- CI on the merge (`ac3e333001`, full run 36764332316):
  `roc-cross-compile (ubuntu-24.04, x64musl)` fails because two fx programs
  (`parallel_fusion.roc`, `inspect_dict_set.roc`) panic when cross-built for
  x64musl with the default (LLVM) backend: `std.debug.assert(size > 0)` in
  `classifySystemV` (`src/layout/abi/x86_64.zig:124`), reached for a
  zero-sized member of an aggregate. Upstream: the same command fails the
  same way at `00cab95af8` (`.git/verify-tools/x64musl_cross_attr.sh`).
  The same two programs fail the x64musl lanes on macOS-15 and Windows 2022,
  and `eval-llvm (ubuntu-24.04)` fails 30 of 2,381 cases (Set, Iter and
  inspect cases), every one an LLVM-backend abort (`signal: 6`) at the same
  assertion. Attributed to the same upstream defect by that assertion; the
  LLVM eval corpus was not separately rerun at upstream. Upstream issue
  #11909; the fix (PR #11915) is folded into the open PR #11885, so these
  jobs pass after the next catch-up that includes it.
- `eval-llvm (macos-15)`'s two aborts ("inspect: inclusive/exclusive numeric
  ranges all iterate", LLVM backend only): on the Raspberry Pi 5 (aarch64
  Linux), a Debug eval runner cross-built from the merged tip and one from
  upstream `00cab95af8` both abort the inclusive case the same way (the
  exclusive one passes there); `.git/verify-tools/pi5_llvm_ranges.sh`. The
  stack: Zig's libc `calloc` panics "incorrect alignment" inside LLVM's
  object emission (`emitMergedBitcodeModulesToObjectFile`). Upstream; the
  case came with `641d298ae1` ("Integrate stored ranges with iteration").
  Not reported upstream as of 2026-10-01.
- 2026-09-30, relative 64-bit oracle on the part 4 trial merge
  (`01abeb1b0c`, upstream `b2b9541c42`), `relative_oracle.py`: PASS. Eval
  dev-code hashes: 2,126 cases, none differ, none on one side only.
  `dev_object` snapshots: 16 files, no 64-bit line differs. This is a trial;
  the real merge reruns it.

## Appendix: old to new commit hashes

Every commit before part 1's rewrite and its replacement. `379469a2c4`,
`904d57d0a4` and `5ce438e86f` (the two "vibe plan" commits and the merge)
all map to the one commit that replaced them.

| Old | New |
|---|---|
| `379469a2c4` | `8e7c114321` |
| `904d57d0a4` | `8e7c114321` |
| `5ce438e86f` | `8e7c114321` |
| `12be3758d5` | `e8e659062c` |
| `8ffd541b71` | `73b96e7924` |
| `82e4e93092` | `5ee8a07527` |
| `cd0d9d49b1` | `0950270e57` |
| `f0c884f2f9` | `6e8a676578` |
| `42b80a5c56` | `85656e1351` |
| `939c17678e` | `0be4fbe2fd` |
| `f23924444c` | `33be6e0cec` |
| `37872af5d3` | `18faf2eabe` |
| `013e9f13f6` | `81fd7f7774` |
| `301db39b9a` | `277feeecfd` |
| `75c55299d2` | `db8d0e81d5` |
| `06e0da2b8b` | `4f0b09e679` |
| `1decf55b3f` | `d94be6fc25` |
| `9896319673` | `5fb339fda7` |
| `654087283b` | `f4af9e372d` |
| `dcb012efe4` | `d626657d87` |
| `c5248f3763` | `470bb6ee0a` |
| `ab6e860e2d` | `d69fb5eb7f` |
| `9081711a60` | `637fa493d3` |
| `45a961d272` | `3a4703ceed` |
| `4843fe861d` | `b562917556` |
| `fbf9701f87` | `ab4042a3fb` |
| `f2bd5fb262` | `6ea49faf81` |
| `8efb4a3369` | `a7c1ed4d54` |
| `233cfe5d55` | `760c5513f8` |
| `cdbaa9af47` | `c5a9cd49cc` |
| `a14bc455db` | `c1afe28d34` |
| `36d5866bdf` | `835187afb3` |
| `e20928099d` | `47046b4c8f` |
| `731b0e28b2` | `b5b44ccdab` |
| `faf770e14f` | `7499e08728` |
| `60be8c5855` | `4d3de2e56e` |
| `0ba1d611fa` | `37cc054a58` |
| `b3b397ad8a` | `727d84088f` |
| `013809c2b6` | `f2fb602f74` |
| `0364d47adb` | `506b0486f2` |
| `741361cf05` | `ac6b9ca982` |
| `bdaeb12155` | `4e5a27516c` |
| `c7528522f4` | `ecf471509f` |
| `57d2dbfecf` | `ee8b2f33a6` |
| `2beb9762d1` | `88a75e3048` |
| `d57f64c811` | `c64dbef7df` |
| `676661b517` | `955f916d65` |
| `1c9bdcfa57` | `b392284263` |
| `8dee9650ca` | `bddcb8bc7b` |
| `2e4ce3f8a8` | `f017e3b2a5` |
| `7654e0f561` | `a31e7a2a91` |
| `2cf0c7ffd5` | `a50e40a165` |
| `2760f61aa1` | `77c761ec12` |
| `4067bc0872` | `d910f7aa39` |
| `170dcf805f` | `2eb455507d` |
| `5e16a9068f` | `06fcdaba4e` |
| `1202fbae9e` | `a02d04458f` |
| `8a1ec2e76d` | `208ddcc06c` |
| `22e7bb2c2a` | `adf22c944a` |
| `bcdf943494` | `026674bcc7` |
| `b2ec048675` | `16d1ab893c` |
| `508f00b2d8` | `607e5c1f38` |
| `8b021b74eb` | `2e7c169071` |
| `1de80a8369` | `c36fd3b6ea` |
| `216f174987` | `279a81e227` |
| `f22b630738` | `c7e0484875` |
| `aa6c9c2485` | `2ec8ae751e` |
| `86c2f646fc` | `e610fb5353` |
| `e9e1a8da3b` | `18000a923c` |
| `ee65370868` | `49bf1449b9` |
| `c8b2e8f839` | `e865de0a8a` |
| `f485e9c6c5` | `c68e88c823` |
| `096eac947c` | `ad15c01f82` |
| `bf3e33730a` | `0bea1440e5` |
| `eb28c6efb7` | `1344ce3159` |
| `4a49f4b51f` | `894650cd4e` |
| `79f9ccf002` | `5887997c63` |
| `cd563f5c05` | `fc02e3fb45` |
| `86153ba924` | `74a5dfc19c` |
| `bf3d0ac8d7` | `f9cbc7c3d9` |
| `a3ad1aec6c` | `7dd3165833` |
| `4a7ffefca9` | `7d3bca5f6e` |
| `eb5c911820` | `6f12baef44` |
| `80c74cc9d5` | `f3c70c60c0` |
| `57bdd065a2` | `fd1cec553e` |
| `8ce226369e` | `24eac62a86` |
| `c17b138009` | `fdaa863dbf` |
| `13547918d4` | `0c66ab5b94` |
| `352d062072` | `43ed156943` |
| `a266aab5ed` | `6205c06435` |
| `b8b1c72b5b` | `2def52effc` |
| `ba0dd55634` | `677588b79e` |
| `5fbaf9fa0d` | `b2067838b2` |
| `3bb3ca2b44` | `1138ce4c33` |
| `f112435139` | `1dca9f9caf` |
| `8ab1649828` | `b0ed747445` |
| `a675c266fb` | `2a796cdc4e` |
| `58c18f99d7` | `f993075b25` |
| `a10627df8c` | `5b75e32d18` |
| `c170dc2dca` | `ab9d92bf7d` |
| `8edfb8859d` | `53953527cb` |
| `6ba6f28726` | `e3457476ca` |
| `31ff7f781e` | `e60908c7e6` |
| `3536f697ca` | `85e383503c` |
| `c2095b72ca` | `73c1c2dcce` |
| `da35674feb` | `6eeba018af` |
| `8ff3b64374` | `aadf66a29b` |
