# Fold step 8 of 9: #9's title and description (draft)

The new title and description for fork PR #9, for review before anything
changes on GitHub. Everything between the two `====` lines is the
description as it would be posted.

**Title** (decided 2026-10-27: name the target "32-bit ARM", and explain
it in the description):

Prepare the dev backend's shared driver for 32-bit ARM (1 of 3)

====

## What this does

The dev backend can generate machine code for two kinds of CPU: x86_64 and aarch64. Both are 64-bit. This PR gets its shared code ready for a third kind, 32-bit ARM, which comes later in the plan.

**What "32-bit ARM" means here:** the 32-bit mode of Arm processors, as on ARMv7-A processors and on 64-bit Arm processors running 32-bit code. Arm's own name for that 32-bit mode is AArch32. It has two instruction sets, A32 and Thumb (T32). The backend generates A32 only, not Thumb. Roc's targets for it are `arm32musl` and `arm32linux`.

Two things stand in the way, and this PR starts on both:

- **The code assumes there are only two architectures.** About 220 places pick one of the two with an `if`/`else`, so the `else` quietly means "the other one". A third architecture would fall into whichever branch happened to be the `else`, with no error.
- **The code assumes a 64-bit target.** It reads and writes values that are one "word" long (pointers, lengths, sizes) as 8 bytes. On a 32-bit target a word is 4 bytes.

Nothing changes for x86_64 and aarch64: the generated code is byte-for-byte the same as before (see Tested).

This is part 1 of the 32-bit ARM work. Parts 2 and 3 finish the word-size changes, and the 32-bit ARM code generator itself arrives in part 6. The branch is on upstream `26436de489`.

## The changes

The 15 commits, in order, grouped by what they do.

**Choosing the architecture in one place**

- `36825aa1f9` Decide the dev backend's architecture through one Isa type.
  A new file, `isa.zig`, names the supported architectures (`Isa`). `isaOf` turns a compile target into one of them, and refuses anything else at compile time (big-endian aarch64 included, which no target uses). `Isa.binaryIs` replaces the old two-way checks in `LirCodeGen`, `FrameBuilder` and `CallingConvention`. It only works while there are exactly two architectures, so adding a third turns each of those checks into a compile error until someone gives it a real answer.

**Running generated code, the glibc stub, and relocations**

- `200333a587` Flush the instruction cache before making JIT memory executable.
  On ARM, a CPU can run old instructions from memory that was just rewritten, unless the code is flushed first. x86_64 doesn't need this, so it was never done. The flush the machine-code shim already had now moves into the dev backend, and runs before generated code is made executable.
- `3d73760a5b` Use correct instructions for 32-bit ARM.
  The generated glibc stub used `ret`, which doesn't exist on 32-bit ARM. It now returns with `mov r0, #0` and `bx lr`, and `abort` exits with `exit_group(1)`.
- `8b9b055402` Write all eight bytes of an abs64 relocation on any host.
  An 8-byte address in the generated code was patched with the size of the compiler's own word. A compiler running on a 32-bit machine wrote only half of it. A new test covers it.

**Using the target's word, not the compiler's**

In a few places the backend measured the target's memory with the compiler's own word size (`@sizeOf(usize)`). That's only right when both are 64-bit.

- `a6b1c06b0c` Size target data by the target's word in the dev backend driver: a Debug check on string pointers, the array of erased-call descriptors, and where a drop function's pointer is stored.
- `863bcaa8e7` Lay out erased-callable payloads by the target's word. The offsets now come from the builtins' structs scaled to the target's word, and a compile-time check makes sure every field is pointer-sized.
- `bd4c9b9add` Check the hot-reload capture prefix against the target's layout.
- `3ce5cb09f3` Size new erased-callable payloads by the target's layout.
- `1b569dfd0d` Report the wasm eval backend unavailable on 32-bit hosts. The wasm interpreter (bytebox) reserves all 4 GiB of a wasm module's memory up front, which a 32-bit process can't do. Freestanding builds don't use bytebox and keep wasm.
- `6cd2d68e6d` Skip CLI tests that instantiate wasm32 output on 32-bit hosts, for the same reason.

**Reading and writing a word at the target's size (word size, 1 of 3)**

`word` is the register width of one target word: 8 bytes today, 4 bytes on a 32-bit target. `word_bits` is the same in bits.

- `9c6152e666` Access RocStr and RocList fields at the target's word width.
  The fields of strings and lists are already placed by the target's word. This makes the loads, stores, shifts and copies of those fields use `word` too. With 8-byte accesses, a 4-byte target would overwrite the next field.
- `4ca2daf8fa` Make one-register integer arithmetic word-relative.
  How an operation checks for overflow used to depend on the type's name. It now depends on whether the type is narrower than a word (a range check) or a full word (the CPU's overflow flags). `intOverflowCheck` makes that choice, and has a test.
- `b7a9abbcc9` Compute low-level pointers at the target's word width: the index arithmetic of the unchecked list and byte operations, and heap pointers saved on the stack.
- `daf1c616f6` Make integer conversions word-relative.
  Sign and zero extension now shift by `word_bits - n`, not `64 - n`. Unsigned-to-float picks its conversion by comparing the source's width with the word's. Widening into a 128-bit integer fills every higher word with the sign or zero.
- `1bc3981a38` Make scalar bit counts word-relative: population count, and leading and trailing zeros.

## Cost

- 23 files, 1,069 lines added and 804 removed. Most are in `LirCodeGen.zig`, and most of those are one-line swaps from a fixed 8 bytes to `word`, or from an old architecture check to `binaryIs`. The overflow checks, the conversions and the bit counts are restructured.
- No new CI steps. The new unit tests (`isaOf`, `binaryIs`, the abs64 patch, `targetFieldOffset`, `intOverflowCheck`, `wordOfU128`) take seconds.
- What maintainers need to keep doing: a new two-way architecture check goes through `isa.binaryIs`, and a value that is one target word uses `word` and `target_ptr_size`, not a fixed `.w64` or 8.

## Not done yet

- The backend still refuses any target whose word isn't 8 bytes (`LirCodeGen.zig:506`), so no 32-bit target can be built yet. That check goes in part 6, together with the 32-bit ARM tests.
- About 540 places still use a fixed 8 bytes: calls, values spread over several registers, erased calls, and the two halves of 128-bit integers. Parts 2 and 3 handle most of them. Arguments passed in memory belong to part 7 (the 32-bit ARM calling convention), and 64-bit values in two 32-bit registers to part 8.

## How the code flows

1. The dev backend is built once per target, at compile time: `LirCodeGen(target)`, with `FrameBuilder` and `CallingConvention` for the same target.
2. Each one asks `isaOf(target)`, which gives `x86_64` or `aarch64`, and stops the build for anything else. A two-way choice asks `isa.binaryIs(...)`. A choice with more answers is a `switch` over every `Isa`.
3. `LirCodeGen` works out `word` and `word_bits` from the target's pointer size, `target_ptr_size`. String and list fields sit at `targetFieldOffset(field, target_ptr_size)`, and erased-callable payloads at `erased_layout`'s offsets for the target.
4. Anything that is one target word (a pointer, a length, a capacity, a word-sized integer) is read, written and computed at `word`, and given a `target_ptr_size` stack slot. Today `word` is 8 bytes, so x86_64 and aarch64 get exactly the instructions they got before.
5. Before generated code runs, `ExecutableMemory` flushes the instruction cache. On x86_64 that returns straight away.

## Tested

All on this PR's head, `1bc3981a38`.

- **The usual checks pass:** the format and unreachable-reason checks, and the builtins, backend, `roc`, check, compile, eval, LIR inline, snapshot tool and snapshot tests.
- **`zig build minici` passes**, every phase. It was run as its six Linux shards, split across two machines.
- **The generated code doesn't change.** For every eval case (2,373), the x86_64 and aarch64 object files are byte-for-byte the same as upstream `26436de489`'s, and so are the 64-bit lines of all 16 `dev_object` snapshots. Both sides were built as the same compiler version. This needs a per-case hash mode that upstream doesn't have, which our tooling adds to both sides for the comparison, so it isn't a step you can run from this PR alone.
- **On real aarch64 hardware,** a Raspberry Pi (which we do), whose instruction and data caches are separate: the full eval runner passed five times out of five, each time with 2,593 passed, 0 failed, 0 crashed and 47 skipped of 2,640, the same as on x86_64. The backend's unit tests passed too, including `execute aarch64 code`, which writes, flushes and runs code. That machine's kernel uses 16 KiB memory pages, which exposes a separate upstream bug, so these runs had #10's two-line fix on top.
- **On real 32-bit ARM hardware,** the eval runner was run at this PR and at upstream, and compared. (It runs only the interpreter there, and was built in ReleaseSafe mode, because a Debug build of the runner doesn't link for 32-bit ARM.) The only differences come from this PR's wasm change: every wasm case failed upstream with `WasmExecFailed`, and is skipped here. Both runs share the same other failures, which are older problems on 32-bit hosts and not caused by this PR: 9 interpreter failures, 4 interpreter crashes, and 2 deep-nesting cases that ran out of the machine's 920 MB of memory.

Part 1 of the Incremental Plan. For review here first, not for upstream yet. It includes #8 (the flush), #3 (abs64) and closed #4 (the glibc stub).

## Where this PR sits in the plan

| # | Pull request | Where it sits |
|---|---|---|
| 0 | Proposal to the maintainers (no code) | none |
| **1** | **Architecture dispatch (`isa.zig`, `binaryIs`) and driver word size (1 of 3): sizes through `word`. With the glibc stub's arm32 body, the instruction cache flush and the host word-size fixes** (this PR) | **dev backend: architecture choice and shared driver, plus glibc stub, code in memory, relocations** |
| 2 | Driver word size (2 of 3): emit helpers move onto each code generator | dev backend: shared driver |
| 3 | Driver word size (3 of 3): the rest of `LirCodeGen.zig`'s 64-bit assumptions | dev backend: shared driver |
| 4 | A32/NEON encoder and its assembler oracle | dev backend: instruction encoder |
| 5 | ELF32 objects, ARM relocations, 32-bit DWARF | output: object file |
| 6 | arm32 code generator, frames, register roles | dev backend: per-architecture code generator |
| 7 | AAPCS32 calling convention | dev backend: calls (C ABI, frames) |
| 8 | 64-bit and 128-bit values on 32-bit registers | dev backend: shared driver |
| 9 | NEON SIMD | dev backend: shared driver |
| 10 | arm32 targets, platforms, runtime files, CI lane | CLI target (start) and linking (end) |
| 11 | arm32 as a host (running code in-process) | output: code in memory |
| 12 | Docs, and turning the CI lane from optional to required | none |

## How to test

From the repository root, run:

```sh
zig build run-check-zig-format run-check-unreachable-rationale run-test-zig-module-builtins run-test-zig-module-backend roc run-test-zig-module-check run-test-zig-module-compile run-test-zig-module-eval run-test-zig-lir-inline run-test-zig-snapshot-tool run-check-snapshots
```

```sh
zig build minici
```

Both should pass.

On an aarch64 Linux machine, also run the command below. If its kernel uses 16 KiB pages (`getconf PAGESIZE` prints 16384), apply #10 first.

```sh
zig build run-test-eval
```

It should pass with the same counts as on x86_64.

====
