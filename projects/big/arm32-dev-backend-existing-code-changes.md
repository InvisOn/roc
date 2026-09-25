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

### Plan documents failed `run-check-tidy` (`12be3758d5`)

Spaced em dashes and missing or duplicate top-level titles in
`projects/big/arm32-dev-backend*.md` and `arm64-backend-reference.md` made the
tidy check fail on the branch before any code changed. Needed so the tidy
check could gate every later commit.

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
