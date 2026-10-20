# Draft: Dev backend: extra shifts before storing a single byte

> **Upstream or ours:** Upstream. It has nothing to do with our arm32 work.

> **Relevance to our arm32 work:** None in particular. We noticed it while reading the backend.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, upstream `main` at `5fc587cf51`, by reading the code). |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | No. |
| Before filing | Low value. Consider not filing. |

---

**Title:** Dev backend: extra shifts before storing a single byte

**What happens**

Before storing a `U8` or `I8` result, the backend shifts the register left by 56 bits and back again to clear the upper bits. Then it stores only the lowest byte, so the upper bits never matter. The two shifts do nothing useful. Nothing goes wrong; it is only wasted work.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/LirCodeGen.zig:16783-16800`, the `.u8` and `.i8` cases of `storeResultToSavedPtr` (line 16769). Each shifts left by 56 and then right by 56 (lines 16788-16789 and 16797-16798), and then `emitStoreScalarToPtr(..., 1)` stores one byte (lines 16790 and 16799).

**How to reproduce**

By reading the code:

```sh
grep -n -A40 'fn storeResultToSavedPtr' src/backend/dev/LirCodeGen.zig
```

In the `.u8` and `.i8` cases, two shifts come before a store that writes only the lowest byte.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
