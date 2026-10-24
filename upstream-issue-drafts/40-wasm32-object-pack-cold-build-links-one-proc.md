# Draft: a cached wasm32 dev build serves only one of a URL package's exports from its object pack

> **Upstream or ours:** Upstream.

> **Relevance to our arm32 work:** None today. Object packs (a URL package's precompiled code, linked into a build) aren't wasm-specific, so once arm32 builds use URL packages, check this in step 12 (`arm32/targets`). Found while testing fold step 5 (fork PR #9), when a CLI test run with `--include-llvm` failed the same way on upstream as on our branch.

Not filed. New, for the owner to decide.

| | |
|---|---|
| Still an issue? | Yes at upstream `414a19203e` (2026-10-23), by running the test. Upstream `main` (`98dcdbfb2f`) doesn't build (draft 37); after `414a19203e` it changes only the editor-tooling build cancel in `src/compile/`. Also fails at `3bb8f2ec6c`. |
| Already upstream? | None found. Searched issues and PRs for "linked procs", "object pack wasm32" and "linked object pack" on 2026-10-24. |
| Fixed on our reference branch? | Not run there; the reference branch has the same test. |
| Before filing | Find out whether the test passed when it was added (`a880250acd`). If it did, bisect. If it never did, the test's expectation may be wrong rather than the cache: the test's own comment says the one-line `sum_squares` inlines into the app. |

---

**Title:** wasm32 object pack test: the cached build reports `linked procs: 1`, expected at least 3

**What happens**

The CLI test "object cache: a wasm32 dev build composes a URL package's size-optimized object pack and behaves like the uncached build" (added in `a880250acd`, 2026-10-18) fails:

```
the cached build did not serve every package export from the URL package's object pack
stderr: pack hits: 1 external procs: 1 linked procs: 1 evaluator artifacts: 0 packs loaded: 0 keys: 0
```

The test builds `test/wasm/linked_object_pack/App.roc` for wasm32 four times: uncached, optimized, then a "cold" and a "warm" cached build. The uncached and optimized builds succeed. The cold cached build also succeeds, but reports only 1 linked procedure. The test expects at least 3 (`package_entries = 3`: `describe`, `double_lanes` and `sum_squares_from`), so it fails there.

To reproduce: `zig build run-test-cli -- --include-llvm --filter "wasm32 dev build composes"`

**What we don't know**

Whether the cache serves too little, or the test expects too much. The app calls `describe`, `double_lanes` and `sum_squares`, and the test's comment says `sum_squares` inlines into the app while `sum_squares_from` should still come from the pack.

**Why CI doesn't catch it**

CI runs the LLVM CLI tests as `run-test-cli -- --include-llvm --filter "[size]" --filter "[speed]"` (`.github/workflows/ci_zig.yml:163`). This test's name contains neither `[size]` nor `[speed]`, so CI never runs it.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream at `414a19203e`, Zig 0.17.0
