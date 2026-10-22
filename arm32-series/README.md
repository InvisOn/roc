# The arm32 series: rebuilding the backend step by step

Written 2026-10-22. This folder plans how I build the arm32 dev backend
myself, in eleven steps (0 to 10), with the reference as the source. Each
step has its own file with everything a new conversation needs to start it.

## Why a rebuilt series

The reference branch `claude/arm32-dev-backend-reference` cannot be replayed
commit by commit:

- 18 of its 49 upstream merges hold their own changes to our code (8,483
  lines in total). Cherry-picking the plain commits loses them.
- Each commit was written against the upstream of its day, so early commits
  do not apply to today's upstream.
- Only merge results were ever verified. Some commits fix earlier ones.

So the series is cut from the reference's **final state**, one topic at a
time, on one pinned upstream commit. Each step builds and is checked on its
own.

## How it relates to the earlier plans

- `NICE_BRANCH.md` (the clean branch): this series is the route for it. The
  steps land on `dev-backend-aarch32`. The rules there still hold: I write
  every commit, Claude proposes and reviews, upstream's style wins.
- `LEARNING_HOLES.md` (the holes branch): the holes move into the steps.
  Step 2 reuses its thirteen encoder holes unchanged. Its reading exercises
  (the map, reviews, bug hunts, explain it back) still fit around each step.
  The branch `arm32-holes` stays as it is.

## The pinned base

- **Upstream base:** `73df27a5bb`.
- **Reference snapshot:** `2f5d8e3685`, the reference's merge of that commit.
  It passed every check (oracle, minici, qemu, Pi 5, Pi 3) and is pushed.
- So `git diff 73df27a5bb 2f5d8e3685` is exactly our work: 127 files,
  +23,274 / -3,230 lines. Every step takes its files from this diff.
- Moving to a newer base happens only between steps, when I choose. Claude
  rebases the remaining steps for me.

## Setup on a new PC

```sh
git clone git@github.com:InvisOn/roc.git roc && cd roc
git remote add upstream https://github.com/roc-lang/roc.git
git fetch upstream && git fetch origin
git worktree add ../roc-series -b arm32-series 73df27a5bb   # or reuse dev-backend-aarch32
git worktree add ../roc-notes notes
```

Notes never go on a code branch. Add files by name, never `git add -A`.

## Every step has the same shape

1. **Goal**: what works at the end.
2. **Files**: what the step takes from the reference snapshot.
3. **Mirrors**: the aarch64 code it follows, and what differs on arm32.
4. **Holes**: the functions I write. Everything else is copied.
5. **Check**: the commands, and the test count that should pass.
6. **Done when**: the exit condition.
7. **Prompt**: text to paste into a new conversation.

Test counts are measured when Claude builds the step and are written into
that step's file. Until then they say "to be measured".

## Ground rules for every step

- **I fill the holes.** Claude cuts the step from the reference, makes the
  holes, builds it, measures the counts and reviews my work. Hints come in
  three levels: a nudge, then the idea, then the reference.
- **Predict, then look.** Before a hole, I write down what I expect.
- **Commits:** signed, no Co-Authored-By or Claude-Session line, no
  upstream `#NNNN` or roc-lang links in messages or committed files.
- **One heavy job at a time** per machine, under
  `systemd-run --user --scope -p MemoryMax=20G -p MemorySwapMax=4G nice -n 10`.
- Upstream bugs found on the way are recorded, not fixed.
- **Every `unreachable` needs a same-line `//` reason** (upstream's rule
  since 2026-10-19, checked by `zig build run-check-unreachable-rationale`),
  or a `base.invariant` call when no reason can be named.
- Update the step file's "Progress" when something changes, and push it to
  `notes`.

## The steps

| # | Step | Holes | Check |
|---|---|---|---|
| 0 | [Harness and stub backend](step-00-harness.md) | none | every arm32 test fails cleanly |
| 1 | [The driver for any word size](step-01-driver.md) | none | 64-bit output unchanged, arm32 compiles |
| 2 | [Registers and the A32 encoder](step-02-encoder.md) | 13 (from the holes plan) | the assembler agrees byte for byte |
| 3 | [Basic code generation and frames](step-03-codegen-frames.md) | about 6 | first simple eval cases |
| 4 | [The AAPCS32 calling convention](step-04-calling-convention.md) | about 4 | calls and returns |
| 5 | [64-bit values on 32-bit registers](step-05-wide64.md) | about 4 | the 64-bit number cases |
| 6 | [128-bit values as four words](step-06-i128.md) | about 3 | the i128, U128 and Dec cases |
| 7 | [ELF32 objects and linking](step-07-objects.md) | about 3 | `roc build` executables, fx under qemu |
| 8 | [Running code in-process](step-08-native.md) | about 2 | the full eval run under qemu |
| 9 | [NEON SIMD](step-09-neon.md) | about 3 | the SIMD cases |
| 10 | [Real hardware](step-10-hardware.md) | none | fx and int on the Pi 5 and Pi 3 |

## Where the reference explains itself

- `src/backend/dev/arm32/DESIGN.md`: the decisions and why.
- `src/backend/dev/arm32/GUIDE.md`: how the pieces fit, and how to test each.
- `src/backend/dev/arm32/TOOLS.md`: every tool and build step we added.
- `projects/big/arm32-dev-backend-existing-code-changes.md`: every change to
  upstream code, with the reason.
- `projects/big/arm32-dev-backend-walkthroughs.md`: walkthroughs with questions.

## Progress

- 2026-10-22: plan written. No step built yet.
