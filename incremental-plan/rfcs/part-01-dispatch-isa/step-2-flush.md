# Fold step 2, step 2 of 9: #8 instruction cache flush

Branch `dispatch/isa`, commit `3acba1afb1` "Flush the instruction cache
before making JIT memory executable", from #8 (`5aa8ffecbf`) plus review
fixes. The hash is the one at the time of writing.

## Why

`ExecutableMemory` wrote generated code and then made it executable with
`mprotect` or `VirtualProtect`, without synchronizing the instruction cache.
x86_64 keeps its caches coherent, so x86_64 CI never sees a problem. aarch64
and 32-bit ARM do not, so the CPU can run stale bytes from memory that was
just written. The arm32 backend runs JIT code on 32-bit ARM (the Pi 3), so
without this flush it can fail at random. aarch64 dev runs are at risk of
the same bug today.

The machine-code shim already flushed before publishing code. Moving that
helper into the dev backend lets the dev backend and the shim share one
flush, rather than keep a second copy.

## What changed

- `instruction_cache.zig` moves from `src/machine_code_shim/` to
  `src/backend/dev/`. The shim already imports the dev backend, so it uses
  it from there.
- `ExecutableMemory.protectExecutable` flushes before changing permissions.
- `FlushInstructionCacheFailed` joins every error set that carries
  `ExecutableMemory`'s errors, `finishWriteExecutablePrefix`'s included. Its
  only caller, `HostSplice.zig:296`, catches every error.
- Six test helpers in `LirCodeGen.zig` (`runRootI64`, `runRootU64`,
  `runRootU8`, `runRootFloatBits`, `ShiftHarness.run`,
  `runHostedRootOverDirtyStack`) get the error in their error sets, because
  they `try ExecutableMemory.initWithEntryOffsetAndUnwindInfo`.

## Review findings and outcomes

Applied, with approval:

- `FlushInstructionCacheFailed` placed in alphabetical order in
  `cli/main.zig` (twice), `ReplSession.zig`, `snapshot_tool/main.zig`,
  `coordinator.zig`, `checked_artifact.zig` (between `EmptyCode` and
  `MmapFailed`), `inspected_run.zig` and `lir_inline_test.zig`.
  `inspected.zig` was left as it was.
- In `machine_code_shim/main.zig`, the alias
  `const instruction_cache = backend.dev.instruction_cache;` moved below
  `const backend`.
- The message now ends with "...joins the error sets that carry
  ExecutableMemory's errors, finishWriteExecutablePrefix's included."

An accidental edit to `LirCodeGen.zig` was undone before the amend.

## Tests

All passed on `3acba1afb1`:

```
zig build -j2 --summary failures run-check-zig-format \
  run-check-unreachable-rationale run-test-zig-module-backend roc \
  run-test-zig-module-check run-test-zig-module-compile \
  run-test-zig-module-eval run-test-zig-lir-inline \
  run-test-zig-snapshot-tool run-check-snapshots
```

## Final commit message

```
Flush the instruction cache before making JIT memory executable

ExecutableMemory wrote generated code and then made it executable with
mprotect or VirtualProtect, without synchronizing the instruction cache.
x86_64 keeps the caches coherent, but aarch64 and 32-bit ARM do not, so a
CPU may run stale bytes from code memory it just wrote. The machine-code
shim already flushes through instruction_cache.flush before publishing
code.

That helper moves from the shim into the dev backend, which the shim
imports already, and protectExecutable now calls it before changing
permissions. FlushInstructionCacheFailed joins the error sets that carry
ExecutableMemory's errors, finishWriteExecutablePrefix's included.
```

## Open

- The flush has never run on aarch64 or ARM hardware. Step 7 runs it on the
  Pi 5 (`<user>@<aarch64-device>`) and the Pi 3 (`<user>@<arm32-device>`).
- #8 is closed at step 8.
