# Draft: Dev backend: redundant narrowing shifts before byte stores

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** It does not affect arm32 in particular. Noticed while reading the driver.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Not rechecked. `storeResultToSavedPtr` still exists; the `.u8`/`.i8` cases were not reread today. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us. |
| Before filing | Reread the `.u8`/`.i8` cases on current upstream before filing. Low value; consider not filing. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** Dev backend: redundant narrowing shifts before byte stores

**What happens**

Before storing a byte, the driver emits a shift pair to narrow the value, and then stores only the low byte anyway. The shifts are dead work. No wrong behaviour.

**How to reproduce**

By reading the code:

```sh
grep -n -A40 'fn storeResultToSavedPtr' src/backend/dev/LirCodeGen.zig
```

Look at the `.u8` and `.i8` cases: a shift pair narrows the value before a store that writes only the low byte.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
