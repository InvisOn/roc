# Draft: A MiniCI job sometimes fails at "Download MiniCI build artifact" before running any test

> **Upstream or ours:** Upstream's CI workflow, but so far seen only on our fork's runs.

> **Relevance to our arm32 work:** It occasionally fails our PR's CI run before any test has run. A rerun passes.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Last seen 2026-10-02 (`minici (macos-harness)`: "Artifact download failed after 5 retries"). A rerun passed. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | Not ours to fix. |
| Before filing | Low value. It is GitHub's artifact service, and a rerun fixes it. |

---

**Title:** A MiniCI job sometimes fails at "Download MiniCI build artifact" before running any test

**What happens**

Now and then one MiniCI job fails at the step that downloads the build artifact. It runs no tests. The `finish` job then fails the whole run. Rerunning the failed jobs passes.

**Where** (upstream `main` at `5fc587cf51`)

- `.github/workflows/ci_manager.yml:488`, the step `Download MiniCI build artifact`.

**How to reproduce**

It can't be triggered on purpose. Two runs where it happened:

```sh
gh run view 36865317895 -R InvisOn/roc --attempt 1 --json jobs \
  --jq '.jobs[] | select(.conclusion=="failure") | .name'      # minici (macos-harness), finish
gh run view 36666185179 -R InvisOn/roc --json jobs \
  --jq '.jobs[] | select(.name=="zig-minici (macos-core)") | .steps[] | "\(.name) \(.conclusion)"'
```

The failing step's log says "Unable to download artifact(s) ... Artifact download failed after 5 retries".

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
- Seen on GitHub-hosted runners, not on this machine.
