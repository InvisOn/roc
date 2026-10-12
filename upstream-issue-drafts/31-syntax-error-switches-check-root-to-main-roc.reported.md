# Draft: A syntax error in an app makes `roc check` and the LSP build a nearby `main.roc` instead

> **FILED as roc-lang/roc#12179** on 2026-10-10: filed by the owner; open.

> **Upstream or ours:** Upstream. `src/compile/compile_build.zig` (`peekPackageKind`, `discoverResolvingMain`) is unchanged on our branch; reproduced with `roc check` built from our branch at `2ceea232c4` (its `src/compile` differs from upstream only by one error name in `coordinator.zig`). The code is the same at upstream `faecf66d88`.

> **Relevance to our arm32 work:** None to arm32. Found while confirming draft 29: it is why that LSP test depends on `/tmp`.

Filed as roc-lang/roc#12179 on 2026-10-10.

| | |
|---|---|
| Still an issue? | Yes, 2026-10-10 (`roc check`, built from our branch; same code at upstream `faecf66d88`). |
| Already upstream? | **Filed as #12179** (2026-10-10). Before filing: None found (2026-10-10: searched issues and PRs for peekPackageKind, findOwningMainRoc, owning main.roc, and `roc check` reporting errors from main.roc). Related but different: #10161 and its fix #10166, which added the walk to an owning `main.roc` for child modules. |
| Fix on our reference branch | None (upstream code; not ours to fix). |
| Before filing | Nothing. File together with draft 29 or mention it there. |

---

**Title:** A syntax error in an app file makes `roc check` and the LSP check a nearby `main.roc` instead, hiding the file's own errors

**What happens**

`roc check` (and the LSP, which builds the same way) decides what to build with `BuildEnv.discoverResolvingMain`. A file that carries its own packages (an app, default app, package or platform) is built from its own header. Any other file is treated as a child module: the build walks up from its directory to the nearest `main.roc` and builds that package, with the file as the entry module.

To tell the two apart it calls `peekPackageKind`, which parses the whole file and returns null when there is any tokenize or parse diagnostic anywhere in it (`compile_build.zig`, `if (ast.tokenize_diagnostics.items.len > 0 or ast.parse_diagnostics.items.len > 0) return null;`). So an app with a syntax error in its body, which is the normal state of a file while it is being edited, is treated as a child module. If any ancestor directory up to `/` holds a `main.roc`, that file's package is built instead.

When that `main.roc` itself has a syntax error, its error is the only one reported, under the checked file's name, and all of the checked file's own errors disappear:

```
$ roc check other.roc        # main.roc is beside it
── ✗ unclosed string ──────────────── main.roc:2:9
...
── 1 error and 0 warnings ─────────── other.roc
```

Without the `main.roc`, the same command reports `other.roc`'s six errors. A valid app beside the same broken `main.roc` checks cleanly (its header is read, so no walk happens), which shows the switch is caused by the checked file's own syntax error.

In the LSP the same switch makes a neighbouring `main.roc`'s diagnostics come first (or alone) for the document being edited; the LSP integration test "parse errors are reported as diagnostics" fails for this reason when `/tmp/main.roc` exists (draft 29).

**How to reproduce**

With any `roc` built from upstream `main`:

```sh
mkdir -p /tmp/roc-root-switch && cd /tmp/roc-root-switch
printf 'main! = |_args| {\n    x = "unclosed in main\n    Ok({})\n}\n' > main.roc
printf 'main! = |_args| {\n    echo!("hello world\n    Ok({})\n}\n' > other.roc
printf 'main! = |_args| {\n    echo!("hello world")\n    Ok({})\n}\n' > fixed.roc

roc check other.roc   # reports only main.roc:2:9; other.roc's errors are missing
roc check fixed.roc   # "No errors found": a valid app ignores main.roc
mv main.roc main.off
roc check other.roc   # now reports other.roc's six errors
```

**Expected**

The kind of the checked file comes from its header, which parses fine here; a syntax error later in the file does not turn an app into a child module. `roc check other.roc` reports `other.roc`'s errors whether or not a `main.roc` exists nearby.

**Where**

`src/compile/compile_build.zig`: `peekPackageKind` (returns null on any parse diagnostic) and `discoverResolvingMain` (treats null like a child module and calls `findOwningMainRoc`, which walks every ancestor directory).

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler: built from source; code identical at upstream `faecf66d88`
