# Draft: x86_64 SysV classifier asserts on a zero-sized aggregate member

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** It fails four x64musl cross-compile jobs and 30 `eval-llvm` cases in our CI. Unrelated to our code.

> **Already reported upstream:** issue #11909 (open). The fix, PR #11915, was folded into PR #11885, which is still open. Do not file.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes: `assert(size > 0)` is still in `src/layout/abi/x86_64.zig` and `classifyMemberSysV` still forwards zero-sized members. |
| Already upstream? | Already reported: issue #11909 (open). Fix: PR #11915, closed and folded into PR #11885 (open as of 2026-10-02). |
| Fix on our reference branch | Not fixed by us (upstream's bug). |
| Before filing | Nothing. **Do not file.** Goes away when #11885 lands. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** x86_64 SysV classifier asserts on a zero-sized aggregate member

Kept for the record only. `test/fx/parallel_fusion.roc` and `test/fx/inspect_dict_set.roc` crash the compiler when built with `--target=x64musl` and the LLVM backend; 30 `eval-llvm` cases fail on the same assertion.

**How to reproduce**

```sh
zig build run-test-cli -- --suite platforms --filter test/fx/parallel_fusion.roc \
  --filter test/fx/inspect_dict_set.roc --cross-target=x64musl
```

Both programs crash in the build phase with `assert(size > 0)` in `src/layout/abi/x86_64.zig`. Issue #11909 has a smaller program.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
