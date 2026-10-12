# Draft: A plain `zig build` deletes the user's whole Roc cache, downloaded packages included

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** It deleted the basic-cli download our verification tools need, in the middle of a test run. We set `XDG_CACHE_HOME` on every build to protect the cache.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `ClearRocCacheStep` is still in `build.zig` and still prints "Cleared roc cache at ...". |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us (we set `XDG_CACHE_HOME` to protect the cache). |
| Before filing | Nothing; the safe reproduction below can be rerun any time. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** A plain `zig build` deletes the user's whole Roc cache, downloaded packages included

**What happens**

The install step, and the steps that build the test platforms, depend on `ClearRocCacheStep`, which deletes `~/.cache/roc` (or `$XDG_CACHE_HOME/roc`) entirely. That includes downloaded packages such as basic-cli. `ROC_CACHE_DIR` does not move packages, so it does not protect them. A contributor's installed `roc` loses its packages every time they build the compiler.

**Why it matters**

Building the compiler destroys data outside the repository: every downloaded package of the contributor's installed `roc`. Their own Roc projects then need the network again, or fail when offline. Nothing in the build output explains why the packages are gone, beyond one line saying the cache was cleared.

**How to reproduce** (safely, with a stand-in cache)

```sh
export XDG_CACHE_HOME=/tmp/roc-probe-cache
mkdir -p $XDG_CACHE_HOME/roc/packages && touch $XDG_CACHE_HOME/roc/packages/marker
zig build 2>&1 | grep 'Cleared roc cache'
ls $XDG_CACHE_HOME/roc      # gone
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
