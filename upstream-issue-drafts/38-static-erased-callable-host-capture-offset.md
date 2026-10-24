# Draft: Erased-callable layouts are measured with the compiler machine's constants in static data and the wasm backend

> **Upstream or ours:** Upstream's code. It gives the right answer today, so nothing fails yet; see "Why it matters".

> **Relevance to our arm32 work:** Same family as draft 07 (32-bit host readiness): the compiler measures target memory with its own word size. Static data serves every target, arm32 included. Found while folding draft 07's fixes into fork PR #9 (fold step 5), where the dev backend gets a target-scaled `erased_layout`.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-24, upstream `main` at `98dcdbfb2f`, by reading the code). |
| Already upstream? | No issue or PR found (searched 2026-10-24 for "capture_offset", "capture_offset static_data" and "static data erased"). |
| Fixed on our reference branch? | No. `src/static_data.zig:1404` there is the same line, and its `WasmCodeGen.zig` has the same 5 uses of `builtins.erased_callable.capture_offset`. |
| Before filing | Check whether any wasm32 runtime code works out the compiler-metadata offset itself (see "Why it matters"). If one does, this is a live wasm32 bug and needs a test. |

---

**Title:** Erased-callable layouts are measured with the compiler machine's constants in static data and the wasm backend

**What happens**

An erased callable is Roc's runtime form of a function value: a small heap block holding a pointer to the code, a pointer to a cleanup function, then the captured values, then a small trailer of compiler metadata. The compiler writes these blocks and the target's runtime reads them, so the compiler must use the target's sizes. In two places it uses the constants from `builtins.erased_callable` instead. Those are compiled into the compiler, so they describe the machine running the compiler, not the target.

**Where** (upstream `main` at `98dcdbfb2f`)

Static data, when a value is frozen into the program:

- `src/static_data.zig:1404`: `const capture_offset: u32 = builtins.erased_callable.capture_offset + prefix;`
- `src/static_data.zig:1407`: `builtins.erased_callable.payloadSize(prefix + capture_size)` sizes the allocation.
- The same function already uses the target's word for the cleanup pointer (`.offset = self.word_size`, line 1425), so one block mixes target and host measurements.

The wasm code generator, whose target is wasm32 (4-byte words) while the compiler usually runs on a 64-bit machine:

- `src/backend/wasm/WasmCodeGen.zig:2790, 8783, 9064, 9067`: `builtins.erased_callable.capture_offset`
- `src/backend/wasm/WasmCodeGen.zig:7019, 9003`: `builtins.erased_callable.compilerMetadataOffset(...)`
- `src/backend/wasm/WasmCodeGen.zig:9077`: `capture_offset + metadata_offset + @offsetOf(builtins.erased_callable.CompilerMetadata, "result_desc")`
- It hard-codes the cleanup pointer's offset as 4 (`wasm_erased_callable_on_drop_offset`, line 178), the wasm32 value, so it too mixes the two.

**Why it matters**

Nothing fails today, for two reasons that are luck rather than design:

- `capture_offset` is `alignForward(@sizeOf(Payload), capture_alignment)`. `Payload` is two pointers (16 bytes on a 64-bit machine, 8 on a 32-bit one), and `capture_alignment` is 16, so `capture_offset` is 16 everywhere. If `Payload` gains a third pointer, it becomes 32 on a 64-bit compiler but 16 on wasm32, and captures land where the runtime doesn't look.
- `compilerMetadataOffset` rounds the capture size up to the compiler machine's pointer alignment (8) instead of wasm32's (4). For a 4-byte capture the compiler puts the metadata at offset 8, where wasm32 would put it at 4. Both sides agree only because the compiler chooses the offset and also registers it with the runtime (`emitErasedProcRegistration`, line 7019). We have not checked whether any wasm32 runtime code computes the offset itself.

**How to reproduce**

Nothing fails today, so there is no failing run. The host-measured constants show up when reading the code:

```sh
grep -n 'builtins.erased_callable\.' src/static_data.zig
grep -n 'builtins.erased_callable\.\(capture_offset\|compilerMetadataOffset\)\|wasm_erased_callable_on_drop_offset: u32' src/backend/wasm/WasmCodeGen.zig
grep -n 'pub const capture_offset\|pub const capture_alignment\|pub const compiler_metadata_alignment\|pub const Payload' src/builtins/erased_callable.zig
```

The first lists lines 1404 and 1407 (it also prints 1408 and 1409, `payload_alignment` and `allocation_has_refcounted_children`, which are the same on every target). The second lists the wasm sites above. The third shows that `capture_offset` and the metadata alignment come from `@sizeOf` and `@alignOf` on the compiler's own structs.

**Possible fix** (untested)

Derive the layout from the target word: `@sizeOf(Payload) / @sizeOf(usize) * word_size`, rounded up to `capture_alignment`, and likewise for the metadata alignment and size. Better, give static data, the wasm backend and the dev backend one shared target-scaled description of the erased-callable layout, so they can't drift apart.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream `main` at `98dcdbfb2f`, Zig 0.17.0
