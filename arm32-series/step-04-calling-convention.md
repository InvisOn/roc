# Step 4: the AAPCS32 calling convention

## Goal

Calls work in both directions. Roc procedures call each other and the
builtins, and C code calls into Roc, following AAPCS32 with VFP arguments
(the hard-float variant Linux uses).

## Files from the reference snapshot

- `src/layout/abi/arm32.zig`: `classifyType` (how each layout is passed),
  `fundamentalKind`, `countFloats` and `countVectors` (homogeneous float
  and vector aggregates).
- `src/layout/abi/call.zig`: the `.arm32` target, `placementArm32`,
  `assignPhysicalArgsArm32` (core registers r0 to r3, S registers with
  back-filling, splitting between registers and stack).
- `src/backend/dev/CallingConvention.zig`: the arm32 parts of the call
  builder: `allocVfp`, `emitVfpLoadAt`, `emitStackArgsArm32`,
  `emitStackArgArm32`, `emitAdjustSpArm32`, `emitArgInstArm32`.
- `src/backend/dev/arm32/CodeGen.zig`: the call functions (`emitCall`,
  `emitDirectCall`, `patchCall`, `emitCallPlaceholder`, the entry and
  hosted float helpers).
- `test/fx/abi_call_shapes.roc`, `test/fx/platform/Abi.roc`,
  `test/fx/platform/host.zig` and
  `test/fx/platform/zig_arm_nested_struct_abi_probe.zig`: shapes that pin
  the ABI against C.
- Docs: `DESIGN.md`, its calling convention sections.

## Mirrors

`src/layout/abi/aarch64.zig` and the AAPCS64 path in `call.zig`. What
differs on arm32:
- four core argument registers instead of eight
- a 64-bit value takes an even-odd register pair (rule C.3)
- a composite may split between the last registers and the stack (C.5)
- an F32 can back-fill an S register below a used D register
- large results come back through a pointer in r0, not x8

## Holes

| Hole | Function | The concept |
|---|---|---|
| 4.1 | `classifyType` | which values go in core registers, VFP registers or memory |
| 4.2 | `assignPhysicalArgsArm32`, the core register part | even-pair alignment and the C.5 split |
| 4.3 | `allocVfp` | back-filling S registers |
| 4.4 | `emitStackArgsArm32` | the outgoing stack area, and saving r12 when it is a source |

## Check

```sh
zig build run-test-zig-module-layout         # the ABI unit tests
zig build run-test-zig-module-backend
qemu-arm-static -cpu cortex-a9 out-arm/bin/eval-test-runner --timeout 300000
```

`test/fx/abi_call_shapes.roc` is checked in step 7, once programs link.

Test counts: to be measured.

## Done when

- The ABI unit tests pass.
- The measured eval count is reached.

## Prompt

> Read `arm32-series/README.md` and
> `arm32-series/step-04-calling-convention.md` on the `notes` branch.
> Build step 4 on top of step 3 with its holes. Before I start, have me
> explain AAPCS32 rules C.3 and C.5 back to you from the spec.

## Progress

- Not started.
