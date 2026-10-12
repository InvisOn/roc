# Draft: Procedure symbol names change with every compiler build

> **Upstream or ours:** Upstream. It bites any test that pins machine-code bytes; upstream has none of those for real programs, which is why only our oracle ran into it.

> **Relevance to our arm32 work:** It broke our byte-identity oracle on every commit. We work around it by renaming the symbols before hashing.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `src/check/checked_artifact.zig` still folds `build_options.compiler_artifact_hash` into the checked-artifact key. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Worked around in our test oracles (`ProcIdentity.canonicalizeSymbolNames`). |
| Before filing | Nothing. This is a design question more than a bug. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** Procedure symbol names change with every compiler build

**What happens**

The compiler's own build hash is part of every checked-artifact key, and procedure symbol names derive from it. Two builds of `roc` at different commits name the same procedure differently, so the object file for an unchanged program changes with every compiler commit. Any test that pins machine-code bytes of real programs breaks on the next commit, and builds are not reproducible across compiler versions.

**Question for the maintainers**

Is the compiler hash meant to reach symbol names, or only cache keys? If only cache keys, symbol names could be derived without it.

**Why it matters**

Only our test oracle ran into it, because upstream has no test that pins the machine code of a real program. It matters because it makes such a test impossible: it would fail on the next compiler commit. A byte-pinning test is the cheapest way to prove that a backend refactor changed nothing, which is what a change as large as a new architecture needs. It also means builds are not reproducible across compiler commits.

**How to reproduce**

Build `roc` at two different commits and compare the symbol names of the same program (the second build is a full rebuild):

```sh
zig build
./zig-out/bin/roc build --opt=dev --no-cache --keep-temp --output=/tmp/int1 test/int/app.roc
nm <kept directory it prints>/roc_app_*.o | grep roc__p | head -3
git commit --allow-empty -m probe && zig build roc
./zig-out/bin/roc build --opt=dev --no-cache --keep-temp --output=/tmp/int2 test/int/app.roc
nm <new kept directory>/roc_app_*.o | grep roc__p | head -3    # different digests
git reset --hard HEAD~1                                        # drop the probe commit
```

The cause: `grep -n compiler_artifact_hash src/check/checked_artifact.zig`.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
