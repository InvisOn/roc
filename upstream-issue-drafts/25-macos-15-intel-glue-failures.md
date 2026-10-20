# Draft: macOS-15-intel `zig-tests`: RustGlue plugins don't load, and `--opt=speed` reports `LlvmBackendUnavailable`

> **Upstream or ours:** Upstream's CI. Seen on our fork's runs and on upstream's own nightly.

> **Relevance to our arm32 work:** It fails in our CI. Unrelated to our code.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Unknown. In upstream's Nightly Gate run on 2026-10-19, `zig-tests (macos-15-intel)` was cancelled after 6 hours, so there is no result. `LlvmBackendUnavailable` now shows up in `eval-llvm (macos-15)` instead. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | Not ours to fix. |
| Before filing | Wait for a nightly run where this job finishes, and check its result. |

---

**Title:** macOS-15-intel `zig-tests`: RustGlue plugins don't load, and `--opt=speed` reports `LlvmBackendUnavailable`

**What happens**

On the `macos-15-intel` runner, the glue tests fail because the RustGlue plugins don't load. Builds with `--opt=speed` report `LlvmBackendUnavailable`. We saw this in our CI run 36615593810 and in upstream's nightly at the same time (2026-09-29).

**Where** (upstream `main` at `5fc587cf51`)

- `.github/workflows/ci_zig.yml:180` and `:262`, the `macos-15-intel` entries of the `zig-tests` matrix.
- The latest run: upstream Nightly Gate run 39320401466 (2026-10-19). `zig-tests (macos-15-intel)` was cancelled after 6 hours.

**Why it matters**

The Intel macOS job can't pass, so it can't warn about a real regression on that platform.

**How to reproduce**

Only on CI, because it needs the `macos-15-intel` runner:

```sh
gh run view 36615593810 -R InvisOn/roc --log-failed | grep 'run failed'
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
- Seen on GitHub-hosted runners, not on this machine.
