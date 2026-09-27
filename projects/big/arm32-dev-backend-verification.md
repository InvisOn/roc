# ARM32 Dev Backend: Verification and Catching Up With Upstream

How the arm32 work (`projects/big/arm32-dev-backend.md`) is verified, commit by
commit and unit by unit, before it is brought up to date with upstream `main`
(`roc-lang/roc`) and proposed there. This file holds the plan and, as it runs,
the results.

## Goal and constraints

- **Goal:** every step of the arm32 plan is shown to be free of problems, with
  evidence, before the work goes upstream in reviewable pieces.
- **History is never rewritten.** No rebase, squash, amend or force-push. A
  commit found broken stays as it is; the fix is a new commit, and this file
  records "red at X, fixed by Y".
- **Nothing is pushed** to any remote until the owner says so. When pushing
  starts, it goes to the private repository (`private`,
  `InvisOn/roc_32bit`), never to the public fork first.
- **Verify first, then catch up.** Catching up is a merge of upstream `main`
  into the branch tip; it does not change any existing commit, so results for
  existing commits stay valid after it. Verifying first gives a known-good
  baseline, so anything that breaks after the merge is attributable to the
  merge.
- Notes produced along the way follow the routing table at the top of
  `projects/big/arm32-dev-backend-issues.md`.

## The history being verified

104 commits on `32-bit-backend` since the merge base with upstream `main`
(`58508d582b`, 2026-09-24), linear apart from one early merge (#3). The plan's
units interleave in the history (A2's commits are mixed with A3, Track C, the
NEON batch, Track D and fixes; J3b landed before J2), so a unit is verified at
its own last commit, and CI runs on phases cut at natural boundaries.

One invariant covers almost the whole history: the 64-bit eval hash file
(`test/dev_code_hashes/eval.blake3`) was committed in A0 (#6) and never
changed afterwards, and the `dev_object` snapshots changed only in J4 and only
in their `arm32*=` lines. From #6 on, every commit must reproduce the
committed 64-bit output exactly.

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
| J2 (cross-compilation on) | `aa6c9c2485` (#67) | local Linux parts (int app, `elf32_reader.py` on object and executable, qemu stdout, arm32linux, the `--opt=speed` diagnostic, the SIMD lane, D10 in Debug builds); the other three hosts need CI |
| J3a (dev backend on arm32 hosts) | `79f9ccf002` (#77) | local under qemu, plus the Raspberry Pi 5; the "Debug runner" clause cannot be met (see the issues note) |
| J3c (required cross-compile lanes) | `cd563f5c05` (#78) | CI only (all four hosts) |
| J3 hardware (call-shape battery, atomics) | `57bdd065a2` (#85) | Pi 3 and Pi 5 |
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

Each phase becomes a branch that points at its existing last commit
(`arm32/phase-1` ... `arm32/phase-8`); no new commits are made for them.

## Stage 0: preparation

1. A separate git worktree for verification, so the working branch is never
   checked out at old commits (`git worktree add ../roc-verify`).
2. Its own Zig cache directory, deleted whole whenever it passes a size limit
   (50 GB), never partially (a partial delete breaks Zig's cache; see the
   issues note on `.zig-cache`).
3. `git config rerere.enabled true`, so conflict resolutions from the trial
   merge (stage 4) are reused by the real merge.
4. The per-commit script (stage 1). It is a tool for this effort, not part of
   the product, so it lives outside the repository tree; its checks are
   listed here so the results can be reproduced.

## Stage 1: every commit, locally

For each commit from #1 to the tip, skipping commits that change only
Markdown files, in the verification worktree:

| Check | From | Command |
|---|---|---|
| Builds | #1 | `zig build roc` |
| Format, lint, tidy, git lints | #1 | `zig build run-check-zig-format run-check-zig-lints run-check-tidy run-check-git-lints` (each separately, where the step exists) |
| Backend unit tests | #1 | `zig build run-test-zig-module-backend`, judged by the test binary's totals (until `3bb3ca2b44` the step exits non-zero on a passing run because a wasm test wrote to stderr) |
| Encoding oracle | #5 | `zig build run-check-arm32-encoding-oracle` (or `python3 ci/arm32_encoding_oracle.py --check`) |
| 64-bit byte identity | #6 | `zig build run-check-dev-code-hashes` and `zig build run-check-snapshots` with no diff in `test/snapshots` |

A step that does not exist yet at a commit is recorded as "n/a", not as a
pass. Each commit's result is one row: commit, each check's result, and for a
failure the first error line. Commits already known to be red on their own
(lint and tidy violations fixed later in #79-#81, for example) are expected;
the point is to find anything *not* already known.

Estimated cost: about 85 commits at 10-15 minutes each on the desktop, so
about a day, run unattended.

## Stage 2: every unit's acceptance criteria

At each unit's last commit (table above), run the unit's acceptance criteria
as written in the plan, and record each criterion with its command, the
output that shows the result, and pass/fail. Criteria that need other hosts
or CI are marked "needs CI" and are settled in stage 6. Criteria the work
could not meet as written (for example J3a's "Debug runner") are recorded
with the reason and the evidence used instead, and cross-referenced to the
issues note, not silently counted as passing.

## Stage 3: fix what stages 1 and 2 find

Each problem found is fixed in a new commit at the tip, one problem per
commit, and recorded twice: in the results below ("red at X, fixed by Y") and
in the issues note (resolved, with the commit). Known problems to fix here
before catching up:

- The J3a CI lane needs 18 GB to build the arm32 eval runners (issues note,
  1.2), so it would fail on a hosted runner.
- The interpreter's hosted calls on arm32 hosts (issues note, 1.2, plan step 1).

## Stage 4: catch up with upstream

1. **Trial merge early**, in parallel with stages 1-3: in a throwaway
   worktree, merge `upstream/main` into the tip without committing it to the
   branch, to see where conflicts are (expected in `LirCodeGen.zig`, the
   shared driver) and to record resolutions for `rerere`. Repeat as upstream
   moves, so the real merge stays small.
2. **The real merge**, once stages 1-3 pass: one merge commit of the then
   current `upstream/main` into `32-bit-backend`. Conflicts are resolved by
   keeping upstream's behaviour and re-applying the arm32 change on top of it;
   every non-trivial resolution is described in the merge commit message.
3. Upstream changes that break arm32 at compile time (a new code path with no
   arm32 arm) are fixed in commits after the merge, one per issue.

## Stage 5: verify the merge

The committed 64-bit golden hashes describe the old base; upstream's own
changes may legitimately change 64-bit output, so after the merge the check
becomes relative:

1. **Relative 64-bit oracle:** generate the eval hashes
   (`--write-dev-code-hashes`) and the `dev_object` snapshot lines for the
   merged tip and for the `upstream/main` commit that was merged, into
   scratch files, and require the x86_64 and aarch64 values to be identical.
   That is Track A's promise on the new base: the arm32 work changes nothing
   for the 64-bit targets. Then commit the regenerated golden files in their
   own commit, citing this comparison.
2. `zig build minici`, run section by section as AGENTS.md describes.
3. arm32: the eval corpus, host effects and the fx suite under qemu
   (`cortex-a9`, the CPU floor) and on the Raspberry Pi 5; the fx suite and
   the int app (musl and glibc) on the Raspberry Pi 3.

## Stage 6: CI per phase and at the tip

In the private repository, one stacked pull request per phase (each based on
the previous phase's branch) and one for the merged tip, so CI runs exactly
each phase's change. Settles the "needs CI" criteria from stage 2. Runners:
GitHub-hosted where the minutes allow, the Raspberry Pi 5 (`roc5`,
`arm32-hw`) for arm32 hardware runs, and self-hosted macOS and Windows
machines if set up (hosted macOS and Windows minutes cost 10× and 2× on a
private repository). This stage does not block stage 4: CI on old commits is
not affected by the merge, and the macOS and Windows parts can trail.

## Stage 7: walkthroughs and upstream

After each phase passes, a walkthrough for the owner: what changed, which plan
decision it implements, what the checks prove. Then the conversation with the
maintainers, and upstream pull requests phase by phase, each brought up to
date with the `main` of that time by a merge and verified with the relative
oracle.

## Open decisions

- Whether J1's six sub-units each get their own CI run (finer phases).
- The Actions minutes budget for stage 6, and whether to wait for
  self-hosted macOS and Windows runners.

## Results

### Stage 1: per-commit table

Not run yet.

### Stage 2: acceptance checklist

Not run yet.

### Stage 4: trial merges

Not run yet.

### Stage 5 and 6

Not run yet.
