# Fold step 2, step 1 of 9: rebase #9

Branch `dispatch/isa`, commit `0b8b57955c` "Decide the dev backend's
architecture through one Isa type". Base: upstream `3bb8f2ec6c`. The hash is
the one at the time of writing; it changes if the branch is rebased again.

## Why

#9 is the plan's part 1. It was written against an older upstream, and the
fold puts #8, #4 and #3 on top of it, so it has to sit on current upstream
first.

The change itself: the shared dev backend driver decided between x86_64 and
aarch64 in about 220 places by comparing `target.toCpuArch()` with one
architecture and taking the other branch otherwise. Each `else` silently
means "the other architecture". When arm32 arrives as a third instruction
set, every one of those sites would send it down whichever branch was the
`else`, with no error. That is exactly the kind of guess AGENTS.md forbids.
With `Isa.binaryIs`, adding a third member turns every two-way site into a
compile error until it becomes a `switch` with its own answer, so the arm32
work is forced to decide each site explicitly.

## What changed

- New `src/backend/dev/isa.zig`: the `Isa` enum (`x86_64`, `aarch64`),
  `isaOf` (maps a `RocTarget` to its ISA and rejects the rest at compile
  time), and `Isa.binaryIs`.
- Every two-way check in `LirCodeGen`, `FrameBuilder` and
  `CallingConvention` goes through `binaryIs`.
- `mod.zig` exports the module.
- No change to generated code.

## Review findings and outcomes

Applied, with approval:

- `binaryIs` now checks `@typeInfo(Isa).@"enum".field_names.len != 2` and
  raises a `@compileError` telling the reader to replace the site with a
  switch. `std.enums.values` ran over the comptime branch quota at
  `ObjectFileCompiler.zig:1141`, and `.fields` does not exist in Zig 0.17.
  An experiment with a third ISA produced 81 compile errors, as intended.
- `isaOf` also rejects `.aarch64_be`, with "the dev backend serves only
  x86_64 and little-endian aarch64 targets". Both emitters write
  little-endian code, and no `RocTarget` uses it.
- The module doc says "instruction-set decision".
- The original test "isaOf maps the native RocTargets" (3 targets) was kept.
  An expanded 31-target version was rejected: v1 targets never reach
  `isaOf`, and `ObjectFileCompiler.zig:1139-1146` already instantiates the
  default targets.
- New test "binaryIs answers each pair of instruction sets".
- `comptime` added at four `LirCodeGen.zig` sites (15005, 15006, 21715,
  21940).
- The `isaOf` import moved next to the x86_64 and aarch64 imports in
  `CallingConvention.zig` and `FrameBuilder.zig`.

Left as they are:

- `FrameBuilder` and `CallingConvention` cache `is_x86_64` and `is_aarch64`.
  The `binaryIs` guard covers them.
- `ObjectFileCompiler.zig:1144` has a dead `aarch64_be` check. It is upstream
  code outside this change.

## Tests

Run on the step 2 head (`3acba1afb1`), which includes this commit; all
passed:

```
zig build -j2 --summary failures run-check-zig-format \
  run-check-unreachable-rationale run-test-zig-module-backend roc \
  run-test-zig-module-check run-test-zig-module-compile \
  run-test-zig-module-eval run-test-zig-lir-inline \
  run-test-zig-snapshot-tool run-check-snapshots
```

## Final commit message

```
Decide the dev backend's architecture through one Isa type

The shared dev backend driver decided between x86_64 and aarch64 in about
220 places, each by comparing target.toCpuArch() with one of the two and
taking the other branch otherwise. Every such `else` silently stands for
"the other architecture", so a third instruction set would be routed into
whichever branch happened to be the `else`, with no error.

isa.zig adds the Isa enum, isaOf (which maps a RocTarget to its ISA and
rejects the rest at compile time, as LirCodeGen's own check did), and
Isa.binaryIs. binaryIs only answers while there are exactly two ISAs, so
adding a third makes every two-way site a compile error until it becomes a
switch with its own answer. Every two-way check in LirCodeGen, FrameBuilder
and CallingConvention now goes through it. isaOf also rejects aarch64_be:
both emitters write little-endian code, and no RocTarget uses it.

No change to generated code.
```

## Notes

- A background fetch moved `upstream/main` from `04d6133c76` to `3bb8f2ec6c`
  during the autosquash. This was disclosed, and the new base was kept.
  Later rebases use explicit commit hashes, not `upstream/main`.
