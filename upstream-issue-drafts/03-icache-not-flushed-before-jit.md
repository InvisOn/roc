# Draft: JIT memory is made executable without flushing the instruction cache

> **Upstream or ours:** Upstream. It concerns every ARM host the compiler runs on (aarch64 Linux, macOS and Windows today). Nobody has seen it fail; the ARM architecture requires the flush, and the compiler already does it in one place.

> **Relevance to our arm32 work:** Needed for arm32 as a host (part 9), but not arm32-specific. Decided 2026-10-28: the fix goes into the shared-driver PR (parts 1 to 3), which links this issue.

Not filed. For roc-lang/roc. **To be reviewed by the owner before filing**
(nothing goes upstream without that review and an explicit OK).

| | |
|---|---|
| Still an issue? | Yes (2026-10-28, upstream `main` at `bad769be8e`, by reading the code). |
| Already upstream? | No issue or PR for `ExecutableMemory` (searched 2026-10-28). 11193 and 11452 (both merged) added the flush to the machine-code shim only. |
| Fix | `200333a587` on `dispatch/isa` (#9), earlier fork PR #8 (closed). Goes into the shared-driver PR (`shared-driver/isa-word-size`). |
| Before filing | See the checklist at the end. |

---

**Title:** JIT memory is made executable without flushing the instruction cache

**What happens**

`ExecutableMemory` copies machine code into memory, makes that memory executable (`mprotect`, or `VirtualProtect` on Windows), and runs it. It never flushes the instruction cache in between.

- On x86 and x86_64 that is fine: the CPU keeps its instruction and data caches in step by itself.
- On aarch64 the architecture requires the program to make newly written code visible to instruction fetch: clean the data cache, invalidate the instruction cache, then a barrier. Nothing in `ExecutableMemory` does that. It works today, as far as anyone has seen, but nothing guarantees it. On Linux the kernel's own cache maintenance during the permission change may be what hides it; whether macOS or Windows on aarch64 do the same has not been checked.
- The compiler already knows this: the machine-code shim flushes with `instruction_cache.flush` (`src/machine_code_shim/instruction_cache.zig`) before it publishes code (`src/machine_code_shim/main.zig:469`). `ExecutableMemory` doesn't use it.

**Where** (upstream `main` at `bad769be8e`)

- `src/backend/dev/ExecutableMemory.zig:404`, `protectExecutable`. It changes the permissions (`mprotect` at line 408, `VirtualProtect` at line 412) with no flush.
- Its callers: `initWithEntryOffsetAndUnwindInfo` (line 204, call at 238), `finishWrite` (267) and `finishWriteExecutablePrefix` (274). `HostSplice.zig` uses the last two (lines 297, 299, 446).
- The existing flush: `src/machine_code_shim/instruction_cache.zig:11`, `flush`. It already covers x86 (nothing to do), aarch64 on Linux, macOS and Windows, and 32-bit ARM on Linux.

**Why it matters**

A CPU caches instructions separately from data. Machine code written into memory goes through the data cache, so the instruction cache can still hold whatever was at those addresses before. Running the code without a flush can run those old bytes: a crash or a wrong answer that is rare, depends on timing, and can't be reproduced on demand.

This memory runs the code the compiler generates for itself: compile-time evaluation, the REPL, the eval tests and `HostSplice`. A failure would look like the compiler misbehaving at random on ARM machines.

**How to reproduce**

There is no reliable way to make it fail. The missing flush shows when reading the code:

```sh
grep -n -i 'mprotect\|VirtualProtect\|flush\|clear_cache' src/backend/dev/ExecutableMemory.zig
```

It shows the permission changes and no flush.

**Proposed fix**

Move `instruction_cache.zig` from the machine-code shim into `src/backend/dev/` (the shim already imports the backend), and call `instruction_cache.flush` at the start of `protectExecutable`. The flush can fail (the 32-bit ARM Linux `cacheflush` system call, Windows `FlushInstructionCache`), which is an operating-system failure, so `FlushInstructionCacheFailed` joins the error sets that carry `ExecutableMemory`'s errors. The existing test of `flush` moves with it. No new test: the kernel's own maintenance during the permission change can hide a missing flush, so a test through `ExecutableMemory` could not fail.

**Environment**

- Found by reading the code, on x86_64 Linux. The fix was run on an aarch64 Linux device: ten eval runs and the backend unit tests (including `execute aarch64 code`) passed.

---

## Before filing (ours, not part of the issue)

- **Review this draft with the owner,** line by line, and apply only the
  changes they approve. Filing needs their explicit OK.
- The fix is taken onto `shared-driver/isa-word-size`; the issue and that PR link each other.
- Check where `FlushInstructionCacheFailed` sits in each of the 10 error lists the fix touches (`ReplSession.programFailureKind`, the two lists in `cli/main.zig`, `coordinator.zig`, `inspected.zig`, `inspected_run.zig`, `checked_artifact.zig`, `snapshot_tool`, `lir_inline_test.zig`). In `cli/main.zig` it sits among file-system errors; make sure the message a user sees there is right.
- Commit message: lead with aarch64, and say the architecture requires the flush; don't imply an observed failure. 32-bit ARM is a second example.
- Recheck the line numbers on `main` the day it is filed.
