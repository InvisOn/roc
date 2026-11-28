# Part 6: the arm32 code generator, frames and register roles

- **Status:** Done
- **Scope:** Branch
- **Plan row:** 6, arm32 code generator, frames, register roles
- **Branch:** `arm32/codegen` (worktree `.workspaces/arm32-codegen`, local)
- **Fork PR:** not yet
- **Parent:** none
- **Base:** `arm32/elf32-objects` (part 5, `68231fc7ed`), on `arm32/encoder`
  (`6244fffad0`), on PR 12983 (`7a684b27af`), on upstream `f79ae91d2f`
- **Head:** `8fdc7c8868` (seven commits; see "Outcome")

## Abstract

Part 6 adds `arm32/CodeGen.zig`: the per-instruction-set code generator
that the shared driver calls for register allocation, stack slots,
prologues and epilogues, and every instruction the driver asks for by
name (`emitAdd`, `emitLoadStack`, `emitCondJump`, ...). It also adds the
arm32 register roles (`CC`) that the driver reads since PR 12983, and the
arm32 frame layout. Q-5 (2026-11-28) settled that part 6 does not build
whole programs: the driver's 64-bit places are compile errors on a 4-byte
word until part 10 adds register pairs, so part 6 is tested by unit tests
on the bytes the code generator writes. Six decisions: how arm32 joins
`Isa` and `Abi` (D1, recommended: in part 6, with every driver arm a
compile error until part 10 fills it), which `CC` roles part 6 answers
(D2), the frame layout (D3), what moves from part 7 into part 6 (D4), how
the byte tests state what they expect (D5) and part 4's encoder signature
(D6). x86_64 and aarch64 output must not change; the relative oracle runs
on each commit.

## Problem

Parts 4 and 5 can encode A32 instructions and write arm32 objects, but
nothing chooses instructions. The shared driver (`LirCodeGen`) does not
emit instructions itself: it calls a per-instruction-set `CodeGen` with a
fixed set of methods (about 110 on the reference's arm32 `CodeGen`, the
same names as x86_64 and aarch64). Until arm32 has one, part 7 (the AAPCS32
calling convention) has no register allocator or frame to build on, and
part 10 has nothing to lower register pairs into.

Since PR 12983 the driver also reads its role registers (frame pointer,
scratch register, the result-pointer and RocOps save registers, the Roc
return registers, ...) from each instruction set's `Emit(abi).CC`. Part 4
left arm32's `CC` to part 6 (part 4's D5).

Upstream changed shape on 2026-11-26 (`568382372d`): the code generator
family is now instantiated per `isa.Abi` (instruction set plus calling
convention), not per `RocTarget`. An arm32 code generator that fits
upstream takes an `Abi`, and an `Abi` maps to an `Isa`, so arm32 has to
join both enums at some point. Every exhaustive `switch (isa)` then needs
an arm32 arm: about 206 in `LirCodeGen.zig`, 15 in `CallingConvention.zig`
and 9 in `FrameBuilder.zig` on `7a684b27af`. When that happens, and what
those arms say until part 10, is the main question here (D1).

### Breakages you can run

Nothing can be run yet: part 6 brings new code, not a fix. What can be
shown is why the driver cannot be part 6's test bed. On a 4-byte word
(`Abi.ptrBitWidth() == 32`), `widths.wide64_width` and
`widths.scalar_width` are compile errors (`src/backend/dev/widths.zig`),
and the driver uses them about 470 times (280 `wide64_width`, 147
`scalar_width`, 43 `scalar_bits` on `215b478e6f`). Instantiating
`LirCodeGen` for arm32 stops at the first one it analyzes:

    error: a 64-bit value needs a register pair on a 4-byte-word ABI

That is by design (PR 12983), and it is why the 8-byte assert stays until
part 10 (Q-5).

## What this enables

- **Follows directly:** part 7 builds the AAPCS32 `CallBuilder` (register
  pairs for 64-bit arguments, rule C.5, VFP back-filling) on part 6's
  registers and frames.
- **Follows directly:** part 10 replaces each driver arm32 compile error
  with real code, family by family, and lifts the 8-byte assert; each of
  its PRs can then be tested end to end.
- **Follows directly:** the rule from part 4's D1 holds: only the arm32
  code generator writes or patches instruction bytes, or knows the PC
  offset and branch ranges, so a later Thumb code generator changes those
  in its own file.
- **Possible later, not planned:** other 32-bit instruction sets (RISC-V
  32, Cortex-M Thumb-2) follow the same path: an `Abi` member, a
  `CodeGen`, and driver arms.

## Background

- **The reference:** `e0fa273ebf` on `32-bit-backend`.
  `arm32/CodeGen.zig` (1,182 lines, 12 tests), `arm32/Call.zig` (160),
  `arm32/Emit.zig`'s `CC` namespace, and the arm32 parts of
  `FrameBuilder.zig` (+233) and `CallingConvention.zig` (+502). It was
  written against a driver parameterized by `RocTarget` and before
  upstream's `RegisterPool` and `DeferredFrameBuilder`.
- **Register plan (reference D5, D10):** general temporaries r0-r3 first,
  then callee-saved r4-r8 (r9 and r10 hold the result and RocOps
  pointers); r11 is the frame pointer, r12 the scratch register, r13 the
  stack pointer, r14 the link register. Float temporaries are the even D
  registers d0, d2, d4, d6, each also a Q register with S views, so one
  allocated register holds an f32, an f64 or a 128-bit vector; q8-q15 are
  vector-only. No spill path: the whole pool is the budget.
- **Out-of-range offsets:** an access whose offset does not fit its form
  forms the address in LR first. Every procedure saves LR in its prologue
  and returns by popping PC, so LR is free inside a body, and r12 stays
  usable as a base or data register.
- **Division:** ARMv7-A without the divide extension calls `__aeabi_*`
  helpers. The driver models those as calls, so they are not part 6's.
- **Upstream today (`f79ae91d2f`):** x86_64 and aarch64 `CodeGen(abi)`
  share `RegisterPool.Methods` for allocation and code-buffer accessors,
  and `FrameBuilder.DeferredFrameBuilder(EmitType)` for prologues, with an
  `Isa` switch choosing each instruction set's callee-saved layout.
- **Earlier decisions:** part 4's D1 (Thumb would be a new `Isa` member),
  D5 (`CC` left to part 6); Q-5 (part 6 tested on bytes, part 10 moves up
  and lifts the assert); the register seams in PR 12983 (the roles `CC`
  must answer).

## Discussion

1. **Acceptable upstream.** Judged as if a maintainer wrote it: upstream's
   current signatures (`CodeGen(abi)`, `Emit(abi)`), its shared pieces
   (`RegisterPool`, `DeferredFrameBuilder`) rather than arm32 copies, each
   commit building on its own, no reference leftovers (`general_high_water`
   is a diagnostic, not ported), and every later reference fix included.
2. **AGENTS.md.** No workarounds or fallbacks. A compile error where code
   is not written yet is not a fallback: it fails the build, never the
   user's program, which is how PR 12983 already marks the 64-bit places.
3. **Output unchanged** for x86_64 and aarch64, shown by the relative
   oracle on every commit.
4. **Review size.** The reference's code generator, roles and frames come
   to about 1,600 lines; with tests and the driver arms (D1) part 6 is
   estimated at 2,300 to 2,700.
5. **Plan order** (Q-5): 6, 7, 10, 8, 9, 11, 12.

### Alternatives considered

- **Port the reference's `CodeGen(target)` unchanged.** Rejected because
  upstream now instantiates per `Abi`, and the reference predates
  `RegisterPool` and `DeferredFrameBuilder` (constraint 1).
- **Test part 6 through the driver.** Rejected because the driver does not
  compile for a 4-byte word before part 10 (Q-5).

## Decisions

### D1. How arm32 joins `Isa` and `Abi`

- **Status:** Accepted (2026-11-28)
- **Context:** `CodeGen(abi)`, `Emit(abi)`, `DeferredFrameBuilder` and
  `CallBuilder` all key on `Abi`, and `Abi.isa()` maps to `Isa`. Adding
  `.arm32` to `Isa` forces an arm in about 230 exhaustive switches, most
  in the driver, which cannot run arm32 code before part 10.
- **Alternatives:**
  1. **`Isa.arm32` and `Abi.arm32_aapcs_vfp` in part 6, every driver arm a
     compile error until part 10.** Each arm reads like
     `.arm32 => @compileError("arm32: <operation> needs part 10")`, with
     the operation named. Implications: about 230 one-line arms (roughly
     300 lines with wrapping); `CodeGen`, `Emit`, frames and `CC` take
     upstream's signatures and use `DeferredFrameBuilder` and
     `RegisterPool` now; part 10's PRs each replace a family of compile
     errors with code and tests. This is the same tool PR 12983 uses for
     the 64-bit places.
  2. **The same members in part 6, with real arm32 code in every driver
     arm.** Implications: about 230 arms of code that nothing compiles
     until part 10 (Zig analyzes only the taken arm of a switch on a
     comptime value), so it is untested and may not even type-check;
     part 6 grows by the reference's driver changes (several thousand
     lines).
  3. **Both members in part 10.** Part 6's `CodeGen` is a plain struct
     for the one arm32 ABI, writes its own prologue and epilogue, and
     part 10 turns it into `CodeGen(abi)` and moves the frame code into
     `DeferredFrameBuilder`. Implications: no placeholder arms in part 6;
     but part 6 does not use upstream's shared frame code or signatures,
     and part 10 rewrites part 6's frame code and signatures, on top of
     the 230 arms.
- **Recommendation:** Alternative 1.
- **Consequences:** part 6 fits upstream's shape from its first commit.
  The compile errors list, in the code, exactly what part 10 still owes,
  and the build proves none is reached. A reviewer sees about 230 small
  arms in the driver diff; the commit that adds them does nothing else.

### D2. Which `CC` roles part 6 answers

- **Status:** Accepted (2026-11-28)
- **Context:** the driver reads these roles from `Emit(abi).CC` since PR
  12983. Part 4 left them to part 6 (its D5). Part 7 owns how arguments
  are assigned to registers.
- **Alternatives:**
  1. **Every role the driver reads, in part 6, from an `arm32/Call.zig`
     that holds only register lists and roles.** Roles and the
     reference's answers: `BASE_PTR` r11, `STACK_PTR` r13, `SCRATCH_REG`
     r12, `PARAM_REGS` r0-r3, `RETURN_REGS` r0-r1, `FLOAT_PARAM_REGS`
     d0-d7, `ROC_RET_REGS` r0-r2, `RESULT_PTR_SAVE_REG` r9,
     `ROC_OPS_SAVE_REG` r10, `INCOMING_STACK_ARG_BASE_OFFSET` 8,
     `CALLER_STACK_ARG_BASE_REG` r11, `STACK_ALIGNMENT` 8, plus the
     tail-call target and delta registers, `RET_PTR_COPY_REG` and the
     callee-saved masks, which the reference predates. Part 6 picks those
     in its commits, under a test that no two roles share a register
     where their lifetimes overlap. Implications: the frame and allocator have their registers;
     part 7 adds only the argument-assignment code.
  2. **Only the roles part 6's own code uses; the rest in part 7.**
     Implications: a `CC` that does not yet satisfy the driver's reads,
     which D1's compile-error arms would have to cover as well.
- **Recommendation:** Alternative 1.
- **Consequences:** part 6's planning settles every arm32 register role in
  one place; a test checks that no role register is also in the
  allocatable pool.

### D3. The frame layout

- **Status:** Accepted (2026-11-28)
- **Context:** `DeferredFrameBuilder` asks each instruction set for its
  callee-saved layout. The reference pushes `{fp, lr}`, sets `fp = sp`,
  then saves r4-r10 at fixed slots below fp (28 bytes) and returns with
  `pop {..., fp, pc}`.
- **Alternatives:**
  1. **The reference's layout, as an `Arm32CalleeSavedInfo` in
     `FrameBuilder.zig`:** `push {r11, lr}`, `mov r11, sp`, a fixed
     28-byte area for r4-r10, locals below, sp 8-byte aligned at calls.
     Implications: stack arguments at a fixed `[r11, #8]`; matches what
     the reference ran on qemu and two Raspberry Pis.
  2. **One `push {r4-r11, lr}` of only the used registers.**
     Implications: shorter prologues, but slot offsets depend on which
     registers are used, so local offsets change after code is emitted;
     the deferred builder would have to patch them.
- **Recommendation:** Alternative 1.
- **Consequences:** a few unused slots in small functions. VFP
  callee-saved registers (d8-d15) are never allocated (D2's pool), so the
  frame saves none.

### D4. What moves from part 7 into part 6

- **Status:** Accepted (2026-11-28)
- **Context:** the reference spreads arm32 code over `CodeGen.zig`,
  `Call.zig`, `Emit.zig`'s `CC` and `CallingConvention.zig`. Part 7 is
  the calling convention.
- **Alternatives:**
  1. **Part 6: `CodeGen` (including `emitCall`, `emitDirectCall`, the
     call placeholders and their patching, and branch veneers), the
     register lists and roles of `Call.zig`, `CC`, and the frame. Part 7:
     the AAPCS32 `CallBuilder` arm in `CallingConvention.zig`, the
     entry-wrapper float handling (`emitEntryVfpArgStore`,
     `emitHostedFloatResultStore`) and `src/layout/abi/arm32.zig`.**
     Implications: part 6 is everything below "which register does this
     argument go in".
  2. **Calls and veneers in part 7 too.** Implications: part 6's
     `CodeGen` lacks methods the driver calls, so part 7 adds them to a
     file part 6 created.
- **Recommendation:** Alternative 1.
- **Consequences:** part 7's RFC starts from a code generator that can
  already branch to and call a symbol.

### D5. How the byte tests state what they expect

- **Status:** Accepted (2026-11-28)
- **Context:** part 6 is tested on bytes (Q-5). The encoder underneath is
  already checked against LLVM's assembler (part 4).
- **Alternatives:**
  1. **Expected bytes built by calling part 4's `Emit` directly.** A test
     runs a `CodeGen` method and compares its bytes with the same
     instructions emitted one by one through `Emit`. Implications: a test
     states which instructions a method chooses, in the encoder's terms;
     encodings are already proven by part 4's oracle.
  2. **Expected assembly text, assembled by the part 4 oracle tool.**
     Implications: the most readable tests, but the oracle tool and its
     build step grow a second kind of input and a second generated file.
  3. **Hand-written hex.** Implications: unreadable and duplicates what
     part 4 proves.
- **Recommendation:** Alternative 1.
- **Consequences:** about one test per family of methods (allocation,
  frames, loads and stores at each offset range, compares and branches,
  calls and patching, VFP), with offsets at the ends of each range.

### D6. Part 4's encoder signature

- **Status:** Accepted (2026-11-28)
- **Context:** part 4's `arm32.Emit(target: RocTarget)` predates
  upstream's change to `Emit(abi)`. With D1 alternative 1, `Abi` gains its
  arm32 member only in part 6.
- **Alternatives:**
  1. **Part 6 changes `Emit(target)` to `Emit(abi)`** in its first
     commit, with the `Abi` member. Implications: parts 4 and 5 stay as
     they are (R-4 is only a rebase); part 6's first commit touches part
     4's file and its generated oracle tests.
  2. **Part 4 becomes a plain `Emit` struct now, and part 6 makes it
     `Emit(abi)`.** Implications: parts 4 and 5 change again before part 6
     exists, with no gain.
  3. **Move "arm32 joins `Isa` and `Abi`" into part 4.** Implications: part
     4 gains D1's 230 arms, far from the code that needs them.
- **Recommendation:** Alternative 1.
- **Consequences:** between part 4 and part 6, `arm32.Emit` is the only
  encoder keyed on `RocTarget`; part 6's first commit ends that.

## Risks

### R1. A compile-error arm is reached in a build that should work

The arms are compile errors, so a build that reaches one fails loudly;
x86_64 and aarch64 never take them (the oracle and CI build those
targets). Nothing can reach them silently.

### R2. The byte tests miss a wrong instruction choice

They check what the code generator chooses, not that the choice computes
the right value. End-to-end proof comes in part 10. Mitigation: each test
names the AAPCS32 or A32 rule it relies on, and part 10's first PR runs
the reference's eval subset under qemu.

### R3. Review size

Estimated 2,300 to 2,700 lines. The D1 arms are mechanical and sit in one
commit; the code generator is split by method family.

### R4. Upstream moves the driver while part 6 is open

The driver changes daily. D1's arms are one line each, so a rebase
conflicts only where upstream adds or removes a switch, and the compiler
lists every new switch without an arm32 arm.

## Testing

From `.workspaces/arm32-codegen`, on each commit, the per-commit check list
in the README (with `run-check-arm32-encoding-oracle` and
`run-check-arm32-link-smoke`), `zig fmt --check ci build.zig`, the
`source` shard, and the relative oracle:

    python3 .workspaces/notes/incremental-plan/tools/relative_oracle.py \
      --upstream <base> --merged <commit> --apply-a0-to-merged

Expected: `relative 64-bit oracle: PASS`. The new byte tests are in the
backend test binary (`run-test-zig-module-backend`), and
`run-check-test-wiring` must show them wired. On the head, also the
`linux-core` shard.

## Recommendation

D1 1, D2 1, D3 1, D4 1, D5 1, D6 1.

## Outcome

Seven signed commits on `arm32/codegen`, local only. Each passed the
check list, `zig fmt`, the `source` shard and its review; the relative
oracle ran on each (results below).

| # | Commit | Content |
|---|---|---|
| 1 | `bfb0f19ef6` | `Isa.arm32`, `Abi.arm32_aapcs_vfp` (32-bit word), 230 arms (D1), `arm32.Emit(abi)` (D6), the `design.md` rule |
| 2 | `9c23a34c70` | `arm32/Call.zig` (registers only) and `Emit.CC` (D2) |
| 3 | `ff85894bcb` | The fixed frame in `DeferredFrameBuilder` (D3) |
| 4 | `1ff5f36a70` | `arm32/CodeGen.zig`: pools, stack slots, frames, immediates, word/byte/halfword memory |
| 5 | `23a97d2b95` | Integer operations, compares, jumps; the driver's `condCode` |
| 6 | `eae09a1d93` | f64/f32 operations, float compares, vector moves; the driver's `floatCondition` |
| 7 | `8fdc7c8868` | Calls, call patching, `emitLoadDataAddress`; the driver's `CodeGen` arm |

- **Size:** 1,714 lines added, 36 removed, in 19 files: `arm32/CodeGen.zig`
  948, `FrameBuilder.zig` +226, `LirCodeGen.zig` +224 (arms), `Call.zig`
  128, `Emit.zig` +112. 193 driver arms are still compile errors.
- **Arm wording:** `"arm32: <function> is not written yet"`, and "is not
  written for an arm32 host yet" for the host arms; arms inside tests of
  64-bit targets say "the targets above are 64-bit" (N-38, N-41).
- **Real now, not compile errors:** the driver's register and condition
  types (N-39), `condCode`, `floatCondition`, `CodeGen`.
- **Decided during the commits:**
  - E-20 1: `CC` declares no `TAIL_CALL_DELTA_REG`; the delta is an
    immediate on arm32.
  - E-21 3: a branch or call beyond A32's ±32 MiB is reported to the user;
    veneers wait for a program that needs them. D4 overstated the
    reference: its veneer methods were empty.
  - N-51 1: `CodeGen` treats an out-of-reach branch as an `invariant`; the
    user-facing check comes with the arm32 driver path.
  - Division (`__aeabi_*`) is not a `CodeGen` method: the call clobbers the
    temporaries in r0-r3, so the driver models it as a call.
  - The shared `RegisterPool` serves general registers only; arm32's float
    pool mixes registers with and without S views.
- **Owed by part 10 (recorded so it is not missed):** the user-facing 32 MiB
  branch-range check (N-51); moving the driver's `TAIL_CALL_DELTA_REG` read
  into the aarch64 arm and dropping x86_64's unused R10 (E-20); division
  as driver-side calls; `allocVector` for vector temporaries (part 11).
- **Check-list gap found:** tidy skips untracked files, so new files are
  `git add -N`'d before every check run.
- **Oracle:** commits 1 to 5 passed; 6 and 7 queued. `linux-core` on the
  head: running.
