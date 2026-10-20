# Draft: macOS-15-intel `zig-tests`: RustGlue plugins fail to load and `--opt=speed` reports `LlvmBackendUnavailable`

> **Upstream or ours:** Upstream's CI workflow. Seen on our fork's runs and on upstream's own nightly.

> **Relevance to our arm32 work:** It fails in our CI. Unrelated to our code.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Unknown. The job was cancelled in our last full run (2026-10-01), so there is no recent result. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not ours. |
| Before filing | Look at upstream's own nightly result for this job before filing. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** macOS-15-intel `zig-tests`: RustGlue plugins fail to load and `--opt=speed` reports `LlvmBackendUnavailable`

**What happens**

On the `macos-15-intel` runner, glue tests fail because the RustGlue plugins do not load, and `--opt=speed` builds report `LlvmBackendUnavailable`. Seen in our CI run 36615593810 and in upstream's nightly at the time (2026-09-29).

**Where** (upstream `main` at `5fc587cf51`)

- `.github/workflows/ci_zig.yml:180` and `:262`: the `macos-15-intel` entries of the `zig-tests` matrix.
- Latest: upstream Nightly Gate run 39320401466 (2026-10-19), `zig-tests (macos-15-intel)` cancelled after 6 hours.

**Why it matters**

The Intel macOS job cannot go green, so it cannot signal a real regression on that platform.

**How to reproduce**

CI only (it needs the `macos-15-intel` runner):

```sh
gh run view 36615593810 -R InvisOn/roc --log-failed | grep 'run failed'
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
- Seen on GitHub-hosted runners, not on this machine.
