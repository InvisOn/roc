# Draft: The glibc stub writes `ret` for architectures that have no `ret` instruction

> **Upstream or ours:** Upstream. Nothing upstream reaches it today, because the affected architectures don't use the stub. Our arm32 work would have reached it for `.arm`.

> **Relevance to our arm32 work:** `arm32linux` uses the glibc stub, and `ret` is not a 32-bit ARM instruction. Our reference branch gives arm its own stub body.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, upstream `main` at `5fc587cf51`). The test below fails. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | Yes, in `627b4b7248`, for arm only (`mov r0, #0` / `bx lr`). |
| Before filing | Nothing. |

---

**Title:** The glibc stub writes `ret` for architectures that have no `ret` instruction

**What happens**

The generated glibc stub gives every stub function the body `ret` on `.aarch64_be`, `.arm`, `.wasm32` and `.other`. 32-bit ARM has no `ret` instruction; it returns with `bx lr`. For wasm32, `ret` means nothing at all. Nothing upstream reaches this today, because those targets don't use the stub. If one did, the stub would fail to assemble or assemble into the wrong thing.

**Where** (upstream `main` at `5fc587cf51`)

- `src/build/glibc_stub.zig:24`, `:93` and `:100`, in `generateComprehensiveStub` (line 7). Each writes `"    ret\n\n"` for `.aarch64_be, .arm, .wasm32, .other`.
- `src/build/glibc_stub.zig:14` gives the same group a 4-byte pointer size.

**Why it matters**

Nobody upstream is affected now. It affected our arm32 work, which uses the stub. It would break any of the other architectures the moment they used the stub too.

**How to reproduce**

A test that fails (run on upstream `main` at `5fc587cf51`). Append it to `src/build/glibc_stub.zig`:

```zig
test "the 32-bit ARM glibc stub uses A32 returns" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try generateComprehensiveStub(&aw.writer, .arm);
    // `ret` is not an A32 instruction; the assembler rejects it ("invalid instruction").
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "    ret\n") == null);
}
```

The file imports `../target/mod.zig`, so run the test through a small root file in `src/`:

```sh
printf 'test {\n    _ = @import("build/glibc_stub.zig");\n}\n' > src/probe_glibc_stub.zig
zig test src/probe_glibc_stub.zig --test-filter "32-bit ARM glibc stub"
```

It fails at the `expect` (`src/build/glibc_stub.zig:156:5`) and ends with `2 passed; 0 skipped; 1 failed.` The assembler confirms that `ret` is not a 32-bit ARM instruction:

```
$ printf '.text\n.globl f\nf:\n    ret\n' > s.s && zig cc -target arm-linux-musleabihf -c s.s
s.s:4:5: error: invalid instruction, did you mean: rev?
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
