# Draft: The nested procedure path pool grows with the square of nesting depth

> **Upstream or ours:** Upstream. `NestedProcSiteBuilder` in `src/check/checked_artifact.zig`.

> **Relevance to our arm32 work:** It blocks our sync. Since upstream `55a9d652c1`, the deep "closures nested as call arguments" eval test runs out of memory on arm32. The pool needs one contiguous block of about 1.4 GB, which a 32-bit process can no longer find.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-23, upstream `main` at `55a9d652c1`). |
| Already upstream? | No issue or PR found (searched 2026-10-23: NestedProcSiteBuilder, path_pool, the test name). Related: draft 33 (#12500), the same test family. |
| Fixed on our reference branch? | No. It is upstream code. |
| Before filing | Check `main` again. The owner files it (2026-10-23). |

---

**Title:** Nested procedure path pool grows quadratically with closure nesting depth

**What happens**

`NestedProcSiteBuilder.addSite` (`src/check/checked_artifact.zig:23428`) copies the whole current path into `path_pool` for every site (line 23437, `self.path_pool.appendSlice(self.allocator, self.path.items)`). A site at depth d adds d components, so n nested sites add about n²/2.

The eval test "issue 11698: closures nested as call arguments" (`src/eval/test/eval_deep_nesting_tests.zig:417`) nests 5,000 closures. The pool reaches about 28 million components. On x86_64 its buffer grows through 431 MB, 988 MB and 1.48 GB mappings, and the process peaks at 2.2 GB.

A 32-bit process can't do this. On arm32 the 1.42 GB request fails with `ENOMEM`, and the test reports `OutOfMemory`. It passed on arm32 at `35eb6b1cee` and fails at `55a9d652c1`. On x86_64 the pool is the same size at both commits, so the pool did not change. Something else in `55a9d652c1` now uses enough address space that the block no longer fits.

**Why it matters**

The test exists to show that deep nesting scales (issue 11698). This structure is quadratic in depth, and it makes up most of the test's memory. Storing each site's parent site and its last component, instead of a copy of its whole path, would make the pool linear in depth.

**How to reproduce**

```sh
git checkout 55a9d652c1
zig build build-test-eval-runner
strace -f -e trace=mmap ./zig-out/bin/eval-test-runner \
  --filter "closures nested as call arguments" --threads 1 2>&1 | grep -E 'mmap\(0x[0-9a-f]+, [0-9]{9,10},'
```

Shown output on x86_64 (Debug build):

```
mmap(0x748fb2a41000, 431267840, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x748fb2a41000
mmap(0x748f77bfe000, 988033024, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x748f77bfe000
mmap(0x748f1f5ba000, 1482964992, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x748f1f5ba000
```

gdb puts the last two in `ArrayList(NestedProcPathComponent).appendSlice`, called from `NestedProcSiteBuilder.addSite` (new capacity 28,427,573).

On arm32 (our branch's eval runner built for `arm-linux-musleabihf`, ReleaseSmall, run under `qemu-arm-static -s 64M`):

```
mmap2(0x24573000,1417256960,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0) = -1 errno=12 (Cannot allocate memory)
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64. arm32 under qemu-user (`qemu-arm-static`, `-cpu cortex-a9`).
- Upstream `main` at `55a9d652c1`, Zig 0.17.0.
- Not yet tested: a clean upstream build for arm32 (upstream does not build eval runners for 32-bit), and a real arm32 board.
