# ARM32 Dev Backend

Line numbers below are as of commit `7d9ba6785c` (2026-09-14), which also
holds the preliminary version of this document that this revision replaces.
`src/backend/dev/LirCodeGen.zig` alone took 101 commits between 2026-08-01 and
that date, so every citation also names the symbol it points at; re-find it
with `rg -n '<symbol>'` rather than trusting the number.

Notation: `D1`-`D12` are the design decisions in "Solution design"; Tracks
`A`-`D` (with `A0`-`A3` as Track A's serial steps) and joins `J1`-`J4` are the
units in "Implementation"; `J3a`-`J3c` are J3's three execution oracles.

## Problem

`RocTarget` (`src/target/mod.zig:420-422`) lists `arm32linux` and `arm32musl`,
and the target layer already knows everything about them: the LLVM triples are
`arm-unknown-linux-gnueabihf` / `arm-unknown-linux-musleabihf` (`toLlvmTriple`,
`:854-855`), `ptrBitWidth` returns 32 (`:901-907`), the glibc loader is
`/lib/ld-linux-armhf.so.3` (`:211`, `glibcProgramInterpreter` `:224-231`), and
`layout.Store` / `base.target.TargetUsize` (`src/base/target.zig:14-51`)
already lay values out for a 4-byte word, which is how wasm32 works today.
Nothing downstream of the target layer serves these two targets:

- **No backend.** `roc build --target=arm32musl app.roc` uses the default
  `--opt=speed` (`src/cli/cli_args.zig:99`; the `--opt` help text at `:419`
  claims `dev` is the default, which is wrong for `roc build`), reaches
  `rocBuildLlvm` (`src/cli/main.zig:9758`) and is rejected at `:9830`: *"roc
  build --opt=speed requires a 64-bit native host target, but arm32musl has
  32-bit pointers"*. `--opt=dev` reaches `rocBuildNative` (`:10106`) and is
  rejected at `:10220`: *"The native object backend does not support the 'arm'
  architecture."* `--opt=interpreter` is native-target-only (`:10585`), and its
  error message tells the user to run `roc build --opt=dev --target=arm32musl`,
  the command this project makes work. `roc run --opt=dev --target=arm32musl`
  is rejected earlier still by `devShimTargetCompatible` (`:6042-6046`), which
  requires the target's arch, OS and pointer width to equal the host's.
  Underneath, the dev backend's `crossCompileDispatch`
  (`src/backend/dev/ObjectFileCompiler.zig:761-804`) instantiates
  `LirCodeGen(target)` only for x86_64/aarch64(_be) (`:782`) and returns
  `UnsupportedTarget` otherwise, as `compileToObjectFile`'s doc comment says
  (`:147`).
- **No runtime objects.** A dev-backend executable links six prebuilt
  per-target objects (`roc_builtins.o`, `roc_builtins_extern.o`,
  `roc_boxy_runtime.o`, `roc_default_runtime.o`, `roc_default_compiler_rt.o`,
  `roc_default_platform.o`). `build.zig` builds them for the entries of
  `cross_compile_builtins_targets` (`build.zig:7812-7827`) into the gitignored
  `src/cli/targets/<name>/`, and the CLI embeds them (`BuiltinsObjects`,
  `main.zig:461-519`). There is no arm32 entry: `BuiltinsObjects.forTarget`
  hands arm32 the *host's* object (`main.zig:526-566`, `.arm32linux,
  .arm32musl => native`; `forTargetExtern` `:570-610` likewise) and the
  default-platform, compiler-rt and boxy tables return `null` (`:652-690`,
  `:707-744`, `:752-808`).
- **No platform declares the target.** `selectExplicitBuildTarget`
  (`src/cli/target_selection.zig:145-155`) refuses a target the platform
  manifest does not list, and no shipped platform lists arm32
  (`test/fx/platform/main.roc:33-43`, `test/int/platform/main.roc:14-25`).

Every `test/snapshots/dev_object_*.md` (10 files) therefore prints
`arm32linux=NOT_IMPLEMENTED` / `arm32musl=NOT_IMPLEMENTED`. The `RocTarget`
enum promises a target the compiler cannot build for. This project makes the
dev backend the first backend that serves it. There is no "fallback to LLVM"
to lose, and AGENTS.md forbids fallbacks in any case: a target is either
served by a backend or rejected with a named diagnostic, which is exactly what
the gates above do.

The `host_lir_codegen_available` doc comment (`LirCodeGen.zig:25513-25518`,
*"32-bit ARM builds intentionally report false for now. The long-term fix is
for dev builds on those targets to route through LLVM ..."*) is about a
different axis: it is keyed on `RocTarget.detectNative()` (`:25511`), i.e. the
machine the *compiler* runs on. That axis is scoped below, and the comment is
rewritten by J3a.

## Scope

**In scope (the target axis):** cross-compiling *to* `arm32musl` and
`arm32linux` from x86_64/aarch64 hosts with `roc build --opt=dev`, producing a
linked executable that runs. Beyond the encoder itself that requires: the
shared driver made 32-bit-capable and ISA-generic (Track A), a from-scratch
A32/NEON encoder under `src/backend/dev/arm32/` (Track B), ELF32 emission
(A3), the arm32 prebuilt runtime objects, `build.zig` entries, test-platform
manifests and host libraries (Track C), a QEMU-based execution lane in CI
(Track D), and the CLI and snapshot-tool gates rewritten with an explicit
`.arm` decision (J2).

**In scope as a test oracle only:** cross-building the compiler's own test
runners for `arm-linux-musleabihf` and running them under `qemu-arm` (J3a). It
is the only way to drive the full eval corpus through `LirCodeGen(arm32musl)`,
and it needs `host_lir_codegen_available` to be true for `.arm` plus the JIT
support that flag switches on (instruction-cache flush, `ExecutableMemory`).
It does **not** make "Roc on arm32 hardware" a supported product: `roc run`,
hot reload, compile-time evaluation and the run shims on an arm32 host are not
criteria. The criteria are exactly J3a's: the arm32 build of the compiler
compiles, and the eval runner, the host-effects runner and `run-test-zig`'s
`LirCodeGen.zig` tests pass under qemu.

**Out of scope, each explicitly rejected with a diagnostic where reached:**
the LLVM backend for arm32 (`--opt=speed`/`--opt=size` keep their diagnostic
at `main.zig:9830`); Thumb-2 code generation (interworking with Thumb-2
*callees* is in scope, see D1); soft-float `arm*eabi` targets (no `RocTarget`
names one); wasm32 (its own backend, `src/backend/wasm/`); i386 (no
`RocTarget` variant); big-endian ARM; an `arm32v1` baseline twin (D2).

## Background

### The dev backend has three tiers, not two

Do not read `LirCodeGen`, `CallingConvention`, `FrameBuilder`, the object
writers and `Dwarf.zig` as architecture-agnostic. The code has three tiers:

1. **Genuinely shared.** LIR walking, layout math, the stack-slot value model,
   the ~68 arch-neutral methods every per-arch `CodeGen` implements with the
   same signature (the *facade*, the only surface the driver should call:
   `emitLoadStack(width, dst, off)`, `emitStoreStack`, `emitMul`/`emitSDiv`/
   `emitUDiv`/`emitCmp(width, ...)`, `emitLoadImm`, `emitJump`/`emitCondJump`,
   `emitPrologueWithAlloc`, `allocStackSlot`, ...; `x86_64/CodeGen.zig:291-575`,
   `aarch64/CodeGen.zig:299-454`), ~15 driver helpers that hide one mnemonic
   behind an arch test (`emitLoad`/`emitStore`/`emitAddRegs`/`emitShlImm`/...,
   `LirCodeGen.zig:19936-20400`), and the per-arch ABI-constant namespace
   `Emit(target).CC` (`PARAM_REGS`, `FLOAT_PARAM_REGS`, `RETURN_REGS`,
   `SHADOW_SPACE`, `RETURN_BY_PTR_THRESHOLD`, `PASS_BY_PTR_THRESHOLD`,
   `SCRATCH_REG`, `BASE_PTR`, `STACK_PTR`, `STACK_ALIGNMENT`;
   `x86_64/Emit.zig:37-60`, `aarch64/Emit.zig:39-57`), which
   `CallingConvention.zig:234` and `FrameBuilder.zig:615` consume as
   `CC_EMIT`. `ObjectFileCompiler.zig` (apart from its gate) and
   `SymbolTable.zig` are shared. `StaticStringData.zig` is already
   width-generic (`word_size = target.ptrBitWidth() / 8`, `:79`;
   `writeSignedWord` `:177-183`).
2. **Per-ISA code living inside the "shared" files.** This is the bulk of the
   project:
   - `LirCodeGen.zig` (27,740 lines) has roughly 230-245 sites that branch on
     the architecture (287 lines mention an arch comparison): ~145 block
     `if (...arch == ...) {..} else {..}`, ~30 inline `if (arch == .x) A else
     B`, ~55 `if` sites with no `else`, and exactly two exhaustive `switch
     (arch)` (`call_stack_alignment` `:721-783`, `host_lir_codegen_available`
     `:25519`). Roughly a third of its functions branch on arch (the exact
     count is regex-dependent).
   - It calls **129 distinct raw ISA mnemonics** through
     `self.codegen.emit.<mnemonic>` on 587 lines (`movRegReg` 71,
     `simdThreeReg` 48, `vexRegRegReg` 19, `cmovcc` 15, `csel` 9,
     `umulhRegRegReg`, `ldrbRegMemSoff`, `movssRegMem`, ...) and names hard
     registers ~330 times (`.RAX` 41, `.XMM0` 22, `.V0` 22, `.R11` 19, `.X0`
     18, `.R12` 17, `.RDX`/`.RCX` 15, `.X20` 14, `.IP0` 13, ...). Examples:
     type and register selection `:699-717`, `:789-810` (these re-spell
     `CC.BASE_PTR`/`CC.STACK_PTR`/`CC.SCRATCH_REG` as literals); pinned save
     registers `:1684-1704` (`X19`/`RBX`, `X20`/`R12`); condition mappers
     `:11228-11278`; i128 multiply `:11432-11470`; hosted-call registers
     `:17179-17180`; `emitShiftRegX86` `:20100-20112` (`.RCX`/`.R11`);
     `emitTrap` `:24268-24274` (`brk()` vs `ud2()`); `movss`/`ldrb` at
     `:25361-25363`, `:25383-25395`.
   - `FrameBuilder.zig` (1,196 lines) is two complete per-ISA implementations
     selected by `is_x86_64`/`is_aarch64` booleans (`:66-79`, ending in
     `@compileError`), with `unreachable` fall-throughs at `:136`, `:165`,
     `:182`, `:198`, `:211`, `:222` and nine `X86_64…`/`Aarch64…` function
     pairs (`:228-579`, `:672-874`).
   - `CallingConvention.zig` (2,889 lines): `CallBuilder` has 17
     `is_aarch64` sites, 11 binary if/else (else = x86_64) and 6
     `if (is_x86_64) ... else if (is_aarch64)` chains with no final else
     (`:1055-1264`), plus `if (comptime !is_x86_64) return;` at `:865`. The
     runtime `CallingConvention` struct itself (`ParamReg`/`ParamRegs` unions
     `:52-60`, `forTarget` `:70-103`, `.arm => unsupportedArchCallingConvention`
     `:101`, a runtime panic `:105-110`) is consumed only by its own tests and
     by a never-read `cc` field in `LirCodeGen` (`:818`, `:1364`).
   - `ObjectWriter.zig:109-114` picks the ELF architecture with an if/else
     chain ending in `error.UnsupportedTarget`; `object/elf.zig` is ELF64-only
     and emits only RELA relocation records (explicit addend field; REL keeps
     the addend in the patched instruction, see D9); `Relocation.zig`'s
     `DataRelocationKind` is `{abs64, rel32, page21, pageoff12}` (`:9-14`),
     switched exhaustively in `elf.zig:323-349`, `object/macho.zig:352-376`,
     `object/coff.zig:394-403` and `RunImage.zig:529-535`; `Dwarf.zig:293`
     writes `address_size` 8 and emits `DW_LNE_set_address`/`low_pc` as `u64`
     with `.eight` relocations (`:179`, `:305`, `:325`; its one test, `:342`,
     asserts `.eight` at `:360-373`).
   - `src/layout/abi/call.zig`, the C-ABI classifier every backend uses for
     host calls (consumers: `CallingConvention.zig`, `LirCodeGen.zig:17226-17231`
     and `:25076-25081`, the LLVM and wasm backends, `main.zig`,
     `eval/host_trampoline.zig`), has `Target = {aarch64, aarch64_macho,
     aarch64_windows, x86_64_sysv, x86_64_windows, wasm32, wasm64}` (`:146-155`)
     and no AAPCS32 (the 32-bit Arm Procedure Call Standard) classifier module
     beside `src/layout/abi/{aarch64,x86_64,wasm}.zig`.
3. **Per-arch encoder modules.** `x86_64/{CodeGen 1092, Emit 2392, Registers
   266, SystemV 135, WindowsFastcall 150}` and `aarch64/{CodeGen 1540, Emit
   2334, Registers 261, Call 177}` lines. A third ISA needs a module of this
   shape from scratch; nothing in x86_64 or aarch64 encoding generalizes.
   (`aarch64_be` is not evidence of sharing: `RocTarget.toCpuArch`
   (`src/target/mod.zig:677-693`) never returns it, so every `.aarch64_be` arm
   in the driver is unreachable from a `RocTarget`.)

Adding arm32 therefore means either writing a third body at every tier-2 site
or first collapsing tier 2 into tier 1. This plan does the latter (Track A),
because a binary `if (arch == .x86_64) A else B` does not fail to compile when
`.arm` arrives: it silently routes arm32 into `B` (into aarch64 at `:699-717`
and `:789-810`; into the *x86_64* path where the test is `!= .aarch64`, e.g.
the float-argument setup at `:12017-12030`), and the no-else sites silently
skip aarch64-only semantics (`finishImage` `:25481`, branch islands
`:20551-20554`/`:14842`/`:22637`, incoming stack copies `:25373-25376`, i128
even-register alignment `:17458`). Relaxing the `@compileError` gate at `:680`
today would *build successfully* and prove nothing, and every
`LirCodeGen(arm32).init` would then panic in safe builds through the dead `cc`
field's `forTarget` call. Zig's exhaustive-switch checking cannot serve as the
checklist until the switches exist: there are two of them in 27,740 lines.

### The real width blocker is the 64-bit register, not the literal 8

`LirCodeGen` hardcodes `target_ptr_size: u32 = 8` (`:689`) and derives
`roc_str_size`/`roc_list_size`/`small_str_max_len` from it (`:692-696`); 152
lines use those constants and ~540 lines carry a standalone literal `8`. A
sampled classification of the literal-8 lines (every 9th hit) is roughly 60%
pointer-word (list/str field offsets `+ 8`/`+ 16`, `allocStackSlot(8)` for
pointer slots, seven `off += 8` copy loops, `(size + 7) / 8` register counts,
`stack_arg_bytes += 8`), 20% genuine 8-byte-value handling (i128 high half at
`+ 8`, `8 => .w64` width arms, f64 store arms) and 20% bit counts and test
constants. `FrameBuilder.zig`'s 24 and `CallingConvention.zig`'s 63 literal 8s
sit inside per-ABI bodies and tests and are not converted; arm32 gets its own
bodies. That audit is real work, but it is the smaller half.

The larger half is that the driver is written against a **64-bit general
register**:

- `.w64` is passed as the operand width on 907 lines, `.w32` on 80.
  (`RegisterWidth` is a per-arch enum: `x86_64/Registers.zig:212` has
  `w8/w16/w32/w64`, `aarch64/Registers.zig:223` only `w32/w64`; driver helpers
  take `comptime width: anytype`, `:19936`.)
- Every integer width ≤ 64 is computed in one 64-bit register and narrowed by
  shifting (`generateIntBinop`: `narrow_signed_shift` 56/48/32 at
  `:10693-10697`, `shift_count_keep` `64 - n` at `:10716-10722`).
- `ValueSize.qword` is the default for `.stack` locations and pointers
  (`:1180-1184`, `:1244-1250`); `stabilize` spills every general register as
  8 bytes (`:1895-1900`).
- i64/u64 are single registers everywhere: `emitUDiv`/`emitSDiv`/`emitUMod`/
  `emitSMod(.w64, ...)` (`:10821-10854`), checked multiply via
  `smulh`/`umulh` or x86 `MUL RDX:RAX` (`:10976-10995`, `:11432-11470`).
- i128/u128/Dec are `I128Parts{low, high}`, two 64-bit registers
  (`:12612-12615`; 193 lines mention `.i128`/`.u128`/`.dec`, 299 mention
  low/high halves; `stack_i128` is "low at offset, high at offset+8",
  `:1250`). The existing `callI128*`/`callDec*` builtin wrappers (`:12104`,
  `:12171`, `:12215`, `:12315`, `:12347`) pass the halves as four `u64`
  scalars, eight AAPCS32 words (`callI128Shift`, `:12374`, passes one
  operand's two halves plus a `u8` count).
- RocStr/RocList are returned in three general registers `ret_reg_0/1/2`
  (`:802-804`; `saveCallReturnValue` `:21155` stores at `:21207-21211`,
  reloads at `:22165-22167`/`:22190-22192`). This is the Roc-internal
  convention for compiled-proc calls (`generateCallToCompiledProc` `:17515`,
  `callCompiledOffsetWithArgInfos` `:24965`), not a C-ABI path.
- `emitLoadImm(reg, value: i64)` is called 243 times.
- i64↔f32/f64 conversions sign-extend to 64 bits and use `.w64` hardware
  conversions (`:3170-3210`); `clz` on `.w64` (`:12486-12487`); 64-bit
  compares of i128 halves (`:12754`); f64 NaN normalisation moves the bit
  pattern through one 64-bit GPR (`emitNormalizeFloatNanInStableLocation`
  `:9407`, `.w64` store at `:9448`).

On arm32 each of these needs either the 32-bit *word* width (pointers,
usize-typed lengths/capacities/indices/refcounts) or a **register pair**
(values whose Roc type is exactly 64 bits), and i128/Dec become four words.
Replacing `8` with `target_ptr_size` and relaxing the gate cannot make this
file host a 32-bit target. D6 names the abstractions Track A introduces.

### Register model: bounded temporaries, not spilling

Do not be misled by `Storage.claimGeneralReg` (`src/backend/dev/mod.zig:200-205`,
panicking *"no free general registers; spilling/reload is not implemented"*):
`LirCodeGen` never uses that type. `rg 'Storage|claimGeneralReg|DevBackend'
src/backend/dev/LirCodeGen.zig` is empty, and `DevBackend`/`Storage`/
`ValueStorage.zig` are legacy re-exports (`src/backend/mod.zig:30-35`) nothing
instantiates. The real model, stated as an invariant in design.md ("Dev
Backend Register Lifetimes", `design.md:13312-13359`):

- every semantic local lives in a frame slot (`emitValueLocal` → `stabilize`,
  *"the result is ALWAYS in a stable location"*, `:1888-1900`;
  `bindAssignedLocal` `:9342-9370` materializes every non-vector value to the
  stack; `ensureStableLocationForLocal` `:9781-9792` allocates a slot for
  every non-zero-sized local);
- general/float registers are short-lived instruction-selection temporaries
  from a bitmask allocator (`allocGeneral` walks `free_general` then
  `callee_saved_available` and returns null, `x86_64/CodeGen.zig:130-141`,
  `aarch64/CodeGen.zig:150-161`), obtained via `allocTempGeneral`
  (`LirCodeGen.zig:18552`), whose exhaustion is a compiler bug: *"LirCodeGen
  invariant violated: bounded instruction selection exhausted the
  general-register pool"*;
- the only register-resident locals are 128-bit vectors, which already have a
  journaled spill path (`spillVectorLocalEntry` `:18571`,
  `spillAllVectorLocals` from `captureStmtEnv` `:1605-1612`);
- design.md forbids adding a spill path: *"Register-pool exhaustion is
  therefore an internal lifetime-invariant failure, not a source-program
  condition and not an invitation for an architecture-specific best-effort
  spill."* (`:13357-13359`).

So arm32 changes the **budget**, not the model. Measured allocatable pools
today: x86_64 SysV 13 (RAX,RCX,RDX,RSI,RDI,R8-R10 + RBX,R12-R15; R11 is
`scratch_reg`, `x86_64/SystemV.zig:106-118`; RBX/R12 are pinned as
result-pointer/RocOps save registers in entry code, `LirCodeGen.zig:1684-1692`),
x86_64 Windows 13, aarch64 25 (X0-X8,X10-X15 + X19-X28; X9 scratch, X16/X17
addressing scratch, X18 platform, `aarch64/Call.zig:136-153`; X19/X20 pinned;
X28 becomes the caller-stack-arg base, `LirCodeGen.zig:799`, `:21717-21723`).
AAPCS32 gives r0-r12; with r11 as frame pointer and r12 (IP) as scratch the
pool is **11**, and **9** once D5's two save registers are pinned (D5 pins no
third register); LR is usable only if saved; and **every 64-bit temporary
costs two**. Known peak-temporary sequences that do not fit: the i128
multiply path holds 7 × 64-bit temporaries (`getI128Parts` `:12627-12629`,
`:11432-11447`), checked i64 multiply 6 (`:10976-10984`), the
struct-in-registers return copies from up to 16 registers (`:21243`), hosted
calls pin two more (`:17179-17180`). In 32-bit terms the i128 multiply alone
needs 14 registers. The consequence (D10) is that i128/Dec arithmetic and
several i64 operations are lowered to memory operands or runtime calls on
arm32, a lowering-strategy change, and that the budget is *measured* with a
debug high-water mark rather than guessed.

### Everything between an object file and a running arm32 binary

- **ELF writer.** `object/elf.zig` (916 lines) is ELF64/RELA-only:
  `CLASS_64` (`:20`), `Elf64_Ehdr` (`:74`), `Elf64_Rela` with `r_info = (sym
  << 32) | type` (`:116-120`, `:807-810`), `e_flags = 0` (`:463`), `.rela.*`
  sections (`:387-396`, `:626-646`), `Architecture = {x86_64, aarch64}`
  (`:123`), relocation-type switches at `:294-349` and `:798-807`. Adding
  `EM_ARM` alone yields an ELFCLASS64 EM_ARM object no linker accepts (D9).
- **Linker.** `src/cli/linker.zig` wraps the embedded LLD (`ld.lld` for ELF,
  `:490`; `-static` for musl, and `-dynamic-linker` from
  `glibcProgramInterpreter` for glibc when the caller passes no `extra_args`,
  `:515-538`; `rocBuildNative` passes `.extra_args = &.{}`, `main.zig:10444`).
  It exists only in LLVM-enabled compiler builds (`llvm_available`, `:27`;
  `link` returns `LLVMNotAvailable` otherwise, `:902-906`). The Linux branch
  passes no arch-specific arguments (the `/machine:` and stack-probe branches
  at `:617-623` and `:654` are Windows `lld-link`), `ld.lld` is expected to
  take the ELF machine from the first input object (external LLD behaviour,
  confirmed by Track C's first arm32 link), and `RocTarget.isStatic()`/
  `glibcProgramInterpreter` already give the right answers for arm32
  (`target/mod.zig:228`, `:655-656`). **No `linker.zig` change is needed**
  beyond an `.arm` case in the interpreter-path test at `:1482-1486`.
  End-to-end validation therefore runs on an LLVM-enabled `roc`, even though
  the dev backend itself needs no LLVM.
- **Default platform and glibc stub.** `src/default_platform/linux_runtime.zig`
  exports `_start` only for x86_64/aarch64 and `@compileError`s for `.arm`
  (`:82-147`; `linuxStartAarch64` asm at `:179-186`); the signal-handler
  backtrace switch has only x86_64/aarch64 ucontext arms (`:336-345`);
  syscalls already go through `std.os.linux` (`:9`). `src/build/glibc_stub.zig`
  emits `ret` for `.arm` (`:21-25`, `:90-101`), which is not an A32
  instruction; it is only reached for glibc cross targets (`build.zig:7498-7503`).
  The builtins are *expected* to be width-clean (`src/builtins/utils.zig`
  branches on `@sizeOf(usize)` at `:291`, `:501`, `:674`, `:697`; wasm32
  builtins build from the same loop, `build.zig:7817`), but wasm32 exercises
  32-bit width, not ARM-specific lowering (64-bit atomics, u128 compiler-rt
  calls), so "the arm32 builtins objects compile at all" is Track C's first
  check.
- **CLI gates and tables.** The gates that reject arm32 (`main.zig:9830` in
  `rocBuildLlvm`, `:10220` in `rocBuildNative`), the Debug-mode panics in
  `devBackendPhaseName`/`devInstructionGenerationPhaseName` (`:9400`,
  `:9414`), the prebuilt-object tables (`:526-808`; the default-platform,
  compiler-rt and boxy tables map `.x64linux => x64glibc` at `:657`, `:711`,
  `:775` while the two builtins tables send it to `native`, `:543`, `:587`,
  so arm32 rows must be explicit in every table), and the
  glibc-cross-only-on-Linux rule (`:10210-10218`), which makes `arm32linux` a
  Linux-host-only build. `target_selection.zig:41-43` already has an explicit
  `.arm32linux, .arm32musl => .other` prong and needs no change.
- **Snapshot tool.** `src/snapshot_tool/main.zig:4097-4102` has its *own copy*
  of the x86_64/aarch64 gate, upstream of `compileToObjectFile` (`:4150`), and
  writes `NOT_IMPLEMENTED` at `:4229-4233`; its error branch at `:4168-4171`
  is a catch-all `else |_|` that also maps *every* compile error to
  `NOT_IMPLEMENTED`. Both it and `crossCompileDispatch` must admit `.arm`
  before any arm32 snapshot line changes.
- **Test platforms.** `test/fx` and `test/int` manifests list only x64/arm64
  targets; musl entries need `crt1.o`, `libhost.a`, `libc.a` under
  `platform/targets/<name>/`. `libhost.a` is cross-built for every entry of
  `linux_cross_targets` = `musl_cross_targets ++ glibc_cross_targets`
  (`build.zig:78`, loop at `:2803-2816`); `crt1.o`/`libc.a` are checked in
  per platform with `git add -f` (`test/{fx,fx-open,int,str}/platform/targets/
  {x64musl,arm64musl}` and `src/glue/platform/targets/`; only the fx copies
  are whitelisted in `.gitignore:62-65`), and the build copies fx's into
  `alloc-count` and `box-model-uniqueness` only (`build.zig:2825-2833`). The
  CLI test runner's cross-target rosters (`src/cli/test/platform_config.zig:47-74`;
  `isKnownCrossTarget` derives from them, `parallel_cli_runner.zig:11246-11251`)
  have no arm32 entry, so `--cross-target=arm32musl` is rejected as unknown,
  and an empty case list exits 0 (`:11541`, `:11589-11595`).

### What the existing test infrastructure can and cannot see

- The eval runner (`src/eval/test/parallel_runner.zig`, `NUM_BACKENDS = 4`
  `:301`) drives the dev backend in-process through `HostLirCodeGen`
  (`eval/mod.zig:19` → `host_lir_codegen_available`), i.e. host architecture
  only, and has no cross-target mode. From an x86_64 or aarch64 host it cannot
  exercise arm32 codegen.
- The `dev_object_*.md` snapshots are the only byte-identity oracle and they
  are thin: 10 programs (an I64 `add(3,4)*2`, string literals, two tag
  matches, a record, static-data exports, a long string, a type-module import)
  with no floats, Dec, lists, closures, recursion or RC helper calls. The
  snapshot tool cross-compiles every `RocTarget` on every CI host and
  Blake3-hashes the object bytes (`snapshot_tool/main.zig:4092-4165`), so it
  checks aarch64 bytes on x86_64 hosts too; `run-check-snapshots` runs on all
  six `ci_zig.yml` matrix hosts (`:408`, `:425-427`).
  `parallel-backend-codegen.md:372` notes there is no other golden-object
  comparison in the suite.
- `zig build run-test-cli -- --suite platforms --cross-target=<t>` builds
  without running (`parallel_cli_runner.zig:16`; `runCrossCompileTest`
  `:2540-2597` passes on "output file exists") and its `roc build` argv has no
  `--opt` (`:2558`), as do the `roc build` steps in `ci_cross_compile.yml`
  (`:67`, `:73`): the cross matrix tests the LLVM path today.
- `ci_cross_compile.yml` already executes cross-built `test/int` binaries on a
  target-arch runner (`test-int-on-target`, `:84-98`, `ubuntu-24.04-arm` for
  arm64). Hosted arm64 runners are not documented to run AArch32 code (recent
  server-class ARM cores are generally reported to omit AArch32 at EL0, user
  mode, so it must not be assumed), and the self-hosted runner in
  `basic_cli_test_arm64.yml` is `workflow_dispatch`-only, downloads a nightly
  instead of building the PR, and has undocumented hardware (`:1-3`, `:15`,
  `:25`). No workflow uses QEMU today (`rg -i 'qemu|binfmt' .github build.zig
  ci` is empty), but `ci/check_baseline_codegen.sh:99-105` already scans
  `.text` words with `python3 ci/count_aarch64_pmull.py` because doing so
  "keeps this working without a cross disassembler, which is not present on
  every runner": the precedent for the encoding oracle in D8.
- `ci_zig.yml:555-602` (`zig-cross-compile`) already builds the whole compiler
  with `zig build -Dtarget=arm-linux-musleabihf` as a PR gate, using the
  LLVM/LLD prebuilts roc-bootstrap ships for that host triple
  (`build.zig.zon:66-70`, `build.zig:8406`). Two consequences: the compiler is
  known to build at 32-bit `usize` for this triple (as it does for the wasm32
  playground, `build.zig:4547-4580`), and the moment
  `host_lir_codegen_available` becomes true for `.arm`, that job compiles
  `LirCodeGen(arm32musl)` and every arm-host JIT path.
- Unit-test styles to mirror: byte-exact encoder tests (`x86_64/Emit.zig` 63
  tests, e.g. `:1624-1631`; `aarch64/Emit.zig` 16, with bit-field comments,
  `:2086-2097`), `CallingConvention.zig` 62 register-assignment tests (all
  x86_64/aarch64 shapes), `Relocation.zig` 8 tests, 6 of them
  `applyRelocations` patch tests (`:443-543`), `elf.zig` 3 (`:823`, `:855`,
  `:877`; only the last asserts relocation types, x86_64 only),
  `ObjectWriter.zig` 13, `FrameBuilder.zig` 13, `LirCodeGen.zig` 42 (all 35
  of their skip guards are hardcoded `builtin.cpu.arch != .x86_64 and !=
  .aarch64`, e.g. `:25909`, `:25931`, `:25977`, `:25992`, `:26034`, not
  `host_lir_codegen_available`).
- **What each host can verify.** Any host, no emulation: `arm32/Emit.zig`
  byte-exact tests; `CallingConvention.zig`/`FrameBuilder.zig` arm32 unit
  tests; `Relocation.zig` `applyRelocations` tests for `R_ARM_*`;
  `elf.zig`/`ObjectWriter.zig` ELF32 tests; `dev_object_*.md` hashes;
  `run-test-cli --cross-target=arm32musl` build-only. Linux x86_64 with
  `qemu-user-static` only: the eval and host-effects runners cross-built for
  `arm-linux-musleabihf` (the JIT-gated tests in `backend/mod.zig:62/154/225`
  and `compile_time_finalization.zig` become live; `LirCodeGen.zig`'s own
  tests only after J3a's skip-guard rewrite); `--cross-run`; the
  `ci_cross_compile.yml` int-app execution.

## Solution design

These decisions are made here, each with a recommended value. The first PR
that depends on a decision confirms it or amends this section in the same PR:
A1 for D5, D6 and D10; A3 for D9; Track B's first batch for D1-D4, D7, D8 and
D11. Items marked *confirm* cannot be verified from the repo alone.

**D1. ISA: A32 only, with Thumb interworking at call boundaries.** Fixed
4-byte instructions keep aarch64's single-word patch model
(`patchPendingCalls` `LirCodeGen.zig:20477-20483`, `patchCallTarget`
`:20493-20500`, `aarch64/CodeGen.zig:840-862` veneers). Every call to a symbol
outside the current code buffer (`roc_builtins.o`, compiler-rt, libc, the
platform host, any of which may be Thumb-2) is a `bl #0` with an `R_ARM_CALL`
relocation so the linker may rewrite `BL`→`BLX` or insert an interworking
veneer; never `R_ARM_JUMP24` and never a hand-resolved displacement. Internal
proc-to-proc calls stay in-buffer (both ends are A32); the aarch64 veneer
scheme is the model when a buffer exceeds the ±32 MiB `BL` range. Function
symbol values have bit 0 clear.

**D2. CPU floor: ARMv7-A + NEON (Advanced SIMD, implying VFPv3-D32, the
Vector Floating-Point unit with 32 double registers) + Thumb-2 interworking,
without the optional `hwdiv` extension.** Rationale: design.md requires every
compiler-backed operation, including the 55 fixed-width SIMD `LowLevel`
members (`src/base/LowLevel.zig:212-269`, mirroring the 53-member
`builtins.simd.Op`), to be implemented natively by *both native dev backends*
with exhaustive dispatch and no fallback call (`design.md:15297-15298`,
`:15321-15325`), and it puts 128-bit vector locals in `vector_reg` locations
(`:13312-13318`, `LirCodeGen.zig:1241`). NEON's Q0-Q15 is the register class
that hosts them. The `hwdiv` extension is optional in ARMv7-A (Cortex-A8/A9
lack `SDIV`/`UDIV`), hence it is excluded; *confirm* the hardware-coverage
claim for this floor (which ARMv7 boards and phones it includes) in the Track
B opening PR, since nothing in the repo supports one.

The floor is recorded once, in `cpuContract` (`src/target/mod.zig:697`; the
`.arm, .other => .{}` prong at `:727` is split so `.arm` gets
`.instruction_features = neon`, leaving `codegen_model` at
`.determined_by_arch_os` so `llvmTargetQuery` names no CPU model and the
`build.zig:80-98` guard, which inspects only the `CrossTarget` literals, is
unaffected; `populateDependencies` pulls in `vfp3`/`d32`). Its purpose is to
make `RocTarget` the single source: `arm32/Emit.zig` gets a comptime assertion
that `RocTarget.arm32musl.requiredRuntimeCpuFeatures()` contains `neon` and
lacks `hwdiv`, and J4's design.md text cites it. It does **not** buy a
run-time check: `requiredRuntimeCpuFeatures` has no consumer outside
`src/target/`, so cross-compiled executables are never feature-checked (true
of every target today), and `host_cpu.zig` only ever downgrades the
*compiler's own host* to a `v1` twin (`nativeTarget` `:164-172`; `.arm` is
skipped at `:108` and `:183`). The test at `:1220-1229` ("arm32 and macOS
arm64 have no v1 twin because Roc names no floor for them") is updated so
arm32 leaves that group; arm32 deliberately has **no `v1` twin**, like
`arm64mac`, whose justification is the hardware-range comment at `:410-413`
(its contract is `.{}`, `:712-713`). The analogy with x86_64's default level
(`x86_64_v3`, `:704`) holds for the codegen side only: generated code sits
above the baseline prebuilt objects, which stay at Zig's architecture baseline
per the comptime guard at `build.zig:80-98`; *confirm* that
`std.Target.arm.cpu.baseline` for `arm-linux-musleabihf` is ARMv7-A +
VFPv3-D16 (no NEON dependence, no `hwdiv`) and pin it with a test so generated
code and prebuilt objects agree. Refcount atomics are `@atomicRmw` inside the
Zig-built builtins (`src/builtins/utils.zig:367`, `:735`); the dev backend
inlines no atomics on any ISA, so `arm32/Emit.zig` needs no `LDREX`/`STREX`/
`DMB` encoders.

Alternative if a NEON-less floor is ever required: an `arm32v1*` twin with
lane-wise scalar SIMD lowering, a separate project. That is the pattern the
existing `v1` twins already follow (baseline x86_64 lacks PCLMUL/AVX2 and
baseline aarch64 lacks PMULL, `mod.zig:708`, `:716`, `:787`;
`ci/check_baseline_codegen.sh:99-105` polices it), so its cost is one more
lane of known work, not a new kind of work. Note also that NEONv1 has no
64-bit polynomial multiply (`VMULL.P8` is 8×8→16; `PMULL` is ARMv8 Crypto), so
`simd_clmul_lo`/`simd_clmul_hi` (`LowLevel.zig:267-268`) are a composed
`VMULL.P8`/`VEOR`/`VEXT` sequence under either floor.

**D3. Float ABI: AAPCS32 VFP variant (hard-float). Not a choice.** It is
fixed by the triples (`gnueabihf`/`musleabihf`) and by every object Roc links.
Rules the encoder and `CallBuilder` implement for C-ABI calls: f32 arguments
in s0-s15, f64 in d0-d7 (d[n] = s[2n]:s[2n+1]), allocated by back-filling (an
f32 takes the lowest free s-register even below a used d-register;
back-filling stops once any VFP argument has gone to the stack); homogeneous
floating-point aggregates (HFA) of 1-4 members in consecutive s/d registers,
returned in s0-s3/d0-d3 (`LirCodeGen.zig:17337-17338` already models the
aarch64 equivalent); f32/f64 scalars return in s0/d0; d8-d15 callee-saved,
d0-d7 and d16-d31 caller-saved. The compiler-rt floating-point *helpers* are
the one exception and use the base PCS (D7). Objects carry
`EF_ARM_ABI_FLOAT_HARD` and `Tag_ABI_VFP_args = 1` (D9).

**D4. Integer ABI facts that break the "one register = 64 bits" model.**
64-bit scalars occupy an even-aligned register pair (r0:r1, r2:r3); by rule
C.3, if the next core register is r3 the argument is rounded to r4 and goes
entirely to the stack, 8-byte aligned, leaving r3 unused. Doublewords are
never split. Rule C.5 splits only *composites* between the remaining core
registers and `[sp]` (a 12-byte, 4-byte-aligned record at r2 goes r2, r3,
`[sp,#0]`). Stack argument slots are 4 bytes; doublewords are 8-byte aligned
on the stack. SP is 8-byte aligned at every public interface (every `BL`),
4-byte internally; Roc uses 8 everywhere for simplicity
(`call_stack_alignment` `:721` gains `.arm => 8`; today every `CC.STACK_ALIGNMENT`
is 16). i64 returns in r0:r1, f64 in d0; any composite larger than 4 bytes
returns via a hidden pointer in r0 that displaces the first argument, so
`RETURN_BY_PTR_THRESHOLD = 4` *for composites* (`needsReturnByPointer`,
`CallingConvention.zig:146-148`, takes only a size and needs an is-composite
input). Composites are never passed by hidden pointer
(`PASS_BY_PTR_THRESHOLD = maxInt`). i128/Dec is four words: r0-r3, or split
per C.5. The Roc-internal three-register str/list return (`saveCallReturnValue`
`:21155`) stays r0-r2 with 4-byte stores at +0/+4/+8; it is not subject to
the C-ABI rule. `CallBuilder`'s `StackArg`/`int_arg_index` model
(`CallingConvention.zig:268-291`) has no notion of pairs, alignment skips or
splits and gains one; `layout/abi/call.zig` gains an `arm32_aapcs_vfp`
`Target` and an `arm32.zig` classifier.

**D5. Register map and Roc-internal ABI** (recommended; confirmed by A1).
`fp = r11`, `sp = r13`, `lr = r14`; `SCRATCH_REG = r12` (IP), excluded from the
allocation mask as R11 and X9 are today (`x86_64/SystemV.zig:106-109`;
`aarch64/Call.zig:136-151`, where X9 is simply absent between `XR` and `X10`,
and `:152-153` for IP0/IP1), and never live across a `BL` because linker
veneers and PLT (procedure-linkage-table) stubs clobber it (AAPCS32, "Core
registers": §6.1.1 in the current 2023Q3 release, §5.1.1 in releases up to
F); LR likewise dead across calls. `PARAM_REGS = {r0,r1,r2,r3}`,
`FLOAT_PARAM_REGS = d0-d7 / s0-s15`, `RETURN_REGS = {r0,r1,r2}` (r0:r1 for
i64; r0-r2 only for the internal str/list path), callee-saved `r4-r10` (r9 is
an ordinary variable register on Linux EABI), callee-saved VFP `d8-d15`.
Result-pointer and RocOps save registers `r9`/`r10` (the X19/X20 and RBX/R12
analogues, `LirCodeGen.zig:1684-1692`); `NULL_OPS_REG` and the hosted-call
function-pointer/table registers (`:25229`, `:17179-17180`) chosen from the
caller-saved set. Frame: `push {fp, lr}; mov fp, sp` first, then `push
{r4-r10}` (the used callee-saved subset) and `sub sp, sp, #frame` padded so SP
stays 8-byte aligned; because `fp` is captured *before* the callee-saved
push, the saved `fp`/`lr` sit at `[fp, #0]`/`[fp, #4]` and **incoming stack
arguments are read fp-relative at `[fp, #8]`** (the x86_64 scheme,
`INCOMING_STACK_ARG_BASE_OFFSET = 8`; a single `push {r4-r10, fp, lr}` would
move them to `[fp, #36 + pad]`), not copied through an X28-style base
register, so no third register is pinned. Resulting temporary pool: r0-r10 =
11, minus r9/r10 where pinned = 9. Addressing ranges differ per form and the
frame code must honour each: word/byte `LDR`/`STR`/`LDRB`/`STRB` reach ±4095
(imm12); `LDRD`/`STRD` (the `Wide64` pair forms), `LDRH`/`STRH`/`LDRSB`/
`LDRSH` reach only ±255 (imm4H:imm4L); `VLDR`/`VSTR` reach ±1020 in multiples
of 4 (imm8 << 2); NEON `VLD1`/`VST1` have no immediate offset at all. Beyond
the range of the chosen form the address is formed into r12 (`add`/`sub r12,
fp, #imm` or `movw`/`movt` + `add`) and the access uses `[r12]`, the arm32
analogue of aarch64's `ldrRegMemSoff` IP0/IP1 path (`aarch64/Call.zig:152-153`).
`arm32/Emit.zig` exposes a per-form `fitsImmediate(width, off)` predicate so
`emitLoadStack`/`emitStoreStack` choose the form, and `FrameBuilder` places
64-bit and vector slots nearest `fp` to keep the short-range forms in reach.
All of these become members of `arm32/Emit.zig`'s `CC` namespace, the seam
`CallingConvention`/`FrameBuilder` already read (D6, A1).

**D6. Width model: `WORD`, `Wide64`, four-word i128.** Track A introduces
three abstractions and classifies every `.w64`, literal-8 and register-pair
site into one of them: (1) `pub const WORD: RegisterWidth` on each per-arch
`CodeGen`/`CC` (`.w64` on x86_64/aarch64, `.w32` on arm32) for every
usize-typed operand: pointers, list/str pointer/length/capacity fields (at
`+0/+WORD/+2*WORD`, derived as `runtime-representation-single-sourcing.md`'s
solution item 2 prescribes), refcount words, indices, stack-slot spills of
pointers, the internal str/list return registers, `emitLoadImm` of usize
immediates; (2) `Wide64`, a driver-level representation for values whose Roc
type is exactly 64 bits (I64/U64/F64 bit patterns): a single register on
64-bit targets, an even-aligned register pair or a memory operand on arm32,
with add/sub/logic/compare/shift-by-immediate lowered to pair sequences,
64-bit shift by a register count either inlined as the standard pair sequence
or routed to `__aeabi_llsl`/`__aeabi_llsr`/`__aeabi_lasr` (decided in Track
B's first batch and recorded in D7), and everything else (division, 64-bit
integer↔float conversion, 64×64→128 products) routed to the runtime helpers
D7 enumerates; (3) i128/u128/Dec as **four words, memory-resident on arm32**,
operated on through new *by-pointer* variants of the `callI128*`/`callDec*`
wrappers (the existing wrappers pass four `u64` scalars, which do not fit
r0-r3). The integer-narrowing scheme in `generateIntBinop`/`ensureInGeneralReg`
becomes parametric in the register width (`reg_bits - 8/16/32`, not
`56/48/32`); `ValueSize` keeps `.qword` for genuine 8-byte values and uses
`WORD` for pointers.

**D7. Runtime helpers a 32-bit codegen needs.** Two calling conventions,
both modelled explicitly by `CallBuilder` as extern-call variants, never
through the C-ABI classifier: (a) *integer helpers*, ordinary AAPCS32:
`__aeabi_idiv`, `__aeabi_uidiv`, `__aeabi_idivmod`, `__aeabi_uidivmod` (32-bit
division; quotient r0, remainder r1); `__aeabi_ldivmod`, `__aeabi_uldivmod`
(64-bit division; dividend r0:r1, divisor r2:r3; quotient r0:r1, remainder
r2:r3, a non-C return convention); `__aeabi_llsl`, `__aeabi_llsr`,
`__aeabi_lasr` (64-bit shift by a register amount; value r0:r1, count r2,
result r0:r1) unless J1 inlines the pair sequence. (b) *floating-point
helpers*, which the ARM Run-time ABI (IHI0043 §4.1.2) defines with the **base
standard PCS even in a hard-float program**: `__aeabi_d2lz`, `__aeabi_d2ulz`
(f64 in r0:r1 → i64/u64 in r0:r1), `__aeabi_f2lz`, `__aeabi_f2ulz` (f32 in r0
→ r0:r1), `__aeabi_l2d`, `__aeabi_ul2d` (r0:r1 → f64 in r0:r1), `__aeabi_l2f`,
`__aeabi_ul2f` (r0:r1 → f32 in r0). The encoder moves operands with `vmov r0,
r1, dN` / `vmov dN, r0, r1` around these calls; D3's d0-d7/s0-s15 rules do
**not** apply to them (VFP `VCVT` handles only 32-bit integers, so every
64-bit integer↔float conversion is one of these calls). Zig's compiler-rt
exports all of the above for `arm-linux-*eabihf` with the base PCS
(*confirm*: `callconv(.arm_aapcs)` in `lib/compiler_rt`), so they come from
`roc_default_compiler_rt.o` (Track C). 64×64→64 multiply is inlined as
`UMULL`/`MLA`/`MLA`; the 64×64→128 `umulh` sites (`LirCodeGen.zig:10993`,
`:11436`) get a four-`UMULL` sequence in `arm32/CodeGen` or a by-pointer
builtin wrapper. i128 div/rem/mod/shift and Dec mul/div stay on Roc's own
builtin wrappers (`LowLevelBuiltins.i128DivRem`,
`src/base/LowLevelBuiltins.zig:86-91`), never on compiler-rt's `__divti3`
family, so no i128-by-value AAPCS32 question arises. The dev backend
references no such symbol today (`rg '__aeabi|__multi3|__divti3'
src/backend/dev` is empty).

**D8. Address materialization and relocations; no literal pools, no GOT
(global offset table).** x86_64 and aarch64 materialize data addresses
position-independently (`leaRegRipRel` + `.rel32` → `R_X86_64_PC32`,
`x86_64/CodeGen.zig:630-639`; `adrp`/`add` + `.page21`/`.pageoff12`,
`aarch64/CodeGen.zig:525-545`), and the same `ld.lld` path links `-shared`
for `output_kind == .shared_lib` (`linker.zig:408`, `:517-528`), where an
absolute relocation in `.text` is a text relocation LLD rejects by default.
arm32 therefore standardizes on: (i) *load the address of rodata symbol S
into rX*: `movw rX, #:lower16:` at P with `R_ARM_MOVW_PREL_NC` (45), `movt rX,
#:upper16:` at P+4 with `R_ARM_MOVT_PREL` (46), `add rX, pc, rX` at P+8. A32
reads PC as the instruction address + 8, so the target value is S − (P+16):
addend −16 on the `MOVW`, −12 on the `MOVT` (in REL form encoded in the
immediates as 0xFFF0 / 0xFFF4). Two new `DataRelocationKind` members,
`arm_movw_prel` and `arm_movt_prel`, handled in `elf.zig addTextDataRelocation`
(`:323`) and `RunImage.zig relocationKindForData` (`:529`), `unreachable` in
macho/coff exactly as `.page21` is for x86_64. (ii) *load a 32-bit constant*:
`movw`/`movt` with no relocation (these immediates are absolute; position
independence comes only from the trailing `add rX, pc`). (iii) *call an
external function*: D1, `R_ARM_CALL` (28), encoded `0xEBFFFFFE` (imm24 = −2,
i.e. the −8 PC bias) in REL form. (iv) *pointer-sized data inside
`.rodata`/`.data`* (pointers in constant lists, string backings): `R_ARM_ABS32`
(2) via `addRodataRelocation`, plus a new `DataRelocationKind.abs32` for the
target-width `local_data` patches (`Relocation.zig:190` hardcodes `.abs64`).
Every symbol Roc references from `.text` is defined in the same link unit, so
no GOT-relative forms are needed.

**Encoding and object oracle.** The pinned Zig ships LLVM's assembler; each
instruction's expected bytes come from `zig cc -target arm-linux-musleabihf
-c t.s` on a one-line `.s` (`.syntax unified / .arch armv7-a / .fpu
neon-vfpv3 / .arm`), read back by a small Python ELF32 reader,
`ci/elf32_reader.py` (the `ci/count_aarch64_pmull.py` precedent), which also
prints ELF32 headers, `e_flags`, section types and `.ARM.attributes` for the
acceptance checks below (on Linux hosts `readelf -h`/`readelf -A` must agree;
they are a cross-check, not the gate, because two of the four CI hosts lack
them). `ci/arm32_encoding_oracle.py` regenerates the expected-byte tables from
the checked-in assembly list `ci/arm32_encoding_oracle.s` into
`src/backend/dev/arm32/encoding_oracle_tests.zig`, committed as ordinary
`expectEqualSlices(u8, ...)` tests with aarch64-style bit-field comments so
`zig build test` needs no external tool.

**D9. ELF32 container and DWARF.** `object/elf.zig` gains an ELF32 path (or a
sibling `elf32.zig` selected by `Architecture`): `Elf32_Ehdr/Shdr/Sym`,
`EI_CLASS = 1`, `EM_ARM = 40`, `e_flags = EF_ARM_EABI_VER5 (0x05000000) |
EF_ARM_ABI_FLOAT_HARD (0x00000400)`, `r_info = (sym << 8) | type`.
Relocation record form is fixed by the first PR that needs it (A3), which
confirms or amends this paragraph: **REL** (`SHT_REL = 9`,
`.rel.text`/`.rel.rodata`/`.rel.debug_*`, addend in the instruction) is what
AAELF32 prescribes and what GNU/LLVM ARM toolchains emit, so it keeps Roc
objects consumable by platform authors' GNU toolchains; **RELA**
(`Elf32_Rela { r_offset: u32, r_info: u32, r_addend: i32 }`) reuses the
writer's existing `.rela.*` plumbing and is accepted by LLD, the only linker
Roc itself uses. Recommended: REL. Emit a `.ARM.attributes` section
(`SHT_ARM_ATTRIBUTES = 0x70000003`, vendor `aeabi`): `Tag_CPU_arch = 10`
(v7), `Tag_CPU_arch_profile = 'A'`, `Tag_ARM_ISA_use = 1`, `Tag_THUMB_ISA_use
= 2`, `Tag_FP_arch = 3` (VFPv3 with D32), `Tag_Advanced_SIMD_arch = 1`,
`Tag_ABI_PCS_R9_use = 0`, `Tag_ABI_align_needed = 1`, `Tag_ABI_align_preserved
= 1`, `Tag_ABI_VFP_args = 1`, `Tag_ABI_FP_number_model = 3`. LLD derives the
output's float-ABI flag from the inputs' `Tag_ABI_VFP_args` and reports a
hard/soft mismatch when both sides declare it; it does not reject an object
that lacks the tag, and it retains only the *first* input's attributes section
in the output (normally `crt1.o`'s), so neither a successful link nor
`readelf -A` on the executable proves Roc's object carries the tag: the
object itself is inspected (J2 makes it inspectable). Emit a local `$a`
mapping symbol at `.text` offset 0 so disassemblers decode A32. No
`.ARM.exidx`/`.eh_frame`: the dev backend emits no unwind information for ELF
today (the only unwind code is Windows COFF xdata/pdata,
`ObjectFileCompiler.zig:424`/`:480`, `ObjectWriter.zig:85-98`, `coff.zig`).
`Dwarf.zig` takes an address width: `address_size` 4 (`:293`), `DW_FORM_addr`
4 bytes, the three `.eight` address relocations (`:179`, `:305`, `:325`)
become `.four` → `R_ARM_ABS32`, `DW_AT_high_pc` stays `DW_FORM_data8` (a
length), and the test at `:342` ("DWARF sections expose every linker-owned
reference", whose width assertions are `:360-373`) is parameterized, not
loosened. `ObjectWriter.zig:109-114` and `elf.Architecture` gain `.arm`.

**D10. Register budget, not spilling.** No spill path is added (design.md
forbids one). A1 adds a Debug-mode high-water mark to
`allocTempGeneral`/`allocTempFloat` and a per-arch `MAX_TEMP_GENERAL`/
`MAX_TEMP_FLOAT` constant in `CC`; the peak observed over the eval corpus and
`test/fx` is recorded per architecture in the PR. Every LIR statement must
compile within the arm32 budget of D5 with 64-bit temporaries counted double;
any sequence that cannot (i128 multiply, checked i64 multiply, the
16-register struct return copy) is re-lowered to memory operands or a runtime
call (D6, D7), never spilled.

**D11. Alignment.** Linux runs with the alignment-check bit clear (`SCTLR.A =
0`, System Control Register), so plain `LDR`/`STR`/`LDRH`/`STRH` tolerate
misalignment, while `LDRD`/`STRD`/`LDM`/`STM`/`VLDR`/`VSTR` take an Alignment
fault on any address that is not 4-byte aligned. On hardware the Linux
kernel's alignment handler *emulates* a faulting `LDRD`/`STRD`/`LDM`/`STM` in
user space by default (a silent, very slow trap visible only in
`/proc/cpu/alignment`) and delivers SIGBUS for `VLDR`/`VSTR` and NEON loads;
user-mode QEMU (6.1+) enforces the same alignment and delivers SIGBUS for all
of them, so QEMU is *stricter* than hardware here (both behaviours are
external knowledge). Roc layouts give u64/i64/f64 8-byte alignment
independent of pointer width (`src/layout/layout.zig:750-751`) and
str/list/box/closure 4-byte alignment on 32-bit targets (`:752-761`,
`src/base/target.zig:24-29`), so the paired forms are safe for every 64-bit
field; byte-packed buffers use two `LDR`/`STR`. `LDRD`/`STRD` additionally
require an even `Rt` with `Rt2 = Rt+1`.

**D12. The host axis (`host_lir_codegen_available` for `.arm`).** Stays
false until J3a. When it becomes true, `HostLirCodeGen = LirCodeGen(arm32musl)`
(`LirCodeGen.zig:25581`) and every comptime consumer become live in the arm32
build of the compiler that `ci_zig.yml:555-602` already performs:
`eval/mod.zig:19`, `compile_time_finalization.zig:445/1170/3697/3905/3936/3951`,
`inspected.zig:2843`, `inspected_run.zig:397`, `host_effects_runner.zig:66/374/384`,
`backend/mod.zig:62/154/225`, `main.zig:6364/6371/6391` and `:15998`,
`defaultRunShimTarget` (`main.zig:6067`, arm32 hosts map to `native`),
`hot_reload.zig:103-109` (`loadU64` relies on the gate being false on 32-bit
hosts), `host_cpu.zig:108/183`, `ExecutableMemory.zig:26-32/:73-77/:143-149`,
and `machine_code_shim/instruction_cache.zig` (`.arm` falls to `@compileError`
at `:117`; the Linux implementation is the `__ARM_NR_cacheflush` syscall,
number `0x0f0002`, r0 = start, r1 = end, r2 = 0, because `mprotect` does not
invalidate the ARMv7 I-cache; the RW-then-RX flow at `ExecutableMemory.zig:237-249`
already satisfies W^X, never writable-and-executable at once).
`RunImage.zig:529-535` needs the D8 kinds. `object_reader.zig` is *not* a
consumer (its sole reference is the re-export at `backend/dev/mod.zig:23`; it
serves the LLVM backend). J3a makes all of this compile and makes the three
runners named in Scope pass under qemu; nothing more.

## Implementation

Work is organized as four independent tracks and four joins. Every unit has an
`Acceptance:` line that is checkable when it lands, on `main`, with `main`
green throughout. Nothing arm32-specific is reachable until J2 flips the
gates.

### Track A — make the driver ISA- and width-generic (behavior-preserving)

Lands first, alone, as a PR series on `main`, before any arm32 code exists.
It is the conflict-prone piece (27,740 lines, ~100 commits/month) and rebases
daily.

**A0. Strengthen the byte-identity oracle first.**
- Add `type=dev_object` snapshots covering what the audit touches:
  `dev_object_float_math.md` (F32/F64 arithmetic, comparisons, F64→I64),
  `dev_object_dec_u128.md` (Dec, U128/I128, 16-byte returns),
  `dev_object_list_ops.md` (List.append/get/len/map with a closure capturing
  two locals), `dev_object_recursion_rc.md` (a recursive Tree with Box,
  forcing incref/decref helpers), `dev_object_many_args.md` (9+ mixed
  int/float arguments so stack args overflow both register files),
  `dev_object_str_ops.md` (Str.concat/split/interpolation on a big string).
  Sources can be lifted from `src/eval/test/eval_tests.zig` and `test/fx/`.
- Add a `--dev-code-hashes <file>` mode to the eval runner that writes (or
  compares) a Blake3 of `CodeResult.code`, `.relocations` and `.symbol_names`
  (`LirCodeGen.zig:1277-1283`) per eval case for the host architecture, and
  check the golden files in as `test/dev_code_hashes/x86_64.blake3` and
  `test/dev_code_hashes/aarch64.blake3`.
- Acceptance: `zig build run-check-snapshots -- --debug && git diff
  --exit-code test/snapshots` passes on every `ci_zig.yml` host; the golden
  hash files exist and the compare mode passes on an x86_64 and an aarch64
  host.

**A1. Arch dispatch: three-way switches and the `CC` seam.**
- Convert every binary arch test to `switch (arch) { .x86_64 => ...,
  .aarch64, .aarch64_be => ..., .arm => @compileError("arm32: TODO") }` with
  no `else`: `LirCodeGen.zig:699-717`, `:789-810`, the ~230 remaining sites
  (`rg -n 'arch == \.|arch != \.|toCpuArch\(\) [=!]= \.' src/backend/dev/LirCodeGen.zig`
  is the list), `FrameBuilder.zig:66-79` and its six `unreachable`
  fall-throughs, `CallingConvention.zig`'s 17 `is_aarch64` sites and `:865`,
  `ObjectWriter.zig:109-114`, `layout/abi/call.zig`'s `Target` selection at
  `LirCodeGen.zig:17226-17231`/`:25076-25081`. Delete the never-read `cc`
  field (`LirCodeGen.zig:818`, `:1364`) and either delete
  `CallingConvention.forTarget`'s runtime struct or give it a real `.arm`
  value so its tests (`:1289-1343`) can gain arm32 twins.
- Move the 587 raw `self.codegen.emit.<mnemonic>` calls (129 distinct
  mnemonics) behind the facade: each becomes a per-arch `CodeGen` method with
  a shared signature (`emitCheckedMul64`, `emitI128Mul`, `emitFloatCmpNaNSafe`,
  `emitTrap`, `emitPcRelAddress`, `emitBranchIslandIfNeeded`,
  `emitFinishImage`, ..., with no-op bodies where an ISA has nothing to do),
  so `rg 'codegen\.emit\.' src/backend/dev/LirCodeGen.zig` is empty.
- Make `LirCodeGen.zig:789-810` read `CC.BASE_PTR`/`CC.STACK_PTR`/
  `CC.SCRATCH_REG` and add the missing members to `Emit(target).CC`:
  `RESULT_PTR_SAVE_REG`, `ROC_OPS_SAVE_REG`, `NULL_OPS_REG`,
  `HOSTED_FN_PTR_REG`, `HOSTED_TABLE_REG`, `ROC_RET_REGS: [3]GeneralReg`,
  `FLOAT_RET_REG`, `CALLER_STACK_ARG_BASE_REG`, `INCOMING_STACK_ARG_BASE_OFFSET`,
  `WORD`, `MAX_TEMP_GENERAL`, `MAX_TEMP_FLOAT`, so `LirCodeGen.zig` names no
  register literal (`rg '\.(RAX|RBX|RCX|RDX|R11|R12|XMM0|X0|X9|X19|X20|X28|IP0|IP1|V0|FP|ZRSP)\b'`
  is empty).
- Add the D10 high-water mark and record the x86_64/aarch64 peaks.
- Acceptance: A0's snapshot and golden-hash oracles unchanged; `run-test-zig`,
  `run-test-eval`, `run-test-eval-host-effects`, `run-test-cli` green; the
  three `rg` checks above return nothing; the `@compileError` gate at `:680`
  is still in place.

**A2. Width parameterization (D6).**
- Derive `target_ptr_size` from `target.ptrBitWidth() / 8`; use `WORD`;
  classify and convert the 152 constant sites and the pointer-word subset of
  the ~540 literal-8 lines, recording the classification of every site in the
  PR (a table or inline tags) so it can be audited; introduce `Wide64` and
  the four-word i128 representation with by-pointer builtin wrappers; make
  narrowing parametric; adopt `runtime-representation-single-sourcing.md`'s
  derived-offset helper for str/list fields (see Related projects).
- Acceptance: identical to A1's (byte-identical output on every 64-bit target
  is the whole point; `WORD == .w64` and `Wide64 == single register` there).

**A3. Width-parametric containers (D9).**
- `object/elf.zig`: ELF32 structures, `r_info` packing, `e_flags`, the REL
  record form (D9's decision, confirmed here), `.ARM.attributes`, `$a`,
  `Architecture.arm`, the R_ARM_* constants, selected by `Architecture` with
  the ELF64 path byte-identical.
- `Relocation.zig`: `abs32`, `arm_movw_prel`, `arm_movt_prel`; arms (or
  `unreachable`) in `elf.zig:323-349`, `macho.zig:352-376`, `coff.zig:394-403`,
  `RunImage.zig:529-535`.
- `Dwarf.zig`: address width parameter; `ObjectWriter.zig:109-114`: `.arm`.
- Acceptance: A0 oracles unchanged; new `elf.zig` tests write an EM_ARM object
  and assert `EI_CLASS == 1`, `e_machine == 40`, `e_flags == 0x05000400`,
  `.rel.text` `sh_type == 9`/`sh_entsize == 8`, and
  `R_ARM_ABS32`/`R_ARM_CALL`/`R_ARM_MOVW_PREL_NC`/`R_ARM_MOVT_PREL` selection;
  the existing `:877` test gains an aarch64 sibling so all three arches assert
  relocation types.

### Track B — the arm32 encoder module (parallel with A)

New files under `src/backend/dev/arm32/`, referenced by nothing until J1, so
they cannot break `main`.

- `Registers.zig`: `GeneralReg` r0-r15 with `fp`/`ip`/`sp`/`lr`/`pc` aliases;
  `FloatReg` as one banked file (s0-s31, d0-d31, q0-q15 with s[2n]/s[2n+1] ⊂
  d[n] ⊂ q[n/2] aliasing) so a single allocator owns all views;
  `RegisterWidth = {w32}` plus whatever the D6 pair helpers need.
- `Emit.zig`: A32 encoders for the scalar, VFP and NEON instructions
  `CodeGen` needs, plus a `CC` namespace with D5's constants and the
  `fitsImmediate` predicate. Land in batches (moves/returns, arithmetic,
  branches/calls, loads/stores, VFP, NEON), each with byte-exact tests from
  the D8 oracle *before* `CodeGen` uses it.
- `Call.zig`: D3-D5 as constants in the shape of `aarch64/Call.zig`.
- `mod.zig`: the shape of `aarch64/mod.zig`.
- Acceptance: every `pub fn` in `arm32/Emit.zig` has at least one byte-exact
  test (`rg -c '^test ' src/backend/dev/arm32/Emit.zig` ≥
  `rg -c '^\s*pub fn ' src/backend/dev/arm32/Emit.zig`);
  `ci/arm32_encoding_oracle.py --check` agrees with the committed
  `encoding_oracle_tests.zig`; `zig build run-test-zig` runs them on every host.

### Track C — arm32 target artifacts (parallel with A and B)

- `build.zig`: add `.{ .name = "arm32musl", .query = .{ .cpu_arch = .arm,
  .os_tag = .linux, .abi = .musleabihf } }` and `arm32glibc` (`.gnueabihf`)
  to **both** `musl_cross_targets`/`glibc_cross_targets` (`:22-31`, covered by
  the baseline comptime guard `:80-98` and the test-platform host-lib loop
  `:2803-2816`) and `cross_compile_builtins_targets` (`:7812-7827`, which
  produces the six embedded objects).
- `src/default_platform/linux_runtime.zig`: an A32 `_start` (`mov r4, sp; ldr
  r0, [r4]; add r1, r4, #4; bl roc_default_linux_start_main; udf #0`, note the
  4-byte argv offset vs `#8` at `:183`) in the export switch (`:82`) and an
  `ArmUContext` (`arm_pc`/`arm_fp`) arm in the backtrace switch (`:336`).
- `src/build/glibc_stub.zig`: real A32 bodies for `.arm` (`mov r0, #0 / bx lr`
  for return-zero stubs; `abort` as `mov r0, #1 / mov r7, #248 / svc #0`,
  `exit_group`).
- `src/cli/main.zig` tables (`:526-566`, `:570-610`, `:652-690`, `:707-744`,
  `:752-808`): explicit `.arm32musl => arm32musl` and `.arm32linux =>
  arm32glibc` rows; no `native` row for arm32 anywhere.
- Test platforms: `arm32musl: { inputs: ["crt1.o", "libhost.a", app,
  "libc.a"] }` in `test/int/platform/main.roc` and `test/fx/platform/main.roc`;
  arm musleabihf `crt1.o` and `libc.a` added with `git add -f` under
  `test/fx/platform/targets/arm32musl/` and `test/int/platform/targets/arm32musl/`
  (plus two whitelist lines in `.gitignore`, `:62-65` pattern, for the fx
  copies); `arm32musl` rows in `src/cli/test/platform_config.zig`
  (`all_cross_targets` `:47`, `targets_with_glibc` `:57`, `targets_fx` `:67`);
  make `parallel_cli_runner.zig` fail, not pass, when `--cross-target` matches
  zero cases (`:11589-11595`).
- Acceptance: `zig build` produces
  `src/cli/targets/arm32musl/{roc_builtins,roc_builtins_extern,roc_boxy_runtime,roc_default_runtime,roc_default_compiler_rt,roc_default_platform}.o`
  and the arm32glibc set; `python3 ci/elf32_reader.py --header --attributes`
  on each prints `Class: ELF32`, `Machine: ARM`, `Flags: 0x5000400`,
  `Tag_ABI_VFP_args: 1`; a unit test pins Zig's arm baseline per D2; `zig
  build run-test-cli -- --suite platforms --cross-target=arm32musl` reports a
  non-zero case count (build-only until J2).

### Track D — CI lanes (parallel; allowed-to-fail until J3 makes them required)

- `ci_cross_compile.yml`: add `arm32musl` to `matrix.target` (`:22`); change
  the int-app build steps (`:67`, `:73`) and the runner's cross-compile argv
  (`parallel_cli_runner.zig:2558`) to pass `--opt=dev` for the arm32 lane
  (today they exercise LLVM); add a `test-int-on-target` row `{ target:
  arm32musl, target_os: ubuntu-24.04, arch: arm32 }` whose first step is
  `sudo apt-get install -y qemu-user-static` (binfmt_misc makes the existing
  `./"$int_app"` invocation work for static musl ELF; otherwise prefix
  `qemu-arm-static`), with `QEMU_CPU=cortex-a9` exported for the step (the
  binfmt path cannot take `-cpu`; the explicit form is `qemu-arm-static -cpu
  cortex-a9`). QEMU's `cortex-a9` (and `cortex-a8`) model is the D2 floor:
  ARMv7-A, NEON, VFPv3-D32, **no** integer divide, so an accidental
  `SDIV`/`UDIV` raises SIGILL in CI. Do not use `cortex-a7`/`cortex-a15`
  (they implement `hwdiv` and VFPv4, so a floor violation runs silently) and
  do not expect d16-d31 use to fault: the D32 register file is part of the
  floor (QEMU model contents are external knowledge; record `qemu-arm -cpu
  help` evidence in the PR).
- `ci_zig.yml:555-602`: extend the existing `arm-linux-musleabihf` lane with
  `zig build build-test-eval-runner build-test-eval-host-effects-runner
  -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseFast` and the
  `qemu-arm-static zig-out/bin/eval-test-runner --timeout 300000` run (J3a),
  plus a second, `-Doptimize=Debug` build of `eval-test-runner` used only for
  the D10 high-water-mark assertion.
- Windows and macOS hosts keep cross-compiling and uploading artifacts only.
- Acceptance: both jobs appear in the PR check list with `continue-on-error:
  true`, and their logs show the `roc build --opt=dev --target=arm32musl` step
  and the `qemu-arm-static` step executed (exit code recorded, not skipped).

### J1 — arm32 `CodeGen` and the driver's `.arm` arms (needs A, B)

- `arm32/CodeGen.zig` implementing the full facade from A1, including the
  NEON lowering of the 55 SIMD ops (its own batch, after scalar), the
  `Wide64` pair helpers, D7's helper calls and D8's address sequences.
- Fill every `.arm => @compileError` left by A1 in `LirCodeGen.zig`,
  `FrameBuilder.zig` (an arm32 `CalleeSavedInfo` and frame body per D5),
  `CallingConvention.zig`'s `CallBuilder` (D4: pairs, C.3 rounding, C.5
  composite splits, VFP back-filling, hidden result pointer, 8-byte SP at
  `BL`, the D7 helper conventions; update the module doc `:3-6` and the
  `packs_stack_args` doc `:47-50` to define packing for both Apple arm64 and
  AAPCS32), `layout/abi/call.zig` (`arm32_aapcs_vfp` + `arm32.zig`),
  `call_stack_alignment` (`.arm => 8`).
- Relax the `@compileError` gate at `LirCodeGen.zig:680`. `crossCompileDispatch`
  and the snapshot tool still exclude `.arm`, so nothing is reachable yet.
- Acceptance: `rg -n 'arm => @compileError' src/backend/dev src/layout/abi`
  is empty; a `test` block inside `LirCodeGen.zig` instantiates
  `LirCodeGen(.arm32musl)` and asserts `CodeGen == arm32.CodeGen(.arm32musl)`,
  `CC.BASE_PTR == .r11`, `CC.SCRATCH_REG == .r12`, `target_ptr_size == 4`,
  `roc_str_size == 12`, `call_stack_alignment == 8`; a test compiles a
  hello-world proc through `LirCodeGen(.arm32musl)` into an object, links it
  with a hand-written A32 `_start` via `zig cc -target arm-linux-musleabihf`,
  and (on a Linux host with `qemu-user-static`) runs it. The SIMD lane and the
  arm32 register-budget measurement need J2's gates and live there.

### J2 — turn cross-compilation on (needs J1, C)

- Add `pub fn supportsTarget(target: RocTarget) bool` to
  `ObjectFileCompiler.zig` beside `crossCompileDispatch` (`:761`) as the one
  arch decision (no such function exists today; `supportsTarget` currently
  names only `TargetsConfig.supportsTarget`, `src/compile/targets_config.zig:231`),
  and make every gate consult it or become an exhaustive `switch
  (classifyCpuArch(...))` with an `.arm` prong that serves the target and
  `.wasm32`/`.other` keeping their diagnostics: `ObjectFileCompiler.zig:782`
  (`crossCompileDispatch`; update the `:147` doc comment to say only wasm32
  returns `UnsupportedTarget`), `main.zig:10220` (`rocBuildNative`),
  `main.zig:9400`/`:9414` (phase names), `snapshot_tool/main.zig:4097-4102`
  (either call `supportsTarget`, or delete the pre-check and rely on
  `compileToObjectFile`'s `UnsupportedTarget`; the error branch at
  `:4168-4171` is a catch-all `else |_|` that maps *every* error to
  `NOT_IMPLEMENTED`, so it must first be narrowed to `error.UnsupportedTarget`
  and propagate everything else, otherwise a real codegen failure would print
  as `NOT_IMPLEMENTED`). `main.zig:9830`/`:9840` stay: LLVM arm32 is out of
  scope and must keep its diagnostic.
- `rocBuildNative` honours `--keep-temp` (`main.zig:10359-10362`, as the LLVM
  path does at `:9983`), so the dev-backend object `roc_app_<target>.o`
  (`:10364`) is inspectable.
- Acceptance: on every `ci_cross_compile.yml` host with an LLVM-enabled
  compiler build (`linker.zig:904`), `roc build --opt=dev --target=arm32musl
  --keep-temp --output=int_app_arm32musl test/int/app.roc` exits 0;
  `python3 ci/elf32_reader.py --header --attributes` on the kept
  `roc_app_arm32musl.o` prints `Class: ELF32`, `Machine: ARM`, `Flags:
  0x5000400`, `Tag_ABI_VFP_args: 1`, `Tag_CPU_arch: 10` and on the executable
  prints `Class: ELF32`, `Machine: ARM`, `Flags: 0x5000400`; under `qemu-arm`
  the executable prints the same stdout as the x64musl build of the same app;
  the same for `--target=arm32linux` on a Linux host (glibc cross builds are
  Linux-host-only, `main.zig:10210-10218`, and the executable additionally
  needs the target system's `/lib/ld-linux-armhf.so.3`); `roc build
  --target=arm32musl` (default `--opt=speed`) still prints the `main.zig:9830`
  diagnostic; `zig build run-check-simd-codegen` gains an arm32 lane that
  cross-builds the exhaustive SIMD corpus with `roc build --opt=dev
  --target=arm32musl` (`ci/check_simd_codegen.sh:95` pattern,
  `design.md:15389-15393`, `build.zig:2985`); a Debug `roc build --opt=dev
  --target=arm32musl` of every `test/fx` and `test/int` program and of the
  `dev_object_*.md` sources never trips the D10 high-water mark above
  `MAX_TEMP_GENERAL`/`MAX_TEMP_FLOAT`.

### J3 — execution oracles (needs J2, D)

arm32 codegen cannot be driven by the eval runner from a 64-bit host, but it
can under user-mode QEMU, and no LLVM differential oracle exists for arm32
(`main.zig:9830`). The oracles that remain, all differential against the
interpreter or against the x86_64/aarch64 dev backends:

- **J3a. The test runners under qemu (primary).** Flip
  `host_lir_codegen_available` for `.arm` (`LirCodeGen.zig:25519`) and make
  every consumer listed in D12 compile. Change all 35 hardcoded skip guards in
  `LirCodeGen.zig`'s tests (`rg -n 'builtin\.cpu\.arch != \.x86_64 and
  builtin\.cpu\.arch != \.aarch64' src/backend/dev/LirCodeGen.zig`; the first
  five are `:25909`, `:25931`, `:25977`, `:25992`, `:26034`) to `if (comptime
  !host_lir_codegen_available) return error.SkipZigTest;` so that `rg` returns
  nothing afterwards. Rewrite the `:25513-25518` doc comment to point at this
  document's Scope. `RocTarget.detectNative()` (`target/mod.zig:507-509`, via
  `fromStdTarget`) already maps an arm/linux host to `.arm32musl` (`:484-489`).
  This lands only after J1/J2 compile cleanly, because `ci_zig.yml:555-602`
  builds the arm32 compiler on every PR.
  Acceptance: `qemu-arm-static zig-out/bin/eval-test-runner --timeout 300000`
  (built with `-Dtarget=arm-linux-musleabihf`) reports zero dev-backend
  fail/wrong_value/crash and the same pass count as the host x86_64 run,
  skips permitted only for cases already tagged `skip.dev`; the host-effects
  runner likewise; `run-test-zig` cross-built the same way reports the
  `LirCodeGen.zig` tests as passed, not skipped; the Debug runner build's D10
  high-water mark never exceeds the arm32 budget. (`fork` under qemu-user is
  expected to work; verify in the first CI run.)
- **J3b. `run-test-cli --cross-target=arm32musl --cross-run`.** Add a
  `--cross-run` flag so `runCrossCompileTest` executes the produced binary
  (via binfmt or an optional `--cross-runner=qemu-arm-static` prefix) and
  applies the same stdout/exit-code checks `runCompiledTest` applies to native
  dev builds.
  Acceptance: on `ubuntu-24.04` with `qemu-user-static`, every `test/fx` and
  `test/int` case passes with stdout identical to the same case's `[dev]` run
  on x86_64.
- **J3c. `ci_cross_compile.yml` int-app lane** from Track D, made required.
  Acceptance: the arm32 artifacts built on all four hosts produce the same
  stdout as the x64musl artifacts.
- Residual risk after J3: user-mode QEMU is *stricter* than Linux on hardware
  for alignment (D11), so an alignment bug that passes under qemu will not
  crash on hardware; what qemu does not reproduce faithfully is cache
  maintenance and memory ordering (the refcount atomics, `__ARM_NR_cacheflush`
  under J3a), so the float-ABI and atomics battery (Tests to add) must run
  once on real AArch32-capable hardware (Raspberry Pi 3/4/5 class) before J4
  locks hashes; whether the self-hosted ARM64 runner's CPU implements AArch32
  at EL0 is checked, not assumed.

### J4 — lock-in and documentation (needs J3)

- Regenerate all 10 (plus A0's) `dev_object_*.md` snapshots. Regeneration is
  pure cross-compilation and works on every host including Windows and macOS;
  landing it *after* J3 is a policy choice (a hash of unverified codegen is a
  regression lock on possibly-wrong output), not a technical dependency.
- `design.md`: the SIMD and ABI sections say "both dev backends" (`:14947`),
  "the native dev backends" (`:15162`), "both native dev backends"
  (`:15297-15298`, `:15321`) and "the AArch64 dev backend" (`:15392-15393`);
  they all become "the native dev backends (x86_64, AArch64, ARM32)", the D2
  floor is added under the target rules, and the `run-check-simd-codegen`
  arm32 lane is documented. `src/backend/dev/mod.zig:6-8` lists supported
  architectures and gains arm32.
- `projects/README.md` indexes this document (it does not today).
- Acceptance: `zig build run-check-snapshots -- --debug && git diff
  --exit-code test/snapshots` passes on all six `ci_zig.yml` hosts (arm32
  object bytes are host-independent); in the regeneration diff only lines
  matching `^arm32(linux|musl)=` change; `rg -c
  'arm32(linux|musl)=NOT_IMPLEMENTED' test/snapshots/` returns 0 matches.

### Landing order and relative size

```
A0 → A1 → A2 → A3 ──┐
B ───────────────────┼─→ J1 ──┐
C ────────────────────────────┼─→ J2 ──┐
D ─────────────────────────────────────┼─→ J3 → J4
```

A: serial on `main`, byte-identical at every step. B, C, D: parallel with A
(B is new files only; D is advisory until J3). J1 needs A and B; J2 needs J1
and C; J3 needs J2 and D; J4 needs J3.

No calendar estimates (no `big/` doc gives them; `projects/README.md:13-14`
sizes them as "weeks"), but the work is lopsided and a reader should not
assume the encoder is the bulk of it:

- **Track A is the largest**: ~230-245 arch sites, 587 raw mnemonic calls over
  129 mnemonics, ~330 register literals, 907 `.w64` sites and ~540 literal-8
  lines to classify, plus the ELF32/DWARF/relocation containers.
- **J1 is second**: an arm32 `CodeGen` of roughly aarch64's size (~1.5k lines
  by analogy) plus the pair/four-word lowering and NEON coverage of 55 ops.
- **Track B**: ~2.3k lines of `Emit` by analogy with aarch64, plus NEON and
  the oracle script.
- **Track C** is mechanical but blocks the executable criterion; **Track D**
  is small.

## Risks

- **Track A's blast radius, and attributing a diff.** A0 exists so that A1
  (dispatch) and A2 (width) can each be proven byte-identical separately; if
  they are merged into one PR a hash diff cannot be attributed. Any golden or
  snapshot diff in Track A is a bug, never an accepted change.
- **Silent mis-routing is the failure mode, not compile errors.** Until A1
  lands, relaxing the gate builds successfully with arm32 routed into aarch64
  or x86_64 code paths. The completion signal for J1 is the empty
  `rg 'arm => @compileError'`, not a clean build.
- **Temporary budget, not spilling.** The x86_64/aarch64 selection sequences
  were written for 13/25 allocatable 64-bit registers; arm32 has 9-11 32-bit
  ones. Peaks are measured (D10) and offending sequences re-lowered; a
  "spill on exhaustion" patch would violate design.md.
- **AAPCS32 argument placement** (even-register pairs, C.3 rounding, C.5
  composite splits, VFP back-filling, hidden result pointer, 8-byte `SP` at
  `BL`) and the **base-PCS float helpers** (D7) are known sources of subtle
  ABI bugs in first ARM32 ports. Every rule has a `CallBuilder` unit test
  *and* a Roc program crossing a real host boundary under qemu (Tests to add).
- **A32 encoder pitfalls to encode as invariants and tests:** PC reads as
  instruction address + 8 in every PC-relative computation (`add rX, pc`,
  `BL`/`B` immediates, the −16/−12 `MOVW`/`MOVT` PREL addends); `LDRD`/`STRD`
  need even `Rt`, `Rt2 = Rt+1` and word alignment (D11); the short immediate
  ranges of `LDRD`/`STRD`/`LDRH`/`VLDR` (D5); s/d/q aliasing is owned by one
  allocator; r12 and lr are dead across every `BL`; `MOVW`/`MOVT` immediates
  are absolute; function symbols have bit 0 clear.
- **The prebuilt-object pipeline is untested for ARM.** The builtins are
  expected to be width-clean, but arm32 is the first 32-bit *native* target
  (wasm32 has no atomics or compiler-rt division calls); Track C's first
  acceptance is that the six objects compile and link.
- **QEMU is not hardware.** Cache maintenance and memory ordering are not
  modelled faithfully (alignment is modelled *more* strictly than Linux, D11);
  one run on real ARMv7 hardware before J4 is required.
- **Concurrent projects.** `parallel-backend-codegen.md` rewrites the same
  proc loop; whichever lands second rebases, and both use A0's byte-identity
  oracle. `runtime-representation-single-sourcing.md` owns the derived-offset
  mechanism A2 needs (Related projects).

## What success looks like

Every criterion below must hold; the project is not done until all do.

- **64-bit output unchanged.** After every Track A PR and after J1-J4:
  `zig build run-check-snapshots -- --debug && git diff --exit-code
  test/snapshots` shows no change to any `x64*`/`arm64*` hash line, on every
  `ci_zig.yml` host; the A0 golden hashes in `test/dev_code_hashes/` match on
  x86_64 and aarch64; `run-test-zig`, `run-test-eval`,
  `run-test-eval-host-effects`, `run-test-cli` and `run-check-simd-codegen`
  are green.
- **No mnemonics, register literals or arch if-tests in the driver.**
  `rg 'codegen\.emit\.' src/backend/dev/LirCodeGen.zig`, A1's register-literal
  `rg`, and `rg -n 'arch == \.|arch != \.|toCpuArch\(\) [=!]= \.'
  src/backend/dev/LirCodeGen.zig` (A1's site list) all return nothing; every
  remaining architecture decision in that file is a `switch (arch)` with no
  `else`; `rg 'arm => @compileError' src/backend/dev src/layout/abi` returns
  nothing.
- **A runnable arm32 executable from every host.** On each `ci_cross_compile.yml`
  host with an LLVM-enabled compiler build (`linker.zig:904`): `roc build
  --opt=dev --target=arm32musl --keep-temp --output=int_app_arm32musl
  test/int/app.roc` exits 0; `python3 ci/elf32_reader.py --header
  --attributes` prints `Class: ELF32`, `Machine: ARM`, `Flags: 0x5000400` for
  the executable and additionally `Tag_ABI_VFP_args: 1` for the kept
  `roc_app_arm32musl.o`; under `qemu-arm` it prints the x64musl build's
  stdout. `--target=arm32linux` does the same from Linux hosts. Plain `roc
  build --target=arm32musl` still prints the `main.zig:9830` diagnostic.
- **Explicit decision at every gate.** `ObjectFileCompiler.supportsTarget`
  exists and is consulted by `crossCompileDispatch`, `rocBuildNative`
  (`main.zig:10220`) and the snapshot tool; `main.zig:9400`/`:9414`,
  `ObjectWriter.zig:109`, `elf.Architecture`, `Relocation.DataRelocationKind`,
  `layout/abi/call.zig Target`, `CallingConvention` and `FrameBuilder` each
  have an `.arm` prong; `.wasm32`/`.other` keep named diagnostics; no
  `else`/`native` catch-all serves arm32 anywhere.
- **The full eval corpus passes on arm32.** The eval runner and host-effects
  runner cross-built for `arm-linux-musleabihf` and run under `qemu-arm`
  report zero dev-backend failures and the host's pass count; `run-test-zig`
  under qemu reports all 35 previously arch-gated `LirCodeGen.zig` tests as
  passed.
- **CI gates.** `ci_cross_compile.yml` builds `arm32musl` with `--opt=dev` on
  all four hosts and executes the artifacts under `QEMU_CPU=cortex-a9` on
  `ubuntu-24.04`; `run-test-cli --cross-target=arm32musl --cross-run` passes;
  both are required for merge.
- **Encoder oracle.** Every `pub fn` in `arm32/Emit.zig` has a byte-exact test
  and `ci/arm32_encoding_oracle.py --check` passes against
  `src/backend/dev/arm32/encoding_oracle_tests.zig`.
- **Register budget.** The D10 high-water mark never exceeds
  `MAX_TEMP_GENERAL`/`MAX_TEMP_FLOAT`: on x86_64 and aarch64 over the eval
  corpus (Debug `run-test-eval`) and `test/fx`; on arm32 over `test/fx`,
  `test/int` and the `dev_object_*.md` sources cross-compiled with a Debug
  `roc build --opt=dev --target=arm32musl` (J2), and over the eval corpus by
  the Debug `eval-test-runner` run under `qemu-arm-static` in the J3a lane.
  The observed peaks are recorded in the PRs.
- **Snapshots.** All `dev_object_*.md` files show a 64-hex-character hash on
  both arm32 lines; `rg -c 'arm32(linux|musl)=NOT_IMPLEMENTED' test/snapshots/`
  is 0.
- **Prebuilt objects.** The twelve `src/cli/targets/arm32{musl,glibc}/*.o`
  objects are built by `build.zig`, are ELF32/EM_ARM/hard-float per
  `ci/elf32_reader.py`, and a test pins Zig's arm baseline (D2).
- **Documentation.** `design.md`'s backend-count statements are updated,
  `src/backend/dev/mod.zig`'s header lists arm32, the
  `LirCodeGen.zig:25513-25518` comment points at this Scope, and
  `projects/README.md` indexes this document.

## How to evaluate the result

### Correctness ideal

Three properties, each enforced mechanically rather than by review. First,
adding an ISA is *exhaustive by construction*: every architecture decision in
the shared driver is a `switch (arch)` or a member of the per-arch `CC`/facade
interface, so a fourth ISA would produce a compile-error checklist, which
today's binary if/else cannot. Second, *byte-identity* for the existing
targets is proven at every Track A step by the snapshot and golden-hash
oracles, so the refactor can be trusted without re-verifying x86_64/aarch64
behaviour. Third, arm32 correctness is *differential*: the same eval corpus
that gates x86_64/aarch64 runs on arm32 under qemu against the interpreter,
the same platform fixtures run under qemu against their expected output, and
the same int app is compared against its x64musl build. What remains
hardware-only after that (cache maintenance and memory ordering, where
user-mode QEMU's modelling differs from hardware) is named and checked once on
real hardware.

### Performance ideal

Zero cost on the existing targets: `WORD`, `Wide64`, the `CC` members and the
facade methods fold at comptime to the instructions emitted today, which is
what byte-identity proves. For arm32, i64 arithmetic and pointer-width
operations are inline pair/word sequences; only division, 64-bit float↔int
conversions, register-count 64-bit shifts (if not inlined), 64×64→128
products and all i128/Dec arithmetic go through helpers or builtins,
mirroring what LLVM emits for the same triple. The Debug high-water mark has
no release cost.

## Tests to add

- **Byte-identity (A0):** the six new `dev_object_*.md` snapshots and the
  eval-runner `--dev-code-hashes` golden files in `test/dev_code_hashes/` for
  x86_64 and aarch64.
- **Encoder (B):** one byte-exact test per `arm32/Emit.zig` emitter in the
  `x86_64/Emit.zig:1624-1631` style with `aarch64/Emit.zig:2086-2097`-style
  bit-field comments, generated and checked by `ci/arm32_encoding_oracle.py`
  against `zig cc -target arm-linux-musleabihf`.
- **AAPCS32 `CallBuilder` unit tests (J1), in `CallingConvention.zig`:**
  `(i32, i64)` → r0, r2:r3 (r1 unused); `(i32, i32, i32, i64)` → r0, r1, r2,
  r3 unused, i64 at `[sp,#0]` 8-aligned; `(i32, i32, {a,b,c: i32})` → r0, r1,
  r2, r3, `[sp,#0]` (C.5 split); `(f64, f32, f64)` → d0, s2, d2 (back-fill);
  nine f64 arguments spill the ninth; a 12-byte composite returned from a
  C-ABI call via the hidden pointer in r0 displacing the first argument; the
  Roc-internal str/list return in r0-r2; the by-pointer i128 wrapper
  placement; `__aeabi_uldivmod`'s r0:r1/r2:r3 return; `__aeabi_d2lz`/
  `__aeabi_l2d` with the f64 operand and result in r0:r1 (base PCS);
  `__aeabi_llsl`'s count in r2; SP 8-byte aligned at every `BL` with an odd
  number of pushed callee-saved registers.
- **Link-and-run conformance (J3):** for each `CallBuilder` shape above, a Roc
  program in `test/fx` or `eval_tests.zig` that crosses a real host boundary
  with that shape (including an `F64 → I64 → F64` round trip), run under
  qemu. These are the only tests that link emitted objects through LLD and
  execute them.
- **Register budget (A1/J2/J3a):** the D10 high-water mark asserted in Debug
  over the eval corpus and `test/fx` for all three ISAs; peaks recorded.
- **Containers (A3):** `elf.zig` ELF32 header/`e_flags`/section-type/
  relocation-type tests; an aarch64 sibling of the `:877` DWARF test;
  `Relocation.zig` `applyRelocations` tests for `R_ARM_CALL`,
  `R_ARM_ABS32`, `R_ARM_MOVW_PREL_NC`/`R_ARM_MOVT_PREL` patching in the style
  of `:465`/`:565`; a `Dwarf.zig` test parameterized over address width.
- **Driver selection (J1):** the `LirCodeGen(.arm32musl)` test block asserting
  the selected types, registers, sizes and alignment.
- **Gate consistency (J2):** a test that the new
  `ObjectFileCompiler.supportsTarget` returns true exactly for the
  `RocTarget`s whose `dev_object_*.md` line is a hash (not `NOT_IMPLEMENTED`),
  for every `RocTarget`.
- **Baseline pin (C):** Zig's `arm-linux-musleabihf` baseline features equal
  the D2 expectation; `arm32/Emit.zig`'s comptime assertion on
  `RocTarget.arm32musl.requiredRuntimeCpuFeatures()`.
- **Skip-guard rewrite (J3a):** all 35 `LirCodeGen.zig` tests that today gate
  on `builtin.cpu.arch` gate on `host_lir_codegen_available`; `run-test-zig`
  under qemu reports them passed.
- **Runner hygiene (C):** `run-test-cli --cross-target=<unknown>` fails, and an
  empty cross-target case list fails.
- **Snapshots (J4):** `dev_object_*.md` with real arm32 hashes; only the
  `arm32*` lines change in the regeneration diff.

## Related projects

- [runtime-representation-single-sourcing.md](runtime-representation-single-sourcing.md)
  — **prerequisite for A2's RocStr/RocList half.** Its solution item 2
  (offsets derived from `@offsetOf` scaled by the target word size, its
  `:101-105`) is the mechanism A2 needs for the `+ 8`/`+ 16` field-offset
  sites (`:13-18`); A2 adopts that derivation rather than introducing a
  second. If that project has not landed first, A2 lands the dev-backend half
  (one `wordOffset(comptime field)` helper) and that project's checklist is
  updated to say so.
- [parallel-backend-codegen.md](parallel-backend-codegen.md) — independent in
  mechanism; both rewrite `LirCodeGen.zig` hot paths (its slice 1 moves the
  proc loop and pending-call patching), so whichever lands second rebases;
  A0's byte-identity oracle serves both. Its per-proc worker split applies to
  `LirCodeGen(arm32)` unchanged.
- `design.md` — edited by J4 as listed there; AGENTS.md makes it the
  authoritative reference, so the three-backend wording and the D2 floor must
  land with J2/J4, not after.
- `projects/README.md` — does not index this document yet. It belongs to none
  of the existing audit batches: it is a capability gap (`RocTarget` names a
  target no backend serves), independent of the other batches except for the
  derived-offset dependency above.

# AI Final Words

The plan is finished and verified. Here is where things stand.

**On the request itself:** the structure verifier had not actually been cancelled. Its result was already in the workflow journal (13 verdicts, 3 extra findings). The four verifiers that looked stalled (facts, driver, link, ABI) were still running and finished a few minutes later, so nothing needed re-running. All 12 agents completed: 71 findings, none refuted, 57 confirmed as written and 14 confirmed with corrections.

**What changed in [arm32-dev-backend.md](projects/big/arm32-dev-backend.md)** (now 1,292 lines, uncommitted on `32-bit-backend`):

- **Problem statement corrected.** No backend can build for arm32 today; there is no LLVM fallback. Every `roc build` path rejects the target with a diagnostic, and no prebuilt arm32 runtime objects, platform manifests, or test-runner rosters exist.
- **The real blocker named.** The driver is written against a 64-bit register (907 `.w64` sites, 587 raw mnemonic calls, roughly 240 binary arch branches), not just an 8-byte pointer constant. Zig's exhaustive-switch checking cannot serve as the checklist because only two such switches exist.
- **Register spilling removed.** The cited `Storage` type is dead code. The real model is stack-resident locals plus a bounded temporary pool, and design.md forbids adding a spill path. The plan now measures the temporary budget instead.
- **Twelve design decisions recorded in the document** instead of a "design note" with no home: A32 with Thumb interworking, an ARMv7-A + NEON floor with no `v1` twin, the fixed hard-float ABI, the AAPCS32 pair and split rules, the register map and frame layout, a `WORD`/`Wide64`/four-word width model, the runtime helper list, PC-relative address materialization, the ELF32 container, and the host-axis boundary.
- **Missing scope added:** ELF32 writer, `abs32` relocation kind, AAPCS32 classifier in the shared C-ABI module, arm32 `_start`, glibc stub fix, six prebuilt objects, test-platform wiring, and a QEMU CI lane. The linker needs no change.
- **Verification restructured** into four parallel tracks and four joins, each with a checkable acceptance line, a landing order that keeps `main` green, and the eval runner cross-built for arm32 under `qemu-arm` as the primary execution oracle.

**Verified by a second five-reviewer pass**, which caught and I fixed: the float-conversion helpers use the soft-float calling convention even in hard-float programs, the QEMU model must be Cortex-A9 rather than Cortex-A7, `readelf -A` on the linked executable inspects `crt1.o` rather than Roc's object, and 35 test skip-guards need rewriting rather than 5.

**Two things I left for you:**

- The document is not yet indexed in `projects/README.md`. The plan notes this; the entry text belongs to whichever batch you want to file it under.
- Six items are marked *confirm* because they cannot be verified from the repository: Zig's ARM baseline features, the hardware coverage of the chosen floor, compiler-rt's helper calling convention, LLD's emulation inference, and the QEMU model contents. Each names the PR that should confirm it.
