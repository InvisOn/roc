# Draft: `main` does not compile since the recursive layout keys change: `RecursiveGraphMap` is gone but still used

> **Upstream or ours:** Upstream. Two upstream changes that each passed on their own conflict once both are on `main`.

> **Relevance to our arm32 work:** It blocks our sync. Our merge of upstream `5300d1ee60` does not build, so we merged only up to `414a19203e`, the last commit before the break.

Not filed, and no need to: upstream already has a fix open (PR 12557). Kept as a record of why our sync stopped at `414a19203e`.

| | |
|---|---|
| Still an issue? | Yes at `7e749fe156` (2026-10-24), by reading the code. Seen as a build error in our merge of `5300d1ee60`, which has upstream's `lir_image.zig` and `layout/store.zig` unchanged. Pure upstream not built yet. |
| Already upstream? | Yes. PR 12557, "Fix the canonical Boxy sidecar's layout store after the recursive layout keys change", open since 2026-10-24. It sets `.interned_recursive_graphs = .empty` and adds `.recursive_layout_keys = .{}`. |
| Fixed on our reference branch? | No. We left out the commits from `6d72ef4d1b` on instead. |
| Before filing | Don't file. Merge the rest of upstream once PR 12557 lands. |

---

**Title:** `main` does not compile: `lir_image.zig` still uses `Store.RecursiveGraphMap`, which was removed

**What happens**

`zig build` fails:

```
src/lir/lir_image.zig:1001:55: error: struct 'store.Store' has no member named 'RecursiveGraphMap'
```

(from our merge of `5300d1ee60`, compile exe roc debug, x86_64-linux-musl host)

**Why**

- `3d52048fab` ("Number the Boxy runtime's tables by what a dev image's code loads") added `serializeCanonicalSidecarInto` in `src/lir/lir_image.zig`. At line 1001 it builds a layout store with `.interned_recursive_graphs = layout_mod.Store.RecursiveGraphMap.init(gpa)`.
- The recursive layout keys change (`870bed4c21` and `6c81708579`, merged as `6d72ef4d1b`) replaced `RecursiveGraphMap` with `RecursiveGraphIndex` in `src/layout/store.zig`, and changed the other two sites in `lir_image.zig` to `.empty`. It didn't touch line 1001, which its branch didn't have yet.
- `serializeCanonicalSidecarInto` is reached from `buildCanonicalSidecarBlob`, which `src/cli/main.zig` calls (about line 10081) with no compile-time guard. So the `roc` executable fails to compile.

`414a19203e`, the commit before `6d72ef4d1b`, still has `RecursiveGraphMap` and is consistent.

**Possible fix** (untested)

Use `.interned_recursive_graphs = .empty,` at `lir_image.zig:1001`, like the other two sites.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream `main` at `44a0e31a28`, Zig 0.17.0
