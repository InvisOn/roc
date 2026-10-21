# Draft: Dev backend: `list_get_unsafe` quietly cuts an i128 or Dec index down to 64 bits

> **Upstream or ours:** Upstream. The bug is in upstream's code and has nothing to do with our arm32 work.

> **Relevance to our arm32 work:** None in particular. We found it while reading the backend for word-size assumptions. Our reference branch leaves it as it is.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-21, upstream `main` at `534956997e`). The test below fails there, as expected. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | No. |
| Before filing | Ready. |

---

**Title:** Dev backend: `list_get_unsafe` quietly cuts an i128 or Dec index down to 64 bits

**What happens**

`list_get_unsafe` takes a list and an index. If the index is an i128 or Dec value, the dev backend loads its low 64 bits and carries on. An index of that type can only come from a bug in an earlier compiler stage. The backend hides that bug instead of reporting it. AGENTS.md forbids this kind of recovery in the backend.

**Where** (upstream `main` at `534956997e`)

- `src/backend/dev/LirCodeGen.zig:2230-2233`, in `generateLowLevel` (line 1852). When the index is on the stack as an i128 (`.stack_i128`), it loads the low 64 bits. The comment says "Dec/i128 index - just load the low 64 bits as U64".
- `LirCodeGen.zig:2234-2238`. An i128 constant (`.immediate_i128`) is cut to 64 bits the same way.

**Why it matters**

An index of the wrong type means an earlier stage produced wrong LIR. Cutting it down and carrying on hides that bug, and the program reads the wrong element. Failing loudly would point straight at the stage that made the mistake.

**How to reproduce**

No Roc program is known to produce such an index. A test that builds the LIR by hand should show it (append it to `src/backend/dev/LirCodeGen.zig`). It makes the list `[10, 20, 30]` and reads it at index 2^64 + 1. The backend keeps only the low 64 bits, which is 1, and returns 20.

```zig
test "list_get_unsafe does not read through a truncated i128 index" {
    if (comptime builtin.cpu.arch != .x86_64 and builtin.cpu.arch != .aarch64) {
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;
    var store = LirStore.init(allocator);
    defer store.deinit();
    var test_state = try TestLayoutState.init(allocator);
    defer test_state.deinit();

    const list_layout = try test_state.layout_store.insertLayout(layout.Layout.list(.u64));
    const elems = [_]i64{ 10, 20, 30 };
    var elem_locals: [elems.len]LocalId = undefined;
    for (&elem_locals) |*local| local.* = try addLocal(&store, .u64);
    const list = try addLocal(&store, list_layout);
    const index = try addLocal(&store, .i128);
    const result = try addLocal(&store, .u64);

    const ret = try store.addCFStmt(.{ .ret = .{ .value = result } }, .test_fixture);
    const drop_list = try store.addCFStmt(.{ .decref = .{
        .value = list,
        .rc = try store.addRcHelperRef(LIR.RcHelper.fromConcrete(.{ .op = .decref, .layout_idx = list_layout })),
        .next = ret,
    } }, .test_fixture);
    const get = try store.addCFStmt(.{ .assign_low_level = .{
        .target = result,
        .op = .list_get_unsafe,
        .rc_effect = try store.addRcEffect(lir.LowLevel.list_get_unsafe.rcEffect()),
        .args = try store.addLocalSpan(&.{ list, index }),
        .next = drop_list,
    } }, .test_fixture);
    // 2^64 + 1: no list has that many elements.
    const index_stmt = try store.addCFStmt(.{ .assign_literal = .{
        .target = index,
        .value = .{ .i128_literal = try store.addStmtRow(LIR.I128Literal, .{ .value = (1 << 64) + 1, .layout_idx = .i128 }) },
        .next = get,
    } }, .test_fixture);
    var current = try store.addCFStmt(.{ .assign_list = .{
        .target = list,
        .elems = try store.addLocalSpan(&elem_locals),
        .next = index_stmt,
    } }, .test_fixture);
    var i: usize = elems.len;
    while (i > 0) {
        i -= 1;
        current = try store.addCFStmt(.{ .assign_literal = .{
            .target = elem_locals[i],
            .value = .{ .i64_literal = .{ .value = elems[i], .layout_idx = .u64 } },
            .next = current,
        } }, .test_fixture);
    }
    const root_proc = try addNoArgProc(&store, current, .u64);

    // Fails: the backend keeps the low 64 bits of the index (1) and returns
    // element 1, which is 20, instead of rejecting an index of the wrong type.
    try std.testing.expect(try runRootU64(&store, &test_state.layout_store, root_proc, .u64) != 20);
}
```

Run it with:

```sh
zig build run-test-zig-module-backend -- --test-filter "list_get_unsafe does not read through a truncated i128 index"
```

Output at `534956997e`. The test fails because the backend returned 20:

```
run-test-zig-module-backend
+- run test backend 0 pass, 1 fail (1 total)
error: 'dev.LirCodeGen.test.list_get_unsafe does not read through a truncated i128 index' failed:
       Cannot print stack trace: stack tracing is disabled
Build Summary: 15/17 steps succeeded (1 failed); 0/1 tests passed (1 failed)
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream `main` at `534956997e`, Zig 0.17.0
