# Step 8: running code in-process

## Goal

The compiler runs arm32 code it just generated, inside its own process.
The eval runner and `roc` on an arm32 host need this. After this step the
whole eval corpus runs under qemu, apart from the SIMD cases.

## Files from the reference snapshot

- `src/backend/dev/HostSplice.zig`: binding builtins in the running
  process, and the arm32 stub (`ldr pc, [pc, #-4]` followed by the target
  address).
- `src/backend/dev/ExecutableMemory.zig` and
  `src/backend/dev/instruction_cache.zig` (moved from
  `src/machine_code_shim/`): making memory executable and flushing the
  instruction cache, which arm32 needs and x86_64 does not.
- `src/machine_code_shim/main.zig`, `src/backend/dev/RunImage.zig`,
  `src/backend/dev/NativeProcCompiler.zig`: the in-process paths.
- `src/eval/host_trampoline.zig`, `src/eval/boxy_abi.zig`,
  `src/eval/mod.zig`: the interpreter-side glue.
- `src/backend/dev/LirCodeGen.zig`: the `.native_execution` prong of
  `callAeabiHelper`.

## Mirrors

The aarch64 in-process path. What differs: the cache flush, and a stub
that can jump anywhere in the 32-bit address space.

## Holes

| Hole | Function | The concept |
|---|---|---|
| 8.1 | `writeStub` (arm32 branch) | an absolute jump through a literal |
| 8.2 | the instruction cache flush | why freshly written code needs it on ARM |

## Check

```sh
zig build build-test-eval-runner build-test-eval-host-effects-runner -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseFast --prefix out-arm
qemu-arm-static -cpu cortex-a9 out-arm/bin/eval-test-runner --timeout 300000
qemu-arm-static -cpu cortex-a9 out-arm/bin/eval-host-effects-runner
zig build run-test-zig-module-backend -Dtarget=arm-linux-musleabihf -fqemu
```

Known limit: one deep "curried lambdas" case runs out of memory on arm32
since upstream `534956997e`. It is an upstream regression, not ours.

Test counts: to be measured.

## Done when

- The measured eval and host-effects counts are reached.

## Prompt

> Read `stepwise-rebuild/README.md` and `stepwise-rebuild/step-08-native.md` on
> the `notes` branch. Build step 8 on top of step 7 with its holes, and
> guide me through them.

## Progress

- Not started.
