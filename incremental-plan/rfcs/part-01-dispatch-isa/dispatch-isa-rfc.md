# Part 1: architecture dispatch and driver word size (1 of 3)

- **Status:** Draft
- **Scope:** Branch
- **Plan row:** 1, Architecture dispatch (`isa.zig`, `binaryIs`) and driver
  word size (1 of 3)
- **Branch:** `dispatch/isa`
- **Fork PR:** [#9](https://github.com/InvisOn/roc/pull/9)
- **Parent:** none
- **Base:** `3bb8f2ec6c` (upstream; see D3)
- **Head:** `e65824d17e` (fold steps 1 to 5, not pushed)

## Abstract

Part 1 makes the dev backend's shared driver ready to have a third
architecture added, without changing a byte of x86_64 or aarch64 output. It
brings in one `Isa` type that every architecture choice goes through, four
small fixes for 32-bit machines (instruction cache flush, glibc stub
returns, abs64 relocation width, target data measured with the host's word
size), and the first third of the driver's word-size work: the word
vocabulary and four commits that make integer logic word-relative. Two
decisions are settled (what folds in, which word-size commits). One is open:
which upstream commit the branch sits on. The relative oracle shows x86_64
and aarch64 object bytes unchanged, and new unit tests check the layout
helpers at a 4-byte and an 8-byte word.

## Problem

The dev backend's shared driver, `LirCodeGen.zig`, assumes two things that
are true only for x86_64 and aarch64. Every choice between architectures is
written as "x86_64, otherwise aarch64", so a third architecture silently
takes aarch64's path. And every size and width assumes an 8-byte word. The
four folded fixes are the same kind of bug outside the driver: code that
uses the compiler machine's word size, or one architecture's instruction,
where the target's is meant.

None of this fails on upstream's supported setups. It fails as soon as the
target or the compiler's own machine is 32-bit, which every later part of
the plan needs. Fixing it first, with output unchanged, lets the arm32 parts
add code instead of changing shared code.

### Breakages you can run

Commit: upstream `main` at `629c3e0e2d`. Run from a scratch worktree of that
commit, made from the main checkout:

```sh
git worktree add --detach .workspaces/probe-629c 629c3e0e2d
```

All commands below run from `.workspaces/probe-629c`. Remove the worktree
afterwards with `git worktree remove --force .workspaces/probe-629c` from the
main checkout.

**1. The abs64 relocation writes 4 of its 8 bytes on a 32-bit compiler
(draft 12).** Append the test from draft 12, "How to reproduce", to
`src/backend/dev/Relocation.zig`, then:

```sh
printf 'test {\n    _ = @import("backend/dev/Relocation.zig");\n}\n' > src/probe_relocation.zig
zig test src/probe_relocation.zig --test-filter "abs64 data relocation writes all eight"
zig test src/probe_relocation.zig --test-filter "abs64 data relocation writes all eight" -target x86-linux-musl
```

The first passes. The second, a 32-bit build, prints
`expected 287454020, found 12297829379897176900` (`0x11223344` against
`0xAAAAAAAA11223344`) and `1 passed; 0 skipped; 1 failed.` Right: both pass.
Cause: `Relocation.zig:253-260`, which picks the write width from
`@sizeOf(usize)`, the compiler's own word.

**2. The glibc stub writes `ret` for 32-bit ARM (draft 16).** Append the
test from draft 16 to `src/build/glibc_stub.zig`, then:

```sh
printf 'test {\n    _ = @import("build/glibc_stub.zig");\n}\n' > src/probe_glibc_stub.zig
zig test src/probe_glibc_stub.zig --test-filter "32-bit ARM glibc stub"
```

It fails at `glibc_stub.zig:155` with `2 passed; 0 skipped; 1 failed.` Right:
it passes. Cause: `glibc_stub.zig:24`, `93` and `100` write `ret` for
`.arm`, which has no such instruction.

**3. The driver can't be built for a 4-byte word.** Append to
`src/backend/mod.zig`:

```zig
test "probe: the dev driver for a 4-byte word" {
    _ = dev.LirCodeGenMod.LirCodeGen(.arm32musl);
}
```

```sh
zig build build-test-zig -j14
```

It stops at `LirCodeGen.zig:494`, "LirCodeGen requires x86_64 or aarch64
target". With that check and the `target_ptr_size == 8` assert (line 505)
deleted, it stops at line 518, which expects the small-string flag at bit
63; a 4-byte word puts it at bit 31. With that assert deleted too, lines
531-534 pick `aarch64.CodeGen` for 32-bit ARM, and only aarch64's own check
stops it (`aarch64/CodeGen.zig:31`, "aarch64.CodeGen requires an aarch64
target"). Right: the architecture choice names every architecture, and the
sizes follow the target's word.

The layout helpers are not part of the problem: upstream's
`RocStr/RocList.targetFieldOffset` already give the right positions at a
4-byte word (string length at 8, list length at 4, small-string bit
`0x80000000`).

Not runnable: the missing instruction cache flush (draft 03) fails only by
timing on aarch64, and the host word-size sites (draft 07) only on a 32-bit
compiler machine, which example 3 stops first. Both are shown by reading
`ExecutableMemory.zig:404-408` and the `grep` commands in draft 07.

## What this enables

- **Follows directly:** parts 2 and 3 (the rest of the word-size work)
  build on the vocabulary and on `Isa`.
- **Follows directly:** part 6 (the arm32 code generator) adds one `Isa`
  member, and the compiler then lists every architecture choice that must
  handle it, instead of arm32 silently taking aarch64's path.
- **Follows directly, for upstream today:** JIT code on aarch64 no longer
  depends on timing to see freshly written instructions (draft 03).
- **Follows directly, for upstream today:** the compiler can run on a
  32-bit machine without corrupting relocations or target data (drafts 12
  and 07), and the wasm eval backend reports itself unavailable there
  instead of failing.
- **Possible later, not planned:** any other 32-bit dev backend target
  (32-bit x86, wasm32 through the dev backend) reuses the same vocabulary.

## Background

- **Word:** the size of an address on a machine, 8 bytes on x86_64 and
  aarch64, 4 on 32-bit ARM. Not the same as Roc's `I64`, which is 8 bytes
  everywhere. The word-size primer explains the terms used here:
  https://claude.ai/artifact/VdH6ooZsWfX7tT4DrEbm1h
- **Host and target:** the machine running the compiler and the machine the
  program runs on. Drafts 07 and 12 are host-for-target mix-ups.
- **The reference branch** `claude/arm32-dev-backend-reference` holds the
  full arm32 backend. Its "A2" commits are the word-size work, 14 in all.
- **What is on the branch** (fold steps 1 to 5, 21 files, +431/−307):

  | Commit | What | From |
  |---|---|---|
  | `0b8b57955c` | One `Isa` type for the architecture choice | #9 |
  | `3acba1afb1` | Flush the instruction cache before running JIT code | #8, draft 03 |
  | `430427f287` | A32 returns in the glibc stub | #4, draft 16 |
  | `30ccea2335` | abs64 writes eight bytes on any host | #3, draft 12 |
  | `9c6a25e452` to `e65824d17e` | Six host word-size fixes | draft 07 |

- **Fold step 6** adds `bf9d0e0d49` and the four "Make … word-relative"
  commits (`0676c747be`, `75e30d5f49`, `b2ec6583e4`, `e7d97b7d88`), about
  +941/−744 lines as written on the reference. Part of `bf9d0e0d49` is
  already upstream (the target-scaled string and list offsets). Its own
  planning doc holds four open questions about bringing them in.
- **Write-ups** of fold steps 1 to 5 are in this directory
  (`step-1-rebase.md` to `step-5-host-word-size.md`).

## Discussion

The constraints:

- **Acceptable upstream.** The PR is judged as if a maintainer wrote it: it
  follows upstream's current code and style, each commit builds and makes
  sense on its own, it brings no reference-branch leftovers (milestone
  labels like "J1", TODOs, code for later parts), and it includes every
  later fix the reference made to the same code. How the code gets onto the
  branch (cherry-pick or cut) doesn't matter.
- **AGENTS.md:** no workarounds, fallbacks or heuristics. A compiler
  invariant is a debug assert or `unreachable`, never a runtime check.
- **64-bit output unchanged.** The relative oracle must show x86_64 and
  aarch64 object bytes identical before and after.
- **Review size.** The plan aims for 300 to 2,000 lines per PR.
- **Plan order.** One PR open at a time. Parts 2 and 3 follow and must not
  need part 1 reopened.
- **Upstream's style wins**, for example a same-line reason on every
  `unreachable`.

### Alternatives considered

- **Each fix as its own PR (#8, #3, #4, a PR for draft 07).** Rejected
  because the fixes only matter for the change that needs them, and
  reviewing them apart hides why (decided 2026-10-24).
- **The architecture dispatch alone, word size later.** Rejected because the
  dispatch then arrives with nothing that uses it (decided 2026-10-24, when
  the old part 3 joined).

## Decisions

### D1. What folds into #9

- **Status:** Accepted (2026-10-24)
- **Context:** The fixes for drafts 03, 12 and 16 were separate fork PRs
  (#8, #3, #4), and draft 07 had none. Each is small and only matters for
  32-bit work.
- **Alternatives:**
  1. Fold all four into #9, and close #8 and #3 (#4 is already closed).
     Implications: one review, about 750 lines before step 6.
  2. Keep them as separate PRs. Implications: four small reviews, each
     without the change that motivates it.
- **Recommendation:** Alternative 1.
- **Consequences:** #9 is larger and mixes the dispatch with fixes outside
  the driver. #8 and #3 close in fold step 8. If upstream merges the glibc
  stub PR (12513) first, its commit drops out.

### D2. Which word-size commits come in

- **Status:** Accepted (2026-10-25, option 1)
- **Context:** A2 has 14 commits. The plan's estimate of about 2,150 lines
  for part 1 assumed all of them.
- **Alternatives:**
  1. The vocabulary (`bf9d0e0d49`) and the four "Make … word-relative"
     commits. The nine "Classify …" commits go to part 3. Implications:
     about +941/−744 more lines; the logic changes land with the vocabulary
     they use.
  2. All 14. Implications: about twice the size, mostly relabelling.
  3. None (word size starts in part 2). Implications: part 1 has nothing
     that uses `Isa`; see Alternatives considered.
- **Recommendation:** Alternative 1.
- **Consequences:** Three of the four commits use definitions that live in
  two "Classify" commits. How to bring those in is question Q1 of the
  step 6 doc. Part 3 grows by the nine "Classify" commits.

### D3. Which upstream commit #9 sits on

- **Status:** Accepted (2026-10-26, alternative 1)
- **Context:** The branch sits on `3bb8f2ec6c`, from before upstream stopped
  compiling. Upstream compiles again and is 45 commits further
  (`629c3e0e2d`); `LirCodeGen.zig` has moved (the 8-byte assert from line
  503 to 505). HANDOFF says to rebase before the checks in fold step 7.
- **Alternatives:**
  1. Rebase onto current `upstream/main` before step 6. Implications: step
     6's conflicts are resolved once, against the code it ships on; costs
     a rebase now and a rerun of the full test set (about 15 minutes) for
     steps 1 to 5.
  2. Rebase after step 6, before step 7. Implications: step 6 is written
     against older code, and its conflicts may need resolving again in the
     rebase.
- **Recommendation:** Alternative 1.
- **Consequences:** The step 1 to 5 hashes change, so the write-ups'
  hashes become history; HANDOFF's #9 row needs the new head.

## Risks

### R1. A width is right for 64 bits and wrong for 32

- **Likelihood:** Medium
- **Impact:** High
- **How we'd notice:** Nothing in part 1 would: 64-bit output is unchanged
  either way. Only arm32 tests from part 6 on.
- **Mitigation:** The unit tests at a 4-byte word; one ultrareview spent on
  part 1 (README, "Ultrareviews").
- **If it happens:** Fix it in the part that finds it, with a test.

### R2. Upstream changes `LirCodeGen.zig` faster than #9 merges

- **Likelihood:** High
- **Impact:** Medium
- **How we'd notice:** Conflicts when rebasing.
- **Mitigation:** Keep #9 rebased; one PR open at a time.
- **If it happens:** Rebase, rerun the oracle.

### R3. The instruction cache flush is wrong on ARM hardware

- **Likelihood:** Low
- **Impact:** High
- **How we'd notice:** Fold step 7 runs it on ARM hardware, 64-bit and
  32-bit. It has only run on x86_64, which never needs a flush.
- **Mitigation:** Run it on ARM hardware before #9 leaves draft.
- **If it happens:** Fix in #9 before it goes upstream.

### R4. The 32-bit host branches are only compile-checked

- **Likelihood:** Low
- **Impact:** Low
- **How we'd notice:** A 32-bit host build: on a 32-bit ARM machine
  (part 11), or the 32-bit x86 build below.
- **Mitigation:** Checked on 2026-10-25. From the repository root,
  `zig build run-test-zig-module-eval -Dtarget=x86-linux-musl` builds the
  `eval` module for 32-bit x86, so its host branches compile. Its tests
  give 61 passed, 1 skipped and 9 crashed: the same tests, with the same
  messages, as on the base `3bb8f2ec6c` without part 1. The crashes are
  older 32-bit host problems outside part 1: LLVM has no 32-bit x86 data
  layout, some values are laid out for a 64-bit host, and crash recovery
  isn't set up.
- **If it happens:** Fix in the part that builds them.

### R5. The oracle compares less than it seems to

- **Likelihood:** Low
- **Impact:** High
- **How we'd notice:** The oracle's own report of what it compared.
- **Mitigation:** Run with `--apply-a0-to-merged`; check that the eval hash
  files were written by this run (the earlier #9 pass compared a stale one).
- **If it happens:** Rerun after fixing the setup.

## Testing

Run from `.workspaces/pr-isa`, on the finished branch:

```sh
zig build run-check-zig-format -j14
zig build run-check-unreachable-rationale -j14
zig build run-test-zig-module-backend -j14
zig build roc -j14
zig build run-test-zig-module-check -j14
zig build run-test-zig-module-compile -j14
zig build run-test-zig-module-eval -j14
zig build run-test-zig-lir-inline -j14
zig build run-test-zig-snapshot-tool -j14
zig build run-check-snapshots -j14
zig build run-test-eval -j14
zig build minici -j14
```

Each passes. On `e65824d17e` the first ten passed in about 15 minutes, and
`run-test-eval` gave 2593 passed, 47 skipped. Step 6 adds unit tests at a
4-byte and an 8-byte word to `run-test-zig-module-builtins` (RocStr and
RocList field offsets) and `run-test-zig-module-backend` (`intOverflowCheck`,
`wordOfU128`).

The relative oracle, from the main checkout (about an hour, up to 20 GB):

```sh
python3 .workspaces/notes/incremental-plan/tools/relative_oracle.py --upstream <base> --merged <head> --apply-a0-to-merged
```

Expected: x86_64 and aarch64 output byte-identical.

The reference check: compare each changed line with the reference's final
state (`e0fa273ebf`) and list every difference. Each one is either a later
reference fix we still need, or an intended change for upstream (style,
current code). None is left unexplained.

The flush on ARM hardware: run the JIT tests on a 64-bit and a 32-bit ARM
device, such as a Raspberry Pi (which we do). The exact commands are
written in fold step 7.

## Recommendation

- D1: fold all four fixes into #9 (accepted).
- D2: the vocabulary and the word-relative commits (accepted). Done as five
  commits in step 6; the structural equality commit has no code left upstream.
- D3: rebase onto current `upstream/main` before step 6 (accepted, done
  2026-10-26 onto `629c3e0e2d`).

The remaining fold steps:

| Step | What |
|---|---|
| 6 | Word size (1 of 3), with its own planning doc (Q1 to Q4) |
| 7 | Checks: the commands above, the relative oracle, the reference check, ARM hardware |
| 8 | #9's description (plan table, "How the code flows", "How to test"); close #8 and #3 |
| 9 | Review #9 again; a dated entry in `pr-review.md` |
