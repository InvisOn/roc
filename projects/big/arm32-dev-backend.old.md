## Problem

`RocTarget` (`src/target/mod.zig:420-422`) already lists `arm32linux` and
`arm32musl`, but the fast native "dev backend" cannot generate code for
either. `host_lir_codegen_available` (`src/backend/dev/LirCodeGen.zig:25373-25438`)
returns `false` for `.arm` with an explicit TODO: *"32-bit ARM builds
intentionally report false for now. The long-term fix is for dev builds on
those targets to route through LLVM rather than trying to instantiate a
nonexistent fast native backend."* `ObjectFileCompiler.compileToObjectFile`
(`ObjectFileCompiler.zig:147`) documents `CompilationError.UnsupportedTarget`
for arm32/wasm32, and `crossCompileDispatch` (`ObjectFileCompiler.zig:760-803`)
only monomorphizes `LirCodeGen(target)` for `.x86_64`/`.aarch64`/`.aarch64_be`,
returning `UnsupportedTarget` for every other arch. Every
`test/snapshots/dev_object_*.md` snapshot prints `arm32linux=NOT_IMPLEMENTED`
/ `arm32musl=NOT_IMPLEMENTED` as a result.

Users targeting arm32linux/arm32musl today fall back to the LLVM backend for
every build, including dev builds, losing the fast-iteration codegen path
every other supported architecture (x86_64, aarch64) already has.

wasm32 is out of scope here: it is also a 32-bit pointer-width target, but it
already has a complete, separate, working backend (`src/backend/wasm/`) that
does not route through `LirCodeGen`/`ObjectFileCompiler` at all. i386 is out
of scope: it has no `RocTarget` variant, so adding it would mean growing the
target enum itself, not filling an existing gap.

## Background

The dev backend is a hybrid of shared driver and per-architecture encoder:

- **Architecture-agnostic today:** `LirCodeGen` (LIR walking, layout math),
  `ObjectFileCompiler`, `CallingConvention` (`src/backend/dev/CallingConvention.zig`),
  `Relocation.zig`, `ObjectWriter`/`object/{elf,macho,coff}.zig`,
  `SymbolTable.zig`, `Dwarf.zig`. These already parameterize over `x86_64`
  vs. `aarch64` via comptime type params and tagged unions.
- **Architecture-specific, unavoidably per-ISA:**
  `x86_64/{CodeGen,Emit,Registers,SystemV,WindowsFastcall}.zig` and
  `aarch64/{CodeGen,Emit,Registers,Call}.zig` — literal machine-code
  encoders. No generic driver can derive ARM32 opcodes from x86_64 or
  aarch64 encoding logic. `aarch64_be` reuses `aarch64`'s files because it
  is an endianness variant of the *same* ISA, not evidence that one encoder
  generalizes across ISA families.

So this project needs a new `src/backend/dev/arm32/` module written from
scratch (Registers, calling convention, CodeGen, Emit), wired into the
existing shared driver. wasm32's existence as an entirely separate top-level
backend is the control case: genuinely different code-generation targets get
separate backends; only ABI/CPU-level variants within one ISA share.

### The hidden blocker: `LirCodeGen.zig` is not actually width-generic

`LirCodeGen` (`src/backend/dev/LirCodeGen.zig:676-782`) hardcodes:

```zig
const target_ptr_size: u32 = 8;   // line 688 — assumed for x86_64/aarch64
const roc_str_size: u32 = 3 * target_ptr_size;
const roc_list_size: u32 = 3 * target_ptr_size;
```

and `@compileError`s unless `arch == .x86_64 or .aarch64 or .aarch64_be`.
There are 152 uses of `target_ptr_size`/`roc_str_size`/`roc_list_size`, and
roughly 385 other literal-8 occurrences (stack-slot strides, `while (off <
roc_list_size) : (off += 8)` loops, etc.) across this 27,403-line file. The
good news: `layout.Store` and `base.target.TargetUsize` (`src/base/target.zig`)
already fully support `u32` width — that is how wasm32 works today — so the
type-size math upstream of codegen is already width-generic. The gap is
specific to this native-codegen driver.

### Register pressure

ARM32 (AAPCS32) has far fewer usable general-purpose registers than either
supported architecture: R0-R3 (args/caller-saved), R4-R11 (callee-saved),
R12 (scratch), R13=SP, R14=LR, R15=PC — about 12 usable GPRs, vs. x86_64's
~14 and aarch64's ~28. `Storage.claimGeneralReg`
(`src/backend/dev/mod.zig:200-205`) currently `@panic`s when registers run
out ("TODO: no free general registers; spilling/reload is not implemented").
ARM32 will hit that panic on realistic Roc programs far sooner than the
other two architectures do today, so register spilling is in-scope work for
this project, not a stretch goal deferred past it.

## Solution design

1. Instruction set: target A32 (fixed 4-byte encoding) first, not Thumb-2.
   Thumb-2 is a later code-size optimization, not part of this project's
   completion contract.
2. ABI: AAPCS32 hard-float (VFP), matching the realistic musl/glibc-hardfloat
   Linux default rather than soft-float.
3. Register allocation: implement real stack spilling for ARM32 rather than
   relying on the shared `Storage` panic path — the register budget is too
   small to defer this.
4. Object format: ELF only. There is no arm32 macOS or Windows `RocTarget`,
   so `object/macho.zig` and `object/coff.zig` need no arm32 work.
5. Generalize `LirCodeGen.zig`'s pointer-width assumption before writing any
   ARM32-specific code, so the shared driver can host a 4-byte-pointer
   target without a parallel hardcoded-8 copy.

## Implementation slices

### Slice 0 — Design decisions (no code)

Confirm A32-vs-Thumb-2, hard-float-vs-soft-float, and the spilling strategy
above in a short note, checked against the doc comments already in
`x86_64/mod.zig` and `aarch64/mod.zig` so terminology matches.

**Validate:** design note reviewed; no build/test impact yet.

### Slice 1 — Make `LirCodeGen` width-generic

Replace `target_ptr_size: u32 = 8` with a value derived from
`target.ptrBitWidth() / 8` (or thread `base.target.TargetUsize` through
directly), and audit every `roc_str_size`/`roc_list_size`/stride-of-8 site
(~150+ direct uses, ~385 literal-8 occurrences total) to use the derived
width instead of a literal. Relax the `@compileError` gate to also allow
`.arm`.

**Validate:** this slice changes zero behavior for x86_64/aarch64 (width
stays 8 for both). Run `zig build run-test-zig`, `zig build run-test-eval`,
and the existing `dev_object_*.md` snapshot tests, and confirm every
existing hash is byte-identical. Any diff here means the refactor leaked
into 64-bit codegen and must be fixed before continuing.

### Slice 2 — `src/backend/dev/arm32/` module

- `Registers.zig`: `GeneralReg` (R0-R12 + SP/LR/PC aliases), `FloatReg`
  (S0-S31/D0-D15 VFP).
- `Call.zig` (mirroring `aarch64/Call.zig`): AAPCS32 argument passing,
  8-byte stack alignment, varargs rules.
- `CodeGen.zig` + `Emit.zig`: instruction selection and A32 encoding for the
  LIR op subset the other two backends implement (arithmetic, control flow,
  calls, loads/stores, struct/tag layout access, RC inc/dec calls).
- `mod.zig`: same shape as `x86_64/mod.zig`/`aarch64/mod.zig`.

**Validate incrementally, instruction-by-instruction:** add byte-exact
encoding tests (mirroring the existing tests already in `x86_64/Emit.zig`
and `aarch64/Emit.zig`) for every instruction as it is written, checked
against an independent oracle (`objdump`/an ARM reference, or a
cross-toolchain assembler such as `arm-none-eabi-as`) before wiring it into
`CodeGen`. Land in small batches — moves/returns, then arithmetic, then
branches/calls, then loads/stores, then float ops — rather than writing the
whole encoder before testing any of it.

### Slice 3 — Extend the shared abstractions

- `CallingConvention.zig`: add an `arm32` arm to the `ParamReg`/`ParamRegs`
  unions and the AAPCS32 constants (`shadow_space = 0`, return/pass-by-ptr
  thresholds, `packs_stack_args` per AAPCS32 rules).
- `LirCodeGen.zig:697-812`: add `arm32.CodeGen`/`GeneralReg`/`FloatReg`
  selection arms, and `frame_ptr`/`stack_ptr`/`scratch_reg`/return-register
  mappings for ARM32.
- Zig's exhaustive `switch` on these enums will itself surface every
  remaining site needing an `.arm` arm as a compile error — treat that list
  of compile errors as the checklist for this slice rather than grepping
  manually.

**Validate:** `zig build` fails at each unhandled switch until arm32 is
threaded through everywhere; a clean build is the completion signal for
this slice, not a bug to route around (e.g. do not add a catch-all `else`
arm to silence it).

### Slice 4 — Object file emission (ELF only)

- `object/elf.zig:28-70,295-349`: add `EM_ARM = 40`, and the minimal ARM
  relocation set actually needed for the static/PIE-less Linux/musl targets
  (`R_ARM_ABS32`, a call relocation such as `R_ARM_CALL`/`R_ARM_JUMP24` or
  `R_ARM_REL32`, and GOT-relative data relocations only if required).
- `Relocation.zig`: add `arm32` cases at every arch-dispatch site (the
  pattern is already visible at `elf.zig:295-349` and `:800-805`).

**Validate:** generate a trivial "hello world" object file for
`arm32musl`, then verify it independently with a cross toolchain
(`arm-linux-gnueabihf-objdump -dr`, `readelf -a`) before trusting anything —
this is the ground truth, not the eventual snapshot hash.

### Slice 5 — Wire into dispatch points

- `LirCodeGen.zig:25379` (`host_lir_codegen_available`): move `.arm` out of
  the `false` list for the host-arch case (only relevant if Roc's own
  compiler is built to run on ARM32 hardware — a separate, lower-priority
  axis from cross-compiling *to* ARM32).
- `ObjectFileCompiler.zig:781` (`crossCompileDispatch`): add `.arm` to the
  arch check so it calls `compileWithCodeGen(LirCodeGen(comptime_target),
  ...)` instead of returning `UnsupportedTarget`. This is the line that
  actually turns cross-compilation on.
- `src/cli/main.zig` / `target_selection.zig`: several `switch` arms
  currently lump `arm32linux`/`arm32musl` into LLVM-only/"native" fallback
  branches (`main.zig:557-561`, `600-606`, `680-684`, `734-738`,
  `799-804`, `6088-6093`, `8395-8400`). Each needs a dedicated arm now that
  the dev backend can serve these targets — each is a place the old "arm32
  has no dev backend" assumption could otherwise linger unnoticed.

**Validate:** `roc build --target arm32musl app.roc` end-to-end on a "hello
world" program; inspect the produced binary. Full behavioral comparison
against the equivalent LLVM-backend build waits on Slice 6 (need to execute
the binary first).

### Slice 6 — Execution testing

The cross-backend eval harness (`zig build run-test-eval`, see
`CONTRIBUTING/debugging_backend_bugs.md`) drives the dev backend in-process
via JIT (`ExecutableMemory`) on the *host* architecture — it cannot exercise
ARM32 codegen unless the test runner itself runs on ARM32 hardware. Real
correctness testing needs one of:

- **QEMU user-mode emulation** (`qemu-arm`) to run cross-compiled ELF
  binaries from x86_64 CI — cheapest to stand up; add to
  `.github/workflows/ci_cross_compile.yml`.
- **Native execution on the existing self-hosted ARM64 runner**
  (`.github/workflows/basic_cli_test_arm64.yml`): many arm64 Linux kernels
  support running 32-bit ARM binaries natively via compat mode — check this
  before reaching for QEMU, since it is faster and closer to real hardware.
- A dedicated self-hosted 32-bit ARM runner (e.g. Raspberry Pi class),
  mirroring the ARM64 runner's pattern, if emulation proves insufficient for
  float-ABI edge cases or alignment traps.

**Validate:** extend `ci_cross_compile.yml` to build a battery of Roc
programs for `arm32linux`/`arm32musl` and execute each under whichever
runner is chosen, comparing stdout against the same programs run through
the interpreter and the x86_64/aarch64 dev backends. This is the actual
functional-correctness gate, independent of the snapshot hashes in Slice 7.

### Slice 7 — Snapshot/regression lock-in (last, not first)

Once Slice 6 has independently verified correctness for a representative
program set, regenerate every `test/snapshots/dev_object_*.md` (14+ files)
via the snapshot tool so `arm32linux=`/`arm32musl=` get real hashes instead
of `NOT_IMPLEMENTED`.

**Validate:** diff each regenerated snapshot by hand for the first pass and
confirm *only* the arm32/arm32musl lines changed — x86_64/aarch64 hashes
must stay byte-identical, per Slice 1's guarantee. After that, these hashes
become the fast regression net for future changes.

## Risks

- **Underestimating Slice 1's blast radius.** ~385 literal-8 occurrences in
  a 27k-line file is a lot to audit by hand; some will not be pointer-width
  related (e.g. byte counts for `f64`) and must not be touched. Budget real
  review time here, not a mechanical find-and-replace.
- **Register spilling correctness.** This is new logic the x86_64/aarch64
  backends do not exercise as hard (they rarely hit the panic path). It is
  the most likely place for silent miscompiles rather than crashes — needs
  its own stress-test category (Tests to add, below), not incidental
  coverage from ordinary snapshot programs.
- **No native execution path in ordinary CI.** Every correctness signal for
  generated ARM32 code depends on emulation or a self-hosted runner that
  does not yet exist for this project; until Slice 6 lands, Slices 2-5 are
  "believed correct from static inspection," which is a materially weaker
  guarantee than what x86_64/aarch64 changes get from the JIT eval harness.
- **AAPCS32 float ABI edge cases** (VFP register banking, `double` argument
  alignment on odd register boundaries) are a known source of subtle ABI
  bugs in other compilers' first ARM32 ports; do not treat Slice 2's
  per-instruction tests as sufficient without dedicated float-argument ABI
  tests.

## What success looks like

- `LirCodeGen(target)` compiles and runs correctly for `.arm`, with no
  change in generated output for any existing x86_64/aarch64 target.
- `roc build --target arm32linux` and `--target arm32musl` produce ELF
  object files/executables via the dev backend (not falling back to LLVM).
- A representative Roc program battery executes correctly under emulation
  or real ARM32 hardware, with output matching the interpreter and the
  other dev-backend architectures.
- Every `test/snapshots/dev_object_*.md` shows a real hash for
  `arm32linux`/`arm32musl` instead of `NOT_IMPLEMENTED`.
- Register-pressure stress tests (deeply nested expressions, many live
  locals) pass under the new spilling path.
- `host_lir_codegen_available` and every CLI dispatch site listed in
  Slice 5 has an explicit `.arm` decision instead of falling into a
  catch-all LLVM branch.

## How to evaluate the result

Re-run the full existing test matrix (`zig build run-test-zig`,
`zig build run-test-eval`) to confirm zero regressions on x86_64/aarch64,
then run the new ARM32-specific battery from Slice 6 under emulation/CI and
confirm output parity with the interpreter backend across the same test
programs. Spot-check a handful of generated object files with an
independent ARM cross-toolchain disassembler rather than trusting only the
in-repo snapshot hashes for the first several builds.

## Tests to add

- Per-instruction byte-exact encoding tests in `arm32/Emit.zig`, mirroring
  the existing `x86_64/Emit.zig`/`aarch64/Emit.zig` test style.
- AAPCS32 calling-convention tests: integer args in R0-R3 then stack,
  struct return-by-pointer threshold, VFP float-argument register banking,
  varargs.
- Register-pressure/spilling stress tests: programs with more live locals
  than available GPRs, specifically exercising the new spill path added in
  Slice 2 (this path has no equivalent forcing function on x86_64/aarch64
  today).
- ELF relocation tests for the new `R_ARM_*` types, analogous to the
  existing `R_X86_64_*`/`R_AARCH64_*` tests in `object/elf.zig`.
- CI battery of Roc programs executed under QEMU or the chosen ARM32
  runner, diffed against interpreter output (Slice 6).
- Updated `dev_object_*.md` snapshots (Slice 7), added only after Slice 6's
  independent verification, not before.

## Related projects

None yet filed against this doc. If [big/parallel-backend-codegen.md](parallel-backend-codegen.md)
lands first, its per-proc worker/writer split applies to `LirCodeGen(arm32)`
the same as it does to the existing two architectures — no extra work
implied in either direction, but land order should be noted if both are in
flight at once.
