# Draft: Dev backend: is the padding after a tag union's discriminant always zero?

> **Upstream or ours:** Upstream's code. Not confirmed as a bug.

> **Relevance to our arm32 work:** None in particular. We noticed it while reading the backend and never confirmed it.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Unconfirmed (2026-10-20, upstream `main` at `5fc587cf51`). Nobody has built a case that reads a wrong tag. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | No. |
| Before filing | Build a tag union whose 4-byte discriminant is followed by non-zero padding, and see whether the tag is read wrong. Don't file before that. |

---

**Title:** Dev backend: is the padding after a tag union's discriminant always zero?

**What might happen**

On the 64-bit targets, the dev backend usually loads a tag union's discriminant as 8 bytes. It masks the loaded value only when the discriminant is smaller than 4 bytes. For a 4-byte discriminant, the upper 4 bytes of the load come from the padding after it. If that padding is not always zero, the comparison could see the wrong tag.

**Question**

Is the padding after a discriminant guaranteed to be zero? If so, this is fine, and a comment saying so would help. If not, the load needs a mask.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/LirCodeGen.zig:11351-11424`, `loadAndMaskDiscriminant`. It loads 8 bytes (`.w64`) unless `disc_use_w32` is set (lines 11366-11389). It masks only when the discriminant is smaller than 4 bytes (lines 11410-11421).
- `LirCodeGen.zig:12795`. `disc_use_w32` is set only when an 8-byte load would run past the end of the value.

**Why it matters**

If the padding can hold non-zero bytes, a `match` on such a tag union could quietly take the wrong branch.

**How to reproduce**

Not reproduced. The code in question:

```sh
grep -n -A30 'fn loadAndMaskDiscriminant' src/backend/dev/LirCodeGen.zig
```

A reproduction needs a tag union whose 4-byte discriminant is followed by padding that holds non-zero bytes.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
