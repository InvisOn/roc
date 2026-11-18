# Part 4: the A32 encoder and its assembler oracle

- **Status:** Draft
- **Scope:** Branch
- **Plan row:** 4, A32/NEON encoder and its assembler oracle
- **Branch:** `arm32/encoder` (worktree `.workspaces/arm32-encoder`)
- **Fork PR:** not yet
- **Parent:** none
- **Base:** `isa-register-seams` (`58646c1c5c`), which sits on
  `isa-word-size` (`896ca8b108`, upstream PR 12983) on upstream
  `37986e9a6a`. The upstream PR is opened only after PR 12983 merges (one
  PR open at a time), and then from upstream `main`.
- **Head:** `58646c1c5c` (no part 4 commits yet)

## Abstract

Part 4 adds an A32 instruction encoder for 32-bit ARM
(`src/backend/dev/arm32/Emit.zig`, `Registers.zig`) and an oracle that
checks it byte for byte against an assembler: a list of assembly lines,
each paired with the `Emit` call that must produce the same bytes, a
script that assembles the list and writes the expected bytes into
generated Zig tests, and a build step that fails when the tests are out of
date or an emitter has no entry. Nothing calls the encoder yet, so x86_64
and aarch64 output cannot change; the relative oracle still runs on each
commit to show it. Eight decisions: how a target would choose Thumb later
(D1, recommended: a new `Isa` member then, no mode now), which assembler
(D2, LLVM's, through `zig cc`), where the expected bytes live (D3,
generated and checked in), the ELF reader the oracle needs (D4, moves
here from part 5), the encoder's `CC` namespace (D5, left to part 6), what
the coverage check counts (D6, every emitting method) and whether NEON
waits for part 11 (D7, yes, except the three vector moves part 6 needs)
and where the oracle's build step runs in CI (D8, in `minici`).

## Problem

The dev backend has encoders for x86_64 and aarch64 only. Every later
arm32 part (code generator, calls, objects, targets) emits A32
instructions, so the encoder comes first. It is also the part that is
easiest to get wrong without noticing: one wrong bit in a register field
or an immediate rotation produces a valid but different instruction, and
nothing fails until a program misbehaves on a device.

Upstream tests its encoders with hand-written expected bytes (63 tests in
`x86_64/Emit.zig`, 13 in `aarch64/Emit.zig` at `37986e9a6a`). For a new
encoder, hand-written bytes risk repeating the author's own mistake in the
test. The reference branch answered that with an assembler oracle: the
expected bytes come from an assembler, not from the person who wrote the
encoder.

Two things go wrong without part 4: the later parts have nothing to emit
with, and the encoder lands without an independent check.

### Breakages you can run

Upstream already names the targets (`arm32linux`, `arm32musl` in
`src/target/mod.zig:464`), but no test platform lists them, so a plain
build stops at the platform header:

    $ roc build --target=arm32musl --opt=dev test/int/app.roc
    ── ✗ unsupported target ──────────────────────────────────────────
    The platform at test/int/platform/main.roc does not support the
    arm32musl target.

With a copy of `test/int` whose platform header adds an `arm32musl` entry
(the same inputs as `arm64musl`), the build reaches the dev backend and
stops there, before it needs any host files:

    $ roc build --target=arm32musl --opt=dev app.roc
    Error: The native object backend does not support the 'arm' architecture.

`isaOfOrNull(.arm32musl)` returns null (`src/backend/dev/isa.zig`), so
nothing asks for an A32 encoding yet. Run 2026-11-19 with a debug `roc`
built from `58646c1c5c`, which matches upstream `37986e9a6a` here. Part 4
does not change this output; part 6 is the first part that does.

What part 4 makes runnable, on the branch once the commits exist:

    cd .workspaces/arm32-encoder
    zig build run-check-arm32-encoding-oracle
    zig build test

The first fails when the generated tests are out of date or an emitter has
no oracle entry; the second runs the generated tests.

## What this enables

- **Follows directly:** part 6 (the arm32 code generator) emits through
  this encoder, and keeps the oracle passing as it adds instructions.
- **Follows directly:** part 5 (objects) gets the ELF reader (D4) already
  in place.
- **Follows directly:** the encoder's coverage check means an emitter
  without an assembler-checked entry cannot land, in part 4 or later.
- **Possible later, not planned:** the same oracle shape for x86_64 and
  aarch64 (LLVM assembles both), replacing hand-written expected bytes.
- **Possible later, not planned:** a Thumb-2 encoder for ARMv7-M (the
  follow-up after part 12) gets its own `Emit` and its own oracle list,
  with the same script.

## Background

- **A32:** the 32-bit ARM instruction set: fixed 4-byte little-endian
  instructions, a condition field on almost every instruction, and
  "modified immediates" (an 8-bit value rotated right by an even amount).
  Reading PC gives the instruction's own address plus 8.
- **Thumb (T32):** ARM's other 32-bit instruction set: 2- and 4-byte
  instructions, PC plus 4, different immediates. ARMv7-A cores run both;
  ARMv7-M cores run only Thumb.
- **Reference:** `claude/arm32-dev-backend-reference`. The plan's sizes
  come from the snapshot `e0fa273ebf`; the branch has one later fix to
  `Emit.zig` (7 lines, in merge `d0846f6eb6`), which part 4 includes.
  Files and sizes in the reference:

  | File | Lines |
  |---|---|
  | `arm32/Emit.zig` | 1,975 |
  | `arm32/Registers.zig` | 254 |
  | `arm32/encoding_oracle_tests.zig` (generated) | 996 |
  | `ci/arm32_encoding_oracle.py` | 247 |
  | `ci/arm32_encoding_oracle.s` | 373 |
  | `ci/elf32_reader.py` (D4) | 248 |

- **The reference encoder:** 165 public functions in `Emit.zig`. Integer,
  branch, memory and stack instructions and helpers outside `Emit`
  (`ModImm.encode`, `Condition.invert`) make up 100, VFP floating point
  43 (`vadd`, `vcmp`, `vcvt`, `vldr`, ...) and NEON vector instructions 22
  (`neonThreeSameQ`, `vld1Q`, `vtbl`, ...), plus the NEON operation enums
  (about 300 lines). It checks at compile time that the target's Zig CPU
  baseline has NEON and lacks hardware divide, and uses `ModImm` so an
  unencodable immediate cannot be passed.
- **The reference oracle:** each line of `arm32_encoding_oracle.s` pairs
  assembly with an `Emit` call (`add r0, r1, r2 | addRegRegReg(.r0, .r1,
  .r2)`). The script assembles the lines with `zig cc -target
  arm-linux-musleabihf`, reads the object with `elf32_reader.py`, and
  writes one Zig test per line. It reads `R_ARM_CALL` relocations because
  LLVM leaves every `bl` for the linker. `--check` fails if the output is
  stale or an emitter has no line.
- **Thumb review** (`thumb-plan-review.md`, 2026-10-27): Thumb left the
  committed plan; how a target would choose it must be recorded here (D1).
- **Register seams** (`../part-02-03-word-size/register-seams.md`): the
  roles each architecture's `CC` supplies are now known (D5).
- **Upstream already uses Python in CI** (`ci/count_aarch64_instructions.py`,
  `ci/test_build_cache.py` and others).

## Discussion

- **Acceptable upstream.** Judged as if a maintainer wrote it: upstream's
  encoder style (`Emit(comptime target)`, one method per instruction form,
  `buf` and `relocs`), current Zig (`@backingInt`, not `@intFromEnum`), no
  reference-branch leftovers (the `DESIGN.md`, `GUIDE.md` and `TOOLS.md`
  files and the `projects/` notes stay out), and the later reference fix
  included.
- **AGENTS.md:** no JSON in the oracle's data; compiler invariants are
  debug assertions and `unreachable`; no workarounds.
- **Output unchanged:** nothing calls the encoder, so x86_64 and aarch64
  output cannot change. The relative oracle runs on every commit anyway.
- **Review size:** the plan's estimate is about 3,800 lines, a quarter of
  it generated (D3). D7 can take about 500 lines out.
- **Plan order:** part 4 cannot depend on parts 5 to 7 (D4, D5).

### Alternatives considered

- **Port the reference's facade, so arm32 code lives behind one
  interface.** Rejected because upstream's driver calls encoders
  directly (thumb review, finding 1), and the facade was dropped in parts
  1 to 3.
- **Hand-written expected bytes, as upstream's encoders have.** Rejected
  because the point of an independent check is that the bytes do not come
  from the encoder's author.
- **Encode Thumb now, beside A32.** Rejected because Thumb is out of the
  committed plan (thumb review); the ARMv7-M follow-up comes after part 12.

## Decisions

### D1. How a target would choose A32 or Thumb, if Thumb ever comes

- **Status:** Proposed
- **Context:** the plan asks part 4 to record this, because it shapes the
  encoder and part 6. Thumb would come with the ARMv7-M follow-up, where
  the cores run only Thumb.
- **Alternatives:**
  1. A new `Isa` member (`.thumb2`) with its own `Emit`, `CodeGen` and
     oracle list. Implications: every exhaustive `switch (isa)` forces an
     answer, as parts 1 to 3 intended; cache keys and relocation patchers
     stay per instruction set; Zig already has a separate `.thumb` CPU
     architecture. Shared A32/Thumb code (registers, VFP) needs a shared
     file.
  2. A mode inside `.arm32` (an encoder parameter). Implications: every
     encoder method, the PC bias, branch ranges, relocation patching and
     the cache key take the mode; nothing forces each site to answer.
  3. A target variant, like upstream's CPU-level twins. Implications:
     twins differ only in instruction selection on one instruction set;
     Thumb is a different encoding, so every byte-writing path would
     branch on the CPU level.
- **Recommendation:** Alternative 1. Part 4 names the encoder A32 only
  and takes no mode parameter.
- **Consequences:** part 6's rule stands: only the arm32 code generator
  writes or patches instruction bytes, or knows the PC bias and branch
  ranges, so a later Thumb code generator changes those in its own file.
  The shared driver's A32-only calls (`ModImm`, conditional moves) are the
  known cost the follow-up pays.

### D2. Which assembler the oracle uses

- **Status:** Proposed
- **Context:** the plan's text says "the GNU assembler"; the reference
  uses LLVM's, through `zig cc`.
- **Alternatives:**
  1. LLVM through `zig cc -target arm-linux-musleabihf`. Implications: no
     tool beyond the Zig that CI already has; LLVM leaves every `bl` as a
     relocation, so the script must read relocations (D4).
  2. GNU `as` (`arm-linux-gnueabihf-as`). Implications: a cross binutils
     package on every machine that runs the check; the CI images would
     need it.
- **Recommendation:** Alternative 1; correct the plan's text.
- **Consequences:** the check runs anywhere Zig runs. Assemblers should
  agree on lines that have only one valid encoding; where a line has
  several, the assembler picks one, and that choice can change between
  versions (R5).

### D3. Where the expected bytes live

- **Status:** Proposed
- **Context:** the assembler must not be needed to run `zig build test`.
- **Alternatives:**
  1. Generated Zig tests, checked in (`encoding_oracle_tests.zig`), and a
     build step that regenerates and compares. Implications: about 1,000
     generated lines in review; `zig build test` needs nothing extra.
  2. Assemble at build time inside a Zig build step. Implications: no
     generated file, but every test run assembles, and the ELF reading
     moves into Zig.
  3. Expected words written next to each line of the `.s` file.
     Implications: smaller, but the words are then hand-maintained again.
- **Recommendation:** Alternative 1, as the reference does.
- **Consequences:** reviewers read the `.s` file and the script, and skim
  the generated file; the PR description says which file is generated.

### D4. The ELF reader the oracle needs

- **Status:** Proposed
- **Context:** the oracle imports `ci/elf32_reader.py`, which the plan
  puts in part 5 (objects), but part 4 lands first.
- **Alternatives:**
  1. Move `elf32_reader.py` into part 4; part 5 reuses it. Implications:
     about 250 more lines here, 250 fewer in part 5.
  2. Use `zig objcopy -O binary` for the bytes and drop relocation reading.
     Implications: the `bl` entries lose their check, because their
     offset field is left for the linker.
- **Recommendation:** Alternative 1.
- **Consequences:** part 5's row in the plan shrinks by about 250 lines.

### D5. The encoder's `CC` namespace

- **Status:** Proposed
- **Context:** the reference `Emit` has a `CC` namespace that reads
  `Call.zig` (part 7). The register seams now fix what `CC` must supply.
- **Alternatives:**
  1. No `CC` in part 4; part 6 adds it, with every role the seams named
     (`BASE_PTR`, `STACK_PTR`, `SCRATCH_REG`, `ROC_RET_REGS`,
     `RESULT_PTR_SAVE_REG`, ...). Implications: part 4 does not depend on
     part 7.
  2. Bring `CC` and the register lists from `Call.zig` now. Implications:
     calling-convention choices land before the calling convention's PR.
- **Recommendation:** Alternative 1.
- **Consequences:** part 4's `Emit` is only an encoder; part 6's planning
  doc lists arm32's answer for each role.

### D6. What the coverage check counts

- **Status:** Proposed
- **Context:** the plan says "every instruction form the code generator
  can emit". The reference checks every public emitting method of `Emit`.
- **Alternatives:**
  1. Every public `Emit` method that emits bytes needs at least one
     oracle line. Implications: mechanical, read from `Emit.zig`; a method
     with several forms (a register or an immediate operand) can still
     pass with one line.
  2. Every form the code generator uses, found from the code generator.
     Implications: needs part 6's code, so it cannot exist in part 4.
- **Recommendation:** Alternative 1, with one oracle line per operand
  form where a method takes a union or enum form argument (`Operand2`,
  `MemForm`).
- **Consequences:** part 4 can enforce it from the first commit.

### D7. Whether NEON waits for part 11

- **Status:** Proposed
- **Context:** the reference encoder includes 22 NEON emitters and about
  300 lines of NEON enums. Most are used only by the shared driver's SIMD
  lowering (part 11). Three are used by the reference's `arm32/CodeGen.zig`
  outside SIMD: `vld1Q`, `vst1Q` and `neonLogicQ(.vorr, ...)`, for the
  128-bit vector-register load, store and move that upstream's driver asks
  of every code generator (`emitLoadStackV128`, `emitStoreStackV128`,
  `emitMoveV128`; the driver spills vector locals through them). VFP
  floating point is needed by part 6.
- **Alternatives:**
  1. Part 4 brings integer, branch, memory, stack, VFP and the three
     vector moves (with the Q registers); the rest of NEON comes with part
     11. Implications: about 500 fewer lines here (emitters, enums, oracle
     lines, generated tests); no code without a user for seven parts.
  2. Everything now, as the plan's title says. Implications: the encoder
     is complete in one review.
- **Recommendation:** Alternative 1.
- **Consequences:** the plan's row 4 becomes "A32/VFP encoder"; part 11
  grows by the rest of the NEON encoder and its oracle lines.
  `neonLogicQ` comes in reduced to `vorr` (a register move), or as a
  dedicated `vmovQ`; to decide when writing the commit.

### D8. Where the oracle's build step runs in CI

- **Status:** Accepted (2026-11-19)
- **Context:** `run-check-arm32-encoding-oracle` must run in upstream CI,
  or a stale generated file or an emitter without a line can land.
- **Alternatives:**
  1. Inside `minici`, next to the other `run-check-*` steps.
     Implications: runs in seconds; follows upstream's pattern; no new
     workflow job.
  2. Its own CI job. Implications: a separate status line, but one more
     job to maintain for a check of a few seconds.
- **Recommendation:** Alternative 1.
- **Consequences:** the oracle commit adds the step to `minici`; the
  machines that run `minici` need only Zig and Python 3, which they
  already have.

## Risks

### R1. The assembler and the encoder agree on a wrong encoding

- **Likelihood:** Low
- **Impact:** Medium
- **How we'd notice:** part 6's programs on hardware or qemu; the relative
  oracle does not cover arm32.
- **Mitigation:** both LLVM and the encoder follow the ARM architecture
  manual; a hand check of a few encodings against the manual in review.
- **If it happens:** fix the oracle line and the encoder together.

### R2. An oracle line checks less than it seems

- **Likelihood:** Medium
- **Impact:** Medium
- **How we'd notice:** review of the `.s` file; a later bug in a form the
  line did not use.
- **Mitigation:** D6's one line per operand form; registers chosen so
  every field differs (`r1`, `r2`, `r12`, not `r0` everywhere).
- **If it happens:** add the missing line.

### R3. Review size

- **Likelihood:** Medium
- **Impact:** Medium
- **How we'd notice:** maintainer feedback.
- **Mitigation:** D7; generated file named in the PR description; commits
  split by instruction family.
- **If it happens:** split the PR by instruction family.

### R4. Upstream moves its encoder style before part 4 opens

- **Likelihood:** Medium (upstream changed `x86_64/Emit.zig` on
  2026-11-16 in `db11f76a97`: shortest encodings)
- **Impact:** Low
- **How we'd notice:** rebase onto `main` before the PR opens.
- **Mitigation:** follow upstream's style at that time.
- **If it happens:** adjust in a fixup before opening.

### R5. A Zig upgrade changes the assembler's output

- **Likelihood:** Low
- **Impact:** Medium
- **How we'd notice:** `run-check-arm32-encoding-oracle` fails after a
  Zig upgrade although `Emit.zig` did not change.
- **Mitigation:** oracle lines written so only one valid encoding exists
  (for example immediates that fit only one rotation, and no pseudo
  instructions such as `ldr r0, =value`, which the assembler expands as
  it likes).
- **If it happens:** regenerate, read the diff, and fix the line or the
  encoder; never regenerate without reading.

## Testing

From `.workspaces/arm32-encoder`, on each commit:

    zig build run-check-arm32-encoding-oracle
    zig build test

Expected: the check prints nothing and exits 0; the generated tests pass.

Test wiring, on each commit:

    zig build run-check-test-wiring

Expected: passes. `arm32/mod.zig` imports `encoding_oracle_tests.zig` in
its test block, and `dev/mod.zig` imports `arm32/mod.zig`, so the
generated tests are in a test binary.

Output unchanged for x86_64 and aarch64, on each commit:

    python3 .workspaces/notes/incremental-plan/tools/relative_oracle.py \
      --upstream <base> --merged <commit> --apply-a0-to-merged

Expected: `relative 64-bit oracle: PASS`.

Also `zig build run-check-zig-lints` and `zig fmt --check` on the new
files. Upstream CI runs the new build step through `minici` (D8).

## Recommendation

D1 alternative 1, D2 1, D3 1, D4 1, D5 1, D6 1, D7 1, D8 1. Commits, each
building and passing on its own:

1. `Registers.zig`: general, S, D and Q registers; `arm32/mod.zig`
   (`Emit`, `Registers`) and its import in `dev/mod.zig`, so
   `run-check-test-wiring` sees the arm32 tests from the start.
2. `Emit.zig` core: `Emit(target)`, buffer and relocations, conditions,
   `ModImm`, `Operand2`, data processing, moves and immediates.
3. Multiply, bit operations, extends and bitfield instructions.
4. Branches, calls and PC-relative addresses (with relocations).
5. Loads, stores, `push` and `pop`.
6. VFP: arithmetic, compares, conversions, moves, loads and stores, and
   the three 128-bit vector moves (D7).
7. The oracle: `ci/elf32_reader.py`, `ci/arm32_encoding_oracle.py`, the
   `.s` file, the generated tests (imported from `arm32/mod.zig`'s test
   block), the build step and its `minici` entry (D8). (Or bring the
   oracle first and grow its `.s` file with each family; to decide when
   writing the commits.)
