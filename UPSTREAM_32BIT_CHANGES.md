# Roc on 32-bit: upstream changes needed

As of 2026-10-26, upstream `main` at `26436de489`.

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

Goal 1 comes first. Goal 2 no longer strictly needs goal 1. Since
`c6154cb220`, a compiler whose machine has no dev backend evaluates
compile-time values in the interpreter instead. A dev backend for the
compiler's own machine still makes that evaluation native.

None of these changes alters the code generated for today's 64-bit targets.
On the arm32 branch where they were made, two compilers pinned to the same
version produce byte-identical x86_64 and aarch64 output.

## 1. A 64-bit compiler building 32-bit programs

| Location | What it does now | What it needs to do |
|---|---|---|
| `src/backend/dev/LirCodeGen.zig:492-494` | Refuses to compile for anything but x86_64 and aarch64. | Allow a 32-bit target once the rows below are fixed. |
| `src/backend/dev/LirCodeGen.zig:503-504` | Asserts the target word is 8 bytes; the comment says string and list words move with 64-bit loads and stores. | Remove the assertion; move words with loads and stores of the target's word size. |
| `src/backend/dev/LirCodeGen.zig:516-517` | Keeps the small-string flag as an `i64` and asserts it is bit 63. | Use the target word's top bit (bit 31 on 32-bit). |
| `src/backend/dev/LirCodeGen.zig:8406, 8419` | The Debug string check tests alignment against `@alignOf(usize) - 1`, the compiler machine's. | Use the target's word alignment; otherwise valid 4-byte-aligned strings fail the check. |
| `src/backend/dev/LirCodeGen.zig:14288, 14295` | Sizes and indexes the erased-call descriptor array by `@sizeOf(usize)`. | Use the target's word size. |
| `src/backend/dev/LirCodeGen.zig:14746, 14771` | Stores the erased-callable drop pointer at offset `@sizeOf(usize)` with an 8-byte store (`.w64`). | Target word size for both the offset and the store. |
| `src/backend/dev/LirCodeGen.zig:14595-14613, 14755-14806` | Lays out erased-callable payloads with `@sizeOf`/`@offsetOf` of the builtins structs as compiled for the compiler's machine. | Derive each offset from the target word; those structs hold only pointers, so on 32-bit every offset halves. |
| `src/backend/dev/LirCodeGen.zig:14373-14377` | The direct call of an erased callable (for programs without the Boxy runtime) reads the function pointer into an 8-byte slot with 8-byte loads and a store (`.w64`). | Use the target's word size for the slot, the loads and the store. |
| `src/backend/dev/LirCodeGen.zig:22311-22316` | `entrypointParamSlotSize` multiplies the register count by a literal 8. | Multiply by the target's word size. |
| `src/backend/dev/LirCodeGen.zig`, whole file | 811 8-byte loads/stores (`.w64`); fixed 8s in 90 `, 8)` and 41 `* 8` expressions; 12 uses of 56 as the small-string length shift. | Review each: most mean "one word", some really mean 64 bits (an `I64`, an `F64`, half of an `I128`), which on 32-bit take two registers. This is the bulk of the work. |
| `src/backend/dev/CallingConvention.zig:384, 646, 708` | Asserts an address argument (`.from_lea`) is 8 bytes. | Expect the target's word size. |
| `src/backend/dev/Relocation.zig:238-252` | Chooses the width of an absolute-address patch (`abs64`) from the compiler machine's `usize`. | Use the width of the target's addresses. |
| `src/snapshot_tool/main.zig:3908` | The `dev_object` snapshot check lists only the 64-bit architectures. | Ask the dev backend which targets it supports, so 32-bit snapshots are checked too. |
| `src/backend/dev/LirCodeGen.zig:15708` | Loads each runtime layout value with `codegen.emitPatchableImm32` and later rewrites it with `patchImm32`. Only x86_64 and aarch64 provide them. | A 32-bit code generator needs both. On 32-bit ARM that is a MOVW/MOVT pair whose two 16-bit immediates are rewritten (our branch does this). |
| `src/build/glibc_stub.zig:24, 93, 100` | Writes `ret` for 32-bit ARM, which has no such instruction. | Write `bx lr` for 32-bit ARM. |

## 2. The compiler running on a 32-bit computer

| Location | What happens now | What it needs to do |
|---|---|---|
| `src/sljmp/linux.zig:6-11`, `src/sljmp/mod.zig:16` | setjmp/longjmp exist only for x86_64 and aarch64; other Linux machines hit a `@compileError`. The compile-time evaluator needs them to recover from a crash. | Add a 32-bit ARM version (saves R4-R11, SP, LR and D8-D15). |
| `src/backend/dev/LirCodeGen.zig:23490-23494` | `host_lir_codegen_available` is false for `.arm`. Since `c6154cb220` that sends compile-time evaluation to the interpreter (`compilerHostMustUseInterpreterForCtfe`, `src/eval/compile_time_finalization.zig:3880`), so it works but is not native. | True for `.arm` once section 1 is done, for native compile-time evaluation. |
| `src/backend/dev/HostSplice.zig:409-420` (tests 434, 476, 532) | Writes a jump stub only for x86_64 and aarch64; the tests skip by naming those architectures. | Add a 32-bit ARM stub (`ldr pc, [pc, #-4]` followed by the target address); skip tests on `host_lir_codegen_available` instead. |
| `src/machine_code_shim/main.zig:483-489, 643-668` | `HostArch` knows only x86, x86_64 and aarch64; jump-stub sizes exist only for those. | Add 32-bit ARM. |
| `src/backend/dev/ExecutableMemory.zig:404-408` | Makes JIT memory executable with `mprotect` without flushing the instruction cache. Harmless on x86; ARM needs an explicit flush or it may run stale bytes. | Flush before making it executable. Upstream already has the flush (with a 32-bit ARM path) in `src/machine_code_shim/instruction_cache.zig:15-18`; `ExecutableMemory` should use it too. |
| `src/eval/mod.zig:18` | Reports the wasm eval backend available on every machine. A wasm32 module reserves its full 4 GiB of memory, which a 32-bit process cannot. | Report wasm available only on 64-bit machines. |
| `src/builtins/native_runtime_libcalls.zig` | Has no entries for the `__aeabi_*` helpers (64-bit division and shifts on 32-bit ARM). | Bind them to the compiler's own compiler-rt when the compiler runs on 32-bit ARM. |

On a 32-bit ARM machine, upstream's eval test runner builds in ReleaseSmall but
reports `UnsupportedPlatform` for the case we tried.

## Already fixed upstream

- `src/base/LargeBlockAllocator.zig:100`: the size-class shift now uses
  `std.math.Log2Int(usize)` rather than `u6`, so it compiles on 32-bit.
- `src/backend/wasm/WasmCodeGen.zig:17585`: the test-only ULEB reader returns
  `u32` and compiles on 32-bit.
- `src/backend/dev/LirCodeGen.zig:506-522`: string and list field offsets now
  come from the builtins, scaled by the target word. They are ready for
  32-bit; only the assertion at line 504 stops them.
- `src/backend/dev/Relocation.zig:177-186`: each call relocation now carries
  its encoding (`FunctionRelocationKind`), chosen by the code generator that
  emitted it, instead of guessing from the code bytes (`69b0808e11`). A
  32-bit ARM `BL` needs a third kind; our branch adds `arm32_call24`.
- `src/eval/compile_time_host.zig:33-37`: the debug allocation stamp is now a
  `u64`, so Debug and ReleaseSafe compilers for a 32-bit machine compile
  (`03f133636a`). That commit also fixed the other `u64`/`usize` mismatches
  that stopped the compiler and its tests compiling for 32-bit. Upstream's
  nightly `zig-cross-compile` job (`.github/workflows/ci_zig.yml`, nightly only because it needs about 15 GB) builds the
  compiler for `arm-linux-musleabihf` and `x86-linux-musl`, so a 32-bit
  compile break now shows up there.
- `src/machine_code_shim/instruction_cache.zig:15-18`: the instruction-cache
  flush has a 32-bit ARM path (`cacheflush` syscall).

- `src/eval/compile_time_finalization.zig:3880`: compile-time evaluation
  falls back to the interpreter on any machine without a dev backend
  (`c6154cb220`), which includes 32-bit ARM and 32-bit x86. Not tested on a
  32-bit machine yet.
- `be04ebd75e`: a relocation offset is narrowed to `usize`, so that code
  compiles for 32-bit machines.
- `6ff41f43e6`: a compile-time value that a 32-bit target cannot hold (one a
  64-bit evaluation produced) is now reported as out of memory instead of
  being narrowed with an unchecked cast.

- `8a64a61258`: the dev backend no longer truncates a 128-bit
  `list_get_unsafe` index to its low word. A list index is a U64, and
  anything else is a compiler invariant.
- `3c394026d0`: a U8 or I8 result is stored as one byte with no extension
  shifts first. The shift counts that assumed a 64-bit register are gone.

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
upstream `main` at `9b119d59e4` with `git grep` and `git show`. The counts in
the whole-file row are raw pattern counts: candidates to review, not all of
them bugs.
