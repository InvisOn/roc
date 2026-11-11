This PR is the next step toward a 32-bit dev backend (my ARM32 backend is in the works). It follows the `switch (isa)` PR. It names every register width in the dev backend's shared driver (`LirCodeGen`, `FrameBuilder`, `CallingConvention`) and lays out the structs the driver shares with the runtime at the target's pointer width.

x86_64 and aarch64 output is byte-identical after every commit. On those targets every new name is `.w64`, so for them the PR is a rename. I checked this per commit by comparing the dev backend's generated code against upstream main.

The PR is 7 commits, and each one builds and passes the tests on its own. Reviewing commit by commit is easier than the whole diff.

## Problem: `.w64` means two things

The driver writes almost every width as `.w64`. That covers two meanings that only differ on a 32-bit target:

- one target word: a pointer, a length, a refcount
- 64 bits on every target: a `U64`, one half of an `i128`

There are hidden widths too: helpers that always use a whole 64-bit register (`emitLoadImm`, `emitMovRegReg`, `emitCmpReg`), literal 8s and 64s that stand for the word or the register, and runtime structs laid out with the compiler's own `@offsetOf`/`@sizeOf`. The driver asserts an 8-byte word, so none of this is wrong today, and no test can tell the meanings apart. A 32-bit backend would have to find each site by hand.

## The names

`widths.zig` defines three names. Each says what kind of value a width is for:

- `word_width`: one target word. `.w32` on a 4-byte target.
- `wide64_width`: 64 bits on every target. A compile error on a 4-byte target, because there it needs a register pair.
- `scalar_width`: a scalar that fits one 64-bit register today. A compile error on a 4-byte target, because the 32-bit backend has to decide per value.

So a 32-bit backend gets a compile error at exactly the sites that need a register pair or a decision, the same way a missing `switch (isa)` arm forces an answer for a new instruction set.

## Commits

1. **Add the width names** in `widths.zig`, with a test and the `design.md` paragraph. No uses yet.
2. **Word-sized values use `word_width`.** The helpers that hid a width take a `comptime width`. Word-sized literal 8s become `target_ptr_size`.
3. **64-bit values use `wide64_width`.** Builtin arguments with a 64-bit parameter go through new `…Wide64` call-builder methods.
4. **The call builder checks argument widths against the callee's signature.** The builtin registry and `exports.zig` get parameter tables, and a debug assert in the call compares them with each argument's width. So a 64-bit argument can only go to a `u64` or `i64` parameter.
5. **Scalars use `scalar_width`**, and register bit counts become `scalar_bits`.
6. **Runtime-shared structs are laid out at the target's pointer width.** This uses `boxy_runtime.desc.externLayout`, which gains a `usize`/`isize` arm and rejects field types it can't lay out at another width. Where the runtime has its own target-width function (such as `native_callable.pendingByteSize`), the driver uses that instead. A test pins `ListOpRequest` and the erased-callable `Payload` at 32-bit.
7. **A lint rejects `.w64` in shared code.** `ci/zig_lints.zig` now rejects a `.w64` in the three driver files outside code for one instruction set: a `switch (isa)` arm, the code after a `switch (isa)` that only one instruction set reaches, an `if` on a `comptime switch (isa)` that is true for one instruction set, a listed single-instruction-set function, or a test. Three remaining instruction-set choices become `switch (isa)` so the lint can see them.

`design.md` gains the rules in the "Dev Backend Instruction Sets" section as the commits go.

## What stays out

This PR only names widths. These stay as they are and are left for the 32-bit backend:

- the 8-byte word assert in `LirCodeGen`
- the value model (one register per value)
- the calling convention's 8-byte stack slots and 16-byte alignment
- 61 stack slots allocated with a literal `allocStackSlot(8)`. Some hold a word and some hold a 64-bit value.
- `emitDynFieldAddr`'s 24-byte field entry (a `boxy_runtime.Field` is 20 bytes on a 32-bit target)
- unit images, and the builtins' own 8-byte assumptions (for example `str_equal_static_small`'s `u64` words)

## Possible follow-up

`externLayout` and `PointerWidth` aren't specific to Boxy: this PR uses them for builtins structs, and the wasm and LLVM backends could use them too. A follow-up PR could move them next to `RocTarget` in `src/target/`, with `boxy_runtime` re-exporting them.
