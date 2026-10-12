# Draft: The full `ci_zig.yml` run loses its Linux build jobs on hosted runners

> **Upstream or ours:** Upstream's CI workflow. Seen on our fork's runs and on upstream's own nightly.

> **Relevance to our arm32 work:** The arm32 eval steps come after the step that gets killed, so they never run on GitHub. We ran them in a separate, smaller CI job to get coverage.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes: seen again on 2026-10-01 (run 36764332316 on InvisOn/roc: `zig-cross-compile` targets, a Linux `zig-tests`, the arm64 nix build cancelled; valgrind and x86-linux-musl died without logs). |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not ours to fix. |
| Before filing | Look at upstream's own recent nightly runs to confirm it still happens there before filing. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** The full `ci_zig.yml` run loses its Linux build jobs on hosted runners

**What happens**

In a full run, the `zig-cross-compile` jobs, the Linux `zig-tests`, valgrind and the arm64 nix build are killed together (exit 143) 12 to 35 minutes into building `roc` with LLVM. Every step after `cross compile with llvm` in those jobs is therefore never run on GitHub. Upstream's nightly showed the same on 2026-09-29 and 2026-09-30.

**Likely cause**

The hosted runner runs out of memory linking the LLVM-enabled compiler. Not confirmed.

**Why it matters**

Every step after `cross compile with llvm` in those jobs never runs on GitHub: cross-compilation for several targets, valgrind and a Linux test pass. A regression in any of them goes unnoticed until someone runs the step locally.

**How to reproduce**

Start a full run (`gh workflow run ci_zig.yml -f full-run=true`), or look at existing ones:

```sh
gh run list -R roc-lang/roc --workflow ci_zig.yml
gh run view 36666186906 -R InvisOn/roc --json jobs \
  --jq '.jobs[] | select(.conclusion=="cancelled") | "\(.name) \(.startedAt) \(.completedAt)"'
```

Each cancelled job's log ends in "Process completed with exit code 143".

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
- Seen on GitHub-hosted runners, not on this machine.
