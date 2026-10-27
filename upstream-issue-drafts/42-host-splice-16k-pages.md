# Draft: Compile-time evaluation segfaults on aarch64 Linux with 16 KiB pages

> **Upstream or ours:** Upstream. #9 does not change `HostSplice.zig`; fork PR #10 fixes it.

> **Relevance to our arm32 work:** Found running fold step 7's eval runner on the aarch64 device, a Raspberry Pi (which we do) whose default kernel uses 16 KiB pages. It blocks running the eval corpus there, which part 1's instruction cache flush check needs. 32-bit ARM uses 4 KiB pages, so arm32 itself is not affected.

Not filed, and not to be filed for now (owner, 2026-10-27). For roc-lang/roc. Fix: fork PR #10, branch `fix/runtime-page-size` (`b1df3f9f18`).

| | |
|---|---|
| Still an issue? | Yes. Seen on the device at upstream `26436de489` (2026-10-26); the code is unchanged on upstream `main` at `3c0fffe7bd` (2026-10-27: `HostSplice.zig:253` still aligns to `page_size_min`). With the fix, the runs on the device pass (fold step 7, sub-step 4). |
| Already upstream? | No issue or PR found (searched 2026-10-27, open and closed, for "16K page", "16KB page", "16 KiB", "page size", "page_size_min", "pageSize", "HostSplice", "StaticDataImage", "mprotect", "Asahi", "Raspberry Pi 5" and "aarch64 segfault"). Closest: 6514 (closed, building the old Rust compiler on that device, unrelated) and the open compile-time evaluation rework 12395 (no mention of page alignment). |
| Fixed on our reference branch? | No. The reference's `HostSplice` uses `page_size_min` the same way. |
| Before filing | Run the plain base runner (without the fix) on a 16 KiB-page kernel and confirm the same crash; only the branch's runner was seen crashing. The fix is confirmed on the device (fold step 7, sub-step 4). |

---

**Title:** Dev backend: compile-time evaluation segfaults on aarch64 Linux with 16 KiB pages

**What happens**

On aarch64 Linux with 16 KiB pages (for example the Raspberry Pi 5's default kernel, `getconf PAGESIZE` = 16384), every eval case that goes through compile-time evaluation crashes:

```
Segmentation fault at address 0x7fff5e0a6000
compiler_rt.zig:601:26: in memsetSmallPowerOf2 (compiler_rt)
src/backend/dev/StaticDataImage.zig:144:13: in place
src/eval/compile_time_finalization.zig:4958:49: in init
src/eval/compile_time_finalization.zig:3243:37: in lowerEvalAndFinishRoots
...
```

The address is on a 4 KiB boundary but not on a 16 KiB one.

**Where** (upstream `main` at `26436de489`)

- `src/backend/dev/HostSplice.zig:253`, in `link`: `executable_len = std.mem.alignForward(usize, total, std.heap.page_size_min)`. The static data starts at `executable_len`.
- `src/backend/dev/ExecutableMemory.zig:275`, `finishWriteExecutablePrefix`, makes `memory[0..executable_len]` executable and read-only; it asserts only that the length is a multiple of `page_size_min`.
- `src/backend/dev/StaticDataImage.zig:144`, `place`, then fills the static data: `@memset(memory, 0)`.

`std.heap.page_size_min` is the smallest page size the target allows, 4 KiB on aarch64 Linux. The kernel protects whole pages, so on a 16 KiB-page kernel the `mprotect` also covers the first part of the static data, and the first write to it faults.

**Why it matters**

The dev backend cannot evaluate compile-time code on these machines at all: the Raspberry Pi 5's default kernel, and Asahi Linux on Apple Silicon. CI and x86_64 use 4 KiB pages, so nothing upstream shows it.

**Suggested fix**

Align the executable prefix to the running kernel's page size, `std.heap.pageSize()` (already used in `src/base`), and assert against the same size in `finishWriteExecutablePrefix`. Kernels with 4 KiB pages are unchanged. Two lines; fork PR #10.

**How to reproduce**

On a 16 KiB-page aarch64 Linux machine, or with an eval runner cross-built on another machine:

```sh
zig build build-test-eval-runner -Dtarget=aarch64-linux-musl --prefix out
```

then, on the device: `./out/bin/eval-test-runner --threads 4`. A 4 KiB-page machine cannot show it.

**Environment**

- Raspberry Pi 5, Raspberry Pi OS, kernel `6.18.50+rpt-rpi-2712` (16 KiB pages); runner cross-built with Zig 0.17.0 from upstream `26436de489` plus our branch.
