# Draft: `abs64` relocation patching is sized by the compiler's host word

> **Upstream or ours:** Upstream code, but it only matters when the compiler itself runs on a 32-bit host. So far only our arm32 work does that.

> **Relevance to our arm32 work:** It matters for a compiler running on arm32. Not fixed on upstream's path.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `patchAbsolutePointerOperand` in `src/backend/dev/Relocation.zig` still branches on `@sizeOf(usize)`. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us on upstream's path. |
| Before filing | Nothing. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** `abs64` relocation patching is sized by the compiler's host word

**What happens**

`patchAbsolutePointerOperand` writes 8 bytes when the compiler runs on a 64-bit host and 4 bytes on a 32-bit host. The width should come from the relocation kind (the target), not from the machine the compiler runs on. Latent today: it only matters for a compiler running on a 32-bit host.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/Relocation.zig:329-345`, `patchAbsolutePointerOperand`: writes 8 bytes if `@sizeOf(usize) == 8` (line 330), 4 bytes if `@sizeOf(usize) == 4` (line 336).

**Why it matters**

Today only a compiler running on a 32-bit host is affected, which means only arm32 work. There, an 8-byte absolute relocation would be patched with 4 bytes and half the address left unwritten, with nothing checking for it. It is the same habit as sizing target data by the host's word.

**How to reproduce**

It needs a compiler running on a 32-bit host, so this is seen by reading the code:

```sh
grep -n -A12 'fn patchAbsolutePointerOperand' src/backend/dev/Relocation.zig
```

The width written comes from `@sizeOf(usize)`.

**A test that fails on a 32-bit host** (run on upstream `main` at `5fc587cf51`, Zig 0.17.0). Append to `src/backend/dev/Relocation.zig`:

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
    // Fails when the compiler runs on a 32-bit host: only 4 bytes are
    // written and code[8..12] keeps 0xAA.
    try std.testing.expectEqual(@as(u64, 0x11223344), std.mem.readInt(u64, code[4..12], .little));
}
```

```sh
printf 'test {\n    _ = @import("backend/dev/Relocation.zig");\n}\n' > src/probe_relocation.zig
zig test src/probe_relocation.zig --test-filter "abs64 data relocation writes all eight"                        # x86_64: passes
zig test src/probe_relocation.zig --test-filter "abs64 data relocation writes all eight" -target x86-linux-musl  # 32-bit x86: fails
```

The 32-bit run (it runs directly on an x86_64 Linux machine) ends with `1 passed; 0 skipped; 1 failed.` at the `expectEqual`.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
