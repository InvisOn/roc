# Draft: the LLVM backend crashes building wasm32v1 code that passes a vector to a function

> **Upstream or ours:** Upstream.

> **Relevance to our arm32 work:** None directly: arm32 doesn't use this LLVM path for wasm. Found while testing fold step 5 (fork PR #9), when a CLI test run with `--include-llvm` failed the same way on upstream as on our branch.

Not filed. New, for the owner to decide.

| | |
|---|---|
| Still an issue? | Yes at upstream `414a19203e` (2026-10-23), by running the test. Upstream `main` (`98dcdbfb2f`) doesn't build (draft 37), but it changes nothing in the LLVM or wasm backends after `414a19203e`. Also fails at `3bb8f2ec6c`. |
| Already upstream? | None found. Searched issues and PRs for "register pieces", "scalar parameter split" and "wasm32v1 vector" on 2026-10-24. |
| Fixed on our reference branch? | No. It has the same `max_scalar_pieces = 2` and the same check (`MonoLlvmCodeGen.zig:13870` and `13884` there), and the same test. |
| Before filing | Recheck on current `main` once it builds again (PR 12557). |

---

**Title:** LLVM backend: "scalar parameter split into 16 register pieces" building a wasm32v1 program that passes vectors

**What happens**

The CLI test "wasm32v1 builds lower vector code to WebAssembly 1.0 at every optimization level" (added in `cc998a9cf3`, 2026-10-18) fails. Building its app with the LLVM backend for wasm32v1 crashes the compiler:

```
roc build --target=wasm32v1 --opt=size --no-cache test/wasm/wasm32v1_vector_app.roc
```

```
thread panic: LLVM codegen invariant violated: scalar parameter split into 16 register pieces
src/backend/llvm/MonoLlvmCodeGen.zig:13884:64 in scalarFromCAbiParams
src/backend/llvm/MonoLlvmCodeGen.zig:2646:65 in unpackFastProcArgs
src/backend/llvm/MonoLlvmCodeGen.zig:2932:40 in compileProcBody
src/backend/llvm/MonoLlvmCodeGen.zig:1756:37 in compileAllProcSpecs
src/cli/main.zig:11192:48 in rocBuildWasmLlvm
```

The test builds wasm32 then wasm32v1, each at `dev`, `size` and `speed`. All three wasm32 builds and the wasm32v1 `dev` build pass. The wasm32v1 `size` build crashes, so `speed` is never reached.

To reproduce: `zig build run-test-cli -- --include-llvm --filter "wasm32v1 builds lower vector"`

**Why**

`scalarFromCAbiParams` assumes a register-passed parameter splits into at most `max_scalar_pieces = 2` pieces, "a 16-byte value in 8-byte pieces" (`MonoLlvmCodeGen.zig:13868-13870`). wasm32v1 is WebAssembly 1.0, which has no 128-bit vector type, so a 16-byte vector such as `U8x16` is passed as 16 one-byte pieces. The invariant then fires.

**Why CI doesn't catch it**

CI runs the LLVM CLI tests as `run-test-cli -- --include-llvm --filter "[size]" --filter "[speed]"` (`.github/workflows/ci_zig.yml:163`). This test's name contains neither `[size]` nor `[speed]`, so CI never runs it.

**Possible fix** (untested)

Size the pieces from the ABI placement instead of a fixed maximum of 2, or have wasm32v1's placement pass a 16-byte vector in memory rather than as 16 register pieces.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream at `414a19203e`, Zig 0.17.0
