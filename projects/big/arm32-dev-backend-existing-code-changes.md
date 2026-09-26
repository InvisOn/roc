# ARM32 Dev Backend: Changes to Existing Code

Every change the arm32 work has made to code that existed before
`projects/big/arm32-dev-backend.md` was started, with the reason it was
needed and the commit that carries it. New files (the `arm32/` module, the
oracle scripts, the vendored runtime) are not listed. Fixes to defects in
existing code are committed separately from plan milestones; plan milestones
that necessarily edit existing code are listed under their milestone.

Every entry that touches code generation leaves x86_64 and aarch64 output
byte-identical, verified by the A0 oracles (`dev_object` snapshots and the
eval-corpus object hashes) unless the entry says otherwise.

## Fixes to existing defects (separate commits)

### Default-platform glibc builds with `--opt=dev` crashed at startup

`roc build --opt=dev` of a program without a `platform` header, for a glibc
target (`x64glibc`, `arm64glibc`, now `arm32linux`), linked with the
target's C ABI: it requested the glibc program interpreter but, since the
default platform's runtime uses no C library, produced no dynamic section,
so the loader crashed before `main`. The LLVM path already linked such
programs statically (`llvmBuildLinkAbi`). That rule is now `buildLinkAbi`,
used by both backends (`rocBuildNative`, `rocBuildEmbedded`). The existing
default-platform CLI cases built only with `--opt=speed`; they now take the
backend, and a new case builds x64glibc with `--opt=dev` and runs it. Found
while checking J2's `arm32linux` target.

### The snapshot tool mapped every dev compile error to `NOT_IMPLEMENTED`

`processDevObjectSnapshot` called `compileToObjectFile` for each target that
passed its architecture pre-check and turned any error into the
`NOT_IMPLEMENTED` hash (`else |_|`). Since the pre-check already excludes the
unsupported targets, every error there is a real code-generation failure,
which the snapshot silently recorded as "not implemented". It now logs the
error and fails the snapshot. Needed before J2 lets the dev backend compile
arm32, so an arm32 failure cannot be mistaken for an unsupported target. No
effect on passing snapshots.

### Target data sized by the host's `usize` (`654087283b`)

`LirCodeGen` measured target memory with the compiler host's word in three
places: the Debug RocStr validity check's alignment mask (`@alignOf(usize) -
1`), the erased-call descriptor array (`@sizeOf(usize)` per entry) and the
erased-callable heap cell's drop-pointer slot. Needed because a 64-bit host
cross-compiling for a 32-bit target would validate 4-byte-aligned heap strings
against 8-byte alignment (a false Debug crash) and lay out 8-byte slots the
target reads as 4-byte ones. No effect on today's targets.

### Erased-callable layouts taken from the host (`ab6e860e2d`)

`LirCodeGen` wrote erased-callable payloads using `builtins.erased_callable`'s
constants and `@offsetOf`/`@sizeOf` on its structs, which the compiler host
lays out. Those structs hold only pointer-sized fields, so on a 32-bit target
`HotReloadCaptureHeader.original_on_drop` moves from 8 to 4 and
`CompilerMetadata` shrinks from 8 bytes (8-aligned) to 4, while the builtins
compiled for the target read the target layout. Needed because arm32 code
would write erased-callable fields where the target runtime does not look.
The driver now derives every such layout from the builtins struct scaled by
the target word (`erased_layout`), with a compile-time check that each field
is pointer-sized. No effect on today's targets.

### `LargeBlockAllocator` shifted by a 64-bit-host class type

`src/base/LargeBlockAllocator.zig`'s `classCapacity` shifted a `usize` by a
`u6`, which only compiles where `usize` is 64 bits, so the compiler itself
(the eval runner, via `zig build -Dtarget=arm-linux-musleabihf`) did not build
for a 32-bit host. Cached classes never exceed `max_class_log2` (30), so the
shift is cast to `usize`'s shift type after asserting that. Needed for the
Track D/J3a lane that runs the eval corpus on arm32 under qemu. No effect on
64-bit hosts.

### Plan documents failed `run-check-tidy` (`12be3758d5`)

Spaced em dashes and missing or duplicate top-level titles in
`projects/big/arm32-dev-backend*.md` and `arm64-backend-reference.md` made the
tidy check fail on the branch before any code changed. Needed so the tidy
check could gate every later commit.

### Instruction cache not flushed before JIT memory runs (`ee65370868`)

`ExecutableMemory.zig` (J3a, D12): memory is published to the instruction
stream through `instruction_cache.flush` before it is made executable. The
flush (`cacheflush` syscall on arm Linux, `dc cvau`/`ic ivau` on aarch64
Linux, the OS calls on macOS and Windows, nothing on x86) moved from
`src/machine_code_shim/` to `src/backend/dev/instruction_cache.zig` so the
shim and `ExecutableMemory` share it. This also adds the flush on aarch64,
which previously relied on the kernel's maintenance at `mprotect`. The new
`error.FlushInstructionCacheFailed` is added to every error set that
enumerated `ExecutableMemory`'s errors.

### In-process relocations patched by guessing the ISA (`c8b2e8f839`)

`Relocation.zig` (J3a): `applyRelocations`/`applyRelocationsWithContext`
take the ISA the code was generated for, and every relocation site is
patched by that ISA's rule. Before, a `linked_function` site was
recognised by its bytes (an `E8` before the operand meant x86_64, a `bl`
opcode meant aarch64) and every 4-byte `jmp_to_return` was treated as an
aarch64 branch. On arm32 that guess is unsound (an A32 `stmda` has `E8` in
its top byte), and the rule against heuristics forbids it anyway. arm32
patches A32 `bl`/`b` displacements (PC + 8); `local_data` is `abs32` on
arm32. The in-process callers (HostSplice, the machine-code shim) pass the
host ISA; the tests pass the ISA of the bytes they patch.

The same commit adds arm32's rules (A32 `bl`/`b`, `abs32` local data) and
the A32 jump stubs listed under J3a.

### The wasm test ULEB reader did not compile for a 32-bit host (`86c2f646fc`)

`WasmCodeGen.zig` (J3a): the test-only ULEB reader shifts by
`Log2Int(usize)`, not `u6`, so the backend tests compile on a 32-bit host.

### Backend tests assumed a 64-bit host; a literal 8 in entry slots (`4a49f4b51f`)

`LirCodeGen.zig` (J3a): `entrypointParamSlotSize` rounds by the target
word, not a literal 8 (an A2 miss; byte-identical on the 64-bit targets).
Tests that ran only on x86_64/aarch64 hosts now run on every host with a
dev backend: the shift tests build LIR with a `U8` amount, as the shift
builtins do; the narrow-argument observer reads word-sized registers; the
static-root pack test builds its descriptor at the target's word size.

### The wasm eval backend reported available on 32-bit hosts (`eb28c6efb7`)

`eval/mod.zig` and `eval/test/parallel_runner.zig` (J3a): the wasm eval
backend is available only on 64-bit hosts. Roc's wasm modules declare no
memory maximum, so bytebox reserves wasm32's full 4 GiB of linear memory,
which a 32-bit process cannot hold (`Uninstantiable64BitLimitsOn32BitArch`).
The runner asks `eval.backendAvailable(.wasm)` instead of hardcoding true,
so on an arm32 host wasm reports `not_implemented` like an absent backend.

### A wasm merge conflict printed to stderr, failing the backend test step (`3bb3ca2b44`)

`backend/wasm/WasmModule.zig` (annoyance fix): a function-type mismatch
during a module merge is recorded in `merge_type_conflict` (the name and
both type indices) instead of printed to stderr in Debug builds, so the
backend test step stops failing on a passing run. WasmCodeGen's eval
builtin-merge invariant message now names the conflicting function.

### A relative `--cross-runner` path was not found (`a266aab5ed`)

`cli/test/parallel_cli_runner.zig`: cross-built programs run in per-test
work directories, so a relative runner such as `ci/ssh_cross_runner.sh` was
not found. `resolveCrossRunner` keeps bare command names for the `PATH`
lookup and absolute paths as given, and anchors a relative path at the
directory the runner started in, as the runner already does for the roc and
glue binaries.

## Plan milestones that edit existing code

### Track B: encoder and oracle (`8ffd541b71`)

- `.gitignore`: whitelists `ci/arm32_encoding_oracle.s`. Needed because `*.s`
  is ignored repository-wide, so CI would never have received the oracle's
  input and `run-check-arm32-encoding-oracle` would fail there.
- `build.zig`, `src/build/minici.zig`: the `run-check-arm32-encoding-oracle`
  step and minici job, so a stale generated test file fails CI.
- `src/backend/dev/mod.zig`: exports `arm32`, which is how its tests reach
  the backend test binary.

### A0: byte-identity oracles (`61a6d470f2`)

- `src/eval/test/parallel_runner.zig`: `--write-dev-code-hashes` /
  `--check-dev-code-hashes`, sharded over forked children. Needed as the
  golden oracle for Track A's rewrite of the driver.
- `src/eval/inspected.zig`: the live-lowering step is factored out of
  `lowerCheckedRootWithViews` (`lowerCheckedRootLive`) and reused by the new
  `devObjectHashes`. Needed because the LIR image the eval runner normally
  uses drops the layout store's recursive-graph keys, which the object path
  requires.
- `src/build/test_harness.zig`: `writeWholeFile` / `readWholeFile`. Needed
  because tidy bans `std.Io.Dir.cwd()` in core source trees such as
  `src/eval/`, and the shared harness is where runner file I/O lives.
- `src/lir/LIR.zig`: `ProcIdentity.canonicalizeSymbolNames`;
  `src/snapshot_tool/main.zig` hashes canonicalized objects. Needed because
  procedure symbol names digest the compiler build, so without it every
  commit would change every hash of an object containing a procedure. The ten
  pre-existing `dev_object` hashes are unaffected (they contain no procedure).
- `build.zig`, `src/build/minici.zig`: the `run-check-dev-code-hashes` step.

### A1: dispatch, register budget, `CC` seam, facade

- `LirCodeGen.zig`, `FrameBuilder.zig`, `CallingConvention.zig`,
  `ObjectWriter.zig` (`a3ad2da0d6`): every two-way `arch == .x86_64` /
  `== .aarch64` test goes through `Isa` (`src/backend/dev/isa.zig`). Needed
  because a binary test silently routes arm32 into another ISA's code path,
  and several `CallBuilder` chains had no final `else` (arm32 would have
  emitted nothing). The never-read `LirCodeGen.cc` field is removed because
  its initializer, `CallingConvention.forTarget`, panics for `.arm`.
- `x86_64/CodeGen.zig`, `aarch64/CodeGen.zig`, `NativeProcCompiler.zig`
  (`42b80a5c56`): the CPU level and the bounded temporary allocators move from
  the driver into each ISA's `CodeGen`, which records the D10 high-water mark.
  Needed as the seam per-ISA instruction selection and arm32's register budget
  build on.
- `x86_64/Emit.zig`, `aarch64/Emit.zig`, `LirCodeGen.zig` (`939c17678e`): role
  registers (result-pointer and RocOps save registers, Roc return registers,
  caller stack-argument base) come from the ISA's `CC`. Needed so arm32
  supplies its register roles by defining its `CC` instead of adding a third
  literal at each site.
- `LirCodeGen.zig`, both `CodeGen.zig` (`f23924444c`, `37872af5d3`): 55
  ISA-neutral helpers move into per-ISA `CodeGen` methods with one signature.
  Needed so arm32 implements them in its own `CodeGen`.

### A3: containers (`301db39b9a`)

- `object/elf.zig`: ELF32/REL writer for `.arm` beside the untouched ELF64
  path. Needed because the writer was ELF64/RELA-only and an EM_ARM ELF64
  object is accepted by no linker.
- `Relocation.zig`: `abs32`, `arm_movw_prel`, `arm_movt_prel` kinds and their
  in-process patchers. Needed for arm32's position-independent data addresses
  (D8).
- `object/macho.zig`, `object/coff.zig`, `RunImage.zig`: explicit refusals of
  the arm32 kinds (`RunImage.relocationKindForData` now returns an error).
  Needed because those switches are exhaustive and none of those formats or
  the shim runs arm32 code.
- `Dwarf.zig`, `ObjectFileCompiler.zig`: DWARF takes the target's address
  width. Needed because DWARF addresses were hard-coded to eight bytes.
- `ObjectWriter.zig`: the call-relocation addend becomes an exhaustive switch
  (x86_64 -4, aarch64 0, arm -8). Needed because `if x86_64 -4 else 0` would
  have given arm32 the wrong PC bias.

### Track C: target artifacts (`75c55299d2`)

- `build.zig`: arm32musl/arm32glibc builtins, runtime and host-library
  targets. Needed for anything to link for arm32.
- `src/default_platform/linux_runtime.zig`: an A32 `_start` and an arm
  `ucontext` for crash backtraces. Needed because `.arm` was a
  `@compileError`.
- `src/build/glibc_stub.zig`: real A32 bodies. Needed because it emitted
  `ret`, which is not an A32 instruction.
- `src/cli/main.zig`: explicit arm32 rows in the five prebuilt-object tables.
  Needed because arm32 fell through to the host's `native` builtins objects
  (and `null` runtime objects).
- `src/cli/test/parallel_cli_runner.zig`: `--cross-target` selecting no cases
  now fails. Needed because it exited 0, so a lane that tested nothing read as
  passing.
- `src/target/mod.zig`: a test pinning Zig's arm baseline to the D2 floor.
- `test/fx`, `test/int` platform manifests: declare `arm32musl`.

### A2: width model

- `LirCodeGen.zig` (`1decf55b3f`): `target_ptr_size` derives from the target
  (it was the literal 8) and the word vocabulary is added; RocStr/RocList
  field accesses name their fields. The small-string literal path bit-cast a
  word's bytes to `u64`, which compiles only for 8-byte words. Needed because
  every 32-bit value of these was wrong or uncompilable.
- `LirCodeGen.zig` (`9896319673`, `dcb012efe4`): list element access, the
  general copier, `List.len`/`List.capacity`, and the string and refcount
  helpers use words; `word_sign_bit` and `small_str_len_shift` replace
  `minInt(i64)` and a literal 56. Needed because those are pointer-sized
  values whose 64-bit spelling is a compile error (or wrong) on arm32.
- `LirCodeGen.zig` (list helpers and pointer-moving helpers): element-address
  arithmetic in `listGetAtLastIndex` and `callListSplitOp`, `generateList`'s
  heap-pointer slot, `emitAddPtrImmAny`, `copyStackToPtr`,
  `copyResultToReturnPointer`, the `general_reg` arms of the `ensure*OnStack`
  helpers and the ZST list copies use words; `storeResultToSavedPtr`'s 8-bit
  narrowing shifts are register-width-relative (`word_bits - 8`). Needed
  because each is a pointer, a byte count or a register-width operation.
- `LirCodeGen.zig`, `src/eval/boxy_abi.zig` (Boxy descriptor and dictionary
  references): `generateBoxyDescRef`, `generateBoxyDictRef`,
  `boxyDescRefToSlot`, the dictionary thunk bodies and `generateCallDict` use
  words, and `generateCallDict` lays out `RocBoxyCallArg` as three target
  words (value, layout, descriptor) instead of the literal offsets 0/8/16 and
  stride 24. A new `boxy_abi` test pins that shape. Needed because descriptors
  and dictionaries are pointers, and the literal layout is the 64-bit one.
- `LirCodeGen.zig` (one-register integer arithmetic): `generateIntBinop`
  and its overflow helpers use words, narrow by `word_bits - n`, and choose
  between a range check and a flag or high-product check with
  `intOverflowCheck` (sub-word versus word-sized) instead of naming
  `.u32`/`.i64`; `emitCheckedI64Mul`/`emitCheckedU64Mul` become
  `emitCheckedSignedWordMul`/`emitCheckedUnsignedWordMul`. On 32-bit targets
  an integer wider than the word goes to `generateWide64IntBinop` (J1). Needed
  because on arm32 I32 is word-sized (a range check against 2^32-1 in a 32-bit
  register cannot detect overflow) and I64 does not fit a register.
- `LirCodeGen.zig` (low-level pointer sites): `List.mapCanReuse` and the
  list-map, list-replace, list-set and list-concat ZST paths, byte-index
  addressing in `num_from_le_bytes`, the compare result, and every allocation's
  saved heap pointer use words; `str_from_utf8` fills `StrFromUtf8Layout` by
  `@offsetOf` and stores its two `u64` tags with `emitStoreImm64`. Needed
  because these are pointers, indices and word copies, and the tags are
  genuine 64-bit fields that a 32-bit target writes as two words.
- `LirCodeGen.zig` (integer conversions): widening, wrapping and
  integer-to-float conversions take their widths from
  `numeric_conversion.getConversionSpec` (the wrapping arm's 38-way if-chain
  for the destination width is gone), extend and mask by `word_bits - n`, and
  on 32-bit targets route a conversion with a side wider than the word to
  `generateWide64IntConversion` (J1). The unsigned-to-float arms merge: a
  source narrower than the word takes the signed conversion, a word-sized one
  the unsigned conversion (`emitSignedWordToFloat`/`emitUnsignedWordToFloat`).
  Widening into i128 stores the word and then fill words up to 16 bytes. The
  int-to-Dec arguments and `f64_from_bits` name `wide64_reg_width`, the width
  of a 64-bit value in one register, which is a compile error on 32-bit
  targets. Needed because on arm32 U32 is word-sized (a signed conversion of
  it is wrong above 2^31) and 64-bit sources and destinations do not fit a
  register.
- `LirCodeGen.zig` (i128 and unary integers): the `I128Parts` functions
  (`generateI128Binop`, comparisons, equality, bit counts, absolute
  difference, the `callI128*`/`callDec*` result loads, `getI128Parts`) name
  `wide64_reg_width` for their halves and `word` for the booleans, flags and
  counts they compute. `storeI128ToMem`, `storeWideScalarToStackOffset` and
  `boxyI128LiteralSlot` copy and store 16 bytes word by word
  (`storeI128ImmToMem`, `copyStackI128ToMem`, `storeI128ImmToStack`,
  `copyStackI128ToStack`, `wordOfU128`). Scalar negate, bitwise not, `abs`
  and `abs_diff` use words and, on 32-bit targets, route integers wider than
  the word to `generateWide64IntUnary`/`generateWide64IntBinop`; the
  `int_try` extension into its builtin's 64-bit argument names
  `wide64_reg_width`. Needed because 16-byte copies are word copies on every
  target, while i128 halves and 64-bit scalars do not fit an arm32 register.
- `LirCodeGen.zig` (structural equality): a field of at most a word is
  compared in one register, a larger one in word-sized XOR-accumulated
  chunks (it was 8 bytes and 8-byte chunks); discriminants load a word unless
  that would read past the union and are masked below the word; result
  booleans, list lengths, pointers, loop counters and offsets use words and
  word slots. Needed because an 8-byte field does not fit an arm32 register,
  and the rest are word-sized values. A discriminant stored in eight bytes is
  a variant index, so its low word is its value on every target.
- `LirCodeGen.zig` (call and return paths): an argument's or result's
  register count is its size in words (`calcArgRegCount`,
  `calcParamRegCount`, `aggregateArgRegisterPressure`; i128 and vectors are
  `16 / word_size`), and spills, caller-stack copies, multi-register loads and
  stores, and stack-argument offsets move one word per register. The i128 and
  vector register pairs name `wide64_reg_width`. On 32-bit targets, scalar
  arguments and results wider than the word go to J1
  (`saveWide64CallReturnValue`, `moveWide64ToReturn`, the scalar count).
  Needed because the internal convention's "register" is a word, and 8-byte
  units would split or drop half of every multi-register value on arm32.
- `LirCodeGen.zig` (refcount, string and list helpers): the RC helper
  bodies and calls, Boxy capture drops, ZST list paths, string capture and
  delimiter scanning, literal comparison, `emitMovRegReg`, and the chunked
  zero, poison and copy loops use words (a 4-byte piece only below a larger
  word). The RC helper's discriminant load follows structural equality's
  rule. `List.split_*` stores its word-valued counts as the builtin's `u64`
  arguments with `emitStoreWordAsU64` (a zero high word on 32-bit targets);
  `List.sublist`'s U64 arguments, the hasher's u64 state and
  `str_count_utf8_bytes`'s U64 result name `wide64_reg_width`. Needed because
  these are pointers, lengths and bytes on every target, except the named
  64-bit values, which a 32-bit target holds as two words.
- `LirCodeGen.zig` (value locations, parameters, erased calls, entry
  wrappers): a `.stack` location's default size is `word_value_size` (it was
  `.qword`), so `.qword` always means a genuine 8-byte value, and the sized
  loads and stores name `wide64_reg_width`/`wide64_store_width` for it.
  `ensureInGeneralReg`, `moveToReg`, `stabilize`, `emitCmpReg`,
  `emitMovRegReg`, parameter binding, erased calls, packed erased functions
  and the entry wrappers move words; immediates go through `emitStoreImm64`
  and word loops; narrowing shifts are `word_bits - n`, with zero shifts
  skipped (A32 encodes an immediate `ASR #0` as `ASR #32`). F64 bits, u64
  builtin results (`scalarRetReg`), 8-byte C-ABI pieces and a U64
  discriminant read name the Wide64 widths. Needed because each of these is
  either a register-sized value (a word) or a 64-bit value a 32-bit register
  cannot hold.
- `LirCodeGen.zig` (scalar bit counts): `generateBitCountScalar` counts
  integers up to a word with masks, adjustments and sentinels relative to
  `word_bits` (wider ones go to `generateWide64IntUnary` on 32-bit targets);
  `emitPopcount64`/`emitClz64` become `emitPopcountWord`/`emitClzWord` with
  word-width SWAR constants. Needed because the 64-bit constants and the
  `64 - width` adjustments are wrong for a 32-bit register.
- `LirCodeGen.zig` (SIMD lowering): lane indices, shift counts, masks,
  bitmask bits, SIMD load/store addresses and the builtin path's slots use
  words; 64-bit halves and lane sums, the 64-bit-lane rounding bias and
  `simdArgParts` name `wide64_reg_width`. Needed for the same reason as the
  scalar slices. The eval hashes barely reach SIMD code, so this one was also
  verified by comparing the `.text` of `test/simd/differential.roc` and
  `test/cli/runtime_simd_smoke.roc` built with `--opt=dev` for x64musl and
  arm64musl before and after (identical).

### Track D: CI lanes

- `src/cli/test/parallel_cli_runner.zig`: `--cross-opt=<dev|size|speed>`
  passes `--opt=` to every cross build (and requires `--cross-target`).
  Needed because the arm32 lane must build with the dev backend while the
  other lanes keep `roc build`'s default; an explicit option rather than a
  rule keyed on the target name.
- `src/cli/test/platform_config.zig`: `int` and `fx` list arm32musl (the two
  platforms whose manifests declare it). Needed so `--cross-target=arm32musl`
  selects their cases instead of reporting an unknown target.
- `.github/workflows/ci_cross_compile.yml`, `ci_zig.yml`: the arm32 lanes
  (cross-compile with `--opt=dev`, a qemu `cortex-a9` on-target row, the eval
  runner built for arm32 and run under qemu), all allowed to fail until J3.

### J1: arm32 code generation

- `x86_64/CodeGen.zig`, `aarch64/CodeGen.zig`, `LirCodeGen.zig`: the facade
  method `emitCtz64` is renamed `emitCtzWord`. Needed because the driver
  calls it only on values that fit one register, and arm32's implementation
  counts a 32-bit word; the name now states the contract every ISA meets.
- `FrameBuilder.zig`: the arm32 frame (D5: `push {fp, lr}; mov fp, sp`, one
  SP decrement covering a fixed r4-r10 area and the locals, page probing at a
  page or more, `mov sp, fp; pop {fp, pc}`), and `ForwardFrameBuilder`'s
  two-way `binaryIs` dispatch becomes exhaustive switches with an arm32 body.
  Needed because the six `.arm32 => @compileError` sites stood where arm32's
  frame belongs, and a two-way test cannot name a third ISA.
- `CallingConvention.zig` (`CallBuilder`): AAPCS32. Implicit stack slots and
  aggregate copy pieces are a target word (8 bytes on 64-bit targets, as
  before); `addMem64Arg`/`addImm64Arg` place a 64-bit argument in an even
  register pair or an 8-aligned stack slot that closes the core registers
  (C.3/C.5), and are `addMemArg`/`addImmArg` on 64-bit targets; float
  arguments back-fill s0-s15; the call emitters gain arm32 arms (`blx r12`,
  `blx rN`, BL with an `R_ARM_CALL` relocation) and the ISA-specific stores
  and scratch moves go through exhaustive switches. Needed because the six
  arm32 sites were compile errors and the two-way tests had no arm32 answer.
- `layout/abi/call.zig`, `layout/abi/mod.zig`, new `layout/abi/arm32.zig`:
  the AAPCS32 VFP C-ABI target (`Target.arm32`): classification (fundamental
  words and pairs, VFP candidates, vectors, composites) and physical
  assignment (C.3 even pairs, C.5 splits, VFP back-filling, result pointer
  in r0). `PhysicalArg` gains `split`, handled by the dev backend's hosted
  call and C-ABI entry paths and unreachable in the interpreter trampoline
  (x86_64 and aarch64 hosts only). Needed so hosted calls and entrypoints
  have an arm32 calling convention; no other target produces `split`.
- `LirCodeGen.zig` (J1c, first groups): the driver selects arm32's `CodeGen`,
  register types, `Condition` and stack alignment, and its top-level arm32
  refusal is gone (nothing instantiates `LirCodeGen(.arm32musl)` until J2).
  Two-way ISA tests in the scalar and memory helpers become exhaustive
  switches or facade calls: byte/halfword loads and stores, register shifts,
  population count and leading zeros, discriminant loads and masks
  (`emitMaskDiscriminant`), flag-setting add/subtract, word multiply
  overflow (`smull`/`umull`), abs and abs_diff, float immediates and
  word-to-float conversions, and return-pointer copies. Where the facade
  emits exactly what a two-way branch did (the x86_64 and aarch64 byte and
  halfword loads and stores), the branch becomes the facade call. Needed
  because each two-way test was a compile error for arm32.
- `LirCodeGen.zig` (J1c, proc and call plumbing): string, float and list
  builtin results (AAPCS32 zero-extends narrow results; a `u64` result is a
  Wide64 stored from r0:r1), RC string sign tests, float conversions and
  square roots, local-slot alignment, proc/helper compilation (arm32 uses the
  x86_64 deferred-prologue frame, so "x86_64" tests there become "not
  aarch64"), call placeholders and retargeting (BL), PC-relative code and
  data addresses (movw/movt/add rd, pc, patched in place), and the caller's
  stack-argument base (fp, as on x86_64). Branch-island, veneer and stub
  bookkeeping becomes explicitly aarch64-only. Needed because each two-way
  test was a compile error for arm32.
- `LirCodeGen.zig` (J1c, call and return paths): the internal return limit
  is two *words* (`max_internal_return_words * word_size`, 16 bytes as before
  on 64-bit targets), so on arm32 an I64 returns in r0:r1
  (`saveWide64CallReturnValue`/`moveWide64ToReturn`) and anything wider,
  including i128 and vectors, through the result pointer; the i128/vector
  two-register return paths are therefore 64-bit-only. `internal_ret_regs`,
  `float_ret_reg` and `emitMoveFloat` replace per-site ISA register lists;
  the AAPCS64 even-register rule for i128 arguments is explicitly
  aarch64-only, and an arm32 i128 argument is four words on the generic
  path. Needed because each two-way test was a compile error for arm32.
- `LirCodeGen.zig` (J1c, entry and hosted calls): the C-ABI target comes
  from one exhaustive selection (`c_abi_target`, `.arm32` for AAPCS32); the
  x86_64 entry-wrapper and Boxy-thunk frames name their pinned registers
  through `CC.RESULT_PTR_SAVE_REG`/`CC.ROC_OPS_SAVE_REG`/`entry_args_reg`
  and `CC.PARAM_REGS`, so arm32 (r9/r10/r8, r0/r1) shares that path; the
  result pointer is the first integer argument on arm32 as on x86_64;
  incoming stack arguments are copied at fixed fp offsets in word pieces;
  C-ABI integer pieces wider than four bytes are 64-bit-only. Needed because
  each two-way test was a compile error for arm32.

### J2: turning cross-compilation on

- `ObjectFileCompiler.zig`: `supportsTarget`, the one decision whether the
  dev backend serves a target (x86_64, aarch64, arm32), used by
  `crossCompileDispatch` and exported as `backend.devSupportsTarget`.
- `cli/main.zig`: `rocBuildNative`'s architecture gate asks
  `devSupportsTarget` (the LLVM path's 64-bit-only gate is unchanged); arm32
  phase names; the entrypoint-ABI hash selects `.arm32`; `rocBuildNative`
  honours `--keep-temp` as the LLVM path does.
- `LirCodeGen.zig`, found by building real programs: a one-word frozen call
  argument is `word_value_size` rather than `.qword`; the C-ABI entrypoint
  stores an incoming VFP argument by its AAPCS32 S-register index and an
  indirect argument's pointer as a word; `u64` builtin parameters go through
  `addU64SlotArg`/`addImm64Arg`/`addMem64Arg` (`list_*`, `str_*`,
  `debug_invalid_local`, `register_proc`, `list_concat`'s update modes,
  `float_to_str`); switch conditions wider than the word compare as pairs
  (`emitSwitchCondCompare`); in-bounds U64 indices use their low word; one-
  register element copies are bounded by the word. All byte-identical on the
  64-bit targets.
- `build.zig` (arm32linux): the arm glibc cross target is named
  `arm32linux`, its `RocTarget`, rather than Track C's `arm32glibc`, because
  test platforms key their `targets/<name>/` directories by target name (the
  `arm32glibc` host library was unreachable); and the glibc stub is generated
  for every GNU ABI (`isGnu()`), not only `.gnu`, so `gnueabihf` gets one.
  `test/int/platform/main.roc` declares `arm32linux`; `platform_config.zig`
  and the arm32 CI lane build it.
- `echo_platform/mod.zig`: the default platform's Linux build header
  declares `arm32musl` and `arm32linux` (its runtime objects existed since
  Track C), so a program without a `platform` header builds for arm32; a
  subcommands case in `parallel_cli_runner.zig` covers it.

### J3b: running cross-built programs

- `LirCodeGen.zig` (J3b, found by running `test/fx` on arm32):
  `list_sublist`'s `{ start, len }` record fields and the drop/take window
  slots pass as `u64` pairs; the list incref RC helper reads the list's
  words at `listFieldOffset` instead of the literal 0/8/16 (an A2 miss).
- `test/fx/platform/host.zig` (temporary Zig workaround):
  `hostedHostGetGreeting` takes the inner `RocStr` directly on arm32, behind
  `work_around_zig_arm_nested_struct_bug`, because Zig 0.16 passes a nested
  by-value `extern struct` off-ABI on arm (issues note). Unchanged on other
  targets. When Zig is fixed, set the switch to false and follow the comment
  there. A probe test (`zig_arm_nested_struct_abi_probe.zig`, run by the
  arm32 CI lane) fails once the bug is fixed, and the host refuses to compile
  for arm on a Zig other than 0.16.0 until the probe is rerun.
- `cli/test/parallel_cli_runner.zig` (J3b): `--cross-run` and
  `--cross-runner`, and the cross build's stderr expectations filtered by
  backend (a fix to Track D's `--cross-opt`).

### J3a: the dev backend on arm32 hosts

- `sljmp` (`e9e1a8da3b`): an A32 setjmp/longjmp for arm Linux (R4-R11, SP, LR,
  D8-D15), so the compile-time evaluator's crash recovery works on an
  arm32 compiler.
- `HostSplice.zig` and `machine_code_shim/main.zig` (`c8b2e8f839`): an A32
  jump stub (`ldr pc, [pc, #-4]` and the target word); HostSplice's tests skip
  on `host_lir_codegen_available` instead of naming x86_64 and aarch64.
- `builtins/native_runtime_libcalls.zig` (`f485e9c6c5`): on an arm32 host,
  `resolve` binds the `__aeabi_*` helpers the arm32 dev backend calls (D7) to
  the compiler's own compiler-rt.
- `LirCodeGen.zig` (`79f9ccf002`): `host_lir_codegen_available` is true for
  arm, so an arm32 compiler evaluates with its own dev backend; the 37 tests
  that named x86_64/aarch64 hosts skip on that constant instead (the tests
  themselves were made host-independent in `4a49f4b51f`, above). The arm32
  lowering fixes in the same commit (checked I64 negate, the small string
  capture copy, the wrapping 128-bit multiply) are new arm32 code and are in
  arm32 DESIGN.md.
- `arm32/Call.zig` and `arm32/CodeGen.zig` (`bf3e33730a`, a D5 amendment):
  out-of-range addresses are formed in LR, not r12. Listed here because it
  changes the register roles the plan's D5 fixed; see arm32 DESIGN.md.
- `.github/workflows/ci_zig.yml` (`79f9ccf002`): the arm32 eval lane is no
  longer allowed to fail and also runs the host-effects corpus.

### J3: call-shape battery

- `test/fx/platform/main.roc`, `host.zig`, new `Abi.roc`, and
  `cli/test/fx_test_specs.zig` (`80c74cc9d5`): eight hosted functions whose C
  signatures are the call shapes a backend must place exactly, and the
  `test/fx/abi_call_shapes.roc` case that calls them.
- `test/glue/fx_platform_cglue_expected.h` (`352d062072`): regenerated,
  because the new hosted functions change the fx platform's generated C
  header (their declarations, and every later hosted index moves by eight).

### J3c: required cross-compile lanes

- `.github/workflows/ci_cross_compile.yml` (`cd563f5c05`): the arm32musl
  lanes are no longer allowed to fail, and the on-target job compares each
  arm32 int app's stdout with the Linux-built x64musl app's, with heap
  addresses masked.

### J4: lock-in

- `snapshot_tool/main.zig` (`c17b138009`): the per-target pre-check asks
  `devSupportsTarget` instead of listing the 64-bit architectures, and a new
  test pins every `dev_object` snapshot line to that gate. The 16
  `dev_object` snapshots gain arm32 hashes (only `arm32*=` lines change).
- `design.md`, `backend/dev/mod.zig`, `projects/README.md` (`13547918d4`):
  ARM32 named among the native dev backends, its CPU floor stated, and the
  plan indexed.
