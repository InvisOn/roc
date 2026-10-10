# ARM32 Dev Backend: Fuzzing Plan

How to fuzz the arm32 dev backend beyond the hand-written eval corpus. The
corpus found four arm32 lowering bugs in J3a (a checked I64 negate, a string
capture copy that exhausted the registers, the wrapping 128-bit multiply, far
addresses in r12) and one in CI (native call addresses above 4 GiB); this plan
looks for the next ones systematically. Status: proposed, 2026-09-29.

## Rules it follows

AGENTS.md and `test/fuzzing/README.md`: fuzzers generate small typed
language constructs and compose them randomly; no catalog of handwritten
scenarios; every userspace name comes from the generator's symbol
generator (builtin names are the only exception).

## What exists

- `test/fuzzing/fuzz-build.zig` generates a typed module
  (`TypedCodeGenerator`) plus an app and platform (`BuildWrapperGenerator`),
  picks a target from every `RocTarget` (arm32 included), and lowers it to
  LIR. It stops there: no code generation, no execution. So arm32 code
  generation is never fuzzed today.
- `TypedCodeGenerator` generates `Bool`, `Str`, `U64`, records, `List(U64)`,
  `Try(U64, Str)` and a `(Bool, U64)` tuple, composed through generated
  methods.
- The eval runner already evaluates each case on the interpreter and the dev
  backend and compares the results; built for arm32 (J3a), its dev backend
  generates and runs arm32 code in-process, under qemu or on a board.
- AFL++ support (`zig build -Dfuzz`) builds instrumented fuzz targets for the
  host; cross builds get repro executables only.

## Oracles

1. **Compile oracle (cheap):** generating arm32 code for any well-typed
   program must not panic, trip an assertion, exhaust the register pool
   (D10), or fail to encode. Runs on the host, at AFL speed.
2. **Differential oracle (strong):** a well-typed program's printed result
   (`Str.inspect`) must be the same from the interpreter and from arm32 code.
   The x86_64 dev backend is a third voice for triage: when the interpreter
   and arm32 disagree, the x86_64 result shows which one is wrong (the
   interpreter has bugs too).
3. **Floor oracle:** under `qemu-arm-static -cpu cortex-a9`, an instruction
   above the ARMv7 floor raises SIGILL, so the differential run under qemu
   also checks the CPU floor.

## Stages

### Stage 1: fuzz arm32 code generation (compile oracle)

Extend `fuzz-build` one step: after lowering, when
`devSupportsTarget(selected_target)`, run the dev backend's object-file
compilation for that target. arm32 is already among the targets the input
selects, so this reaches the arm32 code generator immediately, and the
x86_64/aarch64 ones as a bonus. Runs under the existing AFL++ setup on the
desktop. Small change; the first thing to land.

### Stage 2: widen the generator where arm32 is different

`TypedCodeGenerator`'s types miss the shapes where arm32's lowering differs
from the 64-bit targets. Add them as generator types, composed like the
existing ones (each new type multiplies the reachable programs; no fixed
scenarios):

| Add | arm32 code it reaches |
|---|---|
| `I64`, `U32`, `I32`, `I8`, `U8` | `Wide64` register pairs, narrowing and widening, word division helpers (`__aeabi_*`) |
| `I128`, `U128`, `Dec` | four-word memory lowering, UMAAL multiply, by-pointer helpers |
| `F32`, `F64` | VFP registers, S/D views, AAPCS32 back-filling |
| arithmetic in its `wrap`, checked (`?`) and plain forms | the overflow families, where two of the J3a bugs were |
| wide records and tuples | large frames (far addresses through LR), stack argument passing |
| methods with many parameters | AAPCS32 stack arguments and record splitting (C.5) |
| string interpolation over generated values | the capture copy that exhausted registers |
| SIMD vector types, where the generated types allow | NEON lowering |

Each addition also helps the other backends; nothing here is arm32-only
code in the generator.

### Stage 3: differential execution (the main value)

A new fuzz target, `fuzz-eval-differential`, built for arm32
(`-Dtarget=arm-linux-musleabihf`): from the fuzz input it generates a typed
program whose entry computes a value from generated literals and methods,
evaluates it with the interpreter and with the dev backend in-process
(reusing the eval runner's evaluation code, not a new pipeline), and reports
a mismatch or crash as a failure, printing the generated program.

Where it runs:

- **Raspberry Pi 5**, as a seed loop: fresh random inputs, one after
  another, for hours. Native speed, free, and on real hardware.
- **qemu `cortex-a9`** on the desktop, the same loop, which adds the floor
  oracle.
- **AFL++ with coverage**, later: AFL++'s QEMU mode can fuzz a foreign-arch
  binary with coverage, or an arm64 AFL++ build on the Pi 5 can run the
  arm32 target natively. Worth it only once the seed loop stops finding
  things.

### Stage 4: hosted-call ABI (later)

Generating platforms whose hosted functions take random signatures needs a
matching host compiled per case (a Zig host generated alongside), which is
much more machinery. The call-shape battery (`test/fx/abi_call_shapes.roc`)
covers the known AAPCS32 cases for now; revisit after stages 1-3.

## Triage and regression tests

- Every failing input is kept with its seed; `fuzz-repro` style executables
  print the generated program for it.
- Reduce the input (AFL++'s `afl-tmin`, or re-generating from a shorter
  seed), then decide who is wrong with the three-way vote (interpreter,
  arm32, x86_64).
- Each real bug is fixed in its own commit with a small eval test that
  reproduces it. The test is a regression test for one bug, not a fuzzer
  scenario, so the no-catalog rule is kept.
- Findings go to the issues note as usual.

## When it is done

- Stage 1: a 24-hour AFL++ run with no compile-oracle failure.
- Stage 3: a 24-hour seed loop on the Pi 5 and one under qemu `cortex-a9`
  with no unexplained mismatch, and the generator reaching every row of the
  stage 2 table (checked by counting the LIR operations the generated
  programs lower to).

## Order and effort

| Stage | Effort | Needs |
|---|---|---|
| 1 compile oracle | small: one step in `fuzz-build` | the desktop |
| 2 generator types | medium: several types in `TypedCodeGenerator` | the desktop |
| 3 differential target | medium: reuse the eval runner's evaluation | the 18 GB build fixed or built on the desktop; the Pi 5 and qemu to run |
| 4 hosted ABI | large | later |

Stages 1 and 2 help every backend and could go upstream on their own,
independent of the arm32 pull requests.
