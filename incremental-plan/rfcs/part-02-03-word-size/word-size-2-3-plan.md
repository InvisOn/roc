# Parts 2 and 3: the rest of the driver's word size (re-plan)

- **Status:** Draft
- **Scope:** Branch (plan rows 1 to 3, one PR since 2026-10-28)
- **Plan row:** 1–3, the shared driver for any backend
- **Branch:** `isa-word-size` (worktree `.workspaces/pr-isa-word-size`); step 1 alone is `isa-switch`, fork #11, upstream PR 12740
- **Fork PR:** not yet (new; replaces #9)
- **Parent:** none
- **Base:** upstream `main` at `f7bef6b38f` (2026-11-01), rebased onto `main` whenever it moves. The measurements below were taken on `dispatch/isa` at `1bc3981a38` (upstream `26436de489`)
- **Head:** `d0dce2c444` (step 1 replayed on the base)

## Abstract

Part 1 (#9) made the shared driver's word size explicit for strings,
lists, integer arithmetic, low-level pointers, conversions and bit counts.
Parts 2 and 3 were to finish the job: part 2 by moving about 55 helpers
behind each architecture's code generator, as the reference did; part 3
by classifying every remaining `.w64`. Measured on current upstream, the
reference's part 2 no longer fits: upstream kept those helpers in the
driver, and 22 of the 51 the reference moved no longer exist. This plan
drops the move, keeps the two small register "seams" the 32-bit ARM code
generator needs, and keeps part 3's classification (D1 to D4). As with
part 1, x86_64 and aarch64 output stays byte-identical, shown by the
relative oracle.

## Problem

Part 1 leaves 538 `.w64` sites in `LirCodeGen.zig`, in 132 functions,
and the driver still requires an 8-byte target word. Each remaining site
is either a value that is one target word (a pointer, a length, a count)
and must become `word`, or a value that is 64 bits on every target (a U64,
an i128 half, F64 bits) and must say so by name. Until every site is one
or the other, lifting the 8-byte assert in part 6 would let a word-sized
value be handled as 64 bits on a 32-bit target, silently.

The driver also names x86_64 and aarch64 registers directly: a text search
finds about 107 x86 and 53 aarch64 register names in `LirCodeGen.zig`,
some in comments or in paths that are one architecture's on purpose. For
example `if (isa.binaryIs(.x86_64)) .R11 else .X9` for a
scratch register (`LirCodeGen.zig:629`). A third architecture needs its
own answer at each.

The plan's part 2, "emit helpers move onto each code generator", came from
the reference's facade commits. Upstream has since gone the other way: its
driver keeps its own helpers (`self.emitLoad`, `self.emitStore`) and picks
the architecture inside them. The README already says part 2 "needs
re-planning".

### Breakages you can run

None yet. Nothing changes for 64-bit targets, and no 32-bit target can be
built until part 6 lifts the 8-byte assert. The sites are found by
reading, and checked by the step 6 coverage table once arm32 runs in CI
(parts 8 and 9).

## What this enables

- **Follows directly:** part 6 can lift the 8-byte assert with every site
  classified, and add arm32 to `Isa`.
- **Follows directly:** the arm32 code generator supplies its own scratch
  and role registers instead of the driver naming x86 and aarch64 ones.
- **Possible later, not planned:** a raw `.w64` count of zero makes a
  simple CI check possible: any new raw `.w64` in the driver fails.

## Background

- **Reference commits, part 2 (A1):** `cc1c5fa33d` temporary registers
  into each code generator (+232/−73), `1454f147da` the driver's role
  registers from the per-ISA calling convention (+68/−78), `dc29e1e970`
  and `7b9a395773` the facade, 41 and 14 helpers (+1,481/−1,247). About
  3,180 changed lines in all. The dispatch commit `28281b0f3f` became
  part 1's `isa.zig`.
- **Reference commits, part 3 (A2):** the nine "Classify ..." commits
  (`c38adf988b`, `93c546d7b5`, `1732f08923`, `6a4fec0a76`, `da4cb4a451`,
  `236042aa45`, `6f03627f1b`, `c4156ac121`, `152574b40d`), about 1,160
  added and 850 removed lines. Together with the A2 commits part 1 took,
  they brought the reference from 868 `.w64` sites to 5.
- **Measured on `1bc3981a38`:** 538 `.w64` sites in 132 functions (most:
  `generateLowLevel` 26, `storeI128ToMem` 18, `generateNumAbs` 17,
  `generateAbsDiff128` 17, `storeWideScalarToStackOffset` 16,
  `generatePackedErasedFn` 16); 223 `binaryIs` lines in 137 functions; of
  the reference's 51 moved helpers, 29 still exist in the driver.
- **Step 6's "left for part 3" list**
  (`../part-01-dispatch-isa/step-6-word-size.md`): memory arguments,
  multi-register values, compare helpers with a built-in 64-bit width,
  other pointer-sized values, erased-callable calls and
  `generatePackedErasedFn`, 128-bit bit counts, and the 64-bit width names.
- **The Wide64 dispatch:** where the reference routes a 64-bit integer
  operation to a separate path (`generateWide64IntBinop`,
  `generateWide64IntConversion`, `generateWide64IntUnary`) when the word is
  4 bytes, because the value then needs a register pair. Part 1 left it
  out (its plan D2). The routing must exist by the time part 6 lifts the
  8-byte assert, or a 64-bit operation on arm32 would take the one-register
  path; the lowering itself (register pairs) is part 10.
- **Width names (plan D2 of part 1):** `wide64_reg_width` and
  `wide64_store_width`, `.w64` at an 8-byte word and a compile error at a
  4-byte word ("a 64-bit value needs a register pair on a 32-bit
  target"). Every 64-bit-on-every-target site uses them, so a raw `.w64`
  means an unclassified site.

## Discussion

- **Acceptable upstream:** follow upstream's current driver, which keeps
  its helpers and chooses the architecture inside them. Each commit builds
  and passes alone. No reference leftovers.
- **Output unchanged:** x86_64 and aarch64 byte-identical (relative
  oracle), as in part 1.
- **Review size:** 300 to 2,000 lines per PR (README); re-measure when cut.
- **Plan order:** both parts come before part 4; part 6 depends on them.

### Alternatives considered

- **The reference's facade as it is.** Rejected because 22 of its 51
  helpers no longer exist upstream and it reverses upstream's choice to
  keep helpers in the driver; about 3,000 lines of churn to review.

## Decisions

### Decided 2026-10-28 (supersedes D2; the rest of this doc still needs updating to match)

- `dispatch/isa`, `word-size/emit-helpers` and `word-size/driver-rest`
  become one PR on a new branch, with a new fork PR, because none of it is
  specific to 32-bit ARM: every backend on the shared driver uses it. It
  must be good for all backends.
- The size is accepted (no 2,000-line limit for this PR).
- The glibc stub commit (`3d73760a5b`, 32-bit ARM instructions in the test
  platforms' fake libc) moves to part 8. It is build tooling, not the
  shared driver.
- The branch is `shared-driver/isa-word-size`, worktree
  `.workspaces/pr-shared-driver`, cut from upstream `main` at
  `bad769be8e`. Every time `main` has new commits, the branch is rebased
  onto it (not merged). It has no upstream tracking branch, so a plain
  `git push` can't reach roc-lang/roc. The README's plan table shows parts
  1 to 3 as one row; the part numbers stay as they are.
- #9's other 14 commits are reviewed one at a time, and each goes into the
  branch, or to another part, only after its decision is recorded here.

### Decided 2026-10-28: #9 commit 1 (`36825aa1f9`, one `Isa` type)

Goes into the shared PR, reworked (supersedes D3):

- **A. Exhaustive switches, no `binaryIs`.** Every architecture choice in
  the shared driver is a `switch (isa)` that names each backend's answer.
  Conditions that combine the architecture with something else become a
  switch that yields a `bool` (for example
  `switch (isa) { .aarch64 => lowered.ret == .indirect, .x86_64 => false }`),
  never `isa == .x`. Facts about one backend (scratch, return and role
  registers) come from each code generator where part 2's register seams
  cover them, instead of a switch in the driver. A Zig lint against
  `isa ==` is optional. Chosen on merit: both answers named at the site,
  the guard can't leak through a cached `bool`, backends can share an
  answer, and it is Zig's own mechanism. To verify by compiling: a switch
  on a comptime `isa` skips the other backend's arm, as `if (comptime ...)`
  does.
- **B. Close the guard's holes.** The cached `is_x86_64` / `is_aarch64`
  flags in `FrameBuilder` and `CallingConvention` (36 uses) become
  switches; `ObjectFileCompiler.zig` (the `inline for` over targets) and
  `host_lir_codegen_available` ask `isa.zig` (for example an
  `isaOfOrNull`) instead of their own lists; `aarch64/CodeGen.zig` and
  `aarch64/Emit.zig` reject `aarch64_be` like `isaOf`; the unreachable
  big-endian `@compileError` in `num_from_le_bytes_unchecked` goes.
- **C. Message, tests, style, design.md.** The commit message says why a
  new enum rather than `CpuArchClass` (no dead `arm`/`wasm32`/`other`
  arms) and that `aarch64_be` was already broken (140 checks were
  `== .aarch64` without `_be`, sending it down the x86_64 branch). The
  `isaOf` test covers every x86_64 and aarch64 `RocTarget` with a comptime
  loop. The compile error names the rejected target. `design.md` gets a
  short paragraph: an architecture choice in the shared driver is a
  `switch (isa)`. (The `binaryIs` test, `inline` and `comptime`-consistency
  points go away with A.)

### Decided 2026-10-28: #9 commit 2 (`200333a587`, instruction cache flush)

- **Goes into the shared-driver PR** (owner, 2026-10-28, replacing the
  same day's first decision, "its own small PR"). It is not shared-driver
  code (it touches `ExecutableMemory` and error lists, not `LirCodeGen`,
  `FrameBuilder` or `CallingConvention`) and nothing else in #9 depends on
  it, but it rides with the shared PR rather than as a separate PR.
- It still gets an issue: the draft is
  `upstream-issue-drafts/03-icache-not-flushed-before-jit.md`, updated the
  same day, to be reviewed with the owner later, before filing. The shared
  PR links it.
- Fixes to make when it is taken onto the branch: the commit message leads
  with aarch64 and says the architecture requires the flush, without
  implying an observed failure; each of the 10 error-list placements of
  `FlushInstructionCacheFailed` is checked.

### D1. What part 2 contains

- **Status:** Proposed
- **Context:** the facade no longer fits upstream (Background). The two
  register seams still do: the driver names x86 and aarch64 registers
  directly.
- **Alternatives:**
  1. Port the facade anyway, adapted to today's helpers. Implications:
     an estimated 2,000 to 3,000 changed lines, reverses an upstream choice,
     likely pushback; part 6 then adds arm32 helpers in its own file.
  2. Only the register seams: temporary registers and the calling
     convention's role registers come from each architecture's code
     generator (`cc1c5fa33d`, `1454f147da`, adapted). Helpers stay in the
     driver. Implications: an estimated 300 to 600 changed lines; part 6
     gives each helper's `binaryIs` an arm32 answer instead (see D3).
  3. No part 2; the seams go into part 6. Implications: one PR fewer, but
     part 6, already large, also carries driver refactoring.
- **Recommendation:** Alternative 2.
- **Consequences:** part 2 becomes small and uncontroversial; the facade's
  benefit (arm32 code in arm32's own file) is lost, so arm32 answers sit
  in the driver's `switch (isa)`s, as x86_64 and aarch64 do today.

### D2. One PR or two

- **Status:** Proposed
- **Context:** estimated sizes on current upstream (not measured): part 2
  (D1 alt. 2) 300 to 600 lines. Part 3: between about 1,800 (every site at
  the reference's 3 to 4 changed lines) and about 3,800 (every site at part
  1's 7). Grouping the 538 sites by the function they are in: 184 are in
  64-bit-value functions (i128, Dec, F64, SIMD; likely one-line width
  names), 182 in calls, returns, frames and erased calls (likely
  restructuring), 172 mixed. Weighted, about 2,400 to 3,000, with the width
  names and the Wide64 routing.
- **Alternatives:**
  1. One PR for both. Implications: an estimated 2,700 to 3,600 lines,
     over the limit.
  2. Two PRs as planned: part 2 the seams, part 3 the classification.
     Implications: part 3 is likely over 2,000, so it is expected to split
     by commit group (calls and returns; pointers, Boxy and erased calls;
     i128 and SIMD with the width names) when it is cut.
  3. Merge the seams into part 3's first PR, and split the
     classification in two. Implications: same total, different seams.
- **Recommendation:** Alternative 2.
- **Consequences:** plan numbering unchanged; part 3 most likely becomes
  two or three PRs.

### D3. Where `binaryIs` sites become `switch (isa)`

- **Status:** Proposed
- **Context:** 223 `binaryIs` lines, 137 functions. When arm32 joins
  `Isa`, each fails to compile until it is a switch with an arm32 answer.
- **Alternatives:**
  1. In part 6, as arm32 joins `Isa`. Implications: the switches arrive
     with real arm32 answers; part 6 grows by those arms.
  2. In part 2 or 3, as two-armed switches now. Implications: about 220
     sites of churn with no new behaviour, then touched again in part 6.
- **Recommendation:** Alternative 1.
- **Consequences:** `binaryIs` stays until part 6; parts 2 and 3 don't
  touch it.

### D4. What part 3 contains

- **Status:** Proposed
- **Context:** step 6's list, the reference's classify commits, and the
  width names.
- **Alternatives:**
  1. Everything on step 6's list except the 128-bit and 64-bit lowering
     (part 10), plus the width names and the Wide64 routing. The
     memory-argument sites are classified here too (as `word` or as the
     64-bit width name, whichever is right today); part 7 then only
     changes the calling convention. Implications: raw `.w64` reaches zero;
     part 6 can lift the assert.
  2. Only the pointer-sized sites; width names later. Implications: a
     raw `.w64` keeps two meanings until part 10.
- **Recommendation:** Alternative 1.
- **Consequences:** a CI check for new raw `.w64` becomes possible from
  part 3; part 3 grows by the memory-argument sites.

## Risks

### R1. A word-sized value is classified as 64-bit, or the reverse

- **Likelihood:** Medium
- **Impact:** High (wrong values on arm32, silent on 64-bit)
- **How we'd notice:** nothing on 64-bit; the step 6 coverage tests on
  arm32 from parts 8 and 9.
- **Mitigation:** the reference check against `e0fa273ebf` for each site;
  an ultrareview (the README gives part 3 one).
- **If it happens:** fixed in the commit it belongs to, before part 6.

### R2. Upstream reworks the driver again before the cut

- **Likelihood:** High
- **Impact:** Medium
- **How we'd notice:** the counts above change.
- **Mitigation:** re-measure at the cut; this plan keeps to upstream's
  own structure, so most changes rebase.
- **If it happens:** update D2's sizes and the site list.

## Testing

From the PR's worktree, as for part 1: the full set, `zig build minici`,
and the relative oracle against the base
(`python3 .workspaces/notes/incremental-plan/tools/relative_oracle.py
--upstream <base> --merged <head> --apply-a0-to-merged`, from the main
checkout), which must report PASS with 0 differences. The reference check
compares each changed site with `e0fa273ebf`. No device runs: nothing new
runs on ARM until part 6.

## Recommendation

D1 alternative 2, D2 alternative 2, D3 alternative 1, D4 alternative 1:

- **Part 2, "Driver register seams":** temporary registers and the
  calling convention's role registers from each code generator. About 300
  to 600 lines. Branch `word-size/register-seams`.
- **Part 3, "Driver word size: the rest":** step 6's list including the
  memory-argument sites (minus 128/64-bit lowering), the remaining
  classify commits adapted, the width names and the Wide64 routing. An
  estimated 2,400 to 3,000 lines, expected to split by commit group when
  cut.
- **Not here:** `binaryIs` to `switch (isa)` (part 6), the calling
  convention itself (part 7), 64- and 128-bit lowering (part 10).

Both are cut after #9 merges, each with its own step plan, and the README's
rows for parts 2 and 3 change once this is accepted.

### Decided 2026-10-28: #9 commit 3 (`8b9b055402`, abs64 written as eight bytes)

- **Not in the shared PR.** It goes into another part of the plan, which
  one to be decided later (candidates from the review: part 5, with
  `abs32` and the ARM relocations, or part 9).
- Review findings to carry with it: no real compiler run reaches the bug
  (in-memory `abs64` code only runs on 64-bit hosts; a 32-bit ARM host
  uses `abs32`), so the message should call it a cleanup, not a fix; its
  new test can't fail on any machine CI runs tests on; the hard-coded
  `.abs64` for `local_data` relocations (`Relocation.zig:185`) is its
  natural companion (the reference picks it by architecture). Whether to
  rewrite the message and pair it is decided with its destination.

### Decided 2026-10-28: #9 commits 4 to 7 (target word instead of the compiler's)

`a6b1c06b0c`, `863bcaa8e7`, `bd4c9b9add`, `3ce5cb09f3`:

- **All four go into the shared PR.** Commits 5, 6 and 7 are squashed into
  one commit: commit 5 alone stores at the target's offsets but still
  sizes the allocation and checks the prefix with the compiler's values.
- **Open, to decide later:** where the erased-callable layout lives.
  Options from the review: (1) in `src/builtins/erased_callable.zig` as a
  layout for a given word size (for example `layoutFor(ptr_size)`), with
  the builtins' own constants derived from it, unit-tested at 4 and 8
  bytes, used by the dev backend (recommended); (2) inside `LirCodeGen` as
  `erased_layout`, as #9 has it; (3) as (1), and the LLVM and wasm
  backends switched over too (draft 38).
- **Fixes:** commit 4's drop-pointer store takes its offset from the
  layout (the offset of `Payload.on_drop`), not a bare `target_ptr_size`;
  the alignment checks that use `target_ptr_size - 1` get a name or a
  comment saying pointer alignment equals pointer size on every Roc
  target; each commit message says when the old code is wrong (a compiler
  running on a 32-bit machine building 64-bit code).

### Decided 2026-10-28: #9 commits 8 and 9 (wasm on 32-bit hosts)

`1b569dfd0d`, `6cd2d68e6d`:

- **Not in the shared PR.** Where they go is decided later (candidates
  from the review: part 9 recommended, part 8, or their own PR).
- Review findings to carry with them, decided with their destination:
  skipping works around bytebox reserving a module's whole memory
  (`instance.zig:263`); the alternatives are a declared memory maximum
  (`WasmModule.memory_max_pages`, `null` today) or a bytebox change, and
  the message should name them; the `@sizeOf(usize) >= 8` check is
  written twice (`eval/mod.zig`, `parallel_cli_runner.zig`) and should be
  one constant named after bytebox's condition; the two could be one
  commit.

### Decided 2026-10-29: #9 commit 10 (`9c6152e666`, RocStr and RocList at the word width)

- **Goes into the shared PR.**
- **Fix:** the three-register argument path (`LirCodeGen.zig:19341` at
  `1bc3981a38`) serves strings, lists and records or tag unions of 17 to
  24 bytes. It now loads three words, but the register count is still in
  8-byte units (`aggregateArgRegisterPressure`, `(size + 7) / 8`), so a
  24-byte record on a 4-byte target would load half of itself. The
  register count becomes word-based with it; the commit message no longer
  says records "load as words" as if that were a fix.
- **The shared PR ends with every `.w64` named** (`word` or a width name
  for values that are 64 bits on every target), the rule written in
  `design.md` (with commit 1's `switch (isa)` rule), **and a check** that
  rejects a new raw `.w64` in the driver.
- **Open, to decide later:** the names `target_ptr_size` / `word` /
  `word_bits` (keep; rename to a matching `target_word_*` set; or only
  clarify `word`'s doc comment). Settle before commits 11 to 14 are taken
  onto the branch, since they build on `word`.

### Decided 2026-10-29: #9 commit 11 (`4ca2daf8fa`, one-register integer arithmetic)

- **Goes into the shared PR.**
- **Open, to decide later:** (a) whether the Wide64 routing (plan D2) is
  part of this PR, so `intOverflowCheck`'s assert ("an integer wider than
  the word never reaches this path") is backed by code in the same PR,
  and the commit message points at it; (b) whether signedness comes from
  one source (`emitIntMulOverflowFlag` uses the layout's `shape.signed`,
  the add/sub and checked-multiply paths use `is_unsigned`), or keeps both
  with a Debug check that they agree.
- Carried to the PR's part 3 work: the width-less helpers (`emitCmpImm`,
  `emitCmpReg`, `emitSetCond`, `emitCrashOnCond`), already on step 6's
  "left for part 3" list.

### Decided 2026-10-29: #9 commit 12 (`b7a9abbcc9`, low-level pointers at the word width)

- **Goes into the shared PR.**
- **Open, to decide later:** whether the four in-bounds `U64` index loads
  (`list_get_unsafe`, `list_map_extract_unsafe`, `list_map_write_unsafe`,
  `num_from_le_bytes_unchecked`) go through one helper (for example
  `emitLoadInBoundsIndex`) that states the rule once: the index is below
  the list length, so its low word is the whole index; that is the slot's
  start only on a little-endian target (with a compile-time check); and a
  `U64` in registers is a register pair on a 4-byte word (part 10).

### Decided 2026-10-29: #9 commit 13 (`daf1c616f6`, integer conversions)

- **Goes into the shared PR.**
- **Open, to decide later:** (a) how a source wider than the word is kept
  off the one-word conversion paths: a pure function that chooses the path
  (for example `intToFloatPath(src_bits, signed, word_bits)`), asserting
  `src_bits <= word_bits` and tested at 32 and 64 bits like
  `intOverflowCheck`; or only Debug asserts at each
  `if (src_bits < word_bits)`; to be decided with commit 11's Wide64
  routing question. Today nothing checks it: on a 4-byte word `u64_to_f64`
  and `i64_to_f64` would silently convert one word. (b) Whether
  `word_bits` gets its `u8` type in commit 10, where it is introduced,
  instead of here.
- Carried to the PR's part 3 work: `andRegImm8` in the x86 unsigned
  conversion has no width parameter (joins the width-less helpers from
  commit 11).

### Decided 2026-10-29: #9 commit 14 (`1bc3981a38`, scalar bit counts)

- **Goes into the shared PR.**
- **Open, to decide later:** (a) the guard against a source wider than the
  word in `generateBitCountScalar` (`U64`/`I64` at a 4-byte word skip the
  mask and count one register), together with the Wide64 question from
  commits 11 and 13; (b) the 128-bit path calls `emitClzWord` and friends
  on 64-bit halves (`parts.high`, `parts.low`): its own `...64` helpers
  until part 10, or a comment plus an 8-byte check; (c) keep `wordOfU128`
  (only called with `index = 0`, for repeating masks) or replace it with a
  byte-repeat helper, unless part 10 needs the splitter.

### Summary of #9's commits (review done 2026-10-29)

- `36825aa1f9` one `Isa` type: shared PR, reworked (switches, no `binaryIs`)
- `200333a587` instruction cache flush: shared PR, with an upstream issue (draft 03)
- `3d73760a5b` glibc stub: part 8
- `8b9b055402` abs64 relocation: another part, decided later
- `a6b1c06b0c` target data by the target's word: shared PR
- `863bcaa8e7`, `bd4c9b9add`, `3ce5cb09f3` erased-callable layout: shared PR, squashed into one
- `1b569dfd0d`, `6cd2d68e6d` wasm on 32-bit hosts: another part, decided later
- `9c6152e666` RocStr and RocList at the word width: shared PR
- `4ca2daf8fa` one-register integer arithmetic: shared PR
- `b7a9abbcc9` low-level pointers: shared PR
- `daf1c616f6` integer conversions: shared PR
- `1bc3981a38` scalar bit counts: shared PR

### What the shared PR needs beyond #9 and parts 2 and 3 (found in the review)

Decided:
- every architecture choice a `switch (isa)`, including `FrameBuilder` and
  `CallingConvention`'s cached flags (commit 1, A and B)
- `ObjectFileCompiler.zig:1165` and `host_lir_codegen_available` ask
  `isa.zig` (commit 1, B)
- `design.md`: the `switch (isa)` rule and the `word` / named-width rule
  (commits 1 and 10)
- a check that rejects a new raw `.w64` in the driver (commit 10)
- the argument register count in words (commit 10)
- the PR links the draft 03 issue (commit 2)

Open:
- the erased-callable layout in the builtins for a given word size
  (commits 4 to 7)
- the Wide64 routing and how wider sources are kept off one-word paths
  (commits 11, 13, 14)
- `src/cli/main.zig:13915` picks the hot-reload capture prefix with its
  own `arch == .x86_64 or arch == .aarch64` list (seen while reviewing
  commit 5): one more architecture list outside `isa.zig`; it is CLI code,
  not the dev backend, so whether the shared PR covers it is open
- a new PR description: #9's describes the glibc stub, abs64 and wasm
  commits, which are no longer in it

### Decided 2026-10-29: open points 11 and 12 (after the overnight review)

Numbering from the overnight report's open-decision list
(`overnight-2026-10-29-report.md`).

- **11. Route `src/cli/main.zig:13915` through `isaOfOrNull`.** It picks the
  hot-reload capture prefix with its own `arch == .x86_64 or arch ==
  .aarch64` list; it asks `isa.zig` instead, so `isa.zig` is the only list of
  the dev backend's architectures. Part of the shared PR's first commit.
- **12. Squash commit 1 with the switch conversion.** The first commit of the
  shared PR adds `Isa`, `isaOf` / `isaOfOrNull` and makes every
  architecture choice a `switch (isa)` directly; `binaryIs` never appears.
- Every other open point waits until the commit it affects (list in the
  report and in chat, 2026-10-29).

### Decided 2026-10-29: how the branch is built, and step 1's details

Base: upstream `main` moved to `0c440e5f31` (221 commits, about 1,000 changed
lines in the dev backend files); `shared-driver/isa-word-size` was
fast-forwarded to it and still has no commits of its own. Last night's oracle
and minici ran on `bad769be8e` and are redone on the new base.

- **Ordering method (b): the history is generated, not hand-merged.**
  Replaying commits 10, 11, 13 and 14 after the switch conversion conflicts
  in 15 hunks; a scripted resolution, checked by comparing trees, had lost
  part of commit 10 and most of commit 13's restructuring at 10 places, and
  no test or oracle can see such a loss (64-bit output is identical either
  way). So: commits 2 to 14 (and later work) are built in their `binaryIs`
  form, and each commit of the real branch is the converter
  (`overnight-2026-10-29/to_switch.py`) plus the scripted hand edits applied
  to the matching tree. Nothing is merged by hand, and decision 12 holds
  (reviewers never see `binaryIs`). The hand edits (about 10) become part
  of the script first. The four wrong rerere entries from the trial were
  deleted.
- **Change 1:** `isaOfOrNull` takes a runtime target (no `comptime` on its
  parameter), so `cli/main.zig`'s `devCapturePrefix` (decision 11) can call
  it; `isaOf` keeps `comptime`.
- **Change 2 (a):** step 1 replaces the unreachable big-endian check in
  `num_from_le_bytes_unchecked` with one assert at the top of `LirCodeGen`
  ("every target is little-endian") whose comment names only that load;
  commit 12 adds its own line to the comment ("a value's low word is at the
  start of its slot").
- **Change 3:** step 1 adds the `design.md` section with only the
  instruction-set paragraph; the word-size paragraph comes with the lint in
  the last step.
- **Change 4 (a):** a note only (README, parts 6 and 9). Step 1 changes no
  behaviour.

### Decided 2026-10-31: step 1's oracle base and review fixes

- **Base:** upstream `main` moved to `10c3438d94` (89 commits); the branch
  was fast-forwarded and step 1 regenerated there (no conflicts; the change
  is identical to the `0c440e5f31` one apart from line positions).
- **A0 refreshed for the new base (option 1).** A0's three-way apply
  conflicts in five files on the new base; rerere's replay had also carried
  an edit outside a conflict hunk (`inspected.zig`). The oracle now applies
  `1f461d76df` (tag `scratch/a0-on-10c3438d94`, local only): A0 with each
  conflict resolved by an explicit rule, no rerere. `A0_DECLS`,
  `A0_FOLLOWS` and `a0-patches` still apply after it.
- **H1:** that commit is made with `git commit-tree -S`, which skips the
  fork-rules hook (A0's `eval.blake3` holds six upstream test names with
  issue numbers). Local only, never pushed.
- **Review fixes:** a one-line comment at `use_swar` and `aarch64_sret`
  ("Not a cached isa test: every arm names that backend's answer."); the
  design.md section is "Dev Backend Instruction Sets" (no "And Word Size").
- **3a, host checks in `LirCodeGen`'s tests, in step 1:** the 41 skip and
  run guards (`builtin.cpu.arch == .x86_64 or ... .aarch64`) use
  `host_lir_codegen_available`; the 2 host-dependent stack offsets switch
  on `isaOf(host_lir_codegen_target)`. The owner put the skip guard of
  "dev stores an I8 result as its own byte" on one line.
- **4a:** every `!host_lir_codegen_available` skip guard in `LirCodeGen`'s
  tests is one line (`if (comptime !host_lir_codegen_available) return
  error.SkipZigTest;`), as the owner's edit.

### Decided 2026-11-01: step 1 upstream on its own, later steps on `isa-word-size`

Partly supersedes 2026-10-28 (the branch name, and parts 1 to 3 as one PR).

- Step 1 went upstream as its own PR: branch `isa-switch`, one commit
  `5cd707b9b8`, fork PR #11, upstream PR 12740 (opened by the owner).
- Steps 2 onward go on a new branch `isa-word-size` (worktree
  `.workspaces/pr-isa-word-size`), cut from upstream `main` at
  `f7bef6b38f`, with step 1 cherry-picked on top (`d0dce2c444`, rerere
  off) so the next steps can build on it. It is rebased onto `main`
  whenever `main` moves; once PR 12740 merges, that rebase drops the
  duplicate step 1 commit.
- `shared-driver/isa-word-size` (`10c3438d94`, no commits) is retired.
