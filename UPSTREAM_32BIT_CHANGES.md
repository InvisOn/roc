# Roc on 32-bit: upstream changes needed

As of 2026-10-20, upstream `main` at `cf05860a7c`.

Upstream Roc's dev backend assumes an 8-byte machine word, and in several
places it takes the size of the target's data from the machine the compiler
runs on. About 20 places need to change before Roc can build 32-bit programs
with the dev backend, or run on a 32-bit machine.

## Two kinds of 32-bit support

1. **Building 32-bit programs from a 64-bit computer.** The compiler runs on
   an ordinary x86_64 or aarch64 machine and writes code for a 32-bit ARM
   board. The problem is code that describes the *target's* memory with sizes
   from the *compiler's* machine, or with a fixed 8. Today those always agree,
   so nothing upstream is visibly wrong; they stop agreeing the moment a
   32-bit target exists.
2. **Running the compiler on a 32-bit computer** (e.g. a Raspberry Pi with a
   32-bit OS). The problem is code that does not compile for a 32-bit machine,
   and machine-specific pieces (jump stubs, setjmp/longjmp, cache flushing)
   that exist only for x86_64 and aarch64.

Goal 1 comes first. Goal 2 also needs goal 1: a compiler on a 32-bit machine
evaluates code at compile time with a dev backend for that same machine.

None of these changes alters the code generated for today's 64-bit targets.
On the arm32 branch where they were made, two compilers pinned to the same
version produce byte-identical x86_64 and aarch64 output.

## 1. A 64-bit compiler building 32-bit programs

| Location | What it does now | What it needs to do |
|---|---|---|
| `src/backend/dev/LirCodeGen.zig:520-522` | Refuses to compile for anything but x86_64 and aarch64. | Allow a 32-bit target once the rows below are fixed. |
| `src/backend/dev/LirCodeGen.zig:531-532` | Asserts the target word is 8 bytes; the comment says string and list words move with 64-bit loads and stores. | Remove the assertion; move words with loads and stores of the target's word size. |
| `src/backend/dev/LirCodeGen.zig:544-545` | Keeps the small-string flag as an `i64` and asserts it is bit 63. | Use the target word's top bit (bit 31 on 32-bit). |
| `src/backend/dev/LirCodeGen.zig:8223, 8236` | The Debug string check tests alignment against `@alignOf(usize) - 1`, the compiler machine's. | Use the target's word alignment; otherwise valid 4-byte-aligned strings fail the check. |
| `src/backend/dev/LirCodeGen.zig:14093, 14100` | Sizes and indexes the erased-call descriptor array by `@sizeOf(usize)`. | Use the target's word size. |
| `src/backend/dev/LirCodeGen.zig:14562, 14587` | Stores the erased-callable drop pointer at offset `@sizeOf(usize)` with an 8-byte store (`.w64`). | Target word size for both the offset and the store. |
| `src/backend/dev/LirCodeGen.zig:14393-14429, 14571-14607` | Lays out erased-callable payloads with `@sizeOf`/`@offsetOf` of the builtins structs as compiled for the compiler's machine. | Derive each offset from the target word; those structs hold only pointers, so on 32-bit every offset halves. |
| `src/backend/dev/LirCodeGen.zig:22311-22316` | `entrypointParamSlotSize` multiplies the register count by a literal 8. | Multiply by the target's word size. |
| `src/backend/dev/LirCodeGen.zig`, whole file | 792 8-byte loads/stores (`.w64`); fixed 8s in 83 `, 8)` and 40 `* 8` expressions; 12 uses of 56 as the small-string length shift. | Review each: most mean "one word", some really mean 64 bits (an `I64`, an `F64`, half of an `I128`), which on 32-bit take two registers. This is the bulk of the work. |
| `src/backend/dev/CallingConvention.zig:354, 616, 669` | Asserts an address argument (`.from_lea`) is 8 bytes. | Expect the target's word size. |
| `src/backend/dev/Relocation.zig:191-198, 255-266` | Recognizes a call to patch by guessing from the bytes: `0xE8` before the operand means x86_64; a 4-byte site means an aarch64 branch. | Pass in the instruction set the code was built for. On 32-bit ARM, ordinary instructions can begin with `0xE8`, so the guess patches the wrong bytes. |
| `src/backend/dev/Relocation.zig:329-337` | Chooses the width of an absolute-address patch (`abs64`) from the compiler machine's `usize`. | Use the width of the target's addresses. |
| `src/snapshot_tool/main.zig:3939` | The `dev_object` snapshot check lists only the 64-bit architectures. | Ask the dev backend which targets it supports, so 32-bit snapshots are checked too. |
| `src/build/glibc_stub.zig:24, 93` | Writes `ret` for 32-bit ARM, which has no such instruction. | Write `bx lr` for 32-bit ARM. |

## 2. The compiler running on a 32-bit computer

| Location | What happens now | What it needs to do |
|---|---|---|
| `src/eval/compile_time_host.zig:39` | `allocation_header_stamp: usize = 0x5f6d_6f63_7074_696d` does not fit a 32-bit `usize`. Debug and ReleaseSafe builds for a 32-bit machine fail to compile; ReleaseSmall hides it because the debug-only branch is never analysed. | Use a stamp that fits in 32 bits on 32-bit machines (e.g. `@truncate` from a `u64`). |
| `src/sljmp/linux.zig:6-11`, `src/sljmp/mod.zig:16` | setjmp/longjmp exist only for x86_64 and aarch64; other Linux machines hit a `@compileError`. The compile-time evaluator needs them to recover from a crash. | Add a 32-bit ARM version (saves R4-R11, SP, LR and D8-D15). |
| `src/backend/dev/LirCodeGen.zig:23282-23286` | `host_lir_codegen_available` is false for `.arm`, so a 32-bit ARM compiler has no native code generator for compile-time evaluation. | True for `.arm` once section 1 is done. |
| `src/backend/dev/HostSplice.zig:447-456` (tests 472, 573) | Writes a jump stub only for x86_64 and aarch64; the tests skip by naming those architectures. | Add a 32-bit ARM stub (`ldr pc, [pc, #-4]` followed by the target address); skip tests on `host_lir_codegen_available` instead. |
| `src/machine_code_shim/main.zig:475-481, 635-660` | `HostArch` knows only x86, x86_64 and aarch64; jump-stub sizes exist only for those. | Add 32-bit ARM. |
| `src/backend/dev/ExecutableMemory.zig:404-408` | Makes JIT memory executable with `mprotect` without flushing the instruction cache. Harmless on x86; ARM needs an explicit flush or it may run stale bytes. | Flush before making it executable. Upstream already has the flush (with a 32-bit ARM path) in `src/machine_code_shim/instruction_cache.zig:15-18`; `ExecutableMemory` should use it too. |
| `src/eval/mod.zig:18` | Reports the wasm eval backend available on every machine. A wasm32 module reserves its full 4 GiB of memory, which a 32-bit process cannot. | Report wasm available only on 64-bit machines. |
| `src/builtins/native_runtime_libcalls.zig` | Has no entries for the `__aeabi_*` helpers (64-bit division and shifts on 32-bit ARM). | Bind them to the compiler's own compiler-rt when the compiler runs on 32-bit ARM. |

On a 32-bit ARM machine, upstream's eval test runner builds in ReleaseSmall but
reports `UnsupportedPlatform` for the case we tried.

## Already fixed upstream

- `src/base/LargeBlockAllocator.zig:90-94`: the size-class shift now uses
  `std.math.Log2Int(usize)` rather than `u6`, so it compiles on 32-bit.
- `src/backend/wasm/WasmCodeGen.zig:17687`: the test-only ULEB reader returns
  `u32` and compiles on 32-bit.
- `src/backend/dev/LirCodeGen.zig:534-551`: string and list field offsets now
  come from the builtins, scaled by the target word. They are ready for
  32-bit; only the assertion at line 532 stops them.
- `src/machine_code_shim/instruction_cache.zig:15-18`: the instruction-cache
  flush has a 32-bit ARM path (`cacheflush` syscall).

## Not an upstream problem

Under qemu-user, a 32-bit program gets a fixed 8 MiB main stack whatever it
asks for. The eval runner asks for 64 MiB (`src/base/stack_budget.zig`), which
real hardware grants. After upstream `9aa5608b7f` one deep-recursion eval case
needs about 8.7 MB on 32-bit ARM, so it fails under plain qemu and passes on a
Raspberry Pi. Run qemu with `-s 64M`.

## How the locations were found

Each row matches a change on our arm32 reference branch
(`projects/big/arm32-dev-backend-existing-code-changes.md` lists every one,
with its commit). Every file and line above was then looked up again in
upstream `main` at `cf05860a7c` with `git grep` and `git show`. The counts in
the whole-file row are raw pattern counts: candidates to review, not all of
them bugs.
