# Step 3: basic code generation and frames

## Goal

Simple procedures run on arm32: integer arithmetic on one word, compares,
branches, loads and stores, F32 and F64 arithmetic in VFP registers, and a
correct function frame.

## Files from the reference snapshot

- `src/backend/dev/arm32/CodeGen.zig`: replace the step 1 stub with the
  real functions for registers, immediates, arithmetic, compares and
  conditions, loads and stores, floats, jumps and patching. Calls and SIMD
  stay stubbed.
- `src/backend/dev/arm32/Call.zig`: register roles (frame pointer, scratch
  registers, caller- and callee-saved sets, stack alignment).
- `src/backend/dev/FrameBuilder.zig`: `emitPrologueArm32`,
  `emitEpilogueArm32`, `emitSaveCalleeSavedArm32`,
  `emitRestoreCalleeSavedArm32`, `emitArm32SpDecrement` (with the stack
  probe loop), `arm32Alloc`, `Arm32CalleeSavedInfo`.
- Docs: `GUIDE.md`, "The code generator", and `GUIDE.md`, "Register budget".

## Mirrors

`aarch64/CodeGen.zig` and the aarch64 parts of `FrameBuilder.zig`. What
differs on arm32:
- 12 usable core registers instead of about 28
- a constant may need movw and movt
- 0xFFFF is not a valid immediate, so masks become uxtb or uxth
- the frame is `push {fp, lr}`, then `mov fp, sp`, then the stack drop
- callee-saved registers are stored at fixed slots below fp

## Holes

A first cut. Claude proposes the final list when building the step.

| Hole | Function | The concept |
|---|---|---|
| 3.1 | `emitLoadImm` | any 32-bit constant into a register |
| 3.2 | `emitCmp` and `condLess` | flags, and signed versus unsigned conditions |
| 3.3 | `emitLoadStack`, `emitStoreStack` | fp-relative addressing within range |
| 3.4 | `patchJump` | rewriting a branch once its target is known |
| 3.5 | `emitPrologueArm32` | the frame, and what fp points at |
| 3.6 | `emitArm32SpDecrement` | a large frame, and the stack probe loop |

## Check

```sh
zig build run-test-zig-module-backend
zig build build-test-eval-runner -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseFast --prefix out-arm
qemu-arm-static -cpu cortex-a9 out-arm/bin/eval-test-runner --timeout 300000
```

Run the backend test binary directly to see its real total (`GUIDE.md`,
"Registers, calling-convention constants"). Eval cases that need calls,
64-bit values or larger still fail with "not implemented".

Test counts: to be measured.

## Done when

- The backend unit tests pass.
- The measured eval count is reached, and every failure is a
  "not implemented" from a later step.

## Prompt

> Read `stepwise-rebuild/README.md` and `stepwise-rebuild/step-03-codegen-frames.md`
> on the `notes` branch. Build step 3 on top of step 2. Propose the final
> hole list first, then build it, measure the counts and guide me through
> the holes.

## Progress

- Not started.
