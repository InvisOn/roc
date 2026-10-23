# Draft: JIT memory is made executable without flushing the instruction cache

> **Upstream or ours:** Upstream. On aarch64 a failure would depend on timing, and we never saw one. Our arm32 work needed the fix because 32-bit ARM requires the flush.

> **Relevance to our arm32 work:** Needed for arm32. Without the flush, freshly written code does not run reliably on 32-bit ARM. Our reference branch adds it.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, upstream `main` at `5fc587cf51`, by reading the code). |
| Already upstream? | No issue or PR for `ExecutableMemory` (searched 2026-10-20). 11193 and 11452 (both merged) added the flush to the machine-code shim only. |
| Fixed on our reference branch? | Yes, in `49bf1449b9`. |
| Before filing | Nothing. There is no reliable way to make it fail on aarch64. |

---

**Title:** JIT memory is made executable without flushing the instruction cache

**What happens**

`ExecutableMemory` copies machine code into memory, makes that memory executable with `mprotect`, and runs it. It never flushes the instruction cache first.

- On x86 that is fine, because the CPU keeps its caches in step by itself.
- On aarch64 it works only because Linux happens to flush when `mprotect` is called. The architecture says the program must flush after writing code, and Linux does not promise to do it.
- On 32-bit ARM, code run without a flush can fail.

Upstream already has a flush function (`src/machine_code_shim/instruction_cache.zig`), but only the machine-code shim calls it.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/ExecutableMemory.zig:404-408`, `protectExecutable`. It calls `mprotect` to make the memory readable and executable, with no flush.
- It is called from `ExecutableMemory.zig:251` (in `initWithEntryOffsetAndUnwindInfo`, line 217) and `:281` (in `finishWrite`, line 280).
- The existing flush is `src/machine_code_shim/instruction_cache.zig:11`, `flush`.

**Why it matters**

A CPU caches instructions separately from data. Machine code written into memory goes through the data cache, so the instruction cache can still hold whatever was at those addresses before. Running the code without a flush can run those old bytes. The result is a crash or a wrong answer that shows up rarely, depends on timing, and can't be reproduced on demand.

This memory runs the code the compiler generates for itself: compile-time evaluation, the eval tests, and the machine-code shim. A failure would look like the compiler misbehaving at random on ARM machines.

**How to reproduce**

There is no reliable way to make it fail, because on aarch64 a failure depends on timing. The missing flush shows up when reading the code:

```sh
grep -n -i 'mprotect\|flush\|clear_cache' src/backend/dev/ExecutableMemory.zig
```

It shows the `mprotect` call and no flush.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
