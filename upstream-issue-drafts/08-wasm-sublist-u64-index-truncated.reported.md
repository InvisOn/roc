# Draft: wasm backend: `List.sublist` narrows a `U64` start index to 32 bits

> **FILED as roc-lang/roc#12198** on 2026-10-11: filed by the owner with the repro only (not the observed wasm output); open.

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** It does not affect arm32. Found during the arm32 work while looking at how the other 32-bit target handles 64-bit values.

Filed as roc-lang/roc#12198 on 2026-10-11. The ticket holds the repro only.

| | |
|---|---|
| Still an issue? | Yes, reproduced 2026-10-11 on clean upstream `c1464a1dc0`: both probes fail on wasm only (`[1.0]` instead of `[]`; `1` instead of `0`); interpreter and dev pass. The start index is narrowed to 32 bits. |
| Already upstream? | **Filed as #12198** (2026-10-11). Before filing: None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us (outside our scope). |
| Before filing | Nothing (reproduced on clean upstream 2026-10-11). |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** wasm backend: `List.sublist` narrows a `U64` start index to 32 bits

**What happens**

At upstream `58508d582b`, `List.sublist([1, 2, 3], { start: 4294967296, len: 1 })` returned `[1.0]` on the wasm backend and `[]` on every other backend: the `U64` start index was wrapped to 32 bits, so 2^32 became 0.

**Why it matters**

It is a silent miscompile: the same program returns different results on wasm than on every other backend, with no error. Indices at or above 2^32 are rare, but when one occurs the wasm build reads the wrong elements.

**How to reproduce**

Add to `src/eval/test/eval_low_level_tests.zig`, then `zig build run-test-eval -- --test-filter "probe - "`:

```zig
.{ .name = "probe - sublist start at 2^32",
   .source = "List.sublist([1, 2, 3], { start: 4294967296, len: 1 })",
   .expected = .{ .inspect_str = "[]" } },
.{ .name = "probe - zero-sized sublist start at 2^32",
   .source =
   \\{
   \\x : List({})
   \\x = [{}, {}, {}]
   \\List.len(List.sublist(x, { start: 4294967296, len: 1 }))
   \\}
   , .expected = .{ .inspect_str = "0" } },
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
