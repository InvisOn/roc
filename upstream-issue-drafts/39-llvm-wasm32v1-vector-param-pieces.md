# Draft: The LLVM backend crashes building wasm32v1 code that passes a vector to a function

> **Upstream or ours:** Upstream. It fails the same way on upstream as on our branch.

> **Relevance to our arm32 work:** None directly: arm32 doesn't use this LLVM path for wasm. Found while testing fold step 5 (fork PR #9), when a CLI test run with `--include-llvm` failed.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-25, upstream `main` at `cf42a741e8`, by running the CLI test below on pure upstream). Same panic, at the same lines. Also failed at `414a19203e` and `3bb8f2ec6c`. |
| Already upstream? | No issue or PR found (searched 2026-10-24 for "register pieces", "scalar parameter split" and "wasm32v1 vector"). |
| Fixed on our reference branch? | No. It has the same `max_scalar_pieces = 2` and the same check (`MonoLlvmCodeGen.zig:13870` and `13884` there), and the same test. |
| Before filing | Ready. Rechecked on current `main` (searched again 2026-10-25 for "register pieces" and "wasm32v1 vector": nothing). |

---

**Title:** LLVM backend: "scalar parameter split into 16 register pieces" building a wasm32v1 program that passes vectors

**What happens**

Building a program that passes a 16-byte vector such as `U8x16` between functions for wasm32v1 with the LLVM backend (`--opt=size` or `--opt=speed`) crashes the compiler:

```
thread panic: LLVM codegen invariant violated: scalar parameter split into 16 register pieces
src/backend/llvm/MonoLlvmCodeGen.zig:13884:64 in scalarFromCAbiParams
src/backend/llvm/MonoLlvmCodeGen.zig:2646:65 in unpackFastProcArgs
src/backend/llvm/MonoLlvmCodeGen.zig:2932:40 in compileProcBody
src/backend/llvm/MonoLlvmCodeGen.zig:1756:37 in compileAllProcSpecs
src/backend/llvm/MonoLlvmCodeGen.zig:1095:37 in buildEntrypointModule
src/backend/llvm/MonoLlvmCodeGen.zig:1052:39 in generateEntrypointModule
src/cli/main.zig:11035:61 in compileLlvmAppObject
```

The same app builds with `--opt=dev` for wasm32v1, and with `--opt=size` for wasm32.

**Where** (upstream at `cf42a741e8`)

- `src/backend/llvm/MonoLlvmCodeGen.zig:13868-13870`: `max_scalar_pieces = 2`, documented as "a 16-byte value in 8-byte pieces".
- `src/backend/llvm/MonoLlvmCodeGen.zig:13884`, `scalarFromCAbiParams`: the invariant that fires when a parameter's ABI placement has more pieces than that.

wasm32v1 is WebAssembly 1.0, which has no 128-bit vector type, so a 16-byte vector is passed as 16 one-byte pieces.

**Why it matters**

Any wasm32v1 program that passes vectors between functions can't be built with `--opt=size` or `--opt=speed`. The CLI test written for this, "wasm32v1 builds lower vector code to WebAssembly 1.0 at every optimization level" (added in `cc998a9cf3`, 2026-10-18), fails. CI never runs it: it runs the LLVM CLI tests as `run-test-cli -- --include-llvm --filter "[size]" --filter "[speed]"` (`.github/workflows/ci_zig.yml:163`), and this test's name contains neither `[size]` nor `[speed]`.

**How to reproduce**

Through the CLI test (run on upstream at `cf42a741e8` with Zig 0.17.0):

```sh
zig build run-test-cli -- --include-llvm --filter "wasm32v1 builds lower vector"
```

The test fails at the wasm32v1 `size` build with the panic above.

Directly, with `roc build`. These commands were run on our fork branch, whose changes don't touch the LLVM or wasm backends; the panic is the same as upstream's:

```sh
zig build update-test-fixtures
cp -r test/wasm/platform/targets test/wasm/static-lib-platform/targets
./zig-out/bin/roc build --target=wasm32v1 --opt=dev   --no-cache --output=/tmp/v_dev.wasm   test/wasm/wasm32v1_vector_app.roc  # builds
./zig-out/bin/roc build --target=wasm32v1 --opt=size  --no-cache --output=/tmp/v_size.wasm  test/wasm/wasm32v1_vector_app.roc  # panics, exit 134
./zig-out/bin/roc build --target=wasm32v1 --opt=speed --no-cache --output=/tmp/v_speed.wasm test/wasm/wasm32v1_vector_app.roc  # panics, exit 134
./zig-out/bin/roc build --target=wasm32   --opt=size  --no-cache --output=/tmp/v_w32.wasm   test/wasm/wasm32v1_vector_app.roc  # builds
rm -r test/wasm/static-lib-platform/targets
```

`update-test-fixtures` puts the wasm hosts in `test/wasm/platform/targets/`. The app's platform, `test/wasm/static-lib-platform`, normally gets a copy of them only inside the test runner's private tree, hence the `cp`.

**Possible fix** (untested)

Size the pieces from the ABI placement instead of a fixed maximum of 2, or have wasm32v1's placement pass a 16-byte vector in memory rather than as 16 register pieces.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream at `414a19203e` built from source (CLI test), and our fork branch on `3bb8f2ec6c` (direct commands), Zig 0.17.0
