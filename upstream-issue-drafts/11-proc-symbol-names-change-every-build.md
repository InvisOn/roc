# Draft: Procedure symbol names change with every change to the compiler's source

> **Upstream or ours:** Upstream. It breaks any test that compares the exact machine code of real programs. Upstream has no such test, which is why only our test oracle ran into it.

> **Relevance to our arm32 work:** It broke our byte-for-byte comparison on every commit. We work around it by renaming the symbols before comparing.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-21, upstream `main` at `534956997e`, by reading the code). The reproduction below is corrected after a test with an empty commit kept the names. The corrected steps are not run yet. |
| Already upstream? | No issue or PR found (searched 2026-10-21). #11430 (closed) was a different reproducibility bug. PR #12463 would have changed the key's shape but kept the compiler hash in it. It was closed without merging on 2026-10-20. |
| Fixed on our reference branch? | No. Our test oracle renames symbols before comparing (`ProcIdentity.canonicalizeSymbolNames`). |
| Before filing | Nothing. It is a design question more than a bug. |

---

**Title:** Procedure symbol names change with every change to the compiler's source

**What happens**

Every checked-artifact key includes `compiler_artifact_hash`. That is a hash of the contents of the compiler's source files, plus the Zig toolchain, dependencies and build options (`src/build/compiler_identity.zig`). Procedure symbol names are made from a digest that depends on that key. So any change to the compiler's source, even a comment, gives the same procedure in the same program a different name. The object file for an unchanged program changes with almost every compiler commit. A commit that changes no source file, such as an empty commit, keeps the names.

**Question for the maintainers**

Is the compiler hash meant to reach symbol names, or only cache keys? If only cache keys, symbol names could be made without it.

**Where** (upstream `main` at `534956997e`)

- `src/check/checked_artifact.zig:144` puts `build_options.compiler_artifact_hash` into every checked-artifact key. It is hashed at line 164, in `computeCheckedArtifactKeyBytes` (line 155).
- `src/lir/LIR.zig:67` and `94-98`. Procedure symbols are named `roc__p` followed by a digest (`ProcIdentity.writeSymbolName`), and that digest changes with the key.

**Why it matters**

A test that compares a real program's machine code byte for byte would fail on the next compiler commit that changes any source file, so such a test can't exist. That kind of test is the cheapest way to prove a backend refactor changed nothing, which matters for large changes such as a new architecture. It also means builds of the same program are not reproducible across compiler versions.

**How to reproduce**

Build the same program with two compilers whose source differs only by a comment, and compare the symbol names. The built program keeps its symbols, so `nm` can read them directly. The second `zig build roc` rebuilds the whole compiler.

```sh
zig build roc
zig build update-test-fixtures    # copies the test platform's host libraries into the checkout
./zig-out/bin/roc build --opt=dev --no-cache --output=/tmp/int1 test/int/app.roc
nm /tmp/int1 | grep roc__p | sort -k3 | head -3
echo '// probe' >> src/base/mod.zig && zig build roc
./zig-out/bin/roc build --opt=dev --no-cache --output=/tmp/int2 test/int/app.roc
nm /tmp/int2 | grep roc__p | sort -k3 | head -3    # different digests
git checkout src/base/mod.zig                      # undo the probe
```

An empty commit instead of the comment gives the same names (checked 2026-10-21), because the hash ignores Git state.

The cause: `grep -n compiler_artifact_hash src/check/checked_artifact.zig`.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
