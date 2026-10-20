# Draft: Some unit tests fail in ReleaseFast with `-Dfuzz`

> **Upstream or ours:** Upstream. Reproduced at upstream `58508d582b` without our changes. Probably fixed since.

> **Relevance to our arm32 work:** They showed up as failures in our CI. We had to trace them back to upstream before we could trust our own results.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Probably fixed. In the full CI run on our merge of upstream `00cab95af8` (2026-10-01), none of these tests failed. Not rerun since. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | Not ours to fix. |
| Before filing | Rerun the three tests below in ReleaseFast on current upstream (about an hour). Don't file unless they still fail. |

---

**Title:** Some unit tests fail in ReleaseFast with `-Dfuzz`

Kept for the record. At upstream `58508d582b`, `zig build run-test-zig -Doptimize=ReleaseFast -Dfuzz` failed several tests that pass in Debug:

- "no-op workers do not append duplicate source bodies"
- two staged SpecConstr tests
- two interface-summary tests
- range proving
- an inline test
- three fx stack-overflow tests, on macOS only

**Where** (upstream `main` at `5fc587cf51`)

- `src/lir/proc_passes_test.zig:653`, test "LIR proc pass no-op workers do not append duplicate source bodies".
- `src/postcheck/monotype_lifted/spec_constr.zig:17063`, test "staged SpecConstr discovery admits source order with duplicates and bounded reverse waves".
- `src/postcheck/monotype_lifted/spec_constr.zig:17297`, test "staged SpecConstr submission failure drains accepted tasks".

**How to reproduce**

At upstream `58508d582b`. It takes about an hour and up to 24 GB of memory.

```sh
git checkout --detach 58508d582b
zig build -j2 run-test-zig -Doptimize=ReleaseFast -Dfuzz -Dsystem-afl=false -- \
  --test-filter "no-op workers do not append duplicate source bodies" \
  --test-filter "staged SpecConstr discovery admits source order" \
  --test-filter "staged SpecConstr submission failure drains accepted tasks"
```

All three failed there. With the default `-Doptimize=Debug` they passed.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
