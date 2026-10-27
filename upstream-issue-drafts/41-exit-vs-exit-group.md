# Draft: Generated exit code mixes `exit` and `exit_group`

> **Upstream or ours:** Upstream. Our `dispatch/isa` (fork PR #9 after its next push) uses `exit_group` for the 32-bit ARM glibc stub's `abort` (decided 2026-10-26, after fold step 7's reference check), so the inconsistency now shows on our branch too.

> **Relevance to our arm32 work:** The 32-bit ARM glibc stub's `abort` is ours. Making the x86_64 and aarch64 cases match it is a change of its own, separate from arm32.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-26, upstream `main` at `26436de489`, by reading the code). |
| Already upstream? | No issue or PR found (searched 2026-10-26 for "exit_group" and "glibc stub abort"). |
| Fixed on our reference branch? | Only for 32-bit ARM: the reference's stub `abort` uses `exit_group` (248) there. Its x86_64 and aarch64 cases still use `exit`. |
| Before filing | Recheck the line numbers on current `main`. Decide whether to file it as an issue or as a small PR that changes the three lines. |

---

**Title:** Generated exit code mixes `exit` and `exit_group` across targets

**What happens**

Code the compiler generates to end a process uses the `exit` system call in some places and `exit_group` in others, for no stated reason:

- The glibc stub's `abort` calls `exit`: syscall 60 on x86_64, 93 on aarch64.
- The LLVM backend's default `_start` calls `exit` (60) on x86_64, but `exit_group` (94) on aarch64.
- The default platform's Linux runtime calls `exit_group` everywhere.

On Linux, `exit` ends only the calling thread; `exit_group` ends every thread in the process. They behave the same in a single-threaded process. In a process with other threads, `abort` through the stub, or returning from `main` through the x86_64 `_start`, ends one thread and leaves the rest running.

**Where** (upstream `main` at `26436de489`)

- `src/build/glibc_stub.zig:91` and `:92`, the `abort` body in `generateComprehensiveStub`: `mov $60, %rax` (x86_64) and `mov x8, #93` (aarch64).
- `src/backend/llvm/MonoLlvmCodeGen.zig:1009` (`mov $60, %rax`, x86_64) and `:1026` (`mov x8, #94`, aarch64), in `emitDefaultRunStartModuleAsm`.
- `src/default_platform/linux_runtime.zig:181`, `:182`, `:252`, `:253` and `:649`: `linux.exit_group`.

**Why it matters**

`abort` is meant to end the process, and `_start`'s exit after `main` returns is the process's exit. A host that starts threads would see the process keep running after either. musl's and glibc's `_exit` both use `exit_group`, and so does Roc's own Linux runtime.

**Suggested fix**

Use `exit_group` in all four places: 231 on x86_64 and 94 on aarch64 (and 248 on 32-bit ARM, where it is used).

**How to reproduce**

By reading the code: the three files above. A test could start a second thread that sleeps, then call the stub's `abort`, and check that the process ends with status 1 instead of staying alive.

**Environment**

- Found by reading upstream `main` at `26436de489`. Nothing was run.
