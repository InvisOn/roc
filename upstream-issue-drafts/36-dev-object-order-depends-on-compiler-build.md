# Draft: `dev_object` snapshot hashes change when only a comment in the compiler changes

> **Upstream or ours:** Upstream. It came with #12498 (`16a3cb76e5`). Reproduced on pure upstream `16a3cb76e5`.

> **Relevance to our arm32 work:** It blocks our sync. Three of our own `dev_object` snapshots (`float_math`, `many_args`, `list_ops`) fail minici's `run-test-zig-snapshot-tool` after every merge, because the hashes the chain takes from the oracle's pinned build never match a normal build.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, at `aa370e8626` (2026-10-23, by reading the code: the two commits after `16a3cb76e5` don't touch the files involved). |
| Already upstream? | No issue or PR found (searched 2026-10-23). |
| Fixed on our reference branch? | No. It is upstream code. |
| Before filing | Check `main` again. Decide whether to include the second program (`list_ops`), and check whether any of upstream's own `dev_object` snapshots has more than one procedure (not checked). |

---

**Title:** `dev_object` snapshot hashes depend on the compiler build when a program has more than one procedure

**What happens**

A `dev_object` snapshot of a program with more than one procedure gets a
different hash for every compiler build. Changing only a comment in a
compiler source file changes the hashes for every target. Within one build
the hash is stable from run to run.

The snapshot tool tries to prevent this. Before hashing, it replaces the
build-dependent hash in each procedure's symbol name with an ordinal
(`src/snapshot_tool/main.zig`, "Procedure symbol names digest the compiler
build; hash the object with them canonicalized so the pin tracks code
generation, not the compiler's git revision").

**Why**

Since #12498, `ObjectFileCompiler` lays the object out through
`ProcArtifact.canonicalize`. Its `canonicalBefore`
(`src/backend/dev/ProcArtifact.zig:1713-1727`) orders procedures by
`identity.bytes`, and those bytes digest the compiler build. So the order of
the procedures in the object changes with the build.

`ProcIdentity.canonicalizeSymbolNames` (`src/lir/LIR.zig:115-130`) numbers
the names in the order they appear in the object. That hides the names, but
not the order. The code bytes, offsets and relocations still follow the
build-dependent order.

A program with one procedure is not affected. With two procedures, a
different build gives the same order about half the time, so a snapshot can
pass for a while and then fail on an unrelated commit.

**How to reproduce**

Save this as `test/snapshots/dev_object_float_math.md` (a `dev_object`
snapshot with no `DEV OUTPUT` section yet; our run used the same file with
a `DEV OUTPUT` section already in it, so this exact file is untested):

````
# META
~~~ini
description=F32/F64 arithmetic, comparisons, and F64 to I64 conversion in host-called functions
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

main : F64, F32, I64 -> I64
main = |x, y, n| {
    scaled = x * 2.5 - I64.to_f64(n) / 3.0
    narrowed = F32.to_f64(y * 1.5 + 0.25)
    total = if scaled > narrowed { scaled - narrowed } else { narrowed + scaled }
    F64.to_i64_wrap(total)
}
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : F64, F32, I64 -> I64 }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }
~~~
````

Then:

```sh
git checkout 16a3cb76e5
zig build build-snapshot-tool
./zig-out/bin/snapshot --update-expected test/snapshots/dev_object_float_math.md
grep -E '^(x64|arm64)linux=' test/snapshots/dev_object_float_math.md

sed -i '1s|$| (comment only)|' src/base/mod.zig
zig build build-snapshot-tool
./zig-out/bin/snapshot --update-expected test/snapshots/dev_object_float_math.md
grep -E '^(x64|arm64)linux=' test/snapshots/dev_object_float_math.md
git checkout -- src/base/mod.zig
```

Output on 2026-10-23. First build:

```
x64linux=5e26bec1dd0d8bb9a6345896edff7c4988b28a8b31c8bfecf57d105762207f79
arm64linux=1c6777b1612d533c95ce267ca116a6b4c1d7a225bc7f82f8e7a378e84f131466
```

After the comment-only change:

```
x64linux=fce4dc52a5bebc4eba180e8b8077f3532e8246ab92dd2082eb231c5cb9bbd767
arm64linux=bc5e3494718d385e948c75feb2f75fef30780f80d8a5191d039e6923f82e69de
```

A list program with a closure (`List.map` over `List.append`, capturing two
locals) behaves the same way. `hello_world` (one procedure) does not change.

Running `--update-expected` twice with the same build gives the same hashes
both times, so the output is not random within one build.

**Possible directions** (untested)

- Order procedures by something that does not include the compiler build.
- Or have the snapshot tool undo the order too, not only the names.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream `main` at `16a3cb76e5`, Zig 0.17.0
- Debug build of the snapshot tool (`zig build build-snapshot-tool`)
