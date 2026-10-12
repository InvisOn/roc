# Draft: A backend unit test prints to stderr, which fails `zig build` although every test passes

> **FILED as roc-lang/roc#12200** on 2026-10-11: filed by the owner as "A passing backend unit test prints a WASM merge message that zig build shows as a failed command"; open.

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** It made our runs of the backend tests report failure with every test passing. The reference fixes it.

Filed as roc-lang/roc#12200 on 2026-10-11.

| | |
|---|---|
| Still an issue? | Changed 2026-10-11 (clean upstream `c1464a1dc0`, Zig 0.17): the test still prints `WASM merge: both modules import 'roc_crashed', with types 0 and 1`, under a `failed command:` header, but the build now succeeds (17/17 steps, 500/501 tests passed, exit 0). No longer a failure; a misleading message that reads like one. |
| Already upstream? | **Filed as #12200** (2026-10-11). Before filing: None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | `1138ce4c33` (records the conflict in a field instead of printing). |
| Before filing | Decide whether it is still worth filing: it no longer fails the build. If filed, as a misleading-output issue. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** A backend unit test prints to stderr, which fails `zig build` although every test passes

**What happens**

`zig build run-test-zig-module-backend` reports a failed command even though all tests pass, because a test exercises a WASM module merge that prints a diagnostic with `std.debug.print`, and the build system treats stderr output from a test as failure.

**Why it matters**

The build reports failure while every test passes. A contributor has to read the log to find out that nothing is wrong, and a real failure in the same step is easy to miss among the noise.

**How to reproduce**

```sh
zig build run-test-zig-module-backend 2>&1 | grep -E 'WASM merge|passed|failed command'
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
