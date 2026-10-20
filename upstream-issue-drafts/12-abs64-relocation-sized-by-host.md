# Draft: An `abs64` relocation writes 4 bytes when the compiler runs on a 32-bit machine

> **Upstream or ours:** Upstream's code. It only matters when the compiler itself runs on a 32-bit machine. So far only our arm32 work does that.

> **Relevance to our arm32 work:** It matters for a compiler running on arm32. Our reference branch does not change it.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, upstream `main` at `5fc587cf51`). The test below fails on 32-bit x86. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | No. |
| Before filing | Nothing. |

---

**Title:** An `abs64` relocation writes 4 bytes when the compiler runs on a 32-bit machine

**What happens**

`patchAbsolutePointerOperand` patches an absolute address into generated code. It decides how many bytes to write from the machine the compiler runs on: 8 bytes on a 64-bit machine and 4 bytes on a 32-bit one. The relocation is called `abs64`, so its operand is 8 bytes wide whatever machine the compiler runs on. The width should come from the relocation kind.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/Relocation.zig:329-345`, `patchAbsolutePointerOperand`. It writes 8 bytes when `@sizeOf(usize) == 8` (line 330) and 4 bytes when `@sizeOf(usize) == 4` (line 336).

**Why it matters**

Only a compiler running on a 32-bit machine is affected. There, an 8-byte operand gets only its low 4 bytes written. The other 4 bytes keep whatever they held before, and nothing checks for it.

**How to reproduce**

A test that passes on 64-bit x86 and fails on 32-bit x86 (run on upstream `main` at `5fc587cf51` with Zig 0.17.0). Append it to `src/backend/dev/Relocation.zig`:

```zig
test "an abs64 data relocation writes all eight bytes of its operand" {
    var code: [16]u8 = @splat(0xAA);
    const resolver: SymbolResolver = struct {
        fn resolve(name: []const u8) ?usize {
            return if (std.mem.eql(u8, name, "global_data")) 0x11223344 else null;
        }
    }.resolve;
    const relocs = [_]Relocation{.{ .linked_data = .{ .offset = 4, .name = "global_data", .kind = .abs64 } }};
    try applyRelocations(&code, 0, &relocs, resolver);
    // On a 32-bit machine only 4 bytes are written, and code[8..12] keeps 0xAA.
    try std.testing.expectEqual(@as(u64, 0x11223344), std.mem.readInt(u64, code[4..12], .little));
}
```

Run it through a small root file in `src/`. A 32-bit x86 test binary runs directly on x86_64 Linux.

```sh
printf 'test {\n    _ = @import("backend/dev/Relocation.zig");\n}\n' > src/probe_relocation.zig
zig test src/probe_relocation.zig --test-filter "abs64 data relocation writes all eight"                        # x86_64: passes
zig test src/probe_relocation.zig --test-filter "abs64 data relocation writes all eight" -target x86-linux-musl  # 32-bit x86: fails
```

The 32-bit run fails at the `expectEqual` and ends with `1 passed; 0 skipped; 1 failed.`

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
