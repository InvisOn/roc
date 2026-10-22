# Step 9: NEON SIMD

## Goal

The SIMD low-level operations work on arm32, using ARMv7 NEON. A vector
lives in a Q register, named by its even low D register. 64-bit lane
operations that ARMv7 NEON lacks are built from 32-bit and saturating
forms.

## Files from the reference snapshot

- `src/backend/dev/LirCodeGen.zig`: the NEON block (`neonQ`, `neonHigh`,
  `neonSize`, `emitBasicSimdVectorNeon`, `emitNeonGt64`,
  `emitNeonIsZero64`, and the `generateSimd*Neon` functions).
- `src/backend/dev/arm32/CodeGen.zig`: the vector loads, stores and moves,
  and `allocVector` (q8 to q15 are vector-only).
- `src/backend/dev/arm32/Emit.zig`: if step 2 left the NEON emitters
  stubbed, they arrive here.
- `ci/check_simd_codegen.sh`: the arm32 part.

## Mirrors

The aarch64 NEON code in the same file. ARMv7 NEON is a smaller cousin of
it, with no 64-bit lane compares and no `tbl` across two registers.

## Holes

| Hole | Function | The concept |
|---|---|---|
| 9.1 | `emitBasicSimdVectorNeon`, one family (add and subtract) | lane sizes in the encoding |
| 9.2 | `emitNeonGt64` | a 64-bit lane compare from 32-bit pieces |
| 9.3 | `generateSimdBitmaskNeon` | collapsing lane signs into an integer |

## Check

```sh
qemu-arm-static -cpu cortex-a9 out-arm/bin/eval-test-runner --timeout 300000
./zig-out/bin/roc build --opt=dev --target=arm32musl --output=simd test/simd/differential.roc
qemu-arm-static ./simd
```

The eval corpus barely reaches the SIMD kernels, so the differential
program matters most here.

Test counts: to be measured.

## Done when

- The full eval count is reached under qemu (all of the corpus, minus the
  known upstream case).
- The SIMD differential program agrees.

## Prompt

> Read `arm32-series/README.md` and `arm32-series/step-09-neon.md` on the
> `notes` branch. Build step 9 on top of step 8 with its holes, and guide
> me through them.

## Progress

- Not started.
