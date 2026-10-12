# Draft: Tests fail in the ReleaseFast `-Dfuzz` test pass

> **Upstream or ours:** Upstream. Reproduced at upstream `58508d582b` without our changes; probably fixed since.

> **Relevance to our arm32 work:** They showed up as failures in our CI that we had to trace back to upstream before we could trust our own results.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | **Probably fixed.** In the full CI run on our merge of upstream `00cab95af8` (2026-10-01), the ReleaseFast passes on macOS-15 and Windows 2025 failed only on a problem of our own; none of the upstream tests below failed. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not ours. |
| Before filing | Rerun the three tests in ReleaseFast on current upstream (heavy, about an hour). **Do not file unless they still fail.** |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** Tests fail in the ReleaseFast `-Dfuzz` test pass

Kept for the record. At upstream `58508d582b`, `zig build run-test-zig -Doptimize=ReleaseFast -Dfuzz` failed tests that pass in Debug: "no-op workers do not append duplicate source bodies", two staged SpecConstr tests, two interface-summary tests, range proving, an inline test, and three fx stack-overflow tests on macOS only.

**How to reproduce**

At upstream `58508d582b` (about an hour, up to 24 GB of memory):

```sh
git checkout --detach 58508d582b
zig build -j2 run-test-zig -Doptimize=ReleaseFast -Dfuzz -Dsystem-afl=false -- \
  --test-filter "no-op workers do not append duplicate source bodies" \
  --test-filter "staged SpecConstr discovery admits source order" \
  --test-filter "staged SpecConstr submission failure drains accepted tasks"
```

All three failed there; with the default `-Doptimize=Debug` they passed.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
