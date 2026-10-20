# Draft: LIR images are loaded without the layout store's recursive-graph keys

> **Upstream or ours:** Upstream. Latent there: no upstream code path hands a loaded image to the object-file path today. We hit it while building a test oracle.

> **Relevance to our arm32 work:** Hit while building the test oracle that hashes the machine code of every eval case. We took a different route and left it alone.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `src/lir/lir_image.zig` still creates `interned_recursive_graphs` empty, and `src/layout/digest.zig` still panics "cyclic layout has no recursive-graph key". |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us (we avoided the path). |
| Before filing | Nothing; a reproduction needs a consumer that hands an image to the object-file path. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** LIR images are loaded without the layout store's recursive-graph keys

**What happens**

When a LIR image is loaded, the layout store's `interned_recursive_graphs` map is created empty. Any consumer that passes such an image to the object-file path panics on the first recursive type, because the layout digest needs the key.

**Where** (upstream `main` at `5fc587cf51`)

- `src/lir/lir_image.zig:388` and `:734`: `interned_recursive_graphs` is created empty (`RecursiveGraphMap.init`) when an image is loaded or cloned.
- `src/layout/digest.zig:108`, in `Digests.get` (line 85): `base.invariant("layout digest: cyclic layout {d} has no recursive-graph key", ...)`; unreachable in release builds.

**Why it matters**

Upstream has no code path that triggers it, and we only hit it while building a test oracle. It matters as a trap for future work: anything that loads a LIR image and then generates object code (caching, parallel code generation) will panic on the first program with a recursive type, far from the cause.

**How to reproduce**

No upstream code path triggers it today, so this is seen by reading the code:

```sh
grep -n interned_recursive_graphs src/lir/lir_image.zig     # created empty on load
grep -rn 'has no recursive-graph key' src/layout             # the panic it leads to
```

To trigger it, hand a loaded LIR image of a program with a recursive type (for example a `Tree` holding `Box(Tree)`) to the object-file compiler.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
