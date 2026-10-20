# Draft: `abs64` relocation patching is sized by the compiler's host word

> **Upstream or ours:** Upstream code, but it only matters when the compiler itself runs on a 32-bit host. So far only our arm32 work does that.

> **Relevance to our arm32 work:** It matters for a compiler running on arm32. Not fixed on upstream's path.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `patchAbsolutePointerOperand` in `src/backend/dev/Relocation.zig` still branches on `@sizeOf(usize)`. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us on upstream's path. |
| Before filing | Nothing. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** `abs64` relocation patching is sized by the compiler's host word

**What happens**

`patchAbsolutePointerOperand` writes 8 bytes when the compiler runs on a 64-bit host and 4 bytes on a 32-bit host. The width should come from the relocation kind (the target), not from the machine the compiler runs on. Latent today: it only matters for a compiler running on a 32-bit host.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/Relocation.zig:329-345`, `patchAbsolutePointerOperand`: writes 8 bytes if `@sizeOf(usize) == 8` (line 330), 4 bytes if `@sizeOf(usize) == 4` (line 336).

**Why it matters**

Today only a compiler running on a 32-bit host is affected, which means only arm32 work. There, an 8-byte absolute relocation would be patched with 4 bytes and half the address left unwritten, with nothing checking for it. It is the same habit as sizing target data by the host's word.

**How to reproduce**

It needs a compiler running on a 32-bit host, so this is seen by reading the code:

```sh
grep -n -A12 'fn patchAbsolutePointerOperand' src/backend/dev/Relocation.zig
```

The width written comes from `@sizeOf(usize)`.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
