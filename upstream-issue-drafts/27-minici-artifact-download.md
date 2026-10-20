# Draft: A PR minici shard can fail before running anything, at "Download MiniCI build artifact"

> **Upstream or ours:** Upstream's CI workflow, but seen only on our fork's runs so far.

> **Relevance to our arm32 work:** It occasionally fails our PR's CI run with no test having run. A rerun passes.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes: seen again on 2026-10-02 (`minici (macos-harness)`: "Artifact download failed after 5 retries"); a rerun passed. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not ours. |
| Before filing | Nothing. Low value: it is GitHub's artifact service; a rerun fixes it. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** A PR minici shard can fail before running anything, at "Download MiniCI build artifact"

**What happens**

Occasionally one minici shard fails at the artifact download step and runs no tests; the `finish` job then fails the whole run. Rerunning the failed jobs passes.

**Where** (upstream `main` at `5fc587cf51`)

- `.github/workflows/ci_manager.yml:488`, step `Download MiniCI build artifact`.

**How to reproduce**

It cannot be triggered on demand. Two runs where it happened:

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
