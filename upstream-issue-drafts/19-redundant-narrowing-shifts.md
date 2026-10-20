# Draft: Dev backend: extra shifts before storing a single byte

> **Upstream or ours:** Upstream. It has nothing to do with our arm32 work.

> **Relevance to our arm32 work:** None in particular. We noticed it while reading the backend.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, upstream `main` at `5fc587cf51`, by reading the code). |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | No. |
| Before filing | Low value. Consider not filing. |

---

**Title:** Dev backend: extra shifts before storing a single byte

**What happens**

Before storing a `U8` or `I8` result, the backend shifts the register left by 56 bits and back again to clear the upper bits. Then it stores only the lowest byte, so the upper bits never matter. The two shifts do nothing useful. Nothing goes wrong; it is only wasted work.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/LirCodeGen.zig:16783-16800`, the `.u8` and `.i8` cases of `storeResultToSavedPtr` (line 16769). Each shifts left by 56 and then right by 56 (lines 16788-16789 and 16797-16798), and then `emitStoreScalarToPtr(..., 1)` stores one byte (lines 16790 and 16799).

**How to reproduce**

By reading the code:

```sh
grep -n -A40 'fn storeResultToSavedPtr' src/backend/dev/LirCodeGen.zig
```

In the `.u8` and `.i8` cases, two shifts come before a store that writes only the lowest byte.

**The fix**

Delete the shifts and the comments that explain them. Keep the load and the store.

| Lines | What |
|---|---|
| 16784-16786 | `U8` comment about the shifts |
| 16788-16789 | `U8` shifts |
| 16793-16795 | `I8` comment about the shifts |
| 16797-16798 | `I8` shifts |

After the cut, both cases are the same as the `.i16, .u16` and `.i32, .u32` cases just above them (lines 16775-16782), which already store without shifting:

```zig
.u8, .i8 => {
    const reg = try self.ensureInGeneralReg(loc);
    try self.emitStoreScalarToPtr(saved_ptr_reg, reg, 1);
},
```

**Tests**

- `U8`: the existing test "generate bit-count ops (popcount/clz/ctz)" (`LirCodeGen.zig:25382`) returns `U8` results through this code, by way of `runRootU8(..., .u8)` (line 25479), `generateCode` and `storeResultToSavedPtr` (line 1627).
- `I8`: no existing unit test returns an `I8` this way. This one does. Append it to `src/backend/dev/LirCodeGen.zig`. It should pass both before and after the fix.

```zig
test "dev stores an I8 result as its own byte" {
    if (comptime builtin.cpu.arch != .x86_64 and builtin.cpu.arch != .aarch64) {
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;
    var store = LirStore.init(allocator);
    defer store.deinit();
    var test_state = try TestLayoutState.init(allocator);
    defer test_state.deinit();

    // -10 is loaded sign-extended, so the register's upper bits are all ones.
    // Only the lowest byte, 0xF6, may reach the result.
    const values = [_]i64{ -10, -128, 127, -1, 0 };
    for (values) |value| {
        const proc = try addLiteralProc(&store, .{ .i64_literal = .{ .value = value, .layout_idx = .i8 } }, .i8);
        const expected: u8 = @bitCast(@as(i8, @intCast(value)));
        try std.testing.expectEqual(expected, try runRootU8(&store, &test_state.layout_store, proc, .i8));
    }
}
```

Run both tests before and after the fix. Both should pass each time. (Not run yet.)

```sh
zig build run-test-zig-module-backend -- \
  --test-filter "generate bit-count ops" \
  --test-filter "dev stores an I8 result as its own byte"
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
