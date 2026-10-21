# Draft: Procedure symbol names change with every compiler build

> **Upstream or ours:** Upstream. It breaks any test that compares the exact machine code of real programs. Upstream has no such test, which is why only our test oracle ran into it.

> **Relevance to our arm32 work:** It broke our byte-for-byte comparison on every commit. We work around it by renaming the symbols before comparing.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-21, upstream `main` at `534956997e`, by reading the code). |
| Already upstream? | No issue or PR found (searched 2026-10-21). #11430 (closed) was a different reproducibility bug. PR #12463 would have changed the key's shape but kept the compiler hash in it. It was closed without merging on 2026-10-20. |
| Fixed on our reference branch? | No. Our test oracle renames symbols before comparing (`ProcIdentity.canonicalizeSymbolNames`). |
| Before filing | Nothing. It is a design question more than a bug. |

---

**Title:** Procedure symbol names change with every compiler build

**What happens**

Every checked-artifact key includes a hash of the compiler build itself. Procedure symbol names are made from a digest that depends on that key. So two builds of `roc` from different commits give the same procedure different names. The object file for an unchanged program changes with every compiler commit.

**Question for the maintainers**

Is the compiler hash meant to reach symbol names, or only cache keys? If only cache keys, symbol names could be made without it.

**Where** (upstream `main` at `534956997e`)

- `src/check/checked_artifact.zig:144` puts `build_options.compiler_artifact_hash` into every checked-artifact key. It is hashed at line 164, in `computeCheckedArtifactKeyBytes` (line 155).
- `src/lir/LIR.zig:67` and `94-98`. Procedure symbols are named `roc__p` followed by a digest (`ProcIdentity.writeSymbolName`), and that digest changes with the key.

**Why it matters**

A test that compares a real program's machine code byte for byte would fail on the next compiler commit, so such a test can't exist. That kind of test is the cheapest way to prove a backend refactor changed nothing, which matters for large changes such as a new architecture. It also means builds of the same program are not reproducible across compiler commits.

**How to reproduce**

Build `roc` at two different commits and compare the symbol names in the same program. The second build is a full rebuild.

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
