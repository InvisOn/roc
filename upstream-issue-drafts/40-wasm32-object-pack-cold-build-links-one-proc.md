# Draft: A cached wasm32 dev build serves only one of a URL package's exports from its object pack

> **Upstream or ours:** Upstream. It fails the same way on upstream as on our branch.

> **Relevance to our arm32 work:** None today. Object packs (a URL package's precompiled code, linked into a build) aren't wasm-specific, so once arm32 builds use URL packages, check this in part 10 (`arm32/targets`). Found while testing fold step 5 (fork PR #9), when a CLI test run with `--include-llvm` failed.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-24, upstream at `414a19203e`, by running the test below). Upstream `main` (`98dcdbfb2f`) doesn't build (draft 37); after `414a19203e` it changes only the editor-tooling build cancel in `src/compile/`. Also fails at `3bb8f2ec6c`. |
| Already upstream? | No issue or PR found (searched 2026-10-24 for "linked procs", "object pack wasm32" and "linked object pack"). |
| Fixed on our reference branch? | Not run there; the reference branch has the same test. |
| Before filing | Find out whether the test passed when it was added (`a880250acd`). If it did, bisect. If it never did, the test's expectation may be wrong rather than the cache: the test's own comment says the one-line `sum_squares` inlines into the app. |

---

**Title:** wasm32 object pack test: the cached build reports `linked procs: 1`, expected at least 3

**What happens**

The CLI test "object cache: a wasm32 dev build composes a URL package's size-optimized object pack and behaves like the uncached build" (added in `a880250acd`, 2026-10-18) fails. It builds `test/wasm/linked_object_pack/App.roc` for wasm32 four times: uncached, optimized, then a "cold" and a "warm" cached build. The uncached and optimized builds pass. The cold cached build succeeds, but reports that only 1 procedure came from the URL package's object pack. The test expects at least 3 (`describe`, `double_lanes` and `sum_squares_from`).

**Where** (upstream at `414a19203e`)

- `src/cli/test/parallel_cli_runner.zig`, `customWasmLinkedObjectPack` and `wasmLinkedObjectPackForTarget`: `package_entries = 3`, and the check on the `linked procs:` count of each cached build.
- `test/wasm/linked_object_pack/App.roc`: the app, which calls `Numeric.describe`, `Numeric.double_lanes` and `Numeric.sum_squares`.

**Why it matters**

Either a cached build compiles package code that it should take from the package's object pack, so caching saves less than it should, or the test checks for something the compiler no longer does. CI can't tell, because it never runs this test: it runs the LLVM CLI tests as `run-test-cli -- --include-llvm --filter "[size]" --filter "[speed]"` (`.github/workflows/ci_zig.yml:163`), and this test's name contains neither `[size]` nor `[speed]`.

**How to reproduce**

On upstream at `414a19203e`, with Zig 0.17.0:

```sh
zig build run-test-cli -- --include-llvm --filter "wasm32 dev build composes"
```

The test fails with:

```
run failed   object cache: a wasm32 dev build composes a URL package's size-optimized object pack and behaves like the uncached build  (phase=run)
      the cached build did not serve every package export from the URL package's object pack
      stderr: pack hits: 1 external procs: 1 linked procs: 1 evaluator artifacts: 0 packs loaded: 0 keys: 0
      stdout: 0 errors and 0 warnings found in 110ms while successfully building:
          zig-out/roc-test/work/0-490b23df/wasm_linked_pack_wasm32_0_cold.wasm
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream at `414a19203e` built from source, Zig 0.17.0
