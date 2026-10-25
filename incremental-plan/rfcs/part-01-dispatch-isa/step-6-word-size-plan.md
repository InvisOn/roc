# Fold step 6: word size (1 of 3)

- **Status:** Accepted (2026-10-26)
- **Scope:** Step
- **Plan row:** 1 dispatch/isa
- **Branch:** `dispatch/isa`
- **Fork PR:** #9
- **Parent:** `dispatch-isa-rfc.md`
- **Base:** `629c3e0e2d` (branch D3, accepted 2026-10-26)
- **Head:** `e65824d17e` (before this step)

## Abstract

As done, the step differs from this plan in places (five commits of
different content, no structural equality commit, upstream's names); see
`step-6-word-size.md`, "Decisions made during the step".

This step brings in the vocabulary the dev backend needs to work from the
target's word size instead of assuming 8 bytes, and makes integer
arithmetic, conversions, structural equality and bit counts use it. The
source is five of the reference's 14 "A2" commits (branch D2), applied as
six commits. It needs
four decisions: where the definitions borrowed from two "Classify" commits
go (D1), what happens to the 32-bit-only placeholders that mention TODO and
J1 (D2), where the new unit tests go (D3), and when the notes are updated
(D4). x86_64 and aarch64 output must stay byte-identical, shown by the
relative oracle and the snapshots.

## Problem

The driver now knows the target's word size (`target_ptr_size`, from
`target.ptrBitWidth()`), and upstream already scales RocStr and RocList
field offsets by it. But the loads and stores at those offsets still say
`.w64`, and arithmetic, conversions, equality and bit counts still use
64-bit registers, masks and sentinels for word-sized values. On an 8-byte
word the two agree, so nothing goes wrong today. On a 4-byte word the
offsets shrink but the accesses stay 8 bytes wide, so every word-sized
field access reaches into the field after it. The comment above the
assert (`LirCodeGen.zig:500-501`) even says "RocStr/RocList words are
moved with 64-bit loads and stores"; commit 1 updates it.

### Breakages you can run

Commit: `e65824d17e`. Nothing can be run yet. The driver still asserts an
8-byte word (`LirCodeGen.zig:503`), and with that removed it stops at
`aarch64/CodeGen.zig:31`, because no arm32 code generator exists until
part 6. The breakage is shown by reading:

`LirCodeGen.zig:2245-2248` zeroes an empty list:

```zig
try self.emitStore(.w64, frame_ptr, slot + list_bytes_offset, temp);
try self.emitStore(.w64, frame_ptr, slot + list_len_offset, temp);
try self.emitStore(.w64, frame_ptr, slot + list_capacity_offset, temp);
```

On a 4-byte word the offsets are 0, 4 and 8 (`RocList` is three `usize`
fields, `list.zig:27-33`). Each store writes 8 bytes, so the length store
covers bytes 4 to 11 and runs into the capacity field. The right result is
three 4-byte stores. The same holds at every `.w64` access to a RocStr or
RocList field. Arithmetic has the same habit: it computes in 64-bit
registers and finds overflow by narrowing from 64 bits, which can't work
when a 32-bit integer already fills the word.

## What this enables

- **Follows directly:** part 6 (arm32 code generator) can instantiate the
  driver with a 4-byte word once it lifts the 8-byte assert. Its
  word-sized paths are already right.
- **Follows directly:** the nine "Classify" commits (part 3) build on this
  vocabulary instead of bringing their own.
- **Possible later, not planned:** any other 32-bit dev backend target
  (wasm32 through the dev backend, 32-bit x86) starts from the same
  word-relative driver.

## Background

- **Word:** the size of a pointer and of every `usize` value (lengths,
  capacities, refcounts, indices): 8 bytes on x86_64 and aarch64, 4 on
  arm32.
- **Wide64:** a genuinely 64-bit value (`I64`, `U64`, `F64` bits) on a
  32-bit target. It doesn't fit one register, so it needs a register pair
  or memory. Only 32-bit targets have one.
- **J1:** the reference's milestone label for lowering Wide64 values. It
  means nothing upstream.

The five commits, oldest first, with their size in the driver and the two
`Emit.zig` files. Left out: the reference's notes files, as in step 5, and
its `src/backend/dev/arm32/DESIGN.md`, which three of the commits edit and
which doesn't exist on `dispatch/isa`.

| Reference | Subject | Lines |
|---|---|---|
| `bf9d0e0d49` | Derive the word size and RocStr/RocList field offsets from the target | +251/−223 |
| `0676c747be` | Make one-register integer arithmetic word-relative and classify low-level pointer sites | +314/−240 |
| `75e30d5f49` | Make integer conversions word-relative and name the Wide64 register width | +177/−166 |
| `b2ec6583e4` | Make structural equality word-relative | +64/−60 |
| `e7d97b7d88` | Make scalar bit counts word-relative | +51/−48 |

In all, +857/−737 as written. The first commit shrinks on upstream:
upstream already derives `target_ptr_size` from the target and has
`RocStr.targetFieldOffset` and `RocList.targetFieldOffset`, which replace
the reference's `strFieldOffset` and `listFieldOffset`. What's left of it is
`word` (the register width of a `usize`, `CC.WORD` in each `Emit.zig`),
`word_size`, `wordOffset`, the change from `.w64` to `word` at every
RocStr and RocList access, and the small-string literal path, which stops
bit-casting a word's bytes to u64 (through a `WordBits` integer type).

`wordOffset(i)` is `i * word_size`, the offset of word `i` in a
word-by-word copy (115 call sites). Upstream's `utils.targetWordOffset`
(`src/builtins/utils.zig:289`) does a different job: it converts a host
struct's byte offset to the target's, which is what `targetFieldOffset`
uses. The copy loops have an index, not a host field, so `wordOffset`
stays, and its doc comment says how it differs from `targetWordOffset`.

The 8-byte assert (`LirCodeGen.zig:503`) is upstream's, not the
reference's, and it stays through part 1. So every branch for a 4-byte
word compiles in part 1 but never runs. Part 6 lifts the assert.

## Discussion

- **Acceptable upstream** (as in the branch doc): no reference leftovers,
  which here means no TODO, no J1, and no references to the reference's
  design notes ("D6 of projects/big/arm32-dev-backend.md"). Upstream's
  names win where both exist (`targetFieldOffset`, `target_ptr_size`).
- **AGENTS.md:** a branch that can't run is an invariant: a comptime
  assert or `unreachable`, never a runtime check.
- **64-bit output unchanged:** byte-identical x86_64 and aarch64 objects.
- **Each commit builds and passes on its own.**
- **Plan order:** the width vocabulary for Wide64 (`wide64_reg_width`,
  `wide64_store_width`, `emitStoreImm64`) belongs to part 3 (HANDOFF, open
  decisions).
- **Commit messages:** rewritten for upstream: no "(A2)" suffix, no D6, J1
  or design-note references. Author dates are kept, as in step 5.

### Alternatives considered

- **All 14 A2 commits.** Rejected by branch D2 (2026-10-25).
- **Cut one squashed commit from the reference's final state.** Rejected
  because the six commits each change one kind of operation, and
  reviewers can check each against the oracle; one +857/−737 commit hides
  that.
- **`0676c747be` as one commit.** Its subject ends "and classify low-level
  pointer sites": besides arithmetic, it moves the list-map, list-replace,
  list-set and list-concat zero-size paths, byte-index addressing, the
  compare result and saved heap pointers to words, and rewrites
  `str_from_utf8` to write `StrFromUtf8Layout` field by field. Split
  instead into two commits (2 and 3 below), so each changes one kind of
  thing. Leaving the pointer half to part 3 with the "Classify" commits
  was also possible, but branch D2 took the whole commit into #9.

## Decisions

### D1. Where the borrowed definitions go (Q1)

- **Status:** Accepted (2026-10-26)
- **Context:** Three of the commits use names that the reference defines
  in "Classify" commits, which go to part 3:
  - `word_bits` (`word_size * 8`), from `1732f08923`: used 14 times in
    `0676c747be`, 23 in `75e30d5f49` and 8 in `e7d97b7d88`.
  - `wordOfU128` (one word of a 128-bit constant), from `da4cb4a451`: used
    4 times in `e7d97b7d88`.
  - `generateWide64IntUnary`, from `da4cb4a451`: used once in
    `e7d97b7d88`. Its body is only the J1 placeholder (see D2).

  The `word_bits` counts are uses in code, not in comments.
- **Alternatives:**
  1. Define each where it belongs: `word_bits` in the first commit with
     the rest of the word vocabulary (`word`, `word_size`), although its
     first user is commit 2 (a container-level declaration, so Zig accepts
     it unused); `wordOfU128` with its first user, the bit-count commit.
     Implications: each commit builds alone; the "Classify" commits in
     part 3 lose these definitions; no extra review.
  2. Bring `1732f08923` and `da4cb4a451` whole. Implications: +363/−341
     more lines, mostly relabelling that branch D2 sent to part 3.
  3. Rewrite the four commits without these names. Implications: spells
     `word_size * 8` 45 times; part 3 then renames them all back.
- **Recommendation:** Alternative 1. `generateWide64IntUnary` follows D2.
- **Consequences:** part 3's cut of the two "Classify" commits leaves these
  definitions out.

### D2. The 32-bit-only placeholders (Q2)

- **Status:** Accepted (2026-10-26)
- **Context:** Two commits add paths for Wide64 values that only a 32-bit
  target takes, each ending in a placeholder:
  - `0676c747be`: `@compileError("arm32: TODO Wide64 integer arithmetic (J1)")`
  - `75e30d5f49`: `wide64_reg_width`, which is `word` on an 8-byte word and
    otherwise `@compileError("arm32: TODO this site holds a Wide64 in one
    register; lower it as a pair (J1)")`, plus a second placeholder for
    conversions.
  - `e7d97b7d88`, through D1: the call to `generateWide64IntUnary`.

  The doc comments next to them cite J1 and D6. With the 8-byte assert in
  place, none of these can be reached in part 1.

  `0676c747be` also adds `emitStoreImm64`, which isn't a placeholder: its
  32-bit branch stores a 64-bit immediate as the low word, then the high
  word. Its doc comment cites "D6's `Wide64`", and the rewritten
  `str_from_utf8` uses it for the u64 tags of `StrFromUtf8Layout`.
- **Alternatives:**
  1. Leave the Wide64 paths out of part 1, `emitStoreImm64` included. A
     store or load of a genuinely 64-bit value keeps `.w64`, which is
     correct for it; the `str_from_utf8` tag stores are such sites. Part 3
     brings `wide64_reg_width`, `emitStoreImm64`, the Wide64 paths and
     their lowering together. In arithmetic, conversions and bit counts
     there is no separate 64-bit site: I32 and I64 go through the same
     word-relative code, and only the dropped dispatch
     (`if (comptime word_bits < 64)`) would send I64 elsewhere on a 4-byte
     word. Without it, an I64 there would reach
     `std.debug.assert(shape.bits < word_bits)` in `intOverflowCheck`, and
     conversions would underflow `word_bits - spec.src.bits()`. Both are
     unreachable while the 8-byte assert stands. Implications: smaller
     commits; no placeholders; `75e30d5f49` loses its second half ("name
     the Wide64 register width"), and its message changes; matches the
     plan's split (Wide64 vocabulary in part 3).
  2. Keep the paths, with upstream wording, for example
     `@compileError("64-bit integer arithmetic needs a register pair on
     32-bit targets")`. Implications: part 1 ships code no target uses;
     reviewers see promises for code that isn't there yet.
  3. Keep them as `unreachable` with a reason. Implications: like 2, and
     the error moves from compile time to run time.
- **Recommendation:** Alternative 1.
- **Consequences:** part 3 grows by the Wide64 paths. In part 1, a site that
  holds a 64-bit value and a site that holds a word look different (`.w64`
  against `word`), which is the distinction part 3 needs. Part 3 must add
  the Wide64 dispatch in arithmetic, conversions and bit counts no later
  than the commit that lifts the 8-byte assert. Otherwise I64 code on
  arm32 fails a debug assert, and is undefined behavior in release builds.

### D3. Where the new unit tests go (Q3)

- **Status:** Accepted (2026-10-26)
- **Context:** HANDOFF asks for unit tests of the layout helpers at a
  4-byte and an 8-byte word. `LirCodeGen(target)` can't be instantiated
  with a 4-byte word while the assert stands, so a helper is testable at
  4 bytes only if it takes the word size as a parameter. The tests:
  - `RocList.targetFieldOffset` and `RocStr.targetFieldOffset` at 4 and 8.
    Upstream checks them only at the host word (comptime asserts at
    `@sizeOf(usize)`, `list.zig:50-55`, `str.zig:104-108`), and they
    already take the word size. This is HANDOFF's layout-helper test.
  - `intOverflowCheck`: `0676c747be` brings a test ("one-register
    integers range-check below the word and use flags at the word"), but
    only at 8-byte targets (x64linux, arm64mac). The 4-byte case is the
    one with new logic (I32 takes the flag path), so `intOverflowCheck`
    becomes a function of the word's bit count and the test covers 32
    and 64.
  - `wordOfU128` at 4 and 8.

  `wordOffset` gets no test of its own: it is one multiplication.
- **Alternatives:**
  1. Each test in the commit that adds its helper. Implications: upstream's
     habit (tests next to code); each commit carries its own proof.
  2. One test commit at the end. Implications: easy to review apart, but
     the helper commits arrive untested.
- **Recommendation:** Alternative 1.
- **Consequences:** `intOverflowCheck` and `wordOfU128` become small
  functions of the word size that `LirCodeGen` calls with its own, a
  change from the reference.

### D4. When the notes are updated (Q4)

- **Status:** Accepted (2026-10-26)
- **Context:** steps 1 to 5 got their write-ups after the code. HANDOFF and
  the README Progress line were updated in batches.
- **Alternatives:**
  1. After the step's commits are reviewed: the step write-up
     (`step-6-word-size.md`), HANDOFF and README in one `notes` commit.
     Implications: one review per step, notes never ahead of the code.
  2. Only at the end of the fold (step 8). Implications: fewer commits, but
     HANDOFF is stale for the sync machine in between.
- **Recommendation:** Alternative 1.
- **Consequences:** one extra `notes` commit per step.

## Risks

### R1. A changed byte in 64-bit output

- **Likelihood:** Medium
- **Impact:** High
- **How we'd notice:** `run-check-snapshots` (the `dev_object` snapshots)
  after each commit; the relative oracle once, after the last.
- **Mitigation:** on 8-byte targets `word` is `.w64` and `word_bits` is 64,
  so every rewritten site emits the same instruction. The reference proved
  each commit the same way: `dev_object` snapshots and eval-corpus object
  hashes.
- **If it happens:** find the site in that commit's diff and fix it there.

### R2. A missed word-sized site

- **Likelihood:** High
- **Impact:** Low
- **How we'd notice:** nothing in part 1; the arm32 tests from part 6 on.
- **Mitigation:** the reference's later commits list what they caught;
  the reference check (branch doc, Testing) compares with `e0fa273ebf`.
- **If it happens:** fixed when part 6's arm32 tests find it.

### R3. Conflicts with upstream's newer driver code

- **Likelihood:** High
- **Impact:** Low
- **How we'd notice:** the cherry-picks stop.
- **Mitigation:** rebase first (branch D3), so the conflicts are resolved
  once, on the code #9 ships on.
- **If it happens:** resolve toward upstream's code and names, as in
  step 5.

## Testing

From the `dispatch/isa` worktree (`.workspaces/pr-isa`), after each commit:

```
zig build run-check-zig-format run-check-unreachable-rationale
```
```
zig build run-test-zig-module-backend
```
```
zig build run-check-snapshots
```

After the last commit, the full set from step 5 (about 15 minutes), and
the relative oracle on x86_64 and aarch64 against the step's base (the
branch doc's Testing section has the commands; about an hour, up to about
20 GB). Expected: everything passes, and the oracle reports identical
bytes.

## Recommendation

Before code: rebase onto `629c3e0e2d` (branch D3, accepted).

Then D1 alternative 1, D2 alternative 1, D3 alternative 1 and D4
alternative 1, giving six commits:

1. Name the target word in the dev backend driver (from `bf9d0e0d49`, with
   `word_bits`, the `targetFieldOffset` tests at 4 and 8, and the updated
   comment above the assert; upstream's `targetFieldOffset` kept).
2. Make one-register integer arithmetic word-relative (first half of
   `0676c747be`, without the Wide64 path; `intOverflowCheck` as a function
   of the word's bit count, tested at 32 and 64).
3. Move low-level pointer sites to words (second half of `0676c747be`;
   the `str_from_utf8` tag stores keep `.w64`, without `emitStoreImm64`).
4. Make integer conversions word-relative (from `75e30d5f49`, without
   `wide64_reg_width` and the Wide64 path).
5. Make structural equality word-relative (from `b2ec6583e4`).
6. Make scalar bit counts word-relative (from `e7d97b7d88`, with
   `wordOfU128` and its test, without the Wide64 call).

Each commit gets its own review before the next starts, as in step 5.
