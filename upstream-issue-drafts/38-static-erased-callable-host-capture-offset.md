# Draft: erased-callable layouts measured with the compiler host's constants in static data and the wasm backend

> **Upstream or ours:** Upstream.

> **Relevance to our arm32 work:** Same family as draft 07 (32-bit host readiness): the compiler measures target memory with its own word size. Found while folding draft 07's fixes into fork PR #9 (step 5 of the fold), where the dev backend gets a target-scaled `erased_layout`. Static data serves every target, arm32 included. As far as we can tell it changes nothing today; see "Why it seems latent".

Not filed. New, for the owner to decide.

| | |
|---|---|
| Still an issue? | Yes at upstream `98dcdbfb2f` (2026-10-24), by reading the code. Nothing was run. |
| Already upstream? | None found. Searched upstream issues and PRs for "capture_offset", "capture_offset static_data" and "static data erased" on 2026-10-24. |
| Fixed on our reference branch? | No. `src/static_data.zig:1404` there is the same line, and its `WasmCodeGen.zig` has the same 5 uses of `builtins.erased_callable.capture_offset`. |
| Before filing | Check whether any wasm32 runtime code works out the metadata offset itself (see "Why it seems latent"). If one does, this is a live wasm32 bug, not a latent one, and needs a test. |

---

**Title:** erased-callable layouts are measured with the compiler host's constants in static data and the wasm backend

**Plain-language summary**

An erased callable is Roc's runtime form of a function value: a small heap block holding a pointer to the code, a pointer to a cleanup function, then the captured values, then a small trailer of compiler metadata. The compiler writes these blocks and the target's runtime reads them, so the compiler must use the target's sizes. In two places it uses the constants from `builtins.erased_callable` instead. Those are compiled into the compiler, so they describe the machine running the compiler, not the target.

**Where**

Static data, when a value is frozen into the program (`src/static_data.zig`):

- line 1404: `const capture_offset: u32 = builtins.erased_callable.capture_offset + prefix;`
- line 1407: `builtins.erased_callable.payloadSize(prefix + capture_size)` for the allocation size

The same function already uses the target's word for the cleanup pointer (`.offset = self.word_size`, line 1425), so one block mixes target and host measurements.

The wasm code generator (`src/backend/wasm/WasmCodeGen.zig`), where the target is wasm32 (4-byte words) and the compiler usually runs on a 64-bit machine:

- lines 2790, 8783, 9064, 9067: `builtins.erased_callable.capture_offset`
- lines 7019, 9003: `builtins.erased_callable.compilerMetadataOffset(...)`
- line 9077: `capture_offset + metadata_offset + @offsetOf(builtins.erased_callable.CompilerMetadata, "result_desc")`

It also hard-codes the cleanup pointer's offset as 4 (`wasm_erased_callable_on_drop_offset`, line 178), the wasm32 value, so it too mixes the two.

**Why it seems latent**

- `capture_offset` is `alignForward(@sizeOf(Payload), capture_alignment)`. `Payload` is two pointers (16 bytes on a 64-bit machine, 8 on a 32-bit one), and `capture_alignment` is 16, so `capture_offset` is 16 everywhere. It is right today because of the rounding, not by design. If `Payload` gains a third pointer, it becomes 32 on a 64-bit host but 16 on wasm32, and captures land where the runtime doesn't look.
- `compilerMetadataOffset` rounds the capture size up to the host's pointer alignment (8) instead of wasm32's (4). For a 4-byte capture the compiler puts the metadata at offset 8, where wasm32 would put it at 4. This looks harmless only because the compiler both chooses the offset and registers it with the runtime (`emitErasedProcRegistration`, line 7019), so both sides use the same number. We have not checked whether any wasm32 runtime code computes the offset itself.

**Possible fix** (untested)

Derive the layout from the target word, the way `capture_offset` is built but scaled: `@sizeOf(Payload) / @sizeOf(usize) * word_size`, rounded up to `capture_alignment`, and likewise for the metadata alignment and size. Better, give static data, the wasm backend and the dev backend one shared target-scaled description of the erased-callable layout, so they can't drift apart.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream `main` at `98dcdbfb2f`, Zig 0.17.0
