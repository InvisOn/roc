# `.w64` inventory of the dev backend's shared driver

Measured on upstream `main` `a2609ca2aa` (2026-11-05) and moved to
`ad3a5d2830` (2026-11-06), branch `isa-word-size`. Line numbers are
`ad3a5d2830`'s. `rebase_lines.py` moves the classify scripts' line numbers
to a new base through `git diff`; it stops on any classified line that
changed. Moving to `ad3a5d2830` changed no kind; it added one site, an
aarch64 expect-site literal (`start + 8`, isa).

## The problem

Everything above the dev backend is built for either word: the layout store
keeps sizes per target word (`TargetUsize`, u32 or u64), the builtins give
RocStr and RocList offsets for either word (`targetFieldOffset`), the wasm32
backend targets a 4-byte word, and the LLVM backend reads the word from the
target (`ptrBitWidth()`; not checked further here). The dev backend's shared driver
(`LirCodeGen`, `FrameBuilder`, `CallingConvention`) assumes an 8-byte word,
and `LirCodeGen.zig:352` asserts it. Nearly every width in it is written
`.w64`, which hides two different meanings: a target word (a pointer, a
length) and a value that is 64 bits on every target (a U64, half of an i128).
On x86_64 and aarch64 both are 8 bytes, so no test or oracle can tell them
apart; a misclassified site shows only once a 32-bit backend runs.

## Files

| File | Holds |
|---|---|
| `LirCodeGen.tsv` | every `.w64` in `LirCodeGen` |
| `CallingConvention.tsv`, `FrameBuilder.tsv` | every `.w64` there |
| `LirCodeGen-calls.tsv` | calls of helpers without a width |
| `LirCodeGen-args.tsv` | integer arguments to builtins |
| `LirCodeGen-eights.tsv` | literal 8 offsets, strides, sizes |
| `LirCodeGen-layouts.tsv` | `@offsetOf`, `@sizeOf`, `@alignOf` |

Scripts: `w64_sites.py` lists sites (`.w64`, `--calls`, `--pattern`) with
their context; `classify*.py` hold the kinds; `brace_check.py` and
`check_args.py` cross-check contexts and argument kinds.

## Method

1. `w64_sites.py <file>` lists every `.w64` with its function and context:
   `x86_64` or `aarch64` when the site is inside that arm of a `switch (isa)`,
   in the code after a `switch (isa)` whose other arms all return (`-tail`),
   inside `if (comptime target.toCpuArch() == ...)`, or in a function named for
   one instruction set (`fn:`); otherwise `shared`. Two shared-looking sites
   run for one instruction set only and are marked `isa` by hand in
   `classify.py`: `emitPopcount64`'s POPCNT (behind `use_swar`, which a
   `switch (isa)` computes) and the `else` of a brace-less
   `if (comptime target.toCpuArch() == .aarch64)` at 17710.
2. Every shared site was read and given a kind in `classify.py` (a default per
   function plus per-line exceptions). The script stops on any shared site
   without a kind, on a line given two kinds, and on an exception that matches
   no site, so a re-run on a new base shows what moved.
3. The `.tsv` files hold the result: `line`, `function`, `context`, `kind`,
   `code`.

The contexts are checked twice: `brace_check.py` finds the same arms, tails
and `toCpuArch()` branches by brace matching instead of indentation, and
agrees on every site except seven tail sites in `generateSimdBitmask` and
`generateSimdSum`, which reading confirms are tails (its tail test misreads
those two bodies). Every `switch (isa)` with an empty arm was read to confirm
that the code after it is shared unless it is a tail, and every function
marked by name is called only from its own instruction set's code.

The kinds are by reading; nothing checks them mechanically. A second reading
of every shared site with its preceding lines changed 67 of the first pass's
617 kinds (U64 operands taken for words, i128 return halves taken for
pieces, RocStr and RocList word loops that already step by
`target_ptr_size` taken for chunks). A third, tracing values to their
source (builtin signatures, `ListOpRequest`, `CompositionEntry`, the hasher)
changed 3 more.

## Kinds

- **isa**: one instruction set's code. Stays as it is; a new instruction set
  writes its own. When the code is a shared helper that takes no width,
  its callers depend on its width too: see "Widths no `.w64` names".
- **word**: a pointer, length, capacity, reference count, size, address, a
  RocStr or RocList word, or a whole general register. Becomes the target
  word. Folding "a whole register" into the word assumes the register width
  equals the pointer width, which holds for every Roc target (x86_64,
  aarch64, arm32, wasm32); an x32-style target would need the two apart.
- **64**: 64 bits on every target: U64, I64, F64 bits, half of an i128 or Dec,
  the hasher's state and seed, a U64 operand (an index, a sublist start or
  length, `ListOpRequest.n`), or the double-width product that checks a
  narrow multiply for overflow. Stays 64 bits; on a 32-bit target it needs a
  register pair.
- **scalar**: a value of up to 8 bytes whose width follows its size: integer
  arithmetic, sign and zero extension, immediates, value loads. On a 32-bit
  target, a word for 4 bytes and less, a register pair for 8: the Wide64
  routing.
- **piece**: one register-sized piece of a 16- or 24-byte value at a fixed
  `+8` stride. The width, the stride and the piece count all follow the word.
- **chunk**: the unit of a copy, fill or byte-compare loop. Can become the
  word, with the loop's step and remainder.
- **size-8**: a branch chosen by an 8-byte size (`8 =>`, `.qword`). An 8-byte
  value is 64 bits on every target, so a 32-bit target needs a pair here.

## Counts

| File | isa | word | 64 | scalar | piece | chunk | size-8 |
|---|---|---|---|---|---|---|---|
| `LirCodeGen` | 252 | 317 | 158 | 97 | 18 | 16 | 9 |
| `CallingConvention` | 29 | 2 | 0 | 0 | 0 | 0 | 0 |
| `FrameBuilder` | 32 | 0 | 0 | 0 | 0 | 0 | 0 |

`LirCodeGen`'s 867 sites are in 159 functions. The emitters
(`x86_64/Emit.zig`, `aarch64/Emit.zig`) and the per-instruction-set `CodeGen`
and `Registers` files are one instruction set's code by definition and are not
listed.

Where most sites are:

- word: `generateLowLevel` 42, `generateDyn` 25, `generatePackedErasedFn` 15,
  `generateDynElemLowLevel` 13, `generateDynFrameAlloc` 13
- 64: `generateLowLevel` 18, `storeWideScalarToStackOffset` 14,
  `emitPopcount64` 12, `emitSimdClmulBaseline` 12,
  `moveToReturnRegisterWithLayout` 12
- scalar: `generateIntBinop` 31, `generateLowLevel` 26
- piece: `spillArgToStack` 6
- chunk: `copyChunked` 6, `copyLoop` 5, `fillMem` 3, `fillSmall` 1,
  `emitCompareLiteralAtPtr` 1

## Widths no `.w64` names

The `.w64` list sees only a written `.w64`. A shared helper that takes no
width, and whose instruction-set arms use `.w64`, gives every caller 64 bits
whatever the caller's value is; `codegen.emitLoadImm(reg, i64)` does the same
for immediates. A whole register is one word on every target, so such a call
is correct for a word or a narrow value and wrong only where the value is 64
bits. `LirCodeGen-calls.tsv` therefore classifies the call sites of these
helpers by the value they work on, with one more kind:

- **narrow**: at most 32 bits on every target: a Bool, a flag, a shift or loop
  count, a u32 field, a small mask. Fits one register anywhere; no change.

The helpers are found by `w64_sites.py --calls` and classified by
`classify_calls.py` (same checks as `classify.py`; `test` blocks left out).
The list of helpers came from two searches: helpers whose instruction-set
arms hold `.w64` and that take no width, and helpers that pass a caller's
integer to an immediate instruction. `materializeVectorConstant`,
`loadAndMaskDiscriminant` and `storeDiscriminant` are not listed by caller:
their callers pass no width-dependent value, and their own sites are listed.

| Callee | word | 64 | scalar | narrow | other |
|---|---|---|---|---|---|
| `emitLoadImm` | 67 | 63 | 27 | 29 | isa 30, chunk 2, size-8 1 |
| `emitCmpImm` | 20 | 5 | 8 | 14 | isa 2 |
| `emitCmpRegImm64` | 0 | 6 | 8 | 0 | |
| `emitSaturatingSub` | 0 | 8 | 0 | 0 | |
| `emitSetCond` | 0 | 0 | 0 | 5 | isa 2 |
| `emitAddImm` | 3 | 0 | 0 | 0 | chunk 3, isa 1 |
| address helpers | 39 | 0 | 0 | 0 | |

The address helpers are `emitLeaStack` 15, `emitAddUsizeImm` 10,
`emitAddPtrImmAny` 7, `emitSubStackPtr` 3, `emitAddStackPtr` 2 and
`emitTailBlockAddress` 2. All 343 sites: word 129, 64 82, narrow 48,
scalar 43, isa 35, chunk 5, size-8 1. Every `emitSaturatingSub` site mixes a
word length with a U64 operand (item 7 below).

### Arguments to builtins

The call builder has no width either: each integer argument takes one
register or one stack slot. `LirCodeGen-args.tsv` classifies the 486
non-test arguments by the parameter they fill, from the callee's Zig
signature (`builtins/dev_wrappers.zig`, `boxy_runtime/exports.zig`,
`builtins/in_process_host.zig`): u64 and i64 are 64, usize, isize and
pointers word, u32, u8, bool, i32 and UpdateMode narrow. Float arguments go
in float registers and are not listed. `classify_args.py` holds the kinds;
`check_args.py` lines each builder's arguments up with its target's
parameters wherever the target is named directly (a `.name` builtin, a
`LowLevelBuiltins` lookup table entry, or a boxy runtime name) and no
argument is added under a branch: 112 arguments checked, 0 mismatches. The
other 74 builders name their target through a variable (`builtin_fn`) or add
arguments under branches and were read against the signatures.

| Method | word | 64 | narrow | other |
|---|---|---|---|---|
| `addImmArg` | 36 | 5 | 108 | mixed 1 |
| `addRegArg` | 16 | 59 | 3 | |
| `addMemArg` | 34 | 17 | 0 | |
| `addWordArg` | 46 | 1 | 0 | |
| pointer and RocStr/RocList-word methods | 158 | 0 | 0 | |
| `addMemArgAt`, `addStackMemArgAt` | 0 | 0 | 0 | piece 2 |

All 486: word 290, narrow 111, 64 82, piece 2, mixed 1. The pointer and
word methods are `addLeaArg` 84, `addBytesArg` 22, `addStrBytesLenCapMemArgs`
21, `addListBytesLenCapMemArgs` 16, `addTargetArg` 13 and two `At` variants.
The 64-bit arguments are i128 and Dec halves, hasher seeds and values, SIMD
vector halves, and Roc U64 operands (indexes, starts, lengths, counts,
capacities, spares). Findings:

- The builtin side assumes 8-byte words in places: `str_equal_static_small`
  takes RocStr's three words as `word0`, `word1`, `word2: u64`, and
  `str_static_small_word_eq` and its caseless twin take one as `word: u64`.
- `list_concat` takes `update_modes: u64` for a value of two bits.
- `callListBuiltin` forwards its callers' `.mem` and `.imm` values (12669,
  12670). Every `.mem` value is a U64 operand, so 12669 is 64. The `.imm`
  values are mixed: alignments and update modes are narrow, element sizes
  are words, and two are 64-bit: `list_concat`'s update modes (2476) and the
  zero start and length of an empty sublist window (8004).
- `addWordArg` passes "the word an `opaque_ptr` local holds", but at 17984 the
  local is a list index for `roc_desc_list_item_addr(..., index: u64)`.

Checked and word-neutral: the RocStr and RocList constants
(`SEAMLESS_SLICE_TAG` 1, its mask `~1`, `capacity_shift` 1, and
`str_flag_byte_shift`, which comes from the target offsets), apart from
`str_small_bit` (item 6 below). Each of the 71 `.w32` lines in `LirCodeGen`
was read: u32 fields (layout and descriptor sizes, request fields), 4-byte
size arms, F32 bits, discriminants, or 4-byte copy tails; none is a word.

## Word-size assumptions that are not `.w64`

Items 2, 3 and 8 are inventoried site by site (`LirCodeGen-eights.tsv`,
`LirCodeGen-layouts.tsv`, and the list under 8); the others are single sites
or small groups described here.

1. **The gate:** `LirCodeGen.zig:352`, `comptime std.debug.assert(target_ptr_size == 8)`.
2. **Literal 8s** (`LirCodeGen-eights.tsv`, `classify_offsets.py`; the
   lister's `--pattern` mode finds `± 8`, `* 8` and `8 *`): 105 lines. 64 51
   (the high half of a 16-byte value at `+ 8`, and `ListOpRequest.n`'s u64
   stride), piece 19 (argument and return pieces, 8-byte stack argument
   slots, `generateCAbiCall`'s padding), bits 12 (bytes times 8 bits),
   word 9, isa 5, compiler 5 (buffers for the compiler's own data), chunk 2,
   scalar 1, narrow 1. The 9 word lines are word strides written as 8:
   `placeCallArguments` loads RocStr or RocList words at `+ 8` and `+ 16`
   (19837, 19838) instead of `target_ptr_size` multiples; the RocStr copy at
   3527 steps `word * 8`; `emitLocalArray` (17444, 17453),
   `generateCachedComposition` (17715, 17725, 17739), `generateDyn`'s
   variant payloads (17900) and dictionary lookup (17953) index word arrays
   by `* 8`. `generateTailCall` also advances its stack-argument staging by
   `word_offset += 8` (piece). Of the literal 16s, only 19838 is a word
   stride; the rest are aarch64's 16-byte frame record or 16-byte vectors.
   Stack slots of 8 and 16 bytes (`allocStackSlot(8)` 61, `(16)` 29) are at
   least as large as what they hold at either word, so they stay correct.
3. **Target memory laid out with the compiler's own Zig types**
   (`LirCodeGen-layouts.tsv`, `classify_layouts.py`): 58 `@offsetOf`,
   `@sizeOf` and `@alignOf` lines. host-layout 32: `ListOpRequest`
   (after its two u32s), `FieldInput`, `DeclaredFieldInput`, `VariantInput`,
   `CompositionEntry`, `HotReloadCaptureHeader`, the erased callable payload's
   second word at `@sizeOf(usize)`, pointer alignment as `@alignOf(usize)`,
   and item 4's cell; these follow the compiler's word, not the target's.
   narrow 13: the u32-only builtin layout structs (`StrSplitFirstLayout`,
   `StrFromUtf8Layout`, `NumPrefixParseLayout` and the like),
   `TypeDesc.size` and `.alignment`, and `ListOpRequest.op` and
   `.unique_args`, all before any pointer. compiler 13: buffers and the
   in-process allocator helpers. The wasm backend already lays out the same
   request structs for its 32-bit target with `wasm32FieldOffset` and
   `wasm32StructSize` (`backend/wasm/WasmCodeGen.zig:8849`, `:8864`).
4. **`emitOwnPendingCell`** defines `const word = @sizeOf(u64)` for a cell
   whose size, `builtins.native_callable.pending_words`, is itself
   `@sizeOf(Pending) / @sizeOf(usize)` on the compiler host.
5. **`CallingConvention`:** stack arguments use fixed 8-byte slots
   (`CallingConvention.zig:309`, `:345`), and aggregates split into pieces of
   at most 8 bytes (`:316`). The arguments the driver passes through it are
   in "Arguments to builtins" above.
6. **RocStr's small-string bit:** `str_small_bit` is an `i64` asserted to be
   `minInt(i64)` (`LirCodeGen.zig:364`); on a 4-byte word the length word's
   sign bit is bit 31.
7. **U64 operands:** list indexes (`List.get`, `num_from_le_bytes`, drop-at),
   `List.sublist`'s start and length, and `list_item_size_at_most`'s bound are
   U64 in Roc, and `listSublist` and `ListOpRequest.n` take them as `u64` on
   every target. On a 32-bit target, code that combines them with a word
   length or uses them in address arithmetic must narrow them, with a
   bounds decision. The other way round, results read from a word field
   but typed U64 in Roc (`List.len` at 1919 and 18281 to 18283, the
   capacity at 1947) must be zero-extended to 64 bits.
8. **`@sizeOf(usize)` in other dev backend files:** 33, of which 22 are in
   tests. The 11 others all patch or check pointer slots on the machine that
   runs the code, where the compiler's own word is right: `HostSplice` 319
   and 321 and `StaticDataImage` 235 (in-process images), `Relocation` 266
   and 272 (absolute pointers in in-process code), and `RunImage` 401 and 668
   and `StaticDataPool` 200, 203, 320 and 486 (the run image and its static
   data pool, which the compiler's shim maps on the same machine). This
   assumes the shim runs at the compiler's word size.

## Related, not word size

- Four `if (comptime target.toCpuArch() == .aarch64)` choices in `LirCodeGen`
  (15294, 17647, 17706, 19214) reached `main` after step 1 (upstream PR
  12740, merge `12b9763ec3`, which had none); they were written on
  2026-10-27 to 10-30, alongside step 1. `design.md` "Dev Backend
  Instruction Sets" rules them out (a choice must be an exhaustive
  `switch (isa)`).
  `mod.zig:64` (`loader_host`, x86_64 or aarch64 since `ad3a5d2830`) and
  `ObjectFileCompiler.zig:344` (asserts x86_64 or aarch64) compare the
  architecture too.
- **Unit images** (fast dev linking, `UnitImage.zig`, `UnitImageLoader.zig`;
  about 2,900 new lines in `ad3a5d2830`) place code into dev executables with
  `abs64` relocations (22) and many `u64` fields. They are target data
  outside the shared driver and are not inventoried here; a 32-bit target
  needs its own relocation widths there.
- The driver names x86_64 and aarch64 registers directly (about 152 and 86
  uses in `LirCodeGen`).
