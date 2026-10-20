# Draft: A loaded LIR image has no recursive-graph keys in its layout store

> **Upstream or ours:** Upstream. Nothing upstream hits it today, because no code passes a loaded image on to object-file generation. We hit it while building a test oracle.

> **Relevance to our arm32 work:** We hit it while building the test oracle that hashes the machine code of every eval case. We took a different route and left it alone.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, upstream `main` at `5fc587cf51`, by reading the code). The test below is not run yet. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | No. We avoid that path. |
| Before filing | Run the test below and add its output. |

---

**Title:** A loaded LIR image has no recursive-graph keys in its layout store

**What happens**

When a LIR image is loaded, its layout store gets an empty `interned_recursive_graphs` map. The original store had one entry per recursive layout. Computing a layout digest needs those entries. So the first recursive type in a loaded image hits the invariant "cyclic layout has no recursive-graph key". Object-file generation digests layouts, so any code that loads an image and then generates an object file would hit it.

**Where** (upstream `main` at `5fc587cf51`)

- `src/lir/lir_image.zig:388` and `:734`. `interned_recursive_graphs` is created empty (`RecursiveGraphMap.init`) when an image is viewed and when it is cloned.
- `src/layout/digest.zig:108`, in `Digests.get` (line 85): `base.invariant("layout digest: cyclic layout {d} has no recursive-graph key", ...)`. In a release build this is `unreachable`.

**Why it matters**

Nothing upstream reaches this yet. It is a trap for future work. Anything that loads a LIR image and then generates object code, such as a cache or parallel code generation, will fail on the first program with a recursive type. The failure will show up far from its cause.

**How to reproduce**

No upstream code path reaches it today. Reading the code shows it:

```sh
grep -n interned_recursive_graphs src/lir/lir_image.zig     # created empty when loaded
grep -rn 'has no recursive-graph key' src/layout             # the invariant it leads to
```

A test that should fail (not run yet; append it to `src/lir/lir_image.zig`). It builds the recursive layout `Node := [Nil, Cons(Box(Node))]`, takes its digest, copies the program into an image, loads the image back, and asks for the same digest. In a Debug build the second digest should hit the invariant at `layout/digest.zig:108`.

```zig
test "a viewed LIR image digests a recursive layout" {
    const allocator = std.testing.allocator;
    var program = try Program.Result.init(allocator, .u64);
    defer program.deinit();

    // `Node := [Nil, Cons(Box(Node))]`, as in layout/digest.zig's tests.
    var graph = layout_mod.Graph{};
    defer graph.deinit(allocator);
    const union_node = try graph.reserveNode(allocator);
    const box_node = try graph.reserveNode(allocator);
    graph.setNode(box_node, .{ .box = .{ .local = union_node } });
    graph.setNode(union_node, .{ .tag_union = try graph.appendRefs(allocator, &[_]layout_mod.GraphRef{ .{ .canonical = .zst }, .{ .local = box_node } }) });
    var commit = try program.layouts.commitGraph(&graph, .{ .local = union_node });
    defer commit.deinit(allocator);
    const root = commit.root_idx;
    const expected = try program.layouts.contentDigest(root); // works: the original store has the key

    const memory = try allocator.alignedAlloc(u8, .@"16", 1 << 16);
    defer allocator.free(memory);
    var fixed = std.heap.FixedBufferAllocator.init(memory);
    const header = try fixed.allocator().create(Header);
    const copied = try copyProgramWithStaticDataIntoBuffer(fixed.allocator(), memory.ptr, memory.len, .mapped, &program, &.{}, &.{});
    try copied.fillHeader(header, fixed.end_index);
    var view = try viewMappedImageWithAllocator(header, memory.ptr, fixed.end_index, .u64, allocator);
    defer view.deinit();

    // The loaded store's `interned_recursive_graphs` is empty (line 388), so
    // this hits "cyclic layout ... has no recursive-graph key".
    try std.testing.expectEqualSlices(u8, &expected, &(try view.layouts.contentDigest(root)));
}
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
