# Step 5: 64-bit values on 32-bit registers

## Goal

I64, U64 and F64 values work. The reference calls such a value a
**Wide64**. It lives in memory or as an immediate, never in one register
(decision D6 in `DESIGN.md`). Arithmetic loads it into a register pair.

## Files from the reference snapshot

- `src/backend/dev/LirCodeGen.zig`: the Wide64 functions:
  `wide64StackOffset` and its variants, `loadWide64Pair`,
  `storeWide64Pair`, `allocWide64Pair`, `freeWide64Pair`,
  `generateWide64IntBinop`, `generateWide64IntUnary`,
  `generateWide64IntConversion`, `emitWide64MulChecked`,
  `emitWide64NegatePair`, `finishWide64Overflowing`, `moveWide64ToReturn`,
  `wide64FromRet`, and `callAeabiHelper`.
- `src/backend/dev/CallingConvention.zig`: `addMem64Arg`, `addImm64Arg`,
  `addPairArg`.
- `src/builtins/native_runtime_libcalls.zig`: the `__aeabi_*` helpers
  (64-bit divide and remainder, and conversions between 64-bit integers
  and floats).
- Docs: `DESIGN.md`, D6.

## Mirrors

Nothing directly: on aarch64 a 64-bit value is one register. The closest
pattern is how x86_64 handles i128 as two registers.

## Holes

| Hole | Function | The concept |
|---|---|---|
| 5.1 | `generateWide64IntBinop`, the add and subtract part | the carry from the low word into the high word (adds, adc) |
| 5.2 | `emitWide64MulChecked` | a 64-bit product from 32-bit multiplies, and detecting overflow |
| 5.3 | `addPairArg` | passing a 64-bit argument in an even pair or on the stack |
| 5.4 | `callAeabiHelper` | why division calls a helper, and how its result comes back in r0:r1 |

## Check

```sh
qemu-arm-static -cpu cortex-a9 out-arm/bin/eval-test-runner --timeout 300000
qemu-arm-static -cpu cortex-a9 out-arm/bin/eval-test-runner --filter <name> --timeout 300000
```

A panic about a `.qword` load or a too-wide immediate means some site
passes a Wide64 as one register (`GUIDE.md`, "Listing what the driver
cannot yet compile").

Test counts: to be measured.

## Done when

- The measured eval count is reached, including the I64, U64 and F64
  cases.

## Prompt

> Read `stepwise-rebuild/README.md` and `stepwise-rebuild/step-05-wide64.md` on
> the `notes` branch. Build step 5 on top of step 4 with its holes.
> Start by explaining D6 to me with one example traced through the
> generated code.

## Progress

- Not started.
