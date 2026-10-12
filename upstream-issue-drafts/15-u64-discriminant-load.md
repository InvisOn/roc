# Draft: Dev backend: is a tag union's padding always zero when the discriminant is loaded as 8 bytes?

> **Upstream or ours:** Upstream code. Not confirmed as a bug anywhere.

> **Relevance to our arm32 work:** It does not affect arm32 in particular. Noticed while reading the driver; never confirmed.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Unconfirmed. `loadAndMaskDiscriminant` still exists in `src/backend/dev/LirCodeGen.zig`; nobody has built a case that shows a wrong tag. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us. |
| Before filing | Build a tag union whose four-byte discriminant is followed by non-zero padding and see whether the tag is read wrong. Do not file before that. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** Dev backend: is a tag union's padding always zero when the discriminant is loaded as 8 bytes?

**What might happen**

On the 64-bit targets the discriminant is loaded as eight bytes and masked only when the discriminant is narrower than four bytes. For a four-byte discriminant, the upper four bytes come from padding. If padding is not guaranteed zero, the comparison could see a wrong tag.

**Question**

Is the padding after a discriminant guaranteed to be zero? If yes, this is fine and a comment would help. If no, the load needs a mask.

**Why it matters**

If the padding can hold non-zero bytes, a `match` on such a tag union could take the wrong branch, silently.

**How to reproduce**

Not reproduced. The code in question:

```sh
grep -n -A30 'fn loadAndMaskDiscriminant' src/backend/dev/LirCodeGen.zig
```

A reproduction would need a tag union whose four-byte discriminant is followed by padding that holds non-zero bytes.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
