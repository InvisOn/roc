# Name every width in the dev backend's shared driver

- **Status:** Accepted 2026-11-08
- **Scope:** one PR, plan rows 1 to 3 (follows step 1, upstream PR 12740)
- **Branch:** `isa-word-size` (worktree `.workspaces/pr-isa-word-size`)
- **Base:** upstream `main` at `ad3a5d2830` (2026-11-06), rebased whenever `main` moves
- **Inventory:** `w64-inventory/` (README, TSVs, classify scripts)
- **Supersedes:** `word-size-2-3-plan.md` D1 to D4 for the word-size work
  (the register seams of its D1 are not part of this PR)

## Abstract

Rename every width in the shared driver so that it says what it is: a
target word, a value that is 64 bits on every target, or a scalar that
fits one 64-bit register today. On x86_64 and aarch64 every name is `.w64`,
so the generated code is byte-identical and the PR is a pure rename. On a
4-byte target only the word name has a value; the other two are compile
errors. A 32-bit backend therefore gets a compile error at exactly the
sites that need a register pair or routing, the way a missing
`switch (isa)` arm forces an answer for a new instruction set. The
inventory supplies the per-site choice; the review is of the diff.

## Problem

The driver writes almost every width as `.w64`. That spelling covers two
meanings that only differ on a 32-bit target: one target word (a pointer,
a length) and 64 bits on every target (a U64, an i128 half). Hidden widths
add to it: helpers that always use a whole 64-bit register
(`emitLoadImm`, `emitMovRegReg`, `emitCmpReg`), literal 8s and 64s that
stand for the word or the register, and structs laid out with the
compiler's own `usize`. `LirCodeGen.zig:352` asserts an 8-byte word, so
none of this is wrong today, and no test can tell the meanings apart.

The inventory (`w64-inventory/README.md`) found and classified every such
site at `ad3a5d2830`.

## Design

### Width names

Defined once in `LirCodeGen` next to `target_ptr_size`, with the driver's
`RegisterWidth` chosen by `switch (isa)`:

- `word_width`: one target word. `.w64` at an 8-byte word, `.w32` at a
  4-byte word.
- `wide64_width`: a value that is 64 bits on every target (U64, I64, F64
  bits, an i128 or Dec half, the hasher's state). `.w64` at an 8-byte word;
  at a 4-byte word a compile error worded as an invariant: "a 64-bit value
  needs a register pair on a 4-byte-word target".
- `scalar_width`: an integer or bit pattern of up to 8 bytes held in one
  register, whose width follows its layout (D1). `.w64` at an 8-byte word;
  at a 4-byte word a compile error: "a scalar of up to 8 bytes in one
  register; route 8-byte values to a pair first, then use `word_width`".
- `word_bits` and `scalar_bits`: the matching bit counts for shift amounts
  and bounds (`64 - bits` becomes `scalar_bits - bits`).

Zig resolves a `const` lazily, so a compile-error name fails only where a
function that uses it is analyzed for a 4-byte target, which is every such
function once a 32-bit backend exists.

### What each inventory kind becomes

- **word**, **piece**, **chunk** (`.w64`): `word_width`. Literal 8s of these
  kinds (strides, piece sizes, chunk steps, register counts
  `(size + 7) / 8`) become `target_ptr_size`.
- **64**: `wide64_width`. Literal `+ 8` to a high half stays 8: a 64-bit
  value is 8 bytes on every target.
- **scalar**: `scalar_width`; **reg-bits**: `scalar_bits`.
- **size-8** (an `8 =>` arm, `.qword`, "fits one register" at `<= 8`): the
  arm's width becomes `wide64_width`; a bound that means "one register"
  becomes `target_ptr_size`.
- **narrow**, **neutral**, **bits**, **compiler**, **isa**: unchanged.
- **host-layout**: offsets and sizes from a target-layout function (D4).
- **Helper calls**: see D2. **Builtin arguments**: see D3.

### The `design.md` paragraph

The PR adds one paragraph to `design.md` "Dev Backend Instruction Sets",
after the paragraph on `switch (isa)`. It states seven rules. Each commit
adds the sentences of the rules it makes true, so `design.md` never
describes code that does not exist yet.

The finished paragraph, with the commit that adds each part:

> **[commit 1]** The shared driver also serves every word size, and names each
> register width by the kind of value: `word_width` for a target word
> (pointers, lengths, sizes, addresses), `wide64_width` for a value that is
> 64 bits on every target (U64, I64, F64 bits, an i128 or Dec half), and
> `scalar_width` for an integer of up to 8 bytes held in one register whose
> width follows its layout. **[commit 7]** Shared code never writes `.w64`, which
> names no kind of value; `ci/zig_lints.zig` rejects a `.w64` outside a
> `switch (isa)` arm. **[commit 1]** A width follows the kind of value, never an
> immediate's numeric value: a small U64 is still 64 bits. **[commit 2]** No helper
> has an implied width: every helper that works on a register takes
> `comptime width: RegisterWidth`, so a call without a width does not
> compile. **[commit 4]** A call argument that fills a `u64` or `i64` parameter goes
> through a `…Wide64` builder method, and the call asserts in debug builds
> that each argument's width matches the callee's signature. **[commit 6]** A
> struct shared with the runtime is laid out by the target-layout function,
> never by the compiler's own `@sizeOf` or `@offsetOf`, which describe the
> host. **[commit 5]** Word sizes and register bit counts are `target_ptr_size`,
> `word_bits` or `scalar_bits`, never a literal 8 or 64; a 64-bit value's
> own size stays 8. **[commit 1]** A 32-bit instruction set's `RegisterWidth` has
> no `w64` member, so `wide64_width`, `scalar_width` and a stray `.w64` are
> compile errors on it until the driver routes those values through
> register pairs.

The rules, where they come from, and the commit that adds each:

1. No raw `.w64` in shared code; the width is named (D5). Commit 7, with
   the lint: commits 2, 3 and 5 remove the last raw `.w64`, and the lint
   makes the rule hold.
2. The width follows the kind of value, never the immediate's value (D2).
   Commit 1, with the names.
3. No helper has an implied width; helpers take `comptime width:
   RegisterWidth` (D2). Commit 2.
4. Arguments to `u64` and `i64` parameters go through `…Wide64` methods,
   checked against signatures in debug builds (D3). Commit 4: the methods
   come in commit 3, the check in commit 4.
5. Runtime structs use the target-layout function, never `@sizeOf` or
   `@offsetOf` (D4). Commit 6.
6. Word sizes and register bit counts are `target_ptr_size`, `word_bits`
   or `scalar_bits`, never a literal 8 or 64. Commit 5: the word sizes
   change in commit 2, the register bit counts in commit 5.
7. A 32-bit `RegisterWidth` has no `w64` member (D5). Commit 1, with the
   names, whose compile errors depend on it.

### Size

From the inventory's counts (lines touched, not counting definitions):

- `.w64` sites: word 319, 64 158, scalar 97, piece 18, chunk 16, size-8 9
  (617)
- helper calls: about 300, every shared call names its width (D2)
- builtin arguments with a 64-bit parameter: 82 (D3)
- literals: eights 30, sizes 93
- target-layout function and its 32 sites (D4): about 100; names, `design.md` paragraph, lint: about 100
- signature tables and the argument-width check (D3): about 90

About 1,450 changed lines, nearly all one-line substitutions, under the
plan's 2,000-line limit.

## Commits

Each commit builds, passes the tests, and leaves x86_64 and aarch64 output
byte-identical.

1. **Add the width names** (`word_width`, `wide64_width`, `scalar_width`,
   `word_bits`, `scalar_bits`) and the word-size paragraph of `design.md`
   "Dev Backend Instruction Sets", with the names and rules 2 and 7 (see
   "The `design.md` paragraph"). No uses yet.
2. **Word-sized values use `word_width`:** the helpers that hide a width
   take `comptime width` (D2); the word, piece and chunk `.w64`s in
   `LirCodeGen` and `CallingConvention`, the word, narrow and chunk helper
   calls, their literal 8s as `target_ptr_size`, and `str_small_bit` as a
   `word_bits` integer (D6); `design.md` rule 3. About 560 lines.
3. **64-bit values use `wide64_width`:** the 64 and size-8 sites, the
   64-bit helper calls, and the builtin arguments with a 64-bit parameter through
   the `…Wide64` builder methods (D2, D3). About 370 lines.
4. **The call builder checks argument widths against signatures** (D3):
   the registry's and `exports.zig`'s parameter tables, the builder's
   per-argument width, and the debug assert in the call. About 90 lines.
   It comes after commit 3 so the tests pass with every argument named.
   `design.md` rule 4.
5. **Scalars use `scalar_width`:** the scalar sites, the register bit counts
   as `scalar_bits`, and the scalar helper calls; `design.md` rule 6.
   About 190 lines.
6. **Runtime structs laid out for the target's word** (D4): the
   target-layout function, its comptime check against `@offsetOf` on
   64-bit targets, and the 32 sites; `design.md` rule 5. About 100 lines.
7. **Lint: no raw `.w64` in the shared driver** (D5), and `design.md`
   rule 1. About 80 lines.

The edits of commits 2, 3 and 5 are applied from the inventory's TSVs by
line number and kind, then read in the diff; a site whose code no longer
matches its TSV row stops the script.

## Decisions

### D1. How many width names

- **Status:** Decided 2026-11-07: alternative 1.
- **Context:** 97 `.w64` sites, 40 register bit counts and 50 helper
  calls are scalars: one register holds a 1- to 8-byte integer whose
  width follows its layout. On a 4-byte target, values up to 4 bytes fit a
  word and 8-byte values need a pair, which the code can only tell at run
  time.
- **Alternatives:**
  1. Three names: `word_width`, `wide64_width`, `scalar_width`. Cost: one
     more name; the 32-bit backend must add the routing before its scalar
     paths compile. Benefit: every site that a 32-bit target can get wrong
     is a compile error; nothing is silent.
  2. Two names; scalars use `word_width` with a debug assert that the value
     fits (part 1's approach). Cost: an 8-byte value on an unrouted path
     is caught only in debug builds, at run time. Benefit: one fewer name,
     and scalar paths compile on a 32-bit target at once.
  3. Two names; scalars use `wide64_width`. Cost: loses which sites could
     use a word for small values. Benefit: simplest.
  4. `scalarWidth(size)` from the layout: `.w64` on 64-bit targets; on a
     4-byte target `.w32` up to 4 bytes and a debug assert at 8. Cost: the
     8-byte case is caught only at run time, and every site passes a
     size. Benefit: small scalars work on 32-bit with no routing.
  5. Scalars stay raw `.w64`, on an allow-list in the D5 lint. Cost: about
     180 lint exceptions until part 10, and the rule gets an exception.
     Benefit: about 1,260 lines; the decision moves to part 10.
  6. Each scalar site splits now (`if (size == 8) wide64_width else
     word_width`). Cost: about 180 runtime branches, design work that
     overlaps part 10. Benefit: no third name.
- **Consequences:** `scalar_width` marks exactly the sites part 10 must
  route through a register pair.

### D2. Helpers that hide a width

- **Status:** Decided 2026-11-07: alternative 1, with a typed width
  parameter.
- **Context:** `emitLoadImm` (the instruction set's, called about 220
  times), `emitCmpImm`, `emitCmpRegImm64`, `emitSaturatingSub`,
  `emitMovRegReg` and `emitCmpReg` always work on a whole 64-bit register.
  Most callers pass a word or a narrow value (word 152 and narrow 49 of
  347 shared calls). About 300 shared calls are outside instruction-set
  arms.
- **Alternatives:**
  1. Every such helper takes `comptime width` like `emitLoad` already does;
     every call names its width; the instruction sets' `emitLoadImm` gets a
     driver wrapper. Cost: about 300 call lines. Benefit: no default; a new
     call without a width does not compile, and a `wide64_width` or
     `scalar_width` call is a compile error on a 4-byte target.
  2. The helpers mean "a word"; `…Wide64` and scalar variants at the 64
     and scalar calls only. Cost: about 140 lines. Weakness: a new call
     that forgets the variant is silently word-sized; neither the lint nor
     the tests can see it.
  3. The width in the helper's name (`emitLoadImmWord`,
     `emitLoadImmWide64`, ...), no default name. Same safety as 1 and
     about the same size; 1 matches the existing `emitLoad(width, ...)`.
  4. Hybrid: a width parameter on the five less-called helpers (about 110
     calls), `emitLoadImm` keeps a word default with a `Wide64` variant.
     Cost: about 200 lines. Weakness: the hole stays for the most-called
     helper.
  5. A debug-build width tag per register, asserted by the helpers.
     Catches mistakes on 64-bit tests, but every move, spill and reload
     must carry the tag; out of proportion for a rename.
  6. Separate register types (`WordReg`, `Wide64Reg`). Thousands of lines;
     not realistic here.
  Choosing the width from the immediate's value is not an alternative: it
  is a heuristic (AGENTS.md) and wrong for a small U64.
- **Consequences:** no helper in the shared driver has an implied width;
  the lint (D5) and the compiler together cover every width. The helpers
  take `comptime width: RegisterWidth` (the driver's per-instruction-set
  alias), not `anytype`: on a 32-bit target a raw `.w64` then fails to
  coerce at the caller's line, not inside the helper. Same number of
  lines.

### D3. Builtin arguments with a 64-bit parameter

- **Status:** Decided 2026-11-07: alternative 4, with a table from
  `boxy_runtime/exports.zig` as well; `w64-inventory/check_args.py` stays.
- **Context:** 82 builder arguments fill a `u64` or `i64` parameter (U64
  operands, i128 halves, hasher values); the builder gives every integer
  argument one register or one stack slot. The builtin registry already
  reads its wrappers' signatures at compile time
  (`builtin_registry.zig:477`, the `writes_result_word_triple` table).
- **Alternatives:**
  1. `addRegArgWide64`, `addMemArgWide64`, `addImmArgWide64`: the same at an
     8-byte word, compile errors at a 4-byte word until the calling
     convention passes them as pairs. Cost: 82 lines and three small
     methods. Benefit: the calling convention work (part 7) gets a compile
     error per site. A wrong name stays invisible on 64-bit targets.
  2. Leave them; list them for part 7. Cost: silent until part 7 reads the
     list. Benefit: smaller PR.
  3. Every builder method takes a width; all 486 arguments name theirs.
     Cost: about 486 lines. Benefit: no default. A wrong name stays
     invisible on 64-bit targets.
  4. Alternative 1, plus a signature check: a compile-time table per
     callee of which parameters are `u64` or `i64` (from the registry's
     `dev_wrappers` signatures, and from `exports.zig` for the boxy runtime
     functions); the builder records each argument's width, and the call
     asserts in debug builds that every 64-bit parameter got a `…Wide64`
     argument and no other did. Cost: about 90 more lines. Benefit: a
     misnamed argument fails the existing tests on x86_64 and aarch64, and
     every argument is checked, including the 74 `check_args.py` cannot
     line up. A compiler invariant, so a debug assert and `unreachable` in
     release (AGENTS.md).
  5. Signatures only, no names at the call sites. Not workable alone: on a
     32-bit target the driver must still produce the high half, so each
     site has to know it is 64-bit.
- **Consequences:** the argument kinds are checked by the compiler's own
  tests, not only by reading. `check_args.py` stays as the inventory's
  independent cross-check.

### D4. Structs laid out with the compiler's own types

- **Status:** Decided 2026-11-07: alternative 3.
- **Context:** 32 `@offsetOf`/`@sizeOf`/`@alignOf` uses in 6 functions
  (`generateDyn`, `generateDynElemLowLevel`, `generatePackedErasedFn`,
  `generateCachedComposition`, `emitOwnPendingCell`,
  `emitDebugAssertValidStrLocal`) lay out `extern struct`s from the boxy
  runtime and the builtins (`ListOpRequest`, `FieldInput`,
  `DeclaredFieldInput`, `VariantInput`, `CompositionEntry`,
  `HotReloadCaptureHeader`, `Pending`) with the compiler's own `usize`, so
  they follow the compiler's word, not the target's. The LLVM backend uses
  the same `compose` structs (`MonoLlvmCodeGen.zig:11800`).
- **Alternatives:**
  1. One comptime assert per function that the compiler's word equals the
     target's. Cost: 6 lines. Weakness: only postpones the work; a 32-bit
     target cannot build those functions until it is done.
  2. One central assert at the top of `LirCodeGen`. Cost: 1 line.
     Weakness: blocks the whole driver for a 32-bit target, as the 8-byte
     gate already does.
  3. A generic target-layout function for any `extern struct`: pointers
     and `usize` take the target word, and each field's alignment comes
     from the target (`std.Target.cTypeAlignment`; a `u64` is 8-aligned on
     arm32, 4-aligned on i386). On a 64-bit target a comptime assert checks
     it against `@offsetOf` for every field of every struct, so output stays
     byte-identical and the function is proven by the compiler. Cost: about
     60 lines plus 32 one-line site edits. Benefit: these sites are correct
     on any word; no later step.
  4. Generic struct declarations (`ListOpRequest(Word)` and the like) in the
     runtime, used at `u32` by the compiler for a 32-bit target. Cost:
     changes the runtime's and builtins' declarations and every user,
     the LLVM backend included. Benefit: one source of truth.
  5. Leave them; list them in the PR description. Weakness: pointers at the
     wrong offsets on a 32-bit target, seen as crashes on the device.
- **Consequences:** the inventory's host-layout kind is done in this PR;
  the wasm backend's `wasm32FieldOffset` stays as it is (it could use the
  same function later).

### D5. A lint for raw `.w64`

- **Status:** Decided 2026-11-07: alternatives 1 and 2 together.
- **Context:** after commits 2, 3 and 5 the shared driver has no raw `.w64`
  outside instruction-set arms. `ci/zig_lints.zig` already holds checks of
  this kind (`checkElseSwitchProngs`).
- **Alternatives:**
  1. A lint that rejects `.w64` in `LirCodeGen`, `FrameBuilder` and
     `CallingConvention` outside `switch (isa)` arms. Cost: about 80 lines;
     the arm detection must match the inventory's (`brace_check.py`).
     Benefit: new code cannot reintroduce the ambiguity before a 32-bit
     backend exists.
  2. No lint; a 32-bit backend whose `RegisterWidth` has no `.w64` rejects
     raw uses itself, plus the rules in `design.md` (rule 7 in commit 1,
     rule 1 in commit 7). The arm32
     reference's `RegisterWidth` has only `w32`, so a raw `.w64` there is
     "no member named 'w64'" at its line, as a missing `switch (isa)` arm
     is. Cost: unprotected until then. Benefit: nothing to maintain.
- **Consequences:** the lint guards x86_64 and aarch64 from this PR on;
  the 32-bit backend's `RegisterWidth` must have no `w64` member, so the
  compiler also catches anything the lint's arm detection misses. Neither
  catches a wrong name (R1).

### D6. What stays out

- **Status:** Decided 2026-11-07: alternatives 1 and 2 together.
- **Context:** the inventory lists word-size work beyond naming:
  - the 8-byte assert (`LirCodeGen.zig:352`), and `str_small_bit`
    (`:364`), already derived from `RocStr.targetSmallStrBit` but typed
    `i64` and asserted to be `minInt(i64)` (`:365`), loaded at `:8364` and
    `:21687`;
  - the value model (`.stack` defaulting to `.qword`, one register per
    value);
  - the calling convention's 8-byte slots (`CallingConvention.zig:309`,
    `:316`, `:327`, `:345`) and 16-byte alignment (`:887`);
  - the Wide64 routing and lowering;
  - unit images, and the builtins' own 8-byte assumptions
    (`str_equal_static_small`'s `u64` words).
- **Alternatives:**
  1. A rename only: all of it stays out. Cost: none here. Benefit: x86_64
     and aarch64 output stays byte-identical and the review is about names.
  2. Also give `str_small_bit` a `word_bits` integer type, loaded with
     `word_width`; the gate stays. About 4 lines. Benefit: the last
     64-bit-typed word value in the setup is named like the rest.
  3. Also make the calling convention's slots word-sized, alignment left
     to part 7. About 10 lines, but slot size is the ABI's (AAPCS32: 4-byte
     slots, 8-byte alignment for 64-bit arguments) and untestable here.
  4. Also design the register-pair value model. Several hundred lines with
     no 64-bit effect, untestable here.
  5. Also fix the builtins' `u64` words. A different module and review,
     and no longer a rename.
- **Consequences:**
  - In this PR: `str_small_bit` as a word (commit 2).
  - The gate stays: it still guards what this PR leaves alone. It goes in
    part 6, with the 32-bit instruction set.
  - The value model: its size-8 sites become compile errors through
    `wide64_width`; the register-pair location is design work for the
    32-bit backend.
  - Slots and alignment: part 7. Wide64 routing and lowering: part 10.
  - Unit images and the builtins' `u64` words: listed in the PR
    description.

## Risks

### R1. A site gets the wrong name

- **Likelihood:** Low to medium (the inventory was read three times and
  cross-checked, but by hand).
- **Impact:** a word site named `wide64_width` or `scalar_width` becomes a
  needless compile error later (harmless); a 64-bit site named
  `word_width` is silently wrong on a 32-bit target.
- **Mitigation:** builtin arguments are checked against their signatures
  by the tests (D3). For the other sites, every `word_width` at a site
  whose value comes from a U64, I64 or i128 is the risk; the review reads
  commit 2 for that first.
- **If it happens:** fixed in the commit it belongs to.

### R2. `main` moves while the PR is open

- **Likelihood:** High. **Impact:** low: `rebase_lines.py` moves the
  inventory, and a changed line stops the scripts.

## Testing

- Per commit: the build, and the relative oracle against the base
  (`tools/relative_oracle.py`), which must report 0 differences for
  x86_64 and aarch64.
- From commit 4: the debug-build tests check every builtin argument's
  width against its callee's signature.
- At the end: `zig build minici`, a check that every renamed site's name
  matches its TSV kind, and `check_args.py` on the final tree.
- No device runs: nothing new runs on ARM.
