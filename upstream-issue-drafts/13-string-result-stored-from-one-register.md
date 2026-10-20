# Draft: Dev backend stores only one word of a string result that is not on the stack

> **Upstream or ours:** Upstream. The bug is in upstream's code and has nothing to do with our arm32 work.

> **Relevance to our arm32 work:** None in particular. We found it while reading the backend for word-size assumptions. Our reference branch leaves it as it is.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, upstream `main` at `5fc587cf51`, by reading the code). |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | No. |
| Before filing | Nothing. Whether the branch can be reached is the open question. |

---

**Title:** Dev backend stores only one word of a string result that is not on the stack

**What happens**

`storeResultToSavedPtr` copies a procedure's result to the place the caller asked for. For a string, it handles a value on the stack correctly. For a value anywhere else, it loads it into one register and stores that one word. A Roc string is three words, so the length and capacity are never written.

The comment on that branch calls it a fallback. AGENTS.md forbids fallbacks in this stage.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/LirCodeGen.zig:16899-16914`, the `.str` case of `storeResultToSavedPtr` (line 16769). For `.general_reg`, `.float_reg`, `.vector_reg`, `.stack_i128`, `.list_stack` and the immediate locations, it loads one register (line 16912) and stores one word (line 16913).

**Why it matters**

If this branch is ever taken, the result's length and capacity are garbage. Code that later reads or frees that string uses random memory. If the branch can never be taken, it is dead code where the backend should assert instead.

**How to reproduce**

We don't know of a program that reaches the branch. Reading the code shows it:

```sh
grep -n -B8 -A4 'Fallback for non-stack string location' src/backend/dev/LirCodeGen.zig
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
