# Fold step 6 of 9: word size (1 of 3)

Branch `dispatch/isa`, five commits on top of step 5, after the rebase onto
upstream `629c3e0e2d` (branch D3). Each is rewritten on upstream's code
from a reference "A2" commit; none is a plain cherry-pick. Planning doc:
`step-6-word-size-plan.md`.

| Commit | Source | Subject | Lines |
|---|---|---|---|
| `84c8a5e582` | reference `bf9d0e0d49` | Access RocStr and RocList fields at the target's word width | +180/−134 |
| `b81794e8e4` | reference `0676c747be`, arithmetic half | Make one-register integer arithmetic word-relative | +198/−132 |
| `8861352665` | reference `0676c747be`, pointer half | Compute low-level pointers at the target's word width | +49/−41 |
| `c249dca43b` | reference `75e30d5f49` | Make integer conversions word-relative | +132/−133 |
| `0d8048aee4` | reference `e7d97b7d88` | Make scalar bit counts word-relative | +84/−63 |

The reference's `b2ec6583e4` (structural equality) has no counterpart:
upstream deleted that code in `f7fc21a3b6`. The rebase onto `629c3e0e2d`
changed every step 1 to 5 hash; step 5's write-up keeps the old ones.

## Terms

- **Word:** the size of a pointer and of every `usize` value: 8 bytes on
  x86_64 and aarch64, 4 on 32-bit ARM. `word` is its register width,
  `word_bits` its bit count.
- **Wide64:** a value that is 64 bits on every target (I64, U64, F64 bits).
  On a 32-bit target it needs a register pair. Plan D2 keeps those paths
  out of part 1.
- **The 8-byte assert:** `comptime std.debug.assert(target_ptr_size == 8)`
  in `LirCodeGen`. It stays through part 1, so every 4-byte branch here
  compiles but never runs.

## Why

Upstream's driver already places RocStr and RocList fields at offsets
scaled by the target word, but loads, stores and computes almost
everything at 64 bits and picks paths by type name in ways that are only
right for an 8-byte word. On a 4-byte word the 8-byte accesses reach into
the next field, a 32-bit integer fills the register and needs the
overflow flags, and the bit-count and conversion masks are 32-bit. These
commits make those places follow the target's word, without changing
64-bit output.

## What changed

- **`84c8a5e582`:** `word` (.w64 or .w32, a compile error otherwise) and
  `word_bits`, defined from `target_ptr_size`, with comments saying why
  the sites use them and why the 8-byte assert stays. Every RocStr and
  RocList field load, store and word-by-word copy, and the shifts, masks,
  selects and sign tests on loaded fields, at `word`; bytes-pointer loads
  that relied on offset 0 add the named offset; the small-string literal
  loads integers as wide as the word; the small-string flag check is stated
  for the word. Tests of `targetFieldOffset` at 4- and 8-byte words. Three
  aarch64 locals named `word` renamed `instruction`.
- **`b81794e8e4`:** `intOverflowCheck` (file level, takes the word's bit
  count) chooses between upstream's narrow range checks and the flags;
  operations, narrowing and shift counts relative to the word; the word
  multiply checks renamed. Test at 32 and 64 bits.
- **`8861352665`:** byte-index addressing in four unsafe operations,
  saved heap pointers (slots sized `target_ptr_size`) and the compare
  result at `word`. The bounds-checked U64 index is read as its low word
  (decision D).
- **`c249dca43b`:** widening, wrapping, integer-to-float and
  widening-into-i128 relative to the word; one unsigned-to-float prong;
  `emitSignedWordToFloat` and `emitUnsignedWordToFloat`; `word_bits`
  becomes a u8.
- **`0d8048aee4`:** `emitPopcountWord`, `emitClzWord`, `emitCtzWord`
  (upstream's newer trailing-zero helper included) at `word`; SWAR masks
  from `wordOfU128` (file level, takes the word's bit count); scalar bit
  counts relative to the word. Test at 32 and 64 bits.

## Decisions made during the step

- **Commit 1:** `word` is defined in `LirCodeGen` from `target_ptr_size`
  (upstream has no per-ISA `CC` table), no `word_size`, no `wordOffset`.
  Commit 1 covers every RocStr and RocList access, including ones the
  reference missed. The reference's structural equality commit is dropped:
  upstream deleted that code (`f7fc21a3b6`).
- **Commit 2:** upstream's narrow range helpers stay; `intOverflowCheck`
  (file level, takes the word's bit count) only chooses between them and
  the flags.
- **Commit 3, decision D (refines plan D2):** a U64 used as a full 64-bit
  value keeps `.w64`, but the bounds-checked index of an unsafe operation
  is read as its low word, with a comment at each site. Bounds checks
  themselves keep `.w64`.

## How the reference commits were adapted

- Each commit was applied without committing, every conflict got a
  comment explaining both sides for review, and the commit was then
  rewritten by hand from upstream's file. Upstream's names, helpers and
  newer code win (`target_ptr_size`, `targetFieldOffset`, the list/str
  argument helpers, `callListBuiltin`, `emitShiftImm`, `condCode`,
  `srcBits`, the narrow range helpers, `emitCtz64`).
- Left out (plan D2): every Wide64 dispatch and placeholder
  (`generateWide64IntBinop`, `generateWide64IntConversion`,
  `generateWide64IntUnary`, `wide64_reg_width`, `emitStoreImm64`,
  `wordAsU64`), the reference's design-note labels, its notes files and
  `arm32/DESIGN.md`.
- Beyond the reference: RocStr and RocList sites upstream added later,
  the bytes pointer and word-sized operations the reference left at `.w64`,
  `list_get_unsafe`'s index, five more saved-pointer accesses, the
  `placeCallArguments` literal offsets, and `emitCtz64`.

## Review findings and outcomes

Commit 1:

- **REVIEW (yours), applied:** why still assert an 8-byte word. A comment
  above the assert now says.
- **REVIEW (yours), applied:** `.w64` at a list index. The index is a U64
  and stays; the bytes-pointer loads beside it were misses, 8 sites fixed.
- **Search for misses, applied:** 2 string bytes loads at offset 0, 5
  RocList copy loops, and the 8-byte-only small-string-bit assert.
- **REVIEW (mine), applied:** the comment on `word` overstated what is
  converted; reworded. The three-register argument path also serves
  records; the message says so. The byte-index add left at `.w64` went to
  commit 3.
- **Asked for, applied:** a comment explaining the small-string-bit assert.

Commit 2: conflicts reviewed; upstream's range helpers kept. Mine: the
compare helpers with a built-in 64-bit width went on the part 3 list.

Commit 3: decision D (option 1). Mine: the comment on two index copies was
missing at first; added.

Commit 4: the merged unsigned-to-float prong (yours, approved). Mine: kept
upstream's register-allocation order so the bytes cannot change.

Commit 5: `emitCtz64` kept and converted (approved). The 128-bit path
changed names only; it went on the part 3 list.

Plan-level: the README was checked and fixed; a named 64-bit width goes to
part 3; unit tests cannot cover the `.w64`-to-`word` sites in part 1, so the
table below lists the arm32 tests that must.

## Tests

All run on this machine (x86_64, `-j14`).

- After each commit: `run-check-zig-format`, `run-check-unreachable-rationale`,
  `run-test-zig-module-backend` (and `run-test-zig-module-builtins` for
  commit 1), `run-check-snapshots`. All passed; the snapshot check shows
  `dev_object` output unchanged after every commit.
- On the finished branch (`0d8048aee4`), the full set from step 5 plus
  builtins: all passed.
- The relative oracle, `629c3e0e2d` against `0d8048aee4` (steps 1 to 6):
  PASS: 0 of the 2373 hashed eval cases differ on x86_64 or aarch64, none
  is on one side only, and 0 64-bit `dev_object` snapshot lines differ.
  A0's oracle patch no longer applied to upstream (6 conflicts in 5
  files); they were resolved in the oracle's worktree and recorded with
  rerere, plus one `A0_FOLLOWS` entry in `relative_oracle.py` so its hash
  mode lowers like upstream (`3b7831cbd9`).

## Word-sized sites left for part 3

Found while searching for misses in commit 1. None is a RocStr or RocList
field access, so commit 1 leaves them at `.w64`. Each still assumes an
8-byte word, and part 3 (the rest of the driver's word size) or part 7
(AAPCS32) has to change it before the 8-byte assert goes.

- **Memory arguments:** `CallingConvention.zig`'s `addMemArg` loads every
  memory argument as 64 bits (`emitLoadPromoted`, `.none` case), including
  the RocStr and RocList words that `addStrBytesLenCapMemArgs` and
  `addListBytesLenCapMemArgs` pass at the right offsets. Calling-convention
  work, part 7.
- **Values passed or returned in several registers:** register counts and
  offsets in 8-byte units (`num_regs * 8`, `@as(i32, ri) * 8`) for strings,
  i128 and records alike: `spillArgToStack`, `freezeCallArg`, the
  multi-register argument loads in `placeCallArguments` and the tail-call
  path, and the return-register spills. `aggregateArgRegisterPressure`
  counts records in 8-byte registers, while the three-register argument
  path commit 1 changed loads words, so records of 17 to 24 bytes are
  counted in one unit and loaded in another until part 3. The reference's
  "Count call registers in words" commit (`236042aa45`), part 3.
- **Compare helpers with a built-in 64-bit width:** `emitCmpImm`,
  `emitCmpReg` and `emitCmpRegImm64` take no width. Commit 2's arithmetic
  uses them for the narrow range checks (`emitNarrowIntRangeCheck`) and the
  signed-minimum division checks (`signedLowestI64`), so those compare at
  64 bits while the arithmetic around them is at `word`. Part 3.
- **Other pointer-sized values:** the Box pointer in
  `emitDebugAssertValidBoxLocal`, the descriptor and value pointer arrays
  (`count * 8`), the hidden-local slots (`* 8`), and the erased-call
  argument stride (`call_arg_stride = 24`). The reference's "Classify"
  commits, part 3.
- **128-bit bit counts:** `generateBitCount128` counts an i128 as two
  64-bit halves with the word-sized helpers (`emitPopcountWord`,
  `emitClzWord`, `emitCtzWord`). Right at an 8-byte word; at a 4-byte word
  an i128 is four words. Part 8 (i128 as four words).
- **Values that are 64 bits on every target** stay `.w64` by design (plan
  D2): U64 indices, i128 halves, F64 bits. Their 32-bit lowering is part 8.
- **Name the 64-bit width in part 3.** Part 3 brings the reference's
  `wide64_reg_width` and `wide64_store_width` (plan D2): `.w64` at an
  8-byte word, and at a 4-byte word a compile error worded as an invariant
  ("a 64-bit value needs a register pair on a 32-bit target"), not a TODO.
  Part 3 uses them at every value that is 64 bits on every target, so
  each width is either `word` or a named 64-bit width, and the count of
  raw `.w64` in the driver reaches zero. A raw `.w64` then means a site
  nobody has classified.

## Tests that must cover step 6's sites

Part 1 can't run code at a 4-byte word, so nothing here catches a site
that goes back to `.w64`: on 64-bit targets `word` is `.w64`. The guard is
arm32 tests that exercise each kind of site, running in CI. They become
possible once arm32 programs build (parts 6 and 7) and run in CI from
part 10. The 8-byte assert may only be lifted together with tests that
cover every row:

| Kind of site in step 6 | Example | Test that must cover it |
|---|---|---|
| List length and capacity loads | `List.len`, `List.capacity`, seamless slices | eval cases on lists, including a slice |
| Empty and zero-size lists | `[]`, `List.concat` of zero-size elements | eval cases on empty lists and lists of `{}` |
| List and string word-by-word copies | `List.reverse` of zero-size elements, saved results | eval cases that return a list and a string through a saved pointer |
| Bytes pointer loads | list element access, byte indexing | eval cases on `List.get` and bytes |
| Three-register returns | a proc returning `Str` and `List` | eval cases calling procs that return each |
| Frozen three-register arguments | passing a `Str` to a proc | eval cases passing `Str` and `List` arguments |
| String literals | small (inline) and big strings | eval cases with both sizes at the boundary (11 bytes on arm32) |
| String captures and slices | `Str` captured by a closure, substrings | eval cases on captures and seamless string slices |
| Debug RocStr check | Debug build of any string program | an eval run in a Debug build |
| RocStr/RocList field offsets | `targetFieldOffset` at 4 and 8 | unit tests, in commit 1 |
| One-register integer arithmetic | I8/I16/I32 add, sub, mul with crash, wrap and overflow-flag results | eval cases at each width, including I32 overflow (the flags path on a 4-byte word); `intOverflowCheck` unit test, in commit 2 |
| Bounds-checked byte indexing | `List.get`, `num_from_le_bytes_unchecked`, in-place list map | eval cases reading elements and integers out of byte lists |
| Saved heap pointers | boxing, heap-allocated records and tags, erased closures | eval cases that box values and build closures with captures |
| Compare result | `Num.compare` | eval cases on ordering of each integer width |
| Integer conversions | widen, wrap, integer to float, widening into I128 | eval cases including U32 values at or above 2^31 converted to F64 |
| Bit counts | count ones, leading and trailing zeros on U8 to U32, including zero | eval cases at each width; `wordOfU128` unit test, in commit 5 |

## Final commit messages

### `84c8a5e582`

```
Access RocStr and RocList fields at the target's word width

LirCodeGen already places RocStr and RocList fields at offsets scaled by
the target word (target_ptr_size, RocStr/RocList.targetFieldOffset), but
it still loads and stores them, and computes on them, at 64 bits. On a
4-byte word those accesses would reach into the next field: zeroing an
empty list, for example, writes the length as 8 bytes at offset 4, over
the capacity at offset 8.

`word` is the register width of a target word (.w64 for an 8-byte word,
.w32 for a 4-byte one), and `word_bits` its bit count. These now use it:
RocStr and RocList field loads and stores; the shifts, masks, selects and
sign tests on the loaded fields; word-by-word RocStr and RocList copies;
and the three-register string/list returns. Loads of a bytes pointer that
relied on it being at offset 0 now add str_bytes_offset or
list_bytes_offset. The frozen argument path for values passed in three
registers (strings and lists, and records and tag unions of 17 to 24
bytes) loads them as words at target_ptr_size steps instead of 64 bits at
literal 8 and 16. The small-string literal loads each word as an integer
as wide as the word, so it also compiles for a 4-byte word. The check
that the small-string flag is the length's sign bit is stated for the
target word instead of for i64.

Three aarch64 locals named `word`, which hold instructions, are renamed
to `instruction`.

New tests check RocStr and RocList.targetFieldOffset at 4- and 8-byte
words.

The driver still requires an 8-byte target word, now with a comment
saying why, and there `word` is .w64, so generated code is unchanged
(dev_object snapshots).
```

### `b81794e8e4`

```
Make one-register integer arithmetic word-relative

generateIntBinop computed every integer in a 64-bit register, narrowed
sub-64-bit operands with 64-bit shift amounts, and chose its overflow
check by type name: a range check for 8-, 16- and 32-bit integers, the
operation's flags (or a multiply's high product) for 64-bit ones. That
choice is right only for an 8-byte word. On a 4-byte word a 32-bit
integer already fills the register, so it needs the flags, and the
narrowing amounts are 32 minus the type's width.

The operations, the narrowing and shift-count shifts, and the overflow
flags and checks now work at `word` width, with amounts relative to
word_bits. intOverflowCheck decides between the range check and the
flags by comparing the type's bit count with the word's, and the add,
subtract and multiply overflow paths switch on it instead of on type
names. It takes the word's bit count as a parameter, so a new test
checks it at both 32 and 64 bits. narrowIntRange and the narrow range
helpers are unchanged; emitCheckedI64Mul and emitCheckedU64Mul are
renamed emitCheckedSignedWordMul and emitCheckedUnsignedWordMul.

An integer wider than the word never reaches this path. The driver
still requires an 8-byte target word, where `word` is .w64 and
word_bits is 64, so generated code is unchanged (dev_object snapshots).
```

### `8861352665`

```
Compute low-level pointers at the target's word width

Several driver paths compute or keep a pointer in a register but did so
at 64 bits: the byte-index addressing of list_get_unsafe,
list_map_extract_unsafe, list_map_write_unsafe and
num_from_le_bytes_unchecked (index times element size plus the bytes
pointer), and the heap pointer that allocation-backed constructions save
to a stack slot and reload. A pointer is a target word, so these now use
`word`, and the saved-pointer slots are target_ptr_size bytes instead of
8. The two-flag compare result (-1, 0 or 1) is built at `word` too.

The index of these operations is a U64, but each is an unsafe or
unchecked operation whose index the Roc code has already bounds-checked,
so the index is below the list's length and its low word is the whole
index. The index is therefore loaded and copied at `word`, with a comment
at each site saying so.

The driver still requires an 8-byte target word, where `word` is .w64
and target_ptr_size is 8, so generated code is unchanged (dev_object
snapshots).
```

### `c249dca43b`

```
Make integer conversions word-relative

Integer widening, wrapping, integer-to-float and widening-into-i128
conversions extended and masked their operands by 64 - n in 64-bit
registers, and unsigned-to-float picked the signed conversion for 8-,
16- and 32-bit sources and the unsigned one for 64-bit sources. That
split is right only for an 8-byte word: on a 4-byte word a U32 fills the
register and may exceed the signed range.

The extends and masks now shift by word_bits - n at `word` width. The
two unsigned-to-float prongs become one: a source narrower than the word
is zero-extended and converted with the signed instruction, a word-sized
source takes the unsigned conversion. Both conversions are factored into
emitSignedWordToFloat and emitUnsignedWordToFloat, at `word` width.
Widening into i128 stores the low word and then fills every higher word
with the sign or zero. word_bits becomes a u8, the type of a shift
amount.

A conversion with a side wider than the word does not take these paths.
The driver still requires an 8-byte target word, where `word` is .w64
and word_bits is 64, so generated code is unchanged (dev_object
snapshots).
```

### `0d8048aee4`

```
Make scalar bit counts word-relative

Population count, leading-zero and trailing-zero counts worked on full
64-bit registers: the SWAR popcount used 64-bit masks and a final shift
of 56, the zero-operand results were 64, and the scalar lowering masked
and adjusted relative to 64 bits. On a 4-byte word the masks are 32
bits, the final shift is 24, and a zero word has 32 leading or trailing
zeros.

emitPopcount64, emitClz64 and emitCtz64 become emitPopcountWord,
emitClzWord and emitCtzWord and work at `word` width. The SWAR masks
come from wordOfU128, which takes the word's bit count, so a new test
checks it at 32 and 64 bits; the final shift is word_bits - 8 and the
zero-operand results are word_bits. The scalar lowering masks, adjusts
and adds its sentinel relative to word_bits. The 128-bit lowering is
unchanged apart from the helper names.

An integer wider than the word does not take the scalar path. The
driver still requires an 8-byte target word, where `word` is .w64 and
word_bits is 64, so generated code is unchanged (dev_object snapshots).
```

## Open

- Upstream has moved 28 commits past `629c3e0e2d`; fold step 7 rebases if
  needed and reruns the checks.
