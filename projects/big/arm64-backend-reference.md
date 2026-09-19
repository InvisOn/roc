# AArch64 Dev Backend: How It's Built, and What You'd Need to Learn for ARM32

## Context

`roc_32bit` is a **Zig rewrite** of the Roc compiler — not the Rust compiler most Roc docs/discussions describe. There is no `crates/compiler/build/src/generic64/`. The equivalent "dev backend" (Roc's native, non-LLVM code generator — the thing that turns LIR straight into machine code without going through LLVM) lives at `src/backend/dev/`. This document is a reference companion to [`arm32-dev-backend.md`](./arm32-dev-backend.md) — it explains *how aarch64 actually works today* and *why* that plan's design decisions look the way they do, plus what background knowledge the project requires.

## 1. Overview: how the dev backend is organized

```
src/backend/
├── mod.zig                — top-level backend selection glue
├── dev/                   ← the native code generator (x86_64 + aarch64 live here)
│   ├── mod.zig            — generic DevBackend/Storage scaffolding (mostly vestigial)
│   ├── x86_64/            — x86_64-specific: Registers, Emit, CodeGen, SystemV, WindowsFastcall
│   ├── aarch64/            — aarch64-specific: Registers, Emit, CodeGen, Call
│   ├── CallingConvention.zig  (2,889 lines) — shared CallBuilder/CalleeBuilder generics
│   ├── FrameBuilder.zig       (1,196 lines) — shared prologue/epilogue builder
│   ├── ValueStorage.zig       (82 lines)    — shared ValueLoc/NumKind types
│   ├── LirCodeGen.zig         (27,999 lines)— THE driver: LIR → machine code, parameterized
│   │                                          by RocTarget at comptime, riddled with
│   │                                          `if (target.toCpuArch() == .aarch64)` branches
│   ├── ObjectWriter.zig, object/{elf,macho,coff}.zig — hand-rolled object-file writers
│   ├── Relocation.zig, SymbolTable.zig, object_reader.zig
│   ├── ObjectFileCompiler.zig, ExecutableMemory.zig, RunImage.zig, Dwarf.zig, ProcArtifact.zig
├── llvm/   — the alternate LLVM backend (rejects 32-bit targets outright)
└── wasm/   — a *completely separate*, from-scratch WASM code generator (doesn't touch dev/)
```

Zig has no traits. Instead of `impl Backend for AArch64`, each arch is a **comptime generic function returning a specialized struct type**: `aarch64.Emit(target)`, `aarch64.CodeGen(target)`, `CallBuilder(EmitType)`, `LirCodeGen(target)`. "Implementing the interface" means providing the right public declarations (constants, types, methods) that the generic callers expect to find by name — duck typing, checked at compile time via `@compileError` when nothing matches.

Size breakdown of the whole `dev/` backend (~50,900 lines):

| Category | Lines |
|---|---|
| aarch64-specific (`dev/aarch64/*`) | ~4,350 |
| x86_64-specific (`dev/x86_64/*`, for scale) | ~4,074 |
| Shared infra (CallingConvention, FrameBuilder, object writers, relocations, Dwarf, etc.) | ~14,480 |
| `LirCodeGen.zig` alone (shared driver, arch-conditional) | 27,999 |

The per-arch code is a small fraction of the total. The bulk of the effort — and of what ARM32 has to plug into — is the shared driver and infrastructure.

## 2. The aarch64 implementation in detail

Files (`src/backend/dev/aarch64/`):

| File | Lines | Role |
|---|---|---|
| `Registers.zig` | 261 | `GeneralReg`/`FloatReg` enums (X0–X30/ZRSP, V0–V31), `RegisterWidth` (w32/w64) |
| `Call.zig` | 177 | AAPCS64 constants: param/return regs, callee-saved sets, allocation-preference order |
| `CodeGen.zig` | 1,540 | Arch-specific codegen ops, prologue/epilogue glue, **branch-veneer machinery** |
| `Emit.zig` | 2,334 | Raw instruction encoder — 131 public encoding functions |
| `mod.zig` | 38 | Re-exports / target-specialized aliases |

**Registers** are plain `enum(u5)` matching hardware encodings 1:1, with an `.enc()` method and name helpers for disassembly. A separate `RegisterWidth` enum tracks ARM64's `sf` bit (32- vs 64-bit operation).

**Calling convention (AAPCS64)** is encoded three times at different layers: (a) `aarch64/Call.zig` — plain arrays of param/callee-saved registers plus bitmasks for fast register allocation; (b) `aarch64/Emit.zig`'s `CC` struct — thresholds and register roles (`SCRATCH_REG`, `STACK_ALIGNMENT=16`, etc.) consumed by the generic `CallBuilder`; (c) `CallingConvention.zig`'s runtime tagged union, used when the choice between SysV/Win64/AAPCS64 has to happen at runtime rather than comptime (e.g. `packs_stack_args = target.isMacOS()`, capturing that Apple's ABI packs sub-8-byte stack args tighter than Linux does).

**Instruction encoding is 100% raw byte emission** — every instruction is hand bit-packed into a `u32` and appended little-endian. No assembler abstraction. Quirks are handled by hand: e.g. register 31 means `XZR` in shifted-register ops but `SP` in extended/immediate-add ops, so `movRegReg` special-cases SP as source. 64-bit immediates are synthesized via `MOVZ` + up to 3×`MOVK` (16-bit chunks).

**Stack frames**: `FrameBuilder.zig`'s `DeferredFrameBuilder` generates the function body first (to learn which callee-saved registers got used), then synthesizes prologue/epilogue against that bitmask. Small frames use one pre-indexed `stp x29, x30, [sp, #-N]!`; frames ≥1 page get explicit **stack probing** (page-at-a-time, guards against stack-clash attacks); huge frames materialize the size in a scratch register. Callee-saved GPR pairs land at fixed FP-relative offsets. Frame-pointer-omission exists in the code but is currently disabled (`FramePointerPolicy.always`).

**Calls**: `CallBuilder` stages each argument (register/immediate/lea/memory), tracks int/float/stack destination (mirroring AAPCS64's NGRN/NSRN/NSAA counters), and resolves everything with a parallel-move algorithm to handle register-to-register argument cycles correctly. Direct calls emit `bl`; indirect emit `blr`. Because AArch64's `B`/`BL` only reach **±128MB**, `aarch64/CodeGen.zig` implements its own **branch-veneer/island system** — long-range trampolines inserted whenever a call target falls out of direct-branch range.

**Floats**: separate V0–V31 register file, AAPCS64 float param/return in V0–V7, callee-saved V8–V15 (lower 64 bits only).

**i128/structs**: passed/returned in **register pairs** (not by pointer) per AAPCS64 — 128-bit arithmetic uses carry-chained `adc`/`sbc` across the pair; `stp`/`ldp` move the pair atomically. Structs ≤16 bytes pass by value in up to 2 registers; AAPCS64 has no forced pass-by-pointer threshold (unlike Windows x64's strict rule).

## 3. Why this doesn't just "copy-paste" to ARM32

The aarch64 code is the closest template, but several load-bearing assumptions break for a 32-bit ISA:

- **`LirCodeGen.zig` is written against a 64-bit *register*, not just an 8-byte pointer.** `target_ptr_size: u32 = 8` is one hardcoded constant among many, but the deeper issue is structural: every integer ≤64 bits computes through one 64-bit register; i64/u64 are one register each; i128/u128/Dec use a `{low, high}` pair of 64-bit registers; `.w64` appears on ~900 lines vs `.w32` on ~80. A 32-bit ARM register can't hold what the driver currently assumes fits in one register. This needs a `WORD`/wide-value abstraction, not a find-and-replace of the constant `8`.
- **Only two arches are gated today** (`@compileError` unless `x86_64`/`aarch64`/`aarch64_be`), and outside of two exhaustive `switch(arch)` sites, ~230–245 places do a binary `if (arch == .x86_64) A else B` — meaning a naive third arch would silently fall through into one of the two existing 64-bit code paths instead of failing to compile. Every one of those sites needs an explicit third arm.
- **Branch range is much tighter on ARM32.** AArch64's `BL` reaches ±128MB; A32's `BL` reaches only **±32MB**, and A32 immediates use a 12-bit rotated-immediate scheme rather than aarch64's 16-bit `MOVZ/MOVK` chunks. The veneer/island system aarch64 already has to build (point 2, "Calls") becomes more aggressively necessary, not optional.
- **AAPCS32 vs AAPCS64**: different register set (far fewer general registers — the existing planning doc measures ~9–11 usable temp GPRs on ARM32 vs 13 on x86_64 / 25 on aarch64), different struct/i64 passing rules (register *pairs* with specific even/odd alignment rules — AAPCS32's C.3/C.5), hard-float (VFP) vs soft-float ABI choice, and Thumb/A32 interworking at call boundaries.
- **Object format**: today's ELF writer is ELF64/RELA-only; relocation kinds are `{abs64, rel32, page21, pageoff12}` with no 32-bit-specific kinds (`abs32`, ARM's split `movw`/`movt` relocations) defined yet. `Dwarf.zig` hardcodes an 8-byte address width.
- **Register allocation model**: the existing planning doc corrects a common misconception — `Storage.claimGeneralReg`'s spill-panic path is dead code that `LirCodeGen` never calls. The real model is: every local lives in a fixed stack-frame slot, and registers are used only as short-lived, bounded temporaries from a fixed pool during instruction selection. So ARM32 doesn't need a new spilling mechanism — it needs the *temporary-register budget* recomputed for a much smaller register file, and design.md explicitly rules a spill path out of scope.

## 4. What can be learned from the WASM backend

WASM (`src/backend/wasm/`, ~32,750 lines) is the other 32-bit target in this codebase, so it's worth asking directly what transfers. The short answer: **almost nothing at the code level, but two structural lessons matter.**

**It's a fully independent stack, top to bottom — not a variant of the `dev/` driver.** Confirmed by grep: zero references to `LirCodeGen`, `CallingConvention`, `FrameBuilder`, `ObjectWriter`, or `dev/Relocation.zig` anywhere in `src/backend/wasm/*.zig`. It has its own `CodeBuilder.Relocation` type, its own container format writer (`WasmModule.zig`, 8,303 lines — the wasm binary format, not ELF/Mach-O/COFF), and its own code generator (`WasmCodeGen.zig`, 22,207 lines). This is strong evidence for the existing plan's framing: **genuinely different code-generation targets get their own backend; only ABI/CPU-level variants within one ISA family share infrastructure.** ARM32 is the latter case (it shares an ISA family and calling-convention style with aarch64), so it correctly plugs into `dev/` rather than becoming a fourth top-level sibling like `wasm/`.

**It proves the width problem is isolated to the codegen driver, not the layers above it.** `layout.Store`/`base.target.TargetUsize` already lay out Roc values correctly for a 4-byte word — that's exactly how wasm32 works today, and it required no changes to those layers. So when `arm32-dev-backend.md` scopes the work as "generalize `LirCodeGen`'s width assumption," it's not guessing — wasm is a working existence-proof that everything *upstream* of the native-codegen driver is already 32-bit-clean.

**One place it looks like it might transfer, but doesn't: wide-value handling.** WASM has a *native* 64-bit value type (`i64` is a first-class local/stack type in the wasm VM itself — see `WasmLayout.zig:41`), so a Roc `i64` maps directly to one wasm `i64`, with no register-pairing problem at all. For `i128`/`u128`/`Dec`, wasm doesn't do native wide arithmetic either — it classifies them as `.stack_memory = 16` (spilled to linear memory, represented by an `i32` pointer, `WasmLayout.zig:47,142,147`) and calls out to imported host/builtin functions (`roc_i128_div_s`, `roc_dec_mul`, `roc_dec_to_str`, etc. — see the long list of `*_import` fields in `WasmCodeGen.zig`) rather than emitting inline multi-word arithmetic sequences.

That's a genuinely different strategy than aarch64's carry-chained `adc`/`sbc` register-pair arithmetic, and it's worth knowing about even though the existing plan (D6) chose the native register-pair approach for ARM32 rather than punting to memory + helper calls: if the register-pressure or complexity of the native four-word i128 model turns out worse than expected during implementation, "spill wide values to memory and call a builtin helper" is a proven fallback pattern already living in this codebase, not a novel idea that would need to be invented from scratch.

## 5. What you'd need to learn

**ARM/AArch32 architecture and encoding**
- The A32 instruction set: fixed 32-bit instruction words, condition codes and conditional execution, the 12-bit rotated-immediate encoding for immediates (very different from x86's raw immediates and from aarch64's `MOVZ/MOVK` chunking), addressing modes for `LDR`/`STR` (immediate offset, register offset, pre/post-index).
- A32 vs Thumb/Thumb-2: even though the project scope (per the existing plan) targets A32 only with Thumb *interworking* at call boundaries, you need to understand what interworking means at the ELF/branch level (the `BLX`/bit-0-of-address convention) since glibc/crt code may be built as Thumb.
- Branch range limits (±32MB for `BL`) and why that forces a veneer/trampoline strategy, which the aarch64 `CodeGen.zig` already demonstrates the shape of.
- VFPv3/NEON floating point: separate register file (S0–S31/D0–D15 aliasing), hard-float vs soft-float calling conventions, and why the existing plan pins a hard-float (VFP) ABI + NEON floor rather than soft-float.

**AAPCS32 (the 32-bit ARM calling convention)**
- How it differs from AAPCS64: register pairing rules for 64-bit values (an i64 occupies two consecutive registers, with alignment constraints — AAPCS32 rules C.3/C.5), the smaller general-purpose register file, stack alignment requirements, and VFP register conventions for hard-float.
- The specific `__aeabi_*` runtime helper functions the ABI expects for operations hardware doesn't do directly (integer division, some shifts, float↔int conversions) — these need to exist as callable runtime symbols.

**Object file / linking details specific to 32-bit ARM**
- ELF32 container differences from ELF64 (structure sizes, program/section header layout).
- ARM-specific relocation types, particularly the split `movw`/`movt` address-materialization pattern (loading a 32-bit address in two halves) and deciding between `REL` and `RELA` relocation entries.
- `.ARM.attributes` section conventions that record the ABI/CPU floor a binary was built for.

**How this codebase already works — the parts you'll be extending, not designing from scratch**
- Zig's comptime-generic pattern used throughout (`fn Emit(comptime target: RocTarget) type { return struct {...}; }`) — this is how you'll structure a new `arm32/{Registers,Emit,CodeGen,Call,mod}.zig` set that mirrors `aarch64/`.
- `LirCodeGen.zig`'s instruction-selection style and where/how it currently branches on `target.toCpuArch()` — you'll be adding a third arm to dozens of these sites, so reading a representative sample of the existing aarch64 branches (not just the isolated files) is essential before starting.
- `CallingConvention.zig`'s `CallBuilder`/parallel-move argument-staging algorithm and `FrameBuilder.zig`'s deferred-prologue design (body first, then prologue/epilogue against the observed callee-saved set) — both are meant to be reused, not reinvented, by a new arch.
- The existing ELF writer (`dev/object/elf.zig`) and relocation types (`dev/Relocation.zig`) as the base to extend for ELF32 + new relocation kinds.

**Testing infrastructure**
- How target-specific execution testing currently works for x86_64/aarch64 (snapshot tests under `test/snapshots/dev_object_*.md`, test-platform manifests under `test/fx/platform/main.roc` / `test/int/platform/main.roc` declaring which targets a test platform supports) — ARM32 has no row in these yet.
- Since you likely won't have ARM32 hardware, you'll need to get comfortable running generated binaries under **QEMU user-mode emulation** (or an ARM64 CI runner in AArch32-compat mode) as your execution oracle, and understanding where QEMU's behavior can diverge from real hardware (alignment fault handling, atomics) — a risk the existing plan already flags.

## 6. Where the existing planning docs already answer these questions

`arm32-dev-backend.md` (the current doc, not the `.old.md` draft) already works through 12 concrete design decisions (ISA floor, ABI choice, register map, the width/`WORD` model, relocation kinds, alignment rules) and a 4-track implementation breakdown. Read that doc alongside this one — this document explains *why* those decisions look the way they do, by grounding them in how aarch64 (and, for the width problem specifically, wasm32) actually behave today.
