# Overnight review and experiments, 2026-10-29

Written for the morning; finished at 03:35. Nothing was committed to your branches, pushed, or
filed. All experiments are on a local scratch branch,
`exp/shared-driver-overnight` (worktree `.workspaces/exp-shared`), cut from
upstream `main` `bad769be8e`. The plan doc records no new decisions: every
open question below is still yours.

## Short version

- **The commits you put in the shared PR (#9's commits 1, 2, 4 to 7 and 10
  to 14; 11 commits, since 5, 6 and 7 are not squashed yet) replay onto
  today's `main` with no conflicts**,
  and each one builds and passes on its own there (backend tests and a full
  `roc` build at every commit). Upstream has not touched `src/backend/dev`
  since #9's base: 57 commits, none there.
- **Decision A (switches instead of `binaryIs`) works.** A script converted
  all 223 `binaryIs` sites and the 36 cached flags. The compiler builds,
  every test passes, and x86_64 and aarch64 output is byte-for-byte
  unchanged (relative oracle: 0 of 2,373 eval cases differ, 0 snapshot
  lines). Size: about 1,700 changed lines ignoring whitespace, 6,400 with
  re-indentation, against 530 for `binaryIs`.
- **Your "fix" decisions are prototyped and pass:** `isa.zig` as the only
  architecture list (1B), the test over every target and `design.md` (1C),
  and multi-register arguments counted in words (10).
- **Three open questions now have working prototypes:** the erased-callable
  layout in the builtins (commits 4 to 7), the Wide64 routing (11, 13, 14),
  and the `.w64` lint (10).
- **The `.w64` lint as decided would be wrong.** 220 of the 602 bare `.w64`
  in the driver are direct calls into one CPU's encoder, where `.w64` is that
  CPU's register width and correct. The rule that works: no bare `.w64`
  passed to an architecture-neutral helper. Under it, 354 sites are left on
  the final head (365 before my fixes), all in `LirCodeGen.zig`.
- **One new gap in commit 13:** `signExtendGeneral` (a SIMD lane moved to a
  general register) still sign-extended at 64 bits; fixed in experiment 8. The to-Dec, 128-bit and
  `..._try` conversions use 64 bits on purpose (64-bit halves, or a C
  builtin with `i64` parameters); they become named widths in part 3, and
  the lint flags them so none is forgotten.
- **Verified:** relative oracle three times (0 differences), the PR's usual
  check set, the snapshot check (which also covers Windows and macOS
  targets), and a full `zig build minici` (98 of 98).

## What was run

All on this machine (x86_64 laptop), times are wall clock.

- Replay of the 11 commits onto `bad769be8e`: clean.
- Each replayed commit alone: backend tests and `zig build roc`, 84 to 165 s
  each, all pass (521 to 523 tests; commit 2 adds one, skipped on x86_64).
- Experiment head after each step: backend tests and `zig build roc`, pass.
- Relative oracle, `main` against experiment head `8b3a3d4d2e` (switches,
  `isa.zig`, layout, routing, lint): **PASS**, 28.2 min.
- Relative oracle, `main` against the final head `b52c722729` (adds
  multi-register arguments in words and the `CC` registers): **PASS**,
  18.1 min (upstream side reused).
- The PR's usual check set on the final head (format, unreachable reasons,
  builtins, backend, `roc`, check, compile, eval, LIR inline, snapshot tool,
  snapshots): **pass**, 8.4 min. The compile tests print "Roc cache writes
  are failing"; unchanged `main` prints the same (one of upstream's tests),
  1001 of 1001 pass on both.
- `zig build minici` on the experiment head without the lint (the lint
  fails by design until part 3 is done): **98 of 98 phases pass**, 1 h 53 min
  (cold cache: `build-ci` alone 33 min). Commit `cfbe459736`, which is
  `b52c722729` with the lint reverted; the four small experiment commits after it
  (experiments 8 and 9 below) are covered by oracle 3 and the tests.
- Relative oracle on the final head `12fc51ce78` (everything): **PASS**,
  17.2 min; 0 eval cases and 0 snapshot lines differ.
- Windows and macOS: the oracle compares Linux targets only, but my
  switch conversion also touched Windows- and macOS-only branches (for
  example the Windows float-argument rule). The `dev_object` snapshots record
  an object hash per target, `x64win`, `x64mac`, `arm64win` and `arm64mac`
  included (11 programs, `float_math` among them); no snapshot file changed
  and `run-check-snapshots` passes, so those targets' bytes are unchanged
  too.

Timings are in `.workspaces/timings/timings.csv` (rows dated 2026-10-29).

## The experiments, one by one

Each is a commit on `exp/shared-driver-overnight`. "Byte-identical" means
covered by the oracle.

### 1. Exhaustive switches instead of `binaryIs` (decision A) — done

- **How:** a script (`overnight-2026-10-29/to_switch.py`, next to this
  report) rewrote `if (isa.binaryIs(.X)) A else B` and the
  `is_x86_64` / `is_aarch64` flags into `switch (isa) { .x86_64 => ..,
  .aarch64 => .. }`, flattened `else if` chains, and turned the few
  combined conditions into bool-valued switches; eight of those were then
  rewritten by hand into their natural form (for example
  `uses_position_based_float_args = switch (isa) { .x86_64 => is_windows,
  .aarch64 => false }`). `binaryIs` is deleted.
- **Checked:** Zig 0.17 skips the other backend's arm of a switch on a
  compile-time `isa`, in expression, statement and bool form (tested
  separately). A third `Isa` member gives "switch must handle all
  possibilities" at each switch, one function at a time, as `binaryIs` would.
  The two small Zig files that show this are in `overnight-2026-10-29/`.
- **Result:** builds, tests pass, byte-identical.
- **Size:** +3,536/−2,877 for the conversion and polish; with whitespace
  ignored +1,185/−526. zig fmt puts every switch arm on its own line, so a
  one-line register pick becomes four lines; `LirCodeGen.zig` grows by about
  660 lines. GitHub's "hide whitespace" view shows the 1,700-line version.
- **For review:** the converted code reads well (both answers at each site).
  Suggest the PR squash commit 1 and the conversion, so reviewers never see
  `binaryIs`.

### 2. `isa.zig` as the only list (decision 1B) — done

- `isaOfOrNull(target)` added; `ObjectFileCompiler.zig` and
  `host_lir_codegen_available` use it instead of their own lists (both had
  accepted `aarch64_be`, which `isaOf` rejects).
- `isaOf`'s compile error names the target.
- The unreachable big-endian check in `num_from_le_bytes_unchecked` is
  replaced by one compile-time assert at the top of `LirCodeGen` that every
  target is little-endian, with a comment naming the two places that rely on
  it (that load, and "low word at the start of the slot", commit 12).
- `aarch64/CodeGen.zig` and `aarch64/Emit.zig` reject `aarch64_be`.
- New test: `isaOfOrNull` checked against every `RocTarget`, using the
  target names (`x64...`, `arm64...`) as the independent record. My first
  version restated the function's own switch and could not fail; replaced.
- Result: builds, tests pass, byte-identical.

### 3. Erased-callable layout in the builtins (open, commits 4 to 7)

- `builtins.erased_callable.TargetLayout.of(ptr_size)` returns every offset
  and size the backends need (`on_drop_offset`, `capture_offset`, the
  hot-reload header offsets, `result_desc_offset`, metadata size and
  alignment, and `compilerMetadataOffset` / `payloadSize` /
  `compilerPayloadSize`). A compile-time block checks that
  `TargetLayout.of(@sizeOf(usize))` equals the builtins' own constants, and
  a test checks both 4- and 8-byte values.
- `LirCodeGen`'s private `erased_layout` struct becomes one line,
  `TargetLayout.of(target_ptr_size)`, and commit 4's drop-pointer store uses
  `on_drop_offset` (your fix for commit 4's finding 3).
- Size: +124/−45. Builds, tests pass, byte-identical.
- **Worth knowing:** at a 4-byte word the metadata offset differs from the
  host's for small captures (4 vs 8 for a 4-byte capture), which the test
  pins. The LLVM and wasm backends (draft 38) still use the host constants
  at 7 sites each; with this in place, switching them is a one-line change
  per site, but it is not done here.
- **Recommendation:** take it (option 1 of the open question).

### 4. Wide64 routing (open, commits 11, 13, 14)

- Two pure functions next to `intOverflowCheck`: `intNeedsWide64(bits,
  word_bits)` and `conversionNeedsWide64(spec, word_bits)`, tested at 32 and
  64 bits.
- Routing at three places: the top of `generateLowLevel` (every numeric
  conversion), the top of `generateIntBinop`, and `generateBitCountScalar`.
  They call three stubs (`generateWide64IntBinop`, `...IntUnary`,
  `...IntConversion`) whose body is a compile error.
- On an 8-byte word the checks are compile-time false and the stubs are
  never compiled (the full `roc` build proves it). On a 4-byte word the
  first reached stub stops the build with "64-bit integer ... needs the
  register-pair lowering" (tested in a standalone file).
- Size: +59. Builds, tests pass, byte-identical.
- **What it settles:** the asserts and "never reaches this path" comments in
  commits 11, 13 and 14 become true by construction.
- **Consequence for part 6:** when part 6 lifts the 8-byte assert, these
  stubs stop the arm32 build until part 10 implements them. Part 6 then has
  to either implement them, or turn them into an explicit "64-bit integers
  are not supported on this target yet" error. That is a decision for
  part 6's planning; the routing itself is right for this PR either way.
- **Recommendation:** take it.

### 5. The `.w64` lint (decided: "yes, with check")

- Added as lint "6b" in `ci/zig_lints.zig`, upstream's existing lint
  program, with a unit test.
- **First version (any bare `.w64` in the driver): wrong.** It found 602,
  and about 220 of them are direct calls into one CPU's encoder inside that
  CPU's switch arm or helper (`emit.sbcRegRegReg(.w64, ...)`), where `.w64`
  is that CPU's own register width.
- **Second version (bare `.w64` passed to an architecture-neutral helper,
  that is a call named `emit` + capital letter, such as `self.emitStore` or
  `self.codegen.emitCmp`, plus any `isa ==` / `isa !=`):** 365 sites, all in
  `LirCodeGen.zig`; `FrameBuilder` and `CallingConvention` have none. The
  rule is structural (it reads the callee's name), not a guess.
- The lint fails today by design; it passes only once part 3's
  classification is done, so in the PR it lands as the last commit. On the
  final head it reports 354 (experiments 6 and 9 removed 11). Every flagged
  callee is a genuine shared helper (`emitStore` 75, `emitLoad` 68,
  `emitStoreStack` 56, `emitLoadStack` 47, `emitShiftImm` 33, ...); no
  instruction-set-specific helper (`emitX86...`, `emitNeon...`) is flagged.
- **Suggest** recording the narrower rule with your decision.

### 6. Multi-register arguments in words (decided fix for commit 10) — done

- The register count (`aggregateArgRegisterPressure`) and every place that
  loads, stores, spills or copies a value one register at a time now use
  `word` and `target_ptr_size`: the call setup, erased calls,
  `spillArgToStack`, `copyFromCallerStack`, `freezeCallArg` and parameter
  receiving.
- The special three-register case became the general path: it differed
  only in width, and `emitLoadStack` emits the same instruction as
  `emitLoad(frame_ptr, ...)` on both CPUs.
- **Not changed, on purpose:** the stack-argument slot size
  (`stack_arg_offset += num_regs * 8`) is the calling convention's choice
  (part 7: AAPCS32 packs by 4), and 128-bit integers still count as two
  registers (part 10: four words on a 4-byte target).
- Size: +23/−28. Result: builds, tests pass, byte-identical (oracle 2).

### 7. Register facts from the code generator (part 2 "register seams")

- `frame_ptr`, `stack_ptr`, `scratch_reg` and `call_stack_alignment` now read
  the code generator's existing `EmitType.CC` constants (`BASE_PTR`,
  `STACK_PTR`, `SCRATCH_REG`, `STACK_ALIGNMENT`); four switches gone, no new
  code in the code generators.
- Ten more switches only pick a register (return registers, tail-call
  registers, the stack-argument base). Moving them needs new `CC` members
  in both code generators: that is part 2 proper.
- Result: builds, tests pass, byte-identical (oracle 2).

### 8. `signExtendGeneral` to the word — done

The one real gap left by commit 13 (a SIMD lane moved to a general
register): it now sign-extends to `word_bits` at `word`, with a Debug assert
that the lane is narrower than the word. +5/−3.

### 9. Self-review fixes to the experiments

- The routing checks are wrapped in `if (comptime word_bits < 64)`, so an
  8-byte build does not even look up the conversion table (before, it relied
  on the optimizer dropping a dead lookup).
- In `CallingConvention.zig` my hand edit had reused
  `uses_position_based_float_args` for the R12 save condition: the same value
  (x86_64 on Windows), but a misleading name. Now an explicit switch.
- The tautological `isaOfOrNull` test (see 2) replaced.

### 10. `design.md` section (decision 1C and 10) — done

New section "Dev Backend Instruction Sets And Word Size", right before
"Dev Backend Register Lifetimes": the `switch (isa)` rule, `isaOfOrNull`,
`word` / named widths, the routing, and the lint. About 25 lines.

### Not done, and why

- **One helper for the in-bounds index (open, commit 12).** It cannot keep
  today's bytes: two sites load the index straight into the address register,
  two go through `ensureInGeneralReg` plus a move. A shared helper changes
  the instruction sequence at two sites, which breaks the "64-bit output
  unchanged" rule unless the PR says so. Options: a helper that only holds
  the comment and the little-endian assert (callers keep their shape), or
  accept the byte change and say so in the PR.

## A possible commit order for the shared PR

Drawn from the decisions so far and what the night showed. Each step builds
and passes alone, and keeps x86_64 and aarch64 output unchanged. A proposal,
not a decision.

1. `Isa`, `isaOf` / `isaOfOrNull`, every choice a `switch (isa)` (commit 1
   reworked, squashed with the conversion), the little-endian assert,
   aarch64 guards. `design.md`'s instruction-set paragraph.
2. Instruction cache flush (commit 2, message leads with aarch64).
3. Target data sized by the target's word (commit 4).
4. Erased-callable layout (commits 5, 6, 7 squashed; with `TargetLayout` if
   you choose the builtins).
5. `word`, `word_bits: u8` and the names, plus strings and lists at the word
   width (commit 10).
6. Multi-register arguments in words (your fix for commit 10).
7. Wide64 routing to stubs (if you choose it), before 11, 13 and 14 so their
   asserts are backed.
8. Integer arithmetic (11), low-level pointers (12), conversions (13), bit
   counts (14).
9. Register facts from the code generator's `CC` (part 2 seams), then the
   new `CC` members for the other ten registers.
10. Part 3: the remaining 354 sites (grouped before my fixes: about 154
    general, 113 in calls, returns and erased calls, 59 in 128-bit and Dec
    code, 38 in SIMD), plus `signExtendGeneral`.
11. The lint, and `design.md`'s word-size paragraph, last (it passes only
    when step 10 is done).

## New findings from rounds 2 and 3

1. **`generateIntTryConversion` (the `..._try` conversions) is not a
   word-size bug, on a closer look.** It extends the source to 64 bits and
   passes it, with `i64` bounds, to a C builtin (`wrapIntTrySigned` /
   `wrapIntTryUnsigned`) whose parameters are `i64`. So 64 bits is right on
   every target; it becomes a named 64-bit width in part 3, and on a 4-byte
   word the `i64` arguments are register pairs (part 7's calling convention,
   part 10). I first read it as a gap in commit 13; it is not.
2. **`signExtendGeneral`** (SIMD lane extracted to a general register)
   shifted by `64 - n` at `.w64`; the one real gap in commit 13. Fixed in
   experiment 8.
3. **To-Dec and 128-bit-to-narrow conversions** still use `64 - n`; they
   work on a 64-bit half, so they become named 64-bit widths in part 3. The
   lint flags all of them.
4. **Commit 2's error lists are fine.** All 10 placements of
   `FlushInstructionCacheFailed` sit with `MprotectFailed` and `MmapFailed`
   and get the same handling (the CLI prints the error name, the REPL counts
   it as operational, the snapshot tool as not a type-check error). Nothing
   to change.
5. **Naming data for the open question on commit 10:** upstream already
   calls the same value `target_word_size` in `CallingConvention.zig:110`
   and `target_ptr_size` in `LirCodeGen.zig`. Renaming to `target_word_size`
   would match upstream's own other name; it touches 57 sites
   (`target_ptr_size`) in `LirCodeGen`, `word` (389) and `word_bits` (70)
   could stay.
6. **No other host-word problems in the dev backend.** The remaining
   `@sizeOf(usize)` uses are on the in-memory path (`StaticDataImage`,
   `RunImage`, `HostSplice`), where the compiler's machine is the target,
   plus `Relocation.zig` (commit 3, parked).
7. **Commit messages on the new base:** nothing stale except what is
   already decided (commit 1's message changes with the switch rework,
   commit 2's leads with aarch64).

## Open decisions, with what the night showed

- **Erased-callable layout location (4 to 7):** prototype works, +124/−45,
  tested at both widths. Recommend: builtins (`TargetLayout.of`).
- **Wide64 routing (11, 13, 14):** prototype works, +59, invisible on 64-bit
  targets. Recommend: take it; part 6 decides what the stubs become.
- **Signedness source (11):** not tried tonight; recommend the layout's
  `shape.signed` everywhere plus a Debug check against `is_unsigned`.
- **Index helper (12):** recommend the comment-and-assert helper, keeping
  bytes.
- **Conversion choice function vs asserts (13):** the routing (above) makes
  this mostly moot; recommend the routing plus the existing `if`s.
- **`word_bits: u8` in commit 10 (13):** recommend yes (one definition).
- **128-bit bit-count helpers and `wordOfU128` (14):** not tried tonight.
- **Names `target_ptr_size` / `word` / `word_bits` (10):** recommend
  `target_word_size` for the byte count (matches upstream's
  `CallingConvention`), keep `word` and `word_bits`.
- **New: the lint's rule** (experiment 5): recommend the narrower rule.
- **New: `signExtendGeneral`:** part of the shared PR's part 3 work.
- **`cli/main.zig:13915` arch list:** still open.

## Where things are

- `exp/shared-driver-overnight` (worktree `.workspaces/exp-shared`): the
  11 replayed commits plus 12 "EXP:" commits, local only, unsigned. Throwaway:
  it shows what works, it is not the branch to file.
- `.workspaces/exp-percommit`: detached worktree used for the per-commit
  builds and minici (at `cfbe459736`, the head without the lint). Safe to
  remove.
- `shared-driver/isa-word-size`: untouched, still at `bad769be8e`.
- `main` did not move overnight (last checked 03:20), so no rebase was needed.
