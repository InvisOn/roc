# Draft: JIT memory is made executable without flushing the instruction cache

> **Upstream or ours:** Upstream. The code is upstream's. On aarch64 it is timing-dependent and we never saw it fail; our arm32 work hit it because ARMv7 requires the flush.

> **Relevance to our arm32 work:** Required for arm32: ARMv7 does not run freshly written code reliably without the flush. The reference adds it.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `src/backend/dev/ExecutableMemory.zig` calls `mprotect` and has no flush. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | `49bf1449b9` (and `6eeba018af`). |
| Before filing | Nothing. There is no reliable reproduction on aarch64 (it is timing-dependent). |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** JIT memory is made executable without flushing the instruction cache

**What happens**

`ExecutableMemory` copies machine code into memory, makes that memory executable with `mprotect`, and runs it, without flushing the instruction cache first. On x86 that is fine. On aarch64 it works only because Linux happens to flush when `mprotect` is called; the architecture itself says the program must flush after writing code. On 32-bit ARM, code run without a flush can fail. Upstream already has the flush (`src/machine_code_shim/instruction_cache.zig`), but only the machine-code shim calls it.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/ExecutableMemory.zig:404-408`, `protectExecutable`: `mprotect` to read+execute, no instruction-cache flush.
- Called from `ExecutableMemory.zig:251` (`initWithEntryOffsetAndUnwindInfo`, line 217) and `:281` (`finishWrite`, line 280).
- A flush already exists upstream: `src/machine_code_shim/instruction_cache.zig:11`, `flush`.

**Why it matters**

Today only arm32 depends on this: ARMv7 requires the flush, and without it code generated at compile time does not run reliably there. It is still worth fixing for upstream's own targets. A CPU caches instructions separately from data. Machine code written into memory goes through the data side, so the instruction cache can still hold whatever was at those addresses before. Running the code without flushing can execute stale bytes: a crash or a wrong result that appears rarely, depends on timing and cache state, and cannot be reproduced on demand. x86 keeps the two caches in step by itself; AArch64, like ARMv7, does not, and requires the program to flush after writing code. This path runs the code the compiler generates at compile time (compile-time evaluation, the eval tests, the machine-code shim), so a failure would look like the compiler misbehaving at random on ARM machines. On aarch64 it works today only because the kernel happens to do cache maintenance when the pages are made executable, which neither the architecture nor the kernel promises.

**How to reproduce**

There is no reliable reproduction: on aarch64 a failure depends on timing. The missing flush is seen by reading the code:

```sh
grep -n -i 'mprotect\|flush\|clear_cache' src/backend/dev/ExecutableMemory.zig
```

It shows the `mprotect` call and no flush.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
