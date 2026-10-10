# ARM32 Dev Backend Design

This document describes how the arm32 (A32, ARMv7-A + NEON, AAPCS32
hard-float) dev backend is built, what exists today, and what was learned
while building it. The plan that sequences the work, with its acceptance
criteria, is `projects/big/arm32-dev-backend.md`; its decision numbers (D1-D12)
and unit names (A0-A3, Track B, J1-J4) are used here. `design.md` remains the
authoritative reference for compiler-wide invariants.
Issues found along the way are tracked in
`projects/big/arm32-dev-backend-issues.md`. `GUIDE.md` explains how the pieces
work and how to test each one; `TOOLS.md` documents the tools.

## Status

| Unit | State |
|------|-------|
| Track B, first batch: registers, integer/VFP encoder, AAPCS32 constants, encoding oracle | Done |
| A0: byte-identity oracles for the 64-bit targets | Done |
| A1, dispatch: every arch decision in the driver is exhaustive or arm32-refusing | Done |
| A1, register budget: temporaries allocated by the per-arch `CodeGen`, D10 high-water mark | Done |
| A1, `CC` register seam and facade for ISA-neutral helpers | Done |
| A1 facade for i128/SIMD/overflow/entry strategies | Deferred to A2 and the NEON batch, which did not add it: J1 gave these sites `.arm32` arms with raw emitter calls in exhaustive switches instead. Open (issues note, "The driver still names mnemonics and register literals") |
| Track B, NEON batch: the Advanced SIMD encoder families, 147 oracle entries | Done |
| A3: ELF32/REL writer, `.ARM.attributes`, `R_ARM_*` relocation kinds, DWARF address width | Done |
| A2: width model (`WORD`, `Wide64`, four-word i128) | Classification done: every `.w64` in the driver is `word`, a word loop, or `wide64_reg_width`/`wide64_store_width` (the rest name `StoreWidth` or an ISA's own width table); pair lowering and the by-pointer i128 wrappers are J1's |
| Track C: arm32 runtime objects, `_start`, glibc stub, CLI tables, test-platform manifests and musl runtime | Done |
| Track C: CLI test-runner cross-target rosters | Done with Track D (`int` and `fx` list arm32musl; the runner's `--cross-opt=dev`) |
| Track D: CI lanes (arm32 cross-compile with `--opt=dev`, qemu on-target row, arm32 eval runner under qemu), allowed to fail | Done |
| J1a: `arm32/CodeGen.zig`: allocator pools, stack slots, the ISA-neutral facade | Done |
| J1b: frame builders (deferred and forward) | Done |
| J1b: AAPCS32 `CallBuilder` (pairs, C.5, VFP back-filling, arm32 call emitters) | Done |
| J1b: AAPCS32 C-ABI classifier and physical assignment (`layout/abi/arm32.zig`, `Target.arm32`, `PhysicalArg.split`) | Done |
| J1c: the driver's calls, returns, entry wrappers, helpers and two-way ISA tests | Done |
| J1d: `Wide64` lowering (arithmetic, overflow, division, shifts, compares, unary ops, conversions, F64 bits) | Done |
| J1d: four-word i128/Dec, word division through `__aeabi_idivmod`, U64 window and discriminant values | Done |
| J1e: NEON lowering of every SIMD op; q8-q15 as vector-only temporaries | Done (compiles; execution checked in J1f-J3) |
| J1f: acceptance tests (`LirCodeGen(.arm32musl)` instantiates with the D5 map; a proc compiles through it) | Done; the hand-linked hello world moved to J2, whose `roc build --opt=dev --target=arm32musl` links and runs real programs through the same code generator |
| J2: `supportsTarget` gate, CLI and phase names, `--keep-temp`, arm32 runtime fixes found by real builds | Done (the snapshot tool kept arm32 at `NOT_IMPLEMENTED` until J4) |
| J2: the default platform declares `arm32musl` and `arm32linux` | Done; a CLI case builds `baseline_cpu_smoke.roc` for arm32musl |
| J2: `arm32linux` (glibc) on the int platform | Done; runs on the Pi, CI builds it on the Linux host |
| J2: arm32 lane of `run-check-simd-codegen` | Done; the exhaustive SIMD corpus builds, contains NEON, and passes under qemu and on the Pi |
| J2: D10 register budget over every program J2 builds | Done: general 9 / 11, float 7 / 12, no pool exhausted (see "The register budget is already tight on 64-bit targets") |
| J2: D2 floor asserted where code is generated | Done: `arm32/Emit.zig` checks Zig's arm baseline at comptime (see D2 under "Decisions as implemented") |
| J2: gate-consistency test (`supportsTarget` against the `dev_object` snapshot lines) | Moved to J4 and done there |
| J3b: `--cross-run`/`--cross-runner` in the CLI runner | Done; all 121 `test/fx` programs run correctly under qemu (the fx host works around a Zig 0.16 arm ABI bug) |
| J3a: `host_lir_codegen_available` for arm; the eval runner, host-effects runner and backend tests built for arm32 | Done: under qemu, eval 2171/2171 (dev 2030 evaluations, as on x86_64), host effects 86/86, backend tests 892 passed. On a Raspberry Pi 5 (8 GB, 64-bit kernel with 16 KB pages): eval 2171/2171 (dev 2030 evaluations) in 3.7 minutes, host effects 86/86, all 122 fx programs. On the Raspberry Pi 3: host effects 86/86, eval 2169/2171 with dev 2028 of the 2028 evaluations it reached; the two others ran out of memory while compiling (issues note). Wasm evaluation is unavailable in a 32-bit process (issues note) |
| J3c: the `ci_cross_compile.yml` arm32 lanes are required, and the on-target job compares each arm32 int app's stdout with the Linux-built x64musl app's | Done locally (Linux host, qemu); the macOS and Windows hosts are first checked by CI. The int app prints heap addresses, which the comparison masks |
| J3: call-shape battery and real hardware (the residual risk J3 names) | Done: `test/fx/abi_call_shapes.roc` crosses the host boundary with each AAPCS32 argument and result shape (a register pair after an i32, an i64 on the stack, a record split by C.5, an f32 back-fill, nine f64s, a hidden result pointer, an F64 -> I64 -> F64 round trip). On a Raspberry Pi 3 (Cortex-A53, 32-bit Linux) all 122 fx programs pass through `ci/ssh_cross_runner.sh`, and the refcount builtins there run LDREX/STREX/DMB (refcounts are atomic unless proven single-threaded) |
| J4: lock-in | Done: the snapshot tool asks `devSupportsTarget` for every target, all 16 `dev_object` snapshots carry arm32 hashes (only `arm32*=` lines changed, stable across regeneration and `--debug`), the snapshot tool's gate-consistency test pins them to the gate, and design.md names ARM32 among the native dev backends and states its CPU floor |

`roc build --opt=dev --target=arm32musl` and `--target=arm32linux` build real
programs through the arm32 code generator, and every `dev_object` snapshot
locks its arm32 object bytes (J4, after J3's execution oracles had checked
the code the hashes lock in).

## Where arm32 sits in the pipeline

```
checked modules -> LIR (target_usize = u32) -> LirCodeGen (shared driver)
    -> arm32.CodeGen (J1) -> arm32.Emit (this directory)
    -> ObjectWriter / ELF32 (A3) -> ld.lld (unchanged)
```

Everything up to and including LIR is already width-generic: `TargetUsize`,
the layout store, static-data materialization and `StaticStringData` all take
the word size from the target, and they already produce 32-bit layouts for
wasm32. The work is downstream of LIR, in the dev backend's shared driver
(`LirCodeGen.zig`, `FrameBuilder.zig`, `CallingConvention.zig`), which is
written against a 64-bit general register and branches on the architecture
with binary `if`s that would silently route `.arm` into the aarch64 or x86_64
paths. Track A replaces those with exhaustive switches and a per-arch facade
before any arm32 code is reachable.

## Architecture dispatch in the shared driver

`src/backend/dev/isa.zig` defines `Isa = { x86_64, aarch64, arm32 }` and
`isaOf(target)`. `LirCodeGen`, `FrameBuilder` and `CallingConvention` take
every architecture decision through it, in one of two forms:

- an exhaustive `switch (isa)` with an `.arm32` prong (today
  `@compileError("arm32: TODO")`), used wherever the choice selects a type or
  a whole implementation (`CodeGen`, register types, `CalleeSavedInfo`, the
  prologue/epilogue bodies, the `CallBuilder` register-assignment bodies);
- `isa.binaryIs(.x86_64)` / `isa.binaryIs(.aarch64)` for the ~250 two-way
  tests inside `LirCodeGen`'s bodies. `binaryIs` is a compile error when the
  instantiation is arm32.

This amends the plan's A1, which asked for every site to be rewritten by
hand into a three-way switch. Both give the property the plan is after:
instantiating the driver for arm32 cannot compile while any site still makes
a two-way x86_64/aarch64 decision, so the compiler, not review, produces
J1's checklist, and no site can silently send arm32 down another ISA's path
(the failure mode the plan warns about, where `if (arch == .x86_64) A else B`
quietly routes arm32 into `B`). The `binaryIs` form was chosen because it is
a mechanical rewrite of existing boolean tests and therefore provably
byte-identical for x86_64 and aarch64, whereas hand-rewriting ~250 if/else
bodies into switches in a 28,000-line file is where a behavior change would
hide. J1 converts each site to a real switch as it teaches it arm32. The
never-read `LirCodeGen.cc` field, whose initializer would have panicked for
arm32 through `CallingConvention.forTarget`, is gone, and `ObjectWriter`'s ELF
architecture choice is an exhaustive switch with arm32 still refused until
A3's ELF32 writer exists.

### Which sequences get a facade method

A facade method is worth its shared signature only when every ISA can
implement that signature naturally. The 55 helpers moved in A1 qualify:
width-tagged loads and stores, stack addressing, immediates, compares,
condition codes, register arithmetic, trap. The i128 arithmetic, SIMD
kernels, checked-multiply sequences and entry wrappers do not yet: their
x86_64/aarch64 bodies assume one 64-bit register per value, while arm32
keeps i128 in memory and 64-bit values in memory, loaded as register pairs
(D6), and its SIMD is NEON. They keep `binaryIs` tests until A2 and the
NEON batch define signatures that fit all three ISAs.

## Module layout

- `Registers.zig`: `GeneralReg` r0-r15 with `fp`/`ip`/`sp`/`lr`/`pc` as
  declarations (Zig enums cannot alias values). The VFP/NEON bank is one
  register file seen three ways: `SReg` s0-s31, `DReg` d0-d31, `QReg` q0-q15,
  with conversions between views. `FloatReg` is `DReg`, the unit a register
  allocator owns, so one allocator owns every view and s/d/q aliasing cannot
  be double-booked. Only d0-d15 have S views, so an f32 value must be
  allocated in d0-d15. `RegisterWidth` has one member, `w32`.
- `Emit.zig`: one function per instruction form, with typed operands:
  - `ModImm` is the only way to pass a data-processing immediate. A32 can
    only encode an 8-bit value rotated by an even amount, so an unencodable
    immediate is a type error at the call site (`ModImm.of` fails at compile
    time, `ModImm.encode` returns null) rather than a silent fallback inside
    the encoder.
  - `Operand2` covers immediate, register, register shifted by an immediate
    and register shifted by a register; `dataProc` is the general entry point
    with condition and flag-setting, and named wrappers exist for the common
    forms.
  - Memory forms assert their offset range. `fitsImmediate(form, offset)`
    exposes the per-form ranges (word/byte ±4095; halfword, signed byte and
    doubleword ±255; VFP ±1020 in multiples of 4; NEON none) so the caller
    decides when to form the address in the scratch register. The encoder
    never forms addresses itself.
  - Branch displacements are relative to the branch instruction; the encoder
    applies A32's PC+8 bias. `bl(0)` therefore encodes `0xEBFFFFFE`, which is
    exactly the REL-form addend of an `R_ARM_CALL` relocation (D1).
  - `pcRelAddress` emits the D8 sequence (`movw`/`movt`/`add rd, pc, rd`,
    immediates `0xFFF0`/`0xFFF4` holding the REL addends -16/-12) and returns
    the offset the relocations attach to.
  - The `CC` namespace carries D5's constants for `CallingConvention` and
    `FrameBuilder`.
  - NEON is encoded per encoding family rather than per mnemonic: one
    emitter per family and register shape (`neonThreeSameQ`/`D`,
    `neonLogicQ`/`D`, `neonThreeDiff`, `neonTwoMiscQ`/`D`, `neonNarrow`,
    `neonShiftRightQ`, `neonShiftLeftQ`, `neonShiftNarrow`,
    `neonShiftLeftLong`), with the operation as an enum (`NeonThreeSame`,
    `NeonTwoMisc`, ...) that owns its opcode bits, plus single emitters for
    the one-off forms (`vmovI8Q`, `vmovI64Q`, `vextQ`, `vtbl`,
    `vdupQFromCore`, `vdupQFromLane`, `vmovLaneFromCore`, `vmovCoreFromLane`,
    `vld1Q`, `vst1Q`). Each enum knows which lane sizes ARMv7 defines it for,
    and the emitter asserts that, so a request for an instruction the floor
    lacks (for example `VMAX.S64`) fails at the call site rather than
    producing a different instruction. The oracle has at least one entry per
    enum member.
- `Call.zig`: AAPCS32 register roles and allocation masks. The pool is r0-r3
  (caller-saved) plus r4-r10 (callee-saved); r11 is the frame pointer and r12
  the scratch register, excluded from allocation as x86_64's R11 and
  aarch64's X9 are.
- `encoding_oracle_tests.zig`: generated; see below.

## Decisions as implemented

The plan's D1-D12 stand; these points are where the implementation made them
concrete or amended them.

- **Return registers (D5, amended).** `CC.RETURN_REGS = {r0, r1}` is the C-ABI
  return set (r0:r1 for a 64-bit scalar). The Roc-internal three-register
  RocStr/RocList return is a separate constant, `CC.ROC_RET_REGS = {r0, r1,
  r2}`, so no C-ABI consumer can mistake r2 for a return register.
- **`needsReturnByPointer` is not in `CC` yet.** AAPCS32 returns composites
  wider than a word through a hidden pointer but 64-bit scalars in r0:r1, so
  the predicate needs to know whether the value is a composite. The shared
  signature takes only a size; J1 changes the shared signature rather than
  giving arm32 a size-only approximation.
- **Runtime helpers (D7, confirmed).** Zig's compiler-rt (the pinned 0.16.0)
  exports every helper D7 lists. The float/i64 conversions
  (`__aeabi_d2lz`, `__aeabi_l2d`, ...) are declared `callconv(.arm_aapcs)`,
  the base procedure-call standard, so operands travel in core registers
  even in a hard-float program, as D7 requires. `__aeabi_ldivmod`,
  `__aeabi_uldivmod` and `__aeabi_uidivmod` are naked assembly with the
  documented register convention. `__aeabi_llsl`/`llsr`/`lasr` are exported
  too; the encoder already has the shifted-register operand forms the
  standard inline 64-bit shift sequence needs, and J1 decides between the
  two.

- **No by-pointer i128/Dec wrappers (D6, amended).** D6 planned new
  by-pointer variants of the `callI128*`/`callDec*` wrappers because the
  existing ones take four `u64` scalars, which do not fit r0-r3. They do not
  need to: AAPCS32 passes each `u64` in an even register pair or on the
  stack (C.3-C.5), and `CallBuilder.addMem64Arg` places each half from its
  slot, so the arm32 driver calls the same wrappers as the 64-bit targets
  with every operand's halves read from its 16-byte slot
  (`callI128WrapperWords`).
- **Vector-only temporaries (D5, amended).** D5's float pool is d0-d6
  (q0-q3), four registers, which a three-operand SIMD op plus its
  temporaries exhausts. q8-q15 (d16-d30) are caller-saved under AAPCS32 and
  exist on the VFPv3-D32 floor (D2), but have no S views, so they are
  vector-only: `CodeGen.allocVector` hands them out first and the shared pool
  after them, while `allocFloat` (f32/f64) draws only from d0-d6. Calls spill
  vector locals as before, so no callee-saved register is involved.
- **The floor is Zig's arm baseline, asserted in `Emit` (D2, amended).** D2
  planned to record the floor in `cpuContract` by giving `.arm`
  `instruction_features = neon`, and to assert
  `requiredRuntimeCpuFeatures()` in `arm32/Emit.zig`. Since then the target
  module has adopted a rule that forbids this: a target whose query names a CPU
  model or adds CPU features raises the floor, so it must have a `v1` twin
  (tests "every target Roc raises the CPU floor for has a v1 twin" and "arm32
  and macOS arm64 have no v1 twin because Roc names no floor for them"). NEON
  is already in Zig's arm baseline, so naming it would add a floor that is not
  above anything, and D2 rules out an arm32 `v1` twin. The contract stays
  empty. `Emit` instead asserts at comptime that the contract names no
  features, and that `std.Target.Cpu.baseline` for the target has NEON and
  lacks `hwdiv`/`hwdiv_arm`. The existing `src/target/mod.zig` test pins the
  resolved query the same way at run time.
- **Far addresses are formed in LR (D5, amended).** D5 gives r12 two jobs:
  the driver's fixed scratch register (the return pointer while a result is
  copied out, the data register of stack-argument copies) and the register a
  memory access forms an out-of-range address in (A32 reaches ±4095 bytes
  from a base; halfword, doubleword and VFP forms less). A large aggregate
  needs both at once, and the second clobbers the first. Every arm32 frame
  saves LR in its prologue and returns by popping PC, and the frame policy is
  always `.always`, so LR is free inside a body. `Call.ADDRESS_SCRATCH_REG =
  LR` now forms far addresses, and the address is consumed by the very next
  load or store, so it is never live across a call. r12 is then an ordinary
  base or data register at any offset.
- **Word division (D7).** The floor has no `SDIV`/`UDIV` (D2), so a word
  divide or remainder calls `__aeabi_idivmod`/`__aeabi_uidivmod` (quotient
  r0, remainder r1) through `emitWordDivRem`; signed modulo keeps its divisor
  in a frame slot across the call.

## How correctness is established

### Encodings: the assembler is the oracle

`ci/arm32_encoding_oracle.s` pairs each line of A32 assembly with the `Emit`
call that must produce the same bytes. `ci/arm32_encoding_oracle.py`
assembles the file with `zig cc -target arm-linux-musleabihf` (LLVM's
integrated assembler, so every host with the pinned Zig can run it), reads the
object with `ci/elf32_reader.py`, and writes one test per entry to
`encoding_oracle_tests.zig`, each a call to its `expectEncoding` helper. `zig build test` therefore needs no
external tool, and `zig build run-check-arm32-encoding-oracle` (in minici)
fails when the generated file is stale or when an emitter has no entry.

Entries deliberately exercise the high register bits (r8-r15, odd S
registers, d16-d31) and both offset signs, which is where hand-written A32
encoders usually go wrong (the D/N/M bit split of VFP register numbers is
different for S and D registers).

### The 64-bit targets must not change: two byte-identity oracles

Track A rewrites the shared driver that x86_64 and aarch64 depend on, so any
change to their output is a bug. Two oracles catch it:

- **`dev_object` snapshots.** Ten existed; A0 added six that reach the code
  paths Track A touches (float math and F64 to I64, Dec/I128/U128 with a tuple
  return, list operations with a capturing closure, a recursive boxed tree
  forcing refcount helpers, eighteen mixed arguments that overflow both
  argument register files, and string operations beyond the small-string
  limit). They hash the object for every `RocTarget` from every host.
  **Amended (2026-10-01):** the recursive boxed tree and the string snapshots
  are removed, leaving four; see "Snapshot hashes must not depend on the
  compiler's optimize mode" below. The eval-corpus hashes cover both areas.
- **Eval-corpus object hashes.** **Amended (2026-10-03):** the committed
  file `test/dev_code_hashes/eval.blake3` and its minici step are gone; the
  hashes are now compared between two builds pinned to one compiler
  version. See "A stored hash of generated code cannot outlive a compiler
  commit" below. What follows describes the hash mode itself, which stays.
  `eval-test-runner --check-dev-code-hashes <file>` compiles every eval case that
  returns an inspected value, 1961 of them, through the dev backend's
  object-file path for `x64musl` and `arm64musl` and compares each object's
  Blake3. `--write-dev-code-hashes` regenerates the file. The work is sharded
  across forked children and concatenated in order, so the output is
  byte-identical to a sequential run; it takes about four minutes on sixteen
  cores.

Both oracles hash objects with procedure symbol names canonicalized (see
"Procedure symbol names change with every compiler build" below), so they pin
code generation, not the compiler's git revision.

### Objects: ELF32 with REL relocations (A3)

`object/elf.zig` writes `Architecture.arm` as ELF32 (`write32`); x86_64 and
aarch64 keep the untouched ELF64 path (`write64`), which the byte-identity
oracles confirm. D9's REL form is confirmed: records are `Elf32_Rel`, and
because REL has no addend field the writer stores each relocation's explicit
addend into the relocated field of its output copy, encoded per type (a
word for `R_ARM_ABS32`, imm24 in words for `R_ARM_CALL`, signed imm16 for
`R_ARM_MOVW_PREL_NC`/`R_ARM_MOVT_PREL`). Producers therefore pass addends as
data exactly as they do for RELA; nothing decodes an addend back out of an
instruction. Every object carries `e_flags = 0x05000400`, D9's
`.ARM.attributes` set, and a `$a` mapping symbol. `Dwarf.build` takes the
target's address width, and `DataRelocationKind` gains `abs32`,
`arm_movw_prel` and `arm_movt_prel` (refused explicitly by the Mach-O and
COFF writers and by `RunImage`, whose shim never runs arm32 code).

An end-to-end check ties the encoder and writer to a real toolchain: a
function built with `arm32.Emit` (PC-relative string address through
`movw`/`movt`/`add rX, pc`, a `bl` to musl's `puts` through `R_ARM_CALL`,
`push`/`pop`) and written by `ElfWriter`, linked by LLD via `zig cc -target
arm-linux-musleabihf` with a C `main`, runs under `QEMU_CPU=cortex-a9
qemu-arm-static` and prints its string and returns 42. `readelf -A` and
`python3 ci/elf32_reader.py --attributes` decode the attributes identically,
and they match what LLVM emits for `-mcpu=cortex-a9` on every tag Roc writes.

Two pre-existing J3a concerns surfaced: `Relocation.patchLinkedFunctionRelocation`
chooses a patch by decoding the instruction bytes, and
`patchAbsolutePointerOperand` sizes `abs64` by the *host's* `usize`. The
in-process arm32 path must instead carry explicit kinds (`abs32` exists now).

### Runtime objects and the CPU floor (Track C)

`build.zig` builds the six prebuilt objects (`roc_builtins`,
`roc_builtins_extern`, `roc_boxy_runtime`, `roc_default_runtime`,
`roc_default_compiler_rt`, `roc_default_platform`) for `arm32musl`
(`arm-linux-musleabihf`) and `arm32glibc` (`arm-linux-gnueabihf`); all twelve
are ELF32, EM_ARM, `e_flags 0x5000400`, `Tag_ABI_VFP_args: 1`. The builtins
compile unchanged at 32-bit `usize`, which answers the plan's first Track C
risk. The CLI embeds them with explicit `arm32musl`/`arm32linux` rows in every
table; arm32 no longer falls through to the host's `native` object. The
default platform has an A32 `_start` (argv one word above argc, SP aligned to
8) and an arm `ucontext` arm for its crash backtrace; the glibc stub has real
A32 bodies. `test/fx` and `test/int` declare `arm32musl` with musl's `crt1.o`
and `libc.a`, vendored by `ci/vendor_musl_runtime.py` from the pinned Zig.

D2's *confirm* item resolves in D2's favor, more strongly than the plan
expected: Zig 0.16's baseline for `arm-linux-musleabihf` is ARMv7-A with NEON,
VFPv3-D32 and Thumb-2, without hardware divide or VFPv4, which is exactly the
floor generated code assumes. The prebuilt objects and generated code share
one floor; `src/target/mod.zig` pins it with a test.

Two practical notes. Zig partial-links (`ld.lld -r`) the raw musl startup
object into the `crt1.o` it links, so its cache holds two `crt1.o` files for
the triple with different float-ABI flags; the vendoring script takes the one
the program's own link line names. And `libc.a` is not byte-reproducible (its
members are named by absolute cache paths), so it is vendored, not checked.

### Words versus 64-bit values (A2)

`LirCodeGen` classifies every 64-bit-looking operand as one of two things.
A *word* (`word`, `word_size`, `listFieldOffset`/`strFieldOffset`,
`wordOffset`) is a usize-typed value: a pointer, a list or string length or
capacity, a refcount, a byte count, an in-bounds index used for address
arithmetic. A *64-bit value* is one whose Roc type is 64 bits (I64, U64, F64
bits) and stays 64 bits on every target (a register pair or memory on arm32).
Both are `.w64` on the 64-bit ISAs, so the classification is byte-identical
there, and arm32's `RegisterWidth` has no `w64`, so every unclassified site is
a compile error for arm32.

One representation invariant makes many sites classifiable locally: a
`ValueLocation.general_reg` never holds more than a word. On the 64-bit ISAs a
word is 64 bits, so nothing changes; on arm32 a 64-bit value is never a single
`general_reg` (it lives in memory or, transiently, in a register pair), so
storing or spilling a `general_reg` is always a word-sized access. Immediate
locations (`immediate_i64`) are different: they can carry a genuine 64-bit
value and stay 64-bit.

The list and string builtins take their Roc `U64` counts and indices as
`u64` and narrow them to `usize` themselves (saturating, so an index past
2^32 is past the end). The driver therefore passes those operands as 64-bit
values and never narrows them; the wasm32 backend's `i32_wrap_i64` does, and
miscompiles (see the issues note). The driver crosses the boundary in only
two directions: a `usize` result that Roc types as `U64` (`List.len`,
`List.capacity`) goes through `wordAsU64`, and an index that the operation's
contract puts in bounds is read as its low word.

Integer arithmetic follows the same split. `generateIntBinop` handles an
integer that fits one register, at most a word: sub-word integers are computed
in the full register and narrowed by `word_bits - n` shifts, and overflow is
decided by `intOverflowCheck`, a pure function of the layout that returns
either the type's range (sub-word) or `word_flags` (word-sized: the flags, or a
multiply's high product). So on arm32 an I32 takes the flag path that I64
takes on the 64-bit ISAs, without naming either type. An integer wider than
the word (I64/U64 on arm32) never enters that path: on 32-bit targets only,
`generateIntBinop` sends it to `generateWide64IntBinop` (see "Wide64
lowering" below). Shift counts are masked for word-sized
types too, because an A32 register shift by 32 or more gives zero rather than
wrapping the count.

Conversions follow the same rule, reading both widths from
`numeric_conversion.getConversionSpec`: within the word they extend or mask by
`word_bits - n`; with a side wider than the word they go to
`generateWide64IntConversion`. An unsigned source narrower than the word
converts to float with the signed instruction, a word-sized one with the
unsigned conversion, so U32 moves to the unsigned path on arm32.

A site that holds a 64-bit value in one register and has no generic form yet
names `wide64_reg_width` instead of `.w64`. It equals `word` on the 64-bit
targets and is a compile error on 32-bit ones, so `grep wide64_reg_width` is
J1's list of `Wide64` sites to lower as pairs, beside `binaryIs` and the
`generateWide64*` entry points.

### Wide64 lowering (J1d)

A `Wide64` is memory-resident: a `.stack` location of size `.qword`, or an
`immediate_i64`/`immediate_f64`. Each operation loads the operands into
register pairs (`loadWide64Pair`, low word first), computes, and stores the
result to a fresh slot (`storeWide64Pair`), so no pair outlives one operation
and the one-word `general_reg` invariant holds. `wide64StackOffset` gives the
eight bytes of any `Wide64` location, storing an immediate or an F64 register
first.

- Add and subtract are `ADDS`/`ADCS` and `SUBS`/`SBCS`; the final flags give
  overflow exactly as a 64-bit instruction would (`vs` signed, `hs` for an
  unsigned add, `lo` for an unsigned subtract), and
  `finishWide64Overflowing` then returns the flag, crashes or wraps as
  `generateIntBinop` does for a word.
- A wrapping multiply is `UMULL` plus two `MLA`s. A checked one builds the
  full 128-bit unsigned product (`UMULL`, `UMLAL`, `UMULL`, the carry, then
  `UMLAL`); a signed product's high half subtracts each operand where the
  other is negative, and the product fits when that half is the low half's
  sign spread.
- Division, remainder and modulo call `__aeabi_ldivmod`/`__aeabi_uldivmod`
  (quotient r0:r1, remainder r2:r3), after the zero and `MIN / -1` crash
  checks of the checked forms. The helper already returns remainder 0 for
  `MIN % -1`, so only division checks it. Signed modulo adds the divisor to a
  non-zero remainder of the other sign.
- Shifts mask the count to 6 bits and are branchless: a register shift reads
  the count's bottom byte and gives 0 (LSL/LSR) for 32 or more, so the
  cross-word terms `x << (n - 32)` and `x >> (32 - n)` vanish when they should.
  An arithmetic shift right fills with the sign instead, so for `n >= 32` a
  conditional `MOVGE lo, hi, ASR (n - 32)` replaces the low word.
- Compares are `CMP lo; SBCS hi` (with `>` and `<=` swapping operands);
  equality ORs the two words' XORs.
- Unary ops negate with `RSBS`/`RSC`, and bit counts combine the words' counts
  (`clz(hi) + (hi == 0 ? clz(lo) : 0)`, and the reverse for trailing zeros).
- A 64-bit integer converts to a float through `__aeabi_l2d`/`ul2d`/`l2f`/
  `ul2f`, which use the base PCS: the result comes back in r0 or r0:r1 and is
  moved to a VFP register. `f64_to_bits` stores the double and, when `VCMP`
  of it with itself is unordered, overwrites it with the canonical NaN.

`callAeabiHelper` calls them: by symbol for object files and the shim (Zig's
compiler-rt defines them, `roc_default_compiler_rt.o` in a link), by address
when natively executing on an arm host.

### NEON lowering (J1e)

Each SIMD entry point in the driver routes on `comptime isa == .arm32` to a
`...Neon` function (or, for the lane-wise ops, `emitBasicSimdVectorNeon`),
leaving the x86_64 and aarch64 bodies untouched. A vector is a Q register
named by its even low D register; `neonQ` and `neonHigh` give its Q view
and high half.

- 64-bit lanes, where ARMv7 lacks the instruction: equality is `VCEQ.I32`
  combined by AND with its `VREV64.32`; signed `>` is `VQSUB.S64 (b - a)` spread by
  `VSHR.S64 #63`, unsigned `>` is a non-zero `VQSUB.U64 (a - b)`; `>=` is
  the negated swap; min/max select with `VBSL` through that mask; negate,
  abs, abs-diff and the rounding average are composed from subtracts,
  shifts and saturating subtracts.
- Lane indices and U64 scalars: an index is a U64 the op keeps in range, so
  its low word is used (`wordOfInBoundsU64`); a 64-bit lane's scalar or
  result is a Wide64, loaded into or stored from a D register
  (`emitSimdSplatWide64`, `VSTR`).
- `get_lane` looks the lane's bytes up with `VTBL` (an out-of-range index
  gives 0, as on the other targets); `with_lane` selects through a `VCEQ.I8`
  lane mask with `VBSL`.
- Bitmask: `VSHR` to the sign bit, `VMUL` by per-half lane weights, then
  `VPADDL` up to one 64-bit sum per half.
- Shifts duplicate the count's byte with `VDUP.8` (VSHL reads each lane's
  bottom byte; negative counts shift right); the rounding shift is `VRSHL.S`
  by the negated count, with counts of the lane width or more giving 0.
- Sums are a `VPADDL` chain to two 64-bit sums and a `VADD.I64`.
- Carryless multiply has no instruction on ARMv7 (no `VMULL.P64`), so it is
  a 64-step shift-and-XOR loop over Q registers, not the `VMULL.P8`
  composition the plan sketched: simpler to get right, and the dev backend
  does not optimize.
- `simd_store_16`/`simd_append_16` pass the vector's halves and the U64
  index as `u64` pairs.

### Four-word i128 and Dec (J1d)

An i128, U128 or Dec on a 32-bit target is four words in a 16-byte frame
slot, `.stack_i128` (or `immediate_i128`). `i128StackOffset` gives the slot
of any operand, sign- or zero-extending a word or a Wide64 as `getI128Parts`
does on the 64-bit targets. Each i128 entry point routes on
`comptime word_size < 8` to a `...Words` function:

- add, subtract and bitwise ops chain `ADDS`/`ADCS` (or `SUBS`/`SBCS`, or
  the logic op) over the words, and the final flags give overflow;
- compares chain `CMP`/`SBCS`, equality ORs the words' XORs;
- negate, not, abs, abs-diff, bit counts, narrowing and the minimum and
  zero-divisor checks are word loops;
- multiply, divide, remainder, modulo, shifts, Dec math, conversions to
  float and string, and try-conversions call the existing decomposed
  wrappers, each `u64` half passed as a pair (see "No by-pointer i128/Dec
  wrappers" above). A wrapping i128 multiply uses the checked-multiply
  wrapper, which stores the wrapped product, and ignores its flag.

A genuinely 64-bit memory field written from an immediate
(`StrFromUtf8Layout`'s tags) goes through `emitStoreImm64`, which is already
width-generic: one store on a 64-bit target, two word stores on a 32-bit one.

### Tests follow upstream's practice; where they deviate

New tests follow upstream's practice. A dev backend change gets an eval case
in the shared eval files (`eval_low_level_tests.zig`, `eval_tests.zig`,
`eval_simd_tests.zig`, `rc_conformance_tests.zig`), which every backend runs
and whose results the runner compares; a backend is left out only through the
case's `skip` field. A change visible only through a whole program gets a
program under `test/cli/`, `test/echo/` or `test/fx/` and an entry in the CLI
runner. Code that runs only on values unknown at compile time (an eval case's
constants are folded before the backends see them) is tested by a
`test/fx/runtime_*.roc` program that reads a number from stdin, with its
expected output in `src/cli/test/fx_test_specs.zig`. Unit tests sit in the file they test. There are no per-backend or
arm32-only eval files.

Where arm32 testing deviates from that practice, and why:

- **Encodings are checked against an assembler**
  (`ci/arm32_encoding_oracle.*`, the generated `encoding_oracle_tests.zig`,
  322 tests), where upstream's x86_64 and aarch64 encoders have hand-written
  tests in `Emit.zig`. A new encoder written from the manual has no other
  independent source of truth; see "Encodings" above.
- **Byte-identity oracles for the 64-bit targets** (the dev-code-hash request
  in the eval runner, the relative oracle in `.git/verify-tools/`, the
  `dev_object` snapshot hashes). Upstream has no oracle that its x86_64 and
  aarch64 output stays the same; the driver refactor for arm32 needed one.
- **Test parameters that depend on the host's word size.** The deep-nesting
  eval cases whose compilation takes more memory than a 32-bit process can
  address nest 1,000 levels on such a host (`address_bound_depth`), and the
  eval runner reports the wasm evaluator unavailable in a 32-bit process
  (`src/eval/mod.zig`). Upstream's tests never run in a 32-bit process.
- **Generated programs run on arm32**, under qemu and on Raspberry Pis: the
  eval corpus with the runner built for arm32, the host-effects corpus,
  `test/fx` through the CLI runner's `--cross-run`/`--cross-runner` (added
  for arm32), and the int app. Upstream's CI only builds for targets it does
  not run on. These runs are local (`.git/verify-tools/roc/hw_checks.roc`),
  not in CI.
- **The build fuzzer also compiles each program with the dev backend**
  (`test/fuzzing/BuildFuzzDriver.zig`), for every target the dev backend
  supports; upstream's build fuzzer stops after lowering.
- **Line coverage is measured with a tool of our own**
  (`.git/verify-tools/cov/`: Zig's bitcode instrumented by Zig's clang with
  SanitizerCoverage, block pruning off), where upstream uses its kcov fork on
  arm64 hosts. Local only. The target is every line of our code (the arm32
  files and the driver lines this branch added or changed, by `git diff`
  against upstream) that the arm32 build compiles; gaps in upstream's shared
  driver code are listed, not chased.

## Learnings

### Is 32-bit support too tightly coupled to wasm32?

No. The 32-bit data model is shared, and the places that single out wasm32 do
so for wasm-specific reasons. What the dev backend is coupled to is the 64-bit
register and its two existing ISAs. The details:

- **The width model is shared, not wasm-owned.** Layouts, `TargetUsize`,
  static data and string data are parameterized by the target's word size and
  were built so wasm32 could use them; arm32 uses the same code. Nothing in
  LIR or the layout store asks "is this wasm".
- **wasm32 is the only thing that ever exercises 32-bit code, and it shares no
  codegen with the dev backend.** The eval harness lowers every case twice,
  for the host word and for `u32`, but only the wasm backend consumes the
  `u32` lowering, through its own `WasmCodeGen`. The comptime float-bits tests
  check "64-bit native and wasm32" static bytes. So 32-bit *layouts* are well
  tested, but no 32-bit *native* code path is. arm32 will be the first, and
  any width bug in shared native code (object writing, relocation widths,
  DWARF address size, the driver's literal 8s) will surface for the first
  time on arm32, not in wasm testing.
- **Places that name wasm32 where they mean something else**, all checked:
  - `src/builtins/compiler_rt_128.zig` decomposes u128 shifts and widening
    multiplies only when `cpu.arch == .wasm32`. The reason is that the wasm
    builtins link without compiler-rt, not the word size. On arm32 the Zig-
    compiled builtins emit calls to `__ashlti3`, `__multi3` and friends, and
    Zig's compiler-rt exports those on every target, so they link from
    `roc_default_compiler_rt.o` (Track C). No change is needed, but the
    `is_wasm` name hides the real condition.
  - `src/base/ConcurrentU64.zig` treats wasm32 as "no 64-bit atomics"; other
    targets with a 32-bit `usize` fall through to a mutex-guarded counter, so
    arm32 is correct without a change.
  - `src/layout/abi/call.zig` (the shared C-ABI classifier) has `wasm32` and
    `wasm64` targets but no AAPCS32 one; J1 adds `arm32_aapcs_vfp`.
  - `CallingConvention.forTarget` lumps `.arm`, `.wasm32` and `.other` into
    one unsupported arm, and the CLI's LLVM gate (`src/cli/main.zig`) allows
    wasm32 as the only 32-bit target. Both are explicit per-arch decisions;
    J2 revisits them.

### JIT code cannot be a golden oracle

The plan's A0 originally hashed the eval runner's in-process (JIT) dev code
per host. That does not work: in JIT mode `LirCodeGen` embeds absolute host
addresses of static data and runtime functions as immediates
(`nativeStaticDataAddress` feeding `emitLoadImm`), so the bytes change with
address-space layout between runs. The object-file mode references the same
things through relocations and is deterministic, and because the eval corpus
is lowered for a 64-bit word it can be compiled for both 64-bit ISAs from any
host. One host-independent golden file therefore replaces the plan's two
per-host files.

### LIR images drop the layout store's recursive-graph keys

The eval runner normally hands backends a `LirImage` (a relocatable copy of
the lowered program). `lir_image.zig` rebuilds the layout store with an empty
`interned_recursive_graphs` map. The dev object path computes content digests
of layouts (`src/layout/digest.zig`) and needs those keys to terminate the walk
through recursive layouts; without them it panics ("cyclic layout N has no
recursive-graph key"). The hash oracle therefore compiles the live lowering
(`eval.test_helpers.devObjectHashes`), not the image. The image path is a
latent bug for any future consumer that feeds an image to the object path,
and it should be fixed by serializing the keys, not by making the digest
tolerate their absence.

### Procedure symbol names change with every compiler build

A procedure's object symbol is `roc__proc_` plus 128 bits of its
`ProcIdentity`, a content digest that includes the checked-module artifact
keys, and those include `compiler_artifact_hash`, which `build.zig` derives
from the git revision. So an object containing any procedure changes its bytes
on every commit even when code generation is identical. The ten original
`dev_object` snapshots never noticed, because none of them compiles a
procedure. Rebuilding with two pinned compiler versions and diffing one
object showed that only these names differ: renaming each to its
first-appearance ordinal made the objects identical. The oracles therefore
hash with `ProcIdentity.canonicalizeSymbolNames` applied, and a rebuild under a
different compiler version leaves all 16 snapshots and all 1961 eval hashes
unchanged. A naive golden hash of generated objects would have failed on the
first commit after it was recorded.

### The register budget is already tight on 64-bit targets

Temporary registers are now allocated by each ISA's `CodeGen`
(`allocTempGeneral`/`allocTempFloat`), which records a high-water mark: the
most registers in use at once when a temporary was taken, pinned registers
included, since they shrink the budget too (D10). `MAX_TEMP_GENERAL` and
`MAX_TEMP_FLOAT` are the allocatable pool sizes. Measured once over the eval
corpus compiled for both ISAs (1961 cases):

| ISA | General peak / pool | Float peak / pool |
|-----|---------------------|-------------------|
| x86_64 (System V) | 12 / 13 | 3 / 16 |
| aarch64 | 12 / 25 | 3 / 32 |

arm32's pool is 11 (r0-r10, D5), and every 64-bit temporary takes two. The
selection sequences written for 64-bit registers already need twelve live
general registers, so arm32 cannot reuse them: the heavy sequences (i128
multiply, checked i64 multiply, wide struct returns) must be lowered through
memory operands or runtime calls, as D6/D7/D10 require, and J2 asserts the
arm32 high-water mark stays within its pool. The measurement was taken with
temporary instrumentation that is not in the tree; rerun it by reading
`general_high_water`/`float_high_water` after compiling.

J2 measured arm32 the same way, over every program it builds: the 121 fx
programs, the int app, the SIMD differential corpus, `baseline_cpu_smoke.roc`
and the 16 `dev_object` snapshot sources.

| ISA | General peak / pool | Float peak / pool |
|-----|---------------------|-------------------|
| arm32 (AAPCS32) | 9 / 11 | 7 / 12 |

J3a extends the measurement to the eval corpus, which the arm32 compiler
compiles and runs in process. Two lowerings exceeded the pool there, and
both now have arm32-specific sequences that use fewer registers (the 64-bit
targets keep their sequences, so their bytes do not change):

- A string-interpolation pattern holds the source string's four shape
  registers, a cursor and the capture start across its steps. Copying a
  small capture took four more temporaries, 11 in all, plus whatever the
  procedure had live. `emitStoreSmallStrCaptureWordPair` copies the bytes
  last to first with the capture length as the counter, through two
  temporaries.
- The wrapping 128-bit multiply called the checked multiply wrapper, which
  stores a saturated value on overflow, not the wrapped product (a
  miscompile, not a budget problem, found by the same run).
  `emitI128MulWrapWords` computes the low 128 bits from 32-bit words with
  one `UMAAL` per partial product, through four registers.

The general peak is `dev_object_many_args` (argument marshalling). The float
peak is the NEON lowering in the SIMD corpus. Before J2, the checked 64-bit
multiply (`emitWide64MulChecked`) held both operand pairs in registers and
reached 11 / 11. It now reads each operand word from memory when it needs it,
so it holds 8 registers at most. No build hit an exhausted pool, which would
panic rather than miscompile.

### Snapshot inputs must exercise code generation

Two properties of `type=dev_object` snapshots decide whether a new snapshot
tests anything:

- A provided value with no arguments is evaluated at compile time and emitted
  as data (that is what `dev_object_static_data_exports` checks), so a
  snapshot only exercises code generation if its provided entry point is a
  function the host calls with arguments.
- The snapshot tool reports no diagnostics for these files. A type error turns
  the definition into `<runtime_error>` in the MONO section, and the tool
  happily hashes the resulting object. Every new snapshot has to be checked
  for `<runtime_error>` (or run through `roc check`) before its hashes are
  trusted. Recursive types, for example, must be nominal (`:=`); a recursive
  structural alias is rejected.

### Snapshot hashes must not depend on the compiler's optimize mode

The driver emits runtime validity checks for Box and Str locals only when the
compiler itself is built in Debug (`emitDebugAssertValidBoxLocal`,
`emitDebugAssertValidStrLocal`, gated on `builtin.mode`). A `dev_object`
snapshot whose program has a Box or Str local therefore hashes differently
under a Debug compiler and a ReleaseFast one, and CI runs the snapshot check
in both (`zig-tests`' second, ReleaseFast `run-test-zig` pass). A0's
`dev_object_str_ops` and `dev_object_recursion_rc` did, and failed that pass
on every host. They are removed rather than the gating changed, since the
gating is upstream's code. A new `dev_object` snapshot must avoid Box and Str
locals, or be checked under a ReleaseFast compiler too. The eval-corpus hash
file has the same dependence; it is only ever checked by a Debug runner
(`run-check-dev-code-hashes`), and it covers strings (238 cases) and boxes
(125).

### A stored hash of generated code cannot outlive a compiler commit

A procedure's identity (`ProcIdentity`, the digits of its `roc__p` symbol)
is a content hash that includes the compiler's own build hash, which the
build takes from `git rev-parse --short=8 HEAD`. While the identity only
appeared in symbol names, the oracles could rename the symbols before
hashing (`canonicalizeSymbolNames`) and a committed hash file stayed valid
from commit to commit. Upstream `842120f79f` (in #11885) made a failed Debug
check report the procedure by that identity, passed as two 64-bit
immediates, so the identity is now inside the machine code of every
procedure that has such a check. Every eval case has one (each returns a
string). Two compilers built at different commits therefore never produce
the same bytes, and a committed hash file would fail at every commit.

So the committed file and `run-check-dev-code-hashes` were removed. The
check that remains is relative: build two trees as the same compiler
version and compare their hashes. `.git/verify-tools/relative_oracle.py`
does that for an upstream merge, with a `git` shim that answers the build's
one revision query with a fixed string; with it, the merge of `90d093540f`
matched upstream on all 2,219 cases. Any refactor that must not change
64-bit output is checked the same way: its base against its tip.

The `dev_object` snapshots are not affected as long as their programs have
no Str or Box locals (the Debug checks are for those), which is already
the rule above.

### NEON on the ARMv7 floor: what the SIMD ops map to

The 55 SIMD `LowLevel` ops must be native on arm32 (D2). Most have a direct
ARMv7 NEON instruction on Q registers; the gaps are almost all 64-bit lanes,
which ARMv7 NEON supports only for add, subtract, saturating add/subtract,
shifts and bitwise operations. J1 composes the rest from the encoders above:

| Ops | ARMv7 NEON |
|---|---|
| add/sub (wrap, sat), and/or/xor/not, bit_select | `VADD`/`VSUB`/`VQADD`/`VQSUB` (all sizes), `VAND`/`VORR`/`VEOR`/`VMVN`/`VBSL` |
| shl/shr/shr_zf, shr_rounded by a count | `VSHL`/`VRSHL` by a register of counts from `VDUP` (a negative count shifts right); all sizes |
| min/max, abs_diff, avg_rounded, eq/gt/gte | `VMIN`/`VMAX`/`VABD`/`VRHADD`/`VCEQ`/`VCGT`/`VCGE` for 8-32-bit lanes; 64-bit lanes are composed (compare via `VQSUB.U64` or a subtract and sign spread with `VSHR.S64 #63`, select with `VBSL`) |
| neg_wrap, abs_wrap | `VNEG`/`VABS` for 8-32; 64-bit: `VSUB` from a `VMOV.I8 #0` zero, and a sign-spread `VEOR`/`VSUB` |
| mul_wrap | `VMUL.I8/16/32`; 64-bit lanes from `VMULL.U32`, `VREV64.32`, `VMUL.I32`, `VPADDL.U32`, `VSHL.I64 #32` and `VMLAL.U32` |
| mul_high, mul_wide_lo/hi, mul_q15_sat | `VMULL.S/U` on the D halves, `VSHRN`/`VUZP`; `VQRDMULH.S16` |
| dot_pairs(_sat), sad, pairwise_add_widen, sum_lanes(_wrap) | `VMULL` + `VPADD`/`VPADDL`/`VPADAL` chains, `VQADD`; `VABDL` + `VPADAL`; `VPADD` on D halves |
| interleave, even/odd lanes, reverse_lanes | `VZIP`/`VUZP` (both operands are rewritten in place), `VREV64` + `VEXT #8` |
| table_lookup, concat_shift_bytes | two `VTBL.8` over a `{Dn, Dn+1}` table (out-of-range indices already give 0), `VEXT.8` |
| widen, narrow_wrap/sat | `VMOVL` (`VSHLL #0`), `VMOVN`/`VQMOVN`/`VQMOVUN` |
| bitmask | `VSHR` to the sign bit, `VAND` with a bit-weight constant, `VPADD` chains, core move |
| splat, get/with_lane, load/store, u128 bits | `VDUP` (core or lane), `VMOV` lane↔core, `VMOV` D↔core pair for 64-bit lanes, `VLD1`/`VST1.8` (no alignment requirement), `VMOV` D↔core pairs |
| clmul_lo/hi | a 64-step shift-and-XOR loop over the multiplier's bits (ARMv7 has no 64-bit polynomial multiply, D2) |

### A32 encoding facts that bit, or would have

- A Q register has no encoding of its own: `Qn` is written as the D
  register of its low half (`D:Vd = 2n`), and bit 6 selects the Q form.
- `VSHL`/`VRSHL` by register take the shift counts in `Vn` and the value in
  `Vm`, the reverse of the other three-register operations' operand order.
- `VMOVN`, `VQMOVN`, `VSHRN` and friends encode the destination's lane size,
  while their assembler suffix names the source's (`VMOVN.I16` has size 8).
- An immediate right shift of `n` bits encodes `2 * esize - n` in `imm6`
  (`64 - n` with `L = 1` for 64-bit lanes); a left shift encodes `esize + n`.

- LLVM keeps every `BL` relocatable (`R_ARM_CALL`), even to a local label, so
  the linker can interwork with Thumb. The oracle accepts exactly the
  relocations whose symbol is the branch itself, where the in-place REL
  addend already equals the resolved bytes.
- Immediates such as 4092 have no modified-immediate encoding (4080 does).
- `LDRD`/`STRD` need an even first register and reach only ±255;
  `VLDR`/`VSTR` reach ±1020 in words. Frame layout has to keep 64-bit and
  vector slots near `fp` (D5), and every other access goes through `r12`.
- A single-register `PUSH`/`POP` uses a different encoding (`STR`/`LDR` with
  writeback). The multi-register form asserts at least two registers; the
  8-byte stack alignment makes even-count pushes the normal case anyway.

## Next steps

Every unit of the plan is done. What remains is outside it: the annoyances
listed at the end of `projects/big/arm32-dev-backend-issues.md` (each fixed in
its own commit), the interpreter's hosted calls on arm32 hosts (issues
note), and the wasm oracle on 32-bit hosts (issues note). The hardware
checks were rerun on a Raspberry Pi 5 and pass completely (status table). Every change to the shared driver must keep both
byte-identity oracles unchanged.
