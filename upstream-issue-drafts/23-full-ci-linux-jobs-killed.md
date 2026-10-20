# Draft: In a full `ci_zig.yml` run, the Linux build jobs get killed on GitHub's runners

> **Upstream or ours:** Upstream's CI workflow. Seen on our fork's runs and on upstream's own nightly.

> **Relevance to our arm32 work:** The arm32 eval steps come after the step that gets killed, so they never run on GitHub. We ran them in a separate, smaller CI job instead.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes. Upstream's Nightly Gate failed every night from 2026-10-16 to 2026-10-19. In run 39320401466 (2026-10-19), `zig-cross-compile (arm-linux-musleabihf)` ended with exit code 143. |
| Already upstream? | No issue filed (searched 2026-10-20). Upstream's own Nightly Gate shows it every night. |
| Fixed on our reference branch? | Not ours to fix. |
| Before filing | Low value, since upstream sees it every night. |

---

**Title:** In a full `ci_zig.yml` run, the Linux build jobs get killed on GitHub's runners

**What happens**

In a full run, several jobs are killed at the same time (exit code 143) while they build `roc` with LLVM, 12 to 35 minutes in. They are the `zig-cross-compile` jobs, the Linux `zig-tests`, valgrind, and the arm64 nix build. None of the steps after `cross compile with llvm` in those jobs ever run on GitHub. Upstream's nightly showed the same thing on 2026-09-29 and 2026-09-30, and still does.

**Likely cause**

The runner probably runs out of memory while linking the LLVM-enabled compiler. Not confirmed.

**Where** (upstream `main` at `5fc587cf51`)

- `.github/workflows/ci_zig.yml:524`, the step `cross compile with llvm`. Jobs end with exit code 143 during this step.
- The latest example: upstream Nightly Gate run 39320401466 (2026-10-19), job `zig-cross-compile (arm-linux-musleabihf)`. Its log says "Process completed with exit code 143" and "The runner has received a shutdown signal".

**Why it matters**

The steps after `cross compile with llvm` never run on GitHub. They cover cross-compilation for several targets, valgrind, and a Linux test run. A regression in any of them goes unnoticed until someone runs the step by hand.

**How to reproduce**

Start a full run (`gh workflow run ci_zig.yml -f full-run=true`), or look at existing ones:

```sh
gh run list -R roc-lang/roc --workflow ci_zig.yml
gh run view 36666186906 -R InvisOn/roc --json jobs \
  --jq '.jobs[] | select(.conclusion=="cancelled") | "\(.name) \(.startedAt) \(.completedAt)"'
```

Each cancelled job's log ends with "Process completed with exit code 143".

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
- Seen on GitHub-hosted runners, not on this machine.
