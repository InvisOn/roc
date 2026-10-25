# Step 1: the driver for any word size

## Goal

The shared dev backend driver works for a 32-bit word, and
`LirCodeGen(.arm32musl)` compiles. Every arm32 code generator function
still panics with "step N". x86_64 and aarch64 output does not change by a
single byte.

## Files from the reference snapshot

- `src/backend/dev/isa.zig`: `isaOf` and `Isa.binaryIs`, the arch dispatch.
- `src/backend/dev/LirCodeGen.zig`: the biggest diff of the series (about
  8,700 changed lines). It does three things:
  1. Sizes go through `word`, `word_size` and `word_bits` instead of a
     fixed 8.
  2. Emit helpers move from the driver onto `self.codegen` (for example
     `self.codegen.emitLoad`), so each architecture supplies its own.
  3. Arch checks become `isa` switches with an `.arm32` prong.
- `src/backend/dev/x86_64/CodeGen.zig`, `aarch64/CodeGen.zig`,
  `x86_64/Emit.zig`, `aarch64/Emit.zig`: the helpers that moved there.
- `src/backend/dev/mod.zig`, `src/backend/mod.zig`: exports.
- `src/backend/dev/arm32/mod.zig` and an arm32 `CodeGen.zig` holding the
  full API with every function panicking "not implemented (step N)". The
  stub is not in the reference. Claude writes it from the real file's
  function list.
- Small upstream-code fixes the driver needs, each listed with its reason
  in `projects/big/arm32-dev-backend-existing-code-changes.md`. Examples
  are `src/lir/LIR.zig` (symbol name canonicalization, used by the oracle)
  and `src/eval/inspected.zig`.
- Docs: `src/backend/dev/arm32/GUIDE.md`, the sections "Architecture
  dispatch", "The per-ISA seam" and "The width vocabulary".

The arm32 prongs inside `LirCodeGen.zig` arrive here too, because they are
interleaved with the generalisation. They call into the stub, so nothing
arm32 runs yet.

## Mirrors

The x86_64 and aarch64 paths in the same file. Read the before and after of
a few functions to see the pattern, for example `generateTag`.

## Holes

None. This step is reading. Make a map of `LirCodeGen.zig`: its main
entry points, how one low-level op reaches the code generator, and where
each architecture differs. The holes plan's stage 4 ("trace `x + 1` from
LIR to bytes") is the exercise.

## Check

```sh
zig build run-check-unreachable-rationale
zig build build-test-eval-runner   # also compiles the arm32 driver
```

The 64-bit output must not change. Compare two builds made as the same
compiler version (base and step) with
`eval-test-runner --write-dev-code-hashes` and the `dev_object` snapshots
(`GUIDE.md`, "The 64-bit targets did not change"). Then `zig build minici`.

Test counts: arm32 unchanged from step 0. 64-bit hashes: identical.

## Done when

- The 64-bit hashes and snapshots are identical to the base.
- minici passes.
- `LirCodeGen(.arm32musl)` compiles. A temporary test that compiles one
  proc for arm32 reaches a "not implemented (step N)" panic.

## Prompt

> Read `stepwise-rebuild/README.md` and `stepwise-rebuild/step-01-driver.md` on
> the `notes` branch. Build step 1 on top of step 0. Cut the driver
> changes from `git diff 73df27a5bb e0fa273ebf`, write the arm32 CodeGen
> stub, and prove the 64-bit output is unchanged. Walk me through
> `LirCodeGen.zig` while I make my map.

## Progress

- Not started.
