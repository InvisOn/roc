# Draft: `main` does not compile: `loop_exit_demand.zig` does not handle the new `hole` type

> **Upstream or ours:** Upstream. Two upstream PRs that were each fine on their own.

> **Relevance to our arm32 work:** It blocks verifying any merge of upstream `main` past `35eb6b1cee` until it is fixed. We merged `35eb6b1cee` instead, which has the #12500 fix and compiles.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-22 23:00 NZDT, upstream `main` at `6de96ed3af`). |
| Already upstream? | No issue or PR found (searched 2026-10-22). Likely fixed within hours, since CI on `main` fails too. |
| Fixed on our reference branch? | No. It is upstream code. |
| Before filing | Check `main` again first. File only if it is still broken. |

---

**Title:** `main` does not compile: `isScalar` in `loop_exit_demand.zig` does not handle `.hole`

**What happens**

Building `main` at `6de96ed3af` fails:

```
src/postcheck/monotype_lifted/loop_exit_demand.zig:141:16: error: switch must handle all possibilities
        return switch (self.program.types.get(ty)) {
               ^~~~~~
src/postcheck/monotype/type.zig:306:5: note: unhandled enumeration value: 'hole'
    hole,
```

**Why**

- #12487 (merged as `27654183d3`) added the `hole` variant to the monotype
  `Content` (`src/postcheck/monotype/type.zig:306`).
- #12507 (merged after it, as `8ecb0ca9b4`) added `Inventory.isScalar` in
  `src/postcheck/monotype_lifted/loop_exit_demand.zig:140-149`. Its switch
  lists every variant that existed on its branch, so it has no `.hole` prong.

Each PR compiled on its own. Together they don't.

**How to reproduce**

```sh
git checkout 6de96ed3af
zig build roc
```

Seen while building our merge of `6de96ed3af`. Both files involved are
upstream's and our branch does not change them, but this exact command on a
clean checkout has not been run yet.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream `main` at `6de96ed3af`, Zig 0.17.0
