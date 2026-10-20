# Draft: Dev backend: a string result is stored from one register for non-stack locations

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** It does not affect arm32 in particular. Found while reading the driver for word-size assumptions; the reference leaves it as it is.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `storeResultToSavedPtr` in `src/backend/dev/LirCodeGen.zig` still has the branch commented "Fallback for non-stack string location". |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us. |
| Before filing | Nothing; whether the branch is reachable is the open question. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** Dev backend: a string result is stored from one register for non-stack locations

**What happens**

In `storeResultToSavedPtr`, the `.str` case handles a value that is not on the stack by loading it into one general register and storing that one word. A string is three words; length and capacity are left unwritten. The branch is either dead or corrupts the result. Its comment calls it a fallback, which AGENTS.md forbids in this stage.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/LirCodeGen.zig:16899-16914`, the `.str` case of `storeResultToSavedPtr` (line 16769): for `.general_reg`, `.float_reg`, `.vector_reg`, `.stack_i128`, `.list_stack` and the immediates, it loads one register (16912) and stores one word (16913).

**Why it matters**

A Roc string is three words. If this branch is ever taken, the result has an unwritten length and capacity, which means reading or freeing memory at random. If it can never be taken, it is dead code that hides an invariant the backend should assert.

**How to reproduce**

No program is known that reaches the branch, so this is seen by reading the code:

```sh
grep -n -B8 -A4 'Fallback for non-stack string location' src/backend/dev/LirCodeGen.zig
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
